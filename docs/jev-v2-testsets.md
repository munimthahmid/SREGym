# jev_diag v2 test sets (fixed 2026-10-18, before any v2 code)

Assigned by problem id, class name and the one-line "Failure to Simulate" in `Problem List.md` only. No fault
source files read. Source of the full benchmark: the leaderboard's SREGym-0508 cohort
(sregym.com/problems/cohorts/sregym-0508), 66 of whose ids are registered on main 7c3170e3. `node_clock_drift`
is excluded (not supported on kind). Draft: to be checked by Codex before use.

"Seen" means the SREGym team tuned v1 on that fault family: the blog's 21 faults (current Lite 17 plus
admission_webhook_outage_hotel_reservation, readiness_probe_misconfiguration_social_network,
wrong_dns_policy_astronomy_shop, wrong_service_selector_social_network).

## Dev (17): current SREGym-Lite
Used to build v2. Results here are reported but prove little.

## Transfer: same fault class, different app
- **Lite-IA (17):** the Lite faults on Frappe, Saleor, Slack Spine (`--suite sregym-lite-ia`). Heavy apps; likely
  needs the bigger machine.
- **Cohort, same class (3):** duplicate_pvc_mounts_hotel_reservation, rolling_update_misconfigured_hotel_reservation,
  service_dns_resolution_failure_astronomy_shop.

## Near: a different fault in a family v1 was tuned on (11)
- Service selector: wrong_service_selector_astronomy_shop, wrong_service_selector_hotel_reservation
- DNS: stale_coredns_config_astronomy_shop, stale_coredns_config_social_network, wrong_dns_policy_hotel_reservation,
  wrong_dns_policy_social_network
- Readiness probe: readiness_probe_misconfiguration_hotel_reservation, astronomy_shop_failed_readiness_probe
- Auth to a data store: auth_miss_mongodb
- Retry storm: capacity_decrease_rpc_retry_storm
- Kafka: kafka_queue_problems

## Unseen: a family v1 was not tuned on (the result that matters)
- Probes, different kind: liveness_probe_too_aggressive_astronomy_shop, liveness_probe_too_aggressive_hotel_reservation,
  liveness_probe_too_aggressive_social_network
- Ports, different kind: sidecar_port_conflict_astronomy_shop, sidecar_port_conflict_hotel_reservation,
  sidecar_port_conflict_social_network, service_port_conflict_astronomy_shop, service_port_conflict_hotel_reservation,
  service_port_conflict_social_network
- Images and binaries: incorrect_image, misconfig_app_hotel_res, update_incompatible_correlated, wrong_bin_usage
- Missing objects and settings: missing_configmap_hotel_reservation, missing_service_hotel_reservation,
  missing_env_variable_astronomy_shop, configmap_drift_hotel_reservation
- Scheduling and placement: taint_no_toleration_social_network, persistent_volume_affinity_violation,
  workload_imbalance, resource_request_too_small, scale_pod_zero_social_net
- Operator (controller) faults: operator_invalid_affinity_toleration, operator_non_existent_storage,
  operator_overload_replicas, operator_security_context_fault, operator_wrong_operator_image,
  operator_wrong_update_strategy_fault
- Application behaviour and load: astronomy_shop_ad_service_failure, astronomy_shop_ad_service_high_cpu,
  astronomy_shop_ad_service_image_slow_load, astronomy_shop_ad_service_manual_gc, astronomy_shop_cart_service_failure,
  astronomy_shop_payment_service_failure, astronomy_shop_product_catalog_service_failure, gc_capacity_degradation,
  loadgenerator_flood_homepage
- Data store faults: valkey_memory_disruption, trainticket_f17_nested_sql_select_clause_error,
  trainticket_f22_sql_column_name_mismatch_error
- Routing: ingress_misroute
- Node and disk: kubelet_crash, latent_sector_error, silent_data_corruption

That is 44 unseen faults (3 transfer + 11 near + 44 unseen + 8 Lite ids = the 66 registered cohort ids). Some need heavy apps (astronomy shop, train ticket) or node-level access and may not run on
this laptop; those wait for the bigger machine.

## Open points for review
- Some splits are judgement calls (for example port conflicts count as Unseen: Lite's port fault is a hostPort
  that blocks scheduling, a different mechanism).
- Cohort problems not in today's registry (about 26 page ids) are not used.

## Held-out sample of 10 (fixed 2026-10-19 06:25, before any of the 8 drawn ran)
Running all 58 is more than the PR needs. The sample keeps the 2 already run (whatever their result) and draws 8
more with `random.Random("jev-v2-heldout-10")` from the held-out faults on the Lite apps that run on kind (not the
disk-corruption faults or kubelet_crash), keeping Lite's app mix (3 hotel, 3 social, 4 astronomy in total):

| Fault | App | Group |
|---|---|---|
| service_dns_resolution_failure_astronomy_shop | astronomy | Transfer (already run) |
| wrong_service_selector_astronomy_shop | astronomy | Near (already run) |
| sidecar_port_conflict_hotel_reservation | hotel | Unseen |
| duplicate_pvc_mounts_hotel_reservation | hotel | Transfer |
| readiness_probe_misconfiguration_hotel_reservation | hotel | Near |
| liveness_probe_too_aggressive_social_network | social | Unseen |
| service_port_conflict_social_network | social | Unseen |
| auth_miss_mongodb | social | Near |
| valkey_memory_disruption | astronomy | Unseen |
| incorrect_image | astronomy | Unseen |

All on the frozen v2 1d22d925, four arms each, reported as they come out. Two failed held-out attempts at
00:49 (stale_coredns_config_astronomy_shop, astronomy_shop_failed_readiness_probe) never started (OpenRouter credits)
and are not part of the sample.
