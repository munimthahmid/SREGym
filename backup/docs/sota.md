# State of the art in automated RCA for microservices / Kubernetes (survey for jev v2 rethink)

Status: DONE (2026-10-19). Sections 1-5 complete; see 'Open uncertainties' at the end.
Scope: web papers/benchmarks + local SREGym docs (read-only). Facts are cited; opinions are marked "Opinion".

## 1. Benchmarks and what top systems score

### SREGym (our target)
- Paper: Clark, Su, Pial, Tian, Gniedziejko, Jacobsen, Chen, Xu, "SREGym: A Live Benchmark for AI SRE Agents with
  High-Fidelity Failure Scenarios", [arXiv 2605.07161](https://arxiv.org/abs/2605.07161) ([html](https://arxiv.org/html/2605.07161)).
  90 curated problems, 47 fault primitives, 5 apps; 3,623 viable fault-component pairs (about 40x the curated set).
- Diagnosis grading = LLM judge with three equal parts: fault localization (origin, not cascade), fault
  characterization (mechanism with concrete values such as port, env var), failure scope (no over/under-attribution).
  Judge agreement with human experts kappa = 0.90; alternate judge models agree at kappa = 0.94 (paper, Sec. on oracle).
- Paper results (Table 3, older models): diagnosis 38.1% to 72.6%, mitigation 40.4% to 78.5%, end-to-end 26.7% to 60.7%.
  Best E2E Claude Code + Sonnet-4.6 (60.7% clean, 53.7% with noise).
- Paper findings that matter for us:
  - Ported problems (from AIOpsLab/ITBench) are much easier than SREGym's new ones: E2E 63.7% vs 17.9% for the best
    agent; Claude Code 60.8% -> 28.2%; Codex 57.8% -> 15.4%. That is a generalization gap between "familiar" and
    "novel" faults, for LLM agents too.
  - Noise costs about 10 points of diagnosis (Stratus Sonnet 61.5 -> 51.5; Claude Code 72.6 -> 62.6). All agents were
    "greedy": they "always treat the first plausible anomaly as the target failure (which can be a noise)", and in
    several cases saw the root-cause evidence but discarded it.
  - Hardware faults: agents blame app error handling; none read dmesg/smartctl; characterization near zero.
  - Metastable failures: agents find the trigger in traces but "no agent ... identified both interacting components".
  - Correlated/compound faults: partial conclusions, wrong criticality and scope.
- Public leaderboard: [sregym.com/leaderboard](https://sregym.com/leaderboard) (fetched 2026-10-19). Suite is
  SREGym-Lite-1004 (17 faults), 3 attempts per fault (Devin 2). Ranked by end-to-end. No non-LLM entries, no cost column.
  Top of the board (Diagnosis / E2E):
  | Agent | Model | Diag | E2E | Time to diagnose | Tokens/run |
  |---|---|---|---|---|---|
  | Devin Oncall (3rd party) | Claude Opus 5.5 high | 100% | 100% | 76 s | 1.24M |
  | CloudThinker (3rd party) | GPT-6 Astra low | 100% | 100% | 126 s | 736K |
  | Devin Oncall | GPT-6 Astra max | 100% | 100% | 191 s | 1.11M |
  | CloudThinker | GPT-6 Astra max | 100% | 100% | 310 s | 1.74M |
  | Codex | GPT-6 Astra medium | 100% | 90.2% | 92 s | 377K |
  | Codex | GPT-6.1 Sol medium | 98% | 90.2% | 104 s | 462K |
  | Claude Code | Claude Opus 5 | 90.2% | 70.6% | 242 s | 1.86M |
  | Codex | GPT-5.6 Sol medium | 72.5% | 49% | 118 s | 868K |
  | Claude Code | Claude Opus 4.8 | 58.8% | 41.2% | 360 s | 1.85M |
  Fact: on Lite, diagnosis is saturated (100%) by the best LLM agents. Our v2 numbers (15/17 on Lite, about 88%) sit
  between Claude Code + Opus 5 and the top. Opinion: since Lite is saturated and public, the honest differentiator is
  unseen faults (the full set, 129 problems in the local list, Incident-Arena problems, postmortem problems, SREGym 2.0 "environment scaling").
- SREGym blog ([sregym.com/blog](https://sregym.com/blog)):
  - [Jev-driven SRE diagnosis](https://sregym.com/blog/jev-driven-sre-diagnosis) (Oct 6, 2026; this is our v1): 80/105
    (76.2%) on the 21-fault Sep-4 Lite cohort, median 14.6 s, 2.4 Jev calls/attempt, about $0.15 total Jev cost.
    Close to GPT-5.6 Sol medium's 77.8% at about 7x faster and about 200x cheaper. Failures: Jev chose the wrong clue
    (edge_request_filter: CPU limit chosen over the WAF regex) and decisive evidence missing (search_rate_retry_collapse:
    retry loop between two services; single-component answer space).
  - [Can Jev make SRE agents more reliable?](https://sregym.com/blog/jev-sregym-lite) (Sep 17): Jev as a gate in Codex
    (rank hypotheses, review submission at p >= 0.70) took 20/50 -> 24/50. Jev "couldn't recover missing hypotheses":
    if the right option is never offered, ranking cannot help.
  - [Postmortems to benchmark problems](https://sregym.com/blog/postmortems-to-sre-benchmarks) (Sep 24): 31 new problems
    from real postmortems (Cloudflare WAF, CNI routing, Kafka producer leak, ...). Plan: auto-generate problems from
    postmortems and "evolve" them (more noise, bigger scale). Opinion: the future test distribution is open-ended.
  - [Frontier Data Summit](https://sregym.com/blog/frontier-data-summit) (Oct 13): SREGym 2.0 coming with
    "environment scaling"; no details on hidden test sets.
- Local docs: `~/sregym/SREGym/README.md`, `docs/SREGym-Lite.md` (17 problems), `docs/incident-arena.md` (Frappe,
  Saleor, Slack Spine + 10 Incident Arena tasks; multi-cause problems are graded per cause, all must pass).

### Other benchmarks (for scale of difficulty and lessons)
- AIOpsLab (Microsoft, MLSys 2025) [arXiv 2501.06706](https://arxiv.org/pdf/2501.06706): detection, localization, RCA,
  mitigation on live k8s apps. Overall: FLASH 59.3%, ReAct 55.9%, GPT-4 + shell 49.2%, GPT-3.5 + shell 15.3%.
  SREGym absorbs all AIOpsLab problems.
- ITBench (IBM, ICML 2025) [arXiv 2502.05352](https://arxiv.org/pdf/2502.05352): 102 scenarios (SRE, CISO, FinOps).
  SRE diagnosis pass@1 GPT-4o 13.8% (9.5% without traces): observability matters. SREGym absorbs ITBench too.
- Stratus (NeurIPS 2025) [arXiv 2506.02009](https://arxiv.org/html/2506.02009v2): multi-agent detect/diagnose/mitigate
  with Transactional No-Regression (undo); at least 1.5x mitigation success over prior agents on AIOpsLab and ITBench.
  It is SREGym's built-in baseline agent (`clients/stratus`).
- OpenRCA (ICLR 2025) [mlanthology](https://mlanthology.org/iclr/2025/xu2025iclr-openrca/): 335 offline cases, 68 GB
  telemetry; best (Claude 3.5 + RCA-agent) 11.3%. Accuracy at least halves when two root-cause elements are needed.
- OpenRCA 2.0 [arXiv 2606.27154](https://arxiv.org/html/2606.27154v2): 500 cases with step-wise propagation-path
  labels. Agents name the right root service 76% of the time but ground it in a verified propagation path only 61.5%.
  Best exact match about 27-29% (Claude Opus 4.7, Gemini 3.1 Pro). Three failure patterns: premature commitment,
  absence bias (no spans from a dead pod read as "healthy"), salience capture (pick the loudest anomaly even when it
  is downstream amplification).
- RCAEval (WWW'25 / FSE'26) [arXiv 2412.17015](https://arxiv.org/pdf/2412.17015), [GitHub](https://github.com/phamquiluan/RCAEval):
  735 failure cases, 15 baselines. Metric methods: RCD Avg@5 0.54, CIRCA 0.46; multi-source BARO 0.81; TraceRCA 0.77;
  PDiagnose 0.67. BARO perfect on disk faults, weaker on network delay/loss.
- Audit of RCA leaderboards [arXiv 2606.29159](https://arxiv.org/html/2606.29159): across OpenRCA, RCAEval RE1/RE2,
  PetShop, 16 methods: the best method changes per subsystem; on several subsystems a trivial probe (max |z|,
  alert count) or a shipped baseline beats every published method; 6 of 18 comparisons flipped on a second release of
  the same apps; pooled ranking picked the worse method on a held-out subsystem in 8 of 36 decisions.
- ORCA-bench [arXiv 2607.28545](https://arxiv.org/pdf/2607.28545): on-call tasks; agents degrade on novel
  configurations; hallucinated tool outputs and context loss are named failure modes.

- Incident-Arena [arXiv 2610.00648](https://arxiv.org/html/2610.00648) (10 of its tasks are inside SREGym, see
  `docs/incident-arena.md`): 20 tasks, 12 need several simultaneous fixes. On multi-fault tasks, episodes that issued
  the whole fix passed 53%, episodes that fixed only part passed 2.5% (15 of 595). Best config (GPT-6 Astra) about
  59-64%. More reasoning effort added only 4.6 points. Lesson: partial (single-cause) answers to multi-cause faults
  score near zero.
- SREGym's own problem list (`~/sregym/SREGym-fixes/Problem List.md`, 129 rows, counted by the Type and Fault Level
  columns only): Type = 38 misconfiguration, 24 cloud-management (k8s objects), 21 app software, 13 network,
  11 hardware component, 7 security, 4 database, 4 metastable, 4 multiple-independent, 3 correlated. Fault level =
  54 cluster management, 38 app, 17 container, 12 hardware, 5 OS, 3 mixed/none. Fact: most of the full set is NOT
  "one broken workload": many are k8s policy/network objects, nodes, kernel/hardware, or multi-component.

## 2. Families of RCA methods, principles, failure modes

The literature splits into five families. Each relies on a small set of general principles. Below: what the family
does, the principle, representatives, and known failure modes (facts from the cited papers; failure modes partly
from surveys/benchmarks, partly my reading, marked).

### 2.1 Graph propagation / ranking (call graph or dependency graph + anomaly scores)
- Principle: errors and latency propagate from callee to caller along the call/dependency graph, so the root cause is
  the anomalous node whose anomaly is not explained by an anomalous dependency ("follow the errors upstream until
  they stop"). Ranking via personalized PageRank / random walk biased to anomalous nodes, or via spectrum analysis
  (a node on many abnormal and few normal paths is suspicious).
- Representatives:
  - MicroRCA (NOMS 2020, [paper](https://www.researchgate.net/publication/338864142_MicroRCA_Root_Cause_Localization_of_Performance_Issues_in_Microservices)):
    attributed graph of services + hosts (co-location edges too), personalized PageRank; 89% precision on k8s injections.
  - MicroRank (WWW 2021, [code](https://github.com/IntelligentDDS/MicroRank)): traces, PageRank + spectrum analysis.
  - TraceRCA (IWQoS 2021, [code](https://github.com/NetManAIOps/TraceRCA)): "more abnormal and fewer normal traces
    through it" = more likely root; RCAEval Avg@5 0.77.
  - Groot (eBay, ASE 2021, [ACM](https://dl.acm.org/doi/abs/10.1109/ASE51524.2021.9678708)): nodes are EVENTS
    (metric anomalies, status logs, deployments/changes) not services; edges from SRE-written domain rules; PageRank.
    78% top-1 / 95% top-3 on 952 real incidents, 5,000 services. Closest published analogue to a rule-built,
    no-LLM, production RCA.
  - Murphy (SIGCOMM 2023, [pdf](https://pbg.cs.illinois.edu/papers/harsh23murphy.pdf)): loose associations between
    entities from ordinary telemetry, Markov random field, counterfactual-style reasoning.
- Known failure modes: needs a correct graph (missing edges = missed causes; TORAI
  [arXiv 2604.13522](https://arxiv.org/abs/2604.13522) shows uninstrumented "blind spot" services break trace-graph
  methods); "salience capture" (the loudest node wins even if it is a downstream amplifier, OpenRCA 2.0); dead
  components emit no telemetry and look healthy ("absence bias", OpenRCA 2.0); cycles/retries make the walk diffuse.
  Opinion: on Kubernetes, many roots are not graph nodes at all (a NetworkPolicy, a webhook, a quota, DNS config), so
  the graph must include config objects as nodes (Groot's event-graph idea), not only services.

### 2.2 Statistical anomaly scoring with a baseline (no graph)
- Principle: compare the fault period against a normal period; the metric/component with the largest robust shift
  is the root (or is near it). Temporal precedence: the earliest change point is likelier the cause.
- Representatives: N-Sigma (z-score before vs after), epsilon-Diagnosis (two-sample test),
  BARO (FSE 2024, [arXiv 2405.09330](https://arxiv.org/abs/2405.09330)): multivariate Bayesian online change-point
  detection + a robust scorer (median/IQR instead of mean/std). Nezha (FSE 2023,
  [ACM](https://dl.acm.org/doi/pdf/10.1145/3611643.3616249)): turns metrics, logs and traces into events, mines event
  patterns, and compares fault-free vs fault-suffering phases (89.8% top-1 at code-region/resource-type level).
- Findings: in "How far are we?" (Pham, Ha, Zhang, ASE 2024, [arXiv 2408.13729](https://arxiv.org/abs/2408.13729)),
  N-Sigma and BARO are among the best of 21 methods; N-Sigma is very accurate with an exact onset time but degrades a
  lot with a 1-minute onset error; BARO's robust scorer is much less sensitive. The leaderboard audit
  ([arXiv 2606.29159](https://arxiv.org/html/2606.29159)) found a trivial max-|z| probe or a shipped rank-correlation
  baseline beating every published method on several subsystems.
- Known failure modes: needs a clean pre-fault baseline and a decent onset estimate; ranks metrics, not mechanisms
  (says "cpu of frontend-proxy shifted", not "the WAF regex"); config faults that produce no metric shift
  (wrong selector, missing env) are invisible; noise injections are also anomalies.

### 2.3 Causal discovery / causal inference on telemetry
- Principle: learn a causal graph from metrics (PC, Granger, LiNGAM, DAG-GNN), or take it from architecture, then find
  the node whose own mechanism changed. Key insight from CIRCA and RCD: a fault is an INTERVENTION on the root node,
  so the root is the node whose distribution changed GIVEN its parents (the parents do not explain it).
- Representatives: CIRCA (KDD 2022, [arXiv 2206.05871](https://arxiv.org/abs/2206.05871)): graph from architecture
  knowledge, regression-based hypothesis testing per node conditioned on parents, descendant adjustment; "intervention
  recognition". RCD (NeurIPS 2022, [pdf](https://engineering.purdue.edu/dcsl/publications/papers/2022/rca-neurips22.pdf)):
  localized causal discovery around an F-node (failure indicator) with Psi-PC, no full graph. CausalRCA
  ([arXiv 2209.02500](https://arxiv.org/pdf/2209.02500)): DAG-GNN. Counterfactual: Sage (ASPLOS 2021,
  [arXiv 2101.00267](https://arxiv.org/pdf/2101.00267)), IDI (ICLR 2025, [arXiv 2505.00930](https://arxiv.org/abs/2505.00930)):
  a root cause must satisfy an anomaly criterion AND a fix criterion ("had it been normal, the target would not be
  anomalous"), estimated with in-distribution interventions. PRIM ([arXiv 2605.08786](https://arxiv.org/abs/2605.08786)):
  meta-learned Bayesian prior over causal models, graph-agnostic, zero-shot to new systems.
- Findings: in "How far are we?", plain causal discovery (PC, FCI, Granger, LiNGAM, fGES) + PageRank, RUN,
  MicroCause etc. "mostly perform similarly to Dummy" (random); only CIRCA, RCD, CausalRCA hold up, alongside the
  simple N-Sigma and BARO. Causal discovery is slow and data-hungry.
- Known failure modes: few post-fault samples; latent confounders (shared node, shared DB); learned graphs are wrong
  often enough to mislead. Opinion: the useful part to keep is the principle ("root = changed given its parents" and
  "fix criterion"), not the graph learning.

### 2.4 Learned / supervised and knowledge-based classifiers
- Principle: learn fault signatures from labelled history and match new incidents to them.
- Representatives: DejaVu (FSE 2022, [code](https://github.com/NetManAIOps/DejaVu)): explicitly for RECURRING failures;
  Eadro (ICSE 2023, [arXiv 2302.05092](https://arxiv.org/pdf/2302.05092)): multi-task GNN over logs/metrics/traces;
  RCACopilot (EuroSys 2024, [arXiv 2305.15778](https://arxiv.org/pdf/2305.15778)): per-alert-type "handlers"
  (hand-built diagnostic workflows) collect evidence, then a model predicts the root-cause category; Micro-F1 0.766 but
  Macro-F1 0.533 (rare categories much worse). MetaRCA ([arXiv 2603.02032](https://arxiv.org/abs/2603.02032)): a
  reusable type-level "Meta Causal Graph" (fault types -> symptom types) built OFFLINE from LLM knowledge, fault reports
  and telemetry; at incident time only a localized graph + live data; reports over 80% accuracy across diverse systems.
- Known failure modes: signature matching does not transfer to unseen fault types (DejaVu says so by design; RCACopilot's
  macro-F1 gap); learned models overfit the testbed. Type-level knowledge (MetaRCA) is the exception that transfers.

### 2.5 LLM agents (tool use, hypothesis-and-test loops)
- Principle: the hypothetico-deductive loop of human SREs (form hypothesis, collect evidence, test, revise), with the
  LLM generating hypotheses, commands and the final text.
- Representatives: RCAgent (CIKM 2024, [arXiv 2310.16340](https://arxiv.org/abs/2310.16340)); Roy et al. ReAct for RCA
  (FSE 2024 industry, [arXiv 2403.04123](https://arxiv.org/abs/2403.04123)); Flow-of-Action (WWW 2025,
  [arXiv 2502.08224](https://arxiv.org/pdf/2502.08224)): SOPs constrain the agent; 64.0% vs ReAct 35.5%; auxiliary
  agents remove noise, narrow the search space and decide when to stop; mABC (EMNLP 2024 Findings,
  [arXiv 2404.12135](https://arxiv.org/abs/2404.12135)): several agents vote; D-Bot (VLDB 2024,
  [arXiv 2312.01454](https://arxiv.org/abs/2312.01454)): knowledge extracted offline from docs, tree search over root
  causes, statistical tests pick which knowledge to retrieve; Stratus (above); SynergyRCA
  ([arXiv 2506.02490](https://arxiv.org/pdf/2506.02490)): Kubernetes StateGraph (spatial + temporal relations of k8s
  objects) + MetaGraph (entity-type connections) in Neo4j; LLM only reasons over graph-retrieved context; about 90%
  accuracy on real k8s failures; 1,620 lines of collection + 2,480 lines graph building vs 1,760 lines of LLM logic.
  K8sGPT ([GitHub](https://github.com/k8sgpt-ai/k8sgpt)): deterministic per-resource analyzers (pod, service, PVC,
  webhooks, NetworkPolicy, HPA, PDB, node, events, ...); LLM is optional, only for explanation.
- Findings about agents' failures (directly relevant, since our decision model plays the same role):
  - SREGym paper: greedy first-plausible-anomaly, noise capture, missing hardware layer, metastable two-component miss.
  - OpenRCA 2.0: premature commitment, absence bias, salience capture; right service 76% vs grounded path 61.5%.
  - Trajectory study ([arXiv 2608.21310](https://arxiv.org/abs/2608.21310), 5,000 trajectories): successful runs use
    retrieved evidence to steer the next query and follow fault-propagation paths; failures drift to unrelated
    services, repeat shallow queries, omit or misread evidence, or reason without support. A targeted guard
    improved Acc@1 by 3.5-35.1 points across held-out benchmarks.
  - Jev on SREGym (blog): ranking helps only if the right hypothesis is among the options.

### 2.6 How human SREs triage (the playbook the methods approximate)
- Google SRE book, [Effective Troubleshooting](https://sre.google/sre-book/effective-troubleshooting/): triage,
  examine, diagnose, test/treat; hypothetico-deductive; ask "what touched it last" (recent changes); simplify and
  bisect; beware correlation vs causation and latching onto a past failure's pattern; negative results are useful.
  The SRE book's introduction ([link](https://sre.google/sre-book/introduction/)) states that roughly 70% of outages
  come from changes to a live system.
- USE method (Brendan Gregg, [link](https://www.brendangregg.com/usemethod.html)): for every resource check
  Utilization, Saturation, Errors (a checklist that covers hardware/OS layers agents skip).
- RED method (Tom Wilkie, [link](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)):
  per service Rate, Errors, Duration; and Google's four golden signals
  ([link](https://sre.google/sre-book/monitoring-distributed-systems/)).
- Change correlation at scale: Gandalf (Azure, NSDI 2020,
  [link](https://www.usenix.org/conference/nsdi20/presentation/li)) correlates every fault signal with every ongoing
  rollout in time and space and weights by "fault age" (time between rollout and fault); 92.4% precision, 100% recall
  for bad data-plane rollouts.
- Blast radius: which callers/users are affected; the symptom set the cause must explain (and must not exceed).
- Five whys: keep asking "why" from symptom to the first actionable change; stop at the thing an operator changed.

## 3. Principles we can implement without an LLM (code collects, decision model chooses)

### 3.0 Facts about our starting point that shape this section
- SREGym exposes, through MCP, Prometheus (`get_metrics` PromQL, `get_alerts`), Loki (`get_logs`, labels) and Jaeger
  (`get_services`, `get_operations`, `get_traces`, `get_dependency_graph`) besides kubectl
  (`~/sregym/SREGym-fixes/mcp_server/*.py`).
- Neither v1 nor v2 queries Prometheus metrics, Loki or Jaeger: a grep of `clients/jev_diag/*.py` and
  `clients/jev_v2/*.py` finds only the Prometheus `get_alerts` call (`jev_diag/collector.py:1414-1462`); the rest is
  kubectl objects, events, logs, and exec probes (`jev_diag/probes.py`). So the two signal families most of the
  literature relies on (baseline-vs-incident metric shifts and trace call graphs) are unused today. Per-app trace
  coverage is not verified here.
- v2's cause knowledge is `jev_v2/patterns.py` (663 lines of regexes, thresholds and per-mechanism builders such as
  `amplify_explanations`, `stale_read_explanations`, `hidden_state_explanations`). Opinion: this is closer to
  family 2.4 (signature matching) than to a general principle, which fits the held-out results in the README.

### 3.1 The division of labour that works in no-LLM systems
Published systems that diagnose well without an LLM in the loop (Groot, K8sGPT analyzers, RCACopilot's handlers
before its classifier, MicroRCA/TraceRCA/BARO) share one shape: code enumerates candidates broadly and computes
features and quotable facts; a scorer only ranks. Our decision model is that scorer, with calibrated probabilities.
The design rule that follows (opinion, supported by the Jev blogs): the model can only pick what code offers, so
candidate RECALL is the code's job and must be measured on its own (is the true cause among the options?), separately
from the model's ranking accuracy.

### 3.2 Principle by principle: what code computes, what the model is asked, what reaches the report

| Principle (source) | Code computes (no LLM) | Typed question to the decision model | Report part |
|---|---|---|---|
| Follow errors upstream / propagation (MicroRCA, TraceRCA, Groot, SRE "follow the errors") | A typed dependency graph over ALL k8s objects, not only workloads: Service->selected pods, pod->node (co-location), pod->ConfigMap/Secret/PVC, webhook->pods it matches, NetworkPolicy->pods it selects, quota/LimitRange->namespace, CoreDNS->every pod, plus call edges from Jaeger `get_dependency_graph` and from host:port strings in env/config/logs. Each node gets an anomaly status from RED (rate, errors, duration) and USE (utilization, saturation, errors) signals, restarts, readiness. Candidates = the "unexplained frontier": anomalous nodes with no anomalous dependency that could explain them, plus config/policy nodes touching anomalous nodes. Absence-aware: a callee with zero traffic/logs while callers fail is anomalous, not healthy. | Choice: "Which candidate is the origin?" over the full frontier (not one at a time), each option with features: symptoms covered, onset order, change present, own symptoms. Yes/no: "Is X's failure explained by its dependency Y?" | D1 origin; D3 = anomalous nodes reachable downstream from it |
| Temporal precedence and recent change (SRE book "what touched it last", 70% of outages are changes; Gandalf fault age) | One change ledger: per-field managedFields writes, ReplicaSet/ControllerRevision template diffs (v1 `changes.py` already does much of this), objects created after the app baseline, deletions and missing referenced objects, image changes, node condition changes, live runtime config that differs from declared config (probe). For each change: time relative to symptom onset, the set of nodes it touches, a mechanism class from (kind, field). Score = onset proximity x overlap of touched set with anomalous set. | Choice over changes PLUS an explicit "no change explains this" option (sends the search to runtime hypotheses). | D2 concrete before->after values |
| Baseline vs incident (N-Sigma, BARO robust scorer, Nezha fault-free vs faulty patterns) | For every component: robust z (median/MAD over a pre-onset window, not mean/std; windowed so a 1-minute onset error does not matter) of RED/USE metrics from Prometheus; new log templates (template-mine logs, keep templates absent before onset); new event reasons. Separate "demand rose" from "capacity fell" (CPU usage vs CPU limit both before and after), which is exactly the edge_request_filter confusion in the v1 blog. | Mostly code ranking; model picks among the top-k shifted components/edges with their numbers. | Evidence lines with numbers (D2) |
| Root = changed GIVEN its parents (CIRCA, RCD) | For each anomalous node, check whether an anomalous parent can account for it (same symptom class, earlier onset). If not, the node's own mechanism changed. Pure code over the graph and onsets. | Yes/no only when code is unsure (e.g., overlapping onsets). | Separates origin from victim (D1, D3) |
| Counterfactual / fix criterion (IDI, Sage, Murphy) | Without a fitted causal model: for candidate c, explained(c) = symptoms reachable from c along compatible edges with compatible symptom types (from the type table, 3.3); contradicted(c) = symptoms that started before c's change or sit where c cannot reach. "Fix criterion" proxy: does c cover the user-facing symptoms (entry points, incident text)? | Pairwise choice: "Which of A and B explains the observed symptoms better?" with explained/contradicted counts shown. | Mechanism chain in D2 |
| Hypothesis-and-test (SRE hypothetico-deductive; RCACopilot handlers; Flow-of-Action SOPs; decision-theoretic troubleshooting: [Heckerman, Breese, Rommelse, CACM 1995](https://www.microsoft.com/en-us/research/publication/decision-theoretic-troubleshooting/), [Breese & Heckerman, UAI 1996](https://arxiv.org/pdf/1302.3563)) | A library of GENERIC read-only tests keyed by hypothesis type, not by problem: DNS resolve from a client pod; TCP connect to Service VIP vs pod IP vs port (separates selector/port vs NetworkPolicy vs dead pod); auth against a store with the client's own credentials; endpoints present; live store config vs default; consumer lag; retry/timeout settings on both ends of an edge; node checks (USE on node: disk, memory, conntrack, kernel messages) where reachable. Code maps each test result to supports / contradicts / unknown for each hypothesis. | Choice: "Which test next?" over tests code says are informative (each with which hypotheses it splits, cost). Stop rule: top hypothesis p >= threshold and no informative untested test left. | Test outputs are quotable evidence (D2) |
| Multiple causes and interactions (parsimonious covering, [Reggia](https://link.springer.com/article/10.1007/BF00128779); minimal hitting sets, Reiter 1987 / [de Kleer & Williams 1987](https://philpapers.org/rec/DEKDMF)) | Compute minimal covers of the symptom set: single causes, pairs of independent causes that cover disjoint symptom sets, and trigger + amplifier pairs on one edge (a load/CPU event plus aggressive retry/timeout settings), which is the metastable shape. | Choice among covers: single / pair / trigger+amplifier. | D1 and D2 for each cause (Incident-Arena grades each cause) |
| Non-greedy, noise-resistant comparison (SREGym greedy failure; OpenRCA 2.0 salience capture) | Always enumerate all candidates before asking; give coverage of the user-facing symptoms as a feature, not loudness. Mark changes that touch only healthy nodes as likely noise. | One slate question over all candidates, not "is the first one the origin?" | Avoids over-scoping (D3) |
| Characterization as slot filling | Mechanism sentence = template(kind, field, before -> after, symptom class, propagation path, affected nodes). All slots from code. | When two changes compete, ask "which is the cause and which is a side effect?" with time order and coverage shown. | D2 |

### 3.3 Type-level knowledge, written once (MetaRCA idea, K8sGPT analyzers, Groot rules)
A small table from cause kind to expected symptom classes and confirming test, written only in Kubernetes and
generic terms. Examples (opinion, generic k8s behaviour):
- Service selector or targetPort wrong -> Endpoints empty or wrong port -> callers get refused/503; confirm with
  Service VIP vs pod IP connect test.
- NetworkPolicy deny -> timeouts only from selected sources; other sources fine; confirm with connect from two pods.
- Memory limit lowered (template, webhook, LimitRange) -> OOMKilled on that workload; confirm with pod spec vs
  template vs admission.
- Credential rotated but consumer env stale -> auth errors at the store's clients; confirm with an auth test.
- DNS config broken -> resolve errors across many clients at once; confirm with a resolve test.
- Node problem -> all pods on one node affected, other replicas fine (co-location edge); confirm with node USE.
- Quota/LimitRange/admission -> pods Pending/FailedCreate with a policy reason.
- Runtime config of a store/queue differs from declared -> symptoms without any spec change; confirm by reading live config.
Generality rule (opinion): an entry may name only kinds, fields and symptom classes; never an app, a service name,
a specific value or a regex for one problem. MetaRCA reports over 80% accuracy across systems with knowledge at this
level; DejaVu-style signatures by design only cover recurring failures.

### 3.4 What a decision model is good and bad at here (from the sources)
- Good: picking among well-formed options with features, giving calibrated confidence, adding "friction" before a
  premature answer (Jev blog, 20/50 -> 24/50).
- Bad: recovering a hypothesis that was never offered; choosing the right clue when two quotable facts look alike
  (CPU limit vs regex). Both are fixed on the code side: broader candidate generation and features that separate
  cause from side effect (onset order, demand vs capacity, coverage).

## 4. Generalization: what transfers to unseen faults and what overfits

Facts first, then the opinion they support.

1. **Simple, robust, principle-level scoring transfers; complex or learned methods often do not.** "How far are we?"
   ([arXiv 2408.13729](https://arxiv.org/abs/2408.13729)): most causal-discovery pipelines are no better than random;
   N-Sigma and BARO are among the best. The leaderboard audit ([arXiv 2606.29159](https://arxiv.org/html/2606.29159)):
   a max-|z| probe or a shipped baseline beats every published method on several subsystems; a rank-correlation
   baseline has the best pooled accuracy (0.639).
2. **Rankings built on one set flip on another.** Same audit: 6 of 18 comparisons changed sign between two releases
   of the same apps; pooled rankings chose the worse method on a held-out subsystem in 8 of 36 decisions; every such
   error had a margin smaller than the between-subsystem spread. Our own README is the same story: v2 beats v1 on the
   dev set (Lite 15/17 vs 13/17 and 12/17), ties or loses on held-out A (7 and 8 vs 7 and 7) and loses badly on two
   targeted faults (update_incompatible_correlated: v2 0 and 11 vs v1 89 and 89).
3. **Signature matching covers recurring faults only.** DejaVu is built for recurring failures; RCACopilot's
   Micro-F1 0.766 vs Macro-F1 0.533 shows rare categories fail. Hand-written per-mechanism patterns are signatures,
   whether learned or typed by hand.
4. **Knowledge at the type level transfers.** MetaRCA (type-level meta causal graph, built offline; over 80% across
   diverse systems), PRIM (graph-agnostic prior, zero-shot to new systems), Sleuth
   ([ACM](https://dl.acm.org/doi/10.1145/3623278.3624758); pretrained model transfers to other apps with no or
   few-shot tuning), SynergyRCA's MetaGraph of k8s entity types, Groot's event-type rules, K8sGPT's per-kind analyzers.
5. **Coverage of hypotheses and of observation layers is the main bottleneck, not ranking skill.** Jev cannot recover
   a hypothesis that was not offered (SREGym blog). ITBench: diagnosis 13.8% with traces vs 9.5% without. ARGUS
   ([arXiv 2608.23084](https://arxiv.org/html/2608.23084)): "infrastructure reach", not model capability, was the
   main limit. SREGym paper: no agent looked at the hardware layer. TORAI: uninstrumented services break graph methods.
   Of SREGym's 129 listed problems, 12 are at hardware fault level and 5 more at OS level.
6. **Greedy, first-plausible answers do not survive noise; explaining all symptoms does.** SREGym: about 10 points
   lost to noise, agents greedy. OpenRCA 2.0: salience capture, premature commitment, absence bias.
7. **Single-cause answer spaces fail multi-cause faults.** OpenRCA: accuracy at least halves from one to two root
   elements. Incident-Arena: partial fixes pass 2.5%. SREGym: metastable faults need both interacting components.
8. **Grounded propagation paths separate real diagnosis from lucky naming.** OpenRCA 2.0: right service 76% vs
   grounded path 61.5%. Trajectory study ([arXiv 2608.21310](https://arxiv.org/abs/2608.21310)): successful runs
   follow propagation paths; a guard against omitted/misread evidence and unsupported reasoning added 3.5-35.1 points
   on held-out benchmarks.
9. **Novel faults are hard for everyone, and the frontier moves.** SREGym paper: E2E 63.7% on ported vs 17.9% on new
   problems. The postmortem blog: some problems were "no longer challenging" once newer frontier models arrived.
   Lite is now saturated on diagnosis (100%) by Devin Oncall and CloudThinker.
10. **Benchmark artifacts tempt overfitting.** Fault injection in SREGym is usually a change, so "the newest change is
    the fault" works often. It is also a real SRE principle (about 70% of outages are changes), so it is fair to use,
    but noise injections are changes too, and runtime, load, hardware and metastable faults leave no spec change.
    Opinion: use change correlation as one strong feature with an explicit "no change explains it" branch, never as
    the only path.

Opinion (what these add up to): to transfer, every rule must be stated in terms of Kubernetes kinds, generic
symptom classes and graph relations; the candidate generator must be broad and measured for recall; the answer must
explain all user-facing symptoms with the fewest causes; and evaluation must be stratified by fault family on data the
design never saw, with per-family wins reported rather than one pooled number.

## 5. Most promising ideas for our setting, ranked

Ranking = expected gain on UNSEEN SREGym faults x fit with "code collects, decision model chooses" x evidence in the
literature. All of this is opinion built on the facts above.

1. **Replace per-mechanism patterns with one generic "explain the symptoms" core.** Typed dependency graph over all
   k8s objects (workloads, Services/Endpoints, ConfigMaps/Secrets, PVCs, nodes, NetworkPolicies, webhooks, quotas,
   CoreDNS) plus call edges (Jaeger dependency graph, host:port strings). Candidates = unexplained anomaly frontier,
   absence-aware. Score by coverage of user-facing symptoms, onset order, parsimony. Refs: Groot, MicroRCA, TraceRCA,
   CIRCA's "changed given parents", parsimonious covering. Fixes v1's "not one workload" blind spot and v2's
   signature overfit at the same time.
2. **Change ledger with time-and-space correlation, plus an explicit "no change explains it" option.** Most of it
   exists in v1 `changes.py`; add spatial overlap with anomalous nodes and the "none" branch. Refs: SRE book, Gandalf.
3. **Use the telemetry SREGym already exposes: baseline-vs-incident diffs.** Robust z (median/MAD, windowed) on
   Prometheus RED/USE metrics, new log templates from Loki/pod logs, edge error rates from Jaeger. Gives evidence for
   faults with no spec change (metastable, load, runtime config, hardware) and separates "demand rose" from
   "capacity fell". Refs: BARO, N-Sigma, Nezha, the audit's max-|z| probe.
4. **A generic read-only test library with decision-theoretic test selection.** Tests keyed by hypothesis type
   (resolve, connect VIP vs pod IP, auth with client credentials, endpoints, live config, consumer lag, both ends of
   a retry/timeout edge, node USE). Code turns results into supports/contradicts/unknown; the model chooses the next
   test and when to stop. Refs: decision-theoretic troubleshooting (Heckerman, Breese, Rommelse 1995; Breese & Heckerman 1996), RCACopilot handlers, Flow-of-Action SOPs, SRE hypothetico-deductive.
5. **An answer space with two causes and trigger+amplifier pairs.** Code computes minimal covers; the model picks
   single vs pair. Refs: Reiter / de Kleer-Williams hitting sets, Reggia; Incident-Arena, OpenRCA, SREGym metastable.
6. **Slot-filled characterization and graph-computed scope.** D2 sentence from (kind, field, before -> after, symptom
   class, path); D3 = anomalous nodes reachable from the root, which also keeps noise components out. Ask the model
   "cause or side effect?" when two quotable facts compete (the WAF regex vs CPU limit case).
7. **Ask slate questions, not greedy yes/no walks.** One choice over all candidates with features; use calibrated
   probabilities to abstain or look further. v1 in practice makes 2 calls (v1-architecture.md) and v2's go-back
   almost never runs (v2-audit.md), so the loop should be driven by information value, not by a fixed shape.
8. **Type-level knowledge table with a generality lint.** Cause kind -> expected symptom classes -> confirming test,
   only in k8s and generic terms; reject any rule naming an app, service or problem-specific value. Ref: MetaRCA.
9. **Evaluation discipline.** Measure candidate recall separately from ranking; stratify held-out sets by fault family
   (misconfig, k8s object, network, hardware/OS, app/store, metastable, multi-cause); report per-family wins and
   paired differences with intervals; keep sample C untouched until the end. Ref: the audit paper's reporting format.
10. **Cover the hardware/OS layer with a USE checklist** (disk errors, memory pressure, conntrack, port range, kernel
    messages) where cluster access allows. 12 hardware-level and 5 OS-level problems exist and agents score near zero
    on them, so even partial coverage is a differentiator. Uncertain: what node-level access the diagnosis stage allows.

## Open uncertainties
- Whether Jaeger traces and pre-injection Prometheus history are present for every SREGym app in the diagnosis stage
  (MCP tools exist; coverage not verified here).
- How Devin Oncall and CloudThinker work internally (no public write-up found; the CloudThinker driver in
  `clients/cloudthinker/README.md` supports a seeded-memory "recall arm", but whether leaderboard runs used it is unknown).
- Some 2026 papers (MetaRCA, PRIM, ORCA-bench, auditable graph-guided RCA) were read from abstracts or tool summaries
  only; their numbers should be re-checked before being quoted outside this team.
