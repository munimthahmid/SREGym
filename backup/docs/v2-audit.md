# v2 audit (jev_v2 at 066c4d2f), 2026-10-19

Status: DONE (sections 0-6), 2026-10-19. Facts are marked as facts and cite files, commits and run labels; opinions
are marked **Opinion**.

Scope: read-only audit of `~/sregym/SREGym-fixes/clients/jev_v2/` (the working tree equals 066c4d2f for
`clients/jev_v2` and `clients/jev_diag`; checked with `git diff --stat 066c4d2f`), its history in `~/sregym/SREGym-dev`,
the design notes, and every run in `runs-index.tsv`. Sample C was not opened. Scripts used for the counts are in the
session scratchpad, not in this folder. One offline call of `patterns.build_explanations` + `decide.shortlist` was made
on a saved snapshot (`tgt_update_incompatible_correlated`) with the repo venv, no cluster, no model, no writes.

## 0. The short version

- v2 is a thin decision layer (1,278 lines) on top of all of v1's evidence code (8,708 lines). It collects nothing new.
  None of the design's new evidence (ledger, graph, coverage, Prometheus ranges, Jaeger, Loki, probes, contrast sets,
  discriminating checks, two causes) was built.
- Its "generic patterns" map one-to-one onto the mechanism families of the 17 Lite answer labels (change, acts-on,
  amplify, bad-input, hidden-state), including two pseudo-objects (`interaction/`, `input/`) that exist only to match
  the Lite labels `RPCPath search-to-rate` and `KafkaTopic orders-fulfillment`. 12 of the 15 later commits add or tune a
  rule right after one failed run (the other 3 are follow-ups or bug fixes); 6 of the 15 port a v1 rule back in.
- The "supports / contradicts" checks are mostly restatements of the condition that created the candidate. In 28 of
  56 first decisions the true cause was not ahead of the best wrong option on checks (22 ties, 6 behind).
- The go-back loop has been dead since 6fec2c91: the model was unsure in 26 of 82 arms, a second round ran in 2.
- On Lite v2 differs from v1 and wins (1 of 34 v2/v1 pairs share the mechanism line; v2 better in 11, worse in 4).
  Outside Lite v2 falls back to v1's own characterization text (11 of 26 pairs share the mechanism line; v2 better in 4,
  worse in 6), and on the targeted set it loses all 4 pairs. That is the signature of fitting, not of a better method.

**Which code each run label used** (from the `chainN.sh` guards `git diff --quiet <commit>` and `runs.txt`). The
README calls lite5/lite6 "the latest code", but they ran on **30dd021e**, not 066c4d2f.

| Labels | v2 commit |
|---|---|
| arms01, arms_* | 6400cd46 (first commit) |
| rerun_* | 3dc3e053 |
| final_*, held_ (dns, selector) | 1d22d925 |
| held_duplicate_pvc_mounts_hotel_reservation (ungraded) | 272123ae |
| held2_* | 6fec2c91 |
| held3_* | c798a1b8 |
| held4_* | 2f3ee19f |
| held5_*, lite5_*, lite6_* | 30dd021e |
| held6_*, tgt_* | 066c4d2f |

So the Lite headline (15/17) is on 30dd021e. Only 4 runs exist on 066c4d2f (held6 x2, tgt x2): v2 passes 0/4 (Jev)
and 1/4 (Decisions); v1 passes 2/4 and 3/4 on the same snapshots.

**Sample A was not held out by the time it was scored.** Six v2 commits (272123ae, 676024e9, 6fec2c91, c798a1b8,
2f3ee19f, 30dd021e) landed between the first sample-A runs (held_, 00:34) and the latest sample-A runs (held4/held5, 08:49-10:13), whose
scores reproduce the README's sample-A numbers; several of those commits react to sample-A failures (section 2).
Even tuned on it, v2 only tied v1 there (Jev 7 vs 7, Decisions 8 vs 7).

---

## 1. Actual end-to-end flow (as the code runs it)

Fact: v2 is a new decision layer on top of v1's evidence. It has no collector of its own.

1. **Collection is v1's, unchanged.** `clients/jev_diag/driver.py` collects one snapshot with v1's
   `collect_snapshot` + `derive.post_process` (kubectl state, logs, alerts, v1's code checks). In arms mode the trace
   shows `exec_probes: false`, so no probes run for any arm (v1's `IterativeDiagnoser` is also built without `probe=`
   in `arms.py:151`). Each arm gets `copy.deepcopy(snapshot)` (`arms.py:162`) and reads component detail live through
   v1's `investigate.collect_component_detail`.
2. **Build candidates** (`patterns.build_explanations(snapshot)`, no detail yet): 13 builders turn v1's derived fields
   (`template_changes`, `cluster._changes`, `cluster.findings`, `errors_point_to`, `referenced_by_errors_from`,
   `signals`, `evidence_kinds`, `created`, and later the detail's env/args/logs) into `Explanation` objects with a
   templated mechanism sentence and 1-4 `Prediction`s whose status is fixed when the candidate is built (section 3).
   `victim_check` then adds a contradiction to failing callers of a component that is broken itself.
3. **Pre-read** (`agent.py:128`, added 6fec2c91): shortlist the top 6 (`decide.shortlist`), take the first 6
   components those 6 chains mention, fetch v1's component detail for each.
4. **Decision loop** (`agent.py:134-151`): rebuild candidates with detail, shortlist the top 6 by (contradicted?,
   mechanism-specific supported groups, all supported groups, impact size, build order), then `decide.pick`: ONE
   Choice question ("Which explanation best accounts for all the observed symptoms in `evidence`?") over the 6 option
   texts + "None of these", asked twice with shuffled neutral labels (o1..o7), probabilities averaged. Route: `accept`
   if both asks pick the same option and its average is >= 0.6; `coverage` if "none" leads; else `check`.
   - `check` reads the components of the top two *shortlisted* chains (shortlist rank, not the model's ranking).
     The pre-read already read them, so `_look_closer` almost always returns False and the loop ends (section 4).
   - `coverage` reads the two most-affected unhealthy components not yet read.
5. **Winner** (`_winner`): the averaged leader; if "none" leads, the best-ranked `partial` chain.
6. **Characterize** (`_characterize`, 676024e9 + 6fec2c91): v1's `tree.detail_evidence` facts for the winner's first
   component, then **v1's characterization request** (`classifier.build_characterization_questions`: "which single item
   most directly reveals the mechanism" + fault category), asked twice shuffled, plus v1's limit-vs-change rule
   (066c4d2f). If the winner is `partial`, it becomes a `key-fact` explanation whose mechanism is v1's picked fact.
7. **Report** (`report.build_report`): fixed templates. For `partial`, `key-fact`, `dependency` and `arrival` winners the
   "Mechanism:" line is v1's picked fact, not anything v2 built. Only one cause is ever passed (`[winner]`), although the
   report supports two. `uncertain` (route != accept) appends "Confidence: low; the investigation budget ended before
   the leading explanation was confirmed" even though no budget ended (section 4).

Requests per diagnosis since 6fec2c91: 2 decide + 2 characterize = 4 (v1: 2-3 typical). Wall time 4-12 s per arm;
the 120 s budget and the 8-request cap are never reached.

### What the decision model sees (real example)
Run `held5_service_port_conflict_social_network` (30dd021e),
`results/1019_1006/.runtime/jev_diag/anon_5ddb2baaecb9ebe6569c20dbc88ae1eb/*_arm0_v2_requests.json`, request
`decide:1` (14,676 input tokens; state 37.6k characters).

State (`agent._state`): `{"application": {...}, "evidence": {<component>: {kind, name, namespace, healthy,
signals[:8], template_changes, errors_point_to, referenced_by_errors_from, detail: <v1 component detail: workload
spec, pods, events, log summary, configmaps, service_checks, called_by_with_errors>}}, "cluster": {symptom_onset,
recent_changes, findings}}`, cut to 20k tokens by v1's `fit_state_to_budget`. Here `media-service.signals` already holds
v1's finding "pod unschedulable: 0/4 nodes are available: ... 3 node(s) didn't have free ports for the requested pod
port...".

Options (verbatim, ask 1):
- o1 `Origin: deployment/social-network/compose-post-service. The fault is in this component; the mechanism is not
  established. | Observed impact on: ... | Checks: deployment/compose-post-service only fails because
  deployment/media-service, which it calls, is broken (contradicts)`
- o2 `Origin: deployment/social-network/media-service. The fault is in this component; the mechanism is not
  established. | Observed impact on: media-service, compose-post-service`
- o3 `Origin: interaction/social-network/compose-post-service--media-service. Calls from compose-post-service to
  media-service time out; compose-post-service retries them, and the retries add load that keeps media-service
  saturated, so the failure sustains itself. | ... | Checks: errors of compose-post-service on media-service are
  timeouts or overload (supports)`
- o4 `Origin: deployment/social-network/media-service. deployment/media-service fails or rejects requests, so
  deployment/compose-post-service fail when calling it. | ... | Checks: still-occurring errors of
  compose-post-service name media-service (supports); media-service shows failures of its own (supports)`
- o5 `None of these explanations fits the evidence.`
- o6 `Origin: deployment/social-network/nginx-thrift. The fault is in this component; the mechanism is not
  established.`

What this shows (facts):
- No option states the actual mechanism (a pod that cannot be scheduled because of a host-port clash). It sits only in
  the state, in v1's signal text. The question the model really answers is "which component", which is v1's question.
- o3's "(supports)" is false on its face: the quoted errors are `Connection refused`, which v1 classes as
  "connectivity or timeout", and the amplify check counts that class as "timeouts or overload".
- o2 and o4 have the same origin and say the same thing at different detail. In the Decisions arm the two asks split
  between them (partial 0.48 vs dependency 0.41), so the route was `check` and the report says "Confidence: low".
- All four arms (v2 and v1, both models) submitted the same mechanism sentence (v1's picked FailedScheduling event) and
  all scored 78. v2's machinery changed nothing here.

---

## 2. Inventory of hand-written fault knowledge

Context (fact): every builder reads structures that v1's `derive.py`/`checks.py`/`collector.py` already produced; v2
also imports v1's word lists (`OBSERVABILITY_RE`, `TELEMETRY_RE`, `ROLE_SYNONYMS`, `CHANGE_MARKERS`, `SYMPTOM_MARKERS`,
`POINTED_MARKERS`, `OWN_LOG_MARKERS`). Several v2 rules parse v1's English signal sentences ("selected by ", " was
modified ", "server ... rejects", "e.g.", "was rewritten ... still use the previous values"), so a rewording in v1 silently
disables them.

The design (`jev-v2-design.md`, table "The five blog failures, by cause") derived the first patterns from the five Lite
faults v1 failed. The Lite labels (`jev-v2-dev-labels.json`, written before coding) use exactly the families
`change`, `acts-on`, `amplify`, `bad-input`, `hidden-state`.

Trigger fault = the run that failed just before the commit, confirmed by the commit message, `jev-v2-results.md`, or a
docstring example copied from that run's evidence.

### patterns.py builders and rules
| # | Rule (function / constant) | Mechanism it encodes | Added | Reacting to | Class |
|---|---|---|---|---|---|
| 1 | `change_explanations`, per template field + "together" | a recent pod-template change breaks the workload; split multi-field revisions | 6400cd46 | edge_request_filter (blog failure: two changes in one revision) | General principle. Gaps: no grouping of the same change across workloads; harness noise (otel `restartedAt`) becomes a candidate |
| 2 | `change_explanations`, `cluster._changes` | a separately changed object (Secret, ConfigMap, Service...) acting on an unhealthy component | 6400cd46 | Lite DNS / secret faults | General (thin wrapper over v1's change records) |
| 3 | `acts_on_explanations` | an outside object found by v1's checks (webhook, quota, DNS rule, policy, role) acts on a component | 6400cd46 | Lite webhook, quota, DNS, network policy, finalizer | General (thin wrapper over v1's checks) |
| 4 | acts-on merge in `build_explanations` (values, impact, then predictions) | one object found by a change and by a check counts once | 6400cd46, predictions merged in 272123ae | selector fault | Plumbing, but it stacks support counts on outside objects (held6_auth_miss_mongodb: the ConfigMap got 3 supports vs 2, was picked, and lost D1 because the key wants the Deployment) |
| 5 | `named_by` + `OUTSIDE_RE` (11 kinds + "selected by", "coredns rule") | a finding phrased "<kind> <name> ..." belongs to that object, not the workload | 272123ae | held_wrong_service_selector_astronomy_shop (sample A; v2 44/55 blaming Deployment frontend) | Fitted: regex over v1's phrasing |
| 6 | `dependency_explanations` (`errors_point_to`) | X fails or rejects its callers | 6400cd46 | general | General, but it includes observability targets (tgt_missing_env: Jev picked `daemonset/otel-collector-agent`) and it is the main source of victim picks (below) |
| 7 | `_configured_dependency` + `config_links` + `HOST_RE` | env/args addresses define call edges ("VALKEY_ADDR=valkey-cart:6379") | 2f3ee19f, refined 66b1f609 | held3_valkey_memory_disruption (sample A; v2 11/23 blamed cart; the docstring example is that run's key fact) | Principle general; implementation is name matching |
| 8 | `error_links` + `STORE_WORDS` + `STORE_KINDS` | a caller's errors naming a store protocol ("mongodb", "redis") link it to that store | 79895f12, 66b1f609 | held5_auth_miss_mongodb (34/34) and valkey runs; docstring examples "Failed to create mongodb index", "Wasn't able to connect to redis" are those runs' lines | Fitted: data stores and brokers only, by word list |
| 9 | `_broken_itself` | "broken itself" = unhealthy with evidence beyond being pointed at | 2f3ee19f | valkey_memory | General idea; depends on v1's `evidence_kinds` |
| 10 | `victim_check` | a failing caller of a component broken itself is not the origin | 2f3ee19f ("v1's victim rule") | valkey_memory | General principle (ported from v1). Only one hop; misses when the call link is not found (tgt_update_incompatible: `rate` not marked victim of `mongodb-rate`) |
| 11 | `arrival_explanations` (`ARRIVAL_AFTER_S=15`, `ARRIVAL_BEFORE_ONSET_S=600`) | an object created after the app and shortly before onset | 2f3ee19f | held3_valkey_memory (`job/valkey-memory-flood`) | General heuristic, hand-picked thresholds. Won 2 arms, both failed D1 |
| 12 | `amplify_explanations` (`TIMEOUT_CLASSES`, `SATURATION_RE`, `SETTING_RE`) | retries keep a callee saturated; origin `interaction/<caller>--<callee>` | 6400cd46 | search_rate_retry_collapse (blog failure; label origin `RPCPath search-to-rate`) | Fitted. Fires on any "connectivity or timeout" error incl. `Connection refused` and gRPC Unavailable; offered in held5 service_port, auth_miss, valkey_memory, lite6 dns, valkey_auth, tgt_update. Won only on Lite retry collapse |
| 13 | `hidden_state_explanations`, auth variant | a server's running auth settings no longer match clients | 6400cd46 | valkey_auth_disruption (blog failure) | Fitted. Its "login check" prediction (`check="probe"`) is never run. Never won a pass (the one `hidden-state` pass, final secret_rotation Jev, came from rule 15, which reuses the pattern name) |
| 14 | `_refused_without_own_trouble` + `TIMEOUT_RE` ("quiet server") | clients cannot connect to a server that shows nothing itself | 1d22d925 | valkey_auth_disruption | Fitted |
| 15 | `stale_read_explanations` + `STALE_RE` | a workload still runs with values read at start from an object rewritten later | 1d22d925 | arms_secret_rotation (0/0) | Principle general (env from Secret is fixed at start); detection is v1's check text. Worked in 1 of 4 Lite arms after the fix (final Jev 100; final Dec 0, lite6 11/45) |
| 16 | `bad_input_explanations` (`DATA_CLASS`, `repeated_failures`, `input_candidates`, `MAX_INPUTS=4`) | one bad item in an input blocks a consumer; origin `input/<value>` | 6400cd46 | kafka_poison_pill (blog failure; label origin `KafkaTopic orders-fulfillment`) | Fitted. Outside Lite it fills option slots with nonsense: held5_incorrect_image and tgt_missing_env offered "One bad item in kubernetes / cumulative / otel-collector / flagd, which frontend reads" (4 of 6 options) |
| 17 | `own_setting_explanations` + `own_settings` filter (`POD_PREFIX_RE`, markers) | a broken component's own wrong setting (v1's configuration findings) | 3dc3e053, c25fde1a | arms_duplicate_pvc_mounts_social_network (0/11), rolling_update (89/78) | Principle general (wrapper over v1's checks). "Observability included" exists for jaeger in duplicate PVC: fitted. Observability handling is inconsistent: rules 2, 11 and 18 skip observability components, rules 1, 6 and 17 do not |
| 18 | `partial_explanations` | "the fault is in X, mechanism unknown" | 6400cd46 | none | General |
| 19 | `covered` set | own-setting suppressed when another object's change/acts-on already impacts the component | 3dc3e053, c25fde1a | duplicate PVC / rolling update | Ranking heuristic |
| 20 | `timing()` support-only, `ONSET_TOLERANCE_S=10` | a change before onset supports; after onset is never held against it | 6400cd46 | onset noise | Design choice; makes the check uninformative (section 3) |

### decide.py, agent.py, report.py special cases
| Rule | What | Added | Reacting to | Class |
|---|---|---|---|---|
| `specific_groups` / `GENERIC_GROUPS` in `shortlist` | rank "mechanism evidence" (errors:, linked:, saturation:, auth:, quiet:, rejected:, repeat:) above timing/symptoms/config | 1d22d925 | secret_rotation, valkey_auth | Fitted ranking; creates a victim bias (section 3) |
| `how_to_decide` victim sentence | "a component that only fails because something it calls fails is a victim" | 6400cd46 | v1 wording | General |
| `LIMIT_RULE` | a limit is the cause only if too low for normal needs; a change that raises use is the cause | 066c4d2f ("v1's limit-vs-change rule") | likely lite6 env_variable_shadowing, labeled resource_limits (Jev 78); not stated in the commit | General (ported from v1) |
| `characterize` = v1's characterization request | key fact + fault category | 676024e9, 6fec2c91 ("v1's key-evidence step", "v1's characterization") | the weakness listed in `jev-v2-results.md`: accepting "fault in X, mechanism unknown" (final retry collapse, Decisions 45) | v1. From held2 on, 7 of 10 v2 arms reported this v1 fact as the mechanism |
| `PRE_READ=6` | read candidates' components before the first question | 6fec2c91 | same weakness (picked without reading detail) | Kills the go-back loop (section 4) |
| `_look_closer` routes | unsure: read top-2 shortlisted; none: read two most affected unread | f0f42805 | arms_kafka_poison_pill (11/11, re-read the same component) | Fix of a v2 bug |
| `_fault_object` | v1's "Fault object" line for an outside object linked to the root-cause workload | 6fec2c91 | port of v1's report line | v1 |
| `WORKLOAD_KINDS`, `COMPONENT_LEVEL`, `GENERIC_MECHANISM` | one-component causes list only the origin as impact; generic mechanisms replaced by v1's key fact | c798a1b8 ("v1's format"), 30dd021e | held2_service_port_conflict (sample A; D3 0.33 for both v2 arms, 66; held5 rerun D3 0.67, 78) | Grader shaping; scope rule is general |
| `describe_object` for `interaction/` and `input/` | pseudo-objects rendered as "the interaction between ..." / "input source ..." | 6400cd46 | retry collapse, kafka labels | Fitted |
| `4a9b25e0` | the first decision always runs | 4a9b25e0 | trigger not identified | Bug fix |

### Commit pattern (fact)
16 commits in 17 h 42 min (10-18 19:08 to 10-19 12:50). 12 of the 15 after the first add or tune a rule right after
a specific run failed (8912490e and 66b1f609 are follow-ups of the previous commit, 4a9b25e0 a bug fix); 6 of those 15
messages say they port v1 behavior ("v1's key-evidence step", "v1's
characterization", "v1's format", "v1's victim rule", "as in v1", "v1's limit-vs-change rule"); the next commit after the
run code (29206c54, "report like v1") continues the same way.

Classification count (the 20 patterns.py rows above): general principle 11 (1, 2, 3, 6, 7, 9, 10, 11, 15, 17, 18), fitted
to a specific fault 6 (5, 8, 12, 13, 14, 16) plus two fitted add-ons (the observability exception in 17, the
`specific_groups` ranking), plumbing/heuristic 3 (4, 19, 20). **Opinion**: the general ones are almost all thin wrappers around v1's checks; the knowledge that is
v2's own is mostly the fitted part.

---

## 3. How supports / contradicts / unknown are computed, and whether they discriminate

### How (fact)
Every status is fixed in `patterns.py` when the candidate is built, from the same fields that caused it to be built.
Nothing is checked later: `Prediction.check` ("probe", "metrics") is set in 3 places and read nowhere;
`Explanation.evidence` is never filled. Only non-unknown predictions are shown to the model ("Checks: ... (supports)").

| Prediction | Status rule | Why it cannot discriminate |
|---|---|---|
| timing: "X was made before the symptoms began" | supports if change time <= onset + 10 s, else unknown; never contradicts (`patterns.py:96-102`) | true of every change made before onset, harmless ones included |
| own_symptoms: "X shows symptoms of its own" | supports if unhealthy, contradicts if healthy | true of the cause and of every victim |
| dependency: "still-occurring errors of callers name X" | always supports | it is the condition that created the candidate |
| dependency: "X shows failures of its own" | supports if unhealthy | true of victims in the middle of a chain |
| configured dependency: both predictions | always supports | both are the creation conditions |
| acts-on: "the checks link K N to targets" | supports when targets exist | creation condition |
| amplify: "errors ... are timeouts or overload" | always supports | creation condition, and the class includes `Connection refused` |
| amplify: "X is saturated" | supports if any signal matches `SATURATION_RE` (cpu, limit, latency, queue, slow...) | broad word match |
| bad-input: "fails repeatedly on the same item" | supports if `repeated_failures` | creation condition |
| arrival: "appeared just before the symptoms" | always supports | creation condition |
| hidden-state: auth / quiet / "config was not changed" | from caller error classes and template diff | creation conditions; the deciding probe never runs |
| stale-read: "a server rejects what X presents" | supports if a "server ... rejects" signal exists | real second signal (one of the few) |
| victim: "X only fails because Y, which it calls, is broken" | contradicts | the only contradiction that encodes reasoning; 4 of 56 contradictions shown |

Counts over all 65 decision requests on 30dd021e/066c4d2f (64 first rounds + 1 second round; 368 options): 84 options carry no checks; the shown
statuses are 432 supports and 56 contradicts; 52 of the 56 contradicts are "X shows symptoms of its own" on a healthy
component, 4 are the victim rule. The two most frequent checks ("made before the symptoms", 122; "shows symptoms of its
own", 96) are generic by the code's own definition (`GENERIC_GROUPS`).

### Do they separate the true cause from distractors? (measured)
For each first decision on 30dd021e/066c4d2f (lite5, lite6, held4 dns, held5, held6, tgt), the true origin was taken from the Lite labels, or for other faults from an
arm the judge gave D1 = 1.00 (6 requests had no such arm and were skipped). Compared: best option naming the true origin vs
best wrong option, by (no contradiction, number of supports).

| | Requests | True cause ahead | Tie | True cause behind |
|---|---|---|---|---|
| Lite (lite5, lite6) | 34 | 18 | 10 | 6 |
| Sample A + targeted | 22 | 10 | 12 | 0 |
| All | 56 | 28 | 22 | 6 |

Caveats: name matching treats `configmap/url-shorten-mongodb` and `deployment/url-shorten-mongodb` as the same
origin, so held6_auth_miss_mongodb counts as "ahead" although v2 picked the wrong kind and lost D1. tgt_update counts one
MongoDB deployment as true; the other three bumped ones have the same profile.

Concrete cases where the checks are equal or point the wrong way:
- **tgt_update_incompatible_correlated** (6 MongoDB images bumped to `mongo:8.0.14-rc0`): offline `build_explanations`
  gives 25 candidates, 12 of them change candidates for the 6 bumps (per-field and per-object duplicates). The shortlist
  ranks `dependency:deployment/rate` (a victim; specific 1, supports 2) and `amplify:search->rate` (spurious; specific 1)
  first and second, above every change (specific 0), because "errors name X" counts as mechanism evidence and a change
  can never earn any. Two of the six bumps did not reach the options. All four offered bumps carry the identical checks
  "made before the symptoms (supports); shows symptoms of its own (supports)"; the victim has as many supports (2). Jev: victim 0.44, the
  four bumps 0.08 + 0.26 + 0.01 + 0.01 (vote splitting). v2 scored 0 and 11; v1 scored 89 and 89.
- **tgt_missing_env_variable_astronomy_shop**: options = 4 bad-input fabrications (input "kubernetes", "cumulative",
  "otel-collector", "flagd"), `dependency:daemonset/otel-collector-agent` (an observability daemonset whose only change is
  the harness `restartedAt` annotation, with 2 supports), and the true `change: CART_ADDR removed` (2 supports). Jev 0.39 vs
  0.38, picked otel-collector, scored 11.
- **held5_wrong_service_selector_astronomy_shop**, **lite6_env_variable_shadowing**, **lite6_unschedulable**,
  **lite6_valkey_auth**, **lite6_secret_rotation** and **lite6_finalizer_deadlock**: tie, with 1-3 wrong options at the same profile.
- **lite6_kafka_poison_pill**: all 5 wrong options have as many or more supports than the true `input/orders-fulfillment` (best wrong 2 vs 1);
  the model still picked it (100). On Lite the model often overrides the checks correctly, which also means the checks
  are not what decides.
- **lite6_network_policy_block**, **lite5_search_rate_retry_collapse**: the true option is behind on checks.

**Conclusion (fact-based)**: the statuses mostly restate "this candidate exists"; supports are near-universal, a
contradiction almost only means "healthy". The ranking rule `specific_groups` systematically puts dependency (victim)
and amplify candidates above change candidates.

---

## 4. Dead or ineffective machinery, budget, tokens

### Go-back loop (counted over every v2 arm in runs-index.tsv)
| v2 version | v2 arms | first round not `accept` | arms with a 2nd round |
|---|---|---|---|
| 6400cd46 (arms_) | 34 | 13 | 13 |
| 3dc3e053 (rerun_) | 4 | 3 | 3 |
| 1d22d925 / 272123ae (final_, held_) | 40 | 11 | 11 (one had 3 rounds) |
| 6fec2c91 .. 066c4d2f (after the pre-read) | 84 (2 crashed: lite5_finalizer) | 26 | **2** |

Fact: before 6fec2c91 the go-back ran whenever the model was unsure. 6fec2c91 added the pre-read of the same components
the `check` route reads, so from then on the model was unsure in 26 of 82 arms and a second round ran in 2
(held3_valkey_memory arm0, held5_valkey_memory arm1; both still failed). (The README says 1 of 56; my count differs because
it covers every post-6fec2c91 arm.) Since then:
- `route == "check"` is a no-op; `CONFIDENT_P`, `max_requests=8` and `wall_budget_s=120` never bind (max 6 requests, 12 s).
- `uncertain` only adds the line "Confidence: low; the investigation budget ended ..." to 15 of 52 arms on 30dd021e and 5
  of 8 on 066c4d2f; the claim about the budget is false. **Opinion**: it may cost D2 points with the judge; not measured.
- When the two asks disagree, the leader is decided by averaging two order-dependent answers. Disagreement was 4/41 (Jev)
  and 6/41 (Decisions) arms; top probability < 0.6 in 13/41 for each model.

### Designed but never built (fact, grep of `clients/jev_v2`)
Evidence ledger with ids, typed graph, coverage per component, Prometheus range/trend reads, Jaeger, Loki, probes
(including the login check its own hidden-state chain asks for), contrast sets, discriminating check selection ("2 of 3
checks separate the top two"), two independent causes, the `mismatch`, `resource` and `invalid state` patterns, the loss
funnel and chain-coverage measurement, perturbation tests, ablation. `replay.py` does not re-read component detail, so it
is not faithful to live runs (its docstring says so).

### Tokens, requests, cost (per run, same snapshots; Jev arms unless noted)
| v2 version | runs | v2 tokens | v1 tokens | v2/v1 Jev | v2/v1 Dec | v2 req | v1 req |
|---|---|---|---|---|---|---|---|
| 6400cd46 | 17 | 10.7k | 35.9k | 0.30 | 0.30 | 2.8 | 2.5 |
| 1d22d925 | 20 | 9.6k | 35.5k | 0.27 | 0.31 | 2.6 | 2.5 |
| 6fec2c91 | 5 | 38.4k | 27.3k | 1.41 | 1.44 | 4.0 | 2.0 |
| c798a1b8 | 4 | 56.6k | 34.6k | 1.64 | 1.36 | 4.5 | 2.0 |
| 30dd021e | 26 | 39.8k | 34.0k | 1.17 | 1.25 | 4.0 | 2.3 |
| 066c4d2f | 4 | 49.1k | 45.8k | 1.07 | 1.02 | 4.0 | 3.2 |

Fact: the "3.7x fewer tokens" in `jev-v2-results.md` held only for 1d22d925. The pre-read and v1's characterization
step (6fec2c91) quadrupled v2's tokens; since then v2 uses 1.1-1.6x v1's tokens. Per diagnosis cost on 30dd021e: v2
$0.0017 (Jev) / $0.0028 (Decisions) vs v1 $0.0014 / $0.0022. Cost is negligible either way.

---

## 5. Complexity

Lines (`wc -l`) of the decision code (agent + patterns + decide + explain + report; arms/grade/replay excluded):

| Commit | time | agent | patterns | decide | explain | report | total | patterns.py functions | test functions |
|---|---|---|---|---|---|---|---|---|---|
| 6400cd46 | 10-18 19:08 | 198 | 353 | 101 | 57 | 48 | 757 | 16 | 14 |
| 1d22d925 | 10-18 22:02 | 199 | 456 | 108 | 64 | 48 | 875 | 20 | 18 |
| 30dd021e | 10-19 09:01 | 296 | 596 | 156 | 64 | 80 | 1,192 | 26 | 23 |
| 066c4d2f | 10-19 12:50 | 299 | 663 | 172 | 64 | 80 | 1,278 | 29 | 27 |

- +69% total and +88% in patterns.py in under 18 hours; 13 candidate builders, 1 post-check, 1 ranking rule, 34 module
  constants/regexes across the five files (17 in patterns.py), 7 imported v1 word lists.
- v2 sits on all of v1: `clients/jev_diag` is 8,708 lines (collector 2,509, tree 1,094, classifier 958, derive 786, checks
  560, ...), unchanged since the port in 6400cd46. v2 calls into v1 for collection, detail reads, the evidence list,
  the characterization questions, the budget fit, the category glossary and the client.
- Growth is additive: no rule was ever removed; each failure added a builder, a regex or an exception
  (observability included here, excluded there). **Opinion**: this is the same growth path v1 took (v1's
  `derive.py`/`checks.py` are themselves fault-shaped rules), now duplicated in a second layer.

---

## 6. The design bet, and whether the evidence supports it

### The bet (from `jev-v2-design.md`, `jev-v2-final-design.md`)
"The model is not the main limit; the pipeline's shape is." Code can build a small set of *complete* candidate
mechanism chains from *generic* patterns over the evidence; code checks predictions; the decision model only picks among
complete chains; the report is a template of the picked chain. Plus: never lose a fact, add time-series evidence, go back
when unsure.

### What the evidence says (facts)
1. **The chain vocabulary is the Lite answer key.** The patterns are the label families of the 17 dev faults, two of them
   with pseudo-origins invented to match two labels. On Lite (lite5/lite6), 30 of 34 v2 arms reported a v2-built mechanism; on
   sample A (held4 dns, held5, held6) 15 of 24 and on the targeted set 3 of 4 reported v1's characterization fact
   instead, because no specific pattern won.
2. **Picking among complete chains works when the right chain is offered and nothing else looks like it** (Lite retry
   collapse, edge filter, kafka: v2 89-100 where v1 failed). That part of the bet has support, but only on faults the
   chains were written for.
3. **Unseen faults break the generator, not the picker.** Fitted builders fire anyway and crowd the six slots (4 of 6
   bad-input fabrications in two runs; amplify on `Connection refused`), victims outrank changes by construction, and
   one correlated change (6 image bumps) becomes 12 candidates, of which 4 reach the six slots. The model then picks between options whose checks are identical.
4. **The new evidence never arrived.** v2 sees exactly v1's facts (plus v1's detail on up to 6 components). The design's
   own diagnosis ("the pipeline collects the right fact, then cuts it, hides it, or gives no option that uses it") was
   addressed only by re-routing v1's facts. Facts v1 cuts stay cut for both: in held5_service_port_conflict the raw kubectl
   output of the same run has `hostPort: 9100`, but v1's detail view keeps only `containerPort` and `name`
   (`jev_diag/investigate.py:100`), so every arm lost D2-Q2 ("does not identify the hostPort 9100 binding"). The
   runtime password in valkey_auth needs a probe that was never built (`jev-v2-results.md`).
5. **Results**: same-snapshot pairs v2 vs v1 (same model): Lite (lite5/lite6, 30dd021e) better 11 / worse 4 / equal 19;
   sample A (held4-held6, 13 runs on 2f3ee19f-066c4d2f, some faults twice, tuned on) better 4 / worse 6 /
   equal 16; targeted set (chosen for v2) better 0 / worse 4. Identical mechanism line: Lite 1 of 34, sample A 11 of 26,
   targeted 0 of 4.
6. **The go-back that was meant to escape a wrong shortlist is dead**, so a bad top-6 is final.

**Opinion**: v2 rests on two bets. (a) "A small closed set of hand-written generic patterns can produce the right
complete chain for unseen faults": refuted by the data; 13 builders did not cover sample A, every miss added another
builder, and the fitted ones actively hurt on new faults. (b) "Picking among complete chains beats picking a component
and then a fact": neither refuted nor supported. When the right chain was offered on unseen faults (tgt_missing_env's
CART_ADDR change, tgt_update's image bumps, held5_incorrect_image's image change) it sat among fitted distractors and
victims with equal checks, so the picker was never tested cleanly. On Lite the model sometimes overrode misleading checks
correctly (lite6_kafka), which suggests the model can judge plausibility from the state better than the code's checks.
As built, v2 is v1 plus a Lite-shaped re-ranking layer.

### What is genuinely valuable and general (keep in a redesign)
- **The arms harness** (`arms.py`, `grade.py`): several pipelines on one snapshot, same judge, every request saved.
  Paired comparison removes collection noise; it is how this audit could measure anything. Keep, and add: record the
  code commit in each run file (today it must be inferred from shell scripts).
- **Order-debiased asking** (`decide.pick`: neutral labels, shuffled, asked twice, averaged). Cheap and general; also
  measures model instability. Keep as a primitive; use disagreement as a signal, not only for averaging.
- **One candidate per changed field** (split multi-field revisions) and "none of these" + "mechanism unknown" options.
  General. Must add grouping of identical changes across workloads and a harmless-change filter.
- **The victim rule as code** (contradiction when a failing caller calls something broken itself). General SRE
  reasoning; make it multi-hop and base it on call edges, not word lists.
- **Scope rule in the report** (a one-component cause lists only itself as impact; callers are evidence). General and
  grader-relevant (D3).
- **Naming both the workload and the outside object** (v1's "root cause component" + "Fault object"): held6_auth_miss shows
  that choosing one (v2 picked the ConfigMap) loses D1 when the key wants the other. Keep v1's both-named form.
- **Tokens are not a constraint** (< $0.004 per diagnosis); do not trade evidence for tokens.

### What should not survive
Rules 5, 8, 12, 13, 14, 16 and the observability exception in 17; the `specific_groups` ranking; build-time "checks" shown
to the model as if they were evidence; the pseudo-origins `interaction/` and `input/`; the dead go-back loop and the false
"budget ended" line; parsing v1's English sentences with regexes.

### Open / uncertain
- Whether the false "budget ended" line or the raw multi-kilobyte diffs in mechanism lines (edge filter: a whole Perl
  script) cost judge points: not measured.
- Run counts are single runs per fault; judge noise of ~11 points is visible (cronjob: same text, 100 vs 89).
- The ground truth for non-Lite faults was inferred from judge D1 answers, not from fault code (sample A/T code not
  read for this audit).
