# Feasibility of new evidence sources for v2 (code-only review, 2026-10-19)

Status: COMPLETE (2026-10-19). Read-only review of `~/sregym/SREGym-fixes/` (commit
622300af) plus run artifacts of Lite/held-out runs listed in `runs-index.tsv`. No runs, no cluster access.
Paths below are relative to `~/sregym/SREGym-fixes/` unless they start with `/`.

---

## 1. What telemetry exists during the diagnosis stage

### 1.1 The timeline of one problem (facts)

Order in `sregym/conductor/conductor.py`: `start_problem` -> `deploy_app` (Prometheus, Jaeger, OTel collector, Loki,
MCP server, then the app, then the Jaeger ExternalName redirect, then the workload, lines 1370-1499) -> sleep
`baseline_duration_s` (lines 706-717) -> `_inject_fault` -> sleep `propagation_duration_s` (lines 421-436) -> the
diagnosis stage opens -> main.py launches the agent container (main.py:519-547).

- `baseline_duration_s` and `propagation_duration_s` default to **0** (`sregym/conductor/problems/base.py:17,20`).
  Only the Incident Arena ports set them (120/60 in `problems/environment.py:30-34,70-71`; 120/120 in
  `problems/incident_arena.py:98-111`) and `internal_traffic_policy_local.py:120` (propagation 65). `main.py
  --baseline/--propagation` can override (main.py:1185-1198); the leaderboard setting is not documented.
- `observe` (Prometheus, Jaeger, Loki) is deleted after every problem by `reconcile_to_baseline`
  (`sregym/service/cluster_state.py:32-37`, called at conductor.py:528-530) and redeployed in `deploy_app`. So all
  telemetry starts a few minutes before the app does; there is no data from earlier problems.
- **Measured** (team run logs `/home/priyo_software/Priyo Work/jev-v2-runs/lite6_*.log`, phase ledger
  `results/1019_1131/jev_diag/network_policy_block/phases_attempt1.jsonl`):

  | run | app deployed | workload started | fault injected | stage opens |
  |---|---|---|---|---|
  | lite6_network_policy_block (hotel) | 11:34:20 | 11:34:20 | 11:34:20 | same second |
  | lite6_rolling_update_misconfigured_social_network | 12:07:52 | ~12:08:0x | 12:08:04 | same second |
  | lite6_env_variable_shadowing_astronomy_shop | 12:24:10 | 12:24:27 | 12:24:28 | same second |
  | lite6_edge_request_filter_cpu_saturation | 12:16:20 | 12:16:35 | 12:16:37 | same second |

  App deploy itself took about 15-50 s (images cached). So **the app lives only ~15-50 s before the fault, and
  the generated load runs for 0-2 s before the fault** on hotel and social network (wrk2 Job is created at
  "Start workload", `sregym/generators/workload/wrk2.py:137-144`). Astronomy shop's locust load generator is part
  of its chart, so it has load from pod start (~20-40 s before the fault).
- v1 waits after the stage opens (`clients/jev_diag/driver.py:189-194`, default 120 s; the trace of
  lite6_network_policy_block shows 75 s delay + 45 s trend interval, collection ~125 s after injection).

### 1.2 Prometheus (one central server, `observe` namespace)

Config: `sregym/observer/prometheus/prometheus/values.yaml`.
- Global `scrape_interval: 1m` (line 234) applies to **kube-state-metrics, cAdvisor, node-exporter, the blackbox
  TCP probes and the hotel app metrics** (jobs at lines 1070-1240 have no own interval). Spanmetrics, locust,
  the ingress HTTP probe, TiDB and Incident Arena exporters use 15 s (lines 1243-1395).
- Retention 15d in `full` (line 693), 2h in `svelte` (`observer/prometheus/values-svelte.yaml:24`). Irrelevant
  in practice because `observe` is rebuilt per problem.
- Chaos namespaces are dropped at scrape time (lines 1074-1077, 1091-1094) and again by the MCP filter.

| metric family | source | interval | hotel | social | astronomy | blueprint hotel |
|---|---|---|---|---|---|---|
| container CPU, throttling, memory, OOM events, network, fs | cAdvisor via API server node proxy (1089-1133) | 1m | yes | yes | yes | yes |
| pod/deployment/HPA/quota/restart/last-terminated state | kube-state-metrics (1070-1083) | 1m | yes | yes | yes | yes |
| node CPU/mem/disk/fs/conntrack/time | node-exporter (1135-1140) | 1m | yes | yes | yes | yes |
| `probe_success` TCP to each Service:port | blackbox (1150-1240) | 1m | 8 app services (not DBs) | 13 services | 16 incl. kafka, flagd | none |
| app counters | `hotel-reservation-application` job (1206-1212): `search_rate_{attempts,timeouts,failures,successes}_total`, `rate_queue_depth`, `rate_in_flight`, `rate_backend_qps_limit`, `rate_requests_{received,completed,expired,rejected}_total` (`SREGym-applications/hotelReservation/services/search/server.go:173-180`, `services/rate/server.go:173-186`) | 1m | search, rate only | none | none (app OTel metrics go to `debug`, `sregym/service/apps/values/astronomy-shop-fixes.yaml:32-47`) | none |
| user-facing request/failure counts per endpoint | locust exporter `load-generator:9646` (1262-1275) | 15s | none | none | yes | none |
| RED per service x span name (`traces_span_metrics_calls_total`, `..._duration_milliseconds_bucket`) | central OTel collector spanmetrics (1279-1316; `observer/otel_collector/otel-collector.yaml:23-62`) | 15s | **arrives but mislabeled** (see 1.3) | yes if spans arrive; 1% sampling | yes (OTLP pipeline, namespace=astronomy-shop) | yes |
| HTTP probe through ingress-nginx | `blackbox-ingress-hotel-reservation` (1243-1258) | 15s | only when a problem deploys ingress-nginx | - | - | - |

Spanmetrics dimensions are the defaults (`dimensions: []`, otel-collector.yaml:31,37): service, span name, span
kind, status code. There is no caller->callee label, so edges must come from Jaeger, not from Prometheus.

Alert rules (values.yaml:712-1040) are the only thing v1 reads today. They include the chronic decoys the team
already sees (e.g. `HighRequestRate` on hotel's `rate`, below).

### 1.3 Traces (Jaeger)

- One central `jaegertracing/all-in-one:1.57`, **in memory, capped at 25,000 traces**
  (`observer/jaeger/jaeger.yaml:72-80`). Everything reaches it through the central OTel collector
  (`otel-collector.yaml:39-56`), which also produces the spanmetrics above.
- How each app gets there:
  - **Astronomy shop**: services -> in-namespace `otel-collector` DaemonSet -> `jaeger:4317`
    (`SREGym-applications/astronomy-shop/charts/opentelemetry-demo/values.yaml:955-956,1017`) -> ExternalName to the
    central collector (`observer/jaeger/jaeger.py:64-95`, which also restarts `otel-collector-agent` so it
    re-resolves). Reliable by design. The bundled chart Jaeger is deleted (full) or not deployed (svelte).
  - **Blueprint hotel**: sends Jaeger thrift-HTTP straight to `otel-collector.observe:14268`
    (`SREGym-applications/BlueprintHotelReservation/kubernetes/frontend/frontend-service-env-configmap.yaml:4`).
    Reliable. Prometheus relabels its names `unknown_service:X_process` -> `X` (values.yaml:1286-1291).
  - **Hotel reservation**: Go jaeger-client v2.11.2 over UDP to `jaeger:6831`
    (`SREGym-applications/hotelReservation/config.json`, `tracing/tracer.go`, sample ratio 1 in every
    Deployment). The app's own `jaeger` Service is replaced by an ExternalName only **after** the app pods are
    ready (conductor.py:1488-1494), and this client version resolves the agent address once at start
    (`vendor/github.com/uber/jaeger-client-go/utils/udp_client.go:45-62`). By code reading, pods that never
    restart may send spans to a dead address. **But run data shows hotel spans do arrive at least sometimes**:
    the cronjob_sidecar_blocks_completion_hotel_reservation snapshot has `HighRequestRate` firing with
    `{namespace="blueprint-hotel-reservation", service_name="rate"}` (rate > 50 req/s = hotel's normal load).
    Two facts follow: (a) hotel spanmetrics are labelled `namespace="blueprint-hotel-reservation"` because the
    relabel rule defaults every Jaeger-protocol span to that namespace (values.yaml:1295-1303), so any query must
    select hotel by `service_name`, not `namespace`; (b) coverage per hotel service is **unverified**.
  - **Social network**: C++ Jaeger client over UDP to `jaeger:6831` with **probabilistic sampling 0.01**
    (`SREGym-applications/socialNetwork/helm-chart/socialnetwork/values.yaml:35-42`), same late-ExternalName
    issue as hotel. No team snapshot ever had a span-based alert for `social-network` (expected at 1% sampling
    even if spans flow). Coverage **unverified**.
- Capacity: hotel at 100 req/s fully sampled fills 25,000 traces in roughly 4 minutes, so raw traces cover only
  the last few minutes (fine for "after onset", useless for "before").
- MCP tools (`mcp_server/jaeger_server.py`): `get_services`, `get_operations(service)`, `get_traces(service,
  last_n_minutes)` with a fixed **limit of 20 traces** and no tag/error filter (lines 93-98), and
  `get_dependency_graph(last_n_minutes)` from `/api/dependencies` (lines 111-132). The Jaeger tools apply **no
  visibility filter** (unlike Prometheus and Loki).

### 1.4 Logs (Loki)

- Loki single binary, filesystem storage, retention 24h (`observer/loki/loki-values.yaml:15-25`); Promtail
  DaemonSet ships every pod's container logs except `chaos-mesh|khaos` (`observer/loki/promtail-values.yaml:6-10`).
  Deployed per problem (`sregym/service/telemetry/loki.py:79-92`, conductor.py:1461-1465).
- What Loki adds over `kubectl logs`: logs of **pods that no longer exist** (old ReplicaSet pods replaced by a
  rollout, evicted or deleted pods), and every earlier container instance, not just `--previous`. That is the
  only pre-fault log baseline there is (~15-50 s of startup logs plus whatever ran before a rollout).
- MCP `get_logs(query, last_n_minutes=15)` uses `query_range` with a fixed **limit of 100 lines**
  (`mcp_server/loki_server.py:145-208`). Metric LogQL (`count_over_time ... by (pod)`) comes back as a matrix;
  the formatter reads `stream` labels and treats values as log lines (lines 186-200), so grouping labels are lost
  and timestamps print wrong. Workaround: one query per pod, or count lines client-side.
- Caveat: the Loki filter (`visible_log_value`, `sregym/service/agent_visibility_policy.py:164-165`) only hides
  chaos markers. Load-generator pods (hidden as objects) are **not** hidden in Loki. Using their streams would
  go against the intent of the object filter; I would not use them.

### 1.5 Can an agent compute before-vs-after-onset baselines? (answer)

- **Mostly no, for the core problems with default settings.** With baseline 0 and propagation 0, the healthy
  window is ~15-50 s of app life with little or no load (hotel, social) before the fault. At the 1-minute scrape
  interval, cAdvisor, kube-state-metrics and blackbox probes have **0 or 1 pre-fault sample** per pod. Spanmetrics
  (15 s) have 0-3 pre-fault samples, with load only on astronomy shop.
- **Yes for Incident Arena ports** (120 s baseline) and a few problems that wait inside `inject_fault` (e.g. the
  Kafka pipeline set-up in lite6_kafka_poison_pill_hol_block took ~20 s before "Injected fault").
- What does work without a time baseline (opinion, from the data above):
  1. **Absolute signals** that need no baseline: OOM events, restarts, throttled-period ratio, memory vs limit,
     `probe_success == 0`, error ratio per span, consumer lag, node conntrack/disk vs limit.
  2. **Cross-sectional baselines**: compare a service with its peers in the same app at the same time
     (robust z over services), replicas of one Deployment with each other, and pods of the new ReplicaSet with the
     pods of the old one (Loki keeps the old pods' logs).
  3. **Early vs late after onset**: wait (the diagnosis budget allows it, see 5) and compare the first minute
     after injection with later minutes. Growth (restarts, lag, memory, error rate) is a strong onset signal.
  4. The **change ledger time** (managedFields, ReplicaSet creation) as the onset marker for a short window.

---

## 2. How the agent reaches these sources

Facts:
- The agent runs in a Docker container (README.md:156-158). In filtered mode (the default, README.md:166-171) its
  only allowed destinations are the conductor API (`host.docker.internal:8000`), the Kubernetes API proxy
  (`host.docker.internal:16443`), the MCP port-forward (`host.docker.internal:9954`), and the model provider
  (`sregym/service/container_runner.py:313-336`; for `jev_diag` with an `openrouter/` model that is
  `https://openrouter.ai`, `sregym/service/provider_endpoints.py:87-91`).
- So **Prometheus, Jaeger and Loki are reachable only through the MCP server** (`mcp_server/sregym_mcp_server.py:172-178`,
  SSE endpoints `/prometheus/sse`, `/jaeger/sse`, `/loki/sse`). v1 already does this for alerts
  (`clients/jev_diag/collector.py:1454-1470`, fastmcp `SSETransport` to `http://$API_HOSTNAME:$MCP_SERVER_PORT/prometheus/sse`).
  No auth on MCP (`ObservabilityClient` sends a dummy bearer token, `mcp_server/utils.py:116-124`).
- The MCP server is a Deployment in namespace `sregym` (`mcp_server/k8s/deployment.yaml`), limits **500m CPU /
  512Mi**, port-forwarded to the host by the conductor (`sregym/service/mcp_server.py:68-91`). Its HTTP client to
  the backends has a 120 s timeout and 3 retries on 5xx (`mcp_server/utils.py:93-95,127-138`).
- Prometheus: `get_metrics(query)` calls **instant** `/api/v1/query` only (`mcp_server/prometheus_server.py:16-46`).
  History is still available: a range selector (`x[15m]`) returns raw samples, and a subquery
  (`rate(x[1m])[15m:15s]`) returns a series. Output is a Python `str(dict)`; parse with `ast.literal_eval` as v1
  does for alerts. Records whose labels mention chaos are dropped (lines 37-38).
- kubectl: the agent's `KUBECONFIG` points at the conductor's filtering proxy on the host
  (`sregym/service/k8s_proxy.py:1103-1166`, conductor.py:152-166), which forwards with the **host's own
  kubeconfig** (`k8s_proxy.py:496-534`; on kind that is cluster-admin). The proxy needs the per-run bearer token
  (`k8s_proxy.py:756-758`). Upgraded connections (exec, port-forward) are relayed (`k8s_proxy.py:871-904`).
- Latency (measured, lite6_network_policy_block trace): small `kubectl get -o json` lists 45-100 ms, large lists
  (pods, events, ~190 KB) 0.7-1.4 s. No measured numbers for MCP calls (v1 does not time `get_alerts`
  separately); expect a few hundred ms per call plus query time (opinion).
- Limits to plan for: Jaeger 20 traces per call; Loki 100 lines per call; Prometheus results are unbounded and
  pass through a 512Mi MCP pod, so queries should aggregate (`sum by (pod)`), not pull raw cAdvisor for the whole
  cluster. The MCP pod also serves the kubectl tool for LLM agents; we do not use it for kubectl.
- `kubectl port-forward` to `prometheus-server` in `observe` would also work through the proxy (only `proxy`
  subresources are blocked, `k8s_proxy.py:347-356,768-770`), giving full `query_range`. Not needed: MCP plus
  subqueries is enough, and port-forward is a long-running side process (opinion).

---

## 3. Rules on probes (exec, read-only, filtered mode, what counts as cheating)

### 3.1 Facts from code
- **`kubectl exec` is allowed.** The proxy refuses exec/attach only into **host-network pods, and only in
  filtered mode** (`sregym/service/k8s_proxy.py:772-777`). The MCP kubectl tool lists exec as "unsafe" but does
  not block unsafe commands by default (`mcp_server/kubectl_server_helper/cmd_category.py:22-46`,
  `mcp_server/configs/kubectl_tool_cfg.py:17-20` `forbid_unsafe_commands=False`); its ClusterRole grants
  `pods/exec` (`mcp_server/k8s/clusterrole.yaml:25-38`).
- **SREGym itself expects agents to exec into datastores.** `sregym/service/apps/values/astronomy-shop-fixes.yaml:139-151`:
  valkey's memory limit was raised because "the mitigation oracle and the agent exec the same CLI" (valkey-cli).
  The task text given to LLM agents says "Analyze metrics, logs, and traces" and "query metrics and traces through
  the available observability tools" (`clients/codex/driver.py:198-216`).
- **No read-only rule is enforced in the diagnosis stage.** Writes are allowed by the platform at any time (the
  mitigation stage needs them). But the mitigation oracle snapshots the cluster right before injection
  (conductor.py:307-319), and SREGym's own note shows how a side effect destroys a fault: a valkey OOM-kill one
  second after injection "erased the runtime-only password, so the mitigation oracle passed before the agent
  changed anything" (astronomy-shop-fixes.yaml:141-147).
- **Exec runs inside the target container's cgroup**, so a second process in a memory-capped container can
  OOM-kill it. SREGym documents this for Kafka ("a second JVM needs ~100-150Mi ... the kernel OOM-kills it and
  takes the broker down", astronomy-shop-fixes.yaml:122-138) and v1 documents it too (`clients/jev_diag/probes.py:12-16`,
  with a headroom check at lines 64-88 and tool sizes at 33-36).
- **Filtered mode limits** (default; README.md:166-171):
  - exec into host-network pods refused (k8s_proxy.py:772-777). Host-network pods include node-exporter
    (`charts/prometheus-node-exporter/values.yaml:299,302`), kube-proxy, calico-node and the static control-plane pods
    (standard Kubernetes; not checked in this repo).
  - `pods/proxy`, `services/proxy`, `nodes/proxy` refused (k8s_proxy.py:347-356,768-770), so no kubelet
    `/configz`, `/stats/summary` or `/metrics` through the API.
  - creating or patching workloads to add hostNetwork/hostPID/hostIPC/privileged/hostPath refused
    (`sregym/service/kubernetes_access_policy.py:41-74`, k8s_proxy.py:822-824). So no node debug pods.
  - Calico egress-boundary objects cannot be changed (k8s_proxy.py:244-260,764-766).
  - Pod-to-pod traffic inside the cluster is not restricted by SREGym (the egress policy only denies addresses
    outside the cluster and then `Pass`es, `sregym/service/cluster_egress.py:31-37`), so connect/resolve tests from
    an app pod see exactly what the app sees, including fault NetworkPolicies.
- **What SREGym hides on purpose (the cheating boundary):**
  - problem definitions and grading logic: agents run in a container "preventing access to SREGym internals"
    (README.md:158). Only `socialNetwork/wrk2` and `hotelReservation/wrk2` from SREGym-applications are mounted
    (`sregym/service/container_runner.py:570-574`, `sregym/agent_launcher.py:66-67`), so the shipped manifests are
    not even on disk inside the agent container;
  - Helm release Secrets, "benchmark source data, not runtime evidence" (k8s_proxy.py:784-789; also no Secret
    watches, 791-794);
  - namespaces `chaos-mesh`, `khaos`, the `chaos-mesh.org` API group, chaos events, and objects labelled
    `app=load-generator|locust-fetcher`, `job=workload`, `network-access=restricted`,
    `opentelemetry.io/name=load-generator` (`sregym/service/agent_visibility_policy.py:6-24,66-84`). The proxy's
    stated aim: agents must not discover "that faults are being injected via chaos tools or that traffic is
    synthetic" (k8s_proxy.py:1-15);
  - hotel's decoy `failure-admin-*` ConfigMaps are emptied "so agents cannot read fault details"
    (`sregym/service/apps/hotel_reservation.py:99-116`).
  - Not hidden: other namespaces, kube-system, Secrets other than Helm records, metrics, logs, traces, nodes.

### 3.2 Answers (opinion where marked)
- **Read-only exec probes are fair** under SREGym's rules: exec is allowed, expected for datastores, and nothing
  hidden is touched. They are not fair if they read Helm records, chaos objects, load-generator objects, or the
  load generator's log streams in Loki (Loki does not filter those, section 1.4; opinion: treat as off-limits).
- **Safe datastore probes (opinion, from the facts above):** only native CLIs, only read commands, only after the
  headroom check v1 already has:
  - valkey/redis: `PING`, `INFO memory|clients|stats|keyspace`, `CONFIG GET maxmemory*|requirepass|...` (a few MB).
    `CONFIG GET` is a read; it is the right tool for runtime-only config faults.
  - PostgreSQL: `pg_isready`; `psql -c` with SELECTs on `pg_stat_activity`, `pg_locks`, sequences (local socket
    inside the DB container usually needs no password; uncertain per image).
  - MongoDB 4.4 (`mongo:4.4.6` in hotel, no memory limit set in the hotel manifests): `db.adminCommand({ping:1})`,
    and an auth test with the client's own credentials read from its Secret/env.
  - Kafka consumer offsets: **avoid exec** (JVM tool, documented OOM risk). Use spanmetrics publish/receive
    rates instead (the `MessageConsumerLag` rule already does this, values.yaml:972-996), or run the tool only when
    the broker's limit minus usage is above ~768Mi (v1's `JVM_TOOL_BYTES`).
  - Never `CONFIG SET`, writes, `FLUSH*`, `kill`, restarts or new pods during diagnosis.
- **Node-level probes are not feasible in filtered mode** (conntrack table, df on the node, kubelet config, dmesg,
  clock). Only node-exporter metrics in Prometheus are available (section 1.2).
- Creating a probe pod (e.g. a curl pod) is allowed but is a write that leaves an object behind and can trip
  "all pods ready" style checks; prefer exec into an existing client pod (opinion).

---

## 4. What the agent's kubeconfig can read outside the app namespace

Fact: the kubeconfig points at the conductor's proxy, which forwards with the host's kubeconfig
(k8s_proxy.py:496-534, 1103-1166), i.e. cluster-admin on kind. Only the filters in 3.1 apply. So the agent can
read, cluster-wide:

| object | readable | notes |
|---|---|---|
| Ingress, IngressClass, ingress-nginx namespace | yes | ingress-nginx exists only when a problem deploys it (values.yaml:1027-1030) |
| PriorityClass, StorageClass, PV, VolumeAttachment, CSI objects | yes | not collected by v1 today |
| CRDs and CRs (Calico IPPool/BGP*/IPAM*/NetworkPolicy/GlobalNetworkPolicy, OpenEBS, TiDBCluster) | yes | `chaos-mesh.org` group hidden; CRDs with chaos names hidden (agent_visibility_policy.py:17-36) |
| kube-system workloads and ConfigMaps (CoreDNS, kube-proxy, metrics-server, kubeadm/kubelet config ConfigMaps) | yes | exec into kube-proxy/calico-node refused (host network) |
| other namespaces (observe, sregym, openebs, default, problem-made namespaces) | yes | `chaos-mesh`, `khaos` return 404 |
| Nodes (labels, taints, conditions, allocatable, images) and Leases | yes | `nodes/proxy` refused in filtered mode |
| Mutating/ValidatingWebhookConfigurations, APIServices, ClusterRoles/Bindings | yes | chaos-named ones hidden |
| Events in all namespaces | yes | chaos and hidden-workload events removed |
| Secrets | yes, except Helm release records | no watch |

Infrastructure noise the outside-object collector will see (facts) and must not treat as a cause:
- SREGym's own Calico `GlobalNetworkPolicy` `adminnetworkpolicy.external-egress-boundary` in filtered mode
  (`sregym/service/kubernetes_access_policy.py:7-8`, `cluster_egress.py`);
- objects SREGym creates **after** the app: the `jaeger`, `jaeger-agent`, `jaeger-collector`, `jaeger-query`
  ExternalName Services in the app namespace and a rollout restart of `otel-collector-agent`
  (`observer/jaeger/jaeger.py:64-95`); hotel's patch of `mongodb-geo`/`mongodb-rate` to mount the decoy ConfigMaps
  (`hotel_reservation.py:118-138`); the metrics-server patch and OpenEBS default-class annotation
  (conductor.py:1386-1440). These look like "recent changes" to a change ledger.
- the `observe`, `sregym`, `openebs` workloads. Opinion: filter by relation ("selects, schedules, admits, routes to,
  or shares a node with an app pod"), not by namespace name, to respect the generality rule.

---

## 5. Leaderboard and run setup

- **Profile:** `full` is the leaderboard profile; `svelte` "is **not** comparable" (README.md:201-237,
  `sregym/profile.py:1-15`). The team runs astronomy shop with `--profile svelte` (`docs/jev-v2-batch.sh:4`). For
  the sources in this report, svelte differs only in Prometheus retention (2h) and Alertmanager (unused: `get_alerts`
  reads Prometheus' own `/api/v1/alerts`, prometheus_server.py:49-79); but it removes Grafana, OpenSearch and the
  flagd-ui sidecar from the astronomy namespace (`values/astronomy-shop-svelte.yaml`), i.e. fewer decoy pods. Opinion:
  run the final Unseen astronomy problems in `full` if memory allows, or label them svelte.
- **Time budget:** `--agent-timeout` default 1800 s for the whole agent phase, both stages together
  (main.py:1171-1176, README.md:143-145); the clock starts when the agent container launches (main.py:546-547).
  Top leaderboard agents take 76-310 s to diagnose (sota.md:31-41). So waiting 2-4 minutes after injection to let
  metrics accumulate is affordable.
- **Non-LLM agent:** the harness runs any `kickoff_command` (agents.yaml); `jev_diag` is registered in this fork
  (agents.yaml, entry `jev_diag`) with a filtered-egress rule (`provider_endpoints.py:87-91`). In the upstream main
  clone (`~/sregym/SREGym`, 7c3170e3) that file is a local modification, so upstream does not ship it. The SREGym
  blog published v1's results (sota.md:44-47), but the leaderboard has no non-LLM entries (sota.md:27-28). Whether a
  non-LLM agent can be ranked is **unknown; ask the maintainers**.
- **Models:** SREGym does not restrict which model the agent calls; filtered mode allows the provider of the
  configured `--model` (for `openrouter/...` that is all of openrouter.ai, provider_endpoints.py:87-90). Using Jev or
  Decisions for the submitted diagnosis and other OpenRouter models only for robustness is a team choice, not an
  SREGym rule (STRATEGY open question 3).
- **Submission:** `POST {API}/submit` with `{"stage": "diagnosis", "solution": "<text>"}` (driver.py:126-131,
  `sregym/conductor/conductor_api.py:219-230`) or the MCP `submit` tool (`mcp_server/submit_server.py`). The judge sees
  only that text and the ground truth (benchmark-landscape.md 3.1).
- **Mitigation and ranking:** the leaderboard ranks by end-to-end (sota.md:27-28); a pass needs diagnosis AND
  mitigation (`sregym/results/report.py:57-95`). If the agent exits after diagnosis, the attempt is recorded
  `incomplete` ("agent_exited_before_all_stages_completed", main.py:620). The team's runs use
  `--stages diagnosis` (docs/jev-v2-batch.sh:16-18), which is fine for measuring diagnosis but cannot produce a
  leaderboard E2E entry. A ranked entry would at least have to submit the mitigation stage (an empty submission
  closes it, `clients/codex/driver.py:179-182`).

---

## 6. Feasibility table and recommended first build

Cost = build effort + run time. Risk = chance of misleading evidence or harming the fault. "Lite" = whether the
Lite set can exercise it during development.

| # | source | available? | cost | risk | what it reveals |
|---|---|---|---|---|---|
| A | cAdvisor + kube-state-metrics via PromQL (CPU usage vs limit, throttled ratio, memory vs limit, OOM events, restarts, last-terminated reason, network errors) | yes, all apps; 1m resolution; no pre-fault baseline | low: one MCP client, ~10 aggregated queries, a few seconds | low; known chronic decoys (load generator, sidecars); container-level CFS series may be missing on cgroup v2 (pod-level fallback, values.yaml:801-836) | capacity vs demand, throttling/OOM/memory growth origins, per-pod skew, onset order across workloads |
| B | spanmetrics RED per service and span (`traces_span_metrics_*`) | astronomy, blueprint: yes; hotel: yes but `namespace` mislabeled, coverage per service unverified; social: 1% sampling, unverified | low | medium: mislabels, sparse data, no edge label | which services error or slow first, retry amplification (call-rate jump), publish vs receive gap (consumer lag) without exec |
| C | locust per-endpoint failures (astronomy) | yes, 15 s | low | low (by-design signal; SREGym alerts use it) | user-facing symptom set and onset, for D3 scope |
| D | blackbox `probe_success` per Service | hotel 8, social 13, astronomy 16 services; 1m | low | medium: the prober sits in `observe`, so a policy that blocks only some sources may differ from the app's view | reachability break per Service and when it started |
| E | KSM object history (series that ended = deleted objects; generation/resource-version steps; replica changes) | yes; 1m | low-medium | medium: objects that lived < 1 scrape before deletion are missed (app lives 15-50 s before the fault) | deleted Services/ConfigMaps/Secrets, when a spec changed, in addition to managedFields |
| F | app-exported counters (hotel search/rate) | hotel only | low | low; generic use = "any counter in the app's scrape job that jumped" | retry/timeout/queue saturation evidence for interaction faults |
| G | node-exporter (conntrack, fs, memory, disk, time offset) | yes; on kind all nodes share one kernel, so kernel-wide values are identical across nodes | low | medium on kind (no per-node contrast) | node resource exhaustion (only real substitute for node probes in filtered mode) |
| H | Jaeger dependency graph | astronomy, blueprint: yes; hotel partial; social sparse | medium (service->workload mapping) | medium-high: missing edges look like "no call" | call edges for propagation, victims vs origin, blast radius |
| I | Jaeger raw traces (20 per call, no error filter) | as H | medium-high (big JSON, sampling bias) | medium | concrete error strings, which upstream host:port a proxy actually called (D2 values) |
| J | Loki logs (deleted/old pods, all namespaces incl. CoreDNS) | yes, all apps; 100 lines/call; metric queries lose labels via MCP | medium | low-medium (noise) | logs of pods replaced by the fault's rollout, errors before restarts, old vs new pod contrast, DNS errors |
| K | outside objects via kubectl (Ingress, PriorityClass, StorageClass/PV, CRDs/CRs, kube-system workloads/ConfigMaps, other namespaces, nodes, events cluster-wide) | yes (cluster-admin through proxy) | low: 10-20 list calls, 1-3 s | medium: SREGym infra objects and post-deploy setup changes look like causes; needs relation filter | outside origins (~13 problems in the landscape table) |
| L | exec tests from a client pod: DNS resolve, TCP connect to VIP vs pod IP, HTTP status | yes where the image has tools (hotel image is Debian golang-based; distroless images have none; check `command -v`, v1 `_missing_binary`, probes.py:95-96) | medium | low (no state change) | separates DNS vs selector/port vs NetworkPolicy vs dead backend: the "look closer" tie-breaker |
| M | exec into datastores (valkey/redis INFO/CONFIG GET, psql SELECT on pg_locks/pg_stat_activity, mongo ping/auth) | yes; SREGym expects it | medium | medium-high in memory-capped containers (OOM can erase runtime faults); safe with native tools + headroom check; skip JVM tools | runtime-only state: live config vs declared, auth, locks, memory policy |
| N | node internals by exec/kubelet (conntrack table, df, kubelet config, dmesg) | **no** in filtered mode (host-network exec, nodes/proxy and privileged pods refused) | - | - | use G instead |
| O | shipped manifests / Helm release Secrets | **no** (not mounted; Helm records blocked by design) | - | would be cheating | - |
| P | load-generator objects and their Loki streams | objects hidden; Loki leaks them | - | against SREGym's intent; do not use | - |

### Recommended minimal set to build first (opinion)
1. **K: outside objects**, with a relation filter (object -> app pods it selects, admits, schedules, routes to,
   or shares a node with). Cheapest, deterministic, and fixes a whole class v1 cannot see.
2. **A + B + C + D in one PromQL module** through the existing MCP client pattern: about 12 aggregated queries,
   per workload "now" values plus an early-vs-late post-onset trend (subqueries), absolute signals, and a robust
   z-score across peer services. Map spanmetrics by `service_name` (not `namespace`). Make the agent wait so that at
   least 3 minutes have passed since the stage opened before reading metrics (fits the 1800 s budget).
3. **L: client-side resolve/connect tests** as the generic tie-break library (STRATEGY 3.5).
4. Later: **J** (Loki for replaced pods and CoreDNS), **M** restricted to native read-only CLIs with v1's
   headroom check, **E** (KSM deletions), and **H** only after the verification below.

### Verification to do in stage 0 (one short run on Lite problems only, not on Unseen)
On one hotel, one social-network and one astronomy Lite problem with `--stages diagnosis`, record:
`get_services`, `get_dependency_graph(10)`, `count by (service_name, namespace) (traces_span_metrics_calls_total)`,
`count by (job) (up)`, the time each MCP call takes, and whether `kubectl exec ... -- sh -c 'command -v getent curl'`
works in each app image. This settles trace coverage, the hotel/social labels, latency and tool availability.
About 30 minutes.

---

## Answers to STRATEGY section 6 open questions
1. Prometheus history: yes for all apps, but only ~15-50 s before the fault with default settings (no real
   pre-fault baseline). Traces: astronomy and blueprint yes; hotel arrives but mislabeled and unverified per
   service; social 1% sampled and unverified.
2. Read-only exec probes: fair and expected by SREGym (valkey-cli); refused only into host-network pods in filtered
   mode. The real risk is OOM in memory-capped containers, not the rules.
3. SREGym does not restrict the model; which model "counts" is the team's choice.
4. Not reading shipped manifests is consistent with SREGym: they are not mounted in the agent container and Helm
   release Secrets are blocked on purpose.

## Disclosure
While grepping `sregym/` for the words "cheat|leak", two result lines came from the mitigation-oracle files of two
sealed problems (`cumulative_admission_webhook_timeout_mitigation.py:385`, `missing_stale_cache_fallback_mitigation.py:484-493`).
I did not open those files, read no ground truth, and excluded `oracles/` and `generators/fault/` from later
searches. The run data I used is from Lite and other non-sealed rows of `runs-index.tsv` only.
