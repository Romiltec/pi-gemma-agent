# arcade — results (Gemma 4 12B via Pi, enhanced harness)

Judge: render + physics (game must be drawn every frame and respect the originals' physics).
Hard rungs (block progression): 1,2,3,5,6,7,9. Soft (informational): 4,8.

| rung | result | attempts |
|---|---|---|
| R1 boot | ✅ | 1 |
| R2 menu | ✅ | 1 |
| R3 snake render+grid+input | ✅ | 1 |
| R4 food/grow (soft) | ✅ | 1 |
| R5 snake game over | ✅ | 1 |
| R6 arkanoid paddle | ✅ | 4 (the wall, broken by the v3 method) |
| R7 ball physics (bounce) | ✅ | 1 |
| R8 bricks / game over (soft) | ✅ | 2 |
| R9 restart | ✅ | 1 |

**Outcome: R9 — a complete, faithful, rendered Snake + Arkanoid.** Playable artifact: `game.html`
(open in a browser; press `S`/`A`, arrows, `Enter` on game over).

For the full story (why Pi reached only R2/R5 before, and what the enhanced harness changed),
see `../../docs/FINDINGS.md`.
