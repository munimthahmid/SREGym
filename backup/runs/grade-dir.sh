#!/usr/bin/env bash
# Grade every *_arms.json in a directory with SREGym's judge (one judge bridge). Usage: grade-dir.sh DIR
OUT="$1"
cd /home/priyo_software/sregym/SREGym-v2eval || exit 1
args=()
for f in "$OUT"/*_arms.json; do p=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['problem_id'])" "$f"); args+=(--problem "$p" "$f"); done
echo "[$(date -Is)] grade start ${#args[@]}" >> "$OUT/progress.log"
SREGYM_JUDGE_STARTUP_TIMEOUT=1800 .venv/bin/python -m clients.jev_diag.v2_eval.grade "${args[@]}" > "$OUT/grade.log" 2>&1
echo "[$(date -Is)] grade done exit=$?" >> "$OUT/progress.log"
