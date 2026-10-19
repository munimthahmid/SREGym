# Review 2: are v2's tests good enough before live runs? (2026-10-19)

Scope. Branch `feat/jev-diag-v2` in `~/sregym/SREGym-pr-v2`, commits `ca3bd122..HEAD`. HEAD moved during the review
from `ae68e37e` to `e131dda1` (three report commits, dca2e34b, 85af8577, e131dda1; e131dda1 rewrote the report's subject
rules). Every result below was re-run on `e131dda1`. Tests read: `tests/clients/test_jev_diag_v2.py` (22 tests) and
`tests/clients/test_jev_diag.py` (v1, 26 tests, 31 cases).
Guards and strengths come from `review/strengths-review.md` (S1-S19, G1-G19).

How it was checked (repo untouched, `git status` clean, no model calls).
- Each commit's source change was undone in a scratch copy and its own tests re-run ("revert check").
- 40 small deliberate breaks ("mutations") were made one at a time in a scratch copy of HEAD, each followed by a run of
  the v2 test file, to see which breaks the tests notice.
- 8 new tests and 3 small edits were written and run against HEAD. Every failing one was then run against a scratch
  copy with a small fix applied, to show the test is right and the fix is small.
- v1's test file was run against v2's copied modules (import paths swapped) in the scratchpad.

---------------------------------------------------------------------------------------------------------------------
## 0. Short version

1. **Six bugs, each shown by a failing test** (section 1). The two that matter most for the live runs: a client/server pair
   that was already decided is asked again by the second-cause step, which can add the losing side as a "second
   independent cause" or flip the answer (the secret_rotation shape); and a model error after an origin is confirmed
   throws that origin away and submits the code-only guess instead.
2. **The v2 tests check each feature's main path and little else.** Of 40 small deliberate breaks, the v2 tests caught 5
   (3 of them in the report). Nothing in the decision tree's new branches (tie-break, second cause, split triage) is
   pinned beyond one example each; 0 of 19 breaks in `tree.py` were noticed.
3. **v1's tests do not touch v2.** They import `clients.jev_diag.*`, never `clients.jev_diag.v2.*`. v2's copies of the
   collector, derive, checks, changes, investigate and classifier have almost no tests of their own. Run by hand against
   the v2 copies, all 31 v1 test cases pass today, so a 7-line runner file can keep that true (section 6).
4. **One existing test protects nothing.** `test_a_revision_made_while_deploying_is_not_a_change` passes with its change
   undone (no pinned clock, and its second assert accepts `None`).
5. **v1 strengths with no test anywhere (v1 or v2):** the ordered fallback chain, the login-rejection client scoring, the
   telemetry demotion and workload-before-cluster-node queue order, error recency and warm-up cuts, linked fault-object
   choice, and state trimming of the new keys. Proposed test 8 covers the queue order.
6. **Process.** The eval worktree `~/sregym/SREGym-v2eval` lacks the last 8 commits (c0cca9bb onward); an offline replay
   there today would grade old code.

---------------------------------------------------------------------------------------------------------------------
## 1. Bugs found by failing tests (most serious first)

Severity is likelihood times impact. Each test is in section 6, ready to paste. All seven failing tests (six bugs plus
edit E3) pass once the small fix described is applied in a scratch copy; the full v2 file still passes too, except the
existing wait test noted under bug 4.

### Bug 1 (high). A decided client/server pair is asked again, and can come back as two causes
- Where. `tree._diagnose`, the second-cause block after the loop. The confirmed-origin tie-break is guarded by
  `not pair_decided`, the second-cause block is not.
- What happens. For an auth or RBAC cause, v2 (like v1) examines the "other side" and lets `pair_node` pick the faulty
  side. Then the second-cause step finds the losing side "unexplained" (its own login-rejection lines, origin >= 0.6
  from the earlier step) and asks a tie-break between the two again. With no error line linking them, "both" is
  offered, and a "both" answer reports the server as a second independent cause. With a link, the tie-break can still
  flip the pair's answer. This is the secret_rotation shape (postgresql rejects logins, product-catalog holds the stale
  credentials), one of the 5 hard cases.
- Failing output. `test_a_decided_client_server_pair_is_not_reported_as_two_causes`: `d.second` is `Diagnosis(component=
  'deployment/db' ...)`, expected `None`. The trace shows `pair:deployment/db|deployment/client` followed by
  `tiebreak:deployment/client|deployment/db`.
- Fix (1 line). Skip the second-cause step when `pair_decided`, or leave the pair's other side out of the frontier.

### Bug 2 (high-medium). A model error after an origin is confirmed throws the origin away
- Where. `IterativeDiagnoser.diagnose` wraps all of `_diagnose` in one `try/except Exception`.
- What happens. Any error in a later optional call (second-cause examination, tie-break) replaces the whole run with
  `code_only_diagnosis`, which ranks by evidence kinds and ignores everything the model already confirmed. Example: the
  model confirms `a` at 0.95, the credit runs out on the next call, the report names `b` (it has a "change" kind).
  Likely causes in the planned runs are HTTP 402 at the end of the credit, context-length errors on the three
  small-context models (Clef, Clef Flash, Kev), and malformed answers (a missing question key raises `KeyError`). The
  client retries only 408/409/429/5xx and timeouts.
- Failing output. `test_a_model_failure_after_an_origin_is_confirmed_keeps_that_origin`:
  `assert 'deployment/b' == 'deployment/a'`.
- Fix (small). Catch errors around the optional late steps and keep the concluded answer (the scratch fix wraps the
  second-cause block); better, have the code-only path start from any confirmed origin.
- Related test risk. Because the catch also swallows programming errors, a bug in `_diagnose` turns into a quiet
  code-only report in tests and live runs. Tests that call `diagnose()` should assert the model path was used
  (`"unavailable" not in str(d.investigation["fallback"])`); proposed test 7 does.

### Bug 3 (medium-high). A Deployment rollout restart is never recognised as restart-only
- Where. `changes.restart_only` requires every diff line to contain `kubectl.kubernetes.io/restartedAt`. A ReplicaSet's
  pod template always carries its own `pod-template-hash` label, so every Deployment revision diff also contains
  `pod label pod-template-hash: a -> b`.
- What happens. A plain `kubectl rollout restart` of a Deployment becomes "pod template changed Ns ago" (a `change`
  evidence kind, eligible for the nearest-change flag) instead of "rolling restart" (a symptom). This is the noise R9
  in the strengths review warned about; the review also notes product-catalog's revision in secret_rotation is
  exactly restartedAt plus pod-template-hash, so the fix changes what triage sees on a hard case. Check that case in
  the offline replay before and after. DaemonSet and StatefulSet restarts are not affected. The existing test passes
  only because it hands `restart_only: True` in directly.
- Failing output. `test_a_rollout_restart_of_a_deployment_is_restart_only`: `assert False` on the first assert.
- Fix (1-2 lines). Ignore `pod-template-hash` lines in `restart_only` (or drop that label in `template_diff`, since
  `report.changed_values` already filters it).

### Bug 4 (medium). The adaptive wait ends at 60 s whenever any pod restarted during start-up
- Where. `driver.abnormal_pods` counts a pod as abnormal when any restart count is above 0.
- What happens. A pod that restarted once while the app started (its database was not up yet) and has been Ready
  since is "abnormal" in every sample, so the wait ends at the first poll, 60 s, for every fault, including faults that
  show only in logs, which the docstring says wait the full 120 s. The strengths review counted settled start-up
  history on 50 component instances over 45 snapshots, so this is common. Side effect: the trend baseline is now the
  45 s sample, so an early exit leaves a 15 s trend window instead of v1's 45 s, and "restarted N more time(s) in the
  last Ns" lines (quoted by the judge under D3-Q3) will appear less often.
- Failing output. `test_adaptive_wait_does_not_count_a_restart_from_before_the_fault`: `assert 60.0 == 120`.
- Fix. Count a pod only when it is not Running/Succeeded, not Ready, or its restarts grew since the first sample (add a
  per-pod ready flag to `trend.sample_from_objects`). The existing test
  `test_adaptive_wait_reads_early_once_the_same_pods_stay_abnormal` then needs its crash sample to say the pod is not
  ready, for example `{"phase": "Running", "ready": False, "restarts": {"a": 3}}`; its current sample cannot be told
  apart from a settled pod.

### Bug 5 (medium). Telemetry lines push the victim facts out of the evidence list
- Where. `tree.detail_evidence` starts the "dependencies" group with the telemetry lines (`dep_items =
  list(detail["telemetry"])`), and that group keeps only 4 reserved slots.
- What happens. When telemetry is reachable and the rest of the evidence is long (about 21+ items), the 4 slots go to
  metric lines and "this component's still-occurring error lines refer to its dependency X" and "dependency X looks
  healthy on its own" are dropped. Those two lines are how v1 reasons about victims (S7). Measured in scratch with 30
  signals and 7 telemetry lines: both victim facts gone, 4 telemetry lines kept.
- Failing output. `test_telemetry_lines_never_push_the_dependency_facts_out_of_the_evidence`: `assert False`.
- Fix (2 lines). Append telemetry after the dependency facts.

### Bug 6 (low-medium). Healthy or old outside objects become cluster findings
- Where. `outside.collect_outside`.
- What happens. Every Ingress that routes to an app Service becomes a finding ("routes / to Service front:80"), even
  with ready endpoints and no write since creation; the module docstring says only a missing backend, no ready
  endpoints, or a recent write should qualify. A kube-system DaemonSet or CronJob written within the last hour but
  before the app was deployed (a leftover from an earlier problem) becomes an undated finding "kube-system DaemonSet
  written", because the finding is made before `rank_changes` drops the pre-deploy write. A permanent finding puts the
  cluster node in the queue on every run of that app, the leftover-object trap the strengths review (S10, G11) warns about.
- Failing output. `test_outside_objects_with_nothing_wrong_are_not_findings`: `assert ['Ingress', 'DaemonSet'] == []`.
- Fix (few lines). Add the Ingress finding only with a trouble signal or a write after deploy; add kube-system findings
  only when the write is after the app's earliest creation time.

### Also failing (edit E3, medium-low). After a split triage, a strong origin walks on through the queue
- When the two triage asks disagree and the first pick is confirmed (even at 0.95) but the second pick turns out to be
  a victim, the loop does not conclude; it keeps examining queued candidates until the queue or the 18-step budget
  runs out, then reaches the same answer through the fallback ("most likely origin among investigated components").
  Each extra examination is another chance for a yes-leaning model to confirm a wrong candidate, which then goes to a
  tie-break and can be reported as a second cause (shown in scratch: `a` 0.95, `b` victim, `c` 0.7, "both" gives
  second cause `c`).
- Failing output (E3): `'most likely origin among investigated components' is None` fails; steps were
  `[a, b, c]`, expected `[a, b]`.
- Fix (5 lines). After examining a split pick that is not an origin, conclude the strongest confirmed origin when no
  split pick is left.

### Smaller issue without a test: `report.quote` cuts the head off unprefixed lines
`quote` drops everything before the first ": " in the first 60 characters, meant for the "container: " prefix. Lines
from `previous_container_logs` and call-path examples have no such prefix, so "KeyError: 'DB_HOST'" becomes
"'DB_HOST'" and "... ERROR failed to load config: open /etc/app.yaml: no such file" becomes "open /etc/app.yaml: no such
file". Low severity; the Mechanism line loses the error type. Strip only a known container prefix.

---------------------------------------------------------------------------------------------------------------------
## 2. Test-quality findings

| # | Finding | Severity |
|---|---|---|
| Q1 | `test_a_revision_made_while_deploying_is_not_a_change` is vacuous. No pinned clock, so both records are past the 1 h horizon and `None`; the second assert accepts `None`. It passes with commit bbe5406d undone. Edit E1 pins the clock. | medium (the code is right today; nothing keeps it right) |
| Q2 | v1 tests never import `clients.jev_diag.v2.*`. v2's copied modules are exercised only by the 21 v2 tests. All 31 v1 cases pass against the v2 copies when run by hand; a 7-line runner keeps that (section 6). | medium |
| Q3 | `diagnose()` swallows every exception into the code-only report, so a code bug can pass a test that only checks the component. Diagnose-level tests should assert the model path was used. | medium |
| Q4 | 35 of 40 small breaks went unnoticed (section 4). The proposed set catches 9 more, plus the six bug fixes. | - |
| Q5 | Commits 37bd9d0c, aa6241c9 (driver split), 5c134aa6 (probe on by default) and 85af8577 have no test of their own; 85af8577's input-by-value subject is now covered by e131dda1's test. | low |
| Q6 | The eval worktree lacks every commit from c0cca9bb to e131dda1 (8 commits) and has uncommitted edits (agents.yaml, grade.py). Merge before any offline replay. | process |

---------------------------------------------------------------------------------------------------------------------
## 3. Coverage of v1 strengths and regression guards in v2

"Covered" means a v2 test would fail if the behaviour broke. v1 tests count only for v1 code.

| Strength (guards) | Protected in v2 by | Status |
|---|---|---|
| S1 whole-app triage (G9, G15, G19) | `test_v2_triage_question_matches_v1_on_the_same_snapshot`, `test_when_the_two_triage_asks_disagree_..._stronger_origin_wins` | Partly. The second ask's reversed order is not checked. G9, G19 need the replays. |
| S2 written prior (G10) | `test_v2_triage_question_matches_v1_on_the_same_snapshot` (v2 question text equals v1's) | Covered for wording |
| S3 detector library (G1, G3) | `test_probe_description_carries_timing_with_defaults_for_unset_fields` only | NOT covered for v2's copy. Stale Secret read, RWO PVC, quota, webhook diff and duplicated env have no test in v1 or v2. |
| S4 change detection (G2, G14) | `test_revision_diff_without_a_spec_write_is_a_change_and_a_restart_is_not`, `test_one_change_on_several_workloads_is_reported_as_one_cause`, `test_a_revision_made_while_deploying_is_not_a_change` (vacuous) | Partly. Restart detection from real ReplicaSets NOT covered and broken (bug 3). |
| S5 change vs onset (G2, G11) | `test_a_change_made_before_the_application_existed_is_dropped` | Partly. Onset estimate and "telemetry change never nearest" NOT covered. |
| S6 recency, warm-up cut, telemetry split, trend (G4) | none | NOT covered (no test anywhere for `signature_recency`, `split_warmup_lines`, `apply_trend`) |
| S7 victim reasoning (G13, G9) | `test_a_line_naming_several_components_points_at_the_one_it_called` (the helper alone) | Partly. Its use inside `classify_logs`, `dependency_state` and the victim-chain fallback NOT covered; bug 5 can drop the victim facts. |
| S8 login rejections point at clients (G13, G18) | none | NOT covered (`server_login_rejections`, `other_side`, `pair_node`). Proposed test 2 touches the pair path. |
| S9 conditional telemetry prior (G12, G18) | `test_namespaces_the_app_addresses_are_read_too` (telemetry namespace skipped), `test_telemetry_lines_come_from_the_team_tools_and_skip_empty_results` | Partly. Queue demotion NOT covered (proposed test 8). Code-only report and second-cause step skipping telemetry NOT covered. |
| S10 workload first, linked fault object, carrier lead (G11, G8) | `test_report_names_the_owning_component_through_its_configmap_and_an_outside_object_first` (kube-system ConfigMap leads) | Partly. Cluster node after the top workload NOT covered (test 8). In-namespace carriers leading NOT covered (E2). `select_fault_object` and `finding_linked` have no test anywhere. |
| S11 options built by code (G19) | none for v2 (v1 question tests run on v1 only) | NOT covered for v2's copy (pass by hand) |
| S12 verbatim key fact (G7) | `test_report_leads_with_the_changed_workload_and_has_no_fault_type_line` | Partly. With a fault object the fact can be replaced by the object's signal unnoticed (E2 covers). |
| S13 generous report sections (G8) | `test_report_states_only_what_the_facts_show_for_a_job_that_never_completes` | Changed by design. v2 prints Root cause, Mechanism, Details, Effect, Observed, Affected; warning events, the crashed run's last lines and alerts are no longer printed. A deliberate trade to confirm on Lite. |
| S14 dual naming (G8) | `test_report_names_the_owning_component_...` | Covered (ConfigMap and outside object) |
| S15 few calls (G16) | none | NOT covered. v2 always asks triage twice (at least 3 requests, v1 2); no test pins the request count. |
| S16 stable reruns (G17) | live only | Live check |
| S17 ordered fallback, always answers (G6) | `test_without_the_decision_model_v2_still_reports_from_code` | Partly. The ordered fallback (origin >= 0.4, victim chain, `other`, top non-telemetry) has no test anywhere; a late model error discards a confirmed origin (bug 2). |
| S18 state trimming (G5) | none for v2 (v1 budget tests run on v1 only) | NOT covered for v2's copy; new keys (`call_paths`, `outside_objects`, telemetry lines) are in no trim test |
| S19 fail-soft, replayable (G6) | `test_v2_reads_the_cluster_through_v1s_single_kubectl_runner`, telemetry off-switch test | Partly. `outside.py` and the related-namespace read under kubectl errors NOT covered. |

Guards by tier. Tier A guards (G1-G8, G18, G19) are code checks, but G1, G2, G3 and G19 are defined over saved Lite
recordings, so they need the offline replay ("S1 check" is still unchecked in IMPLEMENTATION.md); the unit tests above
cover only small parts of G2, G6, G7, G8 and G14. G18 (generality lint) exists for `clients/jev_agent` only, not for
`clients/jev_diag/v2`. Tier B and C guards (G9-G17) are model re-asks and live runs and are outside unit tests.

---------------------------------------------------------------------------------------------------------------------
## 4. Does each commit's test catch its change? (revert check, plus mutations)

| Commit | Test added | Fails with the change undone? | Not caught (mutation survives) |
|---|---|---|---|
| 065032a6 copy of v1 | 3 plumbing tests | yes (no v2 package) | the copied modules themselves (Q2) |
| 37bd9d0c, aa6241c9 driver split | none | - | `make_diagnoser` wiring |
| 8008d24d revisions as changes, restarts not | 2 | yes | real restart detection (bug 3); "rolling restart" counted as a symptom |
| b4c9478f probe timing, grace period | 1 | yes | grace-period evidence line (`termination_grace_seconds`) |
| aba4f2f8 evidence slots | 1 | yes | order inside the groups (bug 5 came later with cf354c03) |
| e1a65de7 relayed names | 1 | yes, by import error | the 3-line use inside `classify_logs` |
| 6fc31a5d report | 2 | yes, by import error | (report rewritten since; see e131dda1) |
| 75ddd377 code-only report | 1 | yes | a failure after a confirmed origin (bug 2) |
| 83485d42 adaptive wait | 1 | yes | "same pods twice" rule; settled restarts (bug 4) |
| fa5d98fd outside objects | 2 | yes, by import error | findings feed into `cluster_findings`; infra namespaces skipped; noise (bug 6) |
| bbe5406d deploy-time revision | 1 | **no, passes** (Q1) | the whole change |
| c0cca9bb same change on N | 1 | yes | the 10 s window |
| 52325dad triage twice | 1 | yes | reversed second ask; strong origin plus split; walk-on (E3) |
| 5c134aa6 probe on by default | none | - | the default |
| cf354c03 telemetry | 1 | yes | telemetry order in evidence (bug 5) |
| ae68e37e call paths, tie-break, second cause | 2 | yes | "both" offered when linked; "both" threshold; unclear answer keeps the stronger; pair interplay (bug 1); second-cause filters (telemetry, judged victims, step budget); `explained_by` same-change and fault-object users; call path in evidence; loop needs a capped callee; timeout lines only |
| dca2e34b report states only facts | 1 | yes | - |
| 85af8577 Observed line, input by value | none | - | (covered later by e131dda1's test) |
| e131dda1 report relation rules | 1 | not re-run (report rewrite) | "Service (selecting X)", in-namespace carrier lead, shared ConfigMap users, 10 s same-change window, restart-only kept out of details, telemetry lines never quoted, chosen fact replaced by the object's signal |

Mutation summary (40 breaks, v2 tests at e131dda1). changes.py 2 of 4 caught; tree.py 0 of 19; report.py 3 of 10
(blocked-input, driver and call-path subjects); derive, outside, paths, driver 0 of 7. With the proposed tests the
restart detection, deploy-time window, split with a strong origin, linked tie-break, unclear tie-break, queue
demotion, cluster-node order, in-namespace carrier and kept fact are caught too (9 more), plus the six bug fixes.

---------------------------------------------------------------------------------------------------------------------
## 5. Riskiest untested paths (no proposed test; ranked)

1. **`explained_by` links only through error text** (and same change, fault-object users). A victim whose link lives
   in an env address or config file (the review's tgt_update case, `rate` never marked a victim of `mongodb-rate`)
   counts as unexplained, gets examined, and with no link "both" is offered. This touches the hard case
   update_incompatible_correlated. Measure on the replay how often `second` is set on single-fault states (it should be
   about 0); consider adding env-address links (`_calls`) to `explained_by` and `link_facts`.
2. **Fallback chain order (S17).** `fallback()` (origin >= 0.4, victim chain, `other`, top non-telemetry) has never had a
   test in v1 or v2. Removing the victim-chain return goes unnoticed.
3. **`other_side` and `pair_node` (S8).** The credential and RBAC "other side" path that carried secret_rotation in v1
   has no test; picking the lower origin on an unclear pair answer goes unnoticed.
4. **Second-cause filters.** Telemetry components, components already judged victims, and the step budget are all
   skipped by `unexplained_frontier`; removing any of the three goes unnoticed.
5. **Report subject rules.** A Service fault object, a shared ConfigMap and the 10 s same-change window have no test
   (the blocked input, driver and call-path subjects do).
6. **Related namespaces.** `related_namespaces` adds every namespace named as `svc.ns.svc` in env (except infra and
   telemetry), and its workloads become triage options. A reference into `default` or a shared data namespace would
   add many components. Untested, including the infra filter.
7. **Code-only ranking** puts telemetry last; untested (a code-only report naming the otel collector is the S9 failure).

---------------------------------------------------------------------------------------------------------------------
## 6. Proposed tests (8 new, 3 small edits), ready to paste into `tests/clients/test_jev_diag_v2.py`

They use only helpers already in that file (`NS`, `_comp`, `_snap`, `_diag`, `_Answers`, `_two_faults`, `_run_wait`).
Result on HEAD e131dda1: tests 1-6 and E3 FAIL (the bugs above), tests 7-8, E1 and E2 PASS. Verified copy:
`<scratchpad>/review-tests/test_proposed_v2.py` (run from the repo with
`env PYTEST_ADDOPTS= uv run python -m pytest -q <that path>`).

```python
def test_a_rollout_restart_of_a_deployment_is_restart_only():  # 1 - FAILS today (bug 3)
    from clients.jev_diag.v2 import changes

    def rs(rev: int, h: str, annotations: dict, image: str = "i") -> dict:
        return {
            "metadata": {
                "name": f"web-{h}",
                "namespace": NS,
                "creationTimestamp": f"2026-10-19T07:5{rev}:00Z",
                "labels": {"pod-template-hash": h},
                "annotations": {"deployment.kubernetes.io/revision": str(rev)},
                "ownerReferences": [{"kind": "Deployment", "name": "web"}],
            },
            "spec": {
                "template": {  # the ReplicaSet's template carries its own pod-template-hash label
                    "metadata": {"labels": {"app": "web", "pod-template-hash": h}, "annotations": annotations},
                    "spec": {"containers": [{"name": "web", "image": image}]},
                }
            },
        }

    def restart_only(*replicasets) -> bool:
        comps = {"deployment/web": {"kind": "Deployment", "name": "web", "namespace": NS}}
        changes.attach_template_changes(comps, changes.revision_templates(list(replicasets), []))
        return comps["deployment/web"]["template_changes"]["restart_only"]

    restarted = {changes.RESTART_ANNOTATION: "2026-10-19T07:52:00Z"}
    assert restart_only(rs(1, "5d4f8", {}), rs(2, "7c9b6", restarted))
    assert not restart_only(rs(1, "5d4f8", {}), rs(2, "7c9b6", restarted, image="i2"))


def test_a_decided_client_server_pair_is_not_reported_as_two_causes():  # 2 - FAILS today (bug 1)
    from clients.jev_diag.v2.tree import IterativeDiagnoser

    server = {
        **_comp("db", "t"),
        "signals": ["server rejects logins for account app (12 lines, still occurring)"],
        "evidence_kinds": ["own_failure_logs", "symptoms"],
        "login_candidates": ["deployment/client"],
        "healthy": False,
    }
    client_comp = {**_comp("client", "t"), "signals": ["s"], "evidence_kinds": ["configuration", "symptoms"]}
    snap = _snap({"deployment/db": server, "deployment/client": client_comp, "deployment/c": _comp("c", "t")})
    triage = [{"deployment/db": 0.8, "deployment/client": 0.15, "deployment/c": 0.05, "other": 0.0}] * 2
    picks = {"fault_category": "credentials_or_auth", "faulty_side": "deployment/client", "fault_start": "both"}
    client = _Answers(triage, {"deployment/db": 0.9, "deployment/client": 0.95}, picks=picks)
    d = IterativeDiagnoser(client, fetch_detail=lambda s, c: {}).diagnose(snap)
    assert d.component == "deployment/client" and d.second is None


def test_a_model_failure_after_an_origin_is_confirmed_keeps_that_origin():  # 3 - FAILS today (bug 2)
    from clients.jev_diag.v2.tree import IterativeDiagnoser

    class FailsAfter(_Answers):  # the decision model stops answering after triage (2 asks) and one examination
        calls = 0

        def system_one(self, state, questions, **kwargs):
            self.calls += 1
            if self.calls > 3:
                raise RuntimeError("Decisions API HTTP 402: insufficient credits")
            return super().system_one(state, questions, **kwargs)

    snap = _two_faults(link=False)
    snap.components["deployment/a"]["evidence_kinds"] = ["configuration", "symptoms"]
    snap.components["deployment/b"]["evidence_kinds"] = ["change", "symptoms"]
    triage = [{"deployment/a": 0.8, "deployment/b": 0.15, "deployment/c": 0.05, "other": 0.0}] * 2
    d = IterativeDiagnoser(
        FailsAfter(triage, {"deployment/a": 0.95, "deployment/b": 0.9}), fetch_detail=lambda s, c: {}
    ).diagnose(snap)
    assert d.component == "deployment/a"


def test_adaptive_wait_does_not_count_a_restart_from_before_the_fault(monkeypatch):  # 4 - FAILS today (bug 4)
    from clients.jev_diag.v2 import trend

    pod = {
        "metadata": {"name": "a-1"},
        "status": {
            "phase": "Running",
            "containerStatuses": [{"name": "a", "ready": True, "restartCount": 1, "state": {"running": {}}}],
        },
    }
    settled = trend.sample_from_objects({NS: [pod]}, {})  # restarted once while the app started; Ready since
    assert _run_wait(monkeypatch, [settled] * 10) == 120


def test_telemetry_lines_never_push_the_dependency_facts_out_of_the_evidence():  # 5 - FAILS today (bug 5)
    from clients.jev_diag.v2.tree import detail_evidence

    comp = {**_comp("cart", "t"), "signals": [f"signal {i}" for i in range(30)]}  # a long list of settings/signals
    detail = {
        "telemetry": [f"cpu metrics: line {i}" for i in range(6)],
        "failing_targets": ["deployment/valkey-cart"],
        "calls": {"deployment/valkey-cart": {"looks_healthy_on_its_own": True, "pods_ready": "1/1"}},
    }
    texts = [e["text"] for e in detail_evidence(comp, detail)]
    assert any("refer to its dependency deployment/valkey-cart" in x for x in texts)
    assert any("deployment/valkey-cart looks healthy on its own" in x for x in texts)


def test_outside_objects_with_nothing_wrong_are_not_findings(monkeypatch):  # 6 - FAILS today (bug 6)
    from clients.jev_diag.timeutil import set_now
    from clients.jev_diag.v2 import changes, outside

    ingress = {  # routes to a Service with a ready endpoint, never written since it was created
        "metadata": {"name": "web", "namespace": NS, "creationTimestamp": "2026-10-19T07:00:00Z"},
        "spec": {"defaultBackend": {"service": {"name": "front", "port": {"number": 80}}}},
    }
    daemonset = {  # written at 07:40, ten minutes before the application was deployed (07:50)
        "metadata": {
            "name": "node-agent",
            "namespace": "kube-system",
            "creationTimestamp": "2026-10-19T07:00:00Z",
            "managedFields": [
                {"manager": "kubeadm", "time": "2026-10-19T07:00:00Z", "fieldsV1": {"f:spec": {"f:x": {}}}},
                {"manager": "kubectl", "time": "2026-10-19T07:40:00Z", "fieldsV1": {"f:spec": {"f:y": {}}}},
            ],
        }
    }
    items = {"ingresses": [ingress], "priorityclasses": [], "daemonsets": [daemonset], "cronjobs": []}
    monkeypatch.setattr(outside, "kubectl_items", lambda resource, ns, errors, **k: items.get(resource, []))
    comps = {
        "deployment/front": {
            **_comp("front", "2026-10-19T07:50:00Z"),
            "services": [{"name": "front", "ready_endpoints": 1}],
        }
    }
    set_now(changes.parse_time("2026-10-19T08:00:00Z"))
    try:
        found = outside.collect_outside([NS], comps, {}, [], [])
    finally:
        set_now(None)
    assert [f["kind"] for f in found] == []


def test_two_confirmed_origins_that_share_a_config_object_are_never_two_causes():  # 7 - passes
    from clients.jev_diag.v2.tree import IterativeDiagnoser

    snap = _two_faults(link=False)
    for cid in ("deployment/a", "deployment/b"):
        snap.components[cid]["config_objects"] = {"configmap/shared": {"keys": ["k"]}}
    triage = [{"deployment/a": 0.8, "deployment/b": 0.15, "deployment/c": 0.05, "other": 0.0}] * 2
    # the model would say "both", but linked sides are never offered that option; an unclear answer keeps the stronger
    client = _Answers(triage, {"deployment/a": 0.95, "deployment/b": 0.9}, picks={"fault_start": "both"})
    d = IterativeDiagnoser(client, fetch_detail=lambda s, c: {}).diagnose(snap)
    assert d.investigation["fallback"] is None
    assert d.component == "deployment/a" and d.second is None
    assert [s["component"] for s in d.investigation["steps"]] == ["deployment/a", "deployment/b"]


def test_queue_puts_the_top_workload_before_the_cluster_node_and_telemetry_last():  # 8 - passes (v1 S9, S10)
    from clients.jev_diag.v2.classifier import ChoiceResult
    from clients.jev_diag.v2.tree import OTHER_OPTION, IterativeDiagnoser

    comps = {
        "deployment/otel": {**_comp("otel", "t"), "role": "observability", "evidence_kinds": ["change"]},
        "deployment/front": {**_comp("front", "t"), "evidence_kinds": ["configuration", "symptoms"]},
    }
    snap = _snap(comps)
    snap.cluster["findings"] = [{"kind": "ConfigMap", "name": "coredns", "signal": "written", "components": []}]
    triage = ChoiceResult(
        choice=OTHER_OPTION,
        confidence=0.5,
        probabilities={OTHER_OPTION: 0.5, "deployment/otel": 0.3, "deployment/front": 0.2},
    )
    kind = ChoiceResult(choice="node_or_cluster", confidence=0.6, probabilities={"node_or_cluster": 0.6})
    queue = IterativeDiagnoser(_Answers([], {}), fetch_detail=lambda s, c: {}).initial_queue(snap, triage, kind)
    assert queue == ["deployment/front", OTHER_OPTION, "deployment/otel"]
```

**E1 (passes).** Replace the body of `test_a_revision_made_while_deploying_is_not_a_change`:

```python
    from clients.jev_diag.timeutil import set_now
    from clients.jev_diag.v2 import changes

    meta = {"creationTimestamp": "2026-10-19T05:34:07Z"}
    set_now(changes.parse_time("2026-10-19T05:40:00Z"))
    try:
        deploying = changes.object_change("d/x", "Deployment", "x", NS, meta, revised_at="2026-10-19T05:34:10Z")
        later = changes.object_change("d/x", "Deployment", "x", NS, meta, revised_at="2026-10-19T05:34:40Z")
    finally:
        set_now(None)
    assert deploying is None
    assert later["revision_changed"] and later["at"] == "2026-10-19T05:34:40Z"
```

**E2 (passes).** In `test_report_names_the_owning_component_through_its_configmap_and_an_outside_object_first`, add the
first line right after the existing assert on the "Root cause: Service db" line, and the rest at the end of the test:

```python
    assert "mongod.conf tls requireTLS" in text.splitlines()[0]  # the chosen fact, word for word, on line 1
    # ... existing lines ...
    quota = {"kind": "ResourceQuota", "name": "mem", "namespace": NS, "signal": "requires limits.memory",
             "components": ["deployment/search"]}
    text = build_report(_snap({"deployment/search": _comp("search", "t")}),
                        _diag("deployment/search", fact="x", fault_object=quota))
    assert text.startswith("Root cause: ResourceQuota `mem` in namespace `shop`, acting on Deployment `search`")
```

**E3 (FAILS today, the walk-on).** Append to `test_when_the_two_triage_asks_disagree_both_picks_are_examined_and_the_stronger_origin_wins`:

```python
    # only one pick is an origin: it is concluded once both picks are examined, with no walk to other candidates
    client = _Answers(triage, {"deployment/a": 0.95, "deployment/b": 0.1})
    d = IterativeDiagnoser(client, fetch_detail=lambda s, c: {}).diagnose(_snap(comps))
    assert d.component == "deployment/a" and d.investigation["fallback"] is None
    assert [s["component"] for s in d.investigation["steps"]] == ["deployment/a", "deployment/b"]
```

**Optional, no new test logic: run v1's suite on v2's copies.** A file `tests/clients/test_jev_diag_v1_suite_on_v2.py`
with these lines collects all 31 v1 cases against the v2 modules (31 pass today; checked that the names bind to
`clients.jev_diag.v2.*`). It turns any silent drift in the copied collector, budget fitting or question builders into
a failure, which covers most of the S3, S11 and S18 gaps above at no writing cost.

```python
"""v1's unit tests, run against v2's copies of the same modules (the copies must keep v1's behaviour)."""

import pathlib
import re

_V1 = pathlib.Path(__file__).with_name("test_jev_diag.py")
_MODULES = "classifier|collector|derive|investigate|tree|checks|changes|probes|trend"
_SRC = re.sub(rf"clients\.jev_diag(\.(?:{_MODULES})\b| import )", r"clients.jev_diag.v2\1", _V1.read_text())
exec(compile(_SRC, "test_jev_diag[v2]", "exec"))  # noqa: S102 - defines the same test functions in this module
```

---------------------------------------------------------------------------------------------------------------------
## 7. Files (scratchpad, temporary)

`/tmp/claude-1001/-home-priyo-software-Priyo-Work/69f07c0e-efe8-4221-b2c2-1b938e5242ed/scratchpad/` holds
`review-tests/test_proposed_v2.py` (the tests above), `review-tests/test_jev_diag_v1_suite_on_v2.py`,
`review-tests/sketch/fix-sketch.diff` (the scratch fixes for bugs 1-6 and E3; a sketch, not reviewed code),
`mut/` (mutation runner and list) and `revert/` (per-commit revert runner).
