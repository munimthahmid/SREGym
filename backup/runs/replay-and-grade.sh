#!/usr/bin/env bash
# Offline arms on saved recordings, then grade every arm with SREGym's judge. Usage: replay-and-grade.sh OUT LABELS ARMS
OUT="$1"; LABELS="$2"; ARMS="$3"
IDX="/home/priyo_software/Priyo Work/jev-v2-rethink/runs-index.tsv"
cd /home/priyo_software/sregym/SREGym-v2eval || exit 1
echo "[$(date -Is)] replay start" >> "$OUT/progress.log"
OPENROUTER_API_KEY="$(cat ~/.config/openrouter/key)" .venv/bin/python -m clients.jev_diag.v2_eval.replay_arms \
  --index "$IDX" --labels "$LABELS" --arms "$ARMS" --out "$OUT" >> "$OUT/replay.log" 2>&1
echo "[$(date -Is)] replay done" >> "$OUT/progress.log"
args=()
for f in "$OUT"/*_arms.json; do p=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['problem_id'])" "$f"); args+=(--problem "$p" "$f"); done
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  .venv/bin/python -m clients.jev_diag.v2_eval.grade "${args[@]}" > "$OUT/grade.log" 2>&1
echo "[$(date -Is)] grade done exit=$?" >> "$OUT/progress.log"
