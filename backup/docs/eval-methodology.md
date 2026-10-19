# How to evaluate a new diagnosis pipeline against v1 honestly

Written 2026-10-19 from the existing run data only (81 runs in `runs-index.tsv`, 21 re-rendered runs in
`jev-v2-runs/results/rerender/`, every grade line in `jev-v2-runs/grade*.log`, and the official grade lines in each
run log). Read-only. Sample C was not opened. The method behind every number is in the appendix.

## The short version

- **The judge is not the problem.** When the same text was graded twice (157 times in our data), the score changed
  in 8% of cases, always by exactly one checklist question (11 points), and pass/fail never changed.
- **Run noise for v1 is small.** Across repeated runs of the same fault with unchanged v1 code, pass/fail changed in
  3% (v1 + Jev) and 8% (v1 + Decisions) of run pairs. Two of the three v1 + Decisions flips came from leftover cluster
  state (a CoreDNS edit left by an earlier DNS fault), which is avoidable.
- **The decision model is noisier than the judge.** The two shuffled asks inside one v2 decision picked different
  answers 12% of the time with Jev and 20% with Decisions.
- **The real uncertainty is which faults are in the set.** Between faults, a new pipeline and v1 disagree on about
  a quarter of faults (one passes, the other fails). With 17 faults, a gap of up to 4 passes is what two equally good
  pipelines produce by chance. Our best Lite result (v2 + Jev 16/17 vs v1 + Jev 13/17) is 3 wins and 0 losses, which
  a fair coin produces 1 time in 8. It is not proof, even on the development set.
- **So more faults beat more repeats.** The protocol below uses Lite for development and one sealed Unseen set
  (sample C plus 30 freshly drawn faults, 40 in total), one run per fault, all decision models on the same snapshot,
  and one pre-registered test. With 40 faults we can prove a large gain (6 to 8 more faults passing out of 40, about
  15 to 20 points) but not a small one. A small gain will show up as "not proven", and that should be reported as it is.

## 1. Measured noise

### 1.1 Judge noise (same text graded more than once)

The judge is gpt-6-astra through Codex at high effort with the 9-question checklist (`rca_checklists.yaml`
version 3.0). Each question is worth about 11 points, and 7 of 9 "Yes" answers (78) pass while 6 of 9 (67) fail. So
**one question decides pass or fail only when a text sits at 67 or 78.**

| Repeated grading of identical content | Pairs | Score changed | Pass/fail changed | Size of change |
|---|---|---|---|---|
| Official grade during the run vs our later regrade of the submitted arm (same judge settings) | 80 | 5 (6%) | 0 | 11 each time |
| Two arms of one run that wrote the same text (graded in the same batch) | 48 | 5 (10%) | 0 | 11 each time |
| Same text in two different runs of a fault | 5 | 0 | 0 | |
| Rerender that only renamed a heading ("Key evidence" became "Mechanism", "Mechanism" became "How it fails") | 20 | 2 (10%) | 0 | 11 each time |
| Same file graded twice (`lite6_unschedulable_incorrect_port_assignment`, all 4 arms) | 4 | 0 | 0 | |
| **All identical content** | **157** | **12 (8%)** | **0** | **always one question** |
| For contrast, rerender that added real content | 19 | 4 (21%) | 0 | 11 to 22 |

- Per question, the answer flipped in 9 of 657 repeated answers (1.4%). The over-attribution question D3-Q1 ("does
  it avoid blaming uninvolved components") flipped most (5 of 73), then D2-Q2 (concrete values, 2 of 73).
- The 12 changes were 89↔100 (8 times), and 11↔22, 33↔44, 44↔55, 33↔44 once each. Examples are the cronjob text that
  v2 + Jev and v2 + Decisions both wrote (100 vs 89, runs `arms_` and `rerun_`), and the CoreDNS text of
  `lite6_service_dns_resolution_failure_social_network` (100, then 89 after a heading rename only).
- Near the pass line the judge was steady. v1 + Jev scored exactly 67 three times on both `edge_request_filter_cpu_saturation`
  and `kafka_poison_pill_hol_block` (different texts each run). Of the 15 repeated pairs that started at 67 or 78, none moved.
- Uncertain part. With 0 flips in 157 pairs, the true pass/fail flip rate is probably under 2%. For a text sitting
  exactly at 78 or 67, the per-question rate suggests roughly a 1 in 10 chance of crossing the line on a regrade.

**What it means.** Treat any score difference of one question (89 vs 100) as noise. Judge noise is too small to explain
any of the pass/fail differences we argued about. It does not need repeats. It does need the judge, the checklist
file and the answer keys pinned (see trap 7).

### 1.2 Run-to-run noise (same fault, run again)

v1 (`clients/jev_diag`, a single commit 6400cd46, unchanged across runs per the coordinator) did not change, so its repeats measure pure
environment + decision model + judge noise. v2 changed 15 times between 18 Oct 19:08 and 19 Oct 12:50
(6400cd46 to 066c4d2f), and almost every repeat of a fault ran on different v2 code, so **v2's repeat differences are
code changes mixed with noise, not noise.** They are shown only as an upper bound.

27 faults ran 2 to 4 times. Arms that failed for infrastructure reasons are left out (5 arms: `lite5_finalizer_deadlock_controller_hotel_reservation`
had no OpenRouter credit, HTTP 402, on all four arms; `arms_valkey_auth_disruption` v1 + Decisions got HTTP 502).

| Arm | Faults with repeats | Faults whose pass/fail changed | Run pairs where pass/fail differs | Average score change between runs |
|---|---|---|---|---|
| v1 + Jev | 27 | 1 (4%) | 2 of 76 (3%) | 2.5 |
| v1 + Decisions | 27 | 3 (11%) | 6 of 74 (8%) | 7.6 |
| v2 + Jev (code changed) | 27 | 5 (19%) | 10 of 76 (13%) | 15.4 |
| v2 + Decisions (code changed) | 27 | 6 (22%) | 11 of 76 (14%) | 13.8 |

Every v1 flip changed the named root cause. None came from the judge.

| Fault | v1 arm | Scores in run order | Cause |
|---|---|---|---|
| service_dns_resolution_failure_astronomy_shop | Jev | 89 / 55 / 55 (`held`, `held3`, `held4`) | Named ConfigMap coredns once, Deployment frontend twice (a model or evidence choice) |
| duplicate_pvc_mounts_social_network | Decisions | 100 / 0 / 100 / 100 (`rerun` is the 0) | Blamed a CoreDNS edit left over from the DNS fault that ran just before |
| liveness_probe_too_aggressive_social_network | Decisions | 89 / 0 (`held5` is the 0) | Blamed a CoreDNS edit made 3478 s earlier, left over from an earlier fault |
| secret_rotation_stale_env_credentials_astronomy_shop | Decisions | 100 / 100 / 34 (`lite6` is the 34) | Picked the postgresql init ConfigMap instead of product-catalog |

v2 + Jev also blamed the leftover CoreDNS edit once (`arms_duplicate_pvc_mounts_social_network`, score 0).

A useful single number is how close each fault is to a coin flip. Averaged over faults, the per-fault pass variance
is 0.008 for v1 + Jev and 0.024 for v1 + Decisions (0.25 would mean every fault is a coin flip). Between faults it
is about 0.25. **Almost all the spread is between faults, not between runs of the same fault.**

### 1.3 Decision-model noise (the two shuffled asks inside one v2 decision)

v2 asks each "best explanation" question twice with the options in a different order and averages the answers
(`investigation.rounds[].picks`, the request pairs `decide:1` and `decide:2` in `*_armN_v2_requests.json`).

| Model | Decisions | The two asks picked different answers | Of those, one side was "none of these" | Average probability shift between the asks (total variation) |
|---|---|---|---|---|
| Jev 1.13 | 96 | 12 (12%) | 7 | 0.07 (median 0.06, 90th percentile 0.17) |
| Decisions (gpt-6-luna-decisions) | 94 | 19 (20%) | 3 | 0.22 (median 0.18, 90th percentile 0.44) |

- All 12 Jev disagreements were close calls (the top two answers within 0.2 after averaging). 4 of the 19 Decisions
  disagreements were not close, so **Decisions is sensitive to option order** even when it is fairly sure.
- v1 asks each question once, so this order noise reaches v1's answer directly. That is a likely reason v1 + Decisions
  is less stable than v1 + Jev in 1.2.
- Averaging the two asks (as v2 does) is worth keeping in any new pipeline.

### 1.4 What a difference has to be before it is real

Two pipelines that disagree on about a quarter of faults (our measured rate is 18 to 30% between v2 and v1 on the same
snapshot per set, and 23 to 27% over all runs) produce these gaps by pure chance, even when they are equally good:

| Faults in the set | 95% of chance gaps in pass counts fall within |
|---|---|
| 10 | ±3 |
| 17 | ±4 |
| 27 | ±5 |
| 40 | ±6 |
| 65 | ±8 |

The simplest honest test counts only the faults where the two disagree and asks whether the wins could be a fair coin
(the sign test). With one-sided 5% confidence you need 5 of 5, 7 of 8, 9 of 10, 10 of 12 or 12 of 15 disagreements
going your way. Our past headline results under this test:

| Comparison (same snapshot, pass = 70+) | New-only passes | v1-only passes | Chance of this or better if equal |
|---|---|---|---|
| Lite final, v2 + Jev vs v1 + Jev | 3 | 0 | 0.125 |
| Lite final, v2 + Decisions vs v1 + Decisions | 2 | 1 | 0.50 |
| Held-out A latest, v2 + Jev vs v1 + Jev | 1 | 1 | 0.75 |
| Held-out A latest, v2 + Decisions vs v1 + Decisions | 2 | 1 | 0.50 |

**None of the claims we made so far (better or worse) is supported at this sample size.** The held-out "v2 at best
equal" impression is also within noise. It is a warning, not a measurement.

On a fixed set of faults (rerunning the same faults), run noise alone moves the gap by about ±2 passes on 17 faults
and ±3 on 40, using the measured per-fault variances.

## 2. Recommended protocol

### 2.1 Two sets only

- **Lite (17, development).** Use it as much as you like, including replays of stored snapshots (`clients/jev_v2/replay.py`),
  which cost no cluster time. Its numbers are regression checks, never evidence of generality.
- **Unseen (final test, about 40).** Sample C (10, untouched) plus 30 faults drawn fresh. It is run once, after the
  code is frozen, and only its aggregate numbers are looked at before the decision. Sample A and set T are studied
  and are not reported.

### 2.2 How to draw and freeze the Unseen list without anyone looking at the faults

1. **Write the pool rule first, using ids only.** Start from the registry ids. Remove Lite (17), sample A (10),
   sample B's discarded draw, sample C (it joins Unseen separately), set T (5) and `node_clock_drift`. Sample B's ten
   ids are not written down in `jev-v2-testsets.md`. Reproduce them by rerunning its seed (`"jev-v2-heldout-B"`) over the
   pool definition used that day, or, if that pool cannot be rebuilt, also remove every fault of the types named there
   (service port conflict, sidecar port conflict, liveness probe). Then remove faults that cannot run on this laptop by a
   rule on the app name or the stated requirement (for example node-level or disk faults, Lite-IA apps), decided from
   the problem list only, before drawing.
2. **Shuffle once with a seed written down beforehand**, for example `random.Random("sregym-unseen-2026-10-20").shuffle(sorted(pool))`.
   Never redraw. The first 30 are Unseen-fresh. The rest, in order, are the replacement queue and the reserve. If
   fewer than 30 runnable faults remain after the pool rule, take all of them and keep no reserve.
3. **Replacement rule, decided now.** If a fault fails to start twice for infrastructure reasons (the harness reports
   an injection or setup failure before any arm runs), the next fault in the queue replaces it. The decision uses the
   harness status only, never the diagnosis.
4. **Freeze.** Save the ordered list to one file, and put its sha256, the seed, the pool rule and the code commit
   hashes into the pre-registration file (2.4). Send the hash to the coordinator before any run, so nobody can swap
   the list later.
5. **The reserve stays sealed.** The roughly 10 to 20 fresh faults left after the first 30 are kept for exactly one
   later re-test. Any change made after seeing Unseen results needs a set nobody has seen, and the reserve is it.

### 2.3 How many faults and how many repeats

Power means the chance that a real gain is detected (one-sided sign test at 5%). Faults where the pipelines disagree
are assumed to be about a quarter, as measured.

| Unseen faults | +10 points real gain | +15 points | +20 points | +30 points |
|---|---|---|---|---|
| 17 | 6% | 13% | 24% | 54% |
| 27 | 14% | 30% | 47% | 84% |
| 40 | 23% | 49% | 69% | 96% |
| 65 | 41% | 75% | 91% | 100% |

One decision model per comparison. Pooling all decision models per fault (2.6) raises these numbers. In a simulation
with 10 models, 40 faults and a +15-point gain, power rose from 48% to between 78% and 92%, depending on how often the
models disagree with each other. The false alarm rate stayed under 5%.

**Recommendation.**

- **40 Unseen faults (10 from C and 30 fresh), one run each.** Each run puts every decision model and both
  pipelines on the same snapshot, so environment noise cancels in the comparison.
- **Do not repeat Unseen runs.** Per-fault run variance (0.01 to 0.05) is small next to the between-fault variance
  (about 0.25). A second full pass would cut the uncertainty by only about 5 to 7%, at double the cluster time. If time is
  left over, spend it on the reserve faults instead, as a separate confirmation.
- **On Lite, run each fault twice for the final development check.** Lite is free to reuse, and two runs show
  whether the new pipeline is stable (v1 + Jev changed pass/fail on 1 of 27 faults, so instability above about 3 of 17
  is a design problem, not bad luck).
- What 40 can and cannot show. A gain of 6 to 8 more passing faults out of 40 can be proven. A gain of 2 to 4 cannot,
  and will be reported as "not proven".

### 2.4 What to pre-register (one file, written and hashed before the Unseen run)

- **Code.** The commit of the new pipeline, the v1 commit (6400cd46 or later, unchanged), the SREGym commit, and the
  arms runner commit.
- **Judge.** gpt-6-astra, Codex backend, effort high, plus the sha256 of `rca_checklists.yaml` and of the answer keys
  (problem `expected` texts) of the Unseen faults. The keys are hashed by a script without being printed.
- **Decision models.** The exact model ids and versions, and the order in which arms run.
- **Unseen list.** Its hash and seed, the pool rule and the replacement rule.
- **Infrastructure-failure rule.** If an arm errors before the model answers (HTTP 402 or 5xx, timeout), rerun the
  whole fault once. If it fails again, mark that fault invalid for all arms and report how many were invalid. A model
  refusal or invalid answer, once the call has succeeded, counts as the pipeline's answer.
- **Primary result.** The pass-rate difference (new pipeline minus v1) pooled over all decision models, with the
  one-sided sign test across faults and a 95% bootstrap interval (2.6).
- **Required conditions.** The new pipeline must not lose to v1 by more than 2 faults out of 40 with Jev, nor with
  Decisions, because it must work with both.
- **Decision rule.** There are three outcomes. "Better" only if the sign test gives p < 0.05 and the interval is above
  0. "Worse" if the same test run the other way gives p < 0.05. Anything else is "not proven", reported with its
  interval. With 40 faults the interval is roughly ±10 to ±15 points wide, so a claim of "equal" is not possible
  either.
- **Secondary results (reported, never used to decide).** Pass counts per model, average composite score, D1/D2/D3
  breakdown, tokens and cost.

### 2.5 Running it

- **Clean cluster per fault.** Use a fresh cluster or a full reset, including CoreDNS, between faults, because
  leftover state caused three zero scores (1.2). If a full reset is too slow, check before each fault that CoreDNS
  and the namespaces match a recorded clean state, and stop if they don't.
- **Random run order, fixed by the seed**, so app or time-of-day effects cannot line up with one group of faults.
- **Check credit before starting.** The projected spend must be under 70% of the OpenRouter balance (credit ran out
  mid-run on `lite5_finalizer_deadlock_controller_hotel_reservation`).
- **Judge check.** Before and after the Unseen run, regrade 20 fixed texts from existing Lite runs (20 × ~45 s,
  about 15 minutes). If more than 2 of them change pass/fail, or the average moves more than 3 points, the judge
  drifted. Report that.
- **Keep the laptop awake for the whole run**, and grade alongside the runs, as `grade-rolling*.sh` did.

### 2.6 Analysis (computed by a script that prints only the aggregate table)

- **Score per fault.** For each fault f, compute d_f = (number of models where the new pipeline passes − number where
  v1 passes) / K. For example, with 10 models, if the new pipeline passes on 7 and v1 on 4, d_f = +0.3.
- **Primary test.** Count the faults with d_f > 0 against those with d_f < 0 (ties dropped), using the one-sided sign
  test.
- **Interval.** Take the mean of d_f (the pass-rate difference) with a 95% interval from 10,000 bootstrap resamples
  of faults. Resample whole faults, never single arms, because arms on the same fault are not independent.
- **Per-model table.** Show new passes, v1 passes, new-only and v1-only for each model. It is descriptive. If anyone
  wants a per-model claim, apply the Holm correction across the K models.
- **Not reported as the main number.** The average composite score. It is dominated by a few complete misses (0 or
  11). Pass counts match the leaderboard, so they lead.

### 2.7 Budget plan for 2, 6 or 10 decision models

Assumptions. Each fault takes 8 to 10 minutes of cluster time whatever K is, because all arms share one snapshot. Each
arm costs about $0.002 in model calls (measured $0.0014 to $0.0028 for Jev and Decisions; other models may cost more).
Each arm takes 30 to 60 s of judge time. Both pipelines run on every model, so there are 2K arms per fault.

| Decision models (K) | Arms per fault | Model cost per fault | Judge time per fault | Wall time per fault | Unseen 40 × 1 | Lite 17 × 2 | Total model cost |
|---|---|---|---|---|---|---|---|
| 2 | 4 | $0.008 | 2-4 min | ~9 min (cluster) | $0.32, ~6 h | $0.27, ~5 h | ~$0.6 |
| 6 | 12 | $0.024 | 6-12 min | ~10 min | $0.96, ~7 h | $0.82, ~6 h | ~$1.8 |
| 10 | 20 | $0.040 | 10-20 min | ~15 min with one judge worker, ~10 with two | $1.60, ~7-10 h | $1.36, ~5-8 h | ~$3.0 |

- With $4.64 of credit, K = 10 fits, leaving about $1.6 (35%) for reruns, as long as the new models cost about the same
  as Jev and Decisions. Price every new model first on one Lite fault (20 arms, a few cents). If the projected total
  goes over about $3.2 (70% of the credit), drop the most expensive models or add credit before the Unseen run.
- At K = 6 or more, the judge, not the cluster, sets the pace. Running two judge workers side by side (if Codex
  allows it) keeps a 40-fault Unseen run to one night.
- Development iterations should use snapshot replays on Lite with Jev and Decisions only (K = 2). Bring in the full
  model list for the final Lite check and the Unseen run.

### 2.8 Keeping the design team from peeking

- **Split the roles.** The runner (the user, or a script the user starts) is the only one who reads the Unseen list
  and per-fault results. Designers, meaning the team and every Claude or Codex session, see only the aggregate table
  from 2.6 until the decision is written down.
- **Seal the results.** Unseen runs write to a folder outside the code tree, and agent briefs name it as off-limits,
  the same way the README protects sample C today. Agents also must not read `conductor/problems/*.py` for any
  fault outside Lite.
- **No patterns written for a fault name.** Only use fault names from the public problem list for counting.
- **After the decision is recorded**, per-fault Unseen results may be opened to learn from. From then on those faults
  are development faults, and the next "unseen" claim must use the sealed reserve.

## 3. Traps we fell into, and how the protocol avoids them

1. **Tuning on the test.** Sample A was run, studied, the code changed, and it was run again (`held`, `held2` to
   `held6`, with v2 code changing in between). By the end it was a second development set. *Avoided by* one Unseen run
   on frozen code, aggregate-only viewing, and a sealed reserve for the next test.
2. **Comparing different versions as if they were repeats.** v2 had 15 commits in 18 hours, and tables mixed the
   versions (the "first pass" Lite table, held-out reruns). *Avoided by* pinning commit hashes in the pre-registration
   and giving every result table one commit.
3. **Small sets read as proof.** 16/17 vs 13/17 felt decisive, but it is 3 wins against 0 losses (p = 0.125). Held-out
   A at 10 faults cannot tell equal from 20 points worse. *Avoided by* 40 faults, the sign test, and stating
   "not proven" when that is the result.
4. **Replays on the snapshot that motivated the fix.** "Replay picks product-catalog on both models" after a fix
   built from that very snapshot is guaranteed, not evidence. *Avoided by* counting only fresh runs on faults the
   change did not come from.
5. **Hand-picked sets.** Set T was chosen for v2's strengths. It is fine as a diagnostic, never as evidence of
   generality. *Avoided by* reporting only Lite and Unseen.
6. **Leftover cluster state.** A CoreDNS edit from an earlier DNS fault produced three zero scores, on
   `arms_duplicate_pvc_mounts_social_network` v2 + Jev, `rerun_duplicate_pvc_mounts_social_network` v1 + Decisions,
   and `held5_liveness_probe_too_aggressive_social_network` v1 + Decisions. *Avoided by* a clean cluster per fault
   and random order.
7. **Infrastructure failures scored as diagnoses, and moving answer keys.** `lite5_finalizer_deadlock_controller_hotel_reservation`
   scored 0 on all arms because of HTTP 402 (no credit). The blog's v1 numbers were graded against older answer keys
   ("v1 Jev also passes here with today's answer key"). *Avoided by* the infrastructure-failure rule, the credit check,
   comparing only arms graded with the same pinned judge and keys, and never mixing in blog numbers.
8. **Reading one-question differences.** 89 vs 100 changed on identical text 8% of the time. *Avoided by* using
   pass/fail as the main metric and treating 11-point differences as noise.
9. **Averages pulled by a few zeros.** v2's first-pass average (75.9) vs v1's (84.5) came mostly from three complete
   misses. *Avoided by* paired pass counts first and averages second.
10. **Many models, many chances to look good.** With up to 10 decision models, one will beat v1 by luck.
    *Avoided by* one pooled pre-registered test, Holm correction for per-model claims, and the "no worse on Jev and
    on Decisions" condition.
11. **Redrawing after seeing what came out.** Sample B was discarded after the draw. That was allowed, since nothing
    had run, but it shows the rule came after the draw. *Avoided by* writing the pool rule and the seed before
    drawing, never redrawing, and pre-registering a replacement rule.

## Appendix: how the numbers were computed

- **Data.** Every row of `runs-index.tsv`, read from `*_arms_graded.json` (`arms[i].text`, `arms[i].grade.accuracy`,
  `grade.checklist`). `held_duplicate_pvc_mounts_hotel_reservation` has no graded file and is left out. The official
  grade of the submitted arm (`submit_arm`) comes from the line "Correct/Incorrect diagnosis ... (score: X/100)" in
  `jev-v2-runs/<label>.log`. That run used the same judge settings (gpt-6-astra, codex, high), so it is a true repeat.
- **Identical text** means equal after collapsing whitespace. "Heading-rename only" rerenders are those where the
  word counts differ by 5 words or fewer; every one of them differed by exactly +3/−2 words.
- **Run-to-run statistics** use every pair of runs of the same fault and arm. `service_wrong_pod_selection` (`arms01`)
  is treated as `service_wrong_pod_selection_hotel_reservation`. "Root cause changed" compares the first "Root cause"
  line of the two texts.
- **Shuffled asks.** Each `decide:1`/`decide:2` pair was matched by option text (`questions.best_explanation.criteria`)
  and the two probability vectors were compared. The results match the `picks` in `investigation.rounds`
  (Jev 84 agree and 12 disagree; Decisions 75 agree and 19 disagree).
- **Chance gaps and power.** Exact sign-test calculations, with faults where the pipelines disagree set to 25%
  (+30 points assumes 35%). The pooled-model simulation assumes each model follows the fault's shared effect 75% to
  90% of the time and is otherwise independent. That assumption is the main uncertainty in the pooled numbers.
- **Not measured.** Pure v2 run noise, because no fault was repeated on identical v2 code. Whether models other than
  Jev and Decisions are as stable. Judge behaviour on texts written by a new pipeline, which may land near 67/78 more often.
