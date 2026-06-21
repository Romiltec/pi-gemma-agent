#!/usr/bin/env bash
# install.sh — configure Pi to use a local OpenAI/Anthropic-compatible model (default: Gemma 4 12B via vLLM)
# and install the `pi-gemma` launcher.
#
# Override the endpoint/model:   VLLM_URL=http://host:port MODEL=my-model ./setup/install.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v jq >/dev/null || { echo "jq is required"; exit 1; }
command -v pi >/dev/null || echo "warning: 'pi' not found on PATH — install the Pi coding agent (https://pi.dev)"

VLLM_URL="${VLLM_URL:-http://100.64.0.39:8801}"
MODEL="${MODEL:-gemma-4-12b-it}"
PI_DIR="$HOME/.pi/agent"; mkdir -p "$PI_DIR"
MODELS="$PI_DIR/models.json"; [ -f "$MODELS" ] || echo '{}' > "$MODELS"

# Two providers pointing at the same vLLM endpoint. 'vllm-anthropic' is the recommended one:
# Gemma's tool-calls are emitted cleanly through the Anthropic Messages API, whereas the
# OpenAI-completions path can yield malformed tool-calls with some local builds.
NEW="$(jq -n --arg url "$VLLM_URL" --arg model "$MODEL" '{providers:{
  "vllm-anthropic":{name:"vLLM (Anthropic API)",baseUrl:$url,api:"anthropic-messages",apiKey:"local",authHeader:true,
    models:[{id:$model,name:$model,reasoning:false,input:["text"],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:131072,maxTokens:8192}]},
  "vllm":{name:"vLLM (OpenAI API)",baseUrl:($url+"/v1"),api:"openai-completions",apiKey:"local",authHeader:true,
    models:[{id:$model,name:$model,reasoning:false,input:["text"],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:131072,maxTokens:8192,compat:{maxTokensField:"max_tokens"}}]}}}')"
TMP="$(mktemp)"; jq --argjson new "$NEW" '.providers = ((.providers // {}) + $new.providers)' "$MODELS" > "$TMP" && mv "$TMP" "$MODELS"
echo "✓ Pi providers written to $MODELS  (endpoint: $VLLM_URL, model: $MODEL)"

BIN="${BIN_DIR:-$HOME/.local/bin}"; mkdir -p "$BIN"
ln -sf "$HERE/bin/pi-gemma" "$BIN/pi-gemma"
echo "✓ launcher installed: $BIN/pi-gemma  (ensure $BIN is on your PATH)"
echo
echo "Usage:"
echo "  pi-gemma                 # interactive coding agent on the local model"
echo "  pi-gemma -p 'task ...'   # headless"
echo "Env overrides: PI_GEMMA_MODEL, PI_GEMMA_THINKING (default high), PI_GEMMA_PROVIDER (default vllm-anthropic)"
