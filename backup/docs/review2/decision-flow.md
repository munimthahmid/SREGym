# v2 decision flow review (tree, classifier, report, driver)

Reviewed commit 85af8577 on feat/jev-diag-v2 (tree.py, driver.py and classifier.py are unchanged since ae68e37e).
Two report commits (dca2e34b, 85af8577) landed while I was reviewing; every report finding below was re-run on a
clean copy of 85af8577. The working tree also had uncommitted edits to report.py, collector.py and checks.py. I did
not review those. Read-only, no paid calls.

## How I checked

- I replayed the 29 dev snapshots through the v2 collection code and ran `IterativeDiagnoser` with a fake model. The
  fake reuses the recorded Jev and Luna answers from replay s1-1019-1546 (arms 2 and 3, 58 runs). Anything not
  recorded gets a stated policy.
- I ran the pre-refactor tree (cf354c03) on the same inputs. All 58 reports were identical. So the
  `_characterize` / `_diagnosis` / `_step` refactor behaves the same as the old inline tail for a single cause.
- 116 runs with random answers to every question gave no crash. The most requests in one diagnosis was 20; the code
  caps it at about 23.
- Scripted small flows covered the two-cause, pair, split and replay paths.
- For report findings I used the s1 judge grades wherever the s1 text is identical to what 85af8577 prints.

The scripts and their outputs are in `scratchpad/review-flow/` (harness.py, scen.py, synth.py, secret_tb.py,
replay_polls.py, equiv.py, fuzz.py).

## Findings, most severe first

### 1. The residual check can turn a correct single-cause answer into two causes, or into the wrong cause. HIGH. CONFIRMED.

**Where.** tree.py:482-497 (`explained_by`), 500-516 (`unexplained_frontier`), 463-479 (`link_facts`), 436-460, and
1028-1047 (the reason text is at 1042).

**What happens.** With the recorded answers, the check fired in 5 of the 29 dev problems: liveness_probe,
readiness_probe (arm 3), valkey_memory, secret_rotation and update_incompatible. It costs one extra investigation of
about 24k characters each time. In all 5, `link_facts` found no link, so the tiebreak offered "both". Every one of
them is a single-fault problem.

The links do exist, but the code does not look for them:
- **secret_rotation.** postgresql's `login_candidates` is `[product-catalog]`, and its `postgresql-init` ConfigMap
  was rewritten 1 s after the Secret.
- **update_incompatible.** rate crash-loops on "no reachable servers". mongodb-rate belongs to the concluded
  same-change group, but `link_facts` only compares rate with mongodb-geo.
- **valkey_memory.** The Job floods valkey-cart.
- **liveness_probe.** social-graph-service is flagged only by a log line misread as RBAC ("user_id: 403 not found").

`report-design.md` 5.3 had already noted that no link ties rate to its database.

**Real-model evidence.** On secret_rotation (guard G13, a named hard case) the Luna model judged postgresql to be
the origin at 0.66 in the replay and 0.68 in a live run. Both are above the 0.6 threshold. Driven with that answer,
v2 reaches `tiebreak(product-catalog, postgresql)`. The state says links "none found". The why_asked text says
"postgresql has failures of its own that product-catalog does not account for", which is false and leading.

One model answer then decides the outcome:
- Picking "postgresql" gives the wrong root cause. v1 and v2 without this check pass this problem.
- Picking "both" blames a second component. That costs D3-Q1 and probably D1-Q3. This problem already sits at 0.77,
  so one more lost item fails it.

On "both", the primary becomes whichever side has the higher origin probability (tree.py:804-806, 1044-1046). The
triage question still tells the model "Exactly one fault was injected".

**Upside, to keep in mind.** In readiness arm 3 (wrong primary mongodb-geo) and valkey_memory (the ground truth is
valkey-cart), the check could rescue a failing answer.

**Smallest fix.**
- (a) Treat a component as explained, and as linked, in any of these cases:
  - it is a server whose `login_candidates` include an explained component;
  - it belongs to the concluded cause's `same_change` group, so compare against every group member;
  - it is named in the investigated `calls` or `failing_targets`;
  - its change landed within `SAME_CHANGE_SECONDS` of the cause's change.
- (b) Make why_asked neutral.
- (c) Offer "both" only when each side has its own `change` evidence and the two changes are far apart in time.
- (d) Put the check behind a flag that is off by default, until a dev-pool run with Jev and Luna shows it gains more
  than it loses.

### 2. The secret_rotation report leaves out the database and prints a spec change as the effect. MEDIUM-HIGH. CONFIRMED.

**Where.** report.py:27-31, 33, 211-212 and 252.

**What happens.**
- `STATE_WORDS` contains `restarted`, which also matches `restartedAt`. So the Effect line is the spec-change
  signal: "spec modified 88s ago ... restartedAt ...".
- The Mechanism line is the Secret's creation time.
- postgresql is never named. Its login rejections are not "errors naming" product-catalog, so Affected stays empty.
  `_POINTERS` also drops the "server deployment/postgresql rejects logins ..." signal from the new Observed line.

85af8577 prints the same text that s1 printed, and the judge graded that text 0.77 on both arms. It answered D3-Q2
No ("omits PostgreSQL") and D3-Q3 No ("lists deployment metadata changes"). v1 scored 1.00.

**Smallest fix.**
- Use `\brestarted\b`.
- Add servers whose `login_candidates` contain the cause to Affected, for example "Deployment `postgresql`: rejects
  logins for account otelu (22 lines)".
- Prefer that rejection signal over a finding's timing text as the Mechanism.

### 3. The "Affected (symptoms only, not causes)" line contradicts the root cause. MEDIUM-HIGH. CONFIRMED.

**Where.** report.py:257-269 and 158-159.

**What happens.**
- **search_rate.** The Root cause names "the call path from Deployment `search` to Deployment `rate`". Affected
  then lists search as "symptoms only, not causes". In s1 the judge failed D1-Q2 on both arms quoting exactly this
  label. The judge has not yet graded the new path wording.
- **Cluster conclusion.** On social-network DNS arm 2 (concluded `other`, CoreDNS), user-service is the ground-truth
  target, and it is listed as "symptoms only, not causes". The s1 text was identical and scored D1 0/3, a fail at
  0.56. The component path in arm 3 says "acting on Deployment `user-service`" and scored 1.00.

**Smallest fix.**
- Never list in Affected a component that the Root cause line already names.
- When `comp` is None, name the fault object's linked workloads in the subject with "acting on", the same way the
  component path does.

### 4. The same pair is tie-broken twice, which can undo a pair decision. MEDIUM. CONFIRMED (scripted).

**Where.** tree.py:1014-1028.

**What happens.** The residual check also runs after a confirmed-origins tiebreak picks one side (`second` is None)
and after `pair_node`. The loser is still an investigated origin at 0.6 or more and the winner does not explain it,
so it comes first in the frontier. The tiebreak is then asked again with a new, leading reason.
- **Scripted, unlinked pair.** The first tiebreak keeps `a`, the second says "both", and the report gives two causes.
- **Scripted auth pair.** Server `s` rejects logins from client `c`. `pair_node` picks `c`. Then `tiebreak(c, s)`
  offers "both" because the login link is not seen, and the report gives two causes.

**Smallest fix.** Skip the residual check when `paired` or `pair_decided` is set, and leave already-compared
components out of the frontier.

### 5. After a split triage, the loop does not return to the confirmed origin. MEDIUM. CONFIRMED.

**Where.** tree.py:967-983.

**What happens.** When the two triage asks pick different components, even a 0.95 origin waits until the other pick
is examined. If the other pick is not an origin, nothing goes back to the confirmed one. The loop walks the whole
queue and ends in the fallback.
- **Scripted.** Origin `a` at 0.95 and other pick `b` not an origin gave 8 investigations. v1 stops after 1.
- **Dev replay** (second ask with its top two swapped, unrecorded components answering "none"):
  - update_incompatible went from 4 to 9 requests;
  - finalizer went from 3 to 6;
  - the median went from 3 to 4.
- In update_incompatible the two picks (mongodb-geo and mongodb-user) are the same change, so there was nothing to
  separate.

Every extra step is another chance for a false origin.

**Smallest fix.** Remember which candidates a conclusion was deferred for. Once they are all examined and none is
an origin, conclude `max(confirmed)`. Count two picks in the same `same_change` group as agreement.

### 6. No request fits the small-context limit, and asking triage twice adds 66%. MEDIUM (affects whether the evaluation is valid). CONFIRMED.

**Where.** tree.py:553-556 and 78 (`DETAIL_TOKEN_BUDGET` is fixed at 22000); triage uses the 24000-token budget.

**Measured over 58 runs.**
- Triage requests were 40-61k characters, all 58 of them.
- Investigation requests were 14-34k, with a median of 24k.
- 205 of 216 requests were over 15k.
- The second triage ask adds a median 66% of the characters per diagnosis. The G16 target was at most 1.3x v1.

With Clef, Clef Flash or Kev, every run will fail at triage. The catch-all (tree.py:867-872) will then submit the
code-only report, and the arm will be scored as that model's answer.

**Smallest fix.**
- Give each model its own character budget for the triage and investigation states, and make the detail budget a
  parameter.
- Count `fallback_without_model` as a failed arm in the eval.
- Skip the reversed ask when the first ask is decisive (top ≥ 0.9 in 24 of 58 recorded triage answers), or send
  both asks at the same time.

### 7. Offline replays of v2 runs will serve a wait poll as the snapshot. MEDIUM (affects replay validity). CONFIRMED.

**Where.** driver.py:153-155, together with collector.py:1929 and 1965.

**What happens.** Each poll calls `trend.collect_sample`. That reads `get pods -o json -n <ns>` and `get events` with
exactly the same arguments as the snapshot, and the calls are recorded. Replay serves recorded calls in order, so
the snapshot gets the first poll. In a synthetic bundle, the live snapshot read "Running" and the replayed read
"Pending". v1 has `recording_paused()` for exactly this case.

**Smallest fix.** Wrap the poll's `collect_sample` in `recording_paused()`. Keep recording the baseline.

### 8. Any code error becomes a silent code-only report. LOW-MEDIUM. PLAUSIBLE.

**Where.** tree.py:863-872.

**What happens.** `except Exception` catches programming errors, such as a KeyError or TypeError, as well as model
outages. It also throws away a triage that already succeeded.

Code-only picked a passing arm's component in 22 of 25 dev faults. Its text is weak, though:
- it never names the quota, webhook or CoreDNS object, because it sets no fault object;
- its facts are weak, for example "warning events: BackOff x11";
- on secret_rotation it picks product-reviews.

**Smallest fix.** Catch only errors from the model call, by wrapping them inside `_ask`. When triage succeeded, use
`fallback()` and `_characterize` instead of code-only.

### 9. The Kafka subject has an unclosed parenthesis. LOW. CONFIRMED.

**Where.** report.py:149.

**What happens.** 85af8577 prints "the input `orders-fulfillment` (named by env `ORDERS_TOPIC` consumed by
Deployment ...". The ")" is never closed. The uncommitted working tree is rewriting this line again.

### 10. Smaller items

- **Probes run once per arm.** They are on by default (driver.py:193). Each arm's diagnoser execs into the data store
  again, so arms that share one snapshot can see different probe results, and the side effects repeat. STRATEGY says
  probes run once, during collection. PLAUSIBLE.
- **Earlier read.** The adaptive wait (driver.py:150-159) reads the cluster at about 60 s as soon as one abnormal pod
  stays stable. v1 read at 120 s, so log pointers and "still occurring" states have less time to build. This
  confounds v1-vs-v2 comparisons. The wait also ignores `--trend-interval`. PLAUSIBLE.
- **Cluster-node pick ignored.** When one triage ask picks `other`, the split check ignores it (tree.py:968-972), so
  the cluster node is never asked before a workload is concluded. PLAUSIBLE.
- **Exact ties.** An exact tie after averaging (for example 0.6/0.4 and then 0.4/0.6) is resolved by the components'
  order in the snapshot (tree.py:1385), not by either ask. Rare. CONFIRMED (scripted).
- **Noise lines in evidence.** `detail_evidence` lists pod-template-hash and restartedAt lines as template changes in
  E1 and E2 (tree.py:143-147). In a first-option run, one of them became a second cause's root-cause fact. Reuse
  `report.changed_values` to filter them.
- **Missing impact.** The network_policy and valkey_memory reports now have no line that describes the impact on the
  application (D3-Q3 was lost there before). The fault object's side could supply it, for example the callers'
  errors.
- **Stale trace field.** After a residual-check flip, `investigation["fallback"]` keeps the old reason. This only
  affects the trace.

## Fixed while I was reviewing (dca2e34b, 85af8577)

- On cronjob_sidecar the report no longer claims "its pods are Running and Ready" when 1 of 2 are ready, and the
  Mechanism line no longer repeats the root-cause command. The judge had failed it at 0.67 against v1's 1.00. The
  job facts now appear in Mechanism and Effect.
- On rolling_update the rollout-strategy signal now appears in the Mechanism line. v1 scored 1.00 there and the s1
  v2 text scored 0.78.

## What is fine

- No crash on real snapshots or random answers, and the loop is bounded.
- The refactor gives identical outputs to cf354c03 in all 58 runs.
- `cap_evidence` matches v1 below the 32-item cap, and above it keeps 4 log, 3 event and 4 dependency items as
  intended.
- `Diagnosis.second` serializes, and `build_report` prints both blocks.
- Among the 29 dev faults, `feedback_path` fires only on search_rate.
