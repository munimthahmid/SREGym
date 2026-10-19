# v1 (`jev_diag`) architecture study

Status: complete (2026-10-19). Read-only study of `~/sregym/SREGym-fixes/clients/jev_diag/` (run tree
066c4d2f; the folder arrived in one commit, 6400cd46, so git history says nothing about how v1 evolved).
Run evidence is from `lite5/lite6/held*/tgt` runs in `runs-index.tsv`, arms 2 (v1+Jev) and 3 (v1+Decisions).
Sample C was not opened.

"Fact" = read in code or run files. "Opinion" = my judgment, marked as such.

---------------------------------------------------------------------------------------------------------
## 0. The short version

* v1 is a **fixed-shape decision tree** around one big code-built snapshot. Code collects ~25 kinds of
  Kubernetes facts, turns them into short English **signal strings** per workload ("component"), tags each
  component with **evidence kinds** (change / configuration / pointed_at / own_failure_logs / symptoms) by
  string matching, and asks the decision model to pick a component. Then it reads that one component in
  depth and asks: origin, victim, unrelated or undetermined; next component; cause category; one key
  evidence item. A confirmed origin (p >= 0.6) usually ends the search.
* **In practice it is two calls**: 39 of 44 Jev runs and 39 of 44 Decisions runs made exactly 2 requests
  (triage + one investigation). The "iterative walk" mostly does not walk.
* What it gets right comes mostly from **code that computes a concrete, quotable fact** (a template diff, a
  selector mismatch, a stale Secret read through env, a webhook that rewrote a pod) and puts it in front
  of the model as a selectable option whose text goes straight into the report.
* What it gets wrong: anything that is not one Kubernetes workload (CoreDNS, a Kafka topic, an RPC path),
  anything not visible as a spec or log line (runtime CONFIG SET, retry loops), anything code does not
  compute a fact for (probe timing, a removed env var with no managedFields trace), and anything with two
  sides (load source vs. victim, client vs. server).

---------------------------------------------------------------------------------------------------------
## 1. End-to-end flow

### 1.1 Driver and timing (`driver.py`)
1. Wait for the conductor's diagnosis stage, read app info (`/get_app`: name, namespaces, description).
2. Sleep `--start-delay` 120 s minus the trend interval, take a light **trend sample** (pods + events),
   sleep 45 s (`DEFAULT_TREND_INTERVAL`), then run the full collection. Growth between the two samples
   becomes signals (`trend.apply_trend`: restarts that rose, pods still Pending, warning events that repeated).
3. `collect_snapshot` (collector.py) then `derive.post_process` (always, at the end of collection).
4. Optional `--exec-probes` (off by default; **off in every studied run**, `"exec_probes": false` in the
   traces): Kafka consumer-group progress sampled twice, 15 s apart (`probes.broker_progress`).
5. Diagnoser: `--mode tree` = `IterativeDiagnoser` (the v1 arms); `oneshot` = `JevDiagnoser` (2 fixed
   requests, the blog's earlier design). In `--mode arms` (all studied runs) v1 is built **without the
   `probe` callback** (`clients/jev_v2/arms.py` lines 71-77), so the backend health probe never runs either.
6. `build_diagnosis_text` assembles the report from typed answers; submit.

### 1.2 Triage (one request, `tree.triage` -> `classifier.build_component_questions`)
State: `snapshot.to_state()` = `{application, cluster, components}`, cut by `fit_state_to_budget` to 24,000
*estimated* tokens (2 chars/token, so ~48k chars). The trim ladder (`collector._trim_steps`, 20 steps) first
drops detail from healthy components, then caps logs/events/pods for all. Astronomy Shop states hit the
budget (e.g. lite6_valkey_auth 26.9k -> 20.2k after 7 steps; tgt_update_incompatible 37.2k -> 23.9k after
18 steps); Hotel Reservation and Social Network usually fit untouched.

Three questions in one request:

| Name | Type | Question (verbatim) | Options |
|---|---|---|---|
| `root_cause_component` | Choice | "Exactly one fault was injected into this Kubernetes application after it was deployed and healthy. Which single component is the origin of that fault?" | every workload id (`deployment/x`, ...) plus `other` ("an object that is not a listed workload: an admission webhook, a ResourceQuota or LimitRange, an RBAC role, a node, or a namespace-wide policy. See `cluster.findings`") |
| `fault_object_kind` | Choice | "Which kind of Kubernetes object carries the injected change that explains the abnormal signals in `components` and `cluster.findings`?" | 10 kinds: workload_spec, service, network_policy, config_object, namespace_policy, admission_webhook, rbac, node_or_cluster, data_or_traffic, not_visible (`FAULT_OBJECT_KINDS`) |
| `fault_visible` | Noul | "Does the state contain clear evidence of an active fault ...?" | true/false |

The component question carries a 6-step **triage_order** (classifier.py lines 278-299): prefer `change`
(unless only telemetry), then `configuration`, then `pointed_at`/`own_failure_logs`; `symptoms` and
`error_logs_only` never select on their own; a component whose only problem is failed calls is a victim;
pick `other` when a cluster finding explains things better. The model sees a "what_the_state_contains"
glossary of the signal vocabulary. This is the heart of v1's domain prior, written as instructions.

### 1.3 Queue (`tree.initial_queue`, code only)
* Triage candidates in probability order, up to `MAX_QUEUE`=6, stopping below `MIN_QUEUE_PROBABILITY`=0.05.
* Plus up to `QUEUE_EXTENSION`=4 components triage left out that carry evidence kinds, ranked
  configuration < pointed_at < own_failure_logs < change < symptoms (note: here a bare `change` ranks
  *below* configuration, the opposite of the triage prompt's rule 1).
* Telemetry components without symptoms/own failure/configuration go last.
* If triage puts >= 0.3 of `fault_object_kind` mass on cluster-level kinds (namespace_policy,
  admission_webhook, rbac, node_or_cluster, network_policy) and findings exist, `other` (= the cluster
  node) is moved to **position 1, after the first candidate** (lines 482-486). See limit 4.2.

### 1.4 Investigate node (`tree.investigate`, one request per component)
Code fetches detail live (`investigate.collect_component_detail`, section 2.2), builds a numbered
evidence list (`tree.detail_evidence`, at most 32 items, fixed order: template changes, signals, spec
checks, service checks, probe result, non-default pod settings, salient env, probes, command/args,
image+resources, ConfigMap keys, RBAC, log samples, repeated failures, previous logs, events,
dependencies, remaining env), and sends state `{application, candidate{id, kind, signals, evidence_kinds,
role, detail}, evidence, triage_ranking (top 8), investigated_so_far, cluster_findings}`, cut to 22,000
estimated tokens (`DETAIL_TOKEN_BUDGET`; never actually trimmed in the runs I checked, states are
2-9k est. tokens).

Questions (5 always, 6th when input candidates exist):

| Name | Type | Question (verbatim, shortened how_to_decide) | Options |
|---|---|---|---|
| `verdict` | Choice | "Is `candidate` (Deployment `x`) the origin of the injected fault, a victim of another component, unrelated, or undetermined?" Decide in order: code-found spec/service mismatches make it origin; then look for the mechanism in template_changes, admission_changes, env, probes, ConfigMap content, RBAC, events, log classes; only ongoing errors count; victim needs ongoing errors naming a dependency, which may look healthy; Pending/not-ready are symptoms; telemetry export errors never count. | origin / victim / unrelated / undetermined, each with "what" and "not_for" text (`tree.VERDICTS`) |
| `next_component` | Choice | "If `candidate` is not confirmed as the origin, which component should be investigated next?" First choice: the component its ongoing errors fail to reach (use `failing_targets`, map roles like redis to the cache); second: callers with errors or abnormal triage candidates. | linked components not yet investigated (calls, callers-with-errors, failing targets, clients, shared Services), max 12; padded from triage if < 2; plus `none` |
| `fault_category` | Choice | "If `candidate` is the origin, which category names the cause?" Symptoms are not causes; a limit is a cause only if too low for normal needs; a value the pod has but its template lacks was set at admission. | 18 categories (`FAULT_CATEGORIES`): config_value, credentials_or_auth, image_or_binary, resource_limits, scheduling_constraint, rollout_or_replica_config, health_probe_config, service_routing, network_policy, traffic_policy, dns_resolution, storage_volume, job_lifecycle, admission_or_namespace_policy, rbac_permission, data_or_traffic, code_bug, other |
| `blocked_input` | Noul | "Do `candidate.detail.logs` ... show `candidate` failing again and again on one specific input item (a message, record, offset, row, file, or job), so that it cannot move on to later input?" | true/false |
| `key_evidence` | Choice | "Which single item in `evidence` most directly reveals the mechanism of the fault, assuming `candidate` is the origin?" Prefer config/policy/permission/change items over states; prefer one specific value. | E1..En |
| `input_source` | Choice | "If `candidate` reads its input from a queue, topic, stream, or table, which value in `candidate.detail.input_candidates` names that source?" | I1..In (short identifier-like env values) + `none` |

Note that all questions are asked every time, so category and key evidence are answered "assuming origin"
even when the verdict is victim. Only the verdict and next-hop answers drive the walk.

### 1.5 Transitions (`tree.diagnose`, code only)

| Condition | Action |
|---|---|
| `origin_p` >= 0.6 (`MIN_ORIGIN_PROBABILITY`) and category is credentials_or_auth or rbac_permission, and `other_side()` finds a component | defer: examine the other side first (the user of the fault object, the server's top 2 `login_candidates`, or the first `failing_target`) |
| other side also reaches origin_p >= 0.6 | **pair node** question `faulty_side`: "<reason>. Which side holds the wrong or stale setting that has to change for the two to work together again?" Options a / b / none. Winner needs p >= 0.5, else higher origin_p |
| `origin_p` >= 0.6, no other side | conclude, unless an unexamined component had a higher triage probability and origin_p < 0.9; then examine up to 2 of those first (`defer_conclusion`) |
| `victim_p` >= 0.5 and next hop p >= 0.3 | next hop to the front of the queue; this victim's `failing_targets` inserted right behind it as backups |
| not victim, next hop p >= 0.3 | append next hop to the end |
| `other` popped | **cluster node** (below); conclude if it picks a finding with p >= 0.6 |
| queue empty or `max_steps`=18 | fallback |

**Cluster node** (`tree.cluster_node`): state = `{application, findings[F1..], affected_components{signals,
3 warning events}, cluster_dns}`; one Choice "Which cluster-level or namespace-level object in `findings`
explains the abnormal signals of the `affected_components`?" with a how-to list (webhook without backend,
mutating webhook rewrite, quota rejection, CoreDNS rule, NetworkPolicy, role denial, stuck Terminating);
options F1..Fn + `none`.

**Fallback** (`tree.fallback`), in order: (1) best investigated origin verdict with origin_p >= 0.4;
(2) end of a strong victim chain (victim p >= 0.9 naming its next hop p >= 0.9, the hop is in
`failing_targets`, was examined and is not a victim); (3) `other` if triage chose it; (4) triage top-1
that is not telemetry. For (2) a **chain characterization** request re-asks category and key evidence
from the victim's failure lines plus the dependency's evidence ("`victim` fails when calling `dep`, and
`dep` shows no fault in its own collected state. Which category names the fault inside `dep` ...").

### 1.6 Report (`classifier.build_diagnosis_text`, code only)
* **Fault object**: `tree.fault_object` maps the category to an object kind (`CATEGORY_TO_OBJECT_KIND`, 8
  entries), or to a mutating webhook when the pod-vs-template diff touches a field that explains the
  category (`_ADMISSION_FIELDS`), and picks a linked `cluster.findings` entry (`select_fault_object`,
  scored by link + marker words "not granted", "rejects", "rewrites pods of", "0 ready endpoints",
  "overrides name resolution", + "modified/created").
* Text: if the fault object is a **carrier** (webhook, quota, LimitRange, role/binding, NetworkPolicy;
  `CARRIER_KINDS`) it leads with "Root cause object: ... acting on <component>"; else if blocked input,
  "Root cause: one input item fails ..."; else "Root cause component: ...". Then "Mechanism: <the chosen
  key evidence text verbatim>", "Fault object: ..." (Service/Secret/ConfigMap), "Fault type: <category
  gloss>", up to 4 code-found mismatches, up to 12 abnormal signals, impact lines (callers whose errors
  name it, Local-policy gaps, stuck objects), spec flags, containers, warning events, ongoing error lines,
  previous-run log lines, alerts, a "Classification: Jev confirmed ... probability" line and a
  "Low confidence: X cannot be ruled out" line when triage confidence < 0.3.
* No model writes text. Every word is either a template or a collected string.

### 1.7 Budget
`max_steps` 18 investigation/cluster steps; per request state budgets 24k (triage) and 22k (detail)
estimated tokens; no time budget in the tree itself. Retries: OpenRouter client 3 retries within 240 s.

---------------------------------------------------------------------------------------------------------
## 2. What evidence v1 collects, and how

### 2.1 The snapshot (`collector.collect_snapshot`, ~25 kubectl reads per namespace, then `derive.post_process`)
Unit = **component** = one Deployment, StatefulSet, DaemonSet, CronJob or Job (`WORKLOAD_KINDS`). Pods,
events, Services, policies, config objects are attached to components by owner chain or label selector.

Per component (facts code derives; each abnormal one is also written as an English **signal** string):
* Spec summary (`summarize_workload`): replicas, rollout strategy (signal when maxUnavailable >= replicas or
  both 0), containers (image, limits, requests, ports, env *names*, envFrom, probe target only, mounts,
  command/args), duplicated env names (signal with every value), probe on an undeclared named port, the
  same mount path twice, the same PVC twice, hostAliases / nodeSelector / non-default dnsPolicy / dnsConfig
  / hostNetwork (`spec_flags`, promoted to signals for DNS/network ones), CronJob/Job status (suspended,
  active without success, jobs piling up), Progressing/Available conditions.
* Pods (`summarize_pod`): phase, ready x/y, restarts, waiting reasons, terminated exit codes, OOMKilled,
  unschedulable message, init container stuck > 60 s, "container A completed but B keeps running" (job
  sidecar), settled warm-up restarts moved to `startup_history`.
* Warning events (max 6 per component; warm-up ones and ones about pods that no longer exist are history).
* Services: ports, ready/not-ready endpoints (signal "0 ready endpoints"), internal/external traffic policy,
  session affinity, a selector spanning several workloads (`flag_service_fanout`, with unexposed
  targetPorts), a Service named after a workload whose selector no longer matches it.
* NetworkPolicies selecting the component (signal "selected by NetworkPolicy X (denies all ingress)").
* HPA problems, PVC not Bound, ReadWriteOnce claim mounted by >= 2 replicas (`checks.shared_rwo_claims`).
* `kubectl top`: CPU >= 90 % of limit ("throttling likely"), memory >= 90 % of limit.
* Config objects: referenced ConfigMap/Secret missing; key names and last write (never Secret values);
  **staleness by read mode** (`_stale_readers`: rewritten after the container started; env/envFrom/subPath
  keep the old value, volume files update in place); env var shadowed by envFrom.
* Env addresses (`checks.resolve_env_hosts`): env values parsed for hosts and matched to Service names give
  `calls_services`, `_calls` and the reverse `clients`; Local traffic policy gaps per client node.
* Pod vs. template (`checks.admission_changes`): image/limits/requests/env that the running pod has and its
  ReplicaSet template lacks, minus Kubernetes and LimitRange defaults, plus the mutating webhooks whose
  rules and selectors match the pod.
* Logs (`attach_logs`): 200-line tail of up to 2 Running pods, `--previous` for crashed containers;
  error lines (section 2.4) deduplicated into signatures with count, first/last seen, median gap and
  `ongoing`/`stopped`; lines before first Ready (max 120 s) dropped.
* Alerts from the Prometheus MCP, matched by label.
* Trend (two samples 45 s apart): restarts that grew, still Pending, events that repeated.
* Derived: `role: observability` (name regex), `evidence_kinds`, `healthy`.

Cluster part: nodes (conditions, cordon, taints), firing alerts, NetworkPolicies, Services matching no
workload, **CoreDNS** (Corefile `template`/`rewrite`/`hosts` blocks, plugins, last write, pods ready; a rule
naming an app Service becomes a signal on that component), LimitRanges and ResourceQuotas (>= 90 % used;
a hard cpu/memory quota with containers that declare none and quota events -> "rejects pods of ..."),
admission webhooks (rules, failurePolicy, backend endpoints; "0 ready endpoints ... requests fail"),
RBAC roles bound to the app's service accounts (signal only when a bound workload logs denials; the
denied verb/resource is checked against the rules), objects stuck Terminating on finalizers (linked to the
controller whose role covers the resource and logs denials), `symptom_onset`, `recent_changes`, and
`findings` (every non-workload object with a computed signal or a recorded change).

### 2.2 Detail reads (`investigate.collect_component_detail`, live, per investigated component)
Full workload JSON (env values up to 40 per container, full args, **full probe objects**, volumes,
dnsPolicy, affinity, tolerations, managedFields writers); up to 3 pods' JSON and the namespace's current
events; 300-line logs of 2 pods with `--previous` (40 lines) for crashed containers, error samples with
recency, `error_classes_still_occurring`, `repeated_failures` (same wording >= 3 times over >= 30 s, with
the tokens that never change, e.g. `offset=20`), telemetry errors separated, a 12-line tail; ConfigMap
contents (400 chars per key, 4000 total); `spec_checks` (probe port not declared, only for a not-ready
container; env `host:port` vs. the Service's ports); `service_checks` (targetPort vs. container ports,
no endpoints, Local gaps, multi-workload selector); RBAC bindings and `kubectl auth can-i --list` as the
service account; `input_candidates` (identifier-like env values); `calls` (each dependency's **own** state:
own signals, pods ready, restarts, `looks_healthy_on_its_own`); `called_by_with_errors`; `failing_targets`.

### 2.3 Probes (`probes.py`, need `--exec-probes`; **none ran in the studied runs**)
* Kafka consumer-group lag sampled twice: a partition whose committed offset is frozen while the log end
  grows marks the consumer (by pod IP) with `blocked_input` (group, topic, partition, offset). JVM tool,
  run only with 768 MiB free.
* Backend health command inside a healthy-looking backend that a victim's errors name (`valkey-cli ping`,
  `pg_isready`, mongo ping, `mysqladmin ping`), output mapped to a meaning ("the server requires
  authentication"), plus the client's credential env var names. Gated by memory headroom.

### 2.4 Change detection (`changes.py`)
Three sources, judged against the object's own history, not a deploy time:
1. **managedFields**: a spec write >= 10 s after creation (`modified_after_creation`), with the field
   paths of non-creator writers (`later_writes`).
2. **Created later than its targets**: >= 10 s after the median creation of the objects it acts on.
3. **Pod template revision diff** (ReplicaSets, ControllerRevisions): field-level old -> new for labels,
   annotations, scheduling, DNS, hostAliases, SA, security context, termination grace, volumes, and per
   container image, command/args (500 chars), env added/removed/changed, envFrom, resources, probes, ports,
   mounts.

Changes older than 1 h are dropped. The rest are ranked by when they happened relative to the estimated
first active symptom (earliest of: ongoing error signature first seen, pod not ready since, last crash,
Pending pod created, warning event first seen, alert active since); the nearest change before onset gets
`nearest_change_before_symptoms: true`. Each change becomes a signal on the components it affects.
Important gap: a revision diff **alone never creates a change record** (`object_change` returns None unless
1 or 2 holds; collector.py lines 2112-2124), see 4.5.

### 2.5 Log classification (`collector.is_error_line`, `derive.classify_logs`)
* Error line: a broad keyword regex (`_ERROR_LINE_RE`) unless the line declares a quiet level (JSON/logfmt
  level, Mongo "s", .NET, klog, bracket or token levels), or an explicit failure outcome at any level
  (`_FAILURE_OUTCOME_RE`: NOAUTH, WRONGPASS, HTTP 4xx/5xx, "consumer ... paused at offset", "skipping
  malformed record", ...).
* Semantic classes (`LOG_CLASSES`, regex): authentication failure, authorization denied (RBAC), DNS
  resolution failure, message or data processing failure, out of memory, filesystem permission denied,
  overload or quota exhaustion, connectivity or timeout. Dependency classes point at the named target;
  own-failure classes give the logger a "logs report <class>" signal (`own_failure_logs`).
* Telemetry export failures (`TELEMETRY_RE`) are counted apart and never point anywhere.
* Server-side login rejections (`LOGIN_REJECTIONS`, postgres/mysql/mongodb/rabbitmq formats) are reported
  on the **server** as "rejects logins for account X ... the rejected credentials come from its clients",
  and clients are scored as `login_candidates` (secret rewritten shortly before rejections began and read
  through env +3, sole env value naming the account +3, env addresses the server +1, only database +1,
  refreshed template -2).

### 2.6 Error-pointer links
* `errors_point_to` (on the caller) and `referenced_by_errors_from` (on the callee, `{caller: {class:
  count}}`) come from `derive._mentions`: every **ongoing, non-telemetry** error line of A is searched for
  whole-token names of other components and their Services (plus role synonyms like redis/valkey when
  exactly one component plays that role). The callee gets the signal "errors logged by N other
  component(s) (...) name this component (<top class>, n lines, still occurring), e.g. '...'" ->
  evidence kind `pointed_at`.
* In detail, `failing_targets` = dependencies whose name parts, image repo tokens or role synonyms appear
  in A's ongoing error text; they become the default next hop and backups behind it.
* These links are **textual**: any name inside an error message counts, including names relayed from
  further down a call chain (see 4.9).

---------------------------------------------------------------------------------------------------------
## 3. Where the domain knowledge lives, and how general it is

### 3.1 What the model decides vs. what code decides
| Decided by the model (calibrated choice) | Decided by code (fixed) |
|---|---|
| which component to start from (triage); fault object kind; fault visible | what is read, what becomes a signal, the wording of every fact |
| per component: origin/victim/unrelated/undetermined | `evidence_kinds` tags (string markers) |
| next component (among code-built linked options) | which components are options at each step |
| cause category (18 fixed) | queue order, thresholds, when to stop, fallback order |
| one key evidence item | the fault object (category -> object kind map + finding scoring) |
| blocked input yes/no and its source | which side is "the other side" (credentials/RBAC only) |
| cluster finding; which side of a pair; chain category | the whole report text and which lines appear |

### 3.2 Inventory of hard-coded knowledge (generality is my estimate)
| Piece | Where | Kind of knowledge | General? |
|---|---|---|---|
| Kubernetes object cross-checks (selector vs. labels, endpoints, targetPort vs. ports, Local traffic policy vs. client nodes, RWO claim vs. replicas, quota required fields, LimitRange defaults, pod vs. template admission diff, finalizer + RBAC gap, env read modes) | collector.py, checks.py, derive.py, investigate.py | Kubernetes semantics | **High** for the fault family each check covers, zero outside it. It is a library of detectors, each phrased as a neutral fact. |
| Change detection + onset ranking | changes.py | "faults are recent writes" | **High** for injected faults; blind to changes leaving no managedFields/revision trace and to faults deployed broken. |
| Error line and level regexes | collector.py lines 64-111 | log formats | Medium-high (English, common formats). |
| 8 log classes, telemetry regex | derive.py lines 52-106 | SRE vocabulary | Medium. |
| Role synonyms, login rejection formats (4 servers), probe commands (redis, postgres, mongo, mysql), Kafka tool | derive.py lines 125-163, probes.py | specific technologies | Low-medium: one table row per technology. |
| `OBSERVABILITY_RE` (grafana, jaeger, otel, ...) | derive.py line 35 | names of telemetry products | Low-medium. |
| Signal wording -> evidence kind (`SYMPTOM_MARKERS`, `CHANGE_MARKERS`, `POINTED_MARKERS`, `OWN_LOG_MARKERS`) | derive.py lines 586-632 | coupling to v1's own strings | **Brittle**: anything not listed is "configuration" (see 4.7). |
| Triage order, verdict criteria, category "what/not_for", cluster how-to | classifier.py, tree.py prompt text | SRE priors in plain words | High as priors; the model applies them to any evidence. |
| 18 cause categories, 10 object kinds, `CATEGORY_TO_OBJECT_KIND`, `_ADMISSION_FIELDS`, `CARRIER_KINDS` | classifier.py, tree.py | a fault taxonomy of Kubernetes | Medium: covers spec/config/policy faults well; thin on runtime state, load, data, interactions. |
| Fault-shaped special paths: blocked input (poison message), other side (credentials/RBAC), pair node, chain characterization, stale env credentials, cronjob sidecar, rolling update, duplicate env/mount/PVC | tree.py, derive.py, collector.py | each matches one SREGym-Lite fault family (compare the blog's 21 faults) | Low-medium: general wording, but built from Lite failures. |
| Thresholds 0.6 / 0.9 / 0.5 / 0.3 / 0.05, queue sizes 6+4, 32 evidence items, budgets | tree.py lines 59-75 | tuning | Unknown; tuned on Lite. |

Opinion: v1's real "intelligence" is the detector library plus the change/onset ranking. The model's main
jobs are (a) to pick the component whose facts look most like a cause, using the triage order, and (b) to
pick which fact to quote. Both are choices among things code already found.

---------------------------------------------------------------------------------------------------------
## 4. Built-in assumptions and limits (each with code and run evidence)

Scores below are judge composites (pass >= 0.70), Jev arm / Decisions arm.

### 4.1 "The origin is one workload"
* Code: triage asks "Which single component is the origin"; options are workloads plus one `other`
  (`classifier.component_options`); `Diagnosis.component` is one id; the report leads with "Root cause
  component: <one workload>".
* Runs: `tgt_update_incompatible_correlated` (6 MongoDB images bumped) passes 0.89/0.89 but loses D3
  ("omits mongodb-profile, mongodb-rate, ..."): only `mongodb-geo` is reported. `lite6_kafka_poison_pill`
  0.67/0.56, D1 = 0: the judge wants "Kafka topic/orders-fulfillment"; v1 can only name the consumer
  Deployment (it does find the topic as `input_source` and the offset, but as a sentence, not the origin).
  `lite5_search_rate_retry_collapse` 0.34/0.34: origin is "the search-to-rate RPC path"; v1 names `rate`.
  `held*_valkey_memory_disruption` 0.45 in all 8 v1 arms: v1 names the injector `job/valkey-memory-flood`
  (triage 0.90), the judge wants `valkey-cart`. A "load source -> victim" fault has two ends; v1 must pick one.

### 4.2 Cluster-level objects (CoreDNS and similar)
* Code: cluster objects are reachable only through the single `other` option and the cluster node.
  `initial_queue` moves `other` to **position 1** whenever the kind mass is >= 0.3 (tree.py 482-486), so
  when triage ranked `other` first it gets **demoted behind the top workload**. Then any workload with
  origin_p >= 0.6 ends the search: the "higher-ranked unexamined" check only looks at
  `c in snapshot.components` (tree.py 814-821), so `other` never counts as higher.
* Report: a fault object leads the text only if its kind is in `CARRIER_KINDS` (webhooks, quotas,
  LimitRanges, roles/bindings, NetworkPolicy). A ConfigMap such as `kube-system/coredns` appears only as a
  secondary "Fault object:" line under "Root cause component: Deployment frontend".
* Runs (`service_dns_resolution_failure_astronomy_shop`): Jev triage put 0.72-0.87 on `other` and 0.92-0.96
  on `node_or_cluster` in held, held3, held4. Queue = [frontend, other, ...] in all three. held3/held4:
  frontend origin_p 0.67/0.61 -> concluded frontend -> **0.55** (D1 0.33, "conflating the affected endpoint
  with the origin"). held: origin_p 0.56 -> cluster node picked F1 with 1.0 -> **0.89**. Same for
  `lite6_service_dns_resolution_failure_social_network`: Jev origin_p 0.45 -> cluster node -> 0.89;
  Decisions put 0.92 on the workload -> 0.67. So the DNS outcome depends on whether the workload's
  origin probability happens to fall under 0.6. Opinion: this is a plain ordering bug plus a report
  template gap, not a modelling limit.

### 4.3 Interactions between two services
* Code: the verdict is a 4-way choice that makes origin and victim exclusive. Two-sided reasoning exists
  only for credentials/RBAC (`other_side`, `pair_node`) and for "a victim whose dependency looks healthy"
  (chain fallback). There is no option meaning "the fault is the interaction" (a retry policy on one side
  amplifying a limit on the other, a load generator saturating a cache).
* Runs: `lite5_search_rate_retry_collapse` (the blog's own example; Jev walked rate -> consul ->
  memcached-rate, Decisions rate -> search; both ended on rate, 0.34). `held*_valkey_memory_disruption`
  (job vs. cache, 0.45). `lite6_secret_rotation_stale_env_credentials` Decisions arm: product-catalog got
  origin 0.49 (< 0.6, so no pair node), the queue moved on, postgresql got origin 0.68 and won -> 0.34;
  the Jev arm confirmed product-catalog at 0.65 and passed 1.00. The pair logic only runs if the first
  side crosses 0.6.

### 4.4 Bad input / messages
* Code: a `blocked_input` noul and `input_source` choice (tree.py 316-349); the report then says "Root
  cause: one input item fails processing repeatedly ... The blocked component is X". The broker probe that
  would give group/topic/offset from Kafka itself is off.
* Runs: `lite6_kafka_poison_pill_hol_block` finds offset 20 and `ORDERS_TOPIC=orders-fulfillment` from logs
  and env, but the origin stays the consumer Deployment -> D1 = 0 (0.67/0.56).

### 4.5 Invisible runtime state and invisible changes
* Runtime state: `valkey_auth_disruption` sets `requirepass` with CONFIG SET; nothing in any spec, config
  object or server log changes. The client's line "Wasn't able to connect to redis" is classed
  "connectivity or timeout", not authentication. The probe that would return NOAUTH is disabled in arms
  mode. Jev walked 6 steps (cart -> valkey-cart "unrelated" 0.62 -> checkout -> frontend -> frontend-proxy
  -> otel-collector-agent), fell back to the victim chain, and chain characterization chose
  `service_routing` -> 0.34; Decisions ended on triage top-1 `cart` -> 0.23.
* Invisible change: in `tgt_missing_env_variable_astronomy_shop` the frontend Deployment is at generation 2
  and its revision diff says "container frontend env CART_ADDR removed", but managedFields hold only the
  helm Apply at creation (a pure removal left no spec-write entry; kubectl raw bundle checked). So no change
  record, `signals: []`, evidence kind `error_logs_only`, and triage rule 4 says such a component "never"
  selects on its own. Jev triage chose `email` (0.36), the walk followed error text to shipping, quote,
  otel, checkout and ended on email -> **0.22**. The Decisions arm reached frontend at step 1 (origin 0.42,
  key evidence "env CART_ADDR removed" 0.78) and won by fallback -> **1.00**. The fact was collected; it
  just never became a triage signal.
* Uncollected facts: `detail_evidence` describes probes with `describe_probe` (handler only, tree.py 171),
  so `periodSeconds: 1, failureThreshold: 1` exist in `candidate.detail.workload` but in **no evidence
  option**; `terminationGracePeriodSeconds` is not read in detail at all. `liveness_probe_too_aggressive`:
  Jev picked the ConfigMap script and `code_bug` (0.67, D2 = 0), Decisions 0.89 then 0.00 (one run went to
  the cluster node).

### 4.6 Multiple causes / several mechanisms
* Code: one key evidence item becomes "Mechanism:"; one category. Code-found spec mismatches are all
  listed (max 4), but template changes beyond the key appear only inside a change signal (first 3).
* Runs: `lite6_edge_request_filter_cpu_saturation`: evidence had both "limits.cpu: unset -> 100m" (E8) and
  the new WAF regex args (E5) and "WAF_RULE_REGEX added" (E7). Jev chose E8 (0.42 vs 0.26) -> 0.67;
  Decisions chose E5 (0.80) -> 0.89. The blog reports the same Jev miss 5 of 5 times.

### 4.7 Evidence kinds by string markers
* Code: `derive.classify_evidence` tags a signal "configuration" when it matches none of the marker lists.
  "firing alert X", "service X selects this component but has 0 ready endpoints", "job has 1 active pod(s)
  and has not completed" are all tagged **configuration**. So almost every crashing component carries
  `configuration`, which triage rule 2 treats as a cause.
* Runs: `valkey_memory_disruption`: the flood Job (only signal "job has 1 active pod(s) and has not
  completed") got `configuration` and 0.90 triage; `aux-service` (liveness) got `configuration` from alerts
  and 0 endpoints. Opinion: this is lucky as often as it is harmful; it is not a principled signal.

### 4.8 First confirmed origin wins
* Code: origin_p >= 0.6 concludes (tree.py 797-830) without comparing candidates' explanations; only a
  higher *triage* rank can delay it. A later, stronger candidate is never compared with an earlier one
  except in the pair node.
* Runs: 4.2 (DNS) and 4.3 (secret rotation, Decisions) are both "a plausible workload crossed 0.6 first".

### 4.9 Victim chains follow names in text, including relayed names
* Code: `_mentions` counts any component name inside an error line. A front-end error relaying a deeper
  failure ("shipping quote failure: failed POST to email service") points at shipping, quote and email.
* Runs: `tgt_missing_env_variable` Jev: triage email (0.36, pointed at by frontend's relayed line) ->
  frontend judged victim 0.82 (next hop shipping) -> shipping -> quote -> otel-collector-agent -> checkout;
  no origin, fallback to triage top-1 email -> 0.22. The real error ("Could not parse target name \"\"", 54 lines) has no class and names nothing, so it
  produced no link at all.

### 4.10 Smaller limits
* Telemetry demotion by name: correct most of the time, but a real fault on the otel collector would be
  demoted (tree.py 475-481) and its errors never point (derive.py 292).
* Residue from earlier problems: `configmap/kube-system/coredns` modified ~800 s before onset (by a previous
  problem) appears in `recent_changes` and `findings` of `held3_valkey_memory_disruption`; the 1 h horizon
  keeps it.
* Object kind naming: the judge marked D1-Q1 "No" for naming Deployment `url-shorten-mongodb` and
  Deployment `valkey-cart` when the spec says `service/...` (held5_auth_miss_mongodb 0.78). v1 always names
  the workload kind.
* Deployed-broken faults (no change at all) rely only on configuration checks; nothing compares a setting
  with what is normal for the image or the app.

---------------------------------------------------------------------------------------------------------
## 5. Why v1 generalizes as well as it does (mechanism)

1. **It ships facts, not explanations.** Every detector states a Kubernetes fact in neutral words ("the
   running pod has 16Mi, its template 256Mi; webhook W matches"). A new fault in the same family fires the
   same detector. Held-out sample A shows this: `wrong_service_selector_astronomy_shop` 1.00 x 6 arms,
   `duplicate_pvc_mounts_hotel_reservation` 1.00, `readiness_probe_misconfiguration_hotel_reservation` 1.00,
   `sidecar_port_conflict_hotel_reservation` 0.89-1.00, `incorrect_image` 0.89, `auth_miss_mongodb`
   0.77-1.00, none of which were the development faults.
2. **The benchmark's prior is built in.** "Exactly one fault was injected after it was deployed and
   healthy" + changes ranked against symptom onset + "prefer `change`" is a strong, fault-agnostic prior.
   When the injector writes a spec field (most SREGym faults), the right component has a dated change
   right before onset and triage puts 0.75-1.0 on it.
3. **Short path, few failure points.** Median 2 model calls. The walk rarely runs, so there is little room
   for compounding errors; when it does run long (valkey_auth 8 calls, missing_env 7) it usually fails.
4. **The model chooses among code-made options, so no rule maps evidence to a conclusion.** The decision
   model applies the written priors to whatever evidence appears. Unseen evidence is still a choosable
   option. Hand-written "if pattern then cause" logic is rare in v1 (exceptions in 3.2).
5. **The report quotes the evidence verbatim and is generous.** "Mechanism" is the exact fact with its
   concrete value (the judge's D2 asks for concrete values), and the report adds all abnormal signals,
   impact on callers, events and ongoing error lines, which often earns D3 even when D2 is weak.
6. **Robust plumbing.** Every kubectl read can fail without stopping the snapshot; every step has a
   fallback; budget trimming keeps any app under the context limit.

Opinion on the v1/v2 gap (only as far as v1 explains it): v1 has no fault "patterns" that must match the
evidence before a cause can be stated. Its unit of reasoning is "this component + its strongest fact",
which degrades gracefully: on an unseen fault it still names the changed component and quotes the
change. A design that requires an explanation template to fit fails closed on shapes nobody wrote.

---------------------------------------------------------------------------------------------------------
## 6. Token use per run (arm 2 = Jev, arm 3 = Decisions; 44 runs each, lite5/lite6/held*/tgt)

| | Jev (arm 2) | Decisions (arm 3) |
|---|---|---|
| Requests per run | median 2 (39 of 44 runs = 2; max 8) | median 2 (39 of 44 = 2; max 7) |
| Input tokens per run | median 32.1k (25.7k-87.7k), mean 34.5k | median 22.0k (17.1k-57.2k), mean 23.0k |
| Output tokens per run | median 0.96k | not reported (0) |
| Triage request | median 21.5k (17.6k-26.8k) = 70 % of the run | median 14.3k = 66 % |
| Each investigation | median 9.5k (5.2k-13.7k) | median 7.0k (4.5k-10.8k) |
| Cost per run (OpenRouter) | median $0.00135 | median $0.0022 |
| Summed model latency | median 1.6 s | median 1.5 s |
| Chars per billed token (state + questions) | ~2.2 | ~3.4 |

Same states for both models; the difference in tokens is the tokenizer (Jev counts ~1.5x more tokens
for the same JSON). `collector.CHARS_PER_TOKEN = 2.0` is calibrated to Jev, so the "24k token" triage
budget is ~48k chars and lands near 21-27k Jev tokens and 12-17k Decisions tokens.

What drives it:
* **Triage = the whole application.** Every workload (19-28) with signals, containers, pods, services,
  logs. Components are 75 % of the triage request, questions 20 % (~9.5k chars: the component option list,
  the long instruction glossary, 10 object kinds), cluster 4 %. Astronomy Shop needs trimming.
* **Question text is heavier than the state in investigations.** Median investigation state 11.7k chars,
  questions 14.2k chars: `fault_category` 5.4k (18 categories with what/not_for), `verdict` 3.9k,
  `key_evidence` 2.8k. The evidence list appears **twice** (in state and as option text): ~21 % of the
  request.
* **Walk length.** Each extra step adds 5-14k Jev tokens; the two long walks used 80-88k.
* Not a driver: the detail state, which never needed trimming at the 22k budget.

---------------------------------------------------------------------------------------------------------
## 7. Strengths a better design must keep, and weaknesses worth fixing

### 7.1 Keep
| # | Strength | Code |
|---|---|---|
| K1 | Deterministic, neutral, concrete facts from cross-object checks (pod vs. template + webhook match; selector/port/endpoint checks; Local policy vs. client nodes; env read mode vs. rewrite time; quota required fields; finalizer + RBAC gap; RWO claim vs. replicas) | checks.py, collector.py `attach_*`, derive.py |
| K2 | Change detection from the cluster's own records (managedFields writers and fields, created-after-targets, field-level revision diffs) ranked against an onset estimated from symptoms | changes.py |
| K3 | Error recency by each signature's own rhythm (`ongoing`/`stopped`), warm-up cut, telemetry separation | collector.py 1180-1243, 1246-1275; derive.py 292 |
| K4 | Victim reasoning: callers' errors point at the callee; a dependency is judged by its own state (`looks_healthy_on_its_own`); a server that rejects logins reports on its clients | investigate.dependency_state, derive.server_login_rejections |
| K5 | Model chooses among code-built options; code writes the report from quoted facts (concrete values reach the judge verbatim) | classifier.build_diagnosis_text |
| K6 | Few calls, small cost, fast (median 2 calls, ~1.6 s model time, ~$0.001-0.002) | tree.diagnose |
| K7 | Broad, fault-agnostic triage priors written as plain instructions (change > configuration > pointed_at > symptoms; victims are not origins; telemetry is noise) | classifier.py 278-299, tree.VERDICTS |
| K8 | Robustness: every read can fail, every step has a fallback, budget trimming by priority, replayable raw kubectl bundles | collector.kubectl_items, fit_state_to_budget, replay.py |
| K9 | Generous report: impact on callers, abnormal state, events, ongoing errors, alongside the mechanism (helps D3) | classifier.py 877-924 |

### 7.2 Fix
| # | Weakness | Code | Run evidence |
|---|---|---|---|
| W1 | `other` demoted behind the top workload; `other` never counts as "higher-ranked" | tree.py 482-486, 814-821 | DNS astronomy held3/held4 0.55 vs held 0.89 |
| W2 | Non-carrier cluster objects (CoreDNS ConfigMap) never lead the report | classifier.CARRIER_KINDS, 851-864 | same |
| W3 | A revision diff alone creates no change record, so the component gets no `change` signal | collector.py 2112-2124, changes.object_change 337-340 | tgt_missing_env Jev 0.22 |
| W4 | Evidence kinds by string markers; alerts / 0 endpoints / job-not-done become "configuration" | derive.classify_evidence 586-632 | valkey_memory 0.45 (x8) |
| W5 | Probe evidence drops timing; termination grace not read in detail | tree.detail_evidence 171, checks.describe_probe, investigate.workload_detail | liveness Jev 0.67 (D2 = 0) |
| W6 | One origin, one mechanism, one category: no way to report a set of components, a topic, a path, or two mechanisms | classifier.COMPONENT_QUESTION, Diagnosis | update_incompatible D3 0.67; kafka D1 0; edge Jev 0.67 |
| W7 | First origin >= 0.6 wins; no comparison of competing candidates' facts | tree.py 797-830 | secret_rotation Decisions 0.34 |
| W8 | Name mentions in relayed error text create false pointers; unclassified errors create none | derive._mentions, classify_logs | tgt_missing_env Jev walk |
| W9 | Runtime state invisible; the only tools that see it (backend probe, broker lag) are off in arms runs | probes.py; arms.py 71-77 | valkey_auth 0.34/0.23 |
| W10 | Two-sided faults only for credentials/RBAC; no "interaction" verdict | tree.other_side, VERDICTS | search_rate_retry 0.34; valkey_memory 0.45 |
| W11 | Every question asked every step (category and key evidence even for victims); evidence text sent twice; 18-category text repeated per step | tree.build_investigation_questions | ~55 % of each investigation request is question text |
| W12 | Thresholds hand-tuned on Lite (0.6/0.9/0.5/0.3); results flip on small probability changes | tree.py 59-75 | DNS: 0.56 vs 0.61 decides pass/fail |
| W13 | Fault-type special paths built from Lite failures (blocked input, pair node, chain characterization, admission fields) | tree.py | general in wording, narrow in reach |
| W14 | Workload kind always named; the judge sometimes expects the Service object | classifier.build_diagnosis_text | auth_miss_mongodb D1-Q1 No |

### 7.3 Facts vs. opinions in this section
Facts: every code reference and run number above. Opinions: that K1/K2/K5 are the main source of v1's
generality (I infer this from which runs pass and why, not from an ablation), and that W1-W5 are cheap to
fix while W6/W10 need a different answer shape. Not checked: v1 with `--exec-probes` on (no such graded
runs exist in the index), and whether the blog's 76 % was measured with probes on.
