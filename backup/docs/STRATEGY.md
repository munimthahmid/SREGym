# v2 strategy, revision 2 (for review, 2026-10-19)

Revised after 7 analyses and 7 reviews (`review/`). The first draft is kept in `STRATEGY-draft1.md`.
Nothing gets built until you agree. Section 7 lists the decisions that are yours.

## 1. What we now know (facts from the reports)

**About v1**
- **Its first step does almost all the work.** In 80 of 86 graded v1 runs, the final answer was the component v1's
  first whole-app ranking (the triage) put on top. The walk after it rarely matters. Runs that stopped after 2
  model calls passed 57 of 76; longer walks passed 3 of 10.
- **Why the triage works.** Code computes neutral Kubernetes facts (selector vs labels, pod vs template, a Secret
  rewritten after start, a revision diff) and ranks changes against when symptoms began. A short set of written
  priors guides the pick, and the report quotes the chosen fact word for word. It also costs about $0.0013-0.0022
  per diagnosis, and its pass/fail changed in only 3-8% of repeated runs.
- **Where it loses points.** About 60% of v1's lost checklist items come from what it is allowed to say. It must name
  one workload first, and it cannot name a call path, a topic or a set of workloads. The rest come from what it
  cannot see, including runtime state, hostPort, probe timing, objects outside the app namespace, and metrics.
  On the 48 problems nobody has run, a code-level prediction gives v1 roughly a 25% pass rate.
- **Polluted inputs.** Leftover changes from earlier problems and harness or conductor restarts appear as recent
  changes in 52 of 81 snapshots. A model API error means nothing is submitted, which zeroed 3 arms.

**About old v2**
- **It was a closed set of hand-written fault stories,** fitted to Lite. 12 of 15 commits added a rule right after a
  failed run. Off Lite it fell back to v1's own step (8 of 20 held-out arms) and tied or lost.

**About the benchmark**
- **Lite is saturated and unrepresentative.** Top LLM agents score 100% diagnosis on it. 12 of its 17 problems are
  in the 3 easiest categories, and it has no node or multi-cause problems.
- **The leaderboard ranks end-to-end, diagnosis plus fix,** on the `full` profile. A diagnosis-only entry ranks last.
  Our astronomy runs used `svelte`, which SREGym says is not comparable.
- **There is almost no healthy history before the fault.** Injection comes 15-50 s after the app starts, and metrics
  are scraped once a minute. Before-vs-after comparisons are mostly impossible. Absolute signals,
  replica-vs-replica and service-vs-service comparisons, and early-vs-late trends after the fault do work.
- **Evidence we can use.** Metrics cover every app, Loki keeps logs of pods that are gone, and traces are reliable on
  astronomy and blueprint-hotel only. Read-only exec probes are allowed (SREGym expects valkey-cli), but only small
  native tools are safe, because a probe has already OOM-killed Kafka.

**About the judge**
- **Naming the bad value is decisive.** It earns the concrete-value item in 239 of 243 right-origin runs, and in only
  1 of 28 runs without it.
- **The "Fault type" line costs more than it earns.** It lost the item 10 of 219 times with the line, against 1 of 68
  without it.
- **Missing affected components is the most common loss on right answers** (37% of lost items).

## 2. Goal (measurable, honest)

- **Primary.** On Unseen (15 faults), pooled over 5 decision models, v2 passes clearly more than v1. With 15 faults
  only a large gain is provable, so we report the measured gain and its interval as it is.
- **Guard.** v2 is never worse than v1 by more than 2 faults with Jev or with Decisions.
- **Beyond accuracy.** Cost about $0.002 and time per diagnosis on SREGym's clock, stability over repeats,
  confidence that predicts a judge pass, and answers that do not change when names are randomized.

## 3. Design (separate package; starts as a full copy of v1)

### 3.1 Keep v1's core, fix its plumbing (stage 1)
- **Copy v1 unchanged first,** then fix only general bugs. Those are revision diffs that never become change signals,
  probe timing and termination grace that get dropped, the 32-item evidence cap cutting events and logs, false
  links from names relayed inside error text, symptom onset per component, and a model-free fallback report when the
  API fails.
- **Filter changes to ones that can matter.** A change counts only if it touches an app object after the app was
  deployed and has a visible effect on something failing. That removes leftover CoreDNS edits, harness restarts and
  decoys.
- **Keep v1's protections.** That includes the CoreDNS ordering (it protects against leftovers in 32 of 81 snapshots),
  the telemetry rule, the login-rejection logic and priority-based trimming. Their regression guards are listed in
  `review/strengths-review.md`.
- **Collect once per fault into a stored bundle,** and let every model arm decide from that same bundle. Probes run
  once, during collection.

### 3.2 A report shaped for the judge (stage 1)
Use the five-line template in `review/report-design.md` (Root cause, Mechanism, Details, Effect, Affected).
- **The subject is whatever holds the bad value.** A call path, data object, outside or cluster object, Service field
  or workload field leads the report. A ConfigMap or Secret used by one workload is reported under that workload,
  with Service and Deployment both named.
- **Values are written as old -> new,** with one quoted error line from the origin.
- **Affected callers are listed one hop away, as victims, with their error class.**
- **No fault-type line,** no probabilities, no "cannot be ruled out".
- **Estimated gain.** On our 29 studied faults this alone adds about 10 passes, mostly v1 framing fixes. It is checked
  on Lite plus auth_miss and secret_rotation, which need opposite object kinds.

### 3.3 Say more, decide better (stage 2)
- **Keep v1's whole-app ranking as the core decision.** It decides 80 of 86 of v1's answers.
- **Widen what a candidate can be.** Add outside objects (Ingress, PriorityClass, kube-system, other namespaces,
  CRDs) behind a rule-based filter for SREGym's own setup objects. One change made on several workloads becomes one
  candidate. Add call paths with both sides' settings, and data objects such as topics.
- **Add the useful facts to each candidate in v1's ranking,** such as old -> new values and timing, rather than a
  separate fact-card system.
- **Ask the ranking twice in shuffled order.** If both asks agree, accept. If not, look closer (stage 3's tie-break
  test, or v1's investigate step on the top two).
- **Let the model classify error lines our regexes cannot,** choosing a class from a fixed list, so unseen log formats
  still point somewhere. It runs only on unrecognized lines.
- **Keep requests to 15k characters or less,** so 32k-context models fit.

### 3.4 See more, break ties with evidence (stage 3)
- **A PromQL module.** About 12 aggregated queries using absolute signals, replica-vs-replica, and early-vs-late
  after the fault, plus node-exporter for node faults.
- **Jaeger, scoped to error and latency per call between services,** on apps where traces are reliable (astronomy,
  blueprint-hotel; hotel with its namespace label fixed).
- **Loki, as one small module** for logs of pods that were replaced or deleted.
- **2-3 read-only probes** with small native tools and a memory-headroom check, such as DB auth with the client's own
  credentials, valkey `CONFIG GET`, and DNS or connect from a client pod. Kafka lag comes from metrics. Technology-level
  command tables are allowed; app-level knowledge is not.
- **A tie-break test.** When the two asks disagree, code runs the test that separates the top two and asks a
  two-option question.

### 3.4b Hard categories (stages 2-3)
- **Two independent causes.** If the best single cause leaves failing components unexplained, code looks for a second
  candidate that covers them, and the report names both (the score is the minimum over causes).
- **Feedback loops.** For a call path, metrics show whether retries multiply the work, whether the timeout is below
  the observed latency, and whether the overload continues after its trigger stopped; both sides are reported.
- **Other namespaces of the app.** Collect the namespaces where the app's operator, data and control plane live,
  not only the main namespace (v1 cannot see TiDB operator faults today).
- **Decoys and noise.** Development checks include SREGym's built-in decoys and its noise mode, so a change or alert
  that touches nothing failing never wins.

### 3.5 Generality rules (all stages)
- Knowledge may name Kubernetes kinds, fields, symptom classes and technologies (a DB, a cache), never an app, a
  service name or a problem-specific value. A lint check enforces it.
- Candidate recall (is the true cause among the options?) is measured separately from the pick.
- Name-blind test: randomize names in a stored bundle; the answer must not change.

### 3.6 Also in scope
- **An adaptive wait** instead of v1's fixed 120 s (stage 1), so we are fast on SREGym's clock.
- **A small mitigation stage** (stage 5, if you agree): the model picks among code-built actions (undo the identified
  change, restart to re-apply declared config), then code verifies and rolls back if things get worse.

### 3.7 Cut on purpose (complexity without proven gain)
- A separate 11-field fact-card system and extra question rounds. The facts go into v1's ranking instead.
- A noise-based accept threshold and per-model switches. Plain agreement between the two asks is enough.
- Testing every development step on 5 models. We use Jev and Decisions while building, and all 5 at each stage
  checkpoint and in the final test.
- A time-based holdout. (Noise and decoy checks are kept, on development faults.)

## 4. Evaluation

- **Development set.** Lite plus everything already studied (sample A, set T) plus the never-run problems that are
  not sealed. Those exercise metrics, probes, node and multi-cause faults, which Lite cannot. Development numbers are
  never reported as results.
- **Unseen (15).** Sample C (10) plus 5 drawn by seed, picked without looking and stored outside the project. The
  rest of the frozen 40 stays untouched as a reserve.
- **Models.** Jev 1.13 and GPT-6 Luna Decisions are required. Jev 1.14, Perplexity Decider V1.2 and Liquid d1-ultra
  are added for robustness, with Drex v2.0 as reserve.
- **Profile.** `full` for every app from now on, matching the leaderboard.
- **Reporting.** The per-fault pass difference pooled over models, with a sign test and bootstrap interval. Results
  per category, a recall-to-pass funnel, cost, time and stability. Ablations are "code ranking only" and "v1's report
  vs the new report".

## 5. Stages and checkpoints

| Stage | Work | Check before moving on | Time |
|---|---|---|---|
| 0 | Pre-registration file; a 30-min cluster check (trace coverage, MCP latency, tools in images, `full` profile memory on this laptop); credit check | you approve this doc | 0.5 day |
| 1 | v1 copy, plumbing fixes, change filter, stored bundle, new report, adaptive wait | Lite: at least v1 on every fault; 19 offline regression guards pass | 1 day |
| 2 | Wider candidates, facts added to v1's ranking, ask twice, model-classified error lines | Lite + dev pool; candidate recall; 5 models at the checkpoint | 1 day |
| 3 | PromQL, Jaeger edges, Loki, safe probes, tie-break test | dev-pool faults with runtime, node and interaction causes; 5 models | 1-1.5 days |
| 4 | Unseen (15), once, 5 models | final numbers | a few hours |
| 5 | Mitigation (if you agree): pick among code-built undo/restart actions, verify, roll back | Lite end-to-end | 0.5-1 day |

Realistic total is about 4 days. Stage 1 alone is already a strong, low-risk result. It fixes most of v1's framing and
reporting losses.

## 6. Risks we know about
- The model can only pick what code offers. Recall is measured from stage 2 on.
- Telemetry without a healthy baseline can mislead, so only absolute and comparative signals are used.
- Probes have side effects, so only small tools run, with a memory-headroom check, once per fault.
- Both-kinds wording when the ground truth names the Deployment is untested. It gets checked on Lite first.
- `full` profile memory on a 14 GB laptop is unknown, and stage 0 checks it.

## 7. Decisions for you
1. **Development set.** Use the never-run, non-sealed problems (and sample A and set T) for development checks,
   never in reported numbers? (Recommended. Two reviewers asked for this independently.)
2. **Mitigation.** In scope after the Unseen run, so we can appear on the leaderboard? (Recommended: yes, small and
   safe.)
3. **Leaderboard contact.** Later, ask the SREGym maintainers whether a non-LLM agent can be ranked, and whether they
   would add a cost column. That is outward-facing, so it's your call.
4. **Budget.** The Unseen run needs about $1-2 of the $4.64 left. Top up before stage 4 so a credit error can't wipe a
   run?
