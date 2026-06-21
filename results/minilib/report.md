# minilib — results (Gemma 4 12B via Pi, enhanced harness)

A different domain (a CommonJS utility module, judged by Node assertions — no browser),
to show the ladder method is not game-specific.

| rung | function | result | attempts |
|---|---|---|---|
| R1 | add | ✅ | 1 |
| R2 | isEven | ✅ | 1 |
| R3 | reverse | ✅ | 2 |
| R4 | clamp | ✅ | 1 |
| R5 | fib | ✅ | 1 |
| R6 | fizzbuzz | ✅ | 1 |
| R7 | unique | ✅ | 1 |

**Outcome: R7 — full module, all checks green.** Artifact: `lib.js`.
