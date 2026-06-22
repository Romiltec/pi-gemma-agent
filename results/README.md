# Results — Gemma 4 12B (local, via Pi) on all five ladders

Same model (`gemma-4-12b-it` served by vLLM), same harness (this repo's `pi-gemma`: Anthropic
tool-call channel + `--thinking high` + the method system prompt), judged automatically.

| ladder | domain | rungs | reached | notes |
|---|---|---|---|---|
| `cli` | Node CLI calculator | 5 | **5/5** | all first attempt |
| `api` | zero-dep HTTP API | 4 | **4/4** | all first attempt |
| `todo` | To-Do web app (DOM) | 5 | **5/5** | all first attempt |
| `minilib` | JS utility library | 7 | **7/7** | one retry on R3 |
| `arcade` | Snake + Arkanoid (render + physics) | 9 | **9/9** | R6 (2nd game mode) took 4 attempts — the hard one |

Everyday coding shapes (CLI, backend, frontend app, library) are completed first-try; the
genuinely hard task (a faithful two-mode rendered game) is where the harness earns its keep
(see `../docs/FINDINGS.md`). Playable/inspectable artifacts sit next to each report.
