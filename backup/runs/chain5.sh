#!/usr/bin/env bash
# Final Lite pass: all 17 SREGym-Lite faults on the frozen v2 (1d22d925), four arms each, then one grading pass.
# Runs (label final_<problem>) start once the astronomy batch is done; files go to results/<problem>/final/.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
FROZEN=1d22d925
HOTEL="service_wrong_pod_selection_hotel_reservation search_rate_retry_collapse_hotel_reservation
       cronjob_sidecar_blocks_completion_hotel_reservation finalizer_deadlock_controller_hotel_reservation
       namespace_memory_limit network_policy_block"
SOCIAL="service_dns_resolution_failure_social_network mutating_webhook_resource_limits_social_network
        duplicate_pvc_mounts_social_network rolling_update_misconfigured_social_network"
ASTRO="$(cat "$R/astro_ids.txt")"
until grep -q "BATCH DONE edge_request_filter_cpu_saturation" "$R/runs.txt"; do sleep 20; done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet "$FROZEN" -- clients docker agents.yaml sregym llm_backend main.py; then  # code == frozen (docs may differ)
  echo "[$(date -Is)] FINAL ABORTED: code is not the frozen $FROZEN" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] FINAL START v2=$FROZEN" >> "$R/runs.txt"
for p in $HOTEL $SOCIAL; do "$R/run.sh" "final_$p" openrouter/typesafe/jev-1.13 --problem "$p"; done
for p in $ASTRO; do "$R/run.sh" "final_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
echo "[$(date -Is)] FINAL RUNS DONE" >> "$R/runs.txt"
args=(); pairs=()
for p in $HOTEL $SOCIAL $ASTRO; do
  start=$(grep "START final_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -z "$start" ] && continue
  f=$(find results -name '*_arms.json' -newermt "$start" 2>/dev/null | xargs -r ls -tr | head -1)
  [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("$p=$f") && mkdir -p "$R/results/$p/final" \
    && cp "${f%_arms.json}"* "$R/results/$p/final/"
done
echo "[$(date -Is)] GRADE START final ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-final.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do
  p="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/$p/final/" 2>/dev/null
done
echo "[$(date -Is)] GRADE DONE final exit=$code" >> "$R/runs.txt"
