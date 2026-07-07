# SETUP — run Pi on a local model, optimized, anywhere

This guide gets you from "a model served locally" to "a working, optimized Pi coding agent"
on any machine, for any OpenAI/Anthropic-compatible model. It documents the tuned recipes for
**Gemma 4 12B** and **Qwen (Coder)**, plus a template you can copy for any other model.

There are three moving parts:

1. **Serve the model** (vLLM / Ollama / LM Studio) with tool calling enabled.
2. **Register the model with Pi** on the right channel (`~/.pi/agent/models.json`).
3. **Launch** with the optimization levers (channel + reasoning budget + method prompt).

The single most important optimization is **step 2 — the tool-call channel** — because a coding
agent is only as good as its ability to actually edit files and run commands.

---

## 1. Serve the model

Any OpenAI-compatible (`/v1/chat/completions`) or Anthropic-compatible (`/v1/messages`)
endpoint works. Enable **tool calling** on the server — without it the agent can't edit files.

**vLLM** (recommended for throughput; exposes *both* APIs on the same port):

```bash
vllm serve <model> \
  --served-model-name <id> \
  --max-model-len 131072 \
  --enable-auto-tool-choice \
  --tool-call-parser <parser-for-your-model-family>
```

Pick `--tool-call-parser` for your model family per the
[vLLM tool-calling docs](https://docs.vllm.ai/en/latest/features/tool_calling.html)
(e.g. `hermes` for Qwen2.5; use the parser your model documents). vLLM also serves
`/v1/messages` (Anthropic) on the same port — this repo uses that channel for models whose
OpenAI-style tool-calls are unreliable (see §4).

**Ollama** / **LM Studio** also expose an OpenAI-compatible endpoint (default
`http://localhost:11434/v1` and `http://localhost:1234/v1`); use their tool-calling support.

Verify the endpoint is up:

```bash
curl -s http://localhost:8000/v1/models | jq -r '.data[].id'
```

---

## 2. Register the model with Pi

Run the installer once per model (it's additive — several models coexist):

```bash
MODEL=<id> VLLM_URL=http://localhost:8000 CTX=131072 ./setup/install.sh
```

This writes two providers into `~/.pi/agent/models.json`, both pointing at your endpoint, and
adds `<id>` to each:

- **`vllm-anthropic`** → `api: anthropic-messages`, `baseUrl: <url>` (the `/v1/messages` API)
- **`vllm`** → `api: openai-completions`, `baseUrl: <url>/v1` (the `/v1/chat/completions` API)

You pick which channel to use at launch (§3–§4). To do it by hand instead, the entry looks
like:

```jsonc
// ~/.pi/agent/models.json
{
  "providers": {
    "vllm-anthropic": {
      "baseUrl": "http://localhost:8000", "api": "anthropic-messages",
      "apiKey": "local", "authHeader": true,
      "models": [{ "id": "<id>", "name": "<id>", "input": ["text"],
        "contextWindow": 131072, "maxTokens": 8192,
        "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0} }]
    },
    "vllm": {
      "baseUrl": "http://localhost:8000/v1", "api": "openai-completions",
      "apiKey": "local", "authHeader": true,
      "models": [{ "id": "<id>", "name": "<id>", "input": ["text"],
        "contextWindow": 131072, "maxTokens": 8192,
        "compat": { "maxTokensField": "max_tokens" },
        "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0} }]
    }
  }
}
```

---

## 3. Launch

```bash
pi-gemma                                         # default model, Anthropic channel, thinking high
PI_GEMMA_MODEL=<id> pi-gemma                     # choose a registered model
PI_GEMMA_PROVIDER=vllm PI_GEMMA_MODEL=<id> pi-gemma   # use the OpenAI channel instead
pi-gemma -p "add a /users route and run the tests"    # headless
```

The launcher (`bin/pi-gemma`, despite the name it's model-agnostic) applies three levers:

- **`--provider`** — the tool-call channel (env `PI_GEMMA_PROVIDER`, default `vllm-anthropic`).
- **`--thinking`** — reasoning budget (env `PI_GEMMA_THINKING`, default `high`).
- **`--append-system-prompt setup/method.md`** — the working method (decompose → read-first →
  replicate structure → test-and-iterate).

Make a per-model alias if you like:

```bash
echo 'pi-qwen(){ PI_GEMMA_PROVIDER=vllm PI_GEMMA_MODEL=qwen2.5-coder-14b PI_GEMMA_THINKING=medium pi-gemma "$@"; }' >> ~/.zshrc
```

---

## 4. Choosing the channel (the key optimization)

A coding agent must emit **clean tool calls**. Not every model does this well on every API, and
this is where most of the "it doesn't work" comes from. Rule of thumb:

| model family | recommended channel | thinking | why |
|---|---|---|---|
| **Gemma** (e.g. Gemma 4 12B) | `vllm-anthropic` | `high` | its OpenAI-style tool-calls can be **malformed** (`<\|tool_call\|>…` emitted as text); the Anthropic `/v1/messages` channel is clean. A reasoning budget helps it make structural leaps. |
| **Qwen / Qwen-Coder** | `vllm` (OpenAI) | `medium`/`off` | strong **native** OpenAI tool-calling; Coder variants are already strong, so a large thinking budget mostly costs tokens. |
| **any other model** | test both (§5) | start `high` | measure which channel edits files reliably; keep the cheaper `thinking` that still passes the bench. |

**How to decide for an unknown model:** register it (§2), then run a fast bench ladder on each
channel (§5). The channel where the ladder climbs is the right one.

---

## 5. Verify (and pick settings) with the bench

Don't guess — measure. The bench doubles as a config validator: if a ladder climbs, your
model + channel + settings actually work end-to-end.

```bash
cd bench && npm install && cd ..

# fast, no browser — a good smoke test for any model/channel:
PI_GEMMA_MODEL=<id> bench/runner.sh bench/ladders/cli     pi-anthropic 3   # Anthropic channel
PI_GEMMA_MODEL=<id> bench/runner.sh bench/ladders/cli     pi              3   # OpenAI channel
PI_GEMMA_MODEL=<id> bench/runner.sh bench/ladders/minilib pi-anthropic 3
```

(The runner's 2nd arg selects the channel: `pi-anthropic` → `vllm-anthropic`, `pi` → `vllm`.)
If `cli`/`minilib` climb, the model can edit + iterate. Try `arcade` for the hard case.

---

## Per-model recipes

### Gemma 4 12B (the reference in this repo)

```bash
MODEL=gemma-4-12b-it VLLM_URL=http://<host>:8000 CTX=131072 ./setup/install.sh
pi-gemma                       # provider vllm-anthropic, thinking high  (defaults)
```
- Channel: **`vllm-anthropic`** (OpenAI tool-calls are malformed with Gemma). Thinking **high**.
- Result with this repo's harness: full arcade (R9), all everyday ladders first-try — see
  [`FINDINGS.md`](FINDINGS.md).

### Qwen / Qwen-Coder (e.g. Qwen2.5-Coder-14B, Qwen3-Coder)

```bash
MODEL=qwen2.5-coder-14b VLLM_URL=http://<host>:8000 CTX=131072 ./setup/install.sh
PI_GEMMA_PROVIDER=vllm PI_GEMMA_MODEL=qwen2.5-coder-14b PI_GEMMA_THINKING=medium pi-gemma
```
- Channel: **`vllm`** (OpenAI) — Qwen has solid native tool-calling. Thinking **medium/off**:
  Coder variants are strong, so save tokens. Bump `MAXTOK` if you want longer single edits.
- Serve with the Qwen-appropriate `--tool-call-parser`.

### Any other model (template)

1. `MODEL=<your-id> VLLM_URL=<url> CTX=<ctx> ./setup/install.sh`
2. Smoke-test both channels with the `cli` ladder (§5); keep the one that climbs.
3. Start `PI_GEMMA_THINKING=high`; drop to `medium`/`off` if the bench still passes (cheaper).
4. Make a `pi-<model>` alias with the winning `PI_GEMMA_PROVIDER`/`MODEL`/`THINKING`.

---

## Tuning knobs (summary)

| knob | where | effect |
|---|---|---|
| tool-call **channel** | `PI_GEMMA_PROVIDER` / `models.json` | reliability of edits — the #1 lever |
| **thinking** | `PI_GEMMA_THINKING` | reasoning budget vs token cost |
| **contextWindow** | `install.sh CTX` / `models.json` | how much context Pi will use |
| **maxTokens** | `install.sh MAXTOK` / `models.json` | max length of a single response/edit |
| **method** | `setup/method.md` | how the model approaches tasks (decompose/read-first/…) |
| `compat.maxTokensField` | `models.json` (OpenAI channel) | some servers need `max_tokens` (set by installer) |
