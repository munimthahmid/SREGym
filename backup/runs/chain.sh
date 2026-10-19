#!/usr/bin/env bash
# When the hotel batch is done: start the social-network batch, and grade the hotel arms meanwhile.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
until grep -q "BATCH DONE search_rate_retry_collapse_hotel_reservation" "$R/runs.txt"; do sleep 20; done
setsid nohup "$R/batch.sh" service_dns_resolution_failure_social_network mutating_webhook_resource_limits_social_network \
  duplicate_pvc_mounts_social_network rolling_update_misconfigured_social_network > /dev/null 2>&1 < /dev/null &
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
args=()
for p in search_rate_retry_collapse_hotel_reservation cronjob_sidecar_blocks_completion_hotel_reservation \
         finalizer_deadlock_controller_hotel_reservation namespace_memory_limit network_policy_block; do
  start=$(grep "START arms_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  f=$(ls -t results/*/.runtime/jev_diag/*/*_arms.json 2>/dev/null | while read -r x; do
        [ "$(date -r "$x" +%s)" -ge "$(date -d "$start" +%s)" ] && echo "$x"; done | tail -1)
  [ -n "$f" ] && args+=(--problem "$p" "$f") && mkdir -p "$R/results/$p" && cp "${f%_arms.json}"* "$R/results/$p/"
done
echo "[$(date -Is)] GRADE START hotel ${#args[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-hotel.log" 2>&1
echo "[$(date -Is)] GRADE DONE hotel exit=$?" >> "$R/runs.txt"
