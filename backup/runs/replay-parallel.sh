#!/usr/bin/env bash
# Offline arms on saved recordings in N parallel processes, then one parallel grading pass.
# Usage: replay-parallel.sh OUT LABELS(comma) ARMS [N]
OUT="$1"; LABELS="$2"; ARMS="$3"; N="${4:-4}"
IDX="/home/priyo_software/Priyo Work/jev-v2-rethink/runs-index.tsv"
cd "${SREGYM_EVAL_DIR:-/home/priyo_software/sregym/SREGym-v2eval}" || exit 1
echo "[$(date -Is)] replay start ($N parallel)" >> "$OUT/progress.log"
IFS=, read -ra ALL <<< "$LABELS"
for ((k = 0; k < N; k++)); do
  part=(); for ((i = k; i < ${#ALL[@]}; i += N)); do part+=("${ALL[i]}"); done
  [ ${#part[@]} -eq 0 ] && continue
  (IFS=,; OPENROUTER_API_KEY="$(cat ~/.config/openrouter/key)" /home/priyo_software/sregym/SREGym-v2eval/.venv/bin/python -m clients.jev_diag.v2_eval.replay_arms \
    --index "$IDX" --labels "${part[*]}" --arms "$ARMS" --out "$OUT" > "$OUT/replay.$k.log" 2>&1) &
done
wait
echo "[$(date -Is)] replay done" >> "$OUT/progress.log"
args=()
for f in "$OUT"/*_arms.json; do p=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['problem_id'])" "$f"); args+=(--problem "$p" "$f"); done
SREGYM_JUDGE_STARTUP_TIMEOUT=1800 /home/priyo_software/sregym/SREGym-v2eval/.venv/bin/python -m clients.jev_diag.v2_eval.grade "${args[@]}" > "$OUT/grade.log" 2>&1
echo "[$(date -Is)] grade done exit=$?" >> "$OUT/progress.log"
