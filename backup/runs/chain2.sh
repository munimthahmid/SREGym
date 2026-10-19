#!/usr/bin/env bash
# After the social batch: grade it, then (once the image preload is done) run the astronomy faults with the
# svelte profile, then grade those.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
SOCIAL="service_dns_resolution_failure_social_network mutating_webhook_resource_limits_social_network
        duplicate_pvc_mounts_social_network rolling_update_misconfigured_social_network"
ASTRO="edge_request_filter_cpu_saturation env_variable_shadowing_astronomy_shop kafka_poison_pill_hol_block
       internal_traffic_policy_local_astronomy_shop valkey_auth_disruption
       secret_rotation_stale_env_credentials_astronomy_shop unschedulable_incorrect_port_assignment"
until grep -q "BATCH DONE service_dns_resolution_failure_social_network" "$R/runs.txt"; do sleep 20; done
# shellcheck disable=SC2086
setsid nohup "$R/grade-batch.sh" social $SOCIAL > /dev/null 2>&1 < /dev/null &
while ps -eo args | grep -q '^bash .*jev-v2-runs/preload.sh'; do sleep 30; done
for p in $ASTRO; do
  "$R/run.sh" "arms_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte
done
echo "[$(date -Is)] BATCH DONE $(echo $ASTRO)" >> "$R/runs.txt"
# shellcheck disable=SC2086
"$R/grade-batch.sh" astro $ASTRO
