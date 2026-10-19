#!/usr/bin/env bash
# Replaces chain2: after the social batch, grade it; rerun the two faults the own-setting fix (3dc3e053) changes,
# live, while the astronomy images finish loading; then the astronomy faults (svelte); then grade astro + reruns.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
SOCIAL="service_dns_resolution_failure_social_network mutating_webhook_resource_limits_social_network
        duplicate_pvc_mounts_social_network rolling_update_misconfigured_social_network"
RERUN="duplicate_pvc_mounts_social_network cronjob_sidecar_blocks_completion_hotel_reservation"
ASTRO="edge_request_filter_cpu_saturation env_variable_shadowing_astronomy_shop kafka_poison_pill_hol_block
       internal_traffic_policy_local_astronomy_shop valkey_auth_disruption
       secret_rotation_stale_env_credentials_astronomy_shop unschedulable_incorrect_port_assignment"
until grep -q "BATCH DONE service_dns_resolution_failure_social_network" "$R/runs.txt"; do sleep 20; done
# shellcheck disable=SC2086
setsid nohup "$R/grade-batch.sh" social $SOCIAL > /dev/null 2>&1 < /dev/null &
sleep 60  # grade-batch reads the START lines first; reruns add new ones
for p in $RERUN; do
  "$R/run.sh" "rerun_$p" openrouter/typesafe/jev-1.13 --problem "$p"
done
while ps -eo args | grep -q '^bash .*jev-v2-runs/preload.sh'; do sleep 30; done
for p in $ASTRO; do
  "$R/run.sh" "arms_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte
done
echo "[$(date -Is)] BATCH DONE $(echo $ASTRO)" >> "$R/runs.txt"
# shellcheck disable=SC2086
"$R/grade-batch.sh" astro $ASTRO
# Reruns: graded under their own START label (rerun_<problem>), copied to results/<problem>/rerun/.
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
args=(); pairs=()
for p in $RERUN; do
  start=$(grep "START rerun_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -z "$start" ] && continue
  f=$(find results -name '*_arms.json' -newermt "$start" 2>/dev/null | xargs -r ls -tr | head -1)
  [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("$p=$f") && mkdir -p "$R/results/$p/rerun" \
    && cp "${f%_arms.json}"* "$R/results/$p/rerun/"
done
echo "[$(date -Is)] GRADE START rerun ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-rerun.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do
  p="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/$p/rerun/" 2>/dev/null
done
echo "[$(date -Is)] GRADE DONE rerun exit=$code" >> "$R/runs.txt"
