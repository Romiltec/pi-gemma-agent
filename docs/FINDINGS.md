# Findings — it's the harness, not (only) the model

This project started from a simple, frustrating observation: asked to build a small
browser game in one shot, a local **Gemma 4 12B** failed — on both Claude Code and
OpenCode. The question became: *is a small local model simply too weak to be a coding
agent, or is the scaffold around it the real bottleneck?*

We ran the same `gemma-4-12b-it` (served by vLLM) under three agent harnesses — Claude
Code, OpenCode, and **Pi** — on the same task, judged automatically, and iterated on the
harness. The answer turned out to be clear.

## The benchmark

A task is built **as a ladder of tiny verified steps** (a "rung" = one small increment),
not one big leap. Each rung starts from the last *green* state, the agent makes one small
change, and an automated judge decides pass/fail. The agent never faces the whole problem
at once — the harness owns the decomposition, the model owns each micro-edit.

The `arcade` ladder builds a faithful Snake + Arkanoid in a single `game.html` (menu →
gameplay → game over → restart) across 9 rungs. Two judge generations were used:

- **v1 (state-only):** checks the exposed `window.__game` state transitions.
- **v2 (render + physics):** also requires the game to be **drawn every frame** and to
  respect the originals' physics (grid-stepped snake; ball that bounces with velocity
  inversion). This closes the obvious loophole — *update state without ever rendering*.

## The experiments (same model throughout: Gemma 4 12B)

### 1. State-only judge — the harness gap appears
| agent | rung reached | note |
|---|---|---|
| Claude Code | **9** | full game logic (but, on the v2 judge, it never *renders* the gameplay) |
| OpenCode | 3 | menu works; snake doesn't move; regressed the canvas |
| Pi | 2 | **confounded** — see below |

Pi's low score was **not** capability: its OpenAI-completions channel produced *malformed
tool-calls* with Gemma (`<|tool_call>…` emitted as text), so it could not reliably edit
files. Pointing Pi at the model's **Anthropic Messages API** instead fixed the channel and
took it from **R2 → R5**.

### 2. Render + physics judge — a higher bar
On the stricter judge, Claude's earlier game fails R3 (it never rendered the gameplay).
With the Anthropic channel and a root-cause fix (Pi made the snake move 20px *per frame*,
~1200px/s — unplayable, and it died before the check could observe it; the contract now
requires a ~120ms grid step), **Pi passed R1–R5 mostly first-try** but **stalled at R6**:
it would not add the *second game mode* (Arkanoid), even decomposed and with feedback.

### 3. A better harness — Pi reaches R9
Crucially, Claude *had* made the same model emit complete Arkanoid logic (it just didn't
draw it). **So the model can do it — the limit was Pi's scaffold.** We built an enhanced
runner that imitates what a strong agent does, with three levers:

1. **Read-first** — the prompt forces Pi to read the file and understand the existing
   structure before editing.
2. **Deeper reasoning** — `pi --thinking high` gives a reasoning budget for the
   structural leap.
3. **Structural feedback** — on failure: *"the current mode's branch is missing; replicate
   the structure of the working 'snake' branch (update + draw + input)."*

Result: **Pi reached R9** — a complete, faithful, rendered Snake + Arkanoid — on the strict
render+physics judge. R6 broke on the 4th attempt; R7–R9 followed.

| agent | judge | rung reached |
|---|---|---|
| Claude Code | state-only (v1) | 9 (not rendered) |
| OpenCode | state-only (v1) | 3 |
| Pi (openai channel) | state-only (v1) | 2 (tool-call bug) |
| Pi (anthropic channel) | render+physics (v2) | 5 |
| **Pi (anthropic + enhanced harness v3)** | **render+physics (v2)** | **9** |

## The takeaway

**The same 12B fails or succeeds depending on how much the harness makes it read, reason,
and replicate structure** — exactly the behaviours that make a "smart" agent smart. With
small verified steps, a clean tool-call channel, a reasoning budget, and structural
feedback, a free local model builds a faithful two-game arcade.

## Does it generalize? Five ladders across domains

The laddered small-steps method is not game-specific. The repo ships five ladders, each with
its own automated judge, spanning very different kinds of software:

| ladder | domain | judge |
|---|---|---|
| `arcade` | browser game (Snake + Arkanoid) | Playwright: rendering + physics |
| `todo` | browser app (To-Do) | Playwright: DOM + `window.__todo` state |
| `minilib` | pure JS library | Node assertions |
| `cli` | Node CLI calculator | subprocess stdout / exit codes |
| `api` | zero-dependency HTTP API | boot server + query routes |

Pi (Gemma 4 12B, this repo's harness) climbs all five. Per-ladder results are published under
`results/`. The point: give a weak model small verified steps and good feedback, and it works
across CLIs, backends, frontends, libraries and games alike.

## What this repo packages

The reusable distillation of the above: the right **Pi → local-model config**, the
**method** as a system prompt, the **`--thinking`** lever, a **`pi-gemma` launcher** for
daily coding-agent use, and the **ladder benchmark** (pluggable judges) so anyone can
reproduce the numbers or validate a new model/endpoint.
