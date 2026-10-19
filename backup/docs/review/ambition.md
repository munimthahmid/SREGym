# Ambition review: what would make v2 a real leap (2026-10-19)

Status: DONE (2026-10-19). Sections 0-5 complete; numbers re-checked against run files and the sources named below.
Read: README, STRATEGY, sota, benchmark-landscape (redacted), eval-methodology, decision-models, v1-architecture,
v2-audit, forensics; sregym.com leaderboard and blog (fetched today); arXiv 2605.07161 (html, Tables 3-5);
SREGym README, `main.py` (`--noise`), `sregym/conductor/conductor.py` (stage timing), `oracles/mitigation.py`,
`oracles/network_policy_oracle.py` (Lite), `observer/prometheus/prometheus/values.yaml`, `clients/cloudthinker/README.md`. Run numbers computed from `runs-index.tsv` rows lite5/lite6/held*/tgt only.
Not opened: `UNSEEN-SEALED.txt`, `sealed/`, any problem file, `Problem List.md` (it has rows for sealed problems),
and every problem-specific oracle except the Lite one named above.
Tags: **[fact]** = read in a file, page or run; **[measured]** = computed by me from run files today; **[opinion]**.

---

## 0. Short version

1. **The structural edge of a no-LLM pipeline is exhaustiveness, not intelligence** [opinion]. Code can read every
   object, every metric series before and after onset, and every node, on every run. LLM agents sample greedily. Every
   failure the SREGym paper lists (first plausible anomaly wins, noise capture, nobody looks at the hardware layer,
   partial answers to compound faults) is a coverage failure. Aim the design at that, and stop competing on "reasoning".
2. **Already true of v1, by a lot** [measured]. Cost per diagnosis is $0.0013 (Jev) to $0.0022 (Decisions) against
   377K-1.86M frontier-LLM tokens per run on the leaderboard. Run-to-run stability is high, with pass/fail changing
   in 3% (Jev) and 8% (Decisions) of repeated run pairs. It runs unchanged on two decision models from two vendors.
3. **Not true today, though often assumed** [measured]. On speed, SREGym's clock includes v1's fixed 120 s start delay, so
   v1's time to diagnose is about 131 s. That is slower than the top agents (Devin + Opus 5.5 at 76 s, Codex + GPT-6 Astra
   medium at 92 s). On calibration, v1 at final confidence 0.9 or more passed the judge only 80% of the time (49 of 61).
   Noise robustness is untested, and a leftover CoreDNS edit already caused 3-4 zero scores.
4. **The leaderboard ranks by end to end (diagnosis AND mitigation on the same run)** on SREGym-Lite-1004 (17 faults,
   3 attempts). It has no cost column and no non-LLM entry. A diagnosis-only entry ranks last. Lite is saturated (4
   entries at 100% E2E) and is our development set, so any Lite number from us is in-sample.
5. **Recommended route**. Freeze diagnosis, then add a small no-LLM mitigation stage (undo the identified change,
   restart to re-apply declared config, verify, roll back if worse). Submit through the SREGym team's verified
   third-party route, and ask for a cost column and a "decision-model" tag. Measure TTD on SREGym's own clock after
   replacing the fixed wait with "observe until stable".
6. **Honest headline we could reach** [opinion]: "X of 40 pre-registered unseen SREGym faults diagnosed, pooled over 5
   decision models from 4 vendors (worst model Y), at about $0.002 and about N s per diagnosis, with every report sentence
   machine-traced to a collected fact and no change in answers when every name in the cluster is randomized." Only the
   cost and stability parts are true today.
7. **The four hard families each have a general angle** [opinion]. For metastable loops, compute per-edge work
   amplification and "timeout below observed latency" and check that the overload outlives the trigger. For node and
   hardware faults, run a USE sweep over node-exporter metrics plus a co-location check. For several causes, check the
   residual (symptoms the best single cause does not cover) and group identical changes. For noise, require persistence
   across a window and coverage of the user-facing symptom, and score loudness as zero.
8. **Biggest credibility gap in the plan**. The Unseen list was drawn after an analyst had read every non-C problem
   file and written a one-line row for each (now redacted). Disclose it, and add a **temporal holdout** (problems that
   SREGym adds after our code freeze).
9. **What the draft under-shoots**. Its goal is relative to v1 (+15 points). It has no leaderboard path, no noise
   condition, no TTD fix, and no reproducibility artifacts. It has no invariance tests, and its "look closer" step only
   fires on a top-two disagreement. Section 5 ranks 15 additions. The top 6 plus three small ones fit in about 4-5
   days, one more than the draft.

---

## 1. Where a no-LLM decision-model pipeline can beat LLM agents outright

### 1.1 Scorecard (v1 today vs the leaderboard and the paper)

| Dimension | LLM agents (source) | v1 today | Win today? | What it takes to make it a clear, measured win |
|---|---|---|---|---|
| Cost per diagnosis | 377K-1.86M tokens per run on the board (Codex + GPT-6 Astra medium 377K; Claude Code + Opus 5 1.86M) [fact, leaderboard]. Blog: v1 about 200x cheaper than GPT-5.6 Sol medium [fact, blog] | median $0.00135 Jev, $0.0022 Decisions, 22-32K decision-model tokens [measured, 45 runs] | **Yes, 2-3 orders of magnitude** | Report $ per diagnosis from OpenRouter usage, judge cost excluded for both sides. Keep v2 under $0.005. |
| Work time | TTD 72-518 s on the board [fact] | collection about 8 s plus decisions 2.8 s median (v2 6.2 s) [measured] | Only if the clock agrees | See next row. |
| Time to diagnose on SREGym's clock | Devin + Opus 5.5 high 76 s, Codex + Astra medium 92 s [fact] | **about 131 s**. First model request at 128 s median (125-134 s) because of the 120 s `--start-delay` [measured; `driver.py` 190-195; `conductor.py` 736, 792] | **No** | Replace the fixed wait with "observe until stable" (poll every 10 s; stop when the anomaly set has not grown for 2 polls and a candidate leads by a calibrated margin; cap 120 s). Read Prometheus history instead of waiting. Measure pass rate vs TTD on Lite. |
| Determinism, run-to-run stability | Not published per run. Paper: 3 runs per problem, no variance reported [fact] | pass/fail flips in 3% (Jev) and 8% (Decisions) of run pairs, all traced to one threshold or one leftover object [fact, eval-methodology 1.2]. Blog: every fault 5 of 5 or 0 of 5 [fact] | **Probably yes**, unproven against agents | Report pass^3 (all 3 attempts pass) next to mean pass. Equal for a deterministic pipeline, lower for any agent below 100%. Fix the leftover-state trap (clean cluster per fault). |
| Calibrated confidence, abstention | No calibrated confidence exposed by any agent [fact, leaderboard/paper] | Per decision, yes. Jev at p >= 0.7 right 100% (102 asks) on localization [fact, decision-models 2.3]. **Against the judge's pass, weak.** v1 final origin p >= 0.9 passed 49/61 (80%); p < 0.6 passed 3/9; fallback 1/6. v2 "certain" passed 50/61 (82%), "uncertain" 10/25 (40%) [measured, 86 graded arms each, mixed v2 versions] | **Partly**. The signal exists, not lab-grade | Calibrate "probability of passing the judge", not "probability the origin is right". The 100% vs 80% gap is report quality (D2/D3). Publish a risk-coverage curve, e.g. "commits on 70% of faults and passes 95% of those". |
| Noise and decoys | Noise costs about 10 points of diagnosis (Stratus Sonnet 61.5 to 51.5; Claude Code 72.6 to 62.6; Codex 70.0 to 59.3) [fact, Table 3] | Never run with noise. The "newest change wins" prior was captured by a leftover CoreDNS edit 3-4 times (scores 0) [fact, forensics] | **No** (unknown, with a known weak spot) | Persistence across a window, coverage of user-facing symptoms, loudness scored as zero, decoy-injection tests on replays. Run Lite with noise on. |
| Auditability | Agents write free text. Literature: right service 76% vs grounded path 61.5% (OpenRCA 2.0); hallucinated tool outputs (ORCA-bench) [fact, sota] | Report quotes code-made facts word for word [fact, v1-architecture K5] but has no claim-to-evidence ids and no checker | **Partly** | Every sentence carries evidence ids that point at a recorded raw response. A checker re-derives every quoted value from the recorded bundle. Target "0 unsupported claims, machine-checked". |
| Works across decision models | Agents swing widely by model: Claude Code Opus 4.8 58.8% vs Opus 5 90.2% diag [fact, leaderboard] | 13/17 Jev, 12/17 Decisions on Lite; same pick on identical states 77-80% [fact] | **Partly** (2 models) | 5-10 models from 4+ vendors, report the spread and the worst model. Agreement between models is a free precision signal (32/33 right when Jev and Decisions agree). |
| Safety of the action space | Agents run kubectl with write access (needed for mitigation) | Read-only by construction, fixed action set, model cannot issue commands [fact, v1 code] | **Yes** | State it and measure it: count of mutating API calls during diagnosis = 0 (from the proxy log). |
| Data egress, self-hosting | Logs and configs go to a frontier LLM | Model sees only a code-built JSON state; open-weight decision models exist (Perplexity Decider Apache 2.0, Drex open weights) [fact, decision-models 5] | **Yes** | One run with an open-weight model makes "fully on-prem SRE diagnosis" a real claim. |
| Accuracy on new, hard families | Paper "New failures" (n=13), diagnosis without noise: Stratus Sonnet 33.3%, Claude Code Sonnet 38.5%, Codex GPT-5.4 25.6% [fact, Table 4]. Frontier-model numbers on these families are not public | RT 1/4, IN 0/10, MC 2/2, NI never run (arms passing, small n) [fact, landscape 4.4] | **No** | Sections 2 and 5. This is where "off the chart" has to be earned. |
| Accuracy on Lite | 4 entries 100% diag and E2E [fact] | 13/17 (Jev), 12/17 (Decisions) [fact] | **No** | 16-17/17 without Lite-specific rules. It is in-sample either way. |

### 1.2 What this means [opinion]
- Cost, stability, safety and self-hosting are wins we already own. On their own they are a "cheap but worse"
  story. That story is useful, but no lab would call it a leap.
- The leap has to be **accuracy on families where coverage matters**, combined with the owned wins. LLM agents lose
  there because they do not look (hardware), stop early (noise, compound faults), or never compare both sides of an
  interaction (metastable). Code that always looks everywhere, plus a model that only chooses, attacks exactly those.
- The honest flip side: on a genuinely new mechanism that no generic detector covers, an LLM can read code and reason
  in the open. We cannot. Our fallback is v1's graceful degradation (name the changed thing and quote the strongest
  new fact). Say so in any write-up.
- A lab reviewer will ask what the decision model adds. In v2 the code's top candidate was already right in 77% of
  first rounds, and the model lifted that to 80% (Jev) and 87% (Decisions) [fact, decision-models 0]. The design should
  give the model work code is bad at, such as reading text, judging cause versus side effect, and abstaining. The
  evaluation must include a "code ranking only" ablation (section 4.2).

---

## 2. The hard categories all agents fail, and how the draft could crack them generally

What the paper says [fact, arXiv 2605.07161 html]: "No agent across the metastable failure problems identified both
interacting components". For hardware faults, "All agents attribute the errors to error-handling logic inside the
application", and none ran disk-level checks. On compound faults, agents draw "partial conclusions". Under noise, all
agents take "the first plausible anomaly" as the failure. On the 13 "New failures", diagnosis is 15-39% and E2E 10-28%
(older models). Noise means two 2-minute injections every 5 minutes (pod failures, latency, packet loss, node stress).

Examples below use only non-sealed rows of `benchmark-landscape.md`.

### 2.1 Metastable and retry-storm loops (IX, about 10% of problems)
- Examples. capacity_decrease_rpc_retry_storm and load_spike_rpc_retry_storm (GT `configmap/rpc`: 50 ms timeout,
  30 retries), search_rate_retry_collapse (GT `search-to-rate RPC path`), gc_capacity_degradation (GOGC=1 on all).
  v1 cannot express a path (34 on search_rate). v2 passed it with a Lite-tuned `amplify` pattern.
- General mechanism, all computed in code from generic signals:
  1. **Work amplification per edge**, meaning calls on the edge per upstream request (Jaeger spans or Prometheus
     request counters), before vs after onset. A ratio above 1 that grows is the loop.
  2. **Timeout below observed latency**. Extract every timeout, retry, deadline and backoff value reachable from the
     caller (env, args, ConfigMaps it mounts). Compare the timeout with the callee's observed p50/p99 latency. Code
     writes the fact, e.g. "timeout 50 ms is below the callee's p50 of 120 ms, and 30 retries allow up to 31x load".
  3. **Outlives the trigger**. Find the trigger window (load spike, CPU stress, capacity drop) in metric history and
     check whether overload persists after it ends. That is the textbook definition of metastability.
- The answer slot is trigger + amplifier + sustaining state, on one edge. Ask the model to choose among
  {single cause, trigger + amplifier on edge E, ...} with the three facts shown. The judge's D2-Q1 needs all parts
  (search_rate v2 lost D2-Q1 for omitting the burst).
- Draft coverage. It names "trigger plus an amplifier" (design 2) and metrics (design 3), but not how the amplifier
  is detected. **Add the three computed facts.**

### 2.2 Node, hardware and OS faults (NI, 7%; 12 hardware-level and 5 OS-level rows in SREGym's list)
- Examples. silent_data_corruption (WiredTiger files overwritten, checksum errors), kubelet_crash (`node/kubelet`),
  node_conntrack_exhaustion (GT names the node's conntrack table and 2 Deployments).
- General mechanism:
  1. **Co-location feature**. For every anomalous pod, which node it is on. If all failing pods of a workload share
     a node and replicas elsewhere are healthy, the node becomes a candidate. This is a graph edge (pod to node),
     not a rule.
  2. **USE sweep from node-exporter and kube-state-metrics via PromQL**, which needs no exec into host pods (refused in
     filtered mode). Check utilization, saturation and errors per node, including conntrack fill
     (`node_nf_conntrack_entries / node_nf_conntrack_entries_limit`), clock offset (`node_timex_offset_seconds`),
     filesystem and disk errors, memory pressure, and node conditions and lease age. Run it every time on every node.
     That is cheap for code and exactly what no agent did.
  3. **Storage-integrity log class**. A decision-model yes/no over new log templates: "does this line report data
     corruption or a checksum failure?". This is a typed question, not a regex.
- Partly verified [fact]. `sregym/observer/prometheus/prometheus/values.yaml` has kube-state-metrics and
  prometheus-node-exporter enabled. Whether every app's `full` run scrapes them and keeps pre-onset history is still
  for stage 0 (`review/feasibility.md`).
- Draft coverage. "Node" is in the origin kinds and "outside objects" are added, but there is **no node USE sweep and
  no co-location feature**. Add both.

### 2.3 Several causes, correlated or common-mode (MC 6%; Incident Arena graded per cause with the MINIMUM score)
- Examples. update_incompatible_correlated (the same image on 6 mongodb Deployments; v2 0/11, v1 89/89),
  frappe_desk_and_queue_outage (2 causes), frappe_writes_and_queue_oom (4), slack_sends_fail_strict_mode (2).
  Incident-Arena: partial fixes pass 2.5% [fact, sota].
- General mechanism:
  1. **Common-mode grouping**. Identical field diffs, same time window, many objects. That is one cause with N
     members, named as a set. This is pure code.
  2. **Residual check**. After picking the best single cause, compute which user-facing symptoms it cannot reach
     through typed edges. If a residual cluster remains with its own unexplained frontier, offer "cause A + cause B"
     covers. Ask the model a neutral fact question ("are the symptoms in `residual` explained by `A`?"), then a choice
     among covers. Parsimony stays the default; a second cause must earn its place.
  3. Report each cause as its own complete block, because the judge grades each one.
- Draft coverage. It has "one cause can span several workloads" and "two-sided causes" (design 2). **Add the residual test**.
  Otherwise a second independent cause is only offered if a pattern happens to produce it.

### 2.4 Noise and decoys
- Examples of built-in decoys [fact, landscape 2.4] include 4 inert mutating webhooks, decoy CPU limits, 3 random
  TrainTicket flags, log-noise volume, and conductor-caused restarts. Leftover cluster state acted as a natural decoy
  for us.
- General mechanism:
  1. **Persistence**. The target fault lasts until mitigated, while paper-style noise comes and goes in 2-minute
     windows. Read 10-15 minutes of Prometheus history, and keep only anomalies that persist across the last N
     samples, or that started at the fault onset and have not stopped.
  2. **Explain the user-facing symptom, not the loudest one**. Candidates are scored by coverage of entry-point
     errors and latency (or the incident description), and loudness is never a feature (OpenRCA 2.0 "salience
     capture").
  3. **Change relevance**. A change counts only if it touches the anomalous subgraph and comes before its onset (in
     held5 liveness, the leftover CoreDNS edit was 3,350 s older than the symptoms and touched no failing path).
  4. **Decoy-injection tests on replays** (section 5, item 4), to prove it before any noise run.
- Draft coverage. None, noise is not mentioned. **This is the cheapest "beats LLM agents" headline available**,
  because the paper already measured the agents' loss (-10 points).

### 2.5 Runtime state (RT, 17%: the biggest family where v1 is weak, 1/4)
Not on the paper's list, but it is where SREGym is growing (Incident Arena, GitLab, Stripe; 0 of the 0508 cohort).
The general mechanism is declared vs live state. For each store or server, read live config, users, grants, locks and
consumer offsets through read-only probes, and diff them against what the manifests or env declare. A mismatch with
no spec change is a runtime candidate. The draft lists probes (design 3), but "are read-only exec probes fair?" is
still open (open question 2). **Settle it in stage 0, because RT is 17% of the benchmark.**

---

## 3. Leaderboard mechanics; is a mitigation stage worth it?

### 3.1 Facts (sregym.com/leaderboard, fetched 2026-10-19; README; conductor code)
- Suite SREGym-Lite-1004, 17 faults; 3 attempts per fault (Devin Oncall 2). Columns are diagnosis %, mitigation %,
  **E2E %** (correct diagnosis and successful mitigation on the same run), TTD, TTM, and mean tokens per run.
  **Sorted by E2E.** 23 rows, all LLM agents. An asterisk marks third-party submissions verified by the SREGym team
  (Devin Oncall, CloudThinker). There is no cost column, no non-LLM or decision-model category, and no published
  submission rules.
- Comparable results need the `full` profile (`svelte` is "not comparable") [README].
- TTD is measured by the conductor from the end of setup to the diagnosis submission (`conductor.py` 736, 792), so any
  agent-side wait counts.
- Mitigation is graded by **outcome**, not by text. The default `MitigationOracle` (used by 68 problem files) waits for
  rollouts and checks that workloads are healthy, and it treats a missing pre-injection Deployment as an agent error
  (scale to 0 or delete does not pass) [fact, `oracles/mitigation.py`]. Problem-specific oracles check reachability or
  recovery (e.g. `network_policy_oracle.py` checks for a ready endpoint).
- In the paper's Table 5, agents mitigate successfully 68-89% of the time after a correct diagnosis, and 22-62% after a wrong
  one [fact]. Mitigation partly works without diagnosis. Generic rollbacks fix many faults.
- The SREGym team already hosts a post on v1 (Oct 6) and on Jev inside Codex (Sep 17), and its README documents Jev
  decision support [fact]. A working channel to the maintainers exists.

### 3.2 What it would take to appear credibly [opinion]
1. **An E2E number**. A diagnosis-only row would sit at the bottom of an E2E-sorted table. So either add mitigation,
   or get a diagnosis-only view. Ask for both.
2. **Lite-1004, 3 attempts, `full` profile, run or verified by the SREGym team**, with frozen code and the commit hash
   published, and a plain note that Lite was our development set (in-sample).
3. **Ask the maintainers** for a $-per-run column (tokens are not comparable across model types), a "decision model /
   no LLM" tag, and pass^3. All three are neutral improvements to the board, and they are exactly the axes where we
   win.
4. **TTD fixed first** (section 1.1), or the row shows us slower than the top agents.
5. Opinion on timing. Lite is saturated at 100% E2E by 4 entries. A row at 15-16/17 diagnosis will read as "cheap but
   behind" unless the cost column exists. The stronger public result is the Unseen and hard-family table, published as
   a blog post on sregym.com, with the leaderboard row as a secondary item.

### 3.3 Mitigation stage: yes, small and late [opinion]
- **Why**. It is the only way onto the ranked board. It also turns our precise diagnosis (field, before value, after
  value) into a fix spec, which LLM agents have to improvise. And "the fix worked" is interventional evidence that the
  diagnosis was right, which makes a strong secondary metric ("fix-confirmed diagnoses").
- **What, all no-LLM, chosen by the decision model among code-built actions**:
  1. Restore the changed field to its recorded before value (revision diff, managedFields, sibling template), or
     `rollout undo`.
  2. Remove an object created after the baseline that acts on the victims (policy, webhook, sidecar, hostPort). Never
     delete or scale down a pre-existing Deployment, since the oracle fails that.
  3. Restart to re-apply declared state (stale env after Secret rotation, runtime `CONFIG SET`, CoreDNS reload).
  4. Verify by re-collecting and checking that the symptoms cleared. If things got worse, undo (Stratus-style
     no-regression).
- **Where it will not work**. Runtime data faults (revoked grants, sequence at INT max, dropped users) need typed
  write probes. Leave them out of v1 of mitigation and report them as out of scope.
- **When**. After the Unseen diagnosis run (stage 6, about 1.5-2 days). Building it earlier would pull attention from
  diagnosis, and it must not change diagnosis code.

---

## 4. Headline results that are compelling and honest, and the evidence package

### 4.1 Candidate headlines (fill X, Y, N from the pre-registered run only)
1. **Unseen accuracy at near-zero cost**. "X/40 on pre-registered unseen SREGym faults, pooled over 5 decision
   models from 4 vendors (worst model Y/40), median $0.00Z and N s per diagnosis on SREGym's own clock."
   It is false if pooled X depends on one model, so report the spread.
2. **Hard families**. "On node/hardware, metastable, multi-cause and runtime-state faults (n = ...), X% vs 15-39%
   for LLM agents in the SREGym paper." This is only honest with **a same-fault LLM comparator** (section 4.2, item 11),
   because the paper used older models and other problems. Without it, say "for reference" and not "beats".
3. **Noise**. "Noise costs us K points of diagnosis on Lite, vs 10 for LLM agents in the paper (same noise protocol)."
4. **Stability**. "pass^3 = pass@1 on every model", or "0 of 17 faults change pass/fail across 3 attempts".
5. **Trust**. "When it commits (C% of faults), it passes the judge P% of the time, and it flags the rest as
   unsure with the top two hypotheses and the test that would separate them."
6. **No memorization**. "Renaming every namespace, service, label and image in the recorded cluster changes 0
   answers" (name-blind test), and "inserting a recent unrelated change into the snapshot changes K of 57 answers"
   (decoy test).
7. **Grounding**. "100% of report sentences trace to a recorded tool response; a checker re-derives every quoted
   value."
8. **Pareto**. One plot of the leaderboard with diagnosis % on y and $ per run on a log x axis. We sit 2-3 orders of
   magnitude to the left. This needs the $ estimate for LLM rows, made from their published token counts and public
   prices, with the method stated.

Not honest, avoid. "Beats GPT-6 / Opus on SREGym" from mixed problem sets. Lite numbers presented as generalization.
"10 s per diagnosis" while SREGym's clock says 131 s. A pooled number without the per-model table.

### 4.2 Evidence package a lab would expect
1. **Pre-registration** (already planned). Hashes, seed, pool rule, decision rule, models, judge and answer-key hashes.
   Add the **disclosure** below, plus TTD and $ measurement rules.
2. **Contamination disclosure** [fact, then opinion]. `benchmark-landscape.md` says it read every problem file except
   sample C, and its table had a one-line row (mechanism, GT origin) for each of the 107 non-C problems. The 30 rows
   now sealed were redacted when the list was frozen (README). STRATEGY's category shares are computed over all 107.
   Aggregates are harmless. One-line rows are not, if anyone who designs v2 read them. State who read what, and add
   item 3.
3. **Temporal holdout**. Pre-register now that frozen code will also run on every problem SREGym adds upstream after
   the freeze date (2.0, postmortem problems), once and unchanged. This is the cleanest "unseen" a lab can get
   (the LiveCodeBench idea), and it costs nothing today.
4. **Per-category table** (WS, CO, CL, RT, IX, NI, MC, IN) with n, pass counts and Wilson intervals. Say plainly that
   n = 3-8 per category cannot support category claims at 40 faults.
5. **Funnel**. Evidence collected, then right cause offered (candidate recall), then picked, then report passed. This
   is the only way to know which layer to fix, and labs read it as rigor.
6. **Ablations** on stored snapshots (replay), each removing one part (metrics, traces, logs, probes, outside
   objects, the test library, the residual check). Plus two that matter most to a reviewer. **Code ranking only (no
   decision model)**, to show what the model adds. **An LLM answering the same typed questions** (one call, same
   state), to show whether a decision model is as good as an LLM at the choice step. This is an analysis arm, not the
   product.
7. **Cross-model table** with 5-10 models, showing passes, spread, worst model and agreement-gated precision.
8. **Calibration**, per model, as a reliability plot of "probability of pass" vs judge pass, ECE and a risk-coverage curve.
9. **Stability** from Lite x 3 attempts, reporting pass^3 and the decision flip rate.
10. **Cost and time**, meaning $ per diagnosis from OpenRouter usage, decision-model tokens, TTD on the conductor
    clock, and a work-time breakdown (collection, probes, model).
11. **Same-fault LLM comparator** (optional, strongest). The runner runs Codex + GPT-6 Astra medium (leaderboard row:
    100% diag on Lite, 377K tokens) on the 40 Unseen faults, 1 attempt each, judged identically. This needs Codex
    or OpenAI access and about 40 x 10 minutes of cluster time, but no OpenRouter credit. Without it, every "vs LLM" sentence is
    a reference, not a comparison.
12. **Judge robustness**. Regrade with a second judge model (the paper reports alternate judges at kappa 0.94), plus
    the planned before/after judge drift check.
13. **Release**. Code, recorded tool responses for Lite (and for Unseen after the decision), decision requests and
    answers, and judge outputs. Anyone can then replay the whole pipeline offline for $0. A pipeline that can be
    replayed for $0 is very rare among SRE agents.

---

## 5. Bold, still-general additions ranked by impact vs effort; where the draft is not ambitious enough

### 5.1 Ranked additions
Impact = expected gain on Unseen pass rate (U) and credibility with labs (C). Effort in working days.

| # | Addition (all general: k8s kinds, fields, symptom classes only) | U | C | Effort | Draft today |
|---|---|---|---|---|---|
| 1 | **Report contract lint**. Map each of the judge's 9 questions to a report slot, covering origin with kind+name+namespace, changed object vs broken component, concrete before/after values, victims listed as victims, an impact sentence, and no category label. Code refuses to submit with an empty slot it has data for. D2-Q2 and D3-Q2 are the most common losses | high | med | 0.5 | design 6 (shape only) |
| 2 | **Exhaustive before/after diff** over all Prometheus series (robust z, median/MAD, windowed) including **node-exporter USE** and kube-state-metrics, Jaeger edge errors and latency, and new log templates, with a **persistence filter** | high | high | 1-1.5 | design 3 (sources only) |
| 3 | **Record/replay at the tool-call layer** (kubectl, PromQL, Jaeger, Loki, probes). Every read is cached by request, and replay serves from cache. Gives faithful offline dev, determinism and releasable artifacts. `kubectl_raw.jsonl.gz` already exists. Today's `replay.py` does not re-read detail (v2-audit) | med | very high | 0.5-1 | no |
| 4 | **Invariance suite on replays**. Name-blind (consistent random renaming of every identifier), decoy injection (add a recent unrelated change, an inert webhook, a crash-looping bystander), and evidence deletion (remove the key fact, so the answer should become "unsure", not something made up). Would have caught v2's Lite-shaped patterns on day 1 | med | very high | 0.5 | lint only (design 7) |
| 5 | **Decision model as the evidence classifier, replacing regexes and word lists**. Batch yes/no questions over each new log template or event ("reports an authentication failure?", "reports a connection refused?", "reports data corruption?"). Code reasons over the typed answers. This removes the string matching behind W4 and v2's `SATURATION_RE`. Narrow factual questions transfer best across models (decision-models 4.3). It also handles new apps' log formats | high | high | 1 | no |
| 6 | **Calibrated "probability of pass"** per model, fitted on Lite decisions and graded runs, driving the stop rule and published as risk-coverage | med | high | 0.5 | no |
| 7 | **Hypothesis-test library with value-of-information selection**. Tests keyed by hypothesis class (resolve, connect VIP vs pod IP, auth with the client's own credentials, live config vs declared, consumer lag, both ends of a timeout/retry edge, node USE). Code computes which tests split the current hypotheses (an expected-information table, arithmetic in code). The model chooses among the top 3 tests and answers about outcomes. Stop when calibrated p(pass) clears the bar or no informative test is left | high (RT, IX) | high | 1.5-2 | design 5 (only on a top-two disagreement) |
| 8 | **Residual-based multi-cause plus common-mode groups plus trigger/amplifier** (section 2.3, 2.1) | med (MC, IX, IA) | high | 1 | design 2 (partial) |
| 9 | **Adaptive observation window** instead of the fixed 120 s, measured as pass rate vs TTD on Lite | low | high (speed claim) | 0.5 | no |
| 10 | **Noise condition**. Lite with SREGym noise on (`main.py --noise`, Chaos Mesh transient faults) as a secondary result, ideally Unseen too | low | high | cluster time | no |
| 11 | **Grounded claims**. Evidence ids on every sentence, plus a checker over the recorded bundle | low | high | 0.5 | no |
| 12 | **Temporal holdout pre-registered now** (section 4.2, item 3) | none now | very high | ~0 now | no |
| 13 | **Cross-model committee option**. Ask 2-3 decision models and act on agreement (32/33 right when Jev and Decisions agree). Report single-model and committee results separately. Settle first whether it is allowed (draft open question 3) | low-med | med | 0.25 | no |
| 14 | **Mitigation stage** (section 3.3), after the Unseen decision | none (diag) | high (leaderboard) | 1.5-2 | no |
| 15 | **Spin-off decision-model benchmark**. Frozen SRE states + typed questions + gold answers from the replays, for decision-model vendors (TypeSafe, OpenAI Decisions, Perplexity, Liquid, Nace). The SREGym paper has no non-LLM baseline and the decision-model indexes test no long technical states (decision-models 5). Both gaps are citation magnets | none | very high | 1 after #3 | no |

Suggested order [opinion]. Items 1-6 plus 9, 11 and 12 fit inside the draft's stages 1-3 (about 4-5 days instead of
3-4) and lift both score and credibility. Items 7-8 are the main accuracy bets for RT, IX and MC. Items 10, 13, 14 and
15 come after the Unseen decision, together with the leaderboard submission and the comparator run.

### 5.2 Where the draft is not ambitious enough
1. **The goal is relative to our own v1** ("+15 points"). Labs compare against agents and costs. Add absolute,
   pre-registered targets, for example pooled Unseen pass >= 70%, worst of 5 models within 3 faults of the best,
   median $ <= 0.005, TTD <= 60 s, and pass rate on committed answers >= 90%. Keep the v1 comparison as the
   regression guard it is.
2. **There is no path to the ranked leaderboard.** It is diagnosis only, with no mitigation and no TTD fix (131 s today).
3. **Noise is absent**, though it is the paper's best-measured agent weakness and cheap to test.
4. **Telemetry is "add sources", not "read everything and diff it"**. The structural advantage only appears when the
   sweep is exhaustive (every series, every node, every edge) and code does the comparison.
5. **"Look closer" fires only when the two asks disagree on the top two.** Make it a loop driven by value of
   information over all live hypotheses, with a calibrated stop. v2's go-back ran a second round in 1-2 of 82 arms.
   An evidence step that never runs adds nothing.
6. **The node layer is implicit.** Add the co-location feature and the node USE sweep (section 2.2).
7. **Reproducibility is not designed in.** There is no tool-call record/replay and no release plan.
8. **Generality is enforced by a lint only.** A lint checks the words in the code, while name-blind and decoy tests
   check behaviour. Both are needed.
9. **Calibration and abstention are not results.** They are the most distinctive output a decision model has.
10. **40 faults cannot support category claims** (eval-methodology: +15 points has about 49% power for one model,
    78-92% pooled). Add the temporal holdout and, after the decision, a descriptive full-registry run (labelled as
    studied).
11. **The decision model's value is not isolated.** Add the "code ranking only" and "LLM on the same typed questions"
    ablations, or a reviewer will call it a rules engine with a tie-breaker.
12. **Regex and word-list evidence tagging survives** in the plan (start from v1 = keep `derive.classify_evidence`).
    Moving text judgement to the decision model (item 5) is the general fix and plays to the model's strength.

### 5.3 Ambition traps to avoid [opinion]
- Chasing 17/17 on Lite by tuning. That repeats v2. The leaderboard row should use whatever frozen code the Unseen run
  used.
- Building mitigation before diagnosis is frozen.
- Adding an LLM "summarizer" or "explainer" anywhere. It breaks the constraint and the auditability claim.
- Claiming wins over LLM agents from mixed problem sets, older-model paper numbers, or pipeline time instead of
  conductor time.
- Writing any rule, threshold or example that names an app, service or value from SREGym (the lint plus name-blind
  test enforce this).

---

## Open uncertainties
- Whether Jaeger and enough pre-onset Prometheus history exist for every app in the `full` profile during diagnosis.
  Node-exporter and kube-state-metrics are enabled in the chart values; per-app coverage is unverified
  (`review/feasibility.md` is checking this).
- Whether read-only exec probes and multi-model committees are within the rules (draft open questions 2 and 3).
- Whether the SREGym team accepts non-LLM submissions or would add a cost column (no published rules found).
- How much of the 120 s wait is truly needed. Some faults take minutes to surface (restarts, OOM growth). Measure it.
- The blog's "median diagnosis time 14.6 s" vs today's measured 128 s to first model request. The blog setup may
  have used a shorter start delay. Not verified.
- v1/v2 calibration numbers mix code versions and come from 86 graded arms per pipeline. Treat them as leads.
