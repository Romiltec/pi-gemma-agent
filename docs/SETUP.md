# SETUP — run Pi on a local model, optimized, anywhere

This guide gets you from "a model served locally" to "a working, optimized Pi coding agent"
on any machine, for any OpenAI/Anthropic-compatible model. It documents the tuned recipes for
**Gemma 4 12B** and **Qwen3.6-27B**, plus a template you can copy for any other model.

There are three moving parts:

1. **Serve the model** (vLLM / Ollama / LM Studio) with tool calling enabled.
2. **Register the model with Pi** on the right channel (`~/.pi/agent/models.json`).
3. **Launch** with `pi-agent()` — a shell function that wraps `pi` and injects the method prompt.

No custom binaries. The `pi-agent()` function is installed in your shell rc by `setup/install.sh`.
Provider/model/thinking are set via Pi's native flags or `settings.json` defaults.

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
(e.g. `hermes` for Qwen; `gemma4` for Gemma). vLLM also serves
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

Run the installer once per model. It's **interactive** by default or accepts env vars:

```bash
# Interactive (asks every question):
./setup/install.sh

# Non-interactive (env vars):
MODEL=<id> VLLM_URL=http://localhost:8000 CTX=131072 ./setup/install.sh
```

For a model on a **different endpoint** (so it gets its own providers instead of overwriting
the default ones), add a `NAME` prefix — e.g. `NAME=starbuck ... ./setup/install.sh` creates
a provider named `starbuck` instead of `vllm`. Add `REASONING=true` for models that emit thinking.

### What `install.sh` does

1. **Detects model family** from the ID (gemma, qwen, llama, mistral, unknown)
2. **Recommends the right API channel** (Anthropic for Gemma, OpenAI for Qwen, configurable for others)
3. **Probes the endpoint** (optional) to verify the model is served
4. **Writes providers** into `~/.pi/agent/models.json` (additive — multiple models coexist)
5. **Initialises `~/.pi/agent/settings.json`** on first run (default model, provider, thinking)
6. **Installs `pi-agent()`** shell function + convenience aliases in `~/.zshrc`
7. **Removes old custom binaries** (`pi-gemma`, `pi-starbuck`) if they exist

### Provider naming

| `NAME` env | Providers created | Use case |
|---|---|---|
| *(empty)* | `vllm` + `vllm-anthropic` | First/default model |
| `starbuck` | `starbuck` (+ `starbuck-anthropic` if both APIs) | Second model on different host |
| `mylabel` | `mylabel` (+ `mylabel-anthropic` if both) | Any custom label |

### The `models.json` structure

```jsonc
// ~/.pi/agent/models.json
{
  "providers": {
    // Anthropic channel (no /v1 suffix in baseUrl)
    "vllm-anthropic": {
      "name": "vLLM Anthropic (vllm-anthropic)",
      "api": "anthropic-messages",
      "apiKey": "local",
      "authHeader": true,
      "baseUrl": "http://<host>:<port>",
      "models": [{
        "id": "<id>",
        "name": "<id>",
        "input": ["text"],
        "contextWindow": 131072,
        "maxTokens": 8192,
        "reasoning": false,
        "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
      }]
    },
    // OpenAI channel (/v1 suffix in baseUrl)
    "vllm": {
      "name": "vLLM OpenAI (vllm)",
      "api": "openai-completions",
      "apiKey": "local",
      "authHeader": true,
      "baseUrl": "http://<host>:<port>/v1",
      "models": [{
        "id": "<id>",
        "name": "<id>",
        "input": ["text"],
        "contextWindow": 131072,
        "maxTokens": 8192,
        "reasoning": false,
        "compat": { "maxTokensField": "max_tokens" },
        "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
      }]
    }
  }
}
```

---

## 3. Launch

After `install.sh`, reload your shell. You now have:

```bash
pi-agent                                      # default model (from settings.json)
pi-agent --provider vllm-anthropic --model gemma-4-12b-it --thinking high   # explicit
pi-agent --print "refactor src/utils.js"       # headless

# Convenience aliases (installed by default, edit in ~/.zshrc):
pi-gemma    # Gemma 4 12B via Anthropic channel, thinking high
pi-qwen     # Qwen3.6-27B via starbuck (OpenAI) channel, thinking high
```

The `pi-agent()` function applies the **method system prompt** automatically:

```bash
pi-agent() {
  command pi --append-system-prompt "$(cat <repo>/setup/method.md)" "$@"
}
```

Three levers make a small model punch above its weight:

| Lever | Where | Effect |
|---|---|---|
| **provider** | `--provider` or `settings.json` | Tool-call channel (the #1 optimization) |
| **thinking** | `--thinking` or `settings.json` | Reasoning budget vs token cost |
| **method** | `setup/method.md` (auto-injected) | Decompose → read-first → replicate → iterate |

### Override at runtime

```bash
pi-agent --provider starbuck --model qwen3.6-27b --thinking off   # skip reasoning
pi-agent --provider vllm-anthropic --thinking medium              # reduce thinking
```

### `settings.json` defaults

Edit `~/.pi/agent/settings.json` to change what `pi-agent` uses without flags:

```jsonc
{
  "defaultModel": "qwen3.6-27b",
  "defaultProvider": "starbuck",
  "defaultThinkingLevel": "medium",
  "theme": "dark",
  "hideThinkingBlock": false
}
```

---

## 4. Choosing the channel (the key optimization)

A coding agent must emit **clean tool calls**. Not every model does this well on every API, and
this is where most of the "it doesn't work" comes from. Rule of thumb:

| Model family | Recommended channel | Thinking | Why |
|---|---|---|---|
| **Gemma** (4 12B) | `vllm-anthropic` | `high` | OpenAI tool-calls are **malformed** (`<\|tool_call\|>…` as text) with the `gemma4` parser. The Anthropic `/v1/messages` channel is clean. |
| **Qwen** (3.6-27B) | `starbuck` (OpenAI) | `medium` | Strong **native** OpenAI tool-calling. Large thinking budget mostly costs tokens — Qwen reasons natively. |
| **Other models** | Test both (§5) | Start `high` | Measure which channel edits files reliably; drop `thinking` if the bench still passes. |

**How to decide for an unknown model:** register it (§2), then run a fast bench ladder on each
channel (§5). The channel where the ladder climbs is the right one.

### Do NOT copy Gemma's channel choice blindly

Gemma's malformed OpenAI tool-calls are specific to the `gemma4` tool-call parser in vLLM.
Qwen with the `hermes` parser produces clean OpenAI tool-calls. Always verify with a manual
probe before assuming:

```bash
# Probe OpenAI channel:
curl -s http://<host>:<port>/v1/chat/completions \
  -H "Authorization: Bearer local" \
  -d '{
    "model": "<id>",
    "messages": [{"role": "user", "content": "Hello"}],
    "tools": [{"type": "function", "function": {"name": "test", "parameters": {"type": "object"}}}]
  }' | jq '.choices[0].message.tool_calls'
```

If `tool_calls` is `null` or empty but there's garbled text in `content`, the OpenAI channel
is broken for that model — switch to Anthropic.

---

## 5. Verify (and pick settings) with the bench

Don't guess — measure. The bench doubles as a config validator: if a ladder climbs, your
model + channel + settings actually work end-to-end.

```bash
cd bench && npm install && cd ..

# Fast smoke tests (no browser):
bench/runner.sh bench/ladders/cli     pi-anthropic 3   # Anthropic channel
bench/runner.sh bench/ladders/minilib pi-anthropic 3
bench/runner.sh bench/ladders/api     pi-anthropic 3

# Override model/provider for the runner:
PI_GEMMA_MODEL=qwen3.6-27b PI_GEMMA_PROVIDER=starbuck bench/runner.sh bench/ladders/cli starbuck 5

# Browser judges (requires Playwright):
bench/runner.sh bench/ladders/todo    pi-anthropic 3
bench/runner.sh bench/ladders/arcade  pi-anthropic 5   # stress test

# One-shot (no scaffold, raw capability):
bench/oneshot.sh bench/ladders/arcade 3
```

If `cli`/`minilib` climb, the model can edit + iterate. Try `arcade` for the hard case.

---

## Per-model recipes

### Gemma 4 12B (the reference in this repo)

```bash
MODEL=gemma-4-12b-it VLLM_URL=http://<host>:8801 CTX=131072 ./setup/install.sh
```

Then (after reload):
```bash
pi-gemma                        # provider vllm-anthropic, thinking high
pi-gemma --print "fix the bug"  # headless
```

- **Channel:** `vllm-anthropic` (Anthropic). OpenAI tool-calls are malformed with Gemma's `gemma4` parser.
- **Thinking:** `high`. A reasoning budget helps the 12B make structural leaps.
- **Result:** full arcade (R9), all everyday ladders — see [`FINDINGS.md`](FINDINGS.md).

### Qwen3.6-27B (reasoning model)

Qwen runs on a **different endpoint** from Gemma:

```bash
NAME=starbuck MODEL=qwen3.6-27b VLLM_URL=http://<host>:8000 CTX=131072 REASONING=true ./setup/install.sh
```

Then (after reload):
```bash
pi-qwen                          # provider starbuck (OpenAI), thinking high
pi-qwen --print "design a schema" # headless
```

- **Channel:** `starbuck` (OpenAI). Qwen has clean native tool-calling — Anthropic not needed.
- **Thinking:** `high` for Pi's orchestration. Qwen also reasons natively (`thinkingFormat: qwen-chat-template`).
- **Speed:** a 27B *thinks* before answering, so each turn is slower — the trade for accuracy.
- **Bump `MAXTOK`** (via `install.sh` or `models.json`) if edits get truncated.

### Any other model (template)

```bash
# 1. Register (interactive or env vars):
NAME=<label> MODEL=<id> VLLM_URL=<url> CTX=<ctx> ./setup/install.sh

# 2. Smoke-test with the bench:
PI_GEMMA_MODEL=<id> PI_GEMMA_PROVIDER=<label>-anthropic bench/runner.sh bench/ladders/cli pi-anthropic 3
PI_GEMMA_MODEL=<id> PI_GEMMA_PROVIDER=<label> bench/runner.sh bench/ladders/cli pi 3

# 3. Keep the channel that climbs. Tune thinking:
#    Start high, drop to medium/off if bench still passes (cheaper).

# 4. Add an alias in ~/.zshrc:
#    echo 'pi-mylabel() { pi-agent --provider <label> --model <id> --thinking <level> "$@"; }' >> ~/.zshrc
```

---

## Appendix — using Claude Code (or OpenCode) with the same local model

This repo optimizes **Pi**, but the same local endpoint drives other agents:

- **OpenCode** speaks OpenAI natively → point a provider at `http://<host>:<port>/v1`.
- **Claude Code** speaks the **Anthropic Messages API** → point it at `/v1/messages`
  (vLLM serves it) via env vars. Works for models whose *OpenAI* tool-calls are unreliable:

  ```bash
  claude-local() {
    ANTHROPIC_BASE_URL="http://<host>:<port>" \
    ANTHROPIC_AUTH_TOKEN="local" \
    ANTHROPIC_MODEL="<id>" \
    ANTHROPIC_SMALL_FAST_MODEL="<id>" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    command claude "$@"
  }
  ```

  Reasoning models (Qwen 3.x with `thinking` blocks) work as-is — Claude Code handles them.
  Note: Claude Code's harness is heavier (larger system prompt, more tools) than Pi's —
  great on capable models, but it can overwhelm a small one.

---

## Tuning knobs (summary)

| Knob | Where | Effect |
|---|---|---|
| Tool-call **channel** | `--provider` / `models.json` | Reliability of edits — the **#1 lever** |
| **Thinking** | `--thinking` / `settings.json` | Reasoning budget vs token cost |
| **Context window** | `install.sh CTX` / `models.json` | How much context Pi will send |
| **Max tokens** | `install.sh MAXTOK` / `models.json` | Max length of a single response |
| **Method** | `setup/method.md` | How the model approaches tasks |
| `compat.maxTokensField` | `models.json` (OpenAI) | Some servers need `max_tokens` (set by installer) |
| `compat.thinkingFormat` | `models.json` (OpenAI) | Qwen needs `qwen-chat-template` for thinking blocks |