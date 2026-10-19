# Diagnosis report design for SREGym's judge (review, 2026-10-19)

(Saved by the main session from the reviewer's output; the reviewer could not write files.)

Status: DONE. Read-only. Sources: judge code (`sregym/conductor/oracles/llm_as_a_judge/judge.py`,
`rca_checklists.yaml` v3.0, `llm_as_a_judge_oracle.py`), `Problem.build_structured_root_cause` (`problems/base.py`),
the `root_cause` prose of the 29 studied problems, v1 `clients/jev_diag/classifier.py::build_diagnosis_text`,
v2 `clients/jev_v2/report.py::build_report`, every `*_arms_graded.json` in `runs-index.tsv`, and the 21 rerendered
runs in `jev-v2-runs/results/rerender/` (all map to non-sealed labels by anon id). Sealed check: 0 of the 40 ids
in `UNSEEN-SEALED.txt` appear in `runs-index.tsv` or the rerender set; `sealed/` was not opened; no sealed problem
file, injector or run was read. The judge was not run. Every "estimate" below is reasoning, not a measurement.

Data: 359 graded arms, 354 with a checklist (v1 157, v2 158, v2 rerenders 39). "Right-origin arm" below = judge
said Yes to D1-Q1 and D1-Q3 (271 arms). Counts are over all runs unless a run label is named.

## Summary
1. 354 graded arms mined (157 v1, 158 v2, 39 rerenders).
2. On 271 right-origin arms the losses were D3-Q2 61, D2-Q1 32, D2-Q2 31, D3-Q3 21, D2-Q3 11, D3-Q1 10.
3. Naming the bad value earns D2-Q2 in 239 of 243 right-origin arms; without it 1 of 28.
4. The "Fault type:" line should go: with it D2-Q3 lost 10 of 219 (7 cite the label); without it 1 of 68.
5. A second "Root cause component" label on a victim loses D1-Q2/Q3 (v1 DNS 0/8).
6. Naming only "Deployment X" when GT is service/X earned D1-Q1 2 of 15; leading with the Service 20 of 20.
7. Subject = the object holding the bad value; outside/shared objects first scored full D1 in all 89 such arms.
8. A ConfigMap/Secret used by one workload is not the subject; the component is, with both kinds named.
9. The rerender (v1-style rewrite) changed nothing on its own (35 passes before and after).
10. Affected components named as callers with symptoms: D3-Q2 28 of 28; hidden in details 0 of 8; omitted 1 of 51.
11. Template: five lines (Root cause, Mechanism, Details, Effect, Affected), ~180 words, no labels/odds/hedges.
12. On the latest 29 faults the template alone adds an estimated 10 passes (v1 +7, v2 +3).
13. Passes 22/24/21/21 -> 24/25/25/24 (v2 Jev / v2 Dec / v1 Jev / v1 Dec); 18 failures need better picks or evidence.
14. Main risk: naming both kinds when the GT names the Deployment (untested).
15. Check the template on Lite plus auth_miss and secret_rotation before building on it.

## 1. How the judge reads a report (facts from code)

- It sees two texts only: ground truth `[fault_spec] component=<X>; namespace=<ns> || <prose>` and our report.
  The checklist hints mention `fault_mechanism`, `injector_method`, `parameters`, but those fields do not exist,
  so the prose is the whole answer key.
- System prompt: answer "based ONLY on what is explicitly stated", "Do NOT infer". Its in-context D3 example marks
  "frontend, cart, and recommendation services are all failing because of a missing env var on the frontend" as
  D3-Q1 No (victims written as failing = over-attribution).
- 9 Yes/No items, pass = at least 7 Yes. A report can lose at most 2 items.
- Same-text regrades flip one item about 8% of the time (eval-methodology.md). One-item differences are noise.

## 2. Item by item: what earns or loses each checklist item

Yes counts per group: v1 orig / v2 orig / v2 rerender (n = 157 / 158 / 39).

| Item | Yes | Earns it (evidence) | Loses it (evidence) |
|---|---|---|---|
| D1-Q1 same origin | 126 / 126 / 35 | Subject = object holding the bad value. CoreDNS ConfigMap as subject 20/20; webhook config, ResourceQuota, ClusterRole 42/42; NetworkPolicy 14/14 (GT bare `recommendation`); Kafka topic 6/6; caller-callee path 7/7. Service named first when GT is service/X 20/20 | Wrong pick (most of 67 No's). Kind mismatch: "Deployment X" alone when GT is service/X, Yes in only 2 of 15 (valkey-cart, url-shorten-mongodb), and both Yes arms named the Service elsewhere |
| D1-Q2 origin vs cascade | 123 / 133 / 37 | One root-cause label | A second "Root cause component" label on a victim: v1 DNS arms 0 of 8. Picking a victim (cart, rate, url-shorten-service) |
| D1-Q3 no healthy origin | 114 / 131 / 37 | Same | Same as D1-Q2, plus "Root cause component: Deployment X" when X's Service holds the fault (ITP, pod-selection), Yes only 11 of 18. "`Y` cannot be ruled out" lines, No in 4 of 5 |
| D2-Q1 mechanism | 134 / 110 / 31 | Mechanism words anywhere in the report: generic "X was changed recently and breaks Y" plus a details line with the mechanism words got 46/46. The origin's own error line naming the failure: v1 auth_miss quotes "Cannot read certificate file" 4/4, v2 without it 0/4 | "Mechanism: not established" (Yes 2 of 9). Wrong category label (liveness "code bug"). Missing part of a two-part story: search_rate trigger plus retry loop 0/12; edge regex backtracking 0/12; unschedulable second fault (v2 2 of 6) |
| D2-Q2 concrete values | 127 / 117 / 38 | The GT's mutated value appears: 239 of 243 right-origin arms Yes | Value absent: Yes 1 of 28. The judge rejects symptoms as details ("bind error", "paused offset 20", "HTTP 503 is a symptom, not a mutated setting"). Uncollected values: probe timing, hostPort 9100, sidecar port |
| D2-Q3 no wrong type | 130 / 140 / 38 | No label line: right-origin No in only 1 of 68 | "Fault type:" line on right-origin arms: No 10 of 219, and 7 of those 10 quote the label ("resource limits", "code bug"). The label helped D2-Q1 only 3 times |
| D3-Q1 no over-blame | 139 / 133 / 32 | Victims written as "X fails when calling this component (error class, count)": 4/4 Yes even when GT does not name X | A second root-cause label (9). "breaks deployment/X" or "abnormal on its own" for a healthy X (7; pod-selection "breaks deployment/frontend, deployment/search" 4). A victim inside "Observed impact" (2) or "fails as a result" (1 of 4). "cannot be ruled out" (4) |
| D3-Q2 all affected | 121 / 115 / 29 | GT-named victim or scope in the impact/scope line 28/28 (DNS social names caller compose-post-service 8/8) | The most common right-origin loss (61). Scope only inside a details line while "Observed impact" lists one Deployment: 0/8 (webhook "CREATE pods"). Absent: Yes 1 of 51 (checkout 9/9 lost, DNS astronomy callers 9/9, node-exporter 8/8, "other noncompliant workloads" 14/14, "all pod CREATEs" 14/14, six MongoDB deployments 2/2) |
| D3-Q3 impact matches | 139 / 126 / 34 | Origin state + what callers see (CrashLoop, 0 endpoints, timeouts) | Impact that contradicts the GT story: env shadowing 0/12 (OOMKilled reported, GT says Running and Ready). "breaks deployment/recommendation" + "Observed impact: deployment recommendation" for a healthy workload: No in 5 of 6 v2 ITP arms |

Facts worth stating plainly.
- Wrong-origin arms (83) lose almost everything (D1-Q3 72, D1-Q1 67, D1-Q2 61, D2-Q1 47). The report cannot save a
  wrong pick. Its job is to stop losing items on right picks and on right evidence framed wrongly.
- Right-origin arms lost 166 items. D3-Q2 is 61 of them (37%).
- Length barely matters. Mean score is 92-94 in every word-count bucket. D3-Q1 losses were 4 of 21 above 280 words
  against 1 of 43 below 120 (small n).
- The judge never cited a probability, "Classification:" or confidence line as evidence for a Yes. Those lines
  only add risk.

The rerender experiment (v2 reports rewritten in v1's style, 39 arms) changed pass/fail 0 times. 35 passed before
and after, and the mean moved -0.9 points.
- Two arms went up. In auth_miss, moving the subject from the ConfigMap to the workload took a0 from 44 to 55 and
  a1 from 33 to 55, gaining D1-Q3 (and D3-Q1 on a1).
- D1-Q1 and D2-Q1 were still lost there. The Service was not named, and the mongod "cannot read certificate" line
  was not included.
- Four arms went down (ITP 100 to 77, pod-selection 100 to 89, DNS social x2 100 to 89). Each loss came from moving
  "How it fails: X was changed recently and breaks deployment/Y" or "abnormal on its own" to line 2-3.
- Lesson: v1's style is not the gain. The gain is the subject choice. The loss is blame verbs near the top.

## 3. Which object does the ground truth name? A general rule

Fact: the GT names the changed object in some problems (CoreDNS ConfigMap, webhook config, ResourceQuota,
ClusterRole, `configmap/rpc`, Kafka topic). In others it names the component the change acts on (owned Secret,
`deployment/product-catalog`; NetworkPolicy, bare `recommendation`; datastore runtime, `service/valkey-cart`).
No single fixed rule matched the graded data. v2's "always the outside object" lost auth_miss. v1's "always the
workload" lost DNS, Kafka and ITP points.

### 3.1 Evidence for the rule

| Report shape | GT | D1-Q1 / Q2 / Q3 | Pass |
|---|---|---|---|
| Subject = shared or outside object, workload named as acted-on (v1 "Root cause object: X, acting on Deployment Y"; v2 "Root cause: X" + "acts on Y") | that object (CoreDNS, webhook, quota, ClusterRole) | 62/62 all three | 62/62 |
| Same, NetworkPolicy selecting one workload | bare component name | 14/14 | 14/14 |
| "Root cause component: Deployment X" + "Fault object: ConfigMap coredns" | configmap/coredns | 8/8, 0/8, 0/8 | 0/8 |
| "Root cause component: Deployment X" + "Fault object: Service X" | service/X | 18/18, 18/18, 11/18 | 18/18 |
| "Root cause component: Deployment X" + "Fault object: Secret (read only by X)" | deployment/X | 5/5 all | 5/5 |
| "Root cause: configmap X (owned by workload X)" | service/X (auth_miss) | 0/2, 2/2, 0/2 | 0/2 |
| "Root cause: Service X" | service/X | 20/20 all | 20/20 |
| "Deployment X" only, no Service in the root-cause line | service/X | 2/15 | depends on D2 |

### 3.2 Rule (general; names only kinds and fields)

The subject of the root-cause sentence is the object that holds the bad value or bad state. Apply the first match.

1. **A call path** (timeout, retry or capacity settings on two sides) is written "the call path from `A` to
   `B`". Both sides' settings go in the same sentence.
2. **A data object** (topic, queue, table, record) holds the bad input. Name the data object, and name the
   consumer as blocked.
3. **A cluster-scoped object, an object outside the app namespace, or a namespace policy object** (webhook config,
   ClusterRole, PriorityClass, node, kube-system ConfigMap, ResourceQuota, LimitRange) is the subject. The
   workloads it acts on go in the same sentence after "acting on".
4. **A field on a Service** (selector, ports, traffic policy) makes the Service the subject.
5. **A field on a workload's own spec or pod template** makes that workload the subject. When the same change sits
   on several workloads, name all of them as one subject.
6. **An app-namespace carrier** (ConfigMap, Secret, NetworkPolicy, or one entry in a shared flag or config file)
   depends on how many components use the changed part.
   - If it is used by, selects, or has its changed entry for exactly one component, that component is the subject.
     The carrier appears in the same sentence as the cause ("its ConfigMap `x` sets ...").
   - If several components use it and the change reaches several, the carrier is the subject (as with `configmap/rpc`).
7. **No spec change** (memory exhausted, auth set at runtime, stale credentials) makes the server holding the state
   the subject. A load source that drives it is named in the same sentence as the trigger.

Kind wording. When the subject is a component with both a Service and a workload of the same name (rules 6 and 7),
name both in the subject phrase, Service first: "`url-shorten-mongodb` (Service `url-shorten-mongodb`,
Deployment `url-shorten-mongodb`, namespace `social-network`)". Under rules 4 and 5, lead with the object that
holds the field and add no second kind.

Wording rules for the two-object sentence:
- The words "root cause" appear once, on line 1.
- The other object is joined by a relation word: "its ConfigMap", "acting on", "selects", "isolates",
  "intercepts", "rejects", "is driven by".
- It never gets its own "root cause", "fault object" or "origin" label.

Opinion. The rule matches all 29 studied problems' GT. That includes `configmap/rpc` (shared, rule 6) and the
landscape note that flag entries map to the service (rule 6, entry level). It is untested on unseen faults. The
riskiest part is naming both kinds when the GT names the Deployment (rules 6 and 7). No graded arm tests that shape.

## 4. The template (exact)

Five labelled lines, in this order. Target 180 words or fewer, hard cap 250. Line 1 is 60 words or fewer. Other
lines are at most 2 sentences each. Each line is left out when it has no facts, except lines 1 and 2.

    Root cause: <subject phrase per section 3>. <what is wrong, with the bad value and the good value>, so <direct
    effect on the broken component>.
    Mechanism: <family words for how the bad value causes the failure>; <one quoted error line from the origin
    that states the failure, if any>.
    Details: <Kind name field: old -> new (changed N s before the first symptom)>; <up to 3 more code-found facts on
    the origin>.
    Effect: <state of the origin's pods in plain status words, saying "Running and Ready" when true>; <what callers
    see, by error class>.
    Affected (symptoms only, not causes): <caller>: <error class> calling <origin> (<count>, still occurring);
    <up to 3>. | or, for a namespace or cluster object: <selection rule> plus <observed and at-risk workloads>.

Line 1 (Root cause)
- Subject from section 3.
- The predicate uses Kubernetes or protocol family words built from the field or kind, never from a fault name.
  Examples are "liveness probe", "selector", "env var", "image", "hostPort", "NetworkPolicy denies all ingress and
  egress", "admission webhook rewrites", "ResourceQuota requires", "TLS certificate", "requirepass/NOAUTH",
  "NXDOMAIN", "OOMKilled at memory limit", "per-attempt timeout x retries".
- A lint check keeps app, service and problem names out of this phrase list.
- A two-party conflict names both parties and the shared value: "container `sidecar` binds port 5000, the same
  port as container `hotel-reserv-frontend`"; "hostPort 9100, already held on every node by DaemonSet
  `prometheus-node-exporter`".

Line 2 (Mechanism)
- Never write "not established". If no mechanism fact was found, describe the origin's own observed failure
  instead ("its container exits with ...").
- Quote at most one origin error line and one caller line, 160 characters or fewer, with timestamps, JSON keys and
  pod hashes stripped. Only quote a line that states the failure in words.
- If two independent mismatches were found on the origin (env port and nodeSelector), both go here and in Details.
- A trigger with an amplifier gets both parts in one sentence: "a burst filled <queue>; <caller> retries <N> times
  with a <T> deadline, so load stays above capacity".

Line 3 (Details)
- Write `<field>: <old> -> <new>` when both values are known.
- Write `<field> is <new>` when only the new value is known.
- Write `<field> removed (was <old>)` for a deletion.
- Write `observed: <value>` for runtime state (for example, OOMKilled at 64Mi).
- Identical changes on several objects become one entry naming all of them.
- Values are cut to 120 characters. A changed regex or command is kept, because the judge credits it under D2-Q2.
- When the origin's latest revision changed several fields, list every changed field, up to 4. This alone would
  have given v1 + Jev D2-Q2 on edge_request_filter.

Line 4 (Effect)
- Say whether the origin's pods are Running and Ready, or give their status (CrashLoopBackOff, Pending, 0 of N
  ready, 0 endpoints).
- Then say what callers see, by error class (timeouts, connection refused, NXDOMAIN, NOAUTH, rejected at admission).
- "breaks", "fails" and "is broken" are only for components with their own observed failure. A healthy component
  the cause acts on gets "selects", "routes to" or "acts on".

Line 5 (Affected)
- List callers one hop away whose own error lines name the origin or its Service, at most 3, ordered by error count.
- If none are observed and the origin has 0 ready endpoints, list up to 3 components configured to call it (their
  env or config names its Service), marked "configured to call it". This fallback is opinion and untested.
- Never list second-hop components. Never list a component that is broken but not linked to the origin.
- Scope phrase for namespace or cluster objects. State the selection rule as a fact, then list who is affected.
  - Webhook example: "intercepts every pod CREATE in namespace `social-network`; observed rewritten: nginx-thrift".
  - Quota example: "applies to every workload in `hotel-reservation`; 19 of 19 Deployments declare no memory and
    are rejected on their next pod creation; observed: search".
- The other party in a conflict goes in line 1, because the GT treats it as contributing.

Leave out
- The "Fault type:" or category line.
- "Classification", probabilities, "Confidence: low" and "cannot be ruled out" runner-ups.
- "Observed impact:" lists that mix the origin with victims.
- "Key evidence", "Fault object" and "Root cause component" labels on a second object.
- Evidence dumps (warning-event lists, alert names, image and limit lists, previous-run log tails), pod hashes,
  UIDs and timestamps.
- Generic "X was changed recently and breaks Y" sentences.

## 5. The template filled in for five non-sealed faults (facts from our snapshots and reports)

**5.1 service_dns_resolution_failure_social_network (lite6). Rule 3, outside object as subject, plus callers.**

    Root cause: ConfigMap `coredns` in namespace `kube-system` (the cluster DNS configuration) has a template rule
    that answers NXDOMAIN for `user-service.social-network.svc.cluster.local`, so in-cluster lookups of Service
    `user-service` in namespace `social-network` fail.
    Mechanism: DNS resolution of the Service name fails, so clients cannot connect to user-service even though it
    is listening; caller log "getaddrinfo() <Host: user-service Port: 9090> Temporary failure in name resolution".
    Details: ConfigMap kube-system/coredns data.Corefile: added `template ANY ANY user-service.social-network.svc.cluster.local
    { match "^user-service.social-network.svc.cluster.local\.$"; rcode NXDOMAIN; fallthrough }` (changed 120 s
    before the first symptom).
    Effect: Deployment `user-service` shows no failure of its own; callers cannot resolve it and time out.
    Affected (symptoms only, not causes): Deployment `compose-post-service`: DNS resolution failure calling
    user-service (27 lines) and timeouts (25), still occurring.

**5.2 auth_miss_mongodb (held6). Rule 6, owned ConfigMap, so the component is the subject with both kinds.**

    Root cause: the MongoDB server `url-shorten-mongodb` (Service `url-shorten-mongodb`, Deployment
    `url-shorten-mongodb`, namespace `social-network`) requires TLS with a certificate file that does not exist:
    its ConfigMap `url-shorten-mongodb` sets mongod.conf `net.tls.mode` to `requireTLS` with `certificateKeyFile`
    `/etc/tls/tls.pem`, so mongod cannot set up TLS and exits.
    Mechanism: invalid TLS certificate setup; mongod logs "Cannot read certificate file /etc/tls/tls.pem: No such
    file or directory" and "InvalidSSLConfiguration: Can not set up PEM key file", so database clients cannot
    complete a TLS connection.
    Details: ConfigMap url-shorten-mongodb key mongod.conf: net.tls.mode is requireTLS, net.tls.certificateKeyFile
    is /etc/tls/tls.pem (changed 2 s before the first symptom).
    Effect: 0 of 1 replicas ready, container in CrashLoopBackOff (4 restarts); Service url-shorten-mongodb has 0
    ready endpoints, so requests on database-dependent paths fail.
    Affected (symptoms only, not causes): Deployment `url-shorten-service` (database client): "Failed to upload
    shortened urls from Mongo", still occurring.

**5.3 update_incompatible_correlated (tgt). Rule 5, same change on N workloads, one subject.**

    Root cause: Deployments `mongodb-geo`, `mongodb-profile`, `mongodb-rate`, `mongodb-recommendation`,
    `mongodb-reservation` and `mongodb-user` (namespace `hotel-reservation`) were all updated at the same time to
    an incompatible MongoDB image, mongo:4.4.6 -> mongo:8.0.14-rc0, so none of the six databases can start on its
    existing data.
    Mechanism: incompatible image version upgrade; mongod exits with "Wrong mongod version ... UPGRADE PROBLEM:
    Found an invalid featureCompatibilityVersion document" (exit code 62).
    Details: 6 Deployments mongodb-{geo, profile, rate, recommendation, reservation, user} container image:
    mongo:4.4.6 -> mongo:8.0.14-rc0 (all 126 s ago, before the first symptom).
    Effect: each of the six has 0 of 1 replicas ready and its container in CrashLoopBackOff; their Services have
    no ready endpoints, so persistence fails across the services that use them.

The Affected line is left out here. `rate` also crash-loops, but no error or config link ties it to a database in
the snapshot (forensics 2.1), so the rule does not list it.

**5.4 internal_traffic_policy_local_astronomy_shop (lite6). Rule 4, Service field, workload stays healthy.**

    Root cause: Service `recommendation` in namespace `astronomy-shop` has spec.internalTrafficPolicy Local, so
    kube-proxy sends in-cluster traffic only to recommendation pods on the caller's own node; its only ready
    endpoint is on node kind-worker, so callers on other nodes get no endpoint.
    Mechanism: Service traffic policy limits endpoints to the caller's node; calls from other nodes find no local
    endpoint and hang until the caller's own timeout.
    Details: Service recommendation spec.internalTrafficPolicy is Local (the default is Cluster), written 65 s
    before the first symptom; ready endpoints only on kind-worker.
    Effect: Deployment `recommendation` pods are Running and Ready and its endpoints exist; callers on kind-worker2
    get no response.
    Affected (symptoms only, not causes): Deployment `frontend` (on kind-worker2): its calls to recommendation
    find no local endpoint.

**5.5 liveness_probe_too_aggressive_social_network (held5). Rule 5, values, and no category label.**

    Root cause: Deployment `aux-service` in namespace `social-network` has an aggressive liveness probe on
    container `aux-service-container`: httpGet /health:8080 with no initialDelaySeconds (0), periodSeconds 1,
    failureThreshold 1, timeoutSeconds 1, so a single failed check during startup kills the container.
    Mechanism: liveness probe misconfiguration; the app reports healthy only after about 15 s of startup, but the
    probe allows no delay and one failure, so the kubelet restarts the container before it is ready.
    Details: livenessProbe initialDelaySeconds 0 (unset), periodSeconds 1, failureThreshold 1;
    terminationGracePeriodSeconds not collected yet.
    Effect: 0 of 1 replicas ready; container in CrashLoopBackOff (5 restarts) with Unhealthy probe events;
    Service aux-service has 0 ready endpoints.

The probe values are in v1's investigate detail (trace), but `describe_probe` drops them. Rendering them is a
fact-rendering fix the template needs. terminationGracePeriodSeconds needs collecting.

## 6. Estimated effect on existing graded runs, and risks

Method. I took the latest run per studied fault (29 faults x 4 arms = 116 arms, the forensics main table). I kept
each arm's pick and the facts already in its snapshot or investigate detail. I re-answered each item by hand, using
the rates in section 2. "R" is the template alone. "R+F" adds two fact-rendering fixes: probe timing, and duplicate
container ports. This is reasoning, not a judge run.

Pass counts (of 29). Now: v2 Jev 22, v2 Dec 24, v1 Jev 21, v1 Dec 21. R: 24 / 25 / 25 / 24. R+F gives the same
passes with higher scores.

Ten expected pass flips:
- auth_miss v2 Jev 44 -> ~100 and v2 Dec 33 -> ~100 (rule 6 subject with both kinds, mongod error line, client
  named).
- liveness v2 Jev and v1 Jev 67 -> 78. Dropping the "code bug" label regains D2-Q3; with probe timing they reach
  ~100.
- DNS astronomy v1 Jev and v1 Dec 55 -> 89-100 (CoreDNS as subject; configured callers for D3-Q2).
- Kafka v1 Jev 67 -> 100 and v1 Dec 56 -> 89 (the topic from v1's own blocked-input facts as subject).
- DNS social v1 Dec 67 -> 100 (subject plus caller).
- edge v1 Jev 67 -> 78. All changed revision fields are listed, so the regex earns D2-Q2. Medium confidence.

Estimated Yes counts per item (of 116):

| Item | Now | Template (R) | R+F | Main contributors |
|---|---|---|---|---|
| D1-Q1 | 94 | 100 | 100 | DNS, Kafka, auth_miss |
| D1-Q2 | 95 | 100 | 100 | DNS, Kafka |
| D1-Q3 | 90 | 100 | 100 | DNS, Kafka, ITP v1, auth_miss |
| D2-Q1 | 92 | 93 | 96 | auth_miss; liveness needs probe facts |
| D2-Q2 | 91 | 92 | 99 | edge; R+F also adds sidecar ports x4 and liveness |
| D2-Q3 | 99 | 103 | 103 | no label |
| D3-Q1 | 98 | 106 | 106 | no second label, no "breaks" for healthy components |
| D3-Q2 | 85 | 103 | 103 | webhook and quota scope (8), DNS callers (5), six MongoDB (2), auth_miss client (3) |
| D3-Q3 | 98 | 102 | 102 | ITP, missing_env, auth_miss |

Not fixed by any report, 18 arms.
- valkey_memory x4 (pick is the Job).
- valkey_auth x4 (requirepass never collected; Dec and v1 Jev may gain D1-Q1 but stay at 56-67).
- secret_rotation x3 (wrong pick).
- search_rate v1 x2 (v1 cannot express a call path).
- update_incompatible v2 x2 (victim picked).
- missing_env Jev x2 (victim or observability picked).
- liveness v1 Dec x1 (leftover CoreDNS).
- port_conflict stays at 78 until hostPort and node-exporter facts are collected.

Interpretation. The template is worth about +2 to +4 passes per arm type on this set. It helps v1 most, because
v1's failures there are framing failures. Since the redesign starts from v1 (STRATEGY section 3), this is the
baseline gain.

Risks (opinion, ranked by likelihood x impact)
1. **Both kinds when the GT names the Deployment.** Rules 6 and 7 write "Service X, Deployment X". No graded arm
   tests that against a deployment/X GT. Check on Lite secret_rotation (GT deployment) and sample-A auth_miss
   (GT service) before relying on it.
2. **Callers read as blame.** The judge's own example punishes listing victims as "failing". Mitigations are one
   hop only, observed errors first, at most 3, the label "symptoms only, not causes", and the error-class wording
   that scored 4/4. The configured-caller fallback is untested.
3. **The ownership rule picks the wrong subject** when the GT names an owned carrier itself. None of the 29 studied
   GTs do, but unseen faults may.
4. **No label means D2-Q1 depends on mechanism words.** In 3 judgments the label was the only mechanism evidence.
   The field phrase list must cover each field we can report.
5. **The phrase list becomes fault stories.** It must be keyed by field path, kind and error class only, with the
   lint check from STRATEGY item 7.
6. **Scope phrases over-scope.** State the selection rule as a fact ("every pod CREATE in namespace X"). Do not
   claim every selected workload is broken.
7. **Wording moves can cost one item even when content is the same.** The rerender lost 11-23 points on four arms
   for that reason, and judge noise is about 8% per text. Arms sitting at 78 stay fragile.
8. **The estimates come from 29 studied faults with hand-coded answers.** True gains on Unseen will be smaller,
   because most Unseen failures will be pick or evidence failures the report cannot fix.

## 7. What the report builder needs as input (for stage 1)

The origin and its role (rule 1-7 from section 3); changed objects with field, old, new and timing (including
identical twins on other objects); the origin's status and own error lines; callers with error class and counts
(from `referenced_by_errors_from`, `errors_point_to`, `_impact_lines`); configured callers; selection-rule facts
for namespace and cluster objects (webhook rules and namespaceSelector, quota scope, workloads lacking the
required field); conflict parties. Nothing else from the model goes into the text, except which origin and which
key fact were chosen.

Facts versus opinions. Every count in sections 2 and 3.1 is read from graded files. Section 3.2's rule, the
template and every number in section 6 are my design and estimates.
