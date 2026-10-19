#!/usr/bin/env bash
# Targeted set T (jev-v2-testsets.md): after the held-out reruns are graded, on the same final code (4a9b25e0),
# four arms each, 1 h cap per fault, then one grading pass. Labels tgt_<problem>; files in results/targeted/.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
until grep -qE "GRADE DONE held6|HELD6 ABORTED" "$R/runs.txt"; do sleep 30; done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet 4a9b25e0 -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] TARGETED ABORTED: code is not 4a9b25e0" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] TARGETED START v2=4a9b25e0" >> "$R/runs.txt"
for p in ingress_misroute update_incompatible_correlated capacity_decrease_rpc_retry_storm gc_capacity_degradation; do
  RUN_TIMEOUT=3600 "$R/run.sh" "tgt_$p" openrouter/typesafe/jev-1.13 --problem "$p"
done
RUN_TIMEOUT=3600 "$R/run.sh" tgt_missing_env_variable_astronomy_shop openrouter/typesafe/jev-1.13 --problem missing_env_variable_astronomy_shop --profile svelte
args=(); pairs=()
for p in ingress_misroute update_incompatible_correlated capacity_decrease_rpc_retry_storm gc_capacity_degradation missing_env_variable_astronomy_shop; do
  start=$(grep "START tgt_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END tgt_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)
  [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("$p=$f") && mkdir -p "$R/results/targeted/$p" && cp "${f%_arms.json}"* "$R/results/targeted/$p/"
done
echo "[$(date -Is)] GRADE START targeted ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-targeted.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do p="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/targeted/$p/" 2>/dev/null; done
echo "[$(date -Is)] GRADE DONE targeted exit=$code" >> "$R/runs.txt"
