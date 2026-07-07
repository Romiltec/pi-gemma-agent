#!/usr/bin/env bash
# install.sh — configure Pi to use a local OpenAI/Anthropic-compatible model and install
# the `pi-gemma` launcher. Additive & multi-endpoint: run once per model/endpoint.
#
#   # default endpoint, providers 'vllm' + 'vllm-anthropic':
#   MODEL=gemma-4-12b-it VLLM_URL=http://localhost:8000 ./setup/install.sh
#
#   # a second model on a DIFFERENT endpoint gets its own providers (NAME suffix):
#   NAME=qwen MODEL=qwen3.6-27b VLLM_URL=http://otherhost:8000 REASONING=true ./setup/install.sh
#   # -> providers 'vllm-qwen' (OpenAI) and 'vllm-qwen-anthropic' (Anthropic)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v jq >/dev/null || { echo "jq is required"; exit 1; }
command -v pi >/dev/null || echo "warning: 'pi' not found on PATH — install the Pi coding agent (https://pi.dev)"

VLLM_URL="${VLLM_URL:-http://localhost:8000}"
MODEL="${MODEL:-gemma-4-12b-it}"
CTX="${CTX:-131072}"
MAXTOK="${MAXTOK:-8192}"
REASONING="${REASONING:-false}"
NAME="${NAME:-}"
if [ -n "$NAME" ]; then PROV_OAI="vllm-$NAME"; PROV_ANT="vllm-$NAME-anthropic"; else PROV_OAI="vllm"; PROV_ANT="vllm-anthropic"; fi

PI_DIR="$HOME/.pi/agent"; mkdir -p "$PI_DIR"
MODELS="$PI_DIR/models.json"; [ -f "$MODELS" ] || echo '{}' > "$MODELS"

TMP="$(mktemp)"
jq --arg url "$VLLM_URL" --arg id "$MODEL" --argjson ctx "$CTX" --argjson mt "$MAXTOK" \
   --argjson reasoning "$REASONING" --arg poai "$PROV_OAI" --arg pant "$PROV_ANT" '
  def upsert($arr; $m): (($arr // []) | map(select(.id != $m.id))) + [$m];
  .providers[$pant] = ((.providers[$pant] // {})
    | .name = "vLLM Anthropic (\($pant))" | .baseUrl = $url | .api = "anthropic-messages" | .apiKey = "local" | .authHeader = true
    | .models = upsert(.models; {id:$id, name:$id, reasoning:$reasoning, input:["text"],
        cost:{input:0,output:0,cacheRead:0,cacheWrite:0}, contextWindow:$ctx, maxTokens:$mt}))
  | .providers[$poai] = ((.providers[$poai] // {})
    | .name = "vLLM OpenAI (\($poai))" | .baseUrl = ($url + "/v1") | .api = "openai-completions" | .apiKey = "local" | .authHeader = true
    | .models = upsert(.models; {id:$id, name:$id, reasoning:$reasoning, input:["text"],
        cost:{input:0,output:0,cacheRead:0,cacheWrite:0}, contextWindow:$ctx, maxTokens:$mt, compat:{maxTokensField:"max_tokens"}}))
' "$MODELS" > "$TMP" && mv "$TMP" "$MODELS"
echo "✓ registered model '$MODEL' on providers '$PROV_ANT' and '$PROV_OAI'  (endpoint: $VLLM_URL, ctx: $CTX, reasoning: $REASONING)"

BIN="${BIN_DIR:-$HOME/.local/bin}"; mkdir -p "$BIN"
ln -sf "$HERE/bin/pi-gemma" "$BIN/pi-gemma"
echo "✓ launcher installed: $BIN/pi-gemma  (ensure $BIN is on your PATH)"
echo
echo "Use this model:"
echo "  PI_GEMMA_PROVIDER=$PROV_ANT PI_GEMMA_MODEL='$MODEL' pi-gemma          # Anthropic channel"
echo "  PI_GEMMA_PROVIDER=$PROV_OAI PI_GEMMA_MODEL='$MODEL' pi-gemma          # OpenAI channel"
echo "See docs/SETUP.md for per-model tuning."
