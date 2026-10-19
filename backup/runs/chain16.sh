#!/usr/bin/env bash
# Lite on 30dd021e, split with laptop B (agent-chat): the hotel + social faults here; astronomy here only if
# astro.local exists (B cannot take it), skipped if astro.remote exists. Graded per fault by grade-rolling5.sh.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
CURRENT="service_wrong_pod_selection_hotel_reservation"
LIGHT="service_wrong_pod_selection_hotel_reservation search_rate_retry_collapse_hotel_reservation
       cronjob_sidecar_blocks_completion_hotel_reservation finalizer_deadlock_controller_hotel_reservation
       namespace_memory_limit network_policy_block service_dns_resolution_failure_social_network
       mutating_webhook_resource_limits_social_network duplicate_pvc_mounts_social_network
       rolling_update_misconfigured_social_network"
ASTRO="$(cat "$R/astro_ids.txt")"
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
until grep -q "END lite5_$CURRENT " "$R/runs.txt"; do sleep 15; done
if ! git diff --quiet 30dd021e -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] LITE5B ABORTED: code is not 30dd021e" >> "$R/runs.txt"; exit 1
fi
for p in $LIGHT; do
  grep -q "END lite5_$p " "$R/runs.txt" && continue  # already run
  RUN_TIMEOUT=3600 "$R/run.sh" "lite5_$p" openrouter/typesafe/jev-1.13 --problem "$p"
done
until [ -e "$R/astro.local" ] || [ -e "$R/astro.remote" ]; do sleep 30; done
if [ -e "$R/astro.local" ]; then
  for p in $ASTRO; do RUN_TIMEOUT=3600 "$R/run.sh" "lite5_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
fi
echo "[$(date -Is)] V2H RUNS DONE" >> "$R/runs.txt"
