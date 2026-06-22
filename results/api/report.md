# api — results (Gemma 4 12B via Pi)

A zero-dependency Node HTTP API, judged by booting it and querying routes. **R4/4, every rung first attempt.**

| rung | route | result | attempts |
|---|---|---|---|
| R1 | GET /health -> {ok:true} | ✅ | 1 |
| R2 | GET /echo?msg= | ✅ | 1 |
| R3 | GET /add?a=&b= -> {sum} | ✅ | 1 |
| R4 | unknown -> 404 | ✅ | 1 |

Artifact: `server.cjs` — run `PORT=3000 node server.cjs`, then curl the routes.
