# pi-gemma-agent

**Turn a small local model into a capable coding agent — and prove it.**

This repo packages a working setup and a reproducible benchmark showing that free,
locally-served models (**Gemma 4 12B**, **Qwen3.6-27B**) can act as genuine coding
agents through the [Pi](https://pi.dev) harness — when the scaffold makes them work in
small verified steps.

The headline finding: **it's the harness, not (only) the model.** The same 12B that
fails to build a small game one-shot will build a complete, faithful, *rendered* Snake
+ Arkanoid when driven the right way. Full story → [`docs/FINDINGS.md`](docs/FINDINGS.md).

```
agent (same Gemma 4 12B)            best rung on the strict render+physics benchmark
─────────────────────────────────   ────────────────────────────────────────────────
OpenCode                            R3
Pi  (default setup)                 R5
Pi  (this repo's harness)           R9   ← complete, faithful, playable arcade
```

---

## Architecture

**No custom binaries.** The repo provides:

| Component | What it does |
|---|---|
| `setup/install.sh` | Interactive installer: registers providers in `~/.pi/agent/models.json`, writes `pi-agent()` to your shell rc |
| `setup/method.md` | The optimized system prompt (decompose → read-first → replicate → iterate) |
| `bench/` | Ladder benchmark with pluggable judges — validates any model/endpoint setup |
| `docs/SETUP.md` | Deep-dive: channel selection, per-model recipes, any-model template |

The `pi-agent()` shell function is the only "launcher" — it wraps `pi` and injects
`setup/method.md` as the system prompt. Provider/model/thinking are set via Pi's native
flags (`--provider`, `--model`, `--thinking`) or `~/.pi/agent/settings.json` defaults.

```
┌──────────────────────────────────────────────────────────────────┐
│  $ pi-agent  (or pi-agent --provider vllm-anthropic ...)        │
│  │                                                              │
│  ├─ pi                                                         │
│  │   ├─ --append-system-prompt setup/method.md                 │
│  │   ├─ --provider <from settings.json or CLI>                  │
│  │   ├─ --model <from settings.json or CLI>                     │
│  │   └─ --thinking <from settings.json or CLI>                  │
│  │                                                              │
│  └─ ~/.pi/agent/models.json                                    │
│      └─ providers: vllm-anthropic, starbuck, ollama, …         │
└──────────────────────────────────────────────────────────────────┘
```

---

## Setup step by step

### 1. Prerequisites

| Requirement | Install |
|---|---|
| **Pi coding agent** | `brew install --head https://raw.githubusercontent.com/mariozechner/pi/main/piFormula.rb` or [pi.dev](https://pi.dev) |
| **jq** | `brew install jq` |
| **Node.js 18+** | `brew install node` (for bench judges and extensions) |
| **fd + ripgrep** | `brew install fd ripgrep` |

Verify: `pi --version` (current: 0.80.10)

### 2. Serve your model(s) with vLLM

Each model runs on its own vLLM instance (different host/port/GPU).

**Gemma 4 12B** (small, fast, everyday tasks):
```bash
vllm serve google/gemma-4-12b-it \
  --served-model-name gemma-4-12b-it \
  --max-model-len 131072 \
  --enable-auto-tool-choice \
  --tool-call-parser gemma4 \
  --port 8801
```

**Qwen3.6-27B** (larger, reasoning-heavy):
```bash
vllm serve Qwen/Qwen3-27B \
  --served-model-name qwen3.6-27b \
  --max-model-len 131072 \
  --enable-auto-tool-choice \
  --tool-call-parser hermes \
  --port 8000
```

> **Why two instances?** Each model gets its own GPU memory and port — no contention.
> vLLM serves **both** the OpenAI API (`/v1/chat/completions`) and the Anthropic API
> (`/v1/messages`) on the same port. The choice of API per model is the **single most
> important optimization** (see §4).

Verify endpoints are up:
```bash
curl -s http://<gemma-host>:8801/v1/models | jq -r '.data[].id'
curl -s http://<qwen-host>:8000/v1/models   | jq -r '.data[].id'
```

### 3. Clone and register models

```bash
git clone https://github.com/Romiltec/pi-gemma-agent
cd pi-gemma-agent

# Interactive mode (asks you every question):
./setup/install.sh

# Or non-interactive (env vars):
MODEL=gemma-4-12b-it VLLM_URL=http://<gemma-host>:8801 CTX=131072 ./setup/install.sh

# Second model on a different endpoint (use NAME to avoid overwriting defaults):
NAME=starbuck MODEL=qwen3.6-27b VLLM_URL=http://<qwen-host>:8000 CTX=131072 REASONING=true ./setup/install.sh
```

#### What `install.sh` does

1. **Asks for parameters** (or reads env vars): model ID, endpoint URL, context window,
   max tokens, reasoning support, API channel
2. **Detects model family** and recommends the right API:
   - Gemma → `anthropic-messages` (OpenAI tool-calls are malformed with the `gemma4` parser)
   - Qwen → `openai-completions` (clean native tool-calling)
3. **Writes providers** to `~/.pi/agent/models.json` (additive — multiple models coexist)
4. **Initialises `~/.pi/agent/settings.json`** on first run (default model/provider/thinking)
5. **Installs `pi-agent()`** shell function in `~/.zshrc` (with `pi-gemma`/`pi-qwen` aliases)
6. **Removes old custom binaries** (`pi-gemma`, `pi-starbuck`) if they exist

#### Interactive session example

```
╔══════════════════════════════════════════════════════════╗
║  Pi Agent — Register a local model                     ║
║  Press Enter to accept the default (in brackets)        ║
╚══════════════════════════════════════════════════════════╝

Provider name (leave empty for 'vllm', e.g. 'qwen' for a 2nd model) [vllm]:
Model ID (as served by vLLM, --served-model-name) [gemma-4-12b-it]:

  Recommended API for 'gemma-4-12b-it' (gemma family): anthropic-messages
  → Gemma's OpenAI tool-calls are malformed; Anthropic channel is cleaner.

API to register (openai-completions / anthropic-messages / both) [anthropic-messages]:
vLLM endpoint URL (http://host:port, no trailing /v1) [http://localhost:8000]:
Context window (tokens) [131072]:
Max response tokens [8192]:
Is this a reasoning model (emits <thinking> blocks)? [y/N]: n
Default thinking level for this model (off/minimal/low/medium/high/xhigh) [high]:

┌─────────────────────────────────────────────────────┐
│  Configuration summary                              │
├─────────────────────────────────────────────────────┤
│  Model ID                │ gemma-4-12b-it           │
│  Family                  │ gemma                    │
│  Endpoint                │ http://<host>:8801       │
│  API                     │ anthropic-messages       │
│  Provider (Anthropic)    │ vllm-anthropic           │
│  Context window          │ 131072                   │
│  Max tokens              │ 8192                     │
│  Reasoning               │ false                    │
│  Default thinking        │ high                     │
└─────────────────────────────────────────────────────┘

Verify endpoint is reachable? [y/N]: y
  Probing http://<host>:8801/v1/models … OK — found: gemma-4-12b-it
  ✓ 'gemma-4-12b-it' confirmed on server

Writing providers to ~/.pi/agent/models.json …
✓ Registered 'gemma-4-12b-it' on provider: vllm-anthropic
✓ Created ~/.pi/agent/settings.json (default: gemma-4-12b-it)
✓ Shell function 'pi-agent()' installed in ~/.zshrc

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Setup complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Reload your shell, then use:
    pi-agent                                    # default model
    pi-agent --provider vllm-anthropic --model gemma-4-12b-it --thinking high
```

### 4. The resulting configuration files

#### `~/.pi/agent/models.json` (auto-generated by install.sh)

```jsonc
{
  "providers": {
    // ── Gemma 4 12B ────────────────────────────────────────────
    "vllm-anthropic": {
      "name": "vLLM Anthropic (vllm-anthropic)",
      "api": "anthropic-messages",
      "apiKey": "local",
      "authHeader": true,
      "baseUrl": "http://<gemma-host>:8801",        // no /v1 for Anthropic
      "models": [{
        "id": "gemma-4-12b-it",
        "name": "gemma-4-12b-it",
        "input": ["text"],
        "contextWindow": 131072,
        "maxTokens": 8192,
        "reasoning": false,
        "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
      }]
    },
    "vllm": {
      "name": "vLLM OpenAI (vllm)",
      "api": "openai-completions",
      "apiKey": "local",
      "authHeader": true,
      "baseUrl": "http://<gemma-host>:8801/v1",     // /v1 for OpenAI
      "models": [{
        "id": "gemma-4-12b-it",
        "name": "gemma-4-12b-it",
        "input": ["text"],
        "contextWindow": 131072,
        "maxTokens": 8192,
        "reasoning": false,
        "compat": { "maxTokensField": "max_tokens" },
        "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
      }]
    },

    // ── Qwen3.6-27B ───────────────────────────────────────────
    "starbuck": {
      "name": "vLLM OpenAI (starbuck)",
      "api": "openai-completions",
      "apiKey": "local",
      "authHeader": true,
      "baseUrl": "http://<qwen-host>:8000/v1",
      "models": [{
        "id": "qwen3.6-27b",
        "name": "qwen3.6-27b",
        "input": ["text"],
        "contextWindow": 180224,
        "maxTokens": 8192,
        "reasoning": true,
        "compat": {
          "maxTokensField": "max_tokens",
          "thinkingFormat": "qwen-chat-template"
        },
        "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
      }]
    },

    // ── Ollama cloud (optional) ────────────────────────────────
    "ollama": {
      "name": "Ollama",
      "api": "openai-completions",
      "apiKey": "ollama",
      "baseUrl": "http://127.0.0.1:11434/v1",
      "models": [
        { "id": "deepseek-v4-flash:cloud", "_launch": true, "input": ["text"] },
        { "id": "gemma4:cloud", "_launch": true, "input": ["text"] }
      ]
    }
  }
}
```

#### `~/.pi/agent/settings.json` (auto-initialised, editable)

```jsonc
{
  "defaultModel": "qwen3.6-27b",         // launched when you just type `pi-agent`
  "defaultProvider": "starbuck",         // Qwen on OpenAI channel
  "defaultThinkingLevel": "medium",      // moderate reasoning budget
  "theme": "dark",                       // TUI theme
  "hideThinkingBlock": false,            // show/hide reasoning in TUI
  "packages": [                           // extensions
    "<path-to>/pi-searxng-tools"
  ]
}
```

#### `~/.zshrc` (shell function + aliases)

```bash
export SEARXNG_URL="http://<searxng-host>:8888"

# ─────────────────────────────────────────────────────────────
# Pi Agent — method-prompt wrapper
# ─────────────────────────────────────────────────────────────

pi-agent() {
  command pi --append-system-prompt "$(cat <repo-path>/setup/method.md)" "$@"
}

# Convenience aliases (uncomment/edit to match your models):
pi-gemma() { pi-agent --provider vllm-anthropic --model gemma-4-12b-it --thinking high "$@"; }
pi-qwen()  { pi-agent --provider starbuck --model qwen3.6-27b --thinking high "$@"; }
```

### 5. (Optional) Web search tools

Install the custom SearXNG-based web tools:

```bash
git clone https://github.com/Romiltec/pi-searxng-tools
cd pi-searxng-tools
pi install .

# Remove the default Ollama web-search to avoid duplicates:
pi remove npm:@ollama/pi-web-search
```

Configure in `~/.zshrc`:
```bash
export SEARXNG_URL="http://<searxng-host>:8888"    # required
# export FIRECRAWL_URL="http://<firecrawl-host>:3002"  # optional: clean markdown fetch
# export FIRECRAWL_API_KEY="<key>"                      # only if Firecrawl requires auth
```

Add the package path to `~/.pi/agent/settings.json`:
```json
{ "packages": [ "<absolute-or-relative-path>/pi-searxng-tools" ] }
```

| Tool | Backend | Fallback |
|---|---|---|
| `web_search` | SearXNG JSON API | — |
| `web_fetch` | Firecrawl (clean markdown) | Plain HTTP fetch (if `FIRECRAWL_URL` unset) |

---

## Usage

### Interactive (TUI)

```bash
pi-agent                                    # default model (from settings.json: Qwen/starbuck)
pi-gemma                                    # Gemma 4 12B via Anthropic channel, thinking high
pi-qwen                                     # Qwen3.6-27B via OpenAI channel, thinking high
```

### Headless (one-shot)

```bash
pi-agent --print "refactor src/utils.js and run the tests"
pi-gemma --print "add input validation to src/api.js"
pi-qwen --print "design a REST API scaffold for users/products"
```

### Override any setting at runtime

```bash
pi-agent --provider vllm-anthropic --model gemma-4-12b-it --thinking medium
pi-agent --provider starbuck --thinking off --print "quick fix in main.cjs"
pi-agent -c                                 # continue previous session
pi-agent -r                                 # select session to resume
```

---

## Channel selection (the key optimization)

A coding agent must emit **clean tool calls**. The right channel per model is the #1 lever:

| Model family | Recommended channel | Thinking | Why |
|---|---|---|---|
| **Gemma** (4 12B) | `vllm-anthropic` | `high` | OpenAI tool-calls are **malformed** (`<\|tool_call\|>…` as text) with the `gemma4` parser. The Anthropic `/v1/messages` channel is clean. |
| **Qwen** (3.6-27B) | `starbuck` (OpenAI) | `medium` | Strong **native** OpenAI tool-calling. Coder variants are already strong; large thinking budget mostly costs tokens. |
| **Other models** | Test both | Start `high` | Run a bench ladder on each channel; keep the one that climbs. Drop `thinking` if the bench still passes (cheaper). |

---

## Reproduce the benchmark

```bash
cd bench && npm install && cd ..

# Node-judged ladders (fast, no browser):
bench/runner.sh bench/ladders/cli     pi-anthropic 3
bench/runner.sh bench/ladders/minilib pi-anthropic 3
bench/runner.sh bench/ladders/api     pi-anthropic 3

# Playwright-judged ladders (browser):
bench/runner.sh bench/ladders/todo    pi-anthropic 3
bench/runner.sh bench/ladders/arcade  pi-anthropic 5
```

The runner climbs rung by rung: each rung starts from the last green state, the agent makes
one small change, and on failure the exact judge output is fed back for up to K attempts.

**Override the benchmark's model/provider:**
```bash
PI_GEMMA_MODEL=qwen3.6-27b PI_GEMMA_PROVIDER=starbuck bench/runner.sh bench/ladders/cli starbuck 5
```

---

## How it works (the method)

The system prompt (`setup/method.md`) encodes five rules:

1. **Decompose** — break into smallest working increments; start from a working state.
2. **Read first** — understand existing structure before editing. Look, don't guess.
3. **Replicate structure** — copy the closest working example when adding something similar.
   Symmetry beats invention.
4. **One step at a time** — implement, then verify concretely. Don't break what worked.
5. **Test and iterate** — use exact failure output to fix only what's broken.

---

## What's inside the repo

| Path | Description |
|---|---|
| `setup/install.sh` | Interactive installer: registers providers + writes `pi-agent()` shell function |
| `setup/method.md` | The optimized system prompt (the method) |
| `bench/runner.sh` | Ladder-climbing benchmark (scaffolded mode) |
| `bench/oneshot.sh` | One-shot benchmark (no scaffold, raw capability) |
| `bench/ladders/` | 5 ladders: `arcade`, `minilib`, `cli`, `api`, `todo` |
| `bench/README.md` | Benchmark documentation and how to add ladders |
| `results/` | Published artifacts (playable arcade game + per-ladder reports) |
| `docs/SETUP.md` | Deep-dive: channel selection, per-model recipes, any-model template |
| `docs/FINDINGS.md` | Experiments and findings across agent harnesses |

---

## License

MIT — see [`LICENSE`](LICENSE).