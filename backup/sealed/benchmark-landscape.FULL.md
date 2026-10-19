# SREGym benchmark landscape (analyst report, 2026-10-19)

Scope: what a diagnosis pipeline has to handle to score well on the whole SREGym benchmark, not one subset.
Facts come from code and run files (cited). Opinions are marked as such. Sample C problems are listed by name
only; their problem files, ground truth and runs were not opened (their injector methods in shared files were
skipped too).

Sources read: `sregym/conductor/problems/*.py` (all except the 9 sample-C files), `registry.py`,
`environment_ports.py`, `problem_sets.py`, `apps/*/ports.py`, `contracts/incident_arena/tasks/*/ground-truth.yaml`,
`sregym/generators/fault/{inject_virtual,inject_app,inject_otel,inject_tt,inject_operator,inject_remote_os}.py`
(non-C methods), `sregym/conductor/oracles/llm_as_a_judge/*`, `oracles/diagnosis_oracle.py`, `mcp_server/*`,
`README.md`, `docs/*.md`, `Problem List.md`, `clients/jev_diag/{collector,investigate,changes,probes,driver,classifier}.py`,
`clients/jev_v2/{agent,explain,report,patterns}.py`, and all `*_arms_graded.json` for run labels
`lite5*`, `lite6*`, `held*`, `tgt*` in `runs-index.tsv` (none of them is a sample-C problem).

---

## 0. What "the benchmark" is (facts)

- `registry.py` registers **117 core problem ids** (11 apps), plus **84 ports** of existing fault classes to the
  Incident Arena apps (Frappe 18, Saleor 24, Slack Spine 42, via `environment_ports.py`): 201 runnable ids.
  Ports reuse the core fault class with app-specific setup, so they add apps, not new fault mechanisms.
- 24 ids are "saturated" and no longer registered (100% pass@3 across evaluated models, or 21/21), listed at
  the bottom of `registry.py`: e.g. `k8s_target_port-misconfig`, `pvc_claim_mismatch`, `rbac_misconfiguration`,
  `resource_request_too_large`, `liveness_probe_misconfiguration_*`, `missing_configmap_social_network`,
  `readiness_probe_misconfiguration_social_network`, `wrong_service_selector_social_network`,
  `admission_webhook_outage_hotel_reservation`. Almost all are single-workload spec faults. Opinion: the
  benchmark is deliberately moving away from "one bad field in one Deployment" towards runtime state,
  outside objects and interactions, so the remaining set is harder than its history suggests.
- SREGym-Lite = 17 ids (`problem_sets.py`). Lite-IA = the same 17 faults on Frappe/Saleor/Slack Spine.
- The public leaderboard cohort `sregym-0508` contains 66 registered ids (per `jev-v2-testsets.md`; 58 are
  listed by name there, the other 8 are unnamed Lite ids). All 10 sample-C ids are in that cohort.
- Fault noise (Chaos Mesh pod-kill / delay / loss, `generators/noise`) exists but is off by default
  (`conductor.py`: `enable_noise: bool = False`). Some problems ship their own decoys (see section 2.4).

## 1. Problem table

**Where the root cause lives** (primary; secondary after "+"):
- **WS** one workload's own spec/config (pod template, container env/image/command/probe/ports/resources,
  init containers, dnsPolicy, rollout strategy, CronJob template)
- **CO** a config object in the app namespace (Service, ConfigMap incl. feature flags, Secret, Ingress,
  NetworkPolicy, ResourceQuota)
- **CL** a cluster-level or outside-the-app object (kube-system objects, webhook configurations, PriorityClass,
  namespace labels, ClusterRole, Calico CRs, operator custom resources, objects in other namespaces)
- **NI** node / infrastructure (kubelet, node clock, kernel tables, disk data, node taints)
- **IX** an interaction between components (each part looks valid alone: timeout+retry+capacity loops,
  traffic policy vs pod placement, hostPort vs a DaemonSet, missing fallback vs upstream latency)
- **IN** input data / messages / load (poison record, flooding writer, traffic surge)
- **RT** runtime state invisible in specs (DB users/grants/locks/sequences, runtime `CONFIG SET`, env captured
  before a Secret rotation, pod-local leftovers of a paused rollout)
- **MC** multiple components at once (same mutation on many workloads; several independent causes)

**Evidence** that reveals it: S spec (diff against revision history, managedFields, siblings or shipped
manifests), E events/status, R related-object listing (endpoints, ReplicaSets, webhooks, policies, nodes),
L logs, M metrics (PromQL), T traces, P live probe (exec/SQL/HTTP/TLS/node command).

**GT origin** = the `component=` field of `root_cause` (`[fault_spec] component=X; namespace=Y || prose`).
"bare" = a plain name with no kind. Lite = in SREGym-Lite. 0508 = named in the leaderboard cohort list.

| # | id | app | fault mechanism (one line) | lives | evidence | GT origin (`component=`) | set |
|---|---|---|---|---|---|---|---|
| 1 | update_incompatible_correlated | hotel | image of 6 mongodb-* Deployments set to `mongo:8.0.14-rc0` | MC+WS | S, E, L | `deployments/mongodb-geo, …, mongodb-user` (6 Deployments) | 0508 |
| 2 | incorrect_image | astronomy | product-catalog image -> non-existent `app-image:latest` | WS | E, S | `deployment/product-catalog` (prose also names checkout as affected) | 0508 |
| 3 | kafka_producer_leak | astronomy | extra container in checkout floods Kafka with large messages; broker heap exhausted | WS+IN | S, E, L | `deployment/checkout` | |
| 4 | unschedulable_incorrect_port_assignment | astronomy | checkout `PRODUCT_CATALOG_ADDR` port 8082 (not 8080) and nodeSelector to a non-existent node | WS | S, E | `deployment/checkout` | Lite |
| 5 | misconfig_app_hotel_res | hotel | geo image swapped for a build whose baked-in config dials `mongodb-geo:27777` | WS | L, S | `deployment/geo` | 0508 |
| 6 | missing_env_variable_astronomy_shop | astronomy | `CART_ADDR` removed from frontend | WS | S, L | `deployment/frontend` | 0508 |
| 7 | revoke_auth_mongodb-1 | hotel | admin role revoked inside mongodb-geo (mongo shell), geo pods restarted | RT | L, P | `service/mongodb-geo-db` (no such object exists) | |
| 8 | revoke_auth_mongodb-2 | hotel | same on mongodb-rate | RT | L, P | `service/mongodb-rate-db` | |
| 9 | storage_user_unregistered-1 | hotel | admin user dropped from mongodb-geo | RT | L, P | `service/mongodb-geo` | |
| 10 | storage_user_unregistered-2 | hotel | same on mongodb-rate | RT | L, P | `service/mongodb-rate` | |
| 11 | valkey_auth_disruption | astronomy | `CONFIG SET requirepass` on valkey-cart at runtime; cart restarted | RT | L (NOAUTH), P | `service/valkey-cart` | Lite |
| 12 | valkey_memory_disruption | astronomy | Job `valkey-memory-flood` writes 1 MB values from 10 threads; valkey OOM | IN | E, M, L, R | `service/valkey-cart` (not the Job) | 0508 |
| 13 | edge_request_filter_cpu_saturation | astronomy | frontend-proxy gets a catastrophic-backtracking WAF regex, 100m CPU, crafted `waf` traffic | WS+IN | S, M, L/T | `frontend-proxy` (bare) | Lite |
| 14 | ephemeral_port_range_hotel_reservation | hotel | every pod's `net.ipv4.ip_local_port_range` sysctl narrowed to 4 ports | MC+WS | S, L (EADDRNOTAVAIL) | `all hotel-reservation deployments` | |
| 15 | secret_rotation_stale_env_credentials_astronomy_shop | astronomy | DB password and Secret rotated; product-catalog keeps the env value read at startup | RT+CO | L, S (Secret newer than pod) | `deployment/product-catalog` | Lite |
| 16 | capacity_decrease_rpc_retry_storm | blueprint-hotel | ConfigMap `rpc`: 50 ms timeout, 30 retries; then latency + CPU stress; storm self-sustains | IX+CO | S, M, T | `configmap/rpc` | 0508 |
| 17 | gc_capacity_degradation | blueprint-hotel | `GOGC=1` on all Deployments + memory limit + load | MC+IX | S, M | `deployments/all` | 0508 |
| 18 | load_spike_rpc_retry_storm | blueprint-hotel | same ConfigMap `rpc` change + load spike | IX+CO | S, M, T | `configmap/rpc` | |
| 19 | search_rate_retry_collapse_hotel_reservation | hotel | search's rate RPC policy (3 tries, short deadline) + a burst fills rate's queue; retries keep it overloaded | IX | M, L, S | `search-to-rate RPC path` (an interaction) | Lite |
| 20 | auth_miss_mongodb | social | helm sets url-shorten-mongodb `requireTLS` with missing cert files; mongod crash-loops | WS (its mongod.conf ConfigMap) | L, S | `service/url-shorten-mongodb` | 0508 |
| 21 | configmap_drift_hotel_reservation | hotel | sample C, not opened | - | - | - | C, 0508 |
| 22 | cfs_cpu_throttling_hotel_reservation | hotel | geo CPU limit set just low enough to throttle; decoy CPU limits on other services | WS | M (cgroup `nr_throttled`, throttling alert); `kubectl top` looks normal | `deployment/geo` | |
| 23 | feature_flag_latent_bug_hotel_reservation | hotel | ConfigMap `frontend-runtime-config` flag `SEARCH_BACKEND_VERSION` turns on a dormant HTTP-500 path | CO | S, L/M/T (500s on /hotels, pods Running) | `deployment/frontend` | |
| 24 | finalizer_deadlock_controller_hotel_reservation | hotel | cleanup-controller's ClusterRole made read-only; ConfigMap stuck Terminating on its finalizer | CL | L (403), R | `ClusterRole/configmap-cleanup-controller and configmap/reservation-cleanup-token` | Lite |
| 25 | duplicate_pvc_mounts_hotel_reservation | hotel | frontend >=2 replicas share one RWO PVC + required anti-affinity | WS | E, S | `deployment/frontend` | 0508 |
| 26 | duplicate_pvc_mounts_social_network | social | same on jaeger | WS | E, S | `deployment/jaeger` | Lite |
| 27 | env_variable_shadowing_astronomy_shop | astronomy | second `FRONTEND_HOST=localhost` appended in frontend-proxy (pods stay Ready) | WS | S, T/L | `deployment/frontend-proxy` | Lite |
| 28 | file_descriptor_exhaustion | hotel | frontend wrapped in `ulimit -n 1024`; ~1,100 held connections | WS+IN | L, S | `deployment/frontend` | |
| 29 | liveness_probe_too_aggressive_astronomy_shop | astronomy | new `aux-service` (slow start) with liveness delay 0 / period 1 / threshold 1, grace 0 | WS | E, S | `aux-service` (bare) | 0508 |
| 30 | liveness_probe_too_aggressive_hotel_reservation | hotel | same | WS | E, S | `aux-service` | 0508 |
| 31 | liveness_probe_too_aggressive_social_network | social | same | WS | E, S | `aux-service` | 0508 |
| 32 | init_container_dependency_hang_hotel_reservation | hotel | init container loops `nslookup legacy-config-service` (absent) | WS | E, L, S | `deployment/frontend` | |
| 33 | init_container_dependency_hang_social_network | social | same on user-service | WS | E, L, S | `deployment/user-service` | |
| 34 | integer_overflow_primary_key_astronomy_shop | astronomy | `reviews.productreviews` id sequence set to INT max; inserts fail | RT | L, P (SQL) | `table.reviews.productreviews@postgresql` | |
| 35 | missing_configmap_hotel_reservation | hotel | ConfigMap `mongo-geo-script` deleted; mongodb-geo restarted | CO | E (FailedMount) | `mongodb-geo` (bare) | 0508 |
| 36 | missing_service_hotel_reservation | hotel | sample C, not opened | - | - | - | C, 0508 |
| 37 | missing_stale_cache_fallback_astronomy_shop | astronomy | recommendation code has no cached fallback + 3 s Chaos Mesh delay on product-catalog | IX | T, L | `deployment/recommendation` | |
| 38 | missing_stale_cache_fallback_long_delay_astronomy_shop | astronomy | same with 5 s delay | IX | T, L | `deployment/recommendation` | |
| 39 | namespace_memory_limit | hotel | ResourceQuota requires memory declarations; search ReplicaSets deleted, recreate rejected | CO | E (FailedCreate), R | `resourcequota/memory-limit-quota` | Lite |
| 40 | nightly_rebalance_oom_hotel_reservation | hotel | CronJob `vpa-updater` in kube-system keeps patching recommendation memory limit to 4Mi | CL+WS | E (OOMKilled), S (managedFields writer), R | `vpa-updater CronJob (kube-system)` | |
| 41 | node_clock_drift_hotel_reservation | hotel | worker clock pushed forward, time sync masked (not supported on kind) | NI | L (TLS not yet valid), P | `node/system-clock` | |
| 42 | postgres_lock_contention_product_catalog | astronomy | Job in another namespace holds ACCESS EXCLUSIVE lock on `catalog.products` | RT | T (hangs), P (pg_locks), R | `postgresql (table catalog.products)` | |
| 43 | persistent_volume_affinity_violation | social | sample C, not opened | - | - | - | C, 0508 |
| 44 | priority_preemption_cascade_hotel_reservation | hotel | global-default PriorityClass `platform-medium` lets a tenant pod preempt reservation | CL | E (Preempted), R | `PriorityClass/platform-medium` | |
| 45 | readiness_probe_misconfiguration_hotel_reservation | hotel | frontend readiness probe `httpGet /healthz:8080` | WS | E, R, S | `frontend` (bare) | 0508 |
| 46 | resource_request_too_small | hotel | sample C, not opened | - | - | - | C, 0508 |
| 47 | rolling_update_misconfigured_hotel_reservation | hotel | new custom-service; maxUnavailable 100% / maxSurge 0 + init `sleep infinity` | WS | S, E | `deployment/custom-service` | 0508 |
| 48 | rolling_update_misconfigured_social_network | social | same | WS | S, E | `deployment/custom-service` | Lite |
| 49 | scale_pod_zero_social_net | social | sample C, not opened | - | - | - | C, 0508 |
| 50 | service_dns_resolution_failure_astronomy_shop | astronomy | CoreDNS Corefile NXDOMAIN template for frontend's FQDN | CL | S, L, P | `configmap/coredns` (kube-system) | 0508 |
| 51 | service_dns_resolution_failure_social_network | social | same for user-service | CL | S, L, P | `configmap/coredns` | Lite |
| 52 | sidecar_port_conflict_astronomy_shop | astronomy | busybox sidecar listens on the main container's port (frontend) | WS | L, E, S | `deployment/frontend` | 0508 |
| 53 | sidecar_port_conflict_hotel_reservation | hotel | same (frontend) | WS | L, E, S | `deployment/frontend` | 0508 |
| 54 | sidecar_port_conflict_social_network | social | same (user-service) | WS | L, E, S | `deployment/user-service` | 0508 |
| 55 | service_port_conflict_astronomy_shop | astronomy | hostPort 9100 added to ad; prometheus-node-exporter DaemonSet already holds 9100 | IX+WS | E, S, R | `deployment/ad` (prose names node-exporter) | 0508 |
| 56 | service_port_conflict_hotel_reservation | hotel | same on recommendation | IX+WS | E, S, R | `deployment/recommendation` | 0508 |
| 57 | service_port_conflict_social_network | social | same on media-service | IX+WS | E, S, R | `deployment/media-service` | 0508 |
| 58 | stale_coredns_config_astronomy_shop | astronomy | sample C, not opened | - | - | - | C, 0508 |
| 59 | stale_coredns_config_social_network | social | sample C, not opened | - | - | - | C, 0508 |
| 60 | stale_hostaliases_dns_poisoning_astronomy_shop | astronomy | paused partial rollout keeps one old frontend-proxy pod with hostAliases; carts split across two stores | RT+IX | R (two ReplicaSets, pod vs template), T, P | `deployment/frontend-proxy` | |
| 61 | taint_no_toleration_social_network | social | nodes tainted `sre-fault=blocked:NoSchedule`; user-service has a non-matching toleration | NI+WS | E, R | `user-service` (bare) | 0508 |
| 62 | wrong_bin_usage | hotel | profile container command -> `geo` binary | WS | S, L | `deployment/profile` | 0508 |
| 63 | wrong_dns_policy_hotel_reservation | hotel | profile `dnsPolicy: None` + nameserver 8.8.8.8 | WS | S, L | `profile` (bare) | 0508 |
| 64 | wrong_dns_policy_social_network | social | same on user-service | WS | S, L | `user-service` (bare) | 0508 |
| 65 | service_wrong_pod_selection_hotel_reservation | hotel | frontend Service selector broadened; label also put on search pods | CO | R (endpoints), S | `service/frontend` | Lite |
| 66 | wrong_service_selector_astronomy_shop | astronomy | frontend Service gets an extra selector label: 0 endpoints | CO | R, S | `frontend` (bare; prose says Service) | 0508 |
| 67 | wrong_service_selector_hotel_reservation | hotel | same | CO | R, S | `frontend` (bare) | 0508 |
| 68 | gitlab_notification_unannounced_ambiguity_replicated | gitlab | wrong-primary schema deletion replicated; restore and reconcile notifications | RT | P, L | `gitlab-ce-db` | |
| 69 | gitlab_notification_intermittent_replicated | gitlab | same + intermittent SMTP during recovery | RT | P, L | `gitlab-ce-db` | |
| 70 | gitlab_notification_delayed_audit_replicated | gitlab | same family | RT | P, L | `gitlab-ce-db` | |
| 71 | stripe_feature_config_single | stripe | ClickHouse permission rollout + oversized config files exceed the edge feature limit | RT+IN | L, P | `feature-catalog` | |
| 72 | astronomy_shop_ad_service_failure | astronomy | flagd `adFailure` on (GetAds errors) | CO | S (flagd-config), L, T | `ad` (bare) | 0508 |
| 73 | astronomy_shop_ad_service_high_cpu | astronomy | flagd `adHighCpu` + ad CPU limit 100m | CO+WS | M, S | `ad` | 0508 |
| 74 | astronomy_shop_ad_service_image_slow_load | astronomy | flagd `imageSlowLoad`=10sec (Envoy delays product images) | CO | T, S | `frontend` (bare) | 0508 |
| 75 | astronomy_shop_ad_service_manual_gc | astronomy | sample C, not opened | - | - | - | C, 0508 |
| 76 | astronomy_shop_cart_service_failure | astronomy | flagd `cartFailure` (EmptyCart errors) | CO | L, T, S | `cart` | 0508 |
| 77 | astronomy_shop_failed_readiness_probe | astronomy | gRPC readiness probe patched on cart + flagd `failedReadinessProbe` | WS+CO | E, R, S | `deployment/cart` | 0508 |
| 78 | astronomy_shop_payment_service_failure | astronomy | sample C, not opened | - | - | - | C, 0508 |
| 79 | astronomy_shop_product_catalog_service_failure | astronomy | flagd `productCatalogFailure` (one product) | CO | T, L, S | `product-catalog` | 0508 |
| 80 | kafka_queue_problems | astronomy | sample C, not opened | - | - | - | C, 0508 |
| 81 | kafka_poison_pill_hol_block | astronomy | unparseable record in topic orders-fulfillment; consumer group stalls, pods Ready | IN | P (offset frozen, lag), L | `kafka topic/orders-fulfillment` | Lite |
| 82 | loadgenerator_flood_homepage | astronomy | flagd makes load-generator flood the homepage | IN+CO | M, S | `frontend` (bare) | 0508 |
| 83 | trainticket_f17_nested_sql_select_clause_error | train-ticket | flag `tt-feat-17` turns on malformed nested SQL in ts-voucher-service; 3 random decoy flags also on | CO | L, T | `deployment/ts-voucher-service` | 0508 |
| 84 | trainticket_f22_sql_column_name_mismatch_error | train-ticket | flag `tt-feat-22`: wrong column name in ts-contacts-service SQL | CO | L, T | `deployment/ts-contacts-service` | 0508 |
| 85 | silent_data_corruption | hotel | mongodb-geo WiredTiger files overwritten on the host volume | NI | L (checksum), E | `deployment/mongodb-geo` | 0508 |
| 86 | latent_sector_error | hotel | mongodb-geo WiredTiger files truncated | NI | L (pread), E | `deployment/mongodb-geo` | 0508 |
| 87 | expired_tls_hotel_reservation | hotel | Ingress `frontend-ingress` uses Secret with an expired certificate | CO | L (ingress controller), P (TLS), R | `frontend-ingress` (an Ingress) | |
| 88 | ingress_misroute | hotel | Ingress `hotel-reservation-ingress` routes `/api` to recommendation-service | CO | R/S, P (HTTP) | `hotel-reservation-ingress` | 0508 |
| 89 | network_policy_block | hotel | NetworkPolicy `deny-all-recommendation` (ingress+egress) | CO | R, L | `recommendation` (bare; prose names the policy) | Lite |
| 90 | node_conntrack_exhaustion_hotel_reservation | hotel | client pinned to one node holds many connections to rpc-gateway; node conntrack table full | NI+IN | P (node), L | `victim node nf_conntrack table + deployment/edge-traffic-client + deployment/rpc-gateway` | |
| 91 | internal_traffic_policy_local_astronomy_shop | astronomy | Service recommendation `internalTrafficPolicy: Local`; its pod and frontend pinned to different nodes | IX+CO | S, R, L/T | `service/recommendation` | Lite |
| 92 | pod_cidr_exhaustion_hotel_reservation | hotel | Calico strictAffinity + tiny IPPool + default pool disabled + pause pods elsewhere use all IPs | CL | E (no IPv4), R | `cluster-networking` | |
| 93 | calico_route_reflector_label_drift_hotel_reservation | hotel | BGPPeer selects the deprecated master label; route reflector lost it; cross-node traffic fails | CL | P, R | `BGPPeer/cluster-peer-policy` (cluster-scoped) | |
| 94 | admission_webhook_tls_mismatch_hotel_reservation | hotel | ValidatingWebhookConfiguration with wrong caBundle, failurePolicy Fail; recommendation pod deleted | CL | E (FailedCreate x509), R | `ValidatingWebhookConfiguration/pod-policy.validation.k8s.io` | |
| 95 | mutating_webhook_resource_limits_social_network | social | MutatingWebhookConfiguration sets memory 16Mi on new pods; 4 inert decoy webhooks | CL | S (pod vs Deployment), E, R | `MutatingWebhookConfiguration/gatekeeper-mutating-webhook-configuration` | Lite |
| 96 | psa_restricted_blocks_recreation_hotel_reservation | hotel | namespace label PSA enforce=restricted; recreated pod rejected | CL | E (FailedCreate), R | `namespace/hotel-reservation` | |
| 97 | cumulative_admission_webhook_timeout_hotel_reservation | hotel | 4 mutating webhooks (timeouts sum > 30 s) whose backends are cut off from the apiserver by NetworkPolicies in `policy-system`; inert companions | CL+IX | E (deadline exceeded), R (other namespace) | `deployment/recommendation` (the victim; prose says the fault is the missing apiserver allow) | |
| 98 | cronjob_sidecar_blocks_completion_hotel_reservation | hotel | CronJob with a regular-container sidecar; Jobs never complete and pile up | WS | R, E | `CronJob/audit-log-archiver` | Lite |
| 99 | kubelet_crash | astronomy | kubelet stopped on a worker; rollouts triggered | NI | E, R | `node/kubelet` | 0508 |
| 100 | kubelet_eviction_threshold_misconfig | astronomy | currency pinned to a node; kubelet `nodefs.available` threshold raised: DiskPressure evictions | NI | R (DiskPressure), E, P | `node/<worker>` | |
| 101 | workload_imbalance | astronomy | kube-proxy DaemonSet image swapped for a buggy one + frontend scaled to 5 + load | CL+IN | M, S | `daemonset/kube-proxy + deployment/frontend` | 0508 |
| 102 | operator_overload_replicas | fleetcast/TiDB | TiDBCluster tidb replicas = 100000 | CL | R, E | `customresource/tidbcluster/basic` (ns tidb-cluster) | 0508 |
| 103 | operator_non_existent_storage | fleetcast/TiDB | PD storageClassName does not exist; PVCs Pending | CL | E, R | same | 0508 |
| 104 | operator_invalid_affinity_toleration | fleetcast/TiDB | invalid toleration effect | CL | E, R | same | 0508 |
| 105 | operator_security_context_fault | fleetcast/TiDB | runAsUser -1 | CL | E, L | same | 0508 |
| 106 | operator_wrong_update_strategy_fault | fleetcast/TiDB | invalid statefulSetUpdateStrategy | CL | R, L | same | 0508 |
| 107 | operator_wrong_operator_image | fleetcast/TiDB | operator Deployment image typo | WS (outside app ns) | E | `deployment/tidb-operator-controller-manager` (ns tidb-operator) | 0508 |
| 108 | frappe_desk_and_queue_outage | frappe | MariaDB `max_user_connections`=8 and Redis queue `min-replicas-to-write 1` (2 causes, both graded) | MC+RT | P, L | `mariadb/mariadb.max-user-connections`; `redis-queue/redis-queue.config` | |
| 109 | frappe_writes_and_queue_oom | frappe | MariaDB read_only + revoked grants + Redis queue cap + ACL (4 causes) | MC+RT | P, L | 4 logical components | |
| 110 | saleor_checkout_statement_timeout_canary | saleor | role-in-database `statement_timeout=150ms`, only fresh sessions | RT | P, L | `postgres/postgres.config` | |
| 111 | slack_split_sequencer | slack | svc-message runs the non-atomic sequencer: duplicate sequence numbers | RT+IN | P, L | `message/message.sequencer` | |
| 112 | slack_maintenance_collision | slack | Postgres checkpoint schedule at offset 35 s, inside write peaks | IX+RT | M, P | `db/db.maintenance-controller` | |
| 113 | slack_logins_unread_sends_all_slow | slack | shared Redis switched to strict consistency (250 ms/op) | RT | M/T, P | `redis/redis.cache-policy` | |
| 114 | slack_sends_fail_strict_mode | slack | strict-read toggle on channel + channel DB pool 3/2 (2 causes) | MC+IX | L, P | `channel/channel.membership-acl`; `channel/channel.db-pool` | |
| 115 | slack_sends_fail_compliance_window | slack | channel DB pool 3/2 exposed by a mandated strict window | IX+RT | L, P | `channel/channel.db-pool` | |
| 116 | slack_seq_lock_leak | slack | boot transaction keeps a channel_seq row lock; pool starves | RT | P (pg_locks), L | `message/message.sequencer` | |
| 117 | slack_distractor_volume_seq_lock | slack | same family behind heavy log noise | RT | P, L | `message/message.sequencer` | |

Notes on the table:
- Several injectors **delete and re-create** the Deployment (`inject_virtual.py`: wrong_bin_usage,
  sidecar_port_conflict, liveness_probe_too_aggressive, readiness_probe_misconfiguration, duplicate_pvc_mounts,
  service_port_conflict, rbac_misconfiguration). Then there is no previous ReplicaSet to diff against; the
  in-cluster change signals left are "created after its siblings" and comparison with sibling workloads (Helm
  release Secrets, which hold the rendered manifests, are hidden from agents). `rolling_update_misconfigured` and `liveness_probe_too_aggressive` even create a
  brand-new workload (`custom-service`, `aux-service`) that has no healthy baseline at all.
- Incident Arena problems (108-117) are graded per cause and the score is the **minimum** over causes
  (`llm_as_a_judge_oracle.py`), so 108, 109 and 114 need every cause named.

## 2. Counts per category

### 2.1 Primary category, 107 non-C core problems
| category | all 107 | share | Lite (17) | 0508 cohort, non-C (48) |
|---|---|---|---|---|
| WS one workload's spec | 29 | 27% | 6 | 18 |
| RT runtime state | 18 | 17% | 2 | 0 |
| CL outside / cluster object | 17 | 16% | 3 | 7 |
| CO config object in app ns | 16 | 15% | 3 | 11 |
| IX interaction | 11 | 10% | 2 | 4 |
| NI node / infra | 7 | 7% | 0 | 4 |
| MC many components / causes | 6 | 6% | 0 | 2 |
| IN input / load | 3 | 3% | 1 | 2 |

Counting secondary tags too: IN appears in 10 problems, IX in 15, MC-like scope (GT names more than one
object, or many affected) in about 12.

Sample C by name only (my guess from the id, not verified, kept out of the counts above):
configmap_drift (CO), missing_service (CO), resource_request_too_small (WS), scale_pod_zero (WS),
stale_coredns_config x2 (CL), persistent_volume_affinity_violation (CL or NI), payment_service_failure,
ad_service_manual_gc (flagd-style CO by analogy with their siblings), kafka_queue_problems (IN or CO).

### 2.2 Which categories are big
- Fact: no single category is a majority. WS is the largest at 27%; the "outside the one bad Deployment"
  categories (CO, CL, RT, IX, NI, IN, MC) together are 73% of the full set.
- Fact: Lite over-weights WS/CO/CL (12 of 17) and has no NI or MC. The leaderboard cohort (non-C part) is
  WS 18 + CO 11 + CL 7 = 75%; 7 of its 11 CO ids are feature flags (5 flagd, 2 TrainTicket).
- Fact: RT is 17% of the registered set but 0 of the named cohort ids: it is concentrated in the Incident
  Arena, GitLab/Stripe and newer astronomy-shop problems. Opinion: these are where the benchmark is growing.

### 2.3 What the ground truth names as the origin (107 non-C)
| GT origin form | count | examples |
|---|---|---|
| a workload (Deployment/CronJob, with kind or bare) | 45 | most WS problems; also 97 (victim Deployment) |
| a bare service name while the mutation sits in another object | 8 | flagd faults 72-82 (`ad`, `cart`, `frontend`), 35 (`mongodb-geo`, ConfigMap deleted), 89 (`recommendation`, NetworkPolicy) |
| a Service (`service/x` or bare meaning the Service) | 11 | datastores whose runtime state broke (7-12, 20), selector faults (65-67), traffic policy (91) |
| a ConfigMap | 4 | `configmap/rpc` (16, 18), `configmap/coredns` (50, 51) |
| cluster-scoped / outside objects incl. CRs | 14 | webhook configs, PriorityClass, namespace, BGPPeer, `cluster-networking`, ClusterRole, kube-system CronJob, kube-proxy DaemonSet, TiDBCluster CR x5 |
| Ingress / ResourceQuota | 3 | 87, 88, 39 |
| node | 4 | 41, 99, 100, 90 (node table + 2 Deployments) |
| a data object (topic, table) | 3 | 34, 42, 81 |
| an interaction path | 1 | 19 |
| a logical app component (IA, GitLab, Stripe) | 14 | `channel/channel.db-pool`, `gitlab-ce-db`, `feature-catalog` |

Fact: the GT convention is **not** "the object that was mutated". In about 14 problems the mutation sits in
one object and the GT names another (flagd flags -> the service; `frontend-runtime-config` -> `deployment/frontend`;
rotated Secret -> `deployment/product-catalog`; flood Job -> `service/valkey-cart`; deleted ConfigMap -> bare
`mongodb-geo`; NetworkPolicy -> bare `recommendation`; webhooks + NetworkPolicies -> `deployment/recommendation`).
In others the GT names exactly the mutated outside object (CoreDNS ConfigMap, webhook configs, PriorityClass,
namespace, kube-system CronJob, `configmap/rpc`). A pipeline cannot pick "the" origin by one rule; it has to
name both the changed object and the component it breaks, and state which is which (see section 3.4).

### 2.4 Decoys built into problems (facts)
`cfs_cpu_throttling` adds CPU limits to decoy services (`CPU_LIMIT_DECOYS`); `mutating_webhook_resource_limits`
installs 4 inert decoy webhooks; `cumulative_admission_webhook_timeout` adds inert companion webhooks and a
near-miss kube-system NetworkPolicy allow; TrainTicket turns on 3 random decoy flags
(`inject_tt.activate_decoy_flags`); `slack_distractor_volume_seq_lock` hides the cause behind log noise;
`wrong_bin_usage`, `rolling_update_misconfigured`, `liveness_probe_too_aggressive` re-create or add workloads
so "recently changed" is true of the fault object and of nothing else, but the run's own conductor actions
(rollout restarts by the flagd injector, pinning via nodeSelector in internal_traffic_policy) also look like
recent changes on innocent workloads.

## 3. How the judge grades (facts from code)

Files: `sregym/conductor/oracles/llm_as_a_judge/judge.py`, `rca_checklists.yaml` (version 3.0),
`llm_as_a_judge_oracle.py`; ground truth from each problem's `self.root_cause`.

### 3.1 Inputs and scoring
- The judge sees two texts only: the ground truth and the agent's diagnosis. No cluster state, no tool
  trace. Ground truth is one string built by `Problem.build_structured_root_cause` (`problems/base.py`):
  `[fault_spec] component=<X>; namespace=<ns> || <prose>`. There is **no** separate `fault_mechanism`,
  `injector_method` or `parameters` field, although the checklist hints mention them; the judge infers them
  from the prose. So the prose is the answer key, including every component it happens to mention.
- 9 Yes/No questions, 3 per dimension; dimension score = Yes/3 (rounded to 0.33/0.67); composite =
  0.33*D1 + 0.33*D2 + 0.34*D3; pass if >= 0.70. Arithmetic: **pass exactly when at least 7 of 9 answers are
  Yes** (every 6-of-9 split gives 0.66-0.67; every 7-of-9 split gives 0.77-0.78). A report may lose at most 2
  questions.
- The system prompt: "Answer based ONLY on what is explicitly stated in the diagnosis. Do NOT infer". An unstated
  detail is a No even if the pipeline knew it.
- Empty text or a parse failure after 2 tries = all No (score 0). `lite5_finalizer_deadlock_controller` shows
  0.0 for all 4 arms with empty text and no checklist.
- A list of causes (Incident Arena) is graded once per cause with the full context and the score is the
  minimum (`LLMAsAJudgeOracle.evaluate`).

### 3.2 What each question checks (checklist text, condensed)
- D1-Q1 names the same service/deployment/pod/node/infra component as the GT origin (hint: compare against
  `target_component` and `target_resource_kind`). D1-Q2 separates the origin from cascading points. D1-Q3 does
  not call a healthy component the origin.
- D2-Q1 same injected mechanism. D2-Q2 concrete mutated details (key, wrong value, port, selector, tag,
  limit). D2-Q3 does not attribute it to a wrong fault type.
- D3-Q1 does not blame components the GT does not name as contributing. D3-Q2 includes **all** components the
  GT lists as contributing to **or affected by** the fault. D3-Q3 impact/symptoms consistent with the GT.

### 3.3 How diagnoses lose points (from the `Checklist details` of the graded runs listed above)
Points lost, grouped by cause (problem: arm; quote of the judge's evidence):
1. **Wrong origin = near-zero.** One wrong origin costs D1 x3 plus usually D2-Q1/Q3 and D3-Q1. Examples:
   valkey_memory_disruption, all 16 arms over held3-6 fail (blame the flood Job or `deployment/cart`; GT is
   `service/valkey-cart`); tgt_update_incompatible_correlated v2 (blames `rate`, scores 0 and 11);
   lite6_secret_rotation v2 (blames ConfigMap `postgresql-init`, 11 and 45).
2. **Right object, wrong kind label.** "names deployment/valkey-cart; the authoritative fault target is
   service/valkey-cart" cost D1-Q1 (lite6_valkey_auth arm1, held5_valkey_memory arm0); same for
   `Deployment url-shorten-mongodb` vs `service/url-shorten-mongodb` in held5_auth_miss arms 2-3, while the same
   wording passed D1 in held6_auth_miss arm2. The judge is inconsistent here, so naming both kinds is safer.
   For wrong_service_selector the kind decides everything: held_wrong_service_selector v2 named
   `deployment/frontend` and scored 44/55 although the mechanism (selector) was right.
3. **A second "root cause" label on the victim.** v1's "Root cause component: Deployment frontend" while its
   mechanism names the CoreDNS ConfigMap lost D1-Q2, D1-Q3, D3-Q1 (held3/held4 DNS v1 arms: 55). Same for
   internal_traffic_policy v1 ("Root cause component: Deployment recommendation", GT Service).
4. **Missing concrete values (D2-Q2).** "omits initialDelaySeconds=0, periodSeconds=1, failureThreshold=1, and
   terminationGracePeriodSeconds=0" (liveness_probe_too_aggressive, all 8 arms in held2/held5); "does not identify hostPort 9100 … collision with
   prometheus-node-exporter" (service_port_conflict, all 8 arms); "does not specify that the sidecar … uses the
   primary application's listening port" (sidecar, 7 of 8 arms).
5. **A wrong explicit fault-type label (D2-Q3).** "Fault type: resource limits" on a regex fault
   (lite6_edge arm0) and on an env-shadowing fault (lite6_env_shadowing arm0); "code bug" on the liveness fault;
   "job lifecycle" on valkey memory; "other (an uncategorised fault)". A category line only adds risk.
6. **Under-attribution of affected components (D3-Q2), the most common single loss.** The GT prose lists
   victims and the judge wants them named: checkout for incorrect_image (8 of 8 arms lost it), "dependent
   services" for CoreDNS faults, prometheus-node-exporter for hostPort conflicts, "other noncompliant workloads"
   for the ResourceQuota (all 4 lite6 arms), "all pod CREATE operations in social-network" for the mutating
   webhook (all 4 arms), the 5 other mongodb-* for update_incompatible (both v1 arms, 89 instead of 100).
7. **Over-attribution (D3-Q1)** when an extra component is written as blamed or broken: "Adds that frontend
   'fails as a result'" (held5_incorrect_image arm0), "compose-post-service" (held2 port conflict v2),
   "otel-collector-agent … cannot be ruled out" (lite6_valkey_auth arm2). The judge is noisy: the same
   "fails as a result" line was accepted in held3.
8. **Impact text that does not match the GT story (D3-Q3)**: env shadowing reported as OOMKilled restarts
   instead of "routes to the wrong upstream while Running and Ready" (all 4 lite6 arms); valkey memory reported
   as "an active, incomplete Job" instead of cache OOM.
9. **Partial mechanism for feedback loops (D2-Q1)**: search_rate_retry_collapse v2 lost D2-Q1 for omitting the
   transient burst and post-burst amplification even though it named the retry loop.

### 3.4 Report shape that scores best (derived from 3.1-3.3; opinion where stated)
- One origin sentence that names the object the GT is likely to name, with kind, name and namespace, and when
  the change sits in another object, names that too as the means: e.g. "Root cause: Service `valkey-cart`
  (the valkey-cart server, Deployment `valkey-cart`) ran out of memory because Job `valkey-memory-flood` writes
  1 MB values". Never a second line that calls a different object "root cause component".
- Mechanism in the GT's family words (readiness probe, selector, NXDOMAIN template in the CoreDNS ConfigMap,
  hostPort conflict, requirepass/NOAUTH, retry storm with timeout and retries) plus the concrete mutated field,
  its bad value and, when known, the good value and the conflicting party.
- An "affected" list that names direct victims and dependent callers as victims, with their symptom, kept
  apart from the cause. Opinion: given D3-Q2 is lost far more often than D3-Q1, listing direct dependents as
  affected is a net gain, as long as they are labelled victims.
- Impact described the way an SRE would summarise it (state + user effect: "0 endpoints so requests time out",
  "pods Running and Ready but routed to localhost").
- No fault-category label, no "cannot be ruled out" alternatives, no evidence dump that reads as blame.
  Opinion: v1/v2's long "Evidence:" sections are mostly harmless but are where stray component names (D3-Q1)
  come from.

## 4. Evidence sources: available vs used

### 4.1 What SREGym gives an agent (facts: `mcp_server/`, `README.md`, `sregym/observer/`)
- **kubectl** through the MCP server (`/kubectl`: `exec_kubectl_cmd_safely`, rollback tools) and a
  KUBECONFIG through the conductor's API proxy (`sregym/service/k8s_proxy`), optionally restricting workload
  creation/network (`RESTRICT_NETWORK_ACCESS`). Includes `logs`, `exec`, `top`, `auth can-i`, every resource
  kind including cluster-scoped objects and CRDs.
- **Prometheus** (`/prometheus`): `get_metrics(PromQL)` and `get_alerts`. Stack: prometheus chart with
  kube-state-metrics and node-exporter (`observer/prometheus`), cAdvisor container metrics.
- **Jaeger** (`/jaeger`): `get_services`, `get_operations`, `get_traces(service, minutes)`,
  `get_dependency_graph`. Apps export traces (DeathStarBench Jaeger, OTel collector for astronomy shop).
- **Loki** (`/loki`): `get_logs(LogQL, minutes)`, label listing (promtail ships pod logs).
- **submit** (`/submit`).
- **What is hidden from the agent** (`sregym/service/agent_visibility_policy.py`, `k8s_proxy.py`): the
  `chaos-mesh` and `khaos` namespaces, the `chaos-mesh.org` API group and Chaos Mesh events; objects labelled
  `app=load-generator`, `app=locust-fetcher`, `opentelemetry.io/name=load-generator`, `job=workload`,
  `network-access=restricted`; Helm release Secrets ("benchmark source data, not runtime evidence"; they hold the
  rendered manifests). In filtered network mode, exec into host-network pods is refused. Consequences: the
  3-5 s product-catalog delay in missing_stale_cache_fallback (Chaos Mesh) and the load generator in
  loadgenerator_flood_homepage are invisible as objects; only their effects (latency, traffic) can be seen.
- The `full` profile is the leaderboard profile; `svelte` removes astronomy-shop's bundled Jaeger/OpenSearch/
  Grafana and Alertmanager and is "not comparable" (README).

### 4.2 What the team's pipelines use (facts: `clients/jev_diag`, `clients/jev_v2`)
v2 does not collect anything of its own: it reuses v1's `ClusterSnapshot` and `investigate.py` detail
(`jev_v2/agent.py` imports `collector`, `tree.detail_evidence`).

| source | used | how |
|---|---|---|
| kubectl objects, app namespaces | yes | Deployments, StatefulSets, DaemonSets, CronJobs, Jobs, ReplicaSets, Pods, Events, Services, Endpoints, NetworkPolicies, HPAs, PVCs, LimitRanges, ResourceQuotas, Secrets, ConfigMaps (`collector.py` ~2009-2102) |
| kubectl, cluster scope | partly | Nodes, Namespaces (labels), Mutating/ValidatingWebhookConfigurations, CoreDNS ConfigMap + pods, Roles/ClusterRoles reachable from app ServiceAccounts; RoleBindings in `investigate.py` |
| change history | yes | managedFields write times, created-after relations, ReplicaSet/ControllerRevision template diffs (`changes.py`); no comparison with shipped manifests |
| logs | yes | `kubectl logs` current + `--previous`, tail-limited, error-line extraction |
| `kubectl top` | yes | pod/container CPU and memory |
| Prometheus | alerts only | `fetch_alerts_via_mcp` (`get_alerts`); **no PromQL** |
| live probes | optional, off by default | `probes.py`: Kafka consumer offsets, PING / pg_isready / mongo ping inside a backend; only with `--exec-probes` / `JEV_DIAG_EXEC_PROBES=1`, which `agents.yaml` does not set |
| Jaeger traces / dependency graph | **no** | |
| Loki | **no** | |
| Ingress, PriorityClass, StorageClass, PV, CRDs (Calico, TiDBCluster), kube-system workloads other than CoreDNS (kube-proxy, CronJobs), other namespaces (policy-system, tenant/holder namespaces) | **no** | |
| node internals (conntrack, df, kubelet config, clock), DB internals (users, grants, pg_locks, sequences), Valkey config/memory | **no** (except the optional probes above) | |

### 4.3 Which problems need what the pipelines ignore (opinion, from the table's evidence column)
- PromQL metrics are needed or strongly helpful for about 12 (cpu throttling, retry storms 16/18/19, gc, edge
  CPU, ad high CPU, loadgenerator flood, valkey memory, workload imbalance, slack maintenance/redis).
- Traces for about 9 (flagd error/latency faults 72-79, missing cache fallback 37/38, stale hostAliases,
  postgres lock, env shadowing wrong upstream).
- Outside objects not collected today for about 13 (Ingress 87/88, PriorityClass 44, kube-system CronJob 40,
  kube-proxy 101, Calico 92/93, TiDB CRs 102-106, other-namespace NetworkPolicies 97).
- Live probes into data or nodes for about 15 (RT datastore faults, Kafka offsets, SQL state, node conntrack,
  kubelet config, TLS/HTTP through an Ingress, Incident Arena DB/Redis settings).

### 4.4 Results so far by category (latest runs: lite5/6, held2-6, tgt; arms on one snapshot are not independent, small n)
| category | v1 arms passing | v2 arms passing |
|---|---|---|
| WS | 33/38 | 30/38 |
| CO | 10/10 | 10/10 |
| CL | 5/12 | 10/12 |
| IX | 6/8 | 6/8 |
| RT | 1/4 | 0/4 |
| IN | 0/10 | 2/10 |
| MC | 2/2 | 0/2 |
Fact: both pipelines are good where kubectl state shows the fault (WS, CO); weak where it does not (RT, IN).
CL v1 includes lite5_finalizer, where all 4 arms submitted empty text (score 0). IN is mostly
valkey_memory_disruption (16 arms, none pass). These categories are from my table; runs cover only 29 problems.

## 5. Implications: what a pipeline must express and observe to cover ~90%

Coverage arithmetic (107 non-C core problems, primary category): WS+CO+CL = 62 (58%); +RT = 80 (75%);
+IX = 91 (85%); +NI = 98 (92%). So **90% needs every category except at most IN and MC**, i.e. runtime state,
interactions and node faults cannot be skipped. On the 48 non-C cohort ids, WS+CO+CL = 75% and +IX+NI = 92%.

### 5.1 It must be able to express (in the report and in its internal candidate space)
1. **An origin of any kind**, not only a workload: Deployment/StatefulSet/CronJob, Service, ConfigMap in the
   app namespace or kube-system, Secret, Ingress, NetworkPolicy, ResourceQuota, Namespace (labels),
   Mutating/ValidatingWebhookConfiguration, PriorityClass, ClusterRole, DaemonSet in kube-system, CRs
   (TiDBCluster, Calico BGPPeer/IPPool), Node, a data object (topic, table), an interaction path, and logical
   app components. Fact: v1's report leads with a workload ("Root cause component: Deployment X") plus an
   optional "Fault object: Service Y" line, or, for some outside-object families, "Root cause object:
   MutatingWebhookConfiguration Z, acting on Deployment X" (lite6_mutating_webhook arm2); v2's
   `Explanation.origin` is any `kind/ns/name` plus `interaction/` and `input/`. The same v1 shape (workload
   first, changed object as "Fault object") scored 100 on wrong_service_selector (held arm2) but 55 on the
   CoreDNS fault (held3/held4 arms 2-3): the judge does not treat that shape consistently.
2. **Two names per cause: the changed thing and the broken thing**, with the relation stated, because the GT
   names one or the other depending on the family (section 2.3). Examples: flag in flagd-config -> service;
   flood Job -> valkey-cart; Secret rotation -> product-catalog; webhook -> victim Deployment.
3. **Several origins** (6 mongodb Deployments; "all deployments"; 2-4 independent causes where the score is
   the minimum over causes).
4. **Concrete values for ~25 mutation types**: env name and value (missing, duplicated, wrong port), image tag,
   command/binary, probe numbers, container/host ports and who else holds them, selector labels, dnsPolicy and
   nameservers, sysctl, ulimit, CPU/memory limits and what set them, regex, flag name and variant, Corefile
   template, caBundle, PSA label, priority values, toleration effect, replicas, rollout strategy, init command,
   RPC timeout/retries, GOGC, NetworkPolicy rules, internalTrafficPolicy, Ingress path->backend.
5. **Blast radius**: direct victims and dependent callers named as victims (D3-Q2 is the most common loss).
6. **Feedback-loop stories** (trigger + amplifier + why it persists) for IX problems; D2-Q1 needs all parts.

### 5.2 It must be able to observe
1. Everything it collects today, plus: objects outside the app namespace (Ingress, PriorityClass, StorageClass,
   PV, kube-system DaemonSets/CronJobs, NetworkPolicies and Jobs in other namespaces, CRDs).
2. A baseline for workloads that were deleted and re-created or newly added. In-cluster options: "created
   after its siblings" as a change signal, comparison with sibling workloads of the same app, and the
   object's own managedFields. Opinion: reading the shipped manifests in `SREGym-applications/` from disk is
   probably against the benchmark's intent, since the proxy deliberately hides Helm release Secrets (the
   rendered manifests) from agents; I would not rely on it without asking.
3. PromQL: CPU throttling (`container_cpu_cfs_throttled_*`), memory/OOM, request and retry rates, per-pod load
   skew. Traces: error and latency per edge, deadline errors, which upstream a proxy actually calls.
4. Read-only probes: DB auth and locks and sequences, Valkey `CONFIG GET`/memory, Kafka group offsets, HTTP and
   TLS through an Ingress, node conntrack/df/kubelet config/clock (node access may not exist on the leaderboard
   setup; uncertain).
5. A contrast step against decoys (section 2.4): inert webhooks, decoy CPU limits, decoy flags, log noise,
   conductor-caused restarts.

### 5.3 Opinions for the redesign (marked as opinion)
- The single biggest lever is not a better choice among workload candidates; it is a **wider candidate space**
  (any object kind, data/runtime origins, interactions) fed by **more evidence sources** (metrics, traces,
  outside objects, probes). Today's two pipelines are tuned to the 58% of problems where kubectl shows the fault.
- The second lever is the **report contract**: origin naming in the GT's vocabulary with both changed and broken
  objects, concrete values, victims listed as victims, no category label. This is cheap and touches every
  problem (it would have turned several 66-78 scores in held2/held5 into passes).
- Because "the origin" depends on the fault family's convention, the decision model should choose among
  complete chains (changed object, broken component, mechanism, values, victims) rather than among single
  components; v2's `Explanation` already has that shape but its candidate generators (`patterns.py`) only cover
  what the snapshot contains.
- Lite is a poor proxy for the full benchmark: no NI or MC, little RT, and 12 of 17 in WS/CO/CL.
