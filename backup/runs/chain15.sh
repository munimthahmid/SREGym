#!/usr/bin/env bash
# Lite 17 on 30dd021e, after the held-out sample finishes (chain14). Labels lite5_<p>; graded per fault by
# grade-rolling5.sh, which stops after "V2H RUNS DONE".
R="/home/priyo_software/Priyo Work/jev-v2-runs"
LITE_LIGHT="service_wrong_pod_selection_hotel_reservation search_rate_retry_collapse_hotel_reservation
            cronjob_sidecar_blocks_completion_hotel_reservation finalizer_deadlock_controller_hotel_reservation
            namespace_memory_limit network_policy_block service_dns_resolution_failure_social_network
            mutating_webhook_resource_limits_social_network duplicate_pvc_mounts_social_network
            rolling_update_misconfigured_social_network"
LITE_ASTRO="$(cat "$R/astro_ids.txt")"
until grep -qE "HELD5B (DONE|ABORTED)" "$R/runs.txt"; do sleep 20; done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet 30dd021e -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] LITE5 ABORTED: code is not 30dd021e" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] LITE5 START v2=30dd021e" >> "$R/runs.txt"
for p in $LITE_LIGHT; do RUN_TIMEOUT=3600 "$R/run.sh" "lite5_$p" openrouter/typesafe/jev-1.13 --problem "$p"; done
for p in $LITE_ASTRO; do RUN_TIMEOUT=3600 "$R/run.sh" "lite5_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
echo "[$(date -Is)] V2H RUNS DONE" >> "$R/runs.txt"
