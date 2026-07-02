#!/usr/bin/env bash
# oneshot.sh — build the WHOLE target in ONE prompt (no scaffold), score the best contiguous rung.
#
# Usage:   bench/oneshot.sh <ladder-dir> [N-samples]
# Example: bench/oneshot.sh bench/ladders/arcade 3
#
# Complements runner.sh (scaffold mode). This is the "hard mode": it measures raw one-shot capability,
# with NO small steps and NO feedback loop. Two things make it a FAIR one-shot test:
#
#  1. Coherent spec, not incremental prompts. The per-rung prompts are written for the ladder
#     ("Add ONLY the menu, no gameplay yet", "keep the others working"). Concatenated into a single
#     "build everything" prompt they CONTRADICT each other and tank the result. Here we pass the full
#     requirements but explicitly neutralize the incremental wording ("implement EVERYTHING together").
#
#  2. Write-guard. Some models describe the code in prose/markdown instead of calling the write tool.
#     The target then stays as the seed and every rung fails (a false R0). We detect "file not modified"
#     and flag it, so a narrated-but-not-written answer is not mistaken for real output.
#
# NOTE: one-shot is single-sample and high-variance; use N>1 (best-of / pass@k) and a low temperature
# for a stable signal. Scaffold mode (runner.sh) remains the reliable ranking metric.
#
# Provider/model env-overridable (defaults: local Gemma via vLLM), same as runner.sh.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER_DIR="${1:?usage: oneshot.sh <ladder-dir> [N-samples]}"
N="${2:-1}"
CAP="${BENCH_CAP_SECS:-600}"
MODEL="${PI_GEMMA_MODEL:-gemma-4-12b-it}"
PROVIDER="${PI_GEMMA_PROVIDER:-vllm}"
THINKING="${PI_GEMMA_THINKING:-high}"

L="$LADDER_DIR/ladder.json"
CHECK="$LADDER_DIR/$(jq -r '.check // "check.mjs"' "$L")"
NAME="$(jq -r '.name' "$L")"
TARGET="$(jq -r '.target' "$L")"
SEED="$LADDER_DIR/$(jq -r '.seed' "$L")"
CTX="$(jq -r '.context // ""' "$L")"
NR="$(jq '.rungs | length' "$L")"
REQ="$(jq -r '.rungs[] | "- \(.title): \(.prompt)"' "$L")"

md5() { md5sum "$1" 2>/dev/null | awk '{print $1}' || md5 -q "$1"; }
_cap() { ( "$@" ) & local p=$!; ( sleep "$CAP"; kill -TERM "$p" 2>/dev/null ) & local w=$!; wait "$p" 2>/dev/null; kill "$w" 2>/dev/null; }

echo "== ONE-SHOT '$NAME' | model=$MODEL provider=$PROVIDER | N=$N cap=${CAP}s =="
best_overall=0
for ((s=1; s<=N; s++)); do
  W="$SELF/.oneshot/${MODEL//\//_}/$NAME/s$s"; rm -rf "$W"; mkdir -p "$W"; cp "$SEED" "$W/$TARGET"
  before="$(md5 "$W/$TARGET")"
  PROMPT="$CTX

Build the COMPLETE $TARGET implementing ALL of the following requirements TOGETHER in ONE coherent file.
These are FEATURES that must ALL be present at once. IGNORE any incremental wording such as
'Add ONLY', 'no ... yet', 'each step', or 'keep the others working' — implement EVERYTHING together now:
$REQ
Write the entire file now, complete and working, with all features integrated."
  ( cd "$W" && _cap command pi --provider "$PROVIDER" --model "$MODEL" --thinking "$THINKING" -p "$PROMPT" ) > "$W/agent.log" 2>&1
  after="$(md5 "$W/$TARGET")"
  best=0
  if [ "$before" = "$after" ]; then
    echo "  sample $s: WARN — '$TARGET' was NOT modified (model likely described the code instead of writing it) -> R0"
  else
    for ((r=1; r<=NR; r++)); do node "$CHECK" "$W/$TARGET" "$r" >/dev/null 2>&1 && { [ "$r" -eq $((best+1)) ] && best=$r; }; done
    echo "  sample $s: best contiguous R$best / $NR"
  fi
  [ "$best" -gt "$best_overall" ] && best_overall=$best
done
echo "ONESHOT $MODEL '$NAME' -> best R$best_overall / $NR (over $N sample/s)"
