#!/usr/bin/env bash
# install.sh — Register a local model with Pi and install the pi-agent() launcher.
#
# Run once per model/endpoint. Additive: multiple models coexist.
#
# Non-interactive (env vars):
#   MODEL=gemma-4-12b-it VLLM_URL=http://<host>:8801 ./setup/install.sh
#   NAME=qwen MODEL=qwen3.6-27b VLLM_URL=http://<host>:8000 REASONING=true ./setup/install.sh
#
# Interactive (no env vars):
#   ./setup/install.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_DIR="$HOME/.pi/agent"
MODELS="$PI_DIR/models.json"
SETTINGS="$PI_DIR/settings.json"

##############################################################################
# Helpers
##############################################################################
_ensure() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' is required but not found on PATH."
    [ "$1" = "pi" ] && echo "  Install: https://pi.dev"
    [ "$1" = "jq" ] && echo "  Install: brew install jq"
    exit 1
  }
}

_read() {
  local prompt="${1:?}" default="${2:-}"
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default"
  else
    printf "%s: " "$prompt"
  fi
  IFS= read -r reply
  echo "${reply:-$default}"
}

_confirm() {
  local prompt="${1:?}" default_yes="${2:-true}"
  local default_str
  [ "$default_yes" = "true" ] && default_str="Y/n" || default_str="y/N"
  printf "%s [%s]: " "$prompt" "$default_str"
  IFS= read -r reply
  case "$reply" in
    ""|"[Yy]"|"[Yy]es") return 0 ;;
    *) return 1 ;;
  esac
}

##############################################################################
# Pre-flight checks
##############################################################################
_ensure pi
_ensure jq
mkdir -p "$PI_DIR"
[ -f "$MODELS" ] || echo '{}' > "$MODELS"

##############################################################################
# Collect model parameters (env vars or interactive)
##############################################################################
IS_INTERACTIVE=false
if [ -z "${VLLM_URL:-}" ] || [ -z "${MODEL:-}" ]; then
  IS_INTERACTIVE=true
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  Pi Agent — Register a local model                     ║"
  echo "║  Press Enter to accept the default (in brackets)        ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
fi

# ── Provider name ──────────────────────────────────────────────────────────
# If NAME is provided, providers become "vllm-<NAME>" / "vllm-<NAME>-anthropic"
# or "<NAME>" / "<NAME>-anthropic". If empty, use defaults "vllm" / "vllm-anthropic".
PROVIDER_BASE="${NAME:-}"
if [ "$IS_INTERACTIVE" = true ]; then
  PROVIDER_BASE=$(_read "Provider name (leave empty for 'vllm', e.g. 'qwen' for a 2nd model)" "vllm")
fi
[ -z "$PROVIDER_BASE" ] && PROVIDER_BASE="vllm"
PROV_OAI="$PROVIDER_BASE"
PROV_ANT="${PROVIDER_BASE}-anthropic"

# ── Model ID ───────────────────────────────────────────────────────────────
MODEL_ID="${MODEL:-}"
if [ "$IS_INTERACTIVE" = true ]; then
  MODEL_ID=$(_read "Model ID (as served by vLLM, --served-model-name)" "gemma-4-12b-it")
fi
[ -z "$MODEL_ID" ] && MODEL_ID="gemma-4-12b-it"

# ── Detect model family for API recommendation ─────────────────────────────
detect_family() {
  local id="$1"
  case "$id" in
    *gemma*|*Gemma*|*GEMMA*) echo "gemma" ;;
    *qwen*|*Qwen*|*QWEN*)    echo "qwen" ;;
    *llama*|*Llama*|*LLAMA*) echo "llama" ;;
    *mistral*|*Mistral*)     echo "mistral" ;;
    *)                        echo "unknown" ;;
  esac
}

FAMILY="$(detect_family "$MODEL_ID")"

# ── Preferred API channel ──────────────────────────────────────────────────
# Gemma: anthropic-messages (OpenAI tool-calls are malformed with gemma4 parser)
# Qwen: openai-completions (native tool-calling is clean)
# Others: default to openai, but let user override
DEFAULT_API="openai-completions"
[ "$FAMILY" = "gemma" ] && DEFAULT_API="anthropic-messages"

PREFERRED_API="${PREFERRED_API:-$DEFAULT_API}"
if [ "$IS_INTERACTIVE" = true ]; then
  echo ""
  echo "  Recommended API for '$MODEL_ID' ($FAMILY family): $DEFAULT_API"
  [ "$FAMILY" = "gemma" ] && echo "  → Gemma's OpenAI tool-calls are malformed; Anthropic channel is cleaner."
  [ "$FAMILY" = "qwen" ] && echo "  → Qwen has clean native OpenAI tool-calling."
  echo ""
  API_CHOICE=$(_read "API to register (openai-completions / anthropic-messages / both)" "$DEFAULT_API")
  case "$API_CHOICE" in
    openai-completions) PREFERRED_API="openai-completions" ;;
    anthropic-messages) PREFERRED_API="anthropic-messages" ;;
    both|"") PREFERRED_API="both" ;;
    *) PREFERRED_API="$API_CHOICE" ;;
  esac
fi

# ── vLLM URL ───────────────────────────────────────────────────────────────
ENDPOINT_URL="${VLLM_URL:-}"
if [ "$IS_INTERACTIVE" = true ]; then
  ENDPOINT_URL=$(_read "vLLM endpoint URL (http://host:port, no trailing /v1)" "http://localhost:8000")
fi
[ -z "$ENDPOINT_URL" ] && ENDPOINT_URL="http://localhost:8000"
# Strip trailing /v1 if present (install script adds it for OpenAI channel)
ENDPOINT_URL="${ENDPOINT_URL%/v1}"
ENDPOINT_URL="${ENDPOINT_URL%/}"

# ── Context window ─────────────────────────────────────────────────────────
CTX_SIZE="${CTX:-}"
if [ "$IS_INTERACTIVE" = true ]; then
  CTX_SIZE=$(_read "Context window (tokens)" "131072")
fi
[ -z "$CTX_SIZE" ] && CTX_SIZE=131072

# ── Max tokens ──────────────────────────────────────────────────────────────
MAX_TOK="${MAXTOK:-}"
if [ "$IS_INTERACTIVE" = true ]; then
  MAX_TOK=$(_read "Max response tokens" "8192")
fi
[ -z "$MAX_TOK" ] && MAX_TOK=8192

# ── Reasoning ───────────────────────────────────────────────────────────────
HAS_REASONING="${REASONING:-false}"
if [ "$IS_INTERACTIVE" = true ]; then
  if [ "$FAMILY" = "qwen" ]; then
    _confirm "Is this a reasoning model (emits <thinking> blocks)?" true && HAS_REASONING=true || HAS_REASONING=false
  else
    _confirm "Is this a reasoning model (emits <thinking> blocks)?" false && HAS_REASONING=true || HAS_REASONING=false
  fi
fi

# ── Thinking level default ─────────────────────────────────────────────────
DEFAULT_THINKING="high"
[ "$FAMILY" = "qwen" ] && DEFAULT_THINKING="medium"   # Qwen reasons natively, less Pi thinking needed
if [ "$IS_INTERACTIVE" = true ]; then
  THINKING_LVL=$(_read "Default thinking level for this model (off/minimal/low/medium/high/xhigh)" "$DEFAULT_THINKING")
  [ -n "$THINKING_LVL" ] && DEFAULT_THINKING="$THINKING_LVL"
fi

##############################################################################
# Summary
##############################################################################
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  Configuration summary                              │"
echo "├─────────────────────────────────────────────────────┤"
printf "│  %-22s │ %s              │\n" "Model ID" "$MODEL_ID"
printf "│  %-22s │ %-17s │\n" "Family" "$FAMILY"
printf "│  %-22s │ %-17s │\n" "Endpoint" "$ENDPOINT_URL"
printf "│  %-22s │ %-17s │\n" "API" "$PREFERRED_API"
printf "│  %-22s │ %-17s │\n" "Provider (OpenAI)" "$PROV_OAI"
printf "│  %-22s │ %-17s │\n" "Provider (Anthropic)" "$PROV_ANT"
printf "│  %-22s │ %s              │\n" "Context window" "$CTX_SIZE"
printf "│  %-22s │ %s              │\n" "Max tokens" "$MAX_TOK"
printf "│  %-22s │ %s              │\n" "Reasoning" "$HAS_REASONING"
printf "│  %-22s │ %s              │\n" "Default thinking" "$DEFAULT_THINKING"
echo "└─────────────────────────────────────────────────────┘"

##############################################################################
# Verify endpoint
##############################################################################
if [ "$IS_INTERACTIVE" = true ] && _confirm "Verify endpoint is reachable?" false; then
  echo -n "  Probing $ENDPOINT_URL/v1/models … "
  if MODELS_LIST="$(curl -sf --max-time 5 "$ENDPOINT_URL/v1/models" 2>/dev/null)"; then
    SERVER_IDS=$(echo "$MODELS_LIST" | jq -r '.data[].id' 2>/dev/null | tr '\n' ' ')
    echo "OK — found: $SERVER_IDS"
    # Check our model is listed
    if echo "$SERVER_IDS" | grep -qw "$MODEL_ID"; then
      echo "  ✓ '$MODEL_ID' confirmed on server"
    else
      echo "  ⚠ '$MODEL_ID' not found in server model list (might still work if --served-model-name differs)"
    fi
  else
    echo "⚠ Cannot reach endpoint — proceeding anyway (might be on a private network)"
  fi
fi

##############################################################################
# Register providers in models.json
##############################################################################
echo ""
echo "Writing providers to $MODELS …"
TMP="$(mktemp)"

# Build the jq filter based on which API(s) to register
if [ "$PREFERRED_API" = "both" ] || [ "$PREFERRED_API" = "anthropic-messages" ]; then
  ANT_FILTER='
    .providers[$pant] = ((.providers[$pant] // {})
      | .name = "vLLM Anthropic (\($pant))"
      | .baseUrl = $url
      | .api = "anthropic-messages"
      | .apiKey = "local"
      | .authHeader = true
      | .models = upsert(.models; {
          id: $id, name: $id,
          reasoning: $reasoning,
          input: ["text"],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow: $ctx,
          maxTokens: $mt
        })
    )
  '
fi

OAI_FILTER='
    .providers[$poai] = ((.providers[$poai] // {})
      | .name = "vLLM OpenAI (\($poai))"
      | .baseUrl = ($url + "/v1")
      | .api = "openai-completions"
      | .apiKey = "local"
      | .authHeader = true
      | .models = upsert(.models; {
          id: $id, name: $id,
          reasoning: $reasoning,
          input: ["text"],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow: $ctx,
          maxTokens: $mt,
          compat: { maxTokensField: "max_tokens" }
        })
    )
  '

if [ "$PREFERRED_API" = "both" ]; then
  jq --arg url "$ENDPOINT_URL" \
     --arg id "$MODEL_ID" \
     --argjson ctx "$CTX_SIZE" \
     --argjson mt "$MAX_TOK" \
     --argjson reasoning "$HAS_REASONING" \
     --arg poai "$PROV_OAI" \
     --arg pant "$PROV_ANT" \
     "def upsert(\$arr; \$m): ((\$arr // []) | map(select(.id != \$m.id))) + [\$m]; $ANT_FILTER | $OAI_FILTER" \
     "$MODELS" > "$TMP"
elif [ "$PREFERRED_API" = "anthropic-messages" ]; then
  jq --arg url "$ENDPOINT_URL" \
     --arg id "$MODEL_ID" \
     --argjson ctx "$CTX_SIZE" \
     --argjson mt "$MAX_TOK" \
     --argjson reasoning "$HAS_REASONING" \
     --arg pant "$PROV_ANT" \
     "def upsert(\$arr; \$m): ((\$arr // []) | map(select(.id != \$m.id))) + [\$m]; $ANT_FILTER" \
     "$MODELS" > "$TMP"
else
  jq --arg url "$ENDPOINT_URL" \
     --arg id "$MODEL_ID" \
     --argjson ctx "$CTX_SIZE" \
     --argjson mt "$MAX_TOK" \
     --argjson reasoning "$HAS_REASONING" \
     --arg poai "$PROV_OAI" \
     "def upsert(\$arr; \$m): ((\$arr // []) | map(select(.id != \$m.id))) + [\$m]; $OAI_FILTER" \
     "$MODELS" > "$TMP"
fi

mv "$TMP" "$MODELS"

# Determine which provider(s) were actually registered
REGISTERED_PROVIDERS=""
[ "$PREFERRED_API" = "both" ] || [ "$PREFERRED_API" = "openai-completions" ] && REGISTERED_PROVIDERS="$PROV_OAI"
if [ -n "$REGISTERED_PROVIDERS" ] && { [ "$PREFERRED_API" = "both" ] || [ "$PREFERRED_API" = "anthropic-messages" ]; }; then
  REGISTERED_PROVIDERS="$REGISTERED_PROVIDERS $PROV_ANT"
elif [ "$PREFERRED_API" = "anthropic-messages" ]; then
  REGISTERED_PROVIDERS="$PROV_ANT"
fi

echo "✓ Registered '$MODEL_ID' on provider(s): $REGISTERED_PROVIDERS"

##############################################################################
# Initialise settings.json (first run only)
##############################################################################
if [ ! -f "$SETTINGS" ]; then
  echo '{}' | jq \
    --arg dm "$MODEL_ID" \
    --arg dp "$(echo $REGISTERED_PROVIDERS | awk '{print $1}')" \
    --arg dth "$DEFAULT_THINKING" \
    '{
      defaultModel: $dm,
      defaultProvider: $dp,
      defaultThinkingLevel: $dth,
      theme: "dark",
      hideThinkingBlock: false
    }' > "$SETTINGS"
  echo "✓ Created $SETTINGS (default model: $MODEL_ID, provider: $(echo $REGISTERED_PROVIDERS | awk '{print $1}'))"
fi

##############################################################################
# Install the pi-agent() shell function
##############################################################################
install_shell_function() {
  local rcfile="$HOME/.zshrc"
  # Fallback to .bashrc if zsh not available
  command -v zsh >/dev/null 2>&1 || rcfile="$HOME/.bashrc"

  local func_block="
# ─────────────────────────────────────────────────────────────────────────
# Pi Agent — method-prompt wrapper (installed by pi-gemma-agent/setup/install.sh)
# Removes the need for custom binaries: just 'pi-agent' with --provider/--model
# ─────────────────────────────────────────────────────────────────────────

pi-agent() {
  command pi --append-system-prompt \"\$(cat '$HERE/setup/method.md')\" \"\$@\"
}

# Convenience aliases (uncomment/edit to match your registered models):
pi-gemma() { pi-agent --provider vllm-anthropic --model gemma-4-12b-it --thinking high \"\$@\"; }
pi-qwen()  { pi-agent --provider starbuck --model qwen3.6-27b --thinking high \"\$@\"; }
"

  # Check if already installed (avoid duplicates)
  if grep -q "pi-agent()" "$rcfile" 2>/dev/null; then
    echo "  Shell function already in $rcfile — skipping"
    return
  fi

  echo "$func_block" >> "$rcfile"
  echo "✓ Shell function 'pi-agent()' installed in $rcfile"
}

install_shell_function

##############################################################################
# Cleanup old binaries (if they existed)
##############################################################################
cleanup_old_binaries() {
  local cleaned=false
  for old_bin in "$HOME/.local/bin/pi-gemma" "$HOME/.local/bin/pi-starbuck"; do
    if [ -L "$old_bin" ] || [ -f "$old_bin" ]; then
      rm -f "$old_bin"
      echo "✓ Removed old binary: $old_bin"
      cleaned=true
    fi
  done
}

cleanup_old_binaries

##############################################################################
# Post-install instructions
##############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " Reload your shell, then use:"
echo ""
echo "   pi-agent                                    # default model (from settings.json)"
echo "   pi-agent --provider $PROV_OAI --model $MODEL_ID --thinking $DEFAULT_THINKING"
echo "   pi-agent --print \"your task here\"           # headless"
echo ""
echo " Registered provider(s): $REGISTERED_PROVIDERS"
echo " Recommended API:        $PREFERRED_API"
if [ "$FAMILY" = "gemma" ]; then
  echo " 💡 Gemma tip: use '$PROV_ANT' (Anthropic channel) —"
  echo "   Gemma's OpenAI tool-calls are malformed with the gemma4 parser."
fi
if [ "$FAMILY" = "qwen" ]; then
  echo " 💡 Qwen tip: use '$PROV_OAI' (OpenAI channel) —"
  echo "   Qwen has clean native OpenAI tool-calling."
fi
echo ""
echo " Alias shortcuts (in $rcfile, uncomment if needed):"
echo "   pi-gemma    → Gemma 4 12B via Anthropic channel"
echo "   pi-qwen     → Qwen3.6-27B via OpenAI channel"
echo ""
echo " To register another model on a different endpoint:"
echo "   NAME=<label> MODEL=<id> VLLM_URL=<url> ./setup/install.sh"
echo ""