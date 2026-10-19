# Run forensics: why v1 and v2 pass or fail, run by run (2026-10-19)

Sources. `runs-index.tsv`; each run's `*_arms_graded.json` (judge checklist per arm); `*_armN_vX_requests.json`
(every model request with its options and probabilities); `*_snapshot.json`; code in
`~/sregym/SREGym-fixes/clients/jev_v2/` (tree 066c4d2f, identical to HEAD for `clients/`) and `clients/jev_diag/`
(v1, unchanged since 6400cd46 on 18 Oct 19:08, so every v1 arm in every run uses the same v1 code).
Arm order everywhere is v2 Jev / v2 Decisions (Dec) / v1 Jev / v1 Dec. Pass = score >= 70. In the pattern column
P = pass, "." = fail. "Fact" below means read from the files; "Interpretation" is marked as such.

Stage codes (from the brief). (a) right cause never offered / not reached; (b) offered but ranked or shown weakly;
(c) model picked wrong among offered options; (d) right component, wrong framing/mechanism/scope in the report;
(e) evidence for the true cause never collected or never shown to the model; (f) judge noise.

---

## 1. Main table (latest run per fault in scope)

| Fault | Set | Run | v2 Jev / v2 Dec / v1 Jev / v1 Dec | Pattern | Verdict |
|---|---|---|---|---|---|
| auth_miss_mongodb | A | held6 | 44 / 33 / 100 / 77 | ..PP | v2 names the mongod ConfigMap as root cause; grader wants the MongoDB service; v1's "workload + fault object" framing passes |
| duplicate_pvc_mounts_hotel_reservation | A | held5 | 100 / 100 / 100 / 100 | PPPP | easy; all agree |
| incorrect_image | A | held5 | 77 / 89 / 89 / 89 | PPPP | all right; v2 Jev lost scope points for its "frontend fails as a result" line |
| liveness_probe_too_aggressive_social_network | A | held5 | 67 / 89 / 67 / 0 | .P.. | probe timing values never shown to the model; category coin-flip code_bug vs probe; v1 Dec fell into a leftover CoreDNS change |
| readiness_probe_misconfiguration_hotel_reservation | A | held5 | 100 / 100 / 100 / 100 | PPPP | v2 passes via v1's key-fact fallback (no v2 pattern fired) |
| service_dns_resolution_failure_astronomy_shop | A | held4 | 89 / 89 / 55 / 55 | PP.. | v2 win by framing: v2 names the CoreDNS ConfigMap; v1 names Deployment frontend (cluster node skipped) |
| service_port_conflict_social_network | A | held5 | 78 / 78 / 78 / 78 | PPPP | everyone misses hostPort 9100 and node-exporter (not in the evidence) |
| sidecar_port_conflict_hotel_reservation | A | held5 | 89 / 89 / 89 / 89 | PPPP | v2 passes via key-fact; all miss the port value |
| valkey_memory_disruption | A | held6 | 45 / 56 / 45 / 45 | .... | everyone blames the flood Job; grader wants valkey-cart (OOM). v2 has no "runs out of memory under load" candidate |
| wrong_service_selector_astronomy_shop | A | held5 | 100 / 100 / 100 / 100 | PPPP | fixed in v2 after the first held run failed it (44/55) |
| cronjob_sidecar_blocks_completion_hotel_reservation | Lite | lite5 | 100 / 100 / 100 / 100 | PPPP | easy |
| duplicate_pvc_mounts_social_network | Lite | lite6 | 100 / 100 / 100 / 100 | PPPP | v2 Jev passes on a near tie (jaeger 0.36 vs leftover CoreDNS change 0.35) |
| edge_request_filter_cpu_saturation | Lite | lite6 | 78 / 89 / 67 / 89 | PP.P | v2 win on Jev: per-field change candidates let the regex script win; v1 Jev picked the CPU-limit field |
| env_variable_shadowing_astronomy_shop | Lite | lite6 | 78 / 89 / 89 / 89 | PPPP | v2 Jev split its vote over 3 near-identical change options; "none" won; fallback still passed |
| finalizer_deadlock_controller_hotel_reservation | Lite | lite6 | 100 / 100 / 100 / 100 | PPPP | easy (lite5 run was an OpenRouter 402 credit error, not a diagnosis) |
| internal_traffic_policy_local_astronomy_shop | Lite | lite6 | 100 / 100 / 78 / 89 | PPPP | v1 loses points for calling the Deployment the root cause instead of the Service |
| kafka_poison_pill_hol_block | Lite | lite6 | 100 / 100 / 67 / 56 | PP.. | v2 win: the bad-input pattern names the topic as origin; v1 can only name the consumer Deployment |
| mutating_webhook_resource_limits_social_network | Lite | lite6 | 89 / 89 / 89 / 89 | PPPP | all identical, all miss "all pod CREATEs" scope |
| namespace_memory_limit | Lite | lite6 | 89 / 89 / 89 / 89 | PPPP | all identical |
| network_policy_block | Lite | lite6 | 100 / 100 / 100 / 100 | PPPP | easy |
| rolling_update_misconfigured_social_network | Lite | lite6 | 100 / 100 / 100 / 100 | PPPP | easy |
| search_rate_retry_collapse_hotel_reservation | Lite | lite5 | 89 / 89 / 34 / 34 | PP.. | v2 win: the amplify pattern can name a caller-callee interaction; v1 can only name rate's QPS limit |
| secret_rotation_stale_env_credentials_astronomy_shop | Lite | lite6 | 11 / 45 / 100 / 34 | ..P. | v2 picks the postgresql-init ConfigMap over the stale-read (Jev near tie 0.41 vs 0.36); v1 Dec origin_p 0.49 just under 0.6 |
| service_dns_resolution_failure_social_network | Lite | lite6 | 100 / 100 / 89 / 67 | PPP. | v2 win on Dec: framing (ConfigMap as root cause); v1 Dec stopped at user-service |
| service_wrong_pod_selection_hotel_reservation | Lite | lite5 | 100 / 89 / 100 / 100 | PPPP | easy; 11-point gaps are wording/judge |
| unschedulable_incorrect_port_assignment | Lite | lite6 | 100 / 100 / 100 / 100 | PPPP | easy |
| valkey_auth_disruption | Lite | lite6 | 22 / 56 / 34 / 23 | .... | runtime `requirepass` never collected by anyone; v2 Jev blamed the victim `cart` |
| missing_env_variable_astronomy_shop | T | tgt | 11 / 89 / 22 / 100 | .P.P | v2 Jev near tie lost to a fake "otel-collector is broken" dependency; v1 Jev called frontend a victim |
| update_incompatible_correlated | T | tgt | 0 / 11 / 89 / 89 | ..PP | v2 split six identical image bumps into six one-component options and picked the victim `rate` |

Pass counts in this table (fact): Lite v2 15/17 and 15/17, v1 13/17 and 12/17; A v2 7/10 and 8/10, v1 7/10 and 7/10;
T v2 0/2 and 1/2, v1 1/2 and 2/2.

Same-model head-to-head (fact). v2 passes where v1 fails on 4 faults with Jev (edge, kafka, search_rate,
dns_astronomy) and 5 with Dec (kafka, search_rate, dns_social, dns_astronomy, liveness). v1 passes where v2 fails on
3 faults with Jev (secret_rotation, auth_miss, update_incompatible) and 2 with Dec (auth_miss, update_incompatible).
Of v2's 9 wins, 6 are on Lite (the set v2 was built on), 2 are the same CoreDNS framing on one held fault, and 1 (liveness Dec) came from v1's own characterization step inside v2. Of v1's 5
wins, 4 are on non-Lite faults.

---

## 2. Every failure (score < 70) and every v1-vs-v2 pass/fail disagreement

### 2.1 update_incompatible_correlated (T, tgt) - v2 0 / 11, v1 89 / 89
Facts.
- Six MongoDB deployments had their image bumped mongo:4.4.6 -> mongo:8.0.14-rc0 and crash. `rate` crashes too and
  `search` logs "downstream request failed dependency=rate".
- v2's six options were dependency:rate, amplify search->rate, and only FOUR of the six image changes (geo, profile,
  rate, recommendation). `shortlist` (TOP_K = 6) cut mongodb-reservation and mongodb-user. Each change option said
  "Observed impact on" its own deployment only; dependency:rate said rate + search.
- The decide state (`_state`) only carries components the six options mention, so the model never saw mongodb-
  reservation or mongodb-user at all. v1's triage sees the whole snapshot.
- Jev averaged dependency:rate 0.48 vs best change (geo) 0.205, none 0.19. Dec 0.535 vs mongodb-rate change 0.29
  (its two asks disagreed). Summing all mongo changes still loses (0.31 Jev, 0.35 Dec).
- Victim rule did not fire on dependency:rate. `victim_check` needs `call_links` from rate to mongodb-rate; rate's
  env has no Mongo address (only JAEGER_SAMPLE_RATIO, RATE_BACKEND_QPS_LIMIT, RATE_QUEUE_CAPACITY) and its previous
  log was "unable to retrieve container logs", so no link existed.
- Route = check, but `_look_closer` read nothing new (all six components were pre-read by PRE_READ = 6), so the loop
  ended after one round and submitted the leader marked uncertain.
- Characterization ran on `rate` (wrong component) and chose "errors logged by search name this component" (Jev
  0.35) or a Go stack line `db.go:40` (Dec 0.78); category config_value / other.
- v1: triage put mongodb-geo at 0.74 (Dec: geo 0.36 = user 0.36), step 1 origin 1.0 / 0.89 with the image change as
  key evidence. It lost only D3-Q2 (named geo, not all six).

Stage v2: (c) wrong pick, not a near tie, on top of (a) for scope (no option covered the six together).
Code pieces: patterns (`change_explanations` makes one candidate per component; nothing groups "same change on N
components"); shortlist (TOP_K cut two); state (focused state hides the rest of the cluster); victim rule (link
not discoverable); decide question ("explains the most symptoms" favours the two-component dependency option);
go-back (no-op).

### 2.2 missing_env_variable_astronomy_shop (T, tgt) - v2 Jev 11, v1 Jev 22 (Dec arms 89 and 100)
Facts.
- v2 Jev: dependency:daemonset/otel-collector-agent 0.405 vs change "frontend env CART_ADDR removed" 0.395, none
  0.17. Near tie. Asks agreed on otel (0.39 vs 0.38 in ask 1).
- The otel option came from `_configured_dependency`: `config_links` matched the collector's Service name in the
  env of email, frontend, quote and shipping (telemetry endpoints), and `_broken_itself` was true because the
  daemonset's only evidence is a `kubectl.kubernetes.io/restartedAt` annotation written by the harness. The snapshot
  marks it `role: observability`; `error_links` skips observability components but `config_links` does not. The
  option claimed impact on five components; the true change claimed one.
- Four of six slots were bad-input options treating env values as "inputs" (ENV_PLATFORM=kubernetes, flagd,
  cumulative, otel-collector), each with the same unrelated email-400 log line.
- The cluster's `recent_changes` list held only the otel restart, not the frontend change.
- Characterization on otel-collector-agent picked its readiness probe; report = "health probe config".
- v2 Dec: change 0.50 vs none 0.35 (asks disagreed, route check, submitted as leader and marked uncertain), 89.
- v1 Jev: triage email 0.36, otel 0.31, frontend 0.27. Walk email (victim 0.47, next frontend) -> frontend, whose
  key evidence WAS "CART_ADDR removed" but verdict victim 0.82 (its errors name email), next shipping -> shipping ->
  quote -> otel (unrelated) -> checkout. No origin >= 0.6, fallback "triage top-1" = email.
- v1 Dec: frontend first, origin 0.42; after 5 more steps, fallback "most likely origin among investigated" =
  frontend, 100.

Stage v2 Jev: (c) near tie. Code: patterns (configured dependency on an observability component; bad-input on
arbitrary env values filling slots), decide question (wide-impact preference), go-back no-op.
Stage v1 Jev: (c) the model saw the true cause on the right component and called it a victim; the fallback then
used triage order.

### 2.3 auth_miss_mongodb (A, held6) - v2 44 / 33, v1 100 / 77
Facts.
- Ground truth target is service/url-shorten-mongodb (TLS required with an invalid certificate).
- Both v2 arms picked change:configmap/url-shorten-mongodb (0.815 / 0.90, accept) over the configured dependency
  deployment/url-shorten-mongodb (0.165 / 0.07). Report "Root cause: configmap url-shorten-mongodb ... was changed
  recently and breaks deployment/url-shorten-mongodb". Judge: D1-Q1 No (a ConfigMap is a different resource), D2-Q1
  No (no TLS or certificate mechanism; the key fact `mode: requireTLS` is shown but the mechanism sentence is
  generic).
- v1 had the same evidence (key = mongod.conf requireTLS) but wrote "Root cause component: Deployment
  url-shorten-mongodb" plus a separate "Fault object: ConfigMap" line. D1 passed. v1's report also quotes the
  mongod log lines "Cannot read certificate file" (its error-line section), which is what earned D2-Q1; v2's report
  quotes only the ConfigMap timing and "0 of 1 replicas ready".
- The earlier held5 run (older v2, before the store-link commits 79895f12 / 66b1f609) picked
  dependency:deployment/url-shorten-service, a victim caller (0.47 Jev; Dec 0.39 vs partial:url-shorten-mongodb
  0.385, a near tie). The ConfigMap change was not offered there.

Stage v2 held6: (d) right place, wrong framing. Code: report (`build_report` puts `cause.origin` = the ConfigMap in
the root-cause line; acts-on mechanism is the generic "was changed recently and breaks X"). Stage v2 held5: (c) with
a victim-rule gap (since patched).
Interpretation: this is the mirror image of service_dns (2.6). The grader's "origin" is whatever object the
injector targets. v2 always names the outside object, v1 always names the workload, and each framing wins on some
faults and loses on others.

### 2.4 valkey_memory_disruption (A, held6) - everyone fails, 45 / 56 / 45 / 45
Facts.
- Ground truth origin = service/valkey-cart (memory exhausted). valkey-cart shows "was OOMKilled" and
  CrashLoopBackOff; job/valkey-memory-flood shows only "1 active pod, not completed".
- v2 options: arrival:job (Jev 0.61), own-setting:job, partial:job, partial:valkey-cart (Jev 0.04, Dec 0.21), and
  two otel restartedAt changes. There is no candidate of the form "valkey-cart runs out of memory because a load
  source fills it" (the architecture's `resource` pattern was never built). The job's link to valkey-cart is inside
  a base64 command, so no config or error link exists.
- v1: triage job 0.78 / 0.71, valkey-cart 0.17 / 0.23; step 1 origin 0.88 / 0.97, concluded the job.
- Across four runs v2's pick wandered (held3 cart / cart, held4 job / job, held5 valkey-cart / job, held6 job / job)
  and never passed. v1 named the job every time, 45 every time.

Stage v2: (a) the framing the grader wants was never offered as a complete chain; (c) among what was offered.
Stage v1: (c). Interpretation: the answer key is debatable (the job is the trigger), but the grader is fixed.

### 2.5 liveness_probe_too_aggressive_social_network (A, held5) - v2 Jev 67, v1 Jev 67, v1 Dec 0 (v2 Dec 89)
Facts.
- Ground truth: aux-service liveness probe initialDelaySeconds=0, periodSeconds=1, failureThreshold=1, and
  terminationGracePeriodSeconds=0.
- The collected detail holds `probes.liveness` with periodSeconds 1, failureThreshold 1 (initialDelay absent = 0).
  `describe_probe` (jev_diag/checks.py:111) renders only the target, so the fact the model sees is "liveness probe:
  httpGet HTTP :8080/health". terminationGracePeriodSeconds is not in the detail at all.
- v2 options: partial:aux-service, partial:social-graph-service, acts-on coredns ConfigMap (left from an earlier
  fault, modified 3478 s ago, 3350 s before the symptoms). Jev: none_of_these 0.45 (route coverage), so the winner
  fell back to partial -> key-fact. Characterization chose the service.py ConfigMap (0.38 averaged; the bare probe target 0.335) and
  category code_bug 0.515 vs health_probe_config 0.165. Dec accepted partial 0.875 and chose health_probe_config.
- v1 Jev: same key fact, category code_bug, 67. v1 Dec: aux-service "undetermined" 0.45, then the cluster node
  picked the leftover CoreDNS ConfigMap (0.86), score 0.
- held2 run: same picture (v2 67 / 67, v1 67 / 89).

Stage all: (e) the mutated values were never shown; then (c) a category coin-flip decides 67 vs 89. v1 Dec: (c) on
a harness leftover. v2 code: no pattern for "own probe too aggressive" (own-setting needs a team check to flag it);
everything rides on v1's characterization step.

### 2.6 service_dns_resolution_failure_astronomy_shop (A, held4) - v2 89 / 89, v1 55 / 55 (v2 win)
Facts.
- Both v2 arms accepted change:configmap/kube-system/coredns (0.915 / 0.875). Report: "Root cause: configmap
  coredns" with the NXDOMAIN rule as concrete detail. Lost only D3-Q2.
- Both v1 arms investigated deployment/frontend first, saw the same CoreDNS rule as key evidence, origin 0.61 / 0.94
  (>= 0.6), and stopped. Report "Root cause component: Deployment frontend" + "Fault object: ConfigMap coredns".
  Judge: D1-Q2, D1-Q3, D3-Q1 No.
- v1 Jev triage gave `other` (cluster objects) 0.87 (held4; 0.72 in held3), but the "a higher-ranked triage candidate is still
  unexamined" check in `IterativeDiagnoser.diagnose` only looks at `c in snapshot.components`, so `other` never
  counts and the cluster node is skipped once a workload reaches 0.6.
- In the first held run v1 Jev's frontend origin was 0.56 (< 0.6), so it went on to the cluster node, named the
  ConfigMap and scored 89. Same evidence, pass or fail decided by whether origin_p lands above 0.6.

Stage v1: (d) right evidence, wrong framing, caused by the walk (threshold stop + cluster node excluded from the
"higher-ranked" check). v2's win comes from its framing, not from better evidence.

### 2.7 secret_rotation_stale_env_credentials_astronomy_shop (Lite, lite6) - v2 11 / 45, v1 Jev 100, v1 Dec 34
Facts.
- The injection rewrote both the product-catalog Secret and the postgresql-init ConfigMap; ground truth origin is
  deployment/product-catalog (stale credentials read at start).
- v2 options: dependency otel-collector-agent (observability, again), change ConfigMap postgresql-init, change
  Secret, stale-read product-catalog, and two bad-input options for postgresql with env values "root" and "otel" as
  inputs. Jev: ConfigMap 0.41 vs stale-read 0.36 (asks disagreed, near tie). Dec: ConfigMap 0.555 vs stale-read 0.13.
  Both routes = check, one round only.
- History. arms run (older v2): ConfigMap both arms (0 / 0). final run: Jev stale-read 0.665 (100); Dec moved from
  stale-read 0.34 in round 1 to ConfigMap 0.455 in round 2 after reading more detail (0). lite6: ConfigMap both.
- v1 Jev: product-catalog first, origin 0.65, done, 100. v1 Dec: product-catalog origin 0.49 vs victim 0.45 (just
  under 0.6), walked to postgresql, origin 0.68, concluded postgresql with the init.sql key fact, 34.

Stage v2: (c), near tie for Jev. Code: patterns (the noise candidates take 3 of 6 slots; the ConfigMap's "Checks"
look as strong as the stale-read's), decide question, go-back no-op. Stage v1 Dec: (c) near-threshold origin call.

### 2.8 valkey_auth_disruption (Lite, lite6) - everyone fails, 22 / 56 / 34 / 23
Facts.
- Ground truth: valkey-cart's password was set at runtime (CONFIG SET requirepass), clients get NOAUTH. Nothing in
  the snapshot shows the password; the hidden-state pattern has a "login check against valkey-cart is rejected"
  prediction with `check="probe"`, but v2 has no code that runs probes. Every arm's D2 is 0 or 0.33.
- v2 Jev: dependency:deployment/cart 0.655 (a victim) vs dependency:valkey-cart 0.125 and hidden-state:valkey-cart
  0.13. Accepted. The victim rule could not contradict cart because valkey-cart is not `_broken_itself` (its only
  evidence is other components' errors, `pointed_at`).
- The options contradict each other. o3 says "valkey-cart shows failures of its own (supports)"; o6 says
  "valkey-cart shows no trouble of its own (supports)". `dependency_explanations` sets SUPPORTS whenever the target
  is not healthy, and `healthy` is false for a pointed-at component.
- v2 Dec: dependency:valkey-cart 0.48 vs cart 0.315 (check, one round). The generic dependency mechanism was replaced
  by the characterization key fact "image valkey/valkey:9.0.1, limits memory 64Mi", category other. D2 = 0.
- Earlier runs (arms, final, older v2): both v2 arms picked dependency:valkey-cart at 0.78-0.93 and scored 67 (D1
  "deployment vs service" partial, D2 1/3). Later code (pre-read, more candidates) made Jev worse.
- v1 Jev: cart (victim 0.95, next valkey-cart 0.99) -> valkey-cart judged "unrelated" 0.08 -> four more ->
  fallback "end of a victim chain" = valkey-cart, category service_routing, plus a "otel-collector-agent cannot be
  ruled out" line (triage 0.47). v1 Dec: cart origin 0.46 = victim 0.46, valkey-cart victim 0.36, fallback triage
  top-1 = cart.

Stage: (e) for all arms (the runtime state was never collected). v2 Jev additionally (c), not a near tie, caused by
the victim rule's "broken itself" condition. v2 Dec (d) mechanism overwritten by a weak key fact. v1 (c).

### 2.9 kafka_poison_pill_hol_block (Lite, lite6) - v2 100 / 100, v1 67 / 56 (v2 win)
Facts. v2 bad-input:orders-validator:orders-fulfillment 0.945 / 0.74; report "Root cause: input source
`orders-fulfillment`". v1 both arms found the same thing (blocked input from ORDERS_TOPIC=orders-fulfillment) but
the report says "The blocked component is Deployment orders-validator"; judge D1 all No. v1 Dec also chose the
consumer.py script as key evidence (D2-Q2 No). Same scores in all three runs for v1.
Stage v1: (d) framing; v1 has no way to make a topic the root-cause object.

### 2.10 search_rate_retry_collapse_hotel_reservation (Lite, lite5) - v2 89 / 89, v1 34 / 34 (v2 win)
Facts. v2 amplify:search->rate 0.90 / 0.69, report names the interaction with both sides' settings. v1: triage rate
0.98, origin 0.5 / 0.49, key = RATE_BACKEND_QPS_LIMIT=20; v1 Dec judged search a victim 0.82. Fallback "most likely
origin" = rate. D1 and D2 all No. Same scores in all three runs.
Stage v1: (a) the cause (an interaction of two components) cannot be expressed as one of v1's candidates.

### 2.11 edge_request_filter_cpu_saturation (Lite, lite6) - v2 78 / 89, v1 Jev 67 (v2 win on Jev)
Facts. Revision 2 of frontend-proxy changed command, args (the Perl filter with the catastrophic regex), WAF env
and the CPU limit. v2 makes one option per changed field; Jev args 0.50 vs command 0.295 (check), Dec args 0.66.
v2 Jev then chose category resource_limits (D2-Q1, D2-Q3 No, 78). v1 Jev's key-evidence question picked "limits.cpu:
unset -> 100m" out of the same revision (D2 = 0, 67). v1 Dec picked the args (89). v1 Jev scored 67 in all three runs.
Stage v1 Jev: (c) key-evidence pick among facts on the right component. v2 Jev: (d) category.

### 2.12 service_dns_resolution_failure_social_network (Lite, lite6) - v1 Dec 67 (v2 win on Dec)
Facts. v1 Dec: user-service origin 0.99 at step 1, stopped; cluster node never examined (same check as 2.6);
"Root cause component: Deployment user-service" -> D1-Q2, D1-Q3, D3-Q1 No. v1 Jev: user-service origin 0.45 < 0.6 ->
cluster node -> CoreDNS, 89. Same scores in all three runs. Stage v1 Dec: (d) framing via the walk.

### 2.13 Smaller gaps among passing arms (not failures, listed for completeness)
- incorrect_image v2 Jev 77: winner dependency:product-catalog 0.62 over the image change 0.34 (same component);
  the report's "deployment frontend fails as a result" line was read as over-attribution (D3-Q1). Report code
  (`build_report` knock-on lines).
- env_variable_shadowing v2 Jev 78: three near-identical change options (FRONTEND_HOST frontend -> localhost; "now
  defined 2 times"; "together") got 0.175 / 0.175 / 0.225, so `none_of_these` 0.255 won by plurality (route
  coverage). Grouped by origin, frontend-proxy had 0.67. The fallback (key-fact) still named the duplicate env var
  but category resource_limits (D2-Q3). This was the only in-scope run where vote splitting flipped the leader.
- internal_traffic_policy v1 78 / 89: "Root cause component: Deployment recommendation" with the Service as fault
  object; judge D1-Q3 No (same v1 framing as 2.6).
- service_port_conflict all 78, sidecar_port_conflict all 89, mutating_webhook all 89, namespace_memory_limit all
  89: every arm misses the same item (hostPort 9100 and node-exporter; the shared port value; "all pod CREATEs";
  other non-compliant workloads). These are evidence or report-scope gaps common to both pipelines.

---

## 3. Faults where v2 wins over v1, and exactly why

| Fault | Model | Why v2 wins (fact) | General or Lite-specific? (interpretation) |
|---|---|---|---|
| search_rate_retry_collapse | both | v1 can only name one component; v2's `amplify` pattern names the caller-callee interaction and lists both sides' retry/timeout/QPS settings | pattern written for this Lite fault; fires on any timeout-class caller error |
| kafka_poison_pill | both | v1's report always names the blocked Deployment as the root-cause component; v2's `bad-input` makes the topic the origin | pattern written for this Lite fault; the same pattern produces junk options elsewhere (2.2, 2.7) |
| edge_request_filter | Jev | v2's one-option-per-changed-field lets the script change compete on its own; v1's single key-evidence pick chose the CPU limit | general mechanism; also causes vote splitting (2.13) and the six-way split in 2.1 |
| service_dns (social) | Dec | v2 names the CoreDNS ConfigMap as root cause; v1 Dec stopped at the workload | framing; v1 bug in skipping the cluster node |
| service_dns (astronomy) | both | same as above | the only held-out v2 win, and it is the same framing rule |
| liveness_probe | Dec | v2 Dec chose category health_probe_config (v1 Dec fell into the leftover CoreDNS change) | v2 Dec passed via v1's own characterization step; not a v2 capability |

Interpretation. v2's real wins are two expressiveness gains (an interaction as origin; an input source as origin)
and one framing rule (outside cluster object as root cause). The first two were built for Lite faults. The framing
rule helps when the grader's target is the outside object (CoreDNS) and hurts when it is the workload or service
(auth_miss). v1 has the evidence in every win case except search_rate; it loses on what it is allowed to say.

---

## 4. Stability across runs

v1 code never changed across these runs, so v1 variation = snapshot + model + judge. v2 code changed between almost
every label, so v2 variation mixes code changes with randomness.

| Fault | Runs (v2J/v2D/v1J/v1D) |
|---|---|
| cronjob_sidecar | arms 100/89/100/100, rerun 100/89/100/100, final 100/100/100/100, lite5 100/100/100/100 |
| duplicate_pvc (social) | arms 0/11/100/100, rerun 100/100/100/0, final 100/100/100/100, lite6 100/100/100/100 |
| edge_request_filter | arms 89/89/67/89, final 89/89/67/89, lite6 78/89/67/89 |
| env_variable_shadowing | arms 89/89/89/89, final 89/89/89/89, lite6 78/89/89/89 |
| finalizer_deadlock | arms 100x4, final 100x4, lite5 402 credit error, lite6 100x4 |
| internal_traffic_policy | arms 89/89/89/100, final 89/89/100/89, lite6 100/100/78/89 |
| kafka_poison_pill | arms 11/11/67/56, final 89/89/67/56, lite6 100/100/67/56 |
| mutating_webhook | 89x4 in all three |
| namespace_memory_limit | 89x4 in all three |
| network_policy_block | 100x4 in all three |
| rolling_update | arms 89/78/100/100, final 100x4, lite6 100x4 |
| search_rate_retry | arms 89/89/34/34, final 89/45/34/34, lite5 89/89/34/34 |
| secret_rotation | arms 0/0/100/100, final 100/0/100/100, lite6 11/45/100/34 |
| service_dns (social) | 100/100/89/67 in all three |
| service_wrong_pod_selection | arms01 100/100/89/89, final 89/89/100/89, lite5 100/89/100/100 |
| unschedulable_port | arms 89/78/100/100, final 89/78/100/100, lite6 100x4 |
| valkey_auth | arms 67/67/34/0 (v1 Dec HTTP 502 refusal), final 67/67/45/23, lite6 22/56/34/23 |
| auth_miss_mongodb | held5 34/34/78/78, held6 44/33/100/77 |
| duplicate_pvc (hotel) | held2 100x4, held5 100x4 |
| incorrect_image | held3 89x4, held5 77/89/89/89 |
| liveness_probe | held2 67/67/67/89, held5 67/89/67/0 |
| readiness_probe | held2 100x4, held5 100x4 |
| service_dns (astronomy) | held 89/89/89/55, held3 89/89/55/55, held4 89/89/55/55 |
| service_port_conflict | held2 66/66/78/78, held5 78x4 |
| sidecar_port_conflict | held2 89/89/100/89, held5 89x4 |
| valkey_memory | held3 11/23/45/45, held4 22/45/45/45, held5 45/45/45/45, held6 45/56/45/45 |
| wrong_service_selector | held 44/55/100/100, held3 100x4, held5 100x4 |

Facts.
- v1 pass/fail is stable. Across all repeated faults, v1 flipped pass/fail in only 4 places: duplicate_pvc social v1
  Dec (one 0 from a leftover CoreDNS change), secret_rotation v1 Dec (100, 100, 34 on a 0.49-vs-0.6 origin call),
  liveness v1 Dec (89, 0 on the leftover CoreDNS change), dns_astronomy v1 Jev (89, 55, 55 on a 0.56-vs-0.6 origin
  call). Each flip traces to one threshold or one leftover object.
- v2 flipped pass/fail on kafka (both arms), duplicate_pvc social (both), secret_rotation Jev (0 -> 100 -> 11),
  search_rate Dec (89 -> 45 -> 89), wrong_service_selector (both) and service_port_conflict (both), mostly with code
  changes in between. Between final (1d22d925) and lite5/6 (seven more commits) secret_rotation Jev went 100 -> 11
  and valkey_auth Jev went 67 -> 22 (after the pre-read and configured-dependency commits).
- v2 picks wander where it fails: valkey_memory picked cart, job and valkey-cart across four runs; v1 picked the job
  every time.
- The leftover CoreDNS ConfigMap (from an earlier DNS fault on the same cluster) is a recurring trap: it decided
  duplicate_pvc arms v2 Jev (0), duplicate_pvc rerun v1 Dec (0), liveness held5 v1 Dec (0), and was the runner-up in
  duplicate_pvc lite6 v2 Jev (0.35 vs 0.36).
- Judge noise. Among 73 groups of reports with identical text (pod hashes and numbers normalised), 8 groups got
  different scores. Spreads were 11 points (cronjob v2 Jev vs Dec, same text 100 vs 89; wrong_pod_selection v2 Jev vs
  Dec 100 vs 89; auth_miss v2 44 vs 33) up to 22 points (internal_traffic_policy v1 Jev 89 / 100 / 78 on the same
  text). In this data identical text never crossed the 70 line. The "Deployment named, grader wants the Service" call
  on D1-Q1 is inconsistent: v1 auth_miss got No in held5 and Yes in held6 with the same root-cause line (held6 added
  a "Fault object: ConfigMap" line, so the texts are not identical); valkey_auth's "deployment valkey-cart" got No in
  every run; wrong_service_selector and incorrect_image Deployment answers got Yes.
- Go-back. In older runs (arms, final, rerun) v2 often ran 2 rounds. Since 6fec2c91 (pre-read the top candidates'
  components) it ran exactly ONE round in all 58 in-scope v2 arms. 18 of those 58 ended "check" or "coverage"
  (uncertain) and were submitted anyway; 8 of the 18 failed, versus 4 of the 40 accepted ones.

---

## 5. Taxonomy and root causes

### 5.1 Failure counts by stage (latest in-scope runs; primary stage per failing arm)

| Stage | v2 (12 failing arms) | v1 (16 failing arms) |
|---|---|---|
| (a) never offered / not expressible | 2 (valkey_memory x2) | 2 (search_rate x2) |
| (b) offered but ranked or shown weakly | 0 as primary | 0 as primary |
| (c) wrong pick among offered | 6 (update x2, secret x2, missing_env Jev, valkey_auth Jev); 2 near ties | 8 (edge Jev, secret Dec, valkey_auth x2, liveness Dec, valkey_memory x2, missing_env Jev) |
| (d) right component, wrong framing or mechanism | 3 (auth_miss x2, valkey_auth Dec) | 5 (kafka x2, dns_social Dec, dns_astronomy x2) |
| (e) evidence never collected or never shown | 1 (liveness Jev) | 1 (liveness Jev) |
| (f) judge noise | 0 as primary | 0 as primary |

Secondary causes that sit under these: (e) also underlies all four valkey_auth arms and both service_port_conflict
point losses; the leftover CoreDNS object underlies liveness v1 Dec; the go-back no-op underlies every v2 "check"
failure.

Where the v2 failures sit. Lite 4 (secret x2, valkey_auth x2); A 5 (auth_miss x2, liveness Jev, valkey_memory x2);
T 3 (missing_env Jev, update x2).

Which v2 pattern won, and how often it passed (fact). Lite: acts-on 13/15, own-setting 6/6, change 5/5,
bad-input 2/2, amplify 2/2, key-fact 1/1, dependency 1/3. A: key-fact 6/8, acts-on 4/6, own-setting 2/2,
dependency 2/2, change 1/1, arrival 0/1. T: dependency 0/3, change 1/1. Over all sets a `dependency` winner passed 3
of 8 times; every other pattern passed at least two thirds of the time. On held-out set A, 8 of 20 v2 arms were
decided by `key-fact`, which is v1's characterization step (partial -> v1 key-evidence question); on Lite that
happened once in 34.

### 5.2 The root causes that explain most v2 losses on non-Lite faults

1. **Candidate generation invents wide "dependency" chains that the model prefers.** (update_incompatible x2,
   missing_env Jev, valkey_auth Jev, auth_miss held5, secret_rotation slots.) `_configured_dependency` links any
   component whose env names another component (telemetry endpoints included) to anything "broken itself" (a
   harness restartedAt annotation counts). `dependency_explanations` offers any component named by others' errors,
   victims included. The victim rule only fires when the callee is `_broken_itself` AND a link is found in env or
   error lines, which fails when the link lives in a config file, a base64 command, or an unavailable previous log,
   or when the real server looks healthy (valkey_auth). The decide question tells the model to prefer the option
   that "explains the most symptoms", and these chains list the most impacted components. Fact: dependency winners
   pass 3/8.
2. **One cause is split into many one-component options, and only six fit.** (update_incompatible, env_shadowing,
   edge.) `change_explanations` emits one option per changed field per component; there is no "same change on N
   components" chain; `shortlist` keeps six; `_state` shows the model only the components those six mention. A fault
   that spans six deployments can never be offered as one cause, and parts of it are not even visible.
3. **Root-cause framing is a fixed rule, but the grader's target kind varies.** (auth_miss x2 lost; dns_astronomy
   and dns_social won; v1 lost internal_traffic_policy points the other way.) v2 always names the outside object
   (ConfigMap, Secret, CoreDNS) as root cause with a generic "was changed recently and breaks X" sentence; v1 always
   names the workload with a "Fault object" line. Neither rule matches the grader on all faults.
4. **v2 has no patterns for most unseen fault classes, so on held-out faults it is v1's characterization step with a
   different front end, and it inherits v1's evidence gaps.** (liveness, valkey_memory, readiness and sidecar passes,
   valkey_auth Dec.) 8 of 20 held-out v2 arms were decided by `key-fact`. Probe timing is dropped by
   `describe_probe`; terminationGracePeriodSeconds is not collected; runtime state (requirepass) needs a probe v2
   never runs; hostPort and node-exporter collisions are not in the facts. The hand-written patterns that win on Lite
   (amplify, bad-input) add junk options on other faults (bad-input on env values like "kubernetes", "root", "otel").
5. **Uncertainty buys nothing.** The go-back loop never ran a second round in the 58 in-scope v2 arms because
   `_look_closer("check")` targets the top two chains' components, which PRE_READ already read; it returns False and
   the loop submits the leader. 18 arms ended unsure; 8 of them failed. In the one older case where a second round
   did run in an older version (secret_rotation final, Dec), the extra detail moved the pick from the right chain
  (0.34) to the wrong one (0.455).

### 5.3 What v1 gets wrong (for balance)
- It cannot express an interaction or an input source as the origin (search_rate, kafka).
- Its walk stops at the first workload with origin >= 0.6 and never reaches the cluster node even when triage put
  0.7-0.87 on cluster objects (the "higher-ranked" check skips `other`) (dns_social Dec, dns_astronomy x2).
- Near-threshold origin calls (0.49, 0.56 vs 0.6) decide whole runs (secret_rotation Dec, dns_astronomy Jev).
- It also falls for victims and harness leftovers (missing_env Jev, valkey_auth, liveness Dec).
- But on unseen faults its whole-snapshot triage plus "workload + fault object" report is the more robust default:
  out of 24 non-Lite same-model arm pairs, v1 failed where v2 passed in 3 (dns_astronomy x2, liveness Dec) and v2
  failed where v1 passed in 4 (auth_miss x2, update_incompatible x2).

### 5.4 Facts versus interpretation, in one place
- Facts: every probability, option list, threshold and judge miss quoted above is read from the run files or the
  code named next to it.
- Interpretation: that the grader's target kind is the deciding factor in the framing cases; that the `dependency`
  pattern is the main harm (the 3/8 rate is a fact, the causal reading is mine); that v2's held-out passes "are v1"
  when the winner is key-fact (the code path is a fact; whether v2's front end adds anything there is a judgment);
  that the valkey_memory answer key is debatable.
- Uncertain: how much of each run-to-run v2 change comes from code edits versus snapshot differences (both changed
  together); I did not re-run anything.
