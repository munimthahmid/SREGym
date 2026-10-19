# v1 weakness review: every way v1 loses points, and whether STRATEGY.md fixes it

Status: complete (2026-10-19). Read-only review. Sealed Unseen problems were not opened (see "Method and limits").

Sections: 1. Run walk (every v1 point loss in every run). 2. Coverage matrix (v1 outcome on every non-sealed
problem, observed or predicted). 3. Weakness catalog. 4. STRATEGY.md check and proposed general fixes.

"Fact" = read in code or run files. "Prediction" = my reading of what v1's code would do on a fault it never ran on.
Weakness codes (V1..V27) are defined in section 3; section 1 and 2 use them as tags.

---------------------------------------------------------------------------------------------------------------
## 1. Every v1 point loss in every run

Data: all 81 labels in `runs-index.tsv`, arms 2 (v1+Jev) and 3 (v1+Decisions). 80 runs have a graded file = 160 v1
arms. `held_duplicate_pvc_mounts_hotel_reservation` has no graded file; both v1 texts name the RWO PVC shared by 2
frontend replicas, so they would very likely pass. v1 code is identical in every run (6400cd46), so variation is
snapshot + model + judge only.

Totals (fact): 115 of 160 v1 arms pass (72%), 66 get full marks, 94 lose at least one answer, 260 checklist answers
are lost. Lost answers by question: D1-Q3 43, D3-Q2 36, D1-Q2 34, D1-Q1 31, D2-Q2 30, D2-Q3 27, D2-Q1 23, D3-Q3 18,
D3-Q1 18. Three arms scored 0 because a model API call failed (402 twice, 502 once), not because of a diagnosis.
137 of 160 arms made exactly 2 model requests.

### 1.1 Per fault (all runs pooled; scores are judge composites x100)

| Fault (set) | v1 arms pass | Scores seen | Lost answers | Mechanism of every loss (fact unless marked) | Tags |
|---|---|---|---|---|---|
| kafka_poison_pill_hol_block (Lite) | 0/6 | 67 x3 Jev, 56 x3 Dec | D1-Q1/Q2/Q3 x6, D2-Q2 x3 | v1 finds `ORDERS_TOPIC=orders-fulfillment` and offset 20, but the report must lead with a workload ("The blocked component is Deployment orders-validator"); GT origin is the topic. Dec also picks the consumer.py script as key evidence, so no malformed-record detail. Broker probe off. | V1, V5, V22, V8 |
| search_rate_retry_collapse_hotel_reservation (Lite) | 0/6 | 34 x6 | D1 x18, D2 x18 | Triage 0.95-0.99 on `rate`; origin_p 0.44-0.57 (< 0.6) so it walks rate -> consul/memcached or rate -> search (search judged victim 0.82-0.93), fallback "most likely origin" = rate, key = `RATE_BACKEND_QPS_LIMIT=20`. No way to name the search-to-rate path, the retry policy on the caller, or a feedback loop; no metrics. | V4, V1, V9, V22, V19 |
| valkey_auth_disruption (Lite) | 0/6 | 34, 45, 34 Jev; 0 (502), 23, 23 Dec | D1-Q1 x5, D1-Q3 x4, D2 x15, D3-Q1 x5, D1-Q2 x2 | `requirepass` set at runtime; nothing in spec, config or server log. Client line "Wasn't able to connect to redis" is classed connectivity, not auth. Jev walks 6-7 components, valkey-cart judged "unrelated", ends by "end of a victim chain" fallback, category `service_routing` / `network_policy`; report adds "otel-collector-agent / cart cannot be ruled out". Dec ends on triage top-1 `cart` (a victim). "Deployment valkey-cart" vs GT "service/valkey-cart" costs D1-Q1 even when the name is right. One Dec arm died on HTTP 502 (score 0). | V8, V14, V18, V19, V20, V2(kind), V23 |
| valkey_memory_disruption (A) | 0/8 | 45 x8 | D1 x24, D2-Q3 x8, D3-Q3 x8 | Triage 0.71-0.93 on `job/valkey-memory-flood` (its only signal "job has 1 active pod and has not completed" is tagged `configuration` by string markers), origin 0.86-0.97, category `job_lifecycle` / `config_value`. GT origin is the broken server `service/valkey-cart` (OOMKilled). v1 must pick one end of "load source -> victim" and has no memory metrics. Identical 45 in all 8 arms. | V3, V1, V14, V19, V9 |
| service_dns_resolution_failure_astronomy_shop (A) | 1/6 | 89 once (Jev, origin_p 0.56 < 0.6 so the cluster node ran); 55 x5 | D1-Q2/Q3 x5, D3-Q1 x5, D3-Q2 x6 | Triage `other` 0.72-0.87 (Jev) but `other` is moved behind the first workload, frontend reaches origin_p 0.61-0.95 and wins; the "higher-ranked unexamined" check ignores `other`. Report "Root cause component: Deployment frontend" with the CoreDNS rule only as mechanism. Dec puts 0.55-0.96 on frontend at triage, then confirms it as origin at 0.94-0.95 (yes-bias on the asked candidate). All arms miss the dependent services (D3-Q2). | V16, V2, V15, V17, V21 |
| service_dns_resolution_failure_social_network (Lite) | 3/6 | Jev 89 x3, Dec 67 x3 | D1-Q2/Q3 x3, D3-Q1 x3, D3-Q2 x3 | Same mechanism: Jev origin_p 0.45-0.54 -> cluster node -> 89; Dec origin 0.99 on user-service -> 67. Pass/fail decided by which side of 0.6 the workload lands. | V16, V2, V15, V17, V21 |
| liveness_probe_too_aggressive_social_network (A) | 1/4 | 67, 89 (held2); 67, 0 (held5) | D2-Q2 x4, D2-Q1 x3, D2-Q3 x3, all 9 in the 0 arm | `describe_probe` renders only the probe target, so `periodSeconds 1 / failureThreshold 1 / initialDelay 0` never reach an evidence option; `terminationGracePeriodSeconds` is not collected in detail. Jev category `code_bug` (67). held5 Dec: aux-service "undetermined" 0.45, cluster node picks the leftover CoreDNS change from an earlier problem (0). | V7, V19, V11 |
| edge_request_filter_cpu_saturation (Lite) | 3/6 | Jev 67 x3, Dec 89 x3 | D2-Q1 x6, D2-Q2 x3, D2-Q3 x3 | One revision changed command, args (WAF regex), env and `limits.cpu`. One key-evidence pick: Jev picks "limits.cpu unset -> 100m" every time (D2 = 0); Dec picks the regex but the report never says "catastrophic backtracking / CPU saturation" (D2-Q1). The evidence list hit the 32-item cap in all 6 arms and every log line was cut. | V5, V22, V9, V27 |
| secret_rotation_stale_env_credentials_astronomy_shop (Lite) | 5/6 | 100 x5, 34 (lite6 Dec) | 6 answers in the 34 arm | lite6 Dec: product-catalog origin 0.49 vs victim 0.45, just under 0.6, so the walk continues to postgresql, which gets origin 0.68 and wins with the init.sql key fact. Pair node only runs when the first side crosses 0.6. | V15, V17 |
| missing_env_variable_astronomy_shop (T) | 1/2 | Jev 22, Dec 100 | 7 answers in the Jev arm | Revision diff "env CART_ADDR removed" exists but managedFields show no later write, so no change record and no triage signal. The real error ("Could not parse target name") names nothing; a relayed frontend error names email/shipping/quote. Jev triage email 0.36, frontend judged victim 0.82 although its key evidence was the removal, walk of 6, fallback triage top-1 = email. Dec reached frontend first and won by fallback. | V10, V13, V18, V15 |
| duplicate_pvc_mounts_social_network (Lite) | 7/8 | 100 x7, 0 (rerun Dec) | 9 in the 0 arm | rerun Dec: triage `other` 0.46, first workload unrelated, cluster node picks the CoreDNS ConfigMap rewritten 35 min before the app was even deployed (leftover of an earlier problem). Score 0. | V11 |
| finalizer_deadlock_controller_hotel_reservation (Lite) | 6/8 | 100 x6, 0 x2 | none graded | lite5: OpenRouter HTTP 402 on the first request; `diagnose` raises, nothing is submitted. | V23 |
| internal_traffic_policy_local_astronomy_shop (Lite) | 6/6 | 89, 100, 100, 89, 78, 89 | D1-Q3 x4, D3-Q1 x1 | "Root cause component: Deployment recommendation" with the Service as a secondary "Fault object" line; judge inconsistent on the same shape (78-100). | V2 |
| service_wrong_pod_selection (Lite, incl. arms01) | 6/6 | 89, 89, 100, 89, 100, 100 | D1-Q3 x3 | Same workload-first framing for a Service selector fault. | V2 |
| auth_miss_mongodb (A) | 4/4 | 78, 78, 100, 77 | D1-Q1 x2, D3-Q2 x3, D3-Q3 x1 | "Deployment url-shorten-mongodb" vs GT `service/...` (D1-Q1 No in held5, Yes in held6). Clients of the database never listed; Dec does not describe client TLS handshake failures. | V2(kind), V21, V22 |
| incorrect_image (A) | 4/4 | 89 x4 | D3-Q2 x4 | Checkout (a caller) never listed. Frontend's errors say `connect ECONNREFUSED 10.96.131.201:8080` (the product-catalog ClusterIP): IPs are not mapped to Services, so no "impact on other components" line at all, although `product-catalog.clients` (from env addresses) already lists checkout. | V21, V13 |
| mutating_webhook_resource_limits_social_network (Lite) | 6/6 | 89 x6 | D3-Q2 x6 | Scope of the carrier object (all pod CREATEs in the namespace) never stated; only the investigated workload. | V21 |
| namespace_memory_limit (Lite) | 6/6 | 89 x6 | D3-Q2 x6 | Other workloads that declare no memory and would be rejected on restart are not listed. | V21 |
| service_port_conflict_social_network (A) | 4/4 | 78 x4 | D2-Q2 x4, D3-Q2 x4 | Mechanism is the FailedScheduling event "didn't have free ports". `hostPort` is not in the summary or detail (`ports` keeps only containerPort), and the DaemonSet holding 9100 lives outside the app namespace, so neither the value nor the other party can be named. | V7, V6, V21 |
| sidecar_port_conflict_hotel_reservation (A) | 4/4 | 100, 89, 89, 89 | D2-Q2 x3 | Mechanism is the log "nc: bind: Address already in use"; no check compares the ports the two containers use, so the shared port value is never stated. | V7 |
| env_variable_shadowing_astronomy_shop (Lite) | 6/6 | 89 x6 | D3-Q3 x6 | Report lists every abnormal signal (OOMKilled, restarts, BackOff of frontend-proxy at a 65Mi limit) as "Abnormal state", which contradicts the GT story "Running and Ready but routed to the wrong upstream"; no trace evidence of the wrong upstream. | V20, V9 |
| update_incompatible_correlated (T) | 2/2 | 89 x2 | D3-Q2 x2 | Names mongodb-geo only; the same image bump on 5 more Deployments cannot be one answer. | V1 |
| cronjob_sidecar, network_policy_block, rolling_update (social), unschedulable_port, readiness_probe (hotel), duplicate_pvc (hotel), wrong_service_selector (astronomy) | 40/40 | 100 | none | Code computes a concrete cross-object fact (sidecar keeps Job alive, policy denies all, maxUnavailable >= replicas, nodeSelector to a missing node, probe on wrong path, RWO claim x2 replicas, selector matches 0 pods) and the report quotes it. | - |

### 1.2 Lost answers by mechanism (my attribution of all 260 lost answers; each answer counted once, primary cause)

| Mechanism | Lost answers | Failing arms caused | Faults |
|---|---|---|---|
| V1/V3 answer must be one workload; GT names a topic, a set, or the other end of a load-source chain | 60 | 14 (kafka 6, valkey_memory 8) | kafka (D1), valkey_memory, update_incompatible |
| V4/V22 interaction / feedback-loop mechanism not expressible or not worded | 40 | 6 (search_rate) | search_rate (all D1+D2), edge Dec, auth_miss Dec |
| V16/V2/V17 cause object known, but the walk stops on the workload and the report leads with "Root cause component: Deployment X" (incl. Deployment-vs-Service kind) | 34 | 8 (dns) | dns x2 faults, ITP, wrong_pod_selection, auth_miss |
| V21 affected components not listed (D3-Q2) | 32 | 0 (point losses only) | dns, mutating webhook, quota, incorrect_image, service_port, auth_miss |
| V8/V14/V18 runtime state invisible, client log misclassified, wandering walk, hedge lines | 31 | 5 (valkey_auth) | valkey_auth |
| V11 leftover change from an earlier problem chosen by the cluster node | 18 | 2 (both scored 0) | dup_pvc social, liveness |
| V7 field not collected or not shown (probe timing, grace, hostPort, port collision) | 14 | 2 (liveness Jev) | liveness, service_port, sidecar |
| V5 one key-evidence pick among several real changes | 12 | 3 (edge Jev) | edge Jev, kafka Dec |
| V10/V13 revision diff never a change + relayed-name links | 7 | 1 | missing_env Jev |
| V15 near-threshold walk (0.49 vs 0.6) | 6 | 1 | secret_rotation Dec |
| V20 report text contradicting the GT story (unfiltered state dump) | 6 | 0 | env_shadowing |
| V23 model API error -> nothing submitted | (3 arms, ungraded) | 3 | finalizer x2, valkey_auth x1 |
| Total | 260 | 45 = 160 - 115 | |

Readings (opinion, from the table): (a) about 60% of lost answers come from **what v1 is allowed to say** (one
workload, workload-first framing, no interaction, no set), not from what it saw; (b) the next block is **what it
cannot see** (runtime state, hostPort, probe timing, outside objects, metrics); (c) the walk itself (threshold,
`other` handling, yes-bias) decides about 9 failing arms; (d) D3-Q2 under-listing is the most common point loss
on faults v1 otherwise gets right, and it is cheap to fix; (e) 5 arms died to things that are pure robustness
(leftover objects, API errors).

Second-order facts found while walking the runs:
- **Change list is polluted in most runs.** In 28 of the 45 lite/held/tgt snapshots (52 of all 81),
  `recent_changes` holds `daemonset/otel-collector-agent` (harness `restartedAt`) and/or
  `configmap/kube-system/coredns` rewritten by an earlier problem 6-56 minutes earlier. In the four snapshots checked, the CoreDNS write predates the creation of
  every workload of the app under test (e.g. held5_liveness: CoreDNS 03:06:07, app workloads 04:01:46).
- **The true fault object is often not a change record at all.** For delete-and-recreate injectors (sidecar,
  liveness, readiness, duplicate_pvc, service_port) and for auth_miss held5, the true object has no record:
  `recent_changes` is empty or only holds the leftovers. v1 passes those on spec checks, not on "change before
  symptoms".
- **Onset is fragile.** `symptom_onset` is null in 3 snapshots and earlier than the injected change in others
  (service_wrong_pod_selection: "Service frontend was modified ... 124s after the first active symptom";
  secret_rotation: all injected changes 25-29 s *after* the onset), because the onset is the global earliest
  abnormality, including harness and pre-existing noise.
- **Evidence cap.** 45 of the ~200 v1 investigation requests hit the 32-item evidence cap; in 33 of those every
  warning event was cut, in 12 every log line was cut (fixed order puts spec lines first).

---------------------------------------------------------------------------------------------------------------
## 2. Coverage matrix: v1 on every non-sealed problem

77 registered problems are not in `UNSEEN-SEALED.txt`. 29 have v1 runs (Lite 17, sample A 10, set T 2): their row
gives the observed v1 arm pass rate. The other 48 are predictions from the problem/injector code and v1's code
(collector, changes, derive, tree, classifier, investigate). Four non-sealed problems share their problem file with
a sealed sibling (`storage_user_unregistered-2`, `wrong_dns_policy_social_network`, `silent_data_corruption`,
`missing_stale_cache_fallback_astronomy_shop`); I did **not** open those files and used only the one-line rows in
`benchmark-landscape.md`, so their predictions are lower confidence. For flagd faults I did not open
`inject_otel.py` (shared with sealed problems) and used the problem file's own description.

Columns: **Sees** = is the cause visible in what v1 collects (Y / partly / N). **Can say** = can v1's answer shape
express what the GT names (Y / partly / N). **v1** = observed pass rate (arms) or predicted outcome
(P likely pass >= 70, B borderline 50-50, F likely fail). Tags = weakness codes from section 3.

Key facts behind several predictions (all fact, from code):
- v1 reads only the namespaces `/get_app` returns (`collector.collect_snapshot`), plus Nodes, Namespaces (labels,
  used only for webhook matching), webhook configurations, the CoreDNS ConfigMap and pods, and RBAC reachable from
  app ServiceAccounts. No Ingress, PriorityClass, StorageClass, PV, CRD/CR, kube-system workloads other than CoreDNS,
  or objects in other namespaces. For the 6 operator problems, `get_app` returns the FleetCast namespace
  (`metadata/fleet-cast.json`: `fleetcast`) while the faults live in `tidb-cluster` / `tidb-operator`
  (`conductor_api.get_app`, problem files), so v1 would not even see the broken objects (high confidence; not run).
- Summary and detail keep `containerPort` only (no `hostPort`); no pod/container `securityContext` (sysctls only
  show up in a revision diff, cut to 60 characters by `json_short`); probes rendered as target only; no
  `terminationGracePeriodSeconds`, `priorityClassName` or `paused` in summary or detail (the first two appear only in
  a revision diff, which a new or re-created workload does not have); ConfigMap values cut at 400 characters per key.
- Change records need a managedFields write >= 10 s after creation or creation >= 10 s after the objects the
  workload *calls*; a deleted-and-re-created or newly added workload with no env-address links gets none.
- A model API exception inside `diagnose` propagates; `driver.py` submits nothing.

| # | Problem (set) | What breaks / GT origin | Sees | Can say | v1 | Failing mechanism | Tags |
|---|---|---|---|---|---|---|---|
| 1 | cronjob_sidecar_blocks_completion_hotel_reservation (Lite) | sidecar keeps Jobs alive / CronJob | Y | Y | 8/8 | - | - |
| 2 | duplicate_pvc_mounts_social_network (Lite) | RWO PVC x2 replicas / deployment/jaeger | Y | Y | 7/8 | leftover CoreDNS change picked once | V11 |
| 3 | edge_request_filter_cpu_saturation (Lite) | WAF regex + 100m CPU / frontend-proxy | Y | partly | 3/6 | one key-evidence pick (Jev: CPU limit); no "backtracking / CPU saturation" words or metrics | V5 V22 V9 V27 |
| 4 | env_variable_shadowing_astronomy_shop (Lite) | duplicate FRONTEND_HOST / frontend-proxy | Y | Y | 6/6 (89) | state dump contradicts GT impact | V20 V9 |
| 5 | finalizer_deadlock_controller_hotel_reservation (Lite) | ClusterRole read-only + stuck ConfigMap | Y | Y | 6/8 | API 402 -> empty submission | V23 |
| 6 | internal_traffic_policy_local_astronomy_shop (Lite) | Service ITP Local / service/recommendation | Y | partly | 6/6 (78-100) | workload-first framing | V2 |
| 7 | kafka_poison_pill_hol_block (Lite) | poison record / kafka topic | Y | N | 0/6 | topic cannot be the origin | V1 V5 V22 V8 |
| 8 | mutating_webhook_resource_limits_social_network (Lite) | webhook sets 16Mi | Y | Y | 6/6 (89) | carrier scope not stated | V21 |
| 9 | namespace_memory_limit (Lite) | ResourceQuota requires memory | Y | Y | 6/6 (89) | other non-compliant workloads not listed | V21 |
| 10 | network_policy_block (Lite) | deny-all NetworkPolicy | Y | Y | 6/6 | - | - |
| 11 | rolling_update_misconfigured_social_network (Lite) | maxUnavailable 100% + hung init | Y | Y | 6/6 | - | - |
| 12 | search_rate_retry_collapse_hotel_reservation (Lite) | retry policy x queue / search-to-rate path | partly | N | 0/6 | interaction inexpressible; no metrics | V4 V1 V9 V22 |
| 13 | secret_rotation_stale_env_credentials_astronomy_shop (Lite) | stale env credentials / product-catalog | Y | Y | 5/6 | 0.49 vs 0.6 threshold walk | V15 V17 |
| 14 | service_dns_resolution_failure_social_network (Lite) | CoreDNS NXDOMAIN template / configmap/coredns | Y | partly | 3/6 | `other` demoted; workload-first report | V16 V2 V17 V21 |
| 15 | service_wrong_pod_selection_hotel_reservation (Lite) | broad Service selector / service/frontend | Y | partly | 6/6 (89-100) | workload-first framing | V2 |
| 16 | unschedulable_incorrect_port_assignment (Lite) | wrong port + nodeSelector / checkout | Y | Y | 6/6 | - | - |
| 17 | valkey_auth_disruption (Lite) | runtime requirepass / service/valkey-cart | N | partly | 0/6 | runtime state; log misclassified; walk wanders | V8 V14 V18 V19 V20 V23 |
| 18 | auth_miss_mongodb (A) | requireTLS without certs / service/url-shorten-mongodb | Y | partly | 4/4 (77-100) | Deployment vs Service kind; clients not listed | V2 V21 V22 |
| 19 | duplicate_pvc_mounts_hotel_reservation (A) | RWO PVC / frontend | Y | Y | 4/4 | - | - |
| 20 | incorrect_image (A) | bad image / product-catalog | Y | Y | 4/4 (89) | checkout not listed (errors cite a ClusterIP) | V21 V13 |
| 21 | liveness_probe_too_aggressive_social_network (A) | probe 0/1/1, grace 0 / aux-service | partly | Y | 1/4 | probe timing and grace never shown; residue | V7 V19 V11 |
| 22 | readiness_probe_misconfiguration_hotel_reservation (A) | probe path / frontend | Y | Y | 4/4 | - | - |
| 23 | service_dns_resolution_failure_astronomy_shop (A) | CoreDNS template / configmap/coredns | Y | partly | 1/6 | `other` demoted; workload-first report | V16 V2 V17 V21 |
| 24 | service_port_conflict_social_network (A) | hostPort 9100 vs node-exporter / media-service | partly | partly | 4/4 (78) | hostPort and other-namespace DaemonSet unseen | V7 V6 V21 |
| 25 | sidecar_port_conflict_hotel_reservation (A) | sidecar on main port / frontend | Y | Y | 4/4 (89-100) | no port-collision fact | V7 |
| 26 | valkey_memory_disruption (A) | flood Job -> OOM / service/valkey-cart | partly | partly | 0/8 | load source vs broken server; job tagged configuration | V3 V1 V14 V19 V9 |
| 27 | wrong_service_selector_astronomy_shop (A) | extra selector label / frontend | Y | Y | 6/6 | - | - |
| 28 | missing_env_variable_astronomy_shop (T) | CART_ADDR removed / frontend | partly | Y | 1/2 | revision diff not a change; relayed names; victim verdict | V10 V13 V18 |
| 29 | update_incompatible_correlated (T) | 6 Mongo images bumped / 6 Deployments | Y | partly | 2/2 (89) | one origin only | V1 |
| 30 | liveness_probe_too_aggressive_astronomy_shop | same as #21 | partly | Y | B | same as #21; astronomy adds otel/flagd noise | V7 V19 V11 |
| 31 | liveness_probe_too_aggressive_hotel_reservation | same as #21 | partly | Y | B | same as #21 | V7 V19 V11 |
| 32 | rolling_update_misconfigured_hotel_reservation | same as #11 | Y | Y | P | - | - |
| 33 | sidecar_port_conflict_astronomy_shop | same as #25 (frontend) | Y | Y | P (89) | port value not stated | V7 |
| 34 | sidecar_port_conflict_social_network | same as #25 (user-service) | Y | Y | P (89) | port value not stated | V7 |
| 35 | service_port_conflict_astronomy_shop | same as #24 (ad) | partly | partly | P/B (78) | hostPort + DaemonSet unseen | V7 V6 V21 |
| 36 | service_port_conflict_hotel_reservation | same as #24 (recommendation) | partly | partly | P/B (78) | same | V7 V6 V21 |
| 37 | wrong_service_selector_hotel_reservation | same as #27 | Y | Y | P | - | - |
| 38 | wrong_dns_policy_social_network (file not opened) | user-service dnsPolicy/nameservers / user-service | Y (dnsPolicy flag promoted to signal + revision diff) | Y | P | - | - |
| 39 | storage_user_unregistered-2 (file not opened) | admin user dropped in mongodb-rate / service/mongodb-rate | partly (server login-rejection logs, if mongod logs them) | partly | B | credentials path runs `other_side` + pair node, which may pick the client; Deployment vs Service kind; "user dropped" only if the log says so | V8 V2 V15 |
| 40 | silent_data_corruption (file not opened) | WiredTiger files overwritten on host / mongodb-geo | partly (checksum errors in logs, crash loop) | Y | B/P | no change anywhere, so harness changes compete; triage rule 4 demotes symptoms-only components unless clients' errors name it | V11 V14 |
| 41 | missing_stale_cache_fallback_astronomy_shop (file not opened) | no cache fallback + hidden 3 s delay on product-catalog / recommendation | partly (timeouts only) | N (code property) | F | recommendation's errors point at product-catalog, which looks healthy -> chain end on product-catalog or a mechanism-free pick; needs traces/latency | V9 V4 V18 V22 |
| 42 | ephemeral_port_range_hotel_reservation | sysctl `ip_local_port_range=32000 32003` on all Deployments / "all hotel-reservation deployments" | partly (revision diff `pod securityContext` cut to 60 chars, value likely lost; EADDRNOTAVAIL logs) | N (one workload) | F | names one Deployment; value truncated; others not listed | V1 V7 V21 |
| 43 | capacity_decrease_rpc_retry_storm | ConfigMap `rpc` 50ms timeout / 30 retries + latency/CPU stress / configmap/rpc | partly (ConfigMap content in detail; restartedAt on every Deployment; capacity-restraint quota/LimitRange as extra changes) | N (ConfigMap only as secondary "Fault object") | F | workload-first; no loop mechanism; many simultaneous changes | V1 V2 V4 V9 V22 V11 |
| 44 | gc_capacity_degradation | `GOGC=1` env on all Deployments + LimitRange + load / deployments/all | Y (env added in every revision diff) | N | F (~45-56) | one workload named; D3-Q2 lost; no CPU/GC metrics | V1 V9 V21 |
| 45 | load_spike_rpc_retry_storm | same ConfigMap + load spike / configmap/rpc | partly | N | F | as #43 | V1 V2 V4 V9 V22 |
| 46 | file_descriptor_exhaustion | `ulimit -n 1024` in args + ~1,100 held connections / frontend | Y (args in revision diff, "too many open files" logs) | Y | P | category label may misfire (resource_limits) | V19 |
| 47 | integer_overflow_primary_key_astronomy_shop | sequence at INT4 max (runtime SQL) + new review-writer Deployment / table@postgresql | partly (insert errors in review-writer and postgres logs) | N (table) | F | the new writer workload has errors and no change record, likely triage pick; table cannot be the origin; no SQL probe | V8 V1 V14 |
| 48 | stale_hostaliases_dns_poisoning_astronomy_shop | paused partial rollout keeps one old pod with hostAliases / frontend-proxy | partly (template flags of the current template only; `paused` not read; no "pods run two templates" check) | Y | F | many cloned workloads created as changes; split carts invisible without traces/data probes | V7 V10 V9 V8 V11 |
| 49 | wrong_bin_usage | profile re-created with command `geo` / profile | partly (command in summary; no change record after delete-and-recreate; no sibling comparison) | Y | B | relies on the model noticing name vs binary; callers' errors may name profile | V10 |
| 50 | ingress_misroute | Ingress `/api` -> recommendation-service / the Ingress | N (Ingress never read; proxy Services look like fresh changes) | N | F | object kind not collected; decoy-like new Services | V6 V1 V11 |
| 51 | node_conntrack_exhaustion_hotel_reservation | pinned client fills node conntrack / node table + client + gateway | partly (new pinned Deployment; timeouts) | N (3-part origin) | F | node internals unseen; multi-part answer | V6 V8 V4 V1 |
| 52 | pod_cidr_exhaustion_hotel_reservation | Calico tiny IPPool + strictAffinity + pods in another ns / cluster-networking | partly (FailedCreatePodSandBox events on app pods) | N | F | Calico CRs and other namespace unread; names a victim Deployment | V6 V1 |
| 53 | psa_restricted_blocks_recreation_hotel_reservation | namespace PSA label `enforce=restricted` / namespace | partly (FailedCreate event text names PodSecurity) | N (namespace) | F/B (~56-67) | namespace label write not a change; origin kind namespace not expressible; "Deployment recommendation" leads | V1 V2 V10 |
| 54 | kubelet_crash | kubelet stopped on a worker + 3 rollout restarts / node/kubelet | Y (node Ready=Unknown) | partly (`other` -> Node finding) | F/B | the 3 conductor rollouts are "changes" (rule 1); `other` is demoted; Node reason only, no "kubelet stopped posting status" | V16 V11 V17 V2 |
| 55 | astronomy_shop_product_catalog_service_failure | flagd-config flag `productCatalogFailure` / product-catalog | partly (ConfigMap change; flag JSON cut at 400 chars) | partly | F/B | the change lands on the flag reader (flagd), triage rule 1 prefers it; GT names the service | V3 V7 V11 |
| 56 | trainticket_f17_nested_sql_select_clause_error | flag in flagd-config + flagd restart + 10 decoy flags / ts-voucher-service | partly (SQL errors in voucher logs) | Y | B | flagd carries the only change; decoy flags; flag file truncated | V3 V11 V7 |
| 57 | trainticket_f22_sql_column_name_mismatch_error | same family / ts-contacts-service | partly | Y | B | same | V3 V11 V7 |
| 58-62 | operator_{overload_replicas, non_existent_storage, invalid_affinity_toleration, security_context_fault, wrong_update_strategy_fault} | TiDBCluster CR field / customresource/tidbcluster/basic | N (namespace not collected; CRs never read) | N | F | outside namespace; CR origin | V6 V1 |
| 63 | operator_wrong_operator_image | operator Deployment image typo in `tidb-operator` / that Deployment | N (namespace not collected) | Y if seen | F | outside namespace | V6 |
| 64-66 | gitlab_notification_{unannounced, intermittent, delayed_audit}_replicated | schemas dropped on primary and replicated, truncated backup / gitlab-ce-db | partly (relation-missing errors) | partly | F | runtime data state; recovery story inexpressible | V8 V22 |
| 67 | stripe_feature_config_single | ClickHouse permissions + oversized config files / feature-catalog | partly | partly | F | runtime + data | V8 V1 |
| 68-77 | frappe x2, saleor, slack x7 (Incident Arena) | runtime DB/Redis settings, app admin toggles, app.yaml pool sizes, row locks / logical components like `channel/channel.db-pool`; 3 problems have 2-4 causes scored by the minimum | partly (error logs; some app.yaml values in a ConfigMap) | N (logical sub-components; several causes) | F | logical-component vocabulary; multi-cause minimum; runtime state; metrics/DB probes needed | V1 V5 V8 V9 |

### 2.1 What the matrix says

- Observed (29 studied problems): v1 passes a majority of arms on 20, exactly half on 3 (edge, dns_social,
  missing_env) and fewer than half on 6 (kafka, search_rate, valkey_auth, valkey_memory, dns_astronomy, liveness).
  Arm pass rate 72%.
- Predicted (48 unrun problems): P 8 (#32-34, #37, #38, #46 plus #35/#36 at about 78), B 8 (#30, #31, #39, #40,
  #49, #55-57), F 32 (#53 and #54 are F/B and counted as F). Expected v1 pass rate on these is roughly 25%. This is my prediction, not a measurement.
- The predicted failures concentrate in four mechanisms: answer shape (V1/V2/V3/V4: 27 of 32 predicted fails carry
  one of them), runtime state (V8: 17), missing telemetry (V9: 15) and collection scope (V6: 9). Fixing the decision
  walk alone would move almost none of the predicted fails; fixing framing alone would move few, because most also
  need new evidence.
- The studied sets are not representative: 21 of the 29 studied faults are WS/CO/CL faults (primary category in
  `benchmark-landscape.md`) where kubectl shows the fault, versus 58% in the full non-sealed pool. Any v2 judged only
  on Lite will look good for reasons that do not carry over.

---------------------------------------------------------------------------------------------------------------
## 3. Weakness catalog

Severity = real-world likelihood (how much of the non-sealed pool it touches; categories from
`benchmark-landscape.md`: WS 27%, RT 17%, CL 16%, CO 15%, IX 10%, NI 7%, MC 6%, IN 3%) x impact (turns a pass into a
fail, or loses a point). **Runs** = lost answers / failing arms it caused in section 1 (primary attribution).
**Predicted** = rows of section 2 where it is a failing mechanism. v1-architecture codes W1-W14 are given where they
match.

### 3.1 What v1 can say (answer shape)

| Code | Weakness | Code responsible | Runs | Predicted | Severity |
|---|---|---|---|---|---|
| V1 | **The origin is one workload.** No set of workloads, topic, table, path, node, CR, namespace or logical app component can be the origin; the report always opens with "Root cause component: <workload>" or, through `other`, one cluster finding. (W6) | `classifier.COMPONENT_QUESTION` / `component_options`, `Diagnosis.component`, `build_diagnosis_text` | 60 / 14 (kafka, valkey_memory; update_incompatible D3) | 25 rows (#42-45, 47, 50-53, 58-62, 67, 68-77) | **Critical**: touches MC, IN, NI, most CL and all Incident Arena; impact D1 = 0 |
| V2 | **Workload-first framing and fixed kind.** When the cause object is a Service, ConfigMap or CoreDNS, it is printed as a secondary "Fault object" under "Root cause component: Deployment X" (only webhooks, quotas, LimitRanges, RBAC, NetworkPolicy may lead: `CARRIER_KINDS`). The workload kind is always printed, while the GT often says `service/x`. (W2, W14) | `classifier.CARRIER_KINDS`, `build_diagnosis_text` 851-864 | 34 / 8 (dns, with V16) | #43, 45, 53, 54, 39 | **High**: CO+CL = 31% of the pool; 1-3 D1 answers each, judge inconsistent on the same text |
| V3 | **One name per cause, while the GT names either the changed object or the broken one.** Load source vs. exhausted server, flag store vs. flagged service, rotated Secret vs. stale reader. Triage rule 1 ("prefer `change`") pushes toward the changed object. | triage rule 1 (`classifier.py` 278-299), `tree.fault_object` | 40 / 8 (valkey_memory) | #55-57 | **High**: ~14 problems where GT and mutation differ |
| V4 | **No interaction or two-sided cause.** Verdict is origin XOR victim; two-sided logic only for credentials/RBAC (`other_side`, `pair_node`). (W10) | `tree.VERDICTS`, `other_side` | 36 / 6 (search_rate) | #41, 43, 45, 51; points in #24, 35, 36 | **High**: IX 10% primary, 15 problems with an IX tag |
| V5 | **One mechanism, one key evidence, one cause.** A revision with 4 changed fields yields one pick; several independent causes (scored by the minimum) cannot be reported. (W6) | `key_evidence` Choice, `Diagnosis`, report "Mechanism:" line | 12 / 3 (edge Jev) | #68-77 (3 multi-cause IA problems fail on this alone) | Medium-high |
| V22 | **Mechanism is a quoted fact, never the consequence.** "limits.cpu unset -> 100m" or the regex is quoted, but not "the regex backtracks and saturates CPU"; no "retries amplify load", "clients fail the TLS handshake", "the record cannot be deserialized". | `build_diagnosis_text` ("Mechanism: <key evidence verbatim>") | (with V4) 4 extra | #41, 43, 45, 64-66 | High, and hard without an LLM |
| V19 | **Fixed 18-category taxonomy printed as "Fault type".** No runtime-state, load, interaction or data categories; the category is asked "assuming origin" at every step; a wrong label costs D2-Q3. In 21 of the 27 D2-Q3 losses the judge quotes the printed label or its gloss ("job lifecycle", "a wrong, missing, or shadowed value", "inputs or traffic pattern overwhelm"); the other 6 follow from a wrong component or mechanism. | `classifier.FAULT_CATEGORIES`, `CATEGORY_GLOSS`, report "Fault type:" | spread over V1/V4/V8 rows (27 D2-Q3) | #46 and any new class | Medium (cheap to remove) |

### 3.2 What v1 can see (evidence)

| Code | Weakness | Code responsible | Runs | Predicted | Severity |
|---|---|---|---|---|---|
| V6 | **Collection scope = the namespaces `/get_app` returns** plus Nodes, webhooks, CoreDNS, reachable RBAC. No Ingress, PriorityClass, StorageClass, PV, CRs, kube-system workloads, other namespaces (node-exporter, operator, exhaust namespaces). For FleetCast the returned namespace is not even the one that breaks. | `collector.collect_snapshot` namespace loop; `conductor_api.get_app` | 4 D3-Q2 (service_port) | #24, 35, 36 (points), #50-52, 58-63 | **High**: CL 16% + operator family; impact D1 = 0 |
| V7 | **Fields not collected or not rendered.** `hostPort`; pod/container `securityContext` (sysctls appear only in a diff cut to 60 chars); probe timing (`describe_probe` keeps the target only); `terminationGracePeriodSeconds`; `spec.paused`; `priorityClassName`; ConfigMap values cut at 400 chars per key (flag files); Node condition message; no check that two containers of one pod use the same port. | `summarize_workload`, `investigate._container_detail`, `checks.describe_probe`, `changes.json_short(..., 60)`, `CONFIG_VALUE_CHARS`, `summarize_nodes` | 14 / 2 (liveness) | #30, 31, 33-36, 42, 48, 54-57 | Medium-high: WS 27%; mostly D2-Q2 points, but those sit on the 7-of-9 line |
| V8 | **Runtime state is invisible.** DB users, grants, sequences, locks, `CONFIG SET`, app admin toggles. The only probes (`valkey-cli ping`, `pg_isready`, mongo ping, Kafka group offsets) are off in arms mode and, when on, run only after some component was judged a victim of a healthy-looking backend. (W9) | `probes.py`, `clients/jev_v2/arms.py` 71-77, `tree._maybe_probe` | 31 / 5 (valkey_auth) | 17 rows (#39, 47, 48, 51, 64-77) | **Critical**: RT 17% and all Incident Arena; impact D2 = 0 and usually D1 |
| V9 | **No metrics, traces or log store.** Prometheus is used for alerts only; no PromQL, Jaeger or Loki. Load, latency, retry, CPU-throttling, memory-growth and wrong-upstream faults have no direct evidence. | `collector.fetch_alerts_via_mcp` only | part of V4/V20 rows | 15 rows (#41, 43-45, 48, 68-77) | **High** |
| V10 | **Change detection misses real changes.** A revision diff alone never creates a change record (W3); a deleted-and-re-created or new workload with no env links gets none ("created after siblings" is not computed); namespace-label, Ingress and CR writes are not tracked; mixed revisions (paused rollout) not detected; nothing compares a workload with its siblings. | `collector.py` 2112-2124, `changes.object_change`, `summarize_workload` | 7 / 1 (missing_env Jev) | #48, 49, 53 | Medium-high: the change prior is v1's main generality engine; when it misses, triage falls back to rules that favour noise |
| V11 | **Baseline pollution and leftovers.** Changes up to 1 h old count (`CHANGE_HORIZON_SECONDS = 3600`), so a CoreDNS rewrite by an earlier problem (made before the current app was even deployed) is a "finding"; harness `restartedAt` on the OTel DaemonSet and conductor rollout restarts look like spec changes; the cluster node accepts a finding at p >= 0.6 without comparing it to workload candidates; "Other cluster-level findings" prints them. Present in 52 of 81 snapshots. | `changes.CHANGE_HORIZON_SECONDS`, `derive.cluster_findings`, `tree.cluster_node`, report | 18 / 2 (both scored 0) | #40, 43, 48, 50, 54-57 | **High**: Unseen runs back to back on the same cluster, so this will recur; impact up to 0 |
| V12 | **Onset estimate is the global earliest abnormality**, including pre-existing and harness noise, so the true change can be "after the first active symptom", or onset is null (3 snapshots). | `changes.estimate_symptom_onset` | no failing arm alone | all | Medium (silently weakens V10's prior) |
| V27 | **Fixed-order evidence cap.** At most 32 evidence items, spec lines first; 45 of ~200 investigation requests hit the cap, 33 of them lost every warning event and 12 every log line. | `tree.detail_evidence`, `MAX_EVIDENCE` | edge (all 6 arms) | any component with many spec lines | Medium |
| V26 | **Fixed timing.** 120 s start delay and one 45 s trend sample; slow faults (memory growth, storms that need minutes) or late symptoms may be missed. Not verified in runs. | `driver.py`, `DEFAULT_TREND_INTERVAL` | none seen | #43-45 possibly | Low (unverified) |

### 3.3 How v1 links and decides

| Code | Weakness | Code responsible | Runs | Predicted | Severity |
|---|---|---|---|---|---|
| V13 | **Links come from names in error text only.** Relayed names create false pointers; IP addresses (ClusterIP, pod IP) are not mapped to Services or pods; errors that name nothing (empty target) create no link. (W8) | `derive._mentions`, `investigate.failing_targets` | 4 D3-Q2 (incorrect_image) + missing_env Jev | #41, 48, 49 | Medium-high |
| V14 | **Brittle tags and classes.** `evidence_kinds` by string markers (a Job "not completed" or an alert counts as `configuration`); log classes miss auth failures worded as connection failures; triage rule 4 makes symptoms-only components ineligible; telemetry role by name regex. (W4) | `derive.classify_evidence` 586-632, `LOG_CLASSES`, triage rule 4, `OBSERVABILITY_RE` | inside valkey_memory / valkey_auth rows | #40, 47 | Medium |
| V15 | **Fixed threshold, first origin wins.** `origin_p >= 0.6` ends the search with no comparison of competing candidates; the pair node only runs when the first side crosses 0.6. 0.49 vs 0.6 and 0.56 vs 0.61 decided whole runs. (W7, W12) | `tree.diagnose` 797-830, constants 59-75 | 6 / 1 (+ DNS with V16) | all multi-candidate faults | Medium-high |
| V16 | **Cluster objects demoted.** `other` is moved behind the first workload, and the "higher-ranked unexamined" check only looks at workloads, so a workload at 0.6 beats `other` at 0.87. (W1) | `tree.initial_queue` 482-486, `diagnose` 814-821 | with V2: 8 failing arms | #54 (and CL faults generally) | High (cheap fix) |
| V17 | **Leading per-candidate question + model differences.** "Is X the origin?" draws "yes" from Decisions on 16 of 26 wrong candidates; Jev and Decisions agree on 77-80% of identical requests; one threshold for both. | `tree.VERDICTS` question, `MIN_ORIGIN_PROBABILITY` | DNS Dec, secret Dec | all | Medium-high |
| V18 | **Long walks wander and fall back to triage top-1 or "end of a victim chain"**, re-asking category from a victim's lines. When the walk runs long (7-9 calls) it almost always fails. | `tree.fallback`, `chain_characterization` | inside valkey_auth, missing_env | #41 | Medium |

### 3.4 Report and robustness

| Code | Weakness | Code responsible | Runs | Predicted | Severity |
|---|---|---|---|---|---|
| V21 | **Affected components under-listed (D3-Q2, the most common loss).** Impact lines come only from callers whose error text names the component; the static caller graph (`clients`, from env addresses) is never used; the scope of a carrier object (webhook rules, quota-violating workloads, DNS dependents) and a same-change set are never computed. | `classifier._impact_lines`, `_affected_by_object` (max 4) | 32 lost answers, 0 failing arms alone | #42, 44 and every multi-component fault | **High** (frequent, sits on the 7-of-9 line, cheap) |
| V20 | **Risky report lines.** "Low confidence: X cannot be ruled out" (D1-Q3/D3-Q1), up to 12 unfiltered "Abnormal state" lines (OOMKilled story in env_shadowing, "active incomplete Job" in valkey_memory), "Other cluster-level findings" (leftovers), "Classification: Jev confirmed ..." boilerplate. | `build_diagnosis_text` | 6 + parts of V3/V8 rows | any | Medium |
| V23 | **No degraded mode.** Any model API exception inside `diagnose` propagates; nothing is submitted (score 0). | `driver.py` 391-395, `IterativeDiagnoser.diagnose` | 3 arms -> 0 | any | Medium (rare, catastrophic, trivial fix) |
| V24 | **Hand tables and Lite-tuned constants.** Role synonyms, 4 login-rejection formats, probe commands per technology, telemetry names, thresholds 0.6/0.9/0.5/0.3, queue sizes, all tuned on Lite. | `derive.py` 125-163, `probes.py`, `tree.py` 59-75 | indirect | new apps (#56-57, 64-77) | Medium |
| V25 | **Request shape.** Triage state always above Jev's ~32 kB long-context line; ~9.5k chars of negation-heavy rules; evidence list sent twice; `fault_visible` constant 1.0 in 160/160 asks. | `classifier.build_component_questions`, `tree.build_investigation_questions` | no measured accuracy effect | - | Low-medium |

### 3.5 Ranking (likelihood x impact, my judgment)

1. V8 runtime state (Critical), 2. V1 one-workload answer (Critical), 3. V11 baseline pollution (High, recurs on
every sequential run), 4. V2/V16 framing and cluster demotion (High, cheap), 5. V21 blast radius (High, cheap),
6. V6 scope (High), 7. V9 telemetry (High), 8. V3 changed-vs-broken (High), 9. V4 interactions (High), 10. V22
mechanism wording (High, hard), 11. V7 field gaps, 12. V15/V17 threshold and yes-bias, 13. V10/V12 change and
onset, 14. V13 links, 15. V5 multi-cause, then V14, V18, V19, V20, V23, V27, V24, V25, V26.

---------------------------------------------------------------------------------------------------------------
## 4. Does STRATEGY.md fix each weakness?

Verdicts: **Full** = the plan names the fix and the fix is enough; **Partly** = the plan points at it but leaves out a
piece that decides the outcome; **No** = not in the plan. Fixes proposed here are general: they name Kubernetes
kinds, fields, symptom classes or measurable relations, never an app, service or problem.

| Code | Weakness (short) | STRATEGY.md | What is missing | Proposed general fix |
|---|---|---|---|---|
| V1 | one-workload answer | **Partly** (3.2: any kind, several workloads, topic, path) | How candidates for a *set*, a data object or a sub-component are generated is not said. Incident Arena GTs name a setting inside a component (`channel/channel.db-pool`, `postgres/postgres.config`), which the generality rule ("only Kubernetes kinds and fields") does not cover. Tables are not in the kind list. | Group changes by **identical change signature** (same field path, same new value, within one short window) into one candidate covering N objects. Let an origin be `object` or `object + field/setting path` (e.g. "Deployment `x`, setting `db.pool_size`"), and data objects named by the evidence (topic, table, sequence) taken verbatim from probes or logs. |
| V2 | workload-first framing, fixed kind | **Partly** (3.1 "outside objects never leading", 3.6 one origin sentence) | Kind aliasing is not addressed: the GT says `service/x` while the broken thing runs as `Deployment x` (cost D1-Q1 in auth_miss and valkey_auth even with the right name). | Name the object and its serving pair in one phrase when they share a name ("Service `x` (pods of Deployment `x`)"). Never print a second "root cause" label. |
| V3 | changed vs broken | **Full in shape** (3.2 "names both") | Wording risk: naming the trigger (flood Job, flagd) as a cause can cost D3-Q1. The *relation* between the two (exhausts, rewrites, misroutes) needs a candidate type, which today exists only for "changed object acts on workload". | One origin sentence with fixed roles: "`<broken>` fails because `<changed>` <relation>". Relation comes from a small closed set of symptom-class verbs (rejects, cannot resolve, cannot reach, exhausts memory/CPU of, rewrites, blocks), chosen by the model. Victims listed separately. |
| V4 | interactions | **Partly** (3.2 trigger + amplifier, 3.3 traces) | No general way to *generate* an interaction candidate; v2's `amplify` pattern was Lite-built. | Edge candidate whenever a callee is saturated and the **measured amplification** on that edge (calls out per call in, or retries per request, from traces/metrics) is > 1, or both ends carry a post-anchor change. Facts: both ends' non-default client settings on that edge (any env/config key whose value is a duration or count and was changed or differs from siblings), callee saturation, timing. |
| V5 | one mechanism, one cause | **Partly** (3.6 bad/good value; 1 lists "several causes") | Nothing reports several *independent* causes, which Incident Arena scores by the minimum. One key-evidence pick still chooses between several changed fields. | Keep all changed fields of the chosen change in the mechanism, ordered by the model's pick but not dropped. Report a second cause only when two candidates explain disjoint symptom sets and both pass the agreement gate. |
| V22 | mechanism never worded | **Partly** (3.6 values) | The consequence clause ("since then X shows Y") is absent; without it D2-Q1 is lost even with the right fact (edge Dec, search_rate, auth_miss Dec, kafka). | Mechanism = changed fact + the broken component's observed effect + relation verb, each quoted from typed facts: "`<field>` now `<bad>` (was `<good>`); since then CPU of `<component>` is pinned at its `<limit>` and its callers time out". Code assembles, model picks among assembled sentences. |
| V19 | fault-type label | **Full** (3.6 "no fault-category label") | - | Drop the label; keep any internal category out of the text. |
| V6 | collection scope | **Partly** (3.3 Ingress, PriorityClass, kube-system, other namespaces) | No rule for *which* other namespaces; CRDs/CRs (Calico, TiDB) not listed; `/get_app` can name the wrong namespace (FleetCast vs `tidb-cluster`). | Scope = app namespaces + any namespace holding an object that references or is referenced by an app object (webhook backends, Services, DaemonSets on the same nodes, owners of CRs) + any namespace or cluster object with a write after the app anchor (cheap: list with `--show-managed-fields`, filter by time). Read CRs whose kind appears in recent writes or owns app pods. |
| V7 | field gaps | **Partly** (3.1 probe timing, grace) | `hostPort`, `securityContext`/sysctls, the 60-char diff cut, the 400-char ConfigMap cut, `paused`, `priorityClassName`, node condition messages, container port collisions. | (1) Never truncate a *changed* leaf: diff structured values (JSON/YAML ConfigMap data, args) leaf by leaf and print the changed leaves in full. (2) Render every pod-spec field that differs from the Kubernetes default or from sibling workloads. (3) Generic uniqueness checks: the same port, hostPort or mount path claimed twice in a pod or on a node. |
| V8 | runtime state | **Partly** (3.3 probes, 3.5 tie-break tests) | v1 has only *ping* probes (there is no `CONFIG GET` in `probes.py`); probes run only after a victim verdict; technology commands conflict with the lint rule; exec fairness is open (Q2); app-level toggles stay invisible. | Run cheap read-only probes up front on every backend that clients' errors or call edges point at. Allow a **technology adapter table** keyed by image/port (auth check, config read, lag, locks), linted separately from the "no app names" rule. Where probes cannot reach (app toggles), use metrics and logs as the window and say so in the report only as a mechanism, not as a guess. |
| V9 | no telemetry | **Full in intent** (3.3 PromQL, Jaeger, Loki) | Coverage unverified (Q1); before/after needs a trustworthy onset (V12). | As planned, plus per-component step-change detection (rate, latency, CPU throttling, memory) used as dated symptoms. |
| V10 | change detection gaps | **Partly** (3.1 revision diffs) | Created-after-the-app (re-created or new workload), namespace label writes, Ingress/CR writes, mixed revisions (paused rollout), sibling comparison for deployed-broken workloads. | A change record from any of: managedFields write, revision diff, creation after the app anchor, label/annotation write on Namespace or Node. Detector "pods of one workload run different templates". Sibling comparison: settings that differ from every other workload of the same app. |
| V11 | baseline pollution, leftovers | **No** | The plan's core fact "whether it changed" inherits the leftover CoreDNS (52 of 81 snapshots) and harness `restartedAt` writes. Two v1 arms scored 0 on it; v2 lost one too. | (1) **App anchor**: any write older than the app's own deployment is baseline, never a candidate. (2) A template change that touches only `restartedAt` is "restarted", not "changed" (Kubernetes semantics). (3) Cluster objects compete in the same slate as workloads, no early exit. (4) Never print findings the answer does not use. |
| V12 | onset from global earliest abnormality | **No** (3.4 relies on "onset order") | Onset order is one of the five core facts; today it is null or earlier than the injected change in several snapshots. | Per-candidate timing ("first symptom of the components it can reach came N s after its change"), ignoring abnormalities that began before the app anchor or on telemetry components; metrics step changes when available. |
| V27 | evidence cap order | **No** (moot if options carry facts, but the state still has a budget) | Logs and events are cut first. | Budget per evidence type (keep at least k error signatures and k events per component), dedupe repeats. |
| V26 | fixed timing | **No** | Unverified risk for slow faults. | When no post-anchor change explains the symptoms and symptoms are thin, take a second sample later before deciding. |
| V13 | text-only links | **Partly** (3.1 relayed names, 3.4 call edges, 3.3 traces) | IP addresses in errors not mapped; errors that name nothing make no link. | Map ClusterIPs, pod IPs and ports seen in error lines to Services/pods; build call edges from env/config addresses, Service selectors and traces; let an error link only the immediate dependency of the logging component. |
| V14 | brittle tags, classes, rule 4 | **Partly** (3.1 string-matched kinds) | Log-class gaps and the "symptoms-only never selects" rule are not mentioned (they disappear only if the new core drops rules). | Tags come from the detector that produced the fact (typed), never from matching output strings. No eligibility rules in prompts: facts only. |
| V15 | threshold, first wins | **Full** (3.4 slates asked twice, act on agreement) | Per-model calibration is not in the plan. | As planned; calibrate the accept gate per model on Lite runs. |
| V16 | `other` demoted | **Full** (3.1) | - | Cluster objects as ordinary candidates in the slate. |
| V17 | yes-bias, model differences | **Mostly** (3.4 slates, shuffled double ask, 5 models) | Coverage check for Decisions' missing-option overconfidence is only implicit (candidate recall is measured offline, not checked at run time). | At run time, check that the slate has a candidate for every object family that carries a post-anchor change or a computed finding; ask the slate on facts only. |
| V18 | wandering walk, weak fallbacks | **Full** (the walk is replaced) | The new core's fallback when asks disagree after tie-breaking is not stated. | Fallback = candidate with the strongest code facts (post-anchor change + reachable symptoms), never triage top-1. |
| V21 | blast radius under-listed | **Partly** (3.6 "lists affected components clearly as victims") | No method for computing them; the most common lost answer. | Affected = callers on the static and trace call graph of the broken component, + the carrier's scope (webhook rule matches, quota violators, workloads that reference a DNS-overridden name), + the rest of a same-change set, + components whose symptoms began after the change and can reach the origin. Each printed with its own symptom, labelled victim. |
| V20 | risky lines | **Partly** (no category label) | "cannot be ruled out", unfiltered "Abnormal state" dumps, "Other cluster-level findings". | Print only facts the chosen chain uses; no alternatives; no leftovers. |
| V23 | no degraded mode | **No** | A 402/502 zeroes a fault. The Unseen run is planned on about $3 of the $4.64 left, so a credit error mid-run is plausible. | Catch every model error; submit a code-only report (best post-anchor change with reachable symptoms, plus victims) instead of nothing. Pre-flight credit check before the Unseen run. |
| V24 | hand tables, Lite constants | **Partly** (3.7 lint, 5 models) | The lint as written would forbid the technology adapters the probes need; constants replaced only where the walk goes away. | Two lint classes: app/problem names forbidden everywhere; technology adapters allowed only in one table keyed by image/port. |
| V25 | request shape | **Partly** (token goal) | Jev's ~32 kB long-context line not mentioned. | Keep each request under ~32 kB where possible (focused states, as v2 learned). |

### 4.1 Gaps in STRATEGY.md as a plan (beyond single weaknesses)

1. **Baseline control is missing (V11, V12).** The new decision core is built on "whether it changed" and "onset
   order", which are exactly the two v1 facts that are polluted today. Without an app anchor and restart-only
   handling, the core will rank the leftover CoreDNS write and harness restarts as changes on many Unseen faults.
2. **No degraded mode (V23).** Cheap, and it protects the one-shot Unseen run against API or credit errors.
3. **Blast radius and mechanism wording are named but not designed (V21, V22).** D3-Q2 is the most frequent single
   lost answer (36 of 260), and the consequence clause decides D2-Q1 on faults where the right fact is already quoted
   (edge Dec, auth_miss Dec, kafka).
4. **Candidate generation is the real work, and the plan only lists answer kinds (V1, V4, V5).** Section 3.4 says
   code builds a typed graph and computes facts per candidate, but not how sets, edges, data objects and settings
   become candidates. Recall is measured (good), but the generators decide it.
5. **The dev set cannot exercise most new capabilities.** Lite has no NI or MC fault and 2 RT faults; stages 2-3
   (metrics, probes, outside objects, sets, edges) cannot be checked on it. The 48 unrun non-sealed problems in
   section 2 may be studied under the README rules; using some of them as an unreported capability check would not
   touch the sealed list. This is a decision for the user, since "two sets only" was decided.
6. **Generality lint vs probes.** As written, the lint forbids anything but Kubernetes kinds and fields, while 3.3
   relies on technology probes. Say explicitly where technology knowledge may live.
7. **Small factual corrections.** v1 has no Valkey `CONFIG GET` probe (`probes.py` runs `valkey-cli ping`,
   `pg_isready`, mongo ping, Kafka group offsets); v1 *can* name a ConfigMap or Node as "Root cause object" through
   the cluster node (that is how the DNS arms scored 89), it just rarely gets there.

### 4.2 If only a few things can be done first (my recommendation)

In order of value per effort, all general: (1) app anchor + restart-only handling + cluster objects in the same
slate (V11, V16, V15); (2) report contract: origin sentence with both names and the kind alias, victims from the
call graph and carrier scope, consequence clause, no label, no hedges (V2, V3, V21, V22, V19, V20); (3) degraded
mode (V23); (4) field coverage without truncation of changed leaves + uniqueness checks (V7, V10); (5) change-set
grouping (V1 for MC); (6) scope discovery for outside objects and namespaces (V6); (7) metrics/traces and probes
(V9, V8, V4), which are the largest but also the most open (coverage and fairness questions).

---------------------------------------------------------------------------------------------------------------
## 5. Method and limits

- Sealed list respected: none of the 40 ids in `UNSEEN-SEALED.txt` had its problem file, injector method, ground
  truth or runs opened; no run in `runs-index.tsv` belongs to them; the `sealed/` folder was not read. Shared files
  with a sealed sibling (`wrong_dns_policy.py`, `storage_user_unregistered.py`, `mongo_storage_faults.py`,
  `missing_stale_cache_fallback_astronomy_shop.py`, `inject_otel.py`) were not opened; inside `inject_virtual.py`
  only the methods of non-sealed problems were read (rpc config, GOGC, wrong_bin, fd exhaustion), after listing
  method names (the name list includes sealed injectors' names; one adjacent signature line of
  `inject_missing_service` was printed, no body). Nothing from those names was used.
- Section 1 is fact (graded files, run files). The attribution of each lost answer to one primary mechanism is my
  judgment; several losses have two causes (e.g. DNS = V16 and V2).
- Section 2 predictions for the 48 unrun problems are reasoned from code, not run; confidence is highest for the
  scope cases (operator, Ingress) and lowest for the four problems whose files I did not open.
- I did not run anything, did not modify any repo and did not touch API keys.
