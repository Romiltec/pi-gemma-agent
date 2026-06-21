# bench — the ladder benchmark

A model builds a project **as a ladder of tiny verified steps**. A generic runner drives any
agent up any ladder, with an outer **retry + feedback** loop; pluggable **judges** make it
domain-agnostic.

## Run

```bash
cd bench && npm install && cd ..        # Playwright, for browser-based judges (arcade)
bench/runner.sh <ladder-dir> [agent] [K]
```

- `<ladder-dir>`: e.g. `bench/ladders/arcade` or `bench/ladders/minilib`
- `agent`: `pi-anthropic` (default) or `pi`
- `K`: max attempts per rung (default 5)

Env: `BENCH_CAP_SECS` (per-attempt time cap), `PI_GEMMA_MODEL`, `PI_GEMMA_THINKING`.
Work/sandboxes and the raw CSV land in `bench/.work/<ladder>/` (git-ignored).

## How a rung works

For each rung: start from the last green `target`, hand the agent **one small step** plus the
ladder `context`, let it edit + run `./check.sh <target> <rung>`. If the judge fails, its exact
output is fed back and the agent retries (up to `K`). On success the green advances; otherwise
the climb stops and the reached rung is recorded.

## Ladders included

- **`arcade`** — a faithful Snake + Arkanoid in one `game.html`, judged with Playwright on
  **rendering during play + physics** (grid-stepped snake, ball bounces with velocity
  inversion, game over, restart). 9 rungs.
- **`minilib`** — a CommonJS utility module built function-by-function, judged by Node
  assertions (no browser). 7 rungs. Shows the method isn't game-specific.

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
