#!/usr/bin/env bash
# After chain3 (astro graded, reruns graded): rerun the faults whose live run used v2 before f0f42805 (the coverage
# read fix) and failed, then grade them. Results go to results/<problem>/rerun2/.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
RERUN2="${RERUN2:-kafka_poison_pill_hol_block}"
until grep -q "GRADE DONE rerun" "$R/runs.txt"; do sleep 30; done
for p in $RERUN2; do
  extra=""; grep -q "^${p}$" "$R/astro_ids.txt" 2>/dev/null && extra="--profile svelte"
  # shellcheck disable=SC2086
  "$R/run.sh" "rerun2_$p" openrouter/typesafe/jev-1.13 --problem "$p" $extra
done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
args=(); pairs=()
for p in $RERUN2; do
  start=$(grep "START rerun2_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -z "$start" ] && continue
  f=$(find results -name '*_arms.json' -newermt "$start" 2>/dev/null | xargs -r ls -tr | head -1)
  [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("$p=$f") && mkdir -p "$R/results/$p/rerun2" \
    && cp "${f%_arms.json}"* "$R/results/$p/rerun2/"
done
echo "[$(date -Is)] GRADE START rerun2 ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-rerun2.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do
  p="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/$p/rerun2/" 2>/dev/null
done
echo "[$(date -Is)] GRADE DONE rerun2 exit=$code" >> "$R/runs.txt"
