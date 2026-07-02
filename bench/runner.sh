#!/usr/bin/env bash
# runner.sh — generic ladder-climbing benchmark with an outer retry+feedback loop.
#
# Usage:   bench/runner.sh <ladder-dir> [agent] [K-attempts]
# Example: bench/runner.sh bench/ladders/arcade pi-anthropic 5
#
# A "ladder" is a directory containing:
#   ladder.json   { name, target, seed, context, rungs:[{id,title,prompt}] }
#   check.mjs     a judge:  node check.mjs <target-file> <rung> [--json]  (exit 0 = rung passed)
#   seed/<file>   the starting target file
#
# The runner drives the agent through the rungs: each rung starts from the last
# green target, the agent gets one small step, and on failure the exact check
# output is fed back for up to K attempts. Implements the "small verified steps"
# method. Provider/model are env-overridable (defaults: local Gemma via vLLM).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF/.." && pwd)"
METHOD="$ROOT/setup/method.md"

LADDER_DIR="${1:?usage: runner.sh <ladder-dir> [agent] [K]}"
AGENT="${2:-pi-anthropic}"
K="${3:-5}"
CAP="${BENCH_CAP_SECS:-220}"
MODEL="${PI_GEMMA_MODEL:-gemma-4-12b-it}"
THINKING="${PI_GEMMA_THINKING:-high}"

LADDER="$LADDER_DIR/ladder.json"
CHECK="$LADDER_DIR/$(jq -r '.check // "check.mjs"' "$LADDER")"
NAME="$(jq -r '.name' "$LADDER")"
TARGET="$(jq -r '.target' "$LADDER")"
SEEDREL="$(jq -r '.seed' "$LADDER")"
CONTEXT="$(jq -r '.context // ""' "$LADDER")"
N="$(jq '.rungs | length' "$LADDER")"

WORK="$SELF/.work/$NAME"; mkdir -p "$WORK"
CSV="$WORK/raw.csv"; [ -f "$CSV" ] || echo "agent,rung,pass,score,attempts,seconds" > "$CSV"
GREEN="$WORK/${AGENT}_green/$TARGET"; mkdir -p "$(dirname "$GREEN")"
grep -q "^$AGENT," "$CSV" || cp "$LADDER_DIR/$SEEDREL" "$GREEN"

_cap() { ( "$@" ) & local p=$!; ( sleep "$CAP"; kill -TERM "$p" 2>/dev/null ) & local w=$!; wait "$p" 2>/dev/null; kill "$w" 2>/dev/null; }
invoke() { # $1 sandbox $2 prompt
  local prov=vllm-anthropic; [ "$AGENT" = "pi" ] && prov=vllm
  ( cd "$1" && _cap command pi --provider "$prov" --model "$MODEL" --thinking "$THINKING" \
      --append-system-prompt "$(cat "$METHOD")" -p "$2" ) > "$1/agent.log" 2>&1
}

echo "== ladder '$NAME' | agent=$AGENT model=$MODEL thinking=$THINKING | K=$K cap=${CAP}s =="
for ((r=1; r<=N; r++)); do
  grep -q "^$AGENT,$r," "$CSV" && { echo "skip $AGENT R$r"; continue; }
  PROMPT_RUNG="$(jq -r --argjson id "$r" '.rungs[]|select(.id==$id)|.prompt' "$LADDER")"
  SBX="$WORK/${AGENT}_r${r}"; pass=0; attempts=0; feedback=""; t0=$(date +%s)
  for ((k=1; k<=K; k++)); do
    attempts=$k
    rm -rf "$SBX"; mkdir -p "$SBX"; cp "$GREEN" "$SBX/$TARGET"
    printf '#!/usr/bin/env bash\nexec node "%s" "$@"\n' "$CHECK" > "$SBX/check.sh"; chmod +x "$SBX/check.sh"
    before="$(md5sum "$SBX/$TARGET" 2>/dev/null | awk '{print $1}' || md5 -q "$SBX/$TARGET")"
    TASK="$CONTEXT
CURRENT STEP: $PROMPT_RUNG
Work ONLY on this step. Read $TARGET first, then make the smallest change that satisfies it; do not break what already works.
$feedback
Verify with: ./check.sh $TARGET $r  (it must exit successfully)."
    invoke "$SBX" "$TASK"
    # write-guard: some models describe the code instead of writing it via a tool → the file never changes.
    after="$(md5sum "$SBX/$TARGET" 2>/dev/null | awk '{print $1}' || md5 -q "$SBX/$TARGET")"
    [ "$before" = "$after" ] && echo "  $AGENT R$r attempt $k WARN: $TARGET not modified (model may have narrated the code instead of writing it)"
    OUT="$(node "$CHECK" "$SBX/$TARGET" "$r" 2>/dev/null)"; rc=$?
    if [ "$rc" = 0 ]; then pass=1; cp "$SBX/$TARGET" "$GREEN"; break; fi
    feedback="The previous attempt did NOT pass. Check output (fix ONLY these FAILs, keep what works):
$(echo "$OUT" | grep -iE 'FAIL|rung|error')"
    echo "  $AGENT R$r attempt $k FAIL -> retry with feedback"
  done
  t1=$(date +%s)
  SCORE="$(node "$CHECK" "$SBX/$TARGET" "$r" --json 2>/dev/null | jq -r '.score' 2>/dev/null)"
  echo "$AGENT,$r,$pass,${SCORE:-0},$attempts,$((t1-t0))" >> "$CSV"
  echo "$AGENT R$r -> pass=$pass (attempts=$attempts, $((t1-t0))s)"
  [ "$pass" = 1 ] || { echo "$AGENT stops at R$r"; break; }
done
echo "DONE $AGENT on '$NAME'"
