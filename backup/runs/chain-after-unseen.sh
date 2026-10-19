#!/usr/bin/env bash
# After Unseen: rerun once any problem whose live run produced no answers (infrastructure failure), then the hard
# case that failed on infrastructure, then Lite 15. All on the frozen v2 already in the eval checkout.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
until grep -q "SET unseen done" "$R/runs.txt"; do sleep 30; done
retry=$(grep -E "^\[unseen_[^]]+\] no arms file" "$R/grade-unseen.log" 2>/dev/null | sed -E 's/^\[unseen_([^]]+)\].*/\1/' | sort -u)
[ -n "$retry" ] && "$R/run-set2.sh" unseen_retry $retry
# hard cases left without answers by infrastructure failures
hard=$(for p in update_incompatible_correlated auth_miss_mongodb secret_rotation_stale_env_credentials_astronomy_shop \
  valkey_memory_disruption valkey_auth_disruption; do
  ls "$R/results/hard/$p/"*_arms.json "$R/results/hard_retry/$p/"*_arms.json >/dev/null 2>&1 || echo "$p"; done)
[ -n "$hard" ] && "$R/run-set2.sh" hard_retry2 $hard
"$R/run-set2.sh" lite cronjob_sidecar_blocks_completion_hotel_reservation duplicate_pvc_mounts_social_network \
  edge_request_filter_cpu_saturation env_variable_shadowing_astronomy_shop finalizer_deadlock_controller_hotel_reservation \
  internal_traffic_policy_local_astronomy_shop kafka_poison_pill_hol_block mutating_webhook_resource_limits_social_network \
  namespace_memory_limit network_policy_block rolling_update_misconfigured_social_network \
  search_rate_retry_collapse_hotel_reservation service_dns_resolution_failure_social_network \
  service_wrong_pod_selection_hotel_reservation unschedulable_incorrect_port_assignment
retry=$(grep -E "^\[lite_[^]]+\] no arms file" "$R/grade-lite.log" 2>/dev/null | sed -E 's/^\[lite_([^]]+)\].*/\1/' | sort -u)
[ -n "$retry" ] && "$R/run-set2.sh" lite_retry $retry
echo "[$(date -Is)] ALL SETS DONE" >> "$R/runs.txt"
