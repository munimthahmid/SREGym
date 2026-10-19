#!/usr/bin/env bash
# After the Lite batch (V2H RUNS DONE): move the run tree to the updated v2 (jev-v2-dev,
# 066c4d2f), rerun the two held-out faults it changes, and grade them with one judge.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
until grep -q "V2H RUNS DONE" "$R/runs.txt"; do sleep 30; done
sleep 60  # let the last run's teardown finish
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
git merge -q --no-edit jev-v2-dev || { echo "[$(date -Is)] HELD6 ABORTED: merge failed" >> "$R/runs.txt"; exit 1; }
if ! git diff --quiet 066c4d2f -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] HELD6 ABORTED: code is not 066c4d2f" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] HELD6 START v2=066c4d2f" >> "$R/runs.txt"
RUN_TIMEOUT=3600 "$R/run.sh" held6_valkey_memory_disruption openrouter/typesafe/jev-1.13 --problem valkey_memory_disruption --profile svelte
RUN_TIMEOUT=3600 "$R/run.sh" held6_auth_miss_mongodb openrouter/typesafe/jev-1.13 --problem auth_miss_mongodb
args=()
for p in valkey_memory_disruption auth_miss_mongodb; do
  start=$(grep "START held6_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END held6_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)
  [ -n "$f" ] && args+=(--problem "$p" "$f") && mkdir -p "$R/results/held/$p/v2final" && cp "${f%_arms.json}"* "$R/results/held/$p/v2final/"
done
echo "[$(date -Is)] GRADE START held6 $(( ${#args[@]} / 3 ))" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-held6.log" 2>&1
echo "[$(date -Is)] GRADE DONE held6 exit=$?" >> "$R/runs.txt"
