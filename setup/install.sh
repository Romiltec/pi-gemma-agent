#!/usr/bin/env bash
# install.sh — configure Pi to use a local OpenAI/Anthropic-compatible model and install
# the `pi-gemma` launcher. Additive: run it once per model to register several models.
#
#   MODEL=gemma-4-12b-it VLLM_URL=http://localhost:8000 ./setup/install.sh
#   MODEL=qwen2.5-coder-14b VLLM_URL=http://localhost:8000 CTX=131072 ./setup/install.sh
#
# It writes/updates two providers pointing at the same endpoint — 'vllm-anthropic'
# (Anthropic Messages API) and 'vllm' (OpenAI Chat Completions) — and upserts MODEL into
# both. Pick the channel per model at runtime with PI_GEMMA_PROVIDER (see docs/SETUP.md).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v jq >/dev/null || { echo "jq is required"; exit 1; }
command -v pi >/dev/null || echo "warning: 'pi' not found on PATH — install the Pi coding agent (https://pi.dev)"

VLLM_URL="${VLLM_URL:-http://localhost:8000}"
MODEL="${MODEL:-gemma-4-12b-it}"
CTX="${CTX:-131072}"
MAXTOK="${MAXTOK:-8192}"
PI_DIR="$HOME/.pi/agent"; mkdir -p "$PI_DIR"
MODELS="$PI_DIR/models.json"; [ -f "$MODELS" ] || echo '{}' > "$MODELS"

TMP="$(mktemp)"
jq --arg url "$VLLM_URL" --arg id "$MODEL" --argjson ctx "$CTX" --argjson mt "$MAXTOK" '
  def upsert($arr; $m): (($arr // []) | map(select(.id != $m.id))) + [$m];
  .providers["vllm-anthropic"] = ((.providers["vllm-anthropic"] // {})
    | .name = "vLLM (Anthropic API)" | .baseUrl = $url | .api = "anthropic-messages" | .apiKey = "local" | .authHeader = true
    | .models = upsert(.models; {id:$id, name:$id, reasoning:false, input:["text"],
        cost:{input:0,output:0,cacheRead:0,cacheWrite:0}, contextWindow:$ctx, maxTokens:$mt}))
  | .providers["vllm"] = ((.providers["vllm"] // {})
    | .name = "vLLM (OpenAI API)" | .baseUrl = ($url + "/v1") | .api = "openai-completions" | .apiKey = "local" | .authHeader = true
    | .models = upsert(.models; {id:$id, name:$id, reasoning:false, input:["text"],
        cost:{input:0,output:0,cacheRead:0,cacheWrite:0}, contextWindow:$ctx, maxTokens:$mt, compat:{maxTokensField:"max_tokens"}}))
' "$MODELS" > "$TMP" && mv "$TMP" "$MODELS"
echo "✓ registered model '$MODEL' on providers 'vllm-anthropic' and 'vllm'  (endpoint: $VLLM_URL, ctx: $CTX)"

BIN="${BIN_DIR:-$HOME/.local/bin}"; mkdir -p "$BIN"
ln -sf "$HERE/bin/pi-gemma" "$BIN/pi-gemma"
echo "✓ launcher installed: $BIN/pi-gemma  (ensure $BIN is on your PATH)"
echo
echo "Use it:"
echo "  pi-gemma                                  # default model on the Anthropic channel"
echo "  PI_GEMMA_MODEL='$MODEL' pi-gemma          # pick a registered model"
echo "  PI_GEMMA_PROVIDER=vllm PI_GEMMA_MODEL='$MODEL' pi-gemma   # OpenAI channel (recommended for Qwen)"
echo "See docs/SETUP.md for per-model tuning (Gemma, Qwen, and any model)."
