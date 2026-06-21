# pi-gemma-agent

**Turn a small local model into a capable coding agent — and prove it.**

This repo packages a working setup and a reproducible benchmark showing that a free,
locally-served **Gemma 4 12B** can act as a genuine coding agent through the
[Pi](https://pi.dev) harness — when the scaffold makes it work in small verified steps.

The headline finding: **it's the harness, not (only) the model.** The same 12B that fails
to build a small game one-shot will build a complete, faithful, *rendered* Snake + Arkanoid
when driven the right way. Full story → [`docs/FINDINGS.md`](docs/FINDINGS.md).

```
agent (same Gemma 4 12B)            best rung on the strict render+physics benchmark
─────────────────────────────────   ────────────────────────────────────────────────
OpenCode                            R3
Pi  (default setup)                 R5
Pi  (this repo's setup + harness)   R9   ← complete, faithful, playable arcade
```

## Why

Asked to build a multi-mode browser game in one shot, a local 12B fails. But the failure is
mostly the *scaffold*: a weak model can't hold a whole complex task in its head, gets
confused by oversized tool surfaces, and can't self-correct from terse errors. Give it
**small verified steps**, a **clean tool-call channel**, a **reasoning budget**, and
**structural feedback**, and it succeeds. This repo distills that into a daily-use launcher
plus a benchmark to reproduce/extend the result.

## What's inside

| | |
|---|---|
| `bin/pi-gemma` | launcher: Pi → your local model with the winning method baked in |
| `setup/method.md` | the system prompt that encodes the method (decompose / read-first / replicate / test-and-iterate) |
| `setup/install.sh` | writes the Pi provider config and installs the launcher (parameterized by endpoint/model) |
| `bench/` | the ladder benchmark with **pluggable judges** (`arcade`, `minilib`) |
| `results/` | published artifacts: the playable arcade (`arcade/game.html`) + reports |
| `docs/FINDINGS.md` | the experiments and what they show |

## Quickstart

**Prerequisites:** the [Pi coding agent](https://pi.dev) (`pi` on PATH), `jq`, Node 18+, and a
local **OpenAI/Anthropic-compatible** model endpoint (e.g. [vLLM](https://docs.vllm.ai),
Ollama, or LM Studio) serving a model.

```bash
git clone https://github.com/rocco-milluzzo/pi-gemma-agent
cd pi-gemma-agent

# Point at your endpoint/model (defaults shown). Writes the Pi provider + installs the launcher.
VLLM_URL=http://localhost:8000 MODEL=gemma-4-12b-it ./setup/install.sh

# Use it as a coding agent:
pi-gemma                       # interactive
pi-gemma -p "add input validation to src/api.js and run the tests"   # headless
```

The launcher applies three levers that make a small model punch above its weight:
`--provider vllm-anthropic` (clean tool-calls), `--thinking high` (reasoning budget), and the
method system prompt (`setup/method.md`).

## Reproduce the benchmark

```bash
cd bench && npm install && cd ..                       # installs Playwright (for the arcade judge)
bench/runner.sh bench/ladders/minilib pi-anthropic 3   # fast, no browser — JS library by Node tests
bench/runner.sh bench/ladders/arcade  pi-anthropic 5   # the full Snake+Arkanoid (slower)
```

The runner climbs the ladder rung by rung: each rung starts from the last green state, the
agent makes one small change, and on failure the exact judge output is fed back for up to
*K* attempts. Provider/model are env-overridable (`PI_GEMMA_MODEL`, `PI_GEMMA_THINKING`,
`PI_GEMMA_PROVIDER`), so you can benchmark any model/endpoint or any agent variant.

## Add your own benchmark

A ladder is a directory with a `ladder.json` (`{ name, target, seed, context, rungs }`), a
`check.mjs`/`check.cjs` judge (`node check <target> <rung>` → exit 0 on pass), and a `seed/`.
See [`bench/README.md`](bench/README.md).

## How it works (the method)

1. **Decompose** into the smallest working increments; always start from a working state.
2. **Read first** — understand the existing structure before editing.
3. **Replicate structure** — when adding something similar (a new mode/route/handler), copy
   the closest working example. Symmetry beats invention.
4. **One step at a time** — implement, then verify concretely (run the test/build/check);
   don't break what worked.
5. **Test and iterate** — use the exact failure output to fix only what's broken.

## License

MIT — see [`LICENSE`](LICENSE).
