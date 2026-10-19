# v2 collection and facts review (2026-10-19)

Scope. `clients/jev_diag/v2/` on `feat/jev-diag-v2` (HEAD ae68e37e), compared with v1 (`clients/jev_diag/*.py`) and
read commit by commit from 065032a6. Read-only. No cluster, no model calls, no sealed or UNSEEN files.

How it was checked.
- Offline A/B. All 29 dev recordings were replayed through v1 and v2 collection with no model
  (`scratchpad/review-collect/ab.py`, output `ab.txt` and `ab.json`). Component signals, evidence kinds, the
  nearest-change flag, error pointers, recent changes, cluster findings and call paths were diffed per fault.
- Raw change dump per recording, with the deploy time v2 computes and which changes it keeps (`changes_detail.py`).
- A synthetic cluster with unusual objects run through v2 `collect_snapshot` with kubectl stubbed out
  (`synthetic*.py`). This covers StatefulSets, DaemonSets, CronJobs, Jobs, a workload with no template, odd
  Ingresses, PriorityClasses, kube-system DaemonSets and a related namespace.
- Direct calls of `probes.backend_probe` with kubectl exec stubbed.

Limit of the A/B. All 29 recordings were made by v1. The 6 reads v2 adds are not in them (related-namespace scan,
`ingresses -A`, `priorityclasses`, kube-system DaemonSets and CronJobs), so every replay logs 6 "not in the replay
bundle" errors and the outside-object code never runs on real data. The synthetic runs cover that code instead.

## Findings, most severe first

### 1. The telemetry collector is no longer pushed down the queue (HIGH, CONFIRMED)
- Where. `derive.py:626` puts "rolling restart" in `SYMPTOM_MARKERS`. `tree.py:604-607` demotes a telemetry
  component only when its evidence kinds lack `symptoms`.
- What happens. In v1 the otel collector's restart was a `change`, so it was demoted behind application candidates.
  In v2 the same restart becomes `symptoms`, so the demotion no longer applies. This happens in 12 of the 29
  recordings (every Astronomy Shop one).
- Why it matters. In lite6_valkey_auth_disruption (a hard case), v1's Jev triage put
  `daemonset/otel-collector-agent` first at 0.45, ahead of `deployment/cart` at 0.42. v1 still passed because the
  demotion moved otel back and cart was examined first. v2 removes that safety net on valkey_auth, valkey_memory
  and secret_rotation (3 of the 5 hard cases). The new "no setting changed" wording may lower otel's triage score,
  but nothing guarantees it.
- Smallest fix. Give a restart no evidence kind. Drop "rolling restart" from `SYMPTOM_MARKERS`, and in
  `classify_evidence` skip signals that start with "rolling restart". otel then has kinds `[]` and is demoted as
  before.

### 2. The MongoDB health probe can never run (HIGH, CONFIRMED)
- Where. `probes.py:242-243` and `probes.py:294`. The command template holds `db.runCommand({ping:1}).ok`, and
  `part.format(port=port)` reads `{ping:1}` as a format field.
- What happens. A direct call on a healthy mongo component raised `KeyError 'ping'` before any exec ran.
  `tree._maybe_probe` catches it and records an error in the trace, so nothing crashes. The probe is now on by
  default, but for every MongoDB backend (Hotel Reservation and Social Network use several) it silently returns
  nothing.
- Also worth knowing.
  - `ping` needs no login in MongoDB, so even a working probe cannot show that authentication is required, which
    is the auth_miss case.
  - The 32 MiB budget for the legacy `mongo` shell looks low for a JavaScript shell. Measure it, or use about
    128 MiB, before the probe is allowed to run in memory-capped containers.
- Smallest fix. Use `part.replace("{port}", str(port))`, or escape the braces as `{{ping:1}}`. Add one unit test
  per role template.

### 3. Restart detection and the "previous revision" choice hide the real change (HIGH, CONFIRMED)
- Where. `changes.py:307-326`. Only the last two revisions are diffed (`revs[-2], revs[-1]`).
- Problem (a). For a Deployment, `restart_only` is never true. The ReplicaSet template always carries a new
  `pod-template-hash` label, so the diff always has a hash line besides the restart annotation. Harness restarts of
  Deployments therefore remain full changes, as in v1. Only the DaemonSet case (otel) works.
- Problem (b). When a fault sets a value and then restarts, as secret_rotation does, the last diff shows only the
  restart. In lite6_secret_rotation, product-catalog's diff from revision 3 to 4 is "restartedAt, pod-template-hash"
  and nothing else. The diff from the deploy revision 1 to 4 shows the real mechanism, "env DB_CONNECTION_STRING:
  postgres://otelu:otelp@postgresql/otel?sslmode=disable -> from secretKeyRef product-catalog-db-conn".
  `report.changed_values` therefore has no old -> new value for the true origin of a hard case.
- Trap. If (a) is fixed alone, by ignoring the hash line, product-catalog becomes "rolling restart, no setting
  changed". It would lose its `change` kind and the report would hide its env write. That is a regression on
  secret_rotation.
- Smallest fix. Diff the current template against the revision that was current when the application was
  deployed. That is the newest revision created at or before the deploy time plus 10 s, or `revs[0]` when none is
  older. Then compute `restart_only` on that diff and ignore `pod-template-hash` lines. Results on the recordings:
  otel stays restart-only, product-catalog shows its env change, and tgt_missing_env is unchanged.

### 4. Healthy outside objects become cluster findings (MEDIUM, CONFIRMED on synthetic data)
- Where. `outside.py:94` and `outside.py:112-116`, then `derive.py:688-698`.
- What happens. Every Ingress route adds a finding such as "routes host/ to Service X:80", even when the backend is
  healthy. Every PriorityClass used by app pods, or set as the cluster default, adds a finding such as "value 0,
  globalDefault True, ...".
- Why it matters. `cluster.findings` is then never empty. The `other` option is always offered (`tree.py:587`),
  and triage rule 4 ("... and `cluster.findings` is empty") no longer applies. A real case is FleetCast, which
  installs an Ingress with two routes on every deploy (`sregym/service/apps/fleet_cast.py`). It costs budget on the
  16k-context models too.
- Smallest fix. Add an outside object to findings only when it has an abnormal signal (missing backend, 0 ready
  endpoints) or a change kept after the deploy filter. The route and value text can stay in `outside_objects` as
  context.

### 5. Leftovers from before the deploy still reach the model (MEDIUM, CONFIRMED)
- Problem (a). kube-system DaemonSets and CronJobs (`outside.py:119-123`). A finding "kube-system DaemonSet
  written" is added whenever `object_change` returns a record. `rank_changes` later drops that change as
  pre-deploy, but the finding stays and carries no time. In the synthetic run, a kube-proxy write 1800 s ago with
  the app deployed 600 s ago was dropped from `recent_changes`, while the finding remained.
- Problem (b). The "changed" flags are set before the filter (`collector.py:2024`, `2066`, `2085`). In the 13
  recordings with a leftover CoreDNS edit, v2 drops it from `recent_changes` and findings, but the state still shows
  `cluster.cluster_dns.changed: true` (checked on held5_liveness and lite6_mutating_webhook). The model sees a
  "changed" CoreDNS with no change listed anywhere.
- Smallest fix. Compute the deploy time once in `collect_snapshot`, from app-namespace workloads only. Pass it to
  `collect_outside` so kube-system findings are skipped for pre-deploy writes. Set the `changed` flags in
  `rank_changes` only for changes it keeps.

### 6. Related namespaces can corrupt or weaken the app's own facts (MEDIUM, CONFIRMED on synthetic data)
- Problem (a). Component ids carry no namespace (`collector.py:220`), and related namespaces are read like the
  app's own (`collector.py:1871`). In the synthetic run, a `frontend` Deployment in the related namespace silently
  replaced the app's `frontend`. The app's Service then reported "matches no workload", the Ingress said its backend
  was missing, and the other namespace's Pending pod was attributed to the app. Pod names collide the same way
  (`pod_to_component` is keyed by pod name only).
- Problem (b). Related-namespace workloads count in `application_created`. When the related namespace is older,
  the pre-deploy filter is weakened or switched off. In the synthetic run, the 1800 s old kube-proxy write was kept
  because the data namespace was 5000 s old. FleetCast reuses a long-lived TiDB cluster
  (`TiDBClusterDeployHelper.running_cluster` deploys once per process), so this would apply to every FleetCast
  problem.
- Problem (c). Discovery is narrower than IMPLEMENTATION H3 says.
  - It misses StatefulSet pod addresses such as `mongo-0.mongo.other-ns.svc` (checked).
  - It can never find an operator namespace the app does not address, such as the TiDB operator's.
  - No CRDs are read, although S2.1 lists them as done.
- Likelihood. The scan found no related namespace in any of the 29 recordings, so today's dev apps are unaffected.
  FleetCast and TiDB are the exposed apps.
- Smallest fix.
  - Mark related-namespace components (`related: true`).
  - Skip a related workload whose id already exists, or prefix its id with its namespace.
  - Leave related components out of `application_created`.
  - Correct the H3 and CRD lines in IMPLEMENTATION.

### 7. Shared ConfigMap files give every service the first block's value (MEDIUM-LOW, CONFIRMED)
- Where. `paths.py:41-43` uses `setdefault`. When a file holds the same key in several blocks, only the first value
  is kept.
- Evidence. A synthetic `{"a": {"timeout_ms": 100}, "b": {"timeout_ms": 9000}}` gave `timeout_ms=100`. In the
  Social Network recordings, every service carries `service-config.json:timeout_ms=10000` and `workers=32`, taken
  from whichever block comes first in the shared JSON. A fault on one service's timeout would be reported with the
  wrong number, and the judge rewards the concrete value.
- Smallest fix. Parse JSON and YAML values and keep the dotted path (`block.timeout_ms`). Failing that, drop a key
  that appears with different values.

### 8. Offline replays of v2 runs can be wrong (MEDIUM-LOW for evaluation, live diagnosis unaffected)
- Problem (a), CONFIRMED by code. `driver.wait()` (`driver.py:151-159`) records every poll sample. Replay serves
  identical commands in recorded order, so a replay of a standalone `--mode v2` run gives the collection the first
  poll's pods and events instead of its own. Arms runs are not affected, because they use v1's schedule.
  - Fix. Wrap the polling samples (not the first baseline) in `recording_paused()`.
- Problem (b), PLAUSIBLE. `telemetry.enabled()` does not know about replay mode. An offline replay made while a
  SREGym session is up (MCP at localhost:9954) would add live Prometheus and Jaeger lines from a different problem
  to an old recording.
  - Fix. Return False when the kubectl replay is active, or set `JEV_DIAG_V2_TELEMETRY=0` in `replay_arms`.

### 9. Probes run once per v2 arm, not once per fault (LOW, CONFIRMED by code)
- What happens. `tree._maybe_probe` (`tree.py:623`) runs after the cached detail read, so in `arms.py` each v2 arm
  executes its own probe. Arms may see different probe results, which breaks "every arm decides from the same
  bundle".
- Fix. Cache the probe result together with the detail in the arms runner.

### 10. Smaller items (LOW)
- `_called` narrowing (`derive.py:265`, `328`). A line such as "failed to call checkout ... lookup cart on
  10.96.0.10:53: no such host" narrows to checkout and loses cart, the DNS victim's real target. On the 29
  recordings it changed only tgt_missing_env, where quote and shipping lost a false `pointed_at` and email kept one.
  That is neutral. Do not narrow away a name that follows "lookup" or appears in a DNS or connect error.
- `own_failure` (`paths.py:66-70`) drops a call path when the callee has any signal of its own, including "CPU at
  its limit", which is how a retry storm often shows. It fires correctly on search_rate today.
- `collect_outside`, `related_namespaces` and `paths.call_paths` are not wrapped in try/except. One malformed
  object would abort the whole collection, against v1's fail-soft rule. No synthetic shape crashed them (missing
  spec, resource backends, no metadata, no template). Wrap each one and log to `errors`.
- An Ingress default backend with a named port prints "Service nope:" (`outside.py:58` reads only `number`).
- The component `probes` summary in the triage state (`collector._probe_summary`) still has no timing. Timing now
  appears only in the detail and in template diffs. In held5_liveness, aux-service's `periodSeconds 1,
  failureThreshold 1` is invisible to triage. Adding non-default timing there is cheap.
- A kube-system change has empty `affects`. When it is the nearest change before onset, it takes the
  `nearest_change_before_symptoms` slot and flags no component (`changes.py:530-549`).
- `recent_changes` does not mark restart-only entries. Add `restart_only` to the kept keys.

## New kubectl reads: live-run risk
- Error handling. Every new read goes through `kubectl_items`, which catches any exception, records it in `errors`
  and returns `[]`. A missing resource type or a forbidden list never aborts collection. The model never sees
  collection errors.
- Permissions. Agents reach the API through SREGym's k8s proxy (`sregym/service/k8s_proxy.py`). It allows
  cluster-wide lists (`ingresses -A`, `priorityclasses`), filters hidden namespaces out of them, and allows exec
  except into host-network pods. Ingress (networking.k8s.io/v1) and PriorityClass (scheduling.k8s.io/v1) exist on
  every supported cluster.
- Cost.
  - 2 extra list calls per app namespace, because the related-namespace scan re-reads Deployments and
    StatefulSets without managed fields.
  - 4 cluster reads.
  - For each related namespace, about 20 reads plus pod logs.
  - Each read has the 45 s timeout. Offline, the new derivations cost nothing measurable (v1 plus v2 collection of
    all 29 recordings took 6.7 s).
- Telemetry. The MCP server is checked once. After that, each investigated component runs about 10-15 Prometheus
  queries plus one Jaeger call, each with a 15-20 s timeout and no circuit breaker. If MCP degrades mid-run, one
  component can add over a minute. Set `_available = False` after the first `McpError`.

## Probe safety
- Read-only. The commands are only `valkey-cli/redis-cli ping`, `pg_isready`, `mysqladmin ping` and a mongo
  `ping`. None writes.
- When a probe runs. `_maybe_probe` probes only a backend with all pods ready, no signal of its own, and a victim
  that names it.
- Memory headroom. A store at 90% or more of its memory limit carries its own "near its limit" signal, so it is
  never probed. The 3 MiB native-tool budget therefore always has at least 10% of the limit free. Example from
  lite6_valkey_auth: valkey-cart has a 64Mi limit and used 3Mi.
- Timeouts. A hung server costs 20 s per command, and up to 40 s with the redis-cli fallback.
- Remaining issues. The MongoDB template bug (finding 2) and the legacy mongo shell budget.

## Adaptive wait (`driver.wait`)
In 14 of the 29 recordings, the set of abnormal pods at about 75 s equals the set at about 120 s, so v2 would read
early. In every one of them, those pods belong to the faulty workload or to its direct victim (cart in valkey_auth,
rate in update_incompatible). No deploy-time restart noise appears, because the app is redeployed fresh for each
problem. No problem found beyond finding 8a.

## Per-fault v1 vs v2 (29 dev recordings, collection only)
"otel relabel" means the otel collector's restart changed from `change` to `symptoms` (finding 1). "CoreDNS leftover
dropped" means a CoreDNS edit made before the app was deployed is no longer a recent change or a finding. Its
`changed: true` flag remains (finding 5).

| Recording | Ground truth | v2 difference | Verdict |
|---|---|---|---|
| held4_service_dns_resolution_failure_astronomy_shop | CoreDNS rule for frontend | otel relabel; CoreDNS edit (30 s after deploy) kept | neutral, demotion risk |
| held5_duplicate_pvc_mounts_hotel_reservation | frontend | CoreDNS leftover (2468 s before onset) dropped | fix |
| held5_incorrect_image | product-catalog | CoreDNS leftover dropped; otel relabel | fix + demotion risk |
| held5_liveness_probe_too_aggressive_social_network | aux-service | CoreDNS leftover dropped, findings now empty | fix |
| held5_readiness_probe_misconfiguration_hotel_reservation | frontend | CoreDNS leftover dropped | fix |
| held5_service_port_conflict_social_network | media-service | none | neutral |
| held5_sidecar_port_conflict_hotel_reservation | frontend | CoreDNS leftover dropped | fix |
| held5_wrong_service_selector_astronomy_shop | frontend Service | CoreDNS leftover dropped; otel relabel | fix + demotion risk |
| held6_auth_miss_mongodb | url-shorten-mongodb | none (mongo probe dead, target not ready anyway) | neutral |
| held6_valkey_memory_disruption | valkey-cart | otel relabel | demotion risk (hard case) |
| lite5_cronjob_sidecar_blocks_completion_hotel_reservation | audit-log-archiver CronJob | none | neutral |
| lite5_search_rate_retry_collapse_hotel_reservation | search -> rate call path | new call path with both sides' settings (timeout 750 ms, 3 attempts, rate QPS 20, queue 256) and the feedback-loop flag | fix |
| lite5_service_wrong_pod_selection_hotel_reservation | frontend Service selector | none | neutral |
| lite6_duplicate_pvc_mounts_social_network | jaeger | CoreDNS leftover dropped | fix |
| lite6_edge_request_filter_cpu_saturation | frontend-proxy | CoreDNS leftover dropped; otel relabel | fix + demotion risk |
| lite6_env_variable_shadowing_astronomy_shop | frontend-proxy | CoreDNS leftover dropped; otel relabel | fix + demotion risk |
| lite6_finalizer_deadlock_controller_hotel_reservation | ClusterRole + ConfigMap of cleanup controller | none | neutral |
| lite6_internal_traffic_policy_local_astronomy_shop | recommendation Service | CoreDNS leftover dropped; otel relabel | fix + demotion risk |
| lite6_kafka_poison_pill_hol_block | topic / consumer | CoreDNS leftover dropped; otel relabel | fix + demotion risk |
| lite6_mutating_webhook_resource_limits_social_network | gatekeeper webhook | CoreDNS leftover (317 s before onset, nearest decoy) dropped | fix |
| lite6_namespace_memory_limit | ResourceQuota | none | neutral |
| lite6_network_policy_block | NetworkPolicy on recommendation | none | neutral |
| lite6_rolling_update_misconfigured_social_network | custom-service | CoreDNS leftover dropped | fix |
| lite6_secret_rotation_stale_env_credentials_astronomy_shop | product-catalog | otel relabel; product-catalog still shows only restart+hash in its diff | demotion risk (hard case); value gap (finding 3) |
| lite6_service_dns_resolution_failure_social_network | CoreDNS rule for user-service | none (CoreDNS edit 10 s after deploy kept) | neutral, guard holds |
| lite6_unschedulable_incorrect_port_assignment | checkout | otel relabel | demotion risk |
| lite6_valkey_auth_disruption | valkey-cart | otel relabel; v1 Jev triage had otel top-1 at 0.45 | regression risk (hard case) |
| tgt_missing_env_variable_astronomy_shop | frontend (CART_ADDR removed) | frontend gains `change` and the nearest-change flag ("env CART_ADDR removed", 31 s before onset); quote and shipping lose a false `pointed_at`; otel relabel | fix |
| tgt_update_incompatible_correlated | 6 mongodb Deployments | none in collection (grouping is in the report) | neutral |

Totals. 15 fixes (13 CoreDNS leftovers dropped, the missing_env revision change, the search_rate call path). No
fault lost a true fact it had in v1. 12 recordings carry the telemetry demotion risk (finding 1), including 3 hard
cases.

Files: `scratchpad/review-collect/` holds `ab.py`, `ab.txt`, `ab.json`, `changes_detail.py`, `wait_check.py`,
`synthetic.py`, `synthetic2.py`, `synthetic3.py`, `dns_flag.py` and a copy of `collect_only.py`.
