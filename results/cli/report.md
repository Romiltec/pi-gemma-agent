# cli — results (Gemma 4 12B via Pi)

A Node CLI calculator, judged by running it as a subprocess. **R5/5, every rung first attempt.**

| rung | op | result | attempts |
|---|---|---|---|
| R1 | add | ✅ | 1 |
| R2 | sub | ✅ | 1 |
| R3 | mul | ✅ | 1 |
| R4 | div (+ divide-by-zero error) | ✅ | 1 |
| R5 | --help / usage | ✅ | 1 |

Artifact: `cli.cjs` — run `node cli.cjs add 2 3`.
