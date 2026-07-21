# bench — the ladder benchmark

A model builds a project **as a ladder of tiny verified steps**. A generic runner drives any
agent up any ladder, with an outer **retry + feedback** loop; pluggable **judges** make it
domain-agnostic.

## Prerequisites

```bash
cd bench && npm install && cd ..        # Playwright (for browser-based judges)
```

## Run

```bash
bench/runner.sh <ladder-dir> [agent] [K]
```

- `<ladder-dir>`: e.g. `bench/ladders/arcade` or `bench/ladders/minilib`
- `agent`: label for the CSV report (e.g. `pi-anthropic`, `starbuck`, `qwen-openai`)
- `K`: max attempts per rung (default 5)

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `PI_GEMMA_MODEL` | `gemma-4-12b-it` | Model ID to use |
| `PI_GEMMA_PROVIDER` | `vllm-anthropic` | Provider name (determined by agent arg: `pi-anthropic` → `vllm-anthropic`, `pi` → `vllm`, otherwise uses env) |
| `PI_GEMMA_THINKING` | `high` | Thinking level |
| `PI_GEMMA_METHOD` | `setup/method.md` | Path to method system prompt |
| `BENCH_CAP_SECS` | `220` | Per-attempt time cap (seconds) |

### Examples

```bash
# Default (Gemma via Anthropic channel):
bench/runner.sh bench/ladders/cli     pi-anthropic 3
bench/runner.sh bench/ladders/minilib pi-anthropic 3
bench/runner.sh bench/ladders/arcade  pi-anthropic 5

# Qwen via starbuck provider:
PI_GEMMA_MODEL=qwen3.6-27b PI_GEMMA_PROVIDER=starbuck bench/runner.sh bench/ladders/cli starbuck 5

# One-shot (no scaffold, raw capability):
bench/oneshot.sh bench/ladders/arcade 3
```

Work/sandboxes and the raw CSV land in `bench/.work/<ladder>/` (git-ignored).

## How a rung works

For each rung: start from the last green `target`, hand the agent **one small step** plus the
ladder `context`, let it edit + run `./check.sh <target> <rung>`. If the judge fails, its exact
output is fed back and the agent retries (up to `K`). On success the green advances; otherwise
the climb stops and the reached rung is recorded.

## One-shot (hard mode)

`runner.sh` measures capability **with** the scaffold (small steps + feedback). To measure **raw**
capability, `oneshot.sh` gives the model the whole target in a single prompt — no steps, no retries —
and scores the best contiguous rung the single output passes:

```bash
bench/oneshot.sh bench/ladders/arcade 3            # default model
PI_GEMMA_MODEL=qwen3.6-27b PI_GEMMA_PROVIDER=starbuck bench/oneshot.sh bench/ladders/arcade 3
```

Same env variables as `runner.sh` (`PI_GEMMA_MODEL`, `PI_GEMMA_PROVIDER`, `PI_GEMMA_THINKING`,
`PI_GEMMA_METHOD`, `BENCH_CAP_SECS`).

Two things make it a *fair* one-shot test (learned the hard way — see below):

1. **Coherent spec, not incremental prompts.** The per-rung prompts are written for laddering
   ("Add ONLY the menu, no gameplay yet", "keep the others working"). Concatenated into one
   "build everything" prompt they *contradict* each other and tank the result. `oneshot.sh`
   passes the full requirements but explicitly neutralizes the incremental wording.
2. **Write-guard.** Some models describe the code in prose/markdown instead of calling the write
   tool; the target then never changes and every rung fails (a false `R0`). `oneshot.sh` (and now
   `runner.sh`) detect "file not modified" and warn, so a *narrated-but-not-written* answer is not
   mistaken for real output.

Caveat: one-shot is single-sample and **high variance** — the same model/task can swing several
rungs on prompt phrasing or sampling luck. Use `N>1` (best-of) and a low temperature, and treat
one-shot as a **diagnostic** ("does the task need the scaffold?"), not a fine-grained ranking.
Scaffold mode (`runner.sh`) is the reliable comparison metric.

## Ladders included

Five ladders across domains (judge type in brackets):

- **`arcade`** [Playwright] — a faithful Snake + Arkanoid in one `game.html`, judged on
  **rendering during play + physics** (grid-stepped snake, ball bounces with velocity
  inversion, game over, restart). 9 rungs.
- **`minilib`** [Node] — a CommonJS utility module built function-by-function, judged by Node
  assertions. 7 rungs.
- **`cli`** [Node] — a CLI calculator (`cli.cjs`), judged by running it as a subprocess and
  checking stdout/exit codes. 5 rungs.
- **`api`** [Node] — a zero-dependency HTTP API (`server.cjs`), judged by booting it on a
  random port and querying its routes. 4 rungs.
- **`todo`** [Playwright] — a To-Do web app (`todo.html`), judged on DOM + `window.__todo`
  state (add / toggle / remove / counter). 5 rungs.

The mix (CLI, backend HTTP, browser app, browser game, pure library) shows the laddered
small-steps method is domain-independent, not game-specific.

## Add a ladder

Create `bench/ladders/<name>/`:

```
ladder.json   { "name","target","seed","context","check"?,"rungs":[{ "id","title","prompt" }] }
check.mjs     # or check.cjs — node check <target-file> <rung> [--json], exit 0 = rung passed
seed/<file>   # the starting target
```

- `target` is the file the agent edits (e.g. `game.html`, `lib.js`).
- `context` is prepended to every rung prompt (API/contract/controls and the "replicate the
  working structure" guidance).
- The judge prints `PASS/FAIL` lines and a final `rung N: PASS|FAIL`, and supports `--json`
  (`{ rung, rungPass, score, ... }`). Validate it against a hand-written reference that passes
  every rung before trusting the numbers.
