# Review: does the new v2 keep every v1 strength, and make it stronger? (2026-10-19)

Status: DONE (first full version). Read-only review of `STRATEGY.md` against v1 (`~/sregym/SREGym-fixes/clients/jev_diag/`,
unchanged since 6400cd46) and the run files in `runs-index.tsv`.

Sources. README, STRATEGY, v1-architecture, forensics, v2-audit, decision-models (sections 2-4), v1 code, and the run
files (graded arms, requests, snapshots, traces) of `lite5/lite6/held*/tgt` plus older labels where stated. Numbers below
come from small scripts over those files (kept in the session scratchpad, not in this folder). The judge checklist is
`sregym/conductor/oracles/llm_as_a_judge/rca_checklists.yaml`.

Sealed set. `runs-index.tsv` has 0 rows for the 40 ids in `UNSEEN-SEALED.txt` (checked by exact id match before reading
any row). No file in `sealed/` and no problem file, injector or run of a sealed problem was opened.

Words. "Fact" = read from code or run files. "Opinion" = my judgment, marked. Scores are judge composites x100,
pass >= 70. "Jev" = jev-1.13, "Dec" = gpt-6-luna-decisions. "Arm" = one pipeline + one model on one snapshot.

---------------------------------------------------------------------------------------------------------------------
## 0. Short version

1. **Where v1's strength actually lives (fact).** In 80 of 86 graded v1 arms (lite5, lite6, held*, tgt) v1 concluded on
   the triage's top workload. Runs that stopped after 2 calls passed 57 of 76; runs that walked further passed 3 of 10.
   So v1 is, in practice, "one whole-application triage, then one confirm-and-quote step". The triage works because
   code feeds it neutral detector facts, dated changes ranked against symptom onset, and a short written prior; the
   report then quotes the chosen fact word for word. On the same 43 snapshots per model, v1's D2-Q1 (right mechanism)
   rate is 0.86 (Jev) and 0.88 (Dec) against v2's 0.70 and 0.77.
2. **STRATEGY keeps most of this by starting from a full copy of v1 (stage 1). The danger is stage 3.** Its "one general
   decision core" (code builds a graph, computes "which symptoms it can reach", asks a 2-7 option slate twice) replaces
   exactly the step where v1's strength lives, the whole-snapshot triage with its prior. v2 already showed how this goes
   wrong: a code shortlist dropped 2 of 6 true options, a focused state hid the rest of the cluster, and a "wide impact"
   preference made victims win (dependency winners passed 3 of 8).
3. **Strengths the first analysis missed or filed as bugs.**
   - Workload first, cluster object second. A leftover CoreDNS change from an earlier problem sits in 32 of 81 saved
     snapshots. v1 fell for it in 2 of 64 arms. When triage put most weight on `other` but the top workload was
     examined first, v1 passed (held5_readiness Jev 100 with `other` at 0.60; held5_liveness Jev 67 vs the Dec arm that
     went to the cluster node and scored 0). STRATEGY lists this ordering as a bug to fix. Fixing it by reordering would
     lose this protection. The DNS faults need a comparison, not a reorder.
   - Linked fault objects. Five webhook configurations were all changed 11 s before onset in
     lite6_mutating_webhook; v1 named the right one because it picks the object linked to the examined workload.
   - Conditional telemetry prior. The otel collector (only a harness restart) was triage top-1 in 3 v1 arms and was
     never concluded; jaeger (own symptoms and a config defect) was named in all 7 duplicate-PVC social arms that
     concluded on a workload, 100 each. v2 lost this and picked otel in tgt_missing_env (11).
   - Redundant detectors. In lite6_secret_rotation the changes came after the estimated onset (so the change rule did
     not help), but the stale-read and login-rejection detectors still put 0.75 / 0.85 on the right component.
   - The quoted log lines. held6_auth_miss passed D2 on the mongod lines v1 printed ("Cannot read certificate file");
     v2 had the same evidence and lost D2.
4. **Top risks, ranked by likelihood x impact:** (R1) slate replaces whole-snapshot triage and its prior; (R2) a "reach"
   fact rewards wide-impact candidates (victims, shared infra, telemetry, leftover CoreDNS); (R3) reordering cluster
   objects; (R4) metrics/traces/logs crowd the token budget and shift the onset; (R5) the generality lint strips
   technology tables v1 depends on; (R6) retagging evidence kinds silently changes triage. Section 2 has the details.
5. **Every strength can get measurably better without fault rules**, and each has a guard that runs on Lite, most of
   them offline at zero model cost by replaying the saved raw kubectl bundles (`replay.py --raw`). Section 3.

---------------------------------------------------------------------------------------------------------------------
## 1. Strength inventory, status in STRATEGY, and how to improve each

Status key. **Kept** = STRATEGY keeps it as is. **Improved** = STRATEGY makes it stronger. **At risk** = the design
could lose it without anyone noticing. Guard ids (G..) refer to section 3.

| # | Strength | Main code | STRATEGY status | Guards |
|---|---|---|---|---|
| S1 | Whole-application triage in one ask | classifier.build_component_questions, tree.triage | **At risk** (stage 3) | G9, G15, G19 |
| S2 | The written triage prior (its wording) | classifier.py 248-299 | **At risk** (stage 3, lint, "rules into code") | G10, G9 |
| S3 | Neutral cross-object detector library | checks.py, collector attach_*, derive.py | Kept + improved | G1, G3 |
| S4 | Change detection from the cluster's own records | changes.py, collector 2112-2190 | Improved, with a noise risk | G2 |
| S5 | Change-vs-onset ranking, onset from active symptoms only | changes.rank_changes, estimate_symptom_onset | Kept in name; at risk from new onset sources | G2, G11 |
| S6 | Error recency by each signature's own rhythm, warm-up cut, telemetry split, trend | collector 1180-1275, derive.classify_logs, trend.py | Not mentioned; at risk from Loki/Jaeger | G4 |
| S7 | Victim reasoning: dependency judged by its own state | investigate.dependency_state, tree.VERDICTS, tree.fallback | Kept in concept; at risk from graph gaps | G13, G9 |
| S8 | Server login rejections point at clients, scored | derive.server_login_rejections, tree.other_side, pair_node | Not mentioned; at risk (lint, retagging) | G13, G18 |
| S9 | Conditional telemetry prior | derive.OBSERVABILITY_RE/TELEMETRY_RE, tree.initial_queue demote, triage rule 1 and 5 | Not mentioned; **at risk** | G12, G18 |
| S10 | Workload first, cluster object second; linked fault object; carrier lead line | tree.initial_queue 482-486, classifier.select_fault_object, finding_linked, CARRIER_KINDS | Called a bug; **at risk** | G11, G8 |
| S11 | Model picks among code-made options; no story must fit | tree, classifier | Kept ("facts, never verdicts") | G19 |
| S12 | Verbatim key fact with concrete values; evidence order | classifier.build_diagnosis_text, tree.detail_evidence | Improved (bad and good value); at risk if the origin sentence is templated | G7 |
| S13 | Generous report sections | classifier.py 877-925 | Partly kept; at risk from "shape for the judge" | G8 |
| S14 | Dual naming: workload plus fault object | classifier.build_diagnosis_text, tree.fault_object | Kept and improved | G8 |
| S15 | Few calls, cheap, fast | tree.diagnose early stop | **At risk** (asks twice, tie-breaks, more evidence) | G16 |
| S16 | Stable pass/fail across reruns | whole design | At risk (more steps, live tests) | G17 |
| S17 | Ordered fallback chain, always answers | tree.fallback, chain_characterization | Not mentioned | G6 |
| S18 | Priority-based state trimming | collector._trim_steps, _shrink_remaining, fit_state_to_budget | Not mentioned; **at risk** from new evidence | G5 |
| S19 | Fail-soft, replayable, read-only collection | collector.kubectl_items, attach_logs, RawRecorder, replay.py, derive.post_process | At risk from new sources on the critical path | G6 |

### S1. Whole-application triage in one ask

What it is. One Choice over every workload (19-28 in these apps) plus `other`, with each option keyed by the component id
that is also its key in the state (`components["deployment/x"]`). Asked together with `fault_object_kind` (10 kinds).

Evidence (fact).
- 80 of 86 graded v1 arms concluded on the triage's top workload (scratch count over lite5/lite6/held*/tgt).
- Triage was right 84% (Jev) and 79% (Dec) over 80 asks with 20-29 options (decision-models 2.3). Many options were not a
  problem by themselves (decision-models 2.7).
- Held-out faults it carried: wrong_service_selector 100 in all 6 v1 arms; duplicate_pvc_hotel 100 (x4);
  readiness_probe 100 (x4); sidecar_port 89-100; incorrect_image 89 (x4); auth_miss 77-100; update_incompatible 89 (x2).
- It sees the whole cluster at once. In tgt_update_incompatible v1 triage put 0.74 on mongodb-geo while v2's shortlist cut
  two of the six bumped databases and its focused state hid them (forensics 2.1); v1 89/89, v2 0/11.

STRATEGY status: **at risk.** Section 3.4 says the model "answers short slate questions over 2-7 options". If the slate is
the first thing the model sees, code must pick the 2-7 candidates, so candidate recall becomes a code problem, which is
exactly where v2 failed (TOP_K cut, focused state, fitted builders filling slots). STRATEGY measures recall (3.7), which is
good, but does not say the triage stays.

Make it better (general, measurable).
- Keep the whole-application triage as step 1 and use the slate only for the final call among triage's top-k plus every
  outside object code found linked to an unhealthy component (decision-models best practice 5, "rank then recheck").
  Target: top-3 recall of the true origin >= 95% on Lite, final pick accuracy >= v1's per model.
- Keep options keyed by object id and pointing into the state; use neutral shuffled labels only on the final slate.
- Ask the triage twice in two orders only when its top-2 gap is small, and use agreement as the signal
  (decision-models 2.4: agreement 85-88% right, disagreement 55-72%).

### S2. The written triage prior

What it is. The triage question opens with "Exactly one fault was injected into this Kubernetes application after it was
deployed and healthy". Six ordered rules follow (prefer `change` consistent with the symptoms; otherwise `configuration`;
otherwise `pointed_at` or `own_failure_logs`; symptoms and error-only logs never select on their own; a component whose only
problem is failed calls is a victim; a telemetry change counts only if application errors name it; pick `other` when a
cluster finding explains things better). A glossary explains each state field (classifier.py 248-299).

Evidence (fact).
- Rule 2 ("configuration") did half the work. In these runs the top workload had no `change` kind but had
  `configuration` in 13 faults (duplicate_pvc hotel and social, readiness, sidecar, service_port, liveness,
  auth_miss held5, wrong_service_selector, cronjob, finalizer, namespace_memory, rolling_update, valkey_memory). All but
  valkey_memory and liveness passed with both models.
- Rule 1 ("change") carried incorrect_image (1.00 triage, 0 s before onset), unschedulable (0.95-0.99), edge (0.98-1.00),
  env_shadowing (0.98-1.00), update_incompatible (0.74 / 0.36), internal_traffic (0.99-1.00).
- Rule 5's telemetry clause: see S9.
- Rule 4 ("symptoms never select on their own") is also what made tgt_missing_env fail with Jev: the frontend had only
  `error_logs_only` because its env removal never became a change record (v1-architecture 4.5). The rule is right; the
  missing fact was the bug.

STRATEGY status: **at risk** in three ways. (a) The new core's "neutral facts" (reach, onset order, changed, own symptoms,
parent explains it) are not the same as v1's ordered prior; nothing in STRATEGY says the prior text survives. (b)
decision-models best practice 4 recommends moving rules like rule 4 into code filters; a code filter is brittle where the
model's soft reading is not (rule 1 says "when the change is consistent with the abnormal signals", which code cannot
judge). (c) The lint (S9, S8) may delete the vocabulary the rules refer to.

Make it better.
- Keep the prior as an explicit, versioned block. Rewrite it as single-hop sentences without double negatives (the
  vendor warns about "unless" and "never ... on their own"), and test the rewrite as an A/B on frozen Lite states with 3
  models before adopting it (G10). Target: no Lite fault lost, triage accuracy equal or better per model.
- Give each rule a typed field to point at instead of string-tagged `evidence_kinds`: `changed_near_onset` (seconds),
  `config_defects` (list of detector facts), `named_by_errors_of` (callers, first-hop only), `own_failure_class`,
  `symptoms_only` (bool). The prior then applies literally and the tags stop depending on sentence wording (W4).
- Drop `fault_visible`; it was 1.0 in 160 of 160 asks (decision-models 2.6) and costs tokens.

### S3. Neutral cross-object detector library

What it is. Code compares objects and writes each mismatch as a neutral sentence with values: selector vs labels, Service
targetPort vs container ports, probe port vs declared ports (only for a not-ready container), env host:port vs the
Service's ports, internalTrafficPolicy=Local vs where clients run, RWO claim vs replicas and anti-affinity, quota required
fields vs containers, pod vs template plus the webhooks whose rules match, Secret/ConfigMap rewrite time vs container start
by read mode, duplicated env names, the same PVC or mount twice, finalizer plus role gap, CronJob jobs piling up, init
container stuck, job sidecar still running, `repeated_failures` with the tokens that never change.

Evidence (fact). The quoted key fact in every Lite pass came from a detector (list in G1), for example
"service frontend selects pods of 2 different workloads ... through selector {'service-route': 'frontend'}"
(wrong_pod_selection 100/100), "PVC jaeger-pvc is ReadWriteOnce ... 2 replicas ... anti-affinity" (dup_pvc social 100/100),
"container nginx-thrift limits.memory 16Mi, template 256Mi ... mutating webhooks whose rules and selectors match these pods:
gatekeeper-..." (89/89), "ResourceQuota memory-limit-quota requires memory on every pod and this workload's containers declare
none" (89/89), "readiness probe (httpGet HTTP :8080/healthz) targets port 8080; the container declares ports [5000] and is
not ready" (held5 readiness 100/100).

STRATEGY status: **kept** (stage 1 is a full copy) and **improved** (probe timing, termination grace, revision diffs). One
risk: the planned fix "evidence kinds tagged by string matching" changes which detector output counts as
`configuration`. Today "job has 1 active pod(s) and has not completed" (cronjob, 100/100) and "service X selects this
component but has 0 ready endpoints" are tagged `configuration` only because they match no marker. A stricter typing could
demote them to symptoms and change the triage on cronjob or selector faults.

Make it better.
- One registry of detectors with a typed output (subject object, related object, field, observed value, expected or
  previous value, relation) and one unit test per detector built from a saved Lite or corpus object. The English sentence
  is rendered from the typed record, so rewording never breaks downstream code.
- Add general detectors for facts v1 drops: probe timing (period, failureThreshold, initialDelay) next to the target;
  terminationGracePeriodSeconds; hostPort clashes between pods on one node (held5_service_port lost D2-Q2 on hostPort
  9100, v2-audit 6.4); resources vs observed use. Measure as "facts with a concrete value present for the true origin" on
  Lite.
- When retyping kinds, run G3: any component whose kind set changes on any Lite state is listed and reviewed.

### S4. Change detection from the cluster's own records

What it is. A change is a spec write >= 10 s after creation (managedFields, with the field paths of non-creator writers),
an object created >= 10 s after the objects it acts on, or a field-level pod-template revision diff (changes.py).

Evidence (fact). Dated changes near onset on the true component in the latest runs: incorrect_image (0 s before onset),
unschedulable (0 s), update_incompatible (all six databases 4 s), edge (51 s), env_shadowing (9 s), kafka (78 s),
internal_traffic (Service 65 s), namespace_memory (quota 1 s), auth_miss held6 (ConfigMap 2 s), network_policy (created
13 s after its targets).

STRATEGY status: **improved** (revision diffs become change signals, fixing tgt_missing_env Jev) with a **noise risk**. In
20 of the 45 recent snapshots (all Astronomy Shop) the otel collector carries a change shortly before onset, and in all 20
the only written field is `template.annotations.kubectl.kubernetes.io/restartedAt`. product-catalog's revision in
secret_rotation is also restartedAt plus pod-template-hash. If every revision diff becomes a change, restart-only
revisions become "changes near onset" too.

Make it better.
- Classify each change by content: "restart only" (restartedAt annotation, pod-template-hash) vs "spec change" (image,
  env, args, resources, probes, volumes, scheduling). Restart-only changes stay visible but never set
  `nearest_change_before_symptoms`.
- Group identical changes across workloads (same field, same old -> new value) into one change with a scope list. This
  fixes v1's D3-Q2 loss on update_incompatible ("omits mongodb-profile, ...") without a fault rule.
- Measure: on Lite, the nearest spec change before onset is on the true origin wherever v1 found it (G2).

### S5. Change-vs-onset ranking, onset from active symptoms only

What it is. The onset is the earliest still-active abnormality outside telemetry components (ongoing error signature,
not-ready since, last crash, Pending pod created, warning event first seen, alert active since). Changes before onset rank
first, nearest first; changes on telemetry objects never get the "nearest" flag; changes older than 1 h are dropped. The
signal text says "Ns before / after the first active symptom".

Evidence (fact).
- Leftover CoreDNS change from an earlier problem: present in 32 of 81 saved snapshots, 330-3350 s before onset. v1
  concluded it in 2 of 64 arms (held5_liveness Dec, rerun_duplicate_pvc Dec), both through the cluster node after the
  workload verdict fell under 0.6, never through triage.
- Weak spot: in lite6_secret_rotation the onset came from an alert that predates the injection, so the real changes are
  "22-29 s after the first active symptom". The other detectors still carried Jev to 100 (S8).

STRATEGY status: kept in name ("onset order" is one of the core's facts). **At risk** from item 3: metrics "before vs
after onset" and Loki history will produce earlier anomalies (baseline noise, old episodes), pulling the onset earlier and
pushing real changes "after onset", as already happened once with an alert.

Make it better.
- Compute onset per affected component as well as globally, and state both: "change at T; first symptom of the components
  it acts on at T+x". Rank by the per-component onset.
- Only active, sustained anomalies may set the onset (same recency rule as S6 for any new source).
- Give the cluster node the same timing fact as a field, so "changed 3350 s before the first symptom and acts on no
  unhealthy component" reads as history (G11).

### S6. Error recency, warm-up cut, telemetry split, trend

What it is. Each error signature is "ongoing" or "stopped" by its own median gap (stopped = silent > max(15 s, 3x gap);
single sightings 60 s); lines before a pod's first Ready (max 120 s) are dropped; crash-looping containers count as ongoing;
stopped errors never create pointers or own-failure signals; telemetry export failures are counted apart and never point
anywhere; a second light sample 45 s earlier adds "restarted N more time(s) in the last 49 s".

Evidence (fact, 45 snapshots of lite5/lite6/held*/tgt).
- 161 component instances (3.6 per run) had only stopped errors and so produced no pointer and no evidence kind.
- 44 component instances had warm-up error lines dropped; 50 had settled start-up history moved aside.
- All Social Network runs had 4-5 components with telemetry export errors kept out of pointers.
- Trend lines appeared on 24 component instances and are quoted in reports (held5_liveness "restarted 1 more time(s)
  in the last 49s"; the judge cites restarts under D3-Q3).
- Limit: lite6_kafka Jev quoted "record validation failed at offset=20" marked "(stopped, last seen 142s ago)". A
  blocked consumer can go quiet, so silence is not always recovery.

STRATEGY status: not mentioned, so **at risk** when Loki and Jaeger arrive. Loki returns longer history (warm-up and old
episodes); Jaeger error spans are a new error source. If they bypass the recency filter, old or start-up errors return as
pointers, which is the noise v1 removed.

Make it better.
- Put every error source (pod logs, Loki, Jaeger error spans, metric error rates) through one recency model: ongoing vs
  stopped by its own rhythm, warm-up cut by the pod's Ready time.
- Pair recency with progress: a signature that stopped while the component also stopped making progress (no new
  requests, consumer offset not moving, CPU flat) is "stalled", not "stopped". Metrics give this generally.
- Measure: pointers from stopped or warm-up lines = 0 on all Lite states (G4).

### S7. Victim reasoning: a dependency judged by its own state

What it is. `calls` lists each dependency with its own signals, readiness, restarts and `looks_healthy_on_its_own`
(investigate.dependency_state ignores the errors others log about it). The victim verdict says "the dependency may look
healthy itself: a server whose password, ACL, or config changed shows the failure on its clients". A victim moves the
named dependency to the front of the queue with `failing_targets` as backups; the fallback ends a strong victim chain on
the dependency.

Evidence (fact).
- lite6_valkey_auth Jev: cart judged victim 0.95, next hop valkey-cart 0.99; after a long walk the chain fallback named
  valkey-cart (right place; lost D1 points only on "deployment vs service" and D2 on the invisible runtime password).
- lite5_search_rate Dec judged search a victim 0.82 (search is not the origin).
- Limits: tgt_missing_env Jev called the true origin (frontend) a victim 0.82 because its errors named email; Decisions
  says "origin" to 16 of 26 wrong candidates (decision-models 2.6).

STRATEGY status: kept in concept ("whether a parent already explains it"). **At risk** if "parent" is computed only from a
call graph: v2's victim rule failed when the link lived in a config file, a base64 command or an unavailable previous log
(tgt_update: `rate` never marked a victim of `mongodb-rate`).

Make it better.
- Compute the victim fact from several link sources with provenance (env address, error text first-hop name, Service
  endpoints, Jaeger edge) and show which source it came from. A missing link means "unknown", never "not a victim".
- Fix relayed names (W8) by keeping only the first-hop name in an error line (the name nearest the failing operation),
  not by dropping text links.
- Ask about facts, not verdicts, for Decisions' yes-bias ("Do candidate's ongoing errors name a dependency?" rather than
  "is it the origin?"), as decision-models 3.7 recommends.

### S8. Server login rejections point at the clients

What it is. A server's own login-rejection lines (postgres, mysql, mongodb, rabbitmq formats; only counted on the
component that plays that role) are reported on the server as "rejects logins for account X; the rejected credentials come
from its clients", and clients are scored (Secret read through env rewritten shortly before the rejections began +3, only
client naming the account +3, env addresses the server +1, refreshed template -2). For credential or RBAC causes v1
examines the "other side" and asks a pair question.

Evidence (fact). lite6_secret_rotation snapshot: postgresql "rejects logins for account otelu (19 lines, still occurring);
... candidates deployment/product-catalog (secret/product-catalog-db-conn, which it reads through env values, was rewritten
83s before the rejections began ...)". product-catalog got `change`, `configuration` and `pointed_at`; triage 0.75 (Jev) and
0.85 (Dec). Jev passed 100 with the stale-read fact quoted. Dec failed only because origin 0.49 < 0.6 sent the walk on to
postgresql. Both v2 arms picked the postgresql-init ConfigMap (11 / 45).

STRATEGY status: not mentioned. **At risk** from the lint (the rejection formats name servers) and from a reach-based core
(postgresql has a change, a config fact and symptoms, and "reaches" more symptoms than its client).

Make it better.
- Keep the technology table; generalize by class: "an authentication failure logged by the server role about a named
  account" points at the clients that present that account.
- Confirm with a read-only check when allowed (STRATEGY item 3): the server's view of auth (for example its auth mode or a
  ping that returns NOAUTH), never a secret value.
- Replace the 0.6 threshold that lost the Dec arm with agreement or rank (S16).

### S9. Conditional telemetry prior

What it is. Components whose names match telemetry products get `role: observability`. A telemetry component whose only
evidence is a change or error logs is examined after application candidates; one with its own symptoms or configuration
defects keeps its triage rank. Telemetry export lines never point at anything. Triage rule 1 says a change on a telemetry
component counts only when application errors name it, "operators and the platform write to telemetry objects routinely".

Evidence (fact).
- otel-collector-agent was triage top-1 in lite6_valkey_auth Jev (0.47), arms_valkey_auth Jev (0.49) and tgt_missing_env
  Dec (0.35). v1 concluded it in none of them (tgt_missing_env Dec passed 100 on frontend).
- deployment/jaeger, also "observability", had its own config defect and symptoms in duplicate_pvc_social and was named in
  all 7 graded arms that concluded on a workload (100 each).
- v2 lost this: its config-link builder did not skip observability, and v2 Jev picked otel-collector-agent in
  tgt_missing_env (11) (forensics 2.2).

STRATEGY status: not mentioned, **at risk.** The lint rule "knowledge may name only Kubernetes kinds, fields and symptom
classes, never an app, service or problem-specific value" can be read to forbid `OBSERVABILITY_RE` (grafana, jaeger,
otel...). Jaeger and OTel data will also make the collector look central in any call graph (every service talks to it).

Make it better.
- Add a behavior-based role test next to the name list: a component that only receives export traffic (OTLP ports, many
  clients, no application callers in traces) is telemetry. Keep the name list as a fallback.
- Exclude telemetry edges from "reach" and from victim links.
- Allowlist technology vocabularies in the lint (G18).

### S10. Workload first, cluster object second; linked fault object; carrier lead line

What it is. When triage puts >= 0.3 of the kind mass on cluster kinds, the cluster node is queued right after the top
candidate, not before it. The fault object is picked from findings linked to the concluded workload (`finding_linked`,
plus the admission diff for webhooks). Carrier objects (webhook, quota, LimitRange, role, NetworkPolicy) lead the report as
"Root cause object: X, acting on <workload>".

Evidence (fact).
- Protection against leftovers. held5_readiness Jev: triage `other` 0.60, frontend 0.38; the only finding was the leftover
  CoreDNS change 2470 s before onset; frontend was examined first, origin 1.0, score 100. held5_liveness: Jev triage
  `other` 0.49, aux-service examined first, 67; the Dec arm had aux-service "undetermined" 0.45, went to the cluster node,
  which picked the leftover CoreDNS ConfigMap at 0.86, score 0. The same leftover also drew 0.30-0.32 of triage in
  lite6_duplicate_pvc_social, held5_duplicate_pvc and held5_sidecar (Jev), where the top workload went first and passed.
- Carrier framing through the workload. lite6_finalizer Jev (`other` 0.70) -> "Root cause object: ClusterRole
  configmap-cleanup-controller, acting on Deployment cleanup-controller", 100. lite6_namespace_memory (`other` 0.97 Jev,
  0.61 Dec) -> "Root cause object: ResourceQuota memory-limit-quota ... acting on Deployment search", 89 / 89.
- Linkage picks the right object among look-alikes. lite6_mutating_webhook: five MutatingWebhookConfigurations were all
  written 11 s before onset; the report named gatekeeper-mutating-webhook-configuration, the one whose rules matched the
  rewritten nginx-thrift pods, 89 / 89.
- Cost of the same rule: service_dns astronomy held3/held4 (55 x4) and dns_social Dec (67): the workload crossed 0.6 first
  and the CoreDNS ConfigMap appeared only as a "Fault object" line.

STRATEGY status: **at risk.** Item 1 lists "cluster objects demoted behind workloads" as a bug. If the fix is "examine
`other` first when triage prefers it", held5_readiness and held5_liveness Jev would likely become the Dec failure (cluster
node picks the leftover), and the webhook choice would lose its anchor.

Make it better (a comparison, not a reorder).
- Examine the top workload and the top linked finding, then decide between them with facts both sides share: change time
  vs the onset of the components it acts on, whether it is linked to the unhealthy components (DNS: the CoreDNS rule names
  frontend's Service and changed 37 s before onset), and whether the workload has its own config defect. A cluster object
  leads only when it changed near onset and is linked; otherwise it is the "Fault object" line.
- Measure on Lite: dns_social leads with CoreDNS for both models; every Lite state with the leftover CoreDNS keeps the
  workload (G11).

### S11. The model picks among code-made options; no story must fit

What it is. v1 has no "if pattern then cause" layer between the facts and the answer. Its unit is "this component plus its
strongest fact", which degrades gracefully on faults nobody wrote rules for.

Evidence (fact). On sample A v1 matched or beat v2 (v1 7/10 and 7/10 vs v2 7/10 and 8/10, with v2 tuned on it), and 8 of
20 held-out v2 arms only passed because v2 fell back to v1's key-fact step (forensics 5.1).

STRATEGY status: **kept** ("the options carry facts, never code's verdicts"). Risk: new origin kinds (path, topic,
multi-workload set) need candidate builders, and builders written for specific shapes are how v2 became a pattern list
(`interaction/`, `input/`, bad-input junk options in 4 of 6 slots).

Make it better.
- Generate candidates by enumerating objects that carry a fact (any kind), and attach the general "fault in X, mechanism =
  X's strongest fact" option for every unhealthy or changed object. Shapes like "same change on N workloads" or "path
  between A and B" are groupings of existing facts, built only when the shared facts exist (identical change; caller errors
  that name the callee plus the callee's own saturation fact).
- Measure candidate recall on Lite (G19) and count options per decision that have no fact behind them (target 0).

### S12. Verbatim key fact with concrete values; evidence order

What it is. The report's "Mechanism:" line is the chosen evidence item, word for word. The evidence list puts template
changes first, then signals, code checks, probe results, non-default pod settings, salient env (changed, duplicated, or
address-like), probes, command/args, image and resources, ConfigMap keys, RBAC, logs, events, dependencies, other env. The
list is capped at 32, so the order decides what can be chosen.

Evidence (fact). On the same 43 snapshots per model (lite5, lite6, held*, tgt): D2-Q1 yes rate v1 0.86 (Jev) / 0.88 (Dec)
vs v2 0.70 / 0.77; D2-Q2 (concrete values) v1 0.79 / 0.79 vs v2 0.70 / 0.77. Examples: secret_rotation Jev "Secret
product-catalog-db-conn was rewritten at ..., it is read through env DB_CONNECTION_STRING, which are fixed when the container
starts" (100); env_shadowing "defines env var FRONTEND_HOST 2 times: 'frontend', then 'localhost'" (89/89).
Two weaknesses. Long values are dumped whole (liveness quoted a whole service.py; edge Dec quoted a Perl script; kafka Dec
quoted consumer.py and lost D2-Q2). And the pick is one item (edge Jev picked "limits.cpu: unset -> 100m", 67).

STRATEGY status: **improved** (item 6 adds the bad value and the good value). **At risk** if the "one origin sentence" is a
code template that replaces the quoted fact: v2's "was changed recently and breaks X" lost D2-Q1 on auth_miss with the right
fact in hand (forensics 2.3).

Make it better.
- Origin sentence on top, quoted fact under it, unchanged. For change facts, print "field: old -> new". Cap quoted values
  around the changed tokens (diff context), not by blind truncation.
- When a revision changed several fields, quote each changed field (v1 already lists all code mismatches); let the model
  rank them rather than pick one.
- Measure: D2-Q1 and D2-Q2 yes rates on Lite per model, against v1's on the same snapshots (G7, G15).

### S13. Generous report sections

What it is. After the mechanism the report lists code-found mismatches, abnormal state (up to 12 lines), impact on callers,
notable spec settings, containers, warning events, ongoing error lines, last lines of the crashed run, alerts.

Evidence (fact). held6_auth_miss Jev: the judge's D2-Q1 and D2-Q2 "Yes" cite "requireTLS with an unreadable certificate file
and InvalidSSLConfiguration", which came from the printed mongod error lines, not from the mechanism line; v2 had the same
snapshot and lost D2 (44/33 vs 100/77). D3-Q3 yes rate v1 0.84-0.86 vs v2 0.81.

STRATEGY status: partly kept ("lists affected components clearly as victims"). Risk: "shape the report for the judge" can
turn into a short report. Also listing victims can read as blame (v2 Jev incorrect_image lost D3-Q1 on "frontend fails as a
result").

Make it better.
- Keep every section. Phrase impact as "X fails when calling <origin> (class, count, still occurring)", never as a cause.
- Add "Scope:" listing every object that shares the cause (grouped changes from S4).
- Measure: D3-Q1 and D3-Q3 yes rates on Lite not below v1's.

### S14. Dual naming: workload plus fault object

Evidence (fact). auth_miss: v1 "Root cause component: Deployment url-shorten-mongodb" + "Fault object: ConfigMap ..." passed
D1 (100 / 77); v2 named only the ConfigMap and failed D1 (44 / 33). internal_traffic v1 lost D1-Q3 points (78 / 89) for
leading with the Deployment when the target was the Service. The judge's D1-Q1 asks for "the same service, deployment, pod,
node, or infrastructure component" as the target.

STRATEGY status: **kept and improved** (item 2 and 6: name both the changed thing and the broken thing).

Make it better. Lead with the object that carries the change when it is a Service, policy, webhook, quota or cluster
object, and with the workload when the change is in its own spec; always name the other one in the same sentence. Measure
D1 yes rates on Lite (G8, G15).

### S15. Few calls, cheap, fast

Evidence (fact, same 43 snapshots per model). v1 median 2 requests (max 8), median wall time per arm 2.8-2.9 s
(including live detail reads; summed model latency ~1.5-1.6 s, v1-architecture 6), median input tokens 22.0k (Dec) /
32.2k (Jev), median cost $0.0022 / $0.0014. v2: median 4 requests, 6.2-6.4 s, 26.9k / 40.2k tokens. Longer v1 walks
mostly failed (3 of 10 passed).

STRATEGY status: **at risk.** The goal says "uses no more tokens than v1", but the design adds asking twice, tie-break
tests, new evidence and more candidate kinds. The triage is 66-70% of v1's tokens; asking it twice alone breaks the goal.

Make it better.
- Ask twice only the final slate, and only when the first answer is not clearly ahead.
- Drop `fault_visible`; send the evidence list once (v1 sends it in the state and as options, ~21% of an investigation).
- Budget per model tokenizer (Jev counts ~1.5x Dec tokens); keep Jev requests under ~32 kB where possible.
- Target: median requests <= 4, median tokens <= 1.3x v1 per model, p90 model time <= 10 s (G16). Cost is not the limit
  (< $0.004 per diagnosis), so this is about latency and failure points, not money.

### S16. Stable pass/fail across reruns

Evidence (fact). Across repeated faults v1 flipped pass/fail in 4 places only, each from one threshold (0.49 or 0.56 vs
0.6) or one leftover object (forensics 4). v1 picked the same component in every valkey_memory run; v2's pick wandered
across three components.

STRATEGY status: at risk; more steps and live tie-break tests read live state that can differ between runs.

Make it better. Replace fixed probability thresholds with agreement and rank rules (decision-models 4); make tie-break tests
deterministic reads with a fixed sample window. Measure flips over 2 Lite runs per model (G17).

### S17. Ordered fallback chain, always answers

What it is. If no origin is confirmed: the best investigated origin with p >= 0.4; else the end of a strong victim chain
(with a re-asked category and key fact from the victim's failure); else `other` if triage chose it; else triage top-1 that
is not telemetry.

Evidence (fact). Six v1 arms ended in a fallback. tgt_missing_env Dec passed 100 through "most likely origin among
investigated" (frontend 0.42). lite6_valkey_auth Jev reached valkey-cart through the chain fallback. Gap: when the model
call itself fails there is no diagnosis (lite5_finalizer both arms, OpenRouter 402; arms_valkey_auth v1 Dec, HTTP 502,
score 0).

STRATEGY status: not mentioned.

Make it better. Keep the order of fallbacks. Add a code-only last resort that needs no model call (the nearest spec change
before onset, with its component and its strongest fact; else the top detector fact on the most impacted component), so a
model outage still submits a reasonable report (G6).

### S18. Priority-based state trimming

What it is. 20 ordered trim steps cut healthy components first, then caps logs, events and pods for all; a last-resort
halving never touches protected keys (signals, spec_checks, service_checks, template_changes, admission_changes, evidence,
findings, probe, repeated_failures, failing_targets, input_candidates). The token estimate (2 chars per token) is set for
the heavier Jev tokenizer, so the same state fits both models.

Evidence (fact, triage traces). Trimming ran in 20 of 27 latest runs, on all three apps (Social Network 26.5-34.4k ->
15.3-22.9k estimated tokens after 7 steps). tgt_update_incompatible needed all 18 steps (37.2k -> 23.9k) and still passed 89 / 89.

STRATEGY status: not mentioned. **At risk:** the triage state is already at the budget in most runs. Metrics, traces, logs,
outside objects and probe results will compete for the same space; if they are added to components as ordinary keys, the
trim ladder will cut kubectl detail first or the last-resort halving will shorten protected facts.

Make it better.
- Give each data source a priority tier: protected detector facts and changes; compact derived lines from new sources (one
  sentence per anomaly, with values); raw new data never in the triage state.
- Record what was cut and assert that protected keys are unchanged (G5).

### S19. Fail-soft, replayable, read-only collection

What it is. Every kubectl read returns [] and records the error instead of failing (`kubectl_items`); logs are fetched in a
thread pool with per-job error capture; metrics-server and alerts are optional; probes never stop the diagnosis; secret
values are never read (key names and write times only); every kubectl response is saved (`*_kubectl_raw.jsonl.gz`), and
`replay.py --raw` re-runs the whole collection offline with the clock pinned; `derive.post_process` can be re-run safely.

Evidence (fact). 0 collection errors in 45 recent snapshots, but the fail-soft paths exist for every read. The raw bundles
exist for every run in the index.

STRATEGY status: at risk from new sources on the critical path (PromQL, Jaeger, Loki, exec probes; STRATEGY open question 2
notes exec is refused into host-network pods in filtered mode).

Make it better. Same contract for every new source: per-source timeout, empty result recorded, never raises; record raw
responses into the same bundle so replay stays complete; probes stay read-only and never read secret values (G6).

---------------------------------------------------------------------------------------------------------------------
## 2. Cross-cutting risks in STRATEGY (ranked by likelihood x impact)

| # | Risk | Likelihood / impact | Evidence it is real | What to write into STRATEGY |
|---|---|---|---|---|
| R1 | The 2-7 option core replaces the whole-app triage and its prior | high / high | v2: TOP_K cut 2 of 6 true options, focused state hid the rest, 0/11 vs v1 89/89 (tgt_update); 80/86 v1 arms decided at triage | "Step 1 stays v1's whole-application triage with its prior; the slate decides only among its top-k plus linked outside objects." |
| R2 | "Which symptoms it can reach" rewards wide impact | high / high | v2's "explains the most symptoms": dependency winners passed 3 of 8; victims and telemetry links won (forensics 5.2) | "Reach is shown as a fact; the prior says reach alone never selects, as symptoms alone never select in v1 rule 4. Telemetry edges are excluded from reach." |
| R3 | Reordering cluster objects before workloads | medium / high | leftover CoreDNS in 32 of 81 snapshots; held5_readiness and held5_liveness Jev passed only because the workload went first | Replace the bug-fix line with the comparison in S10 |
| R4 | New data crowds the budget and moves the onset | medium / medium-high | triage already trimmed in 20 of 27 runs; an early alert already pushed real changes "after onset" (secret_rotation) | Source tiers (S18); one recency model for all sources (S6); per-component onset (S5) |
| R5 | The lint deletes technology knowledge v1 needs | medium / medium | telemetry names, server login formats, role synonyms (redis/valkey) carry S8, S9, and failing_targets | Allowlist technology and protocol vocabularies; forbid app, service and problem names only (G18) |
| R6 | Retyping evidence kinds changes triage silently | medium / medium | cronjob and selector faults rely on signals that are "configuration" by default | Run G3 and review every changed tag |
| R7 | Report shaping drops the verbatim fact or sections | medium / medium | v2's templated mechanism lost D2-Q1 on auth_miss; v1's printed log lines earned D2 | Origin sentence above the quoted fact, never instead of it; keep all sections |
| R8 | More calls, more latency, more variance | medium / low-medium | v2 4 calls, 6.3 s; long v1 walks pass 3 of 10; Dec order flips 20% | Targets in S15; agreement instead of thresholds |
| R9 | Revision diffs add restart-only "changes" | medium / low-medium | restartedAt on the otel collector in most astronomy runs | Change content classes (S4) |
| R10 | New probes and queries become failure points | low-medium / medium | exec refused into host-network pods (STRATEGY open question 2) | Fail-soft contract (S19) |

About "no fault-category label" in the report (STRATEGY item 6). Fact: in 86 graded v1 arms the judge's D2-Q3 ("avoid
attributing the fault to an incorrect or unrelated fault type") was "No" 17 times; 11 of those cite v1's "Fault type" label
(code_bug on liveness, job lifecycle or config value on valkey_memory, service routing on valkey_auth). It was "Yes" 69
times, and 61 of those answers mention the classification. A missing label cannot conflict, so dropping it probably removes those 11
misses; whether the judge then still credits D2-Q1 as often is not measured. Opinion: keep the category as an internal
answer (it drives the fault object and the other-side logic) and A/B the printed label on Lite before deciding.

What STRATEGY gets right for v1's strengths (fact-based): starting from a full copy of v1 (protects S3-S9, S12-S14,
S17-S19 at stage 1); naming both the changed and the broken object (S14); measuring candidate recall separately (S11);
fixing probe timing, revision diffs and relayed names (S3, S4, S7); read-only probes for runtime state (S8, valkey_auth).

---------------------------------------------------------------------------------------------------------------------
## 3. Regression guards (run on Lite during development)

Three tiers. Tier A is deterministic and costs nothing: it replays each Lite run's saved raw kubectl bundle through the new
collector and derive code (`replay.py --raw` already does this, serving per-component detail reads from the bundle when
the original run made them). Tier B re-asks the decision questions on frozen states (about $0.001 per ask). Tier C is
the arms harness on live Lite runs (v1 and new on one snapshot, same judge). Test fixtures may name faults and values; the
pipeline may not (the generality rule applies to pipeline code, not to tests).

| Id | Tier | Check | Protects |
|---|---|---|---|
| G1 | A | Every fact v1 quoted in a Lite pass is still produced, with its value, on the same component (table below) | S3, S12 |
| G2 | A | The nearest spec change before onset is the same object as in v1's snapshot for every Lite fault that has one; restart-only and telemetry changes are never flagged nearest; the leftover CoreDNS change is never flagged | S4, S5 |
| G3 | A | Diff of evidence kinds (or their typed replacements) for every component of every Lite state vs v1; any change is listed for review | S2, S3 |
| G4 | A | 0 pointers or own-failure signals from stopped or warm-up lines; telemetry lines never point; counts of stopped-only components within 10% of v1 per state; the same holds for Loki and Jaeger inputs | S6 |
| G5 | A | After budget fitting at each model's budget, protected keys are byte-identical to the untrimmed state; new-source facts are cut before any kubectl fact; the largest saved state (tgt_update size, 37k est. tokens) fits without losing a signal | S18 |
| G6 | A | Chaos: replay with each new source disabled, timing out, or returning junk; no exception, kubectl facts unchanged. Model client raising on every call still yields a submitted code-only report | S17, S19 |
| G7 | A | The report contains the chosen fact string exactly (after newline normalization); change facts show old -> new; no quoted value longer than the cap without its changed tokens | S12 |
| G8 | A | Report keeps the sections of S13; when a linked fault object exists both names appear in the first line; carrier objects lead | S10, S13, S14 |
| G9 | B | Re-ask step 1 and the final decision on frozen Lite states with Jev, Dec and one more model, two orders. Every Lite fault v1 passed with a model is still right with that model (v1 Jev 13, Dec 12); report per-model accuracy and top-3 recall | S1, S2, S7 |
| G10 | B | Prior ablation: same as G9 with the prior block removed or rewritten; adopt a rewrite only if no Lite fault is lost on any of the 3 models | S2 |
| G11 | B | Leftover trap. On every Lite state with the leftover CoreDNS finding (lite6 dup_pvc_social, edge, env_shadowing, internal_traffic, kafka, mutating_webhook, rolling_update) the pick is never CoreDNS; on dns_social it leads with CoreDNS. Perturbation: add a synthetic unrelated ConfigMap change 2000 s before onset to every Lite state; no pick changes | S5, S10 |
| G12 | B | Telemetry trap. The otel collector restart is present in many astronomy states; it is never picked. Perturbation: give the telemetry collector the widest reach in the graph; no pick changes. jaeger is still picked on dup_pvc_social | S9 |
| G13 | B | secret_rotation names product-catalog with both models (v1 Dec failed only on the threshold, so this is also an improvement target); valkey_auth locates valkey-cart, not cart | S7, S8 |
| G14 | B | Grouping. Offline perturbation: copy one Lite image or env change to 3 more workloads; the report names one cause with all 4 in scope | S4, S13 |
| G15 | C | Paired Lite arms, 2 runs per fault per model: pass count >= v1 per model; no fault where v1 passes both runs and new fails both; D1, D2-Q1, D2-Q2, D3 yes rates not below v1's | all |
| G16 | C | Median requests <= 4, median input tokens <= 1.3x v1 per model, p90 model time <= 10 s, collection time recorded per source | S15 |
| G17 | C | Pass/fail flips across the 2 runs per model no more than v1's | S16 |
| G18 | A | The generality lint passes on v1's own technology tables (role synonyms, server login formats, telemetry names, probe commands) and fails on any app, service or problem name in pipeline code | S8, S9 |
| G19 | A | For every Lite state, the true origin object and the component it breaks are in the candidate set; every unhealthy or changed object has a "fault in X, mechanism = strongest fact" option; options with no fact behind them = 0 | S1, S11 |

Facts G1 must find (from v1's Lite reports, latest runs; the value in quotes must appear on that component):

| Lite fault | Component | Fact and value |
|---|---|---|
| cronjob_sidecar | cronjob/audit-log-archiver | job has an active pod that has not completed; sidecar command `nc -lk` |
| finalizer_deadlock | deployment/cleanup-controller | ConfigMap reservation-cleanup-token terminating, held by finalizer; ClusterRole grants "get, list, watch" only |
| search_rate_retry | deployment/rate | `RATE_BACKEND_QPS_LIMIT=20` (plus, new, the caller's retry and timeout settings) |
| service_wrong_pod_selection | deployment/frontend | Service frontend selects 2 workloads through selector `{'service-route': 'frontend'}` |
| duplicate_pvc_mounts_social | deployment/jaeger | PVC jaeger-pvc ReadWriteOnce, 2 replicas, anti-affinity |
| edge_request_filter | deployment/frontend-proxy | revision 2 changed `args` (the regex) and `limits.cpu: unset -> 100m` |
| env_variable_shadowing | deployment/frontend-proxy | FRONTEND_HOST defined 2 times, `'frontend'` then `'localhost'` |
| internal_traffic_policy | deployment/recommendation | Service recommendation `internalTrafficPolicy=Local`, modified 65 s before onset |
| kafka_poison_pill | deployment/orders-validator | repeated failure at `offset=20`; `ORDERS_TOPIC=orders-fulfillment` |
| mutating_webhook | deployment/nginx-thrift | running pod `limits.memory 16Mi, template 256Mi`; matching webhook gatekeeper-... |
| namespace_memory_limit | deployment/search | ResourceQuota memory-limit-quota requires memory; containers declare none |
| network_policy_block | deployment/recommendation | selected by NetworkPolicy deny-all-recommendation (denies all ingress and egress) |
| rolling_update_misconfigured | deployment/custom-service | init container `sleep infinity` (plus rollout strategy) |
| secret_rotation | deployment/product-catalog | Secret rewritten after start, read through env DB_CONNECTION_STRING; postgresql rejects logins for `otelu` with product-catalog as candidate |
| service_dns_social | CoreDNS ConfigMap / user-service | rule for user-service with `rcode NXDOMAIN`, changed 120 s before onset |
| unschedulable_port | deployment/checkout | node_selector `kubernetes.io/hostname: extra-node` |
| valkey_auth | deployment/valkey-cart | cart's errors name valkey-cart; new: a read-only check showing the server requires auth |

Offline guard corpus (needs the user's decision). Sample A and set T are studied and not reported, but their saved raw
bundles and snapshots cover v1 strengths that Lite does not exercise (correlated change on six databases, stale TLS config,
probe timing, held-out selector and port faults). Using them only for Tier A and B regression, never for reported
numbers, would catch losses that Lite cannot show. This conflicts with the "two sets only" rule as written, so it is a
question, not a plan.

---------------------------------------------------------------------------------------------------------------------
## 4. Suggested edits to STRATEGY.md (wording to add)

1. Section 3.1, replace "cluster objects demoted behind workloads" with "cluster objects are compared with the top workload
   using change time vs onset and linkage to the affected components; they are not simply moved first (a leftover CoreDNS
   change is in 32 of 81 saved snapshots)."
2. Section 3.4, add "Step 1 stays v1's whole-application triage with its written prior. The slate (2-7 options, asked in
   two orders) decides only among the triage's top-k plus linked outside objects. Reach is a fact, never a reason on its
   own; telemetry edges are excluded from reach."
3. Section 3.6, add "The origin sentence is placed above v1's quoted key fact, never instead of it; all v1 report sections
   stay."
4. Section 3.7, add "The lint allows Kubernetes kinds and fields, symptom classes, and technology or protocol vocabularies
   (data store roles, server log formats, telemetry product names); it forbids app, service and problem names."
5. Section 2, change "uses no more tokens than v1" to "median requests <= 4 and median tokens <= 1.3x v1 per model".
6. New item: "Every new data source is fail-soft, recorded in the raw bundle, passes the same recency filter as pod logs,
   and enters the state as compact facts in a lower trim tier than kubectl facts."
7. New item: "If the model call fails, a code-only report is still submitted."
8. Stage table: each stage's check includes guards G1-G19 (section 3 of this review), not only "Lite: at least v1".

---------------------------------------------------------------------------------------------------------------------
## 5. Facts, opinions, and what is uncertain

- Facts: all counts, scores, probabilities, quoted report lines and code references above, read from the run files and the
  code named next to them. Counts cover lite5, lite6, held*, tgt unless a section says "all labels" (81 snapshots).
- Opinions: that the triage step is where v1's strength lives (inferred from 80/86 conclusions at triage top-1 and from
  which runs pass; no ablation was run); that reordering cluster objects would lose held5_readiness and held5_liveness Jev
  (inferred from the Dec arm's behavior on the same snapshot); that the stage 3 core would repeat v2's recall failure
  (inferred from v2's mechanism, not tested); the risk ranking.
- Uncertain: the net judge effect of dropping the "Fault type" line; whether metrics-based onsets are noisier than the
  current ones (no metrics were collected in any run); how often Loki returns warm-up or stopped history in these apps;
  judge noise of about 11 points on identical text (forensics 4), so single Lite runs can mislead, which is why G15 uses
  two runs per fault.
