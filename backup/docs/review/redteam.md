# Red-team review of STRATEGY.md (2026-10-19)

Status: DONE (2026-10-19).

Scope. Read README.md, STRATEGY.md and the seven evidence reports in this folder, plus code in
`~/sregym/SREGym-fixes` (`clients/jev_diag/{probes,classifier}.py`, `clients/jev_v2/arms.py`,
`mcp_server/{prometheus,jaeger,loki}_server.py`, `sregym/conductor/{conductor.py,problems/base.py}`) and
`runs-index.tsv`. Nothing in `sealed/` was opened. `UNSEEN-SEALED.txt` was checked only for its structure (comment
lines and line lengths, never the ids). No problem file, run or table row of a sealed problem was read. No other
reviewer's file was read. Read-only otherwise.

Severity = likelihood x impact, each High / Medium / Low. **Critical** = High x High. **High** = High x Medium.
**Medium** = Medium x Medium or High x Low. **Low** = the rest.

## 0. Short version

The diagnosis of what went wrong is mostly right, and the direction (general core, wider answers, more evidence,
report shaped for the judge) is sound. But as written the plan would repeat v2's mistake in a new form, and its test
is weaker than it claims. The ten things that matter most follow.

1. **Unseen is not unseen (O1, Critical).** The landscape analyst read every non-C problem file, and STRATEGY.md was
   written from that unredacted table before the seal. Two of every three pool faults the author could read about
   are in Unseen. Only sample C is clean. The seal also leaks (plaintext ids, row-numbered text in the landscape),
   and no sealed reserve is left (O2, O3).
2. **Development cannot exercise the design (O4, Critical).** Lite has no node or multi-component fault, two runtime
   faults and no blueprint-hotel fault, and the fresh 30 exclude every studied fault type by rule. Every stage check
   is on Lite, so the new parts meet their target shapes for the first time in the final run.
3. **The candidate space will be won by hubs, distractors and innocent changes (N1-N3, Critical).** "Symptoms it can
   reach" favours CoreDNS, nodes and the telemetry collector; the slate cut decides recall; harness restarts,
   leftovers and decoys all count as "changed". Each has already cost real runs.
4. **The look-closer step is unlikely to work as drawn (N5, N6, N12).** The two asks disagree only 12-20% of the
   time; many real pairs have no read-only test; probes have side effects (one already OOM-killed a Kafka broker);
   and live per-arm tests break "one snapshot per fault".
5. **"Name both objects" does not say which one leads (N7), and the D2 sentence has no design (N13).**
6. **Telemetry has no baseline in most problems (N4, F27).** `baseline_duration_s` defaults to 0 and the fault is
   injected right after deploy; the MCP tools give instant PromQL, 20 traces and 100 log lines.
7. **Fact errors.** v1 can already lead with a ConfigMap, webhook, quota, role or NetworkPolicy (F10, F19); the 42%
   figure is of 107 problems and "both weak" is measured only for runtime and load faults (F13); v1 has no
   `CONFIG GET` or credential login probe (F18); a "path" origin fits one Lite fault (F22); the pool was not
   untouched (F23).
8. **Goals overstated.** +15 points is detected only about half to four fifths of the time, not "the smallest gain we
   can prove" (F15); "no more tokens than v1" conflicts with the design and the audit, and the real limit is request
   size for 32k-context models (F17, N10).
9. **Missing fault shapes.** Re-created and new workloads with no baseline, feature-flag ConfigMaps with no old
   value, load-driven exhaustion that names the server, retry-storm evidence, runtime checks that need credentials,
   node co-location, deleted objects, and a noise check (section 4.2).
10. **Fix order.** Re-state and re-seal Unseen and widen the development set first; then collect once per fault and
    decide many times; then candidates with effect evidence; then the report contract; telemetry last (section 5).

---

## 1. Fact-check of STRATEGY.md

Verdicts. OK = supported by the reports or code. Overstated = true in part, stronger than the evidence. Wrong =
contradicted by the reports or code. Unsupported = an opinion or causal claim stated as evidence.

| # | Claim (STRATEGY section) | Verdict | Evidence and correction |
|---|---|---|---|
| F1 | "v2 was a closed list of hand-written fault stories. Its 20 rules in patterns.py match the 17 Lite faults" (1) | Overstated | v2-audit section 2 sorts the 20 rows into 11 general principles (mostly thin wrappers over v1 checks), 6 fitted rules plus 2 fitted add-ons, and 3 plumbing rows. What matches Lite is the set of pattern *families* (change, acts-on, amplify, bad-input, hidden-state) and two pseudo-origins. "Closed list" is fair; "20 rules match 17 faults" is not. |
| F2 | "12 of 15 commits added or tuned a rule right after one failed run" (1) | OK | v2-audit section 2, commit pattern. |
| F3 | "held-out 7 and 8 vs 7 and 7; set T 1 of 4 arms vs 3 of 4" (1) | OK, with two caveats | Numbers match forensics section 1. But sample A was tuned on (6 v2 commits landed between the first and last sample-A runs, v2-audit) and the Lite headline ran on 30dd021e, not the latest code. eval-methodology 1.4 shows none of these gaps is significant (sign-test p 0.50 to 0.75). "Ties or loses" is a direction, not a measurement. |
| F4 | "It is signature matching, which only covers faults already seen" (1) | Opinion | Reasonable reading (sota 2.4 and 4.3), but not measured. Label it as interpretation. |
| F5 | "The model saw 432 supports against 56 contradicts" (1) | OK | v2-audit section 3 (65 decision requests, 368 options, on 30dd021e and 066c4d2f). |
| F6 | "The true cause was ahead on checks in only 28 of 56 decisions, which is why we kept seeing near ties" (1) | Numbers OK, causal part unsupported | The true cause was behind in only 6 of 56; 22 were ties. decision-models 3.2 shows the model overrode the code ranking in both directions (Jev fixed 16 asks and broke 12) and near ties on v2's decide question were 17% (Jev) and 8% (Decisions). Nothing links the near ties to check ties. |
| F7 | "Its 'look closer' step never ran. It made a second round in 2 of 82 runs, because it re-read what it had already read" (1) | Count OK, wording self-contradicting | "Never ran" vs "2 of 82". The folder holds three different counts for the same thing (README 1 of 56, forensics 0 of 58 in-scope arms, v2-audit 2 of 82); state one with its scope. Also, before 6fec2c91 the second round ran in 27 of 78 arms, and in the documented case (secret_rotation `final`, Decisions) it moved the pick from right to wrong (forensics 5.2 item 5). So the evidence that "looking closer" helps is thin, not just that it was switched off. |
| F8 | "v1 makes 2 model calls in 39 of 44 runs" (1) | OK | v1-architecture section 6. |
| F9 | "v1's strength is ... a library of neutral Kubernetes fact detectors ... plus recent change before the symptoms" (1) | Unsupported as fact | v1-architecture 7.3 says this is inferred from which runs pass, with no ablation. Those detectors were also written for the blog's 21-fault Lite cohort (v1-architecture 3.2, "fault-shaped special paths"; v2-audit section 5 calls v1's derive/checks "fault-shaped rules"). It is a strength on Lite-like faults, which the fresh Unseen draw excludes by rule (see O4). |
| F10 | "It can only name one workload, never a ConfigMap, topic, node or interaction as the cause" (1) | Wrong in part | `classifier.build_diagnosis_text` leads with "Root cause object: <kind> <name>" for carrier kinds (webhooks, ResourceQuota, LimitRange, roles and bindings, NetworkPolicy; classifier.py 645-655 and 852-855) and whenever the cluster node concludes (classifier.py 825-829). That is how v1 named the CoreDNS ConfigMap and scored 89 on both DNS faults when it reached the cluster node (forensics 2.6 and 2.12). Correct statement: v1 cannot name a topic or an interaction, and reaches cluster objects only when a workload's origin probability happens to stay under 0.6 (W1). |
| F11 | "a few plain bugs (CoreDNS ordering, revision diffs that never become signals, probe timing dropped)" (1) | OK | v1-architecture W1, W3, W5. |
| F12 | "Top LLM agents already score 100% diagnosis on [Lite]" (1) | OK | sota section 1 leaderboard (3 attempts per fault). |
| F13 | "The full SREGym has 117 problems, and 42% of them sit where both pipelines are weak: runtime state 17%, interactions 10%, node faults 7%, several causes 6%, plus outside objects" (1) | Overstated | The shares are of the 107 non-C problems, not 117. 42% is RT + IX + NI + MC + IN (45 of 107); IN (3%) is in the sum but not named. "Both pipelines are weak" is measured only for RT (arms passing v1 1/4, v2 0/4) and IN (0/10, 2/10). Interactions passed 6 of 8 arms for both, MC passed 2 of 2 for v1, and no node fault was ever run (landscape 4.4). And these shares describe the whole benchmark, while the Unseen pool is limited to four apps; landscape 2.2 puts RT mostly in Incident Arena, GitLab, Stripe and newer astronomy-shop problems, and only the last are in those apps. |
| F14 | "Both pipelines use only kubectl and Prometheus alerts. Neither touches the metrics, traces or logs SREGym provides" (1) | Mostly OK, misleading on logs | No PromQL, Jaeger or Loki (sota 3.0). But both read pod logs through kubectl (current and `--previous`) and `kubectl top`. Say "neither uses PromQL, traces or Loki". |
| F15 | "15 points more ... With 40 faults that is the smallest gain we can prove" (2) | Overstated | eval-methodology 2.3: with one model, a real +15 is detected 49% of the time; the 10-model pooled simulation gives 78-92%, under an untested assumption about how independent models are. The plan pools 5 models, so expect somewhere between. A true +15 gain ends "not proven" in roughly 1 run in 5 to 1 in 2. The goal mixes a target with a detection limit. |
| F16 | "works on 5 decision models" (2) | Inconsistent | README says the pipeline should work across about 10 OpenRouter models. Pick one and say which are for development and which are held back (see N11). |
| F17 | "uses no more tokens than v1" (2) | Conflicts with the evidence and the design | v2-audit section 6 recommends "do not trade evidence for tokens" (cost < $0.004 per diagnosis). The design adds PromQL, traces, Loki, outside objects, two asks per slate and re-asks after tests. The real limit is request size per model (Jev long-context mode above ~32 kB; d1-ultra and Microsoft-Decision-1 have 32k context; decision-models 1 and 5), not tokens per run. |
| F18 | Probes "such as a DB auth check, Valkey `CONFIG GET` or Kafka offsets, which v1 has but never runs" (3.3) | Wrong in part | `probes.py` has Kafka consumer offsets (sampled twice) and protocol pings (valkey/redis PING, pg_isready, mongo ping, mysqladmin ping) whose output is mapped to meanings such as "requires authentication". There is no `CONFIG GET` and no login with the client's credentials. The same file records a real side effect: a JVM tool OOM-killed a memory-capped Kafka broker. |
| F19 | v1 bug "outside objects never leading the report" (3.1) | Wrong in part | See F10. True only for non-carrier objects (ConfigMap, Secret, Service) when a workload is concluded. |
| F20 | "All are general fixes to v1's own code" (3.1) | Overstated | "First origin above 0.6 wins" and "false links from relayed names" are design changes, not bug fixes. Both live in the walk that stage 3 replaces, so stage 1 effort on them is thrown away. |
| F21 | "the ground truth names one or the other depending on the problem" (3.2) | OK | landscape 2.3, also visible in unsealed faults alone (CoreDNS ConfigMap vs `service/url-shorten-mongodb` vs `service/valkey-cart`). But naming both does not settle which one leads (N7). |
| F22 | Origin can be "a path between two services" (3.2) | Lite-fitted | landscape 2.3: 1 of 107 ground-truth origins is an interaction path, and it is a Lite fault. v2-audit lists the `interaction/` pseudo-origin under "should not survive". The retry-storm faults outside Lite name a ConfigMap. Express interactions as two concrete objects (trigger and amplifier), not as a path object. |
| F23 | "30 fresh faults drawn by seed from the untouched pool" (4) | Wrong | benchmark-landscape read every problem file except sample C before the seal ("Sources read") and described each one's mechanism, ground-truth form and evidence. STRATEGY.md (modified 14:41) was written before the seal (UNSEEN-SEALED.txt and the redacted landscape, both 14:44). README's "~55 problems nobody has looked at" and "ids only, hashed" are also inaccurate; the file holds the ids in plain text plus a hash of the list. See O1-O3. |
| F24 | "All models share one snapshot per fault" (4) | Partly | The snapshot is shared, but every arm reads component detail live (`arms.py` docstring; `collect_component_detail` per arm) and arms run one after another, so later arms see a later cluster. The planned tie-break tests would also be live and per arm. |
| F25 | "Cost is about $3 of the $4.64 left, and the run takes about one night" (4) | Plausible, not derived | eval-methodology 2.7 gives ~$1.8 total for 6 models and ~$3.0 for 10, at today's ~$0.002 per arm. The new design's larger states and extra asks raise the per-arm cost, and live probes and telemetry queries add minutes per arm (Kafka sampling alone is 2 x 15 s plus JVM start). Re-price after stage 2 on one Lite fault. |
| F26 | Stage 1 check "Lite: at least v1 on every fault" (5) | Gate is noise-bound | v1 + Decisions flips pass/fail in 8% of run pairs (eval-methodology 1.2). Over 17 faults and 2 models, one to three chance flips are expected per comparison, so the gate fails or passes by luck and invites per-fault patching (O5). |
| F27 | Open question 1, telemetry coverage "not verified" (6) | OK, and worse than stated | `problems/base.py` sets `baseline_duration_s = 0` (only 2 problem files override it); the load starts at deploy and the fault is injected right after (conductor.py ~700-720, ~1494-1497). So most problems have no steady-state window before the fault. The MCP Prometheus tool is an instant query (`/api/v1/query`), Jaeger `get_traces` returns at most 20 traces, Loki at most 100 lines. |

---

## 2. New failure modes the design would introduce

Each item says what goes wrong, the evidence, severity, and a general mitigation.

### N1. "Which symptoms it can reach" rewards hubs and punishes the true cause (Critical)
- What. Reachability over a typed graph favours objects connected to everything (CoreDNS, nodes, quotas, the
  telemetry collector every pod points at, the frontend). The true cause often has missing edges (`rate` had no
  Mongo address in env; the flood Job's target sat in a base64 command; addresses in config files).
- Evidence. The v2 "dependency" winner passed 3 of 8 times; missing_env Jev picked the otel collector because
  telemetry endpoints in four components' env made it "reach" five components (forensics 2.2, 5.2 item 1).
  sota 2.1 lists missing edges and salience capture as the main failure modes of graph methods.
- Likelihood High, impact High.
- Mitigation. Never show a raw reach count. Show "symptoms it explains with a compatible mechanism" (cause kind to
  symptom class table, sota 3.3) and "symptoms it cannot explain", plus specificity (share of the objects it acts on
  that are actually unhealthy). Tag every edge with its source (trace, env address, config file, error text). A
  missing edge is "unknown", never "cannot reach". Measure edge precision and recall on development faults where
  traces exist.

### N2. A wider candidate space brings more distractors, vote splitting and shortlist cuts (Critical)
- What. Every object kind becomes a candidate. Something must cut hundreds of objects to 2-7 slate options, and
  that cut is a code verdict that decides recall.
- Evidence. v2's TOP_K = 6 cut two of the six image bumps, and its focused state hid them from the model
  (forensics 2.1). Three near-identical options split the vote and "none" won in env_shadowing (forensics 2.13).
  When the right option is missing, Decisions puts only 0.11 on "none" and picks a wrong option confidently
  (decision-models 2.6).
- Likelihood High, impact High.
- Mitigation. Group options by origin and merge near-duplicates before asking; sum probabilities per origin. Fill
  slots by family (one per family that has evidence, such as workload change, config object, cluster object,
  runtime/no-change, load) instead of top-k by score. Measure recall at the slate, after the cut, not at the
  generator. Keep a code-side coverage check rather than trusting "none of these".

### N3. "Whether it changed" is true of innocent objects (Critical)
- What. The strongest prior in both pipelines is "recent change before onset". The harness, the injectors and
  earlier problems all write changes too.
- Evidence. A harness `restartedAt` annotation on the otel collector became v2's winner in missing_env (11).
  A leftover CoreDNS edit from an earlier problem caused three zero scores and a near tie (forensics 4,
  eval-methodology 1.2). Injectors restart victims or pin pods (landscape 2.4). The benchmark ships inert decoy
  webhooks and other decoys on purpose (landscape 2.4).
- Likelihood High, impact High.
- Mitigation. Type change records by field; an annotation-only restart is "restarted, no config change" and is never
  a cause on its own. Require effect evidence for a change to be a candidate (the pod differs from its template,
  endpoints changed, events or errors cite it, the symptom class fits). Use the conductor's own order. The app is
  undeployed and redeployed for every problem (conductor.py, `undeploy_leftovers` then `deploy`), so a change that
  predates the app namespace's creation cannot be this problem's fault. Demote changes that touch only healthy
  objects.

### N4. Telemetry with no baseline, tiny samples and absence bias (High)
- What. "PromQL before vs after onset" assumes a healthy window. Most problems have none.
- Evidence. `baseline_duration_s = 0` by default; the load starts at deploy and injection follows immediately
  (F27). The Prometheus tool is an instant query; Jaeger returns 20 traces; Loki 100 lines. Jaeger is itself an app
  component in Social Network (duplicate_pvc_mounts_social_network's ground truth is `deployment/jaeger`), so the
  trace source can be the fault. The load generator is hidden from agents (landscape 4.1). sota 2.2 reports that N-Sigma
  degrades badly with a one-minute onset error. OpenRCA 2.0's "absence bias" (no spans read as healthy).
- Likelihood High, impact Medium.
- Mitigation. Settle coverage in stage 0 on Lite apps before building. Prefer contrasts inside the incident window
  (replica vs replica, caller vs non-caller, sibling services) over a historical baseline. Carry an explicit
  "no baseline" flag. Missing telemetry is "unknown", never "healthy" or "contradicts". Use `offset` and subqueries
  for windows since the tool has no range API. Telemetry facts describe candidates; they do not create them until
  development shows they help.

### N5. Probes have side effects, fail, or cannot run (High)
- What. Exec probes and connect/auth/resolve tests run inside a live, failing system.
- Evidence. A JVM probe already OOM-killed a Kafka broker (`probes.py` docstring). Exec into host-network pods is
  refused in filtered mode (landscape 4.1). Distroless images lack the tools (`_missing_binary`). An auth test "with
  the client's credentials" needs Secret values, which v1 deliberately never reads. Failed logins write new error
  lines that the pipeline will then read as symptoms, and some servers block a client after repeated failures.
  Connect tests use ports and conntrack entries, which is exactly what exhaustion faults are about. A crash-looping
  pod can restart mid-probe.
- Likelihood Medium, impact High.
- Mitigation. Keep the memory headroom gate and strict timeouts. Three outcomes only (confirms, refutes,
  inconclusive); every error, timeout, missing binary or refused exec is inconclusive, never refutes. No
  credentials unless open question 2 is answered yes in writing. Record each probe's time window and drop log lines
  from that window in later reads. List each probe's side-effect class and ban anything that leaves state behind
  (sessions, consumer groups, objects). Run the probe library once per fault in collection, shared by all arms
  (see N12), not per arm.

### N6. Tie-break tests do not exist for many hypothesis pairs, and the trigger is too narrow (High)
- What. "When the two asks disagree, run a test that separates the top two." Many real pairs have no read-only test,
  and disagreement is rare.
- Evidence. Pairs from our own failures that no read-only test separates include two fields of one revision (regex vs CPU limit,
  edge), the trigger vs the victim of one story (flood Job vs valkey-cart), the changed object vs the workload it
  breaks (auth_miss, a framing question rather than a test question), probe settings vs a script in a ConfigMap
  (liveness). The asks disagree only 12.5% (Jev) and 20% (Decisions) of the time, while about a third of decisions
  are "unsure" and agreeing asks are still wrong 12-15% of the time (decision-models 2.3, 2.4).
- Likelihood High, impact Medium.
- Mitigation. Trigger on disagreement OR a leader below a per-question level OR a top-two margin under 0.2. Write
  an explicit table from hypothesis-pair type to test or "no test", and measure its coverage on development faults.
  With no test, ask a two-option "cause or side effect" question in both orders (decision-models 3, item 8). If still
  unsure, fall back to the candidate with change plus effect evidence, which was the robust default (forensics 5.3).

### N7. "Name both objects" does not decide which one leads, and can over-scope D3 (High)
- What. The judge's D1-Q1 checks the object named as the origin; D1-Q2 checks that the origin is kept apart from
  cascade points; D3-Q1 penalises extra blamed components and is the noisiest question.
- Evidence. The same two-object shape scored 100 (wrong_service_selector, Service as fault object) and 55
  (CoreDNS faults, "Root cause component: Deployment frontend" plus the ConfigMap), and v2's ConfigMap-first line
  lost auth_miss (landscape 3.3 and 5.1; forensics 2.3). D3-Q1 flipped 5 of 73 times on identical text
  (eval-methodology 1.1).
- Likelihood High, impact Medium.
- Mitigation. A general lead rule by fan-out, checkable on unsealed faults alone. If the changed object acts on many
  components (cluster-scoped, namespace-wide, or used by two or more workloads), it leads. If it is used by exactly one
  workload or Service, that workload leads, named with both kinds ("Service and Deployment X"), and the changed object
  follows as the means ("through ConfigMap Y, field Z"). Never write a second "root cause" label. Regrade existing
  Lite, A and T texts rewritten under the rule (no new runs needed) and count flips before adopting it.

### N8. "Same change on N workloads" grouping turns noise into a big candidate (Medium)
- What. A harness restart or a Helm write across many Deployments looks like "one change on N components" with
  the widest reach.
- Evidence. Harness `restartedAt` writes exist (forensics 2.2); the grouping is new, so no run evidence yet.
- Likelihood Medium, impact Medium.
- Mitigation. Group only identical non-trivial edits (same field path and same new value) on two or more objects,
  never annotation-only or restart-only edits, and only when most members are unhealthy.

### N9. Trigger + amplifier and two-cause covers multiply spurious options (Medium)
- What. Any load signal plus any retry setting forms a "pair".
- Evidence. v2's `amplify` fired on any "connectivity or timeout" error, including `Connection refused`, in six
  non-Lite runs and won only on the Lite fault it was written for (v2-audit section 2, row 12).
- Likelihood Medium, impact Medium.
- Mitigation. Offer a pair only when no single candidate explains the user-facing symptoms (parsimony), require
  separate effect evidence for each side, and cap pair options at two per slate.

### N10. Request size outgrows small-context models (High)
- What. More sources, per-candidate fact cards, two asks and re-asks.
- Evidence. v1's triage state is already 40-48k characters and always in Jev's long-context mode. d1-ultra (in the
  plan) and Microsoft-Decision-1 have 32k context; at 16k only 56-82% of v1 requests fit (decision-models 2.1, 5).
- Likelihood High, impact Medium.
- Mitigation. Replace the token goal with a per-request cap (for example 30 kB for every model), enforced by a
  priority ladder that never trims the facts of options on the slate. Drop questions that never vary
  (`fault_visible` was 1.0 in 160 of 160 asks). Measure fit per model in stage 2.

### N11. Per-model calibration drift, and tuning on the same models used to judge robustness (Medium)
- What. The same probability means different things per model and question; new models are unmeasured.
- Evidence. Jev at 0.7 is about as trustworthy as Decisions at 0.9; "none" use 0.30 vs 0.11; Decisions says "yes"
  to the candidate it is asked about 16 of 26 times (decision-models 2.3, 2.6, 4).
- Likelihood Medium, impact Medium.
- Mitigation. Gates based on rank and agreement only. Any per-model mapping is fitted on pooled request-level data
  from all development runs (hundreds of asks), then frozen. Hold one model out of all development and use it only
  in the final runs, as a direct test of quirk-tuning.

### N12. Live reads drift across ten sequential arms, and runs get slow (Medium)
- What. With 5 models x 2 pipelines, arms run one after another and each reads detail live; v2 arms would also run
  live tests.
- Evidence. `arms.py` runs arms sequentially with live `collect_component_detail`; restarts grow and logs roll
  between arms. v2's `replay.py` does not re-read detail, so replays are not faithful (v2-audit section 4).
- Likelihood Medium, impact Medium.
- Mitigation. Collect everything once before any arm (detail for every unhealthy component and its neighbours,
  telemetry, the probe library), store it, and make every arm a pure function of that bundle. This keeps one
  snapshot per fault, removes arm-to-arm interference, makes replays exact and makes development cheaper.

### N13. The mechanism sentence (D2) has no design (High)
- What. The new core picks an origin; nothing says how the quoted fact and concrete values are chosen.
- Evidence. On held-out faults 8 of 20 v2 arms were decided by v1's key-fact step, and that step is where edge
  (CPU limit chosen over the regex) and liveness (script chosen over the probe) failed (forensics 5.1, 2.5, 2.11).
  Missing concrete values cost D2-Q2 in nearly every arm of three fault families (liveness 8 of 8, hostPort
  conflict 8 of 8, sidecar 7 of 8; landscape 3.3 item 4).
- Likelihood High, impact Medium.
- Mitigation. Build the mechanism sentence from slots (object, field, old to new value, effect evidence, symptom
  class). When one revision changed several fields, ask which field change produces the observed symptom class, with
  the class shown. Quote every changed field of the winning revision in a short "changed fields" line.

### N14. No-change faults have no path, because the model rarely says "none" (High)
- What. Runtime and load faults leave no spec change, so the best-looking change wins anyway.
- Evidence. valkey_auth (runtime `requirepass`) failed in every arm of every run; Decisions puts 0.11 on "none" when
  the answer is missing (forensics 2.8, decision-models 2.6).
- Likelihood High (for these faults), impact High; how many such faults are in Unseen is unknown, so rated High.
- Mitigation. Code builds an explicit "no recorded change explains this" candidate whenever the strongest change
  lacks effect evidence, carrying the probe and telemetry facts. Do not rely on the model's "none".

### N15. Hidden causes have no node in the graph (Medium)
- What. Chaos Mesh delays and the load generator are hidden from agents by policy; only their effects show.
- Evidence. landscape 4.1 (agent visibility policy); missing_stale_cache_fallback's delay is a Chaos Mesh object.
- Likelihood Medium, impact Medium.
- Mitigation. An "unobserved external factor on edge A to B" candidate when edge latency or load shifts and neither
  end changed.

### N16. Observability components handled by name (Medium)
- What. v1 demotes telemetry components by a name regex; v2 skipped them in some builders and not others.
- Evidence. A Lite ground truth is `deployment/jaeger`; the otel collector is a frequent harness-noise winner
  (v1-architecture 4.10, v2-audit row 17).
- Likelihood Medium, impact Medium.
- Mitigation. No name-based rule. Telemetry export errors are their own symptom class and never point anywhere; an
  observability component is a candidate only through its own effect evidence, like any other.

---

## 3. How the plan could still overfit, and how Unseen information could leak

### O1. The 30 fresh Unseen faults were studied before the seal (Critical)
- Facts. benchmark-landscape lists as read "`sregym/conductor/problems/*.py` (all except the 9 sample-C files)",
  the injector files and the ground-truth files, and described every row's mechanism, ground-truth form and needed
  evidence. STRATEGY.md was last written at 14:41; UNSEEN-SEALED.txt and the redacted landscape are from 14:44.
  The sealed file's own comment says the 30 were drawn from a pool of 45, so two of every three pool faults the
  strategy author could read about are in Unseen.
- Where it shows in the plan. The evidence priorities follow landscape 4.3 counts ("PromQL for about 12, traces for
  about 9, outside objects for about 13, probes for about 15"), which include rows now redacted. The named list of
  outside kinds in design item 3 was written from the unredacted table; checking by row number only, I found one or
  more named kinds whose only support in the reports is a now-redacted row. The report rules use ground-truth forms
  counted over all 107 problems, Unseen included.
- Impact. An Unseen gain can no longer be called a gain on faults "nobody has looked at". Code and runs were not
  seen, but fault descriptions were.
- Mitigation.
  1. Say this plainly in the pre-registration and in any later write-up.
  2. Before building, do a provenance pass. Every design element cites an unsealed fault, a studied run or a general
     Kubernetes or protocol fact. An element whose only support is a redacted row is rewritten in generic form (for
     outside objects, collect every namespaced and cluster-scoped kind from `kubectl api-resources` and run the same
     change and effect logic over all of them, instead of a named list).
  3. Report sample C separately. Its files were never opened by anyone (landscape skipped them), so it is the
     cleanest part of Unseen, even though 10 faults prove little on their own.
  4. If a truly fresh check is wanted, the SREGym paper describes 3,623 viable fault-component pairs from 47 fault
     primitives (sota 1). If the injector library can instantiate pairs outside the curated set (uncertain), the user
     could generate a small set by script that nobody reads. Otherwise, wait for new SREGym problems.

### O2. The seal itself leaks (High)
- Facts. UNSEEN-SEALED.txt holds the 40 ids in plain text in the analysts' folder; README calls them "hashed". The
  seed and pool rule are in the same file, so the draw can be roughly recomputed from the registry. The landscape's
  redaction blanks table rows, but sections 2.3, 2.4, 4.3 and 5 still describe redacted rows by row number
  (mechanism, ground-truth form, decoys, needed evidence). Any agent told to read the landscape learns about Unseen.
- Likelihood High, impact Medium (it lowers trust in the result rather than changing it).
- Mitigation. Keep only the sha256 in this folder and move the plaintext list and seed somewhere agents are not
  pointed to. Re-redact those landscape sections or move them to `sealed/`. Add a read-deny hook for sealed paths.

### O3. No sealed reserve is left (High)
- Facts. eval-methodology 2.2 item 5 keeps the undrawn faults sealed as the one clean re-test after any change made
  post-Unseen. The 15 undrawn pool faults are ordinary, unredacted rows in the landscape and were read.
- Impact. After the Unseen run, any fix has no honest test this cycle.
- Mitigation. Decide now, before building. Either split the 40 by seed into a test part and a sealed reserve
  (less power), or record that the Unseen run is final for this cycle.

### O4. The development set cannot exercise what the design is for (Critical)
- Facts. Lite has no node fault, no multi-component fault and two runtime faults (landscape 2.1). No Lite, sample-A
  or set-T fault runs on blueprint-hotel, and no run in `runs-index.tsv` uses it, yet the Unseen pool includes that
  app. The fresh draw excludes "same-fault-type variants of studied faults" (sealed file comment), so the 30 are
  fault types v1's Lite-built detectors were never written for. Every stage check in STRATEGY is on Lite.
- Impact. Stages 2 and 3 cannot show that the new sources or the new core work on the shapes they target. Their
  first real test is the Unseen run. That is how v2 failed.
- Mitigation. Use a wider development set made of Lite + sample A + set T + unsealed runnable faults outside Unseen, chosen to
  include at least one blueprint-hotel fault and examples of runtime, interaction, node and load faults. Before using
  any of them, the runner runs a script that drops faults sharing an injector method or fault class with a sealed
  fault and prints only the kept list. Gate stages on this set's totals, not on Lite.

### O5. A per-fault Lite gate invites patching (High)
- Facts. 12 of v2's 15 later commits came right after one failed run (v2-audit). STRATEGY's stage 1 gate is "at
  least v1 on every Lite fault", which run noise alone breaks (F26).
- Mitigation. Gate on totals over the wider set with a noise band declared in advance (for example, within 2 faults
  of v1). No commit or comment names a fault. Work from a written gap list (v1's W1-W14, this review), not from the
  latest failure. Keep an ablation table per rule; a rule whose removal changes only one development fault is
  reviewed as a likely fit.

### O6. The generality lint checks strings, not structure, and clashes with the probe plan (High)
- Facts. v1's detectors use Kubernetes words only, yet each was built for a seen family (v1-architecture 3.2); a
  string lint passes them all. The plan's own probes are per technology (Valkey, Kafka, databases), which the rule
  "only Kubernetes kinds, fields and symptom classes" forbids. Thresholds, slot order and the choice of which
  detectors exist are fitting a lint cannot see.
- Mitigation. Three tiers of allowed knowledge. Tier 1, Kubernetes semantics. Tier 2, public protocol knowledge,
  keyed by image, port or protocol and never by app or service name. Never, app or service names and problem
  values. Each rule cites the general fact it encodes. Add the ablation table from O5. A script the user runs
  compares string literals in the new code with literals in all non-Lite problem files and prints only a count.

### O7. Per-category Unseen results need someone to label Unseen faults (Medium)
- Mitigation. The runner's script joins categories from the sealed table. Report only cells with at least 5 faults
  and pool the rest. Per-fault results stay closed until the decision is written (eval-methodology 2.8).

### O8. Builders can read sealed material by accident (High)
- Facts. The SREGym tree holds every problem file, `Problem List.md`, `registry.py` and the ground-truth files. A
  routine grep for a Kubernetes or protocol word while building ("coredns", "requirepass") prints sealed problem code.
  eval-methodology 2.8 bars agents from problem files outside Lite; STRATEGY does not adopt the rule. Unseen run
  outputs would land under `results/` beside development runs, and `runs-index.tsv` would list them.
- Mitigation. Build in a worktree with sealed problem files, list rows and ground truths removed. Read-deny hook.
  Unseen runs write to a sealed folder that the index does not cover.

### O9. The primary metric pools models that will never be submitted (Medium)
- Facts. Three of the five models are for robustness only (decision-models 5). A design that gains only on them can
  pass the primary test; the guard limits losses on Jev and Decisions but asks for no gain there.
- Mitigation. State which pool is primary. If the five-model pool stays primary, add "the pooled gain on Jev and
  Decisions alone is not negative".

### O10. Picking design variants by looking at many models on a small set (Medium)
- Mitigation. Compare variants with the same paired sign test on the wider development set. When a difference is
  not proven, keep the simpler variant.

---

## 4. What is missing

### 4.1 Known v1 and v2 weaknesses the plan does not address

| # | Weakness | Evidence | Severity | Mitigation |
|---|---|---|---|---|
| M1 | Question bloat and negation-heavy instructions. ~55% of each v1 investigation request is question text; triage carries 9.5k characters of "unless / only if / never" rules. Stage 1 copies them. | v1-architecture W11; decision-models 2.1 and 3 item 4 (vendor warns these are answered less reliably) | Medium | Move such rules into code (filter or annotate candidates); keep questions single-hop; drop `fault_visible` (never varied). |
| M2 | Lite-tuned thresholds (0.6, 0.9, 0.5, 0.3) stay in stages 1-2, and new ones (slot counts, margins) will be set on Lite. | v1-architecture W12; DNS passed or failed on 0.56 vs 0.61 | Medium | Rank and agreement rules; any number is set on pooled request-level development data and frozen. |
| M3 | Lite-shaped special paths (blocked input, pair node, chain characterization, stale env credentials, cronjob sidecar). The plan does not say whether they stay. | v1-architecture 3.2, W13 | Medium | Keep the facts they compute; drop the special control flow once the general core exists. |
| M4 | Vote splitting across near-identical options. | forensics 2.13 (env_shadowing: "none" won by plurality while one origin held 0.67) | High (see N2) | Group by origin, sum probabilities. |
| M5 | The false "investigation budget ended" line on unsure answers. | v2-audit section 4 (15 of 52 arms on 30dd021e) | Low | Remove; say nothing about confidence in the report. |
| M6 | Replays are not faithful and run files do not record the code commit. | v2-audit sections 4 and 6 | Medium | Collect-once bundles (N12) make replay exact; write commit ids into every run file and the pre-registration. |
| M7 | An empty submission scores 0. | lite5_finalizer, all four arms empty after an HTTP 402 (landscape 3.1) | Low | A final guard that always submits a non-empty fallback text (for example v1's). |
| M8 | The characterization step (which fact and values reach the report) is unspecified. | N13 | High | Slot-filled mechanism sentence. |

### 4.2 Benchmark categories the plan will still fail

| Category | What the plan adds | Why it will still fail | Severity | Mitigation |
|---|---|---|---|---|
| Runtime state in data stores (users, grants, sequences, locks, runtime settings) | pings, maybe `CONFIG GET` | Needs a login with real credentials and a query; open question 2 is unresolved. Ground truth can name an object that does not exist (`service/mongodb-geo-db`, landscape row 7), so naming must follow the app's own Service names. | High | Settle question 2 first. If allowed, a small per-protocol read-only set (who am I, my grants, settings that differ from defaults). If not, a "server rejects its clients, no recorded change" candidate from client error classes plus the ping result, naming the Service. |
| Node and hardware | "node" as an origin kind | No evidence plan. Exec into host-network pods is refused; laptop kind cluster; eval-methodology 2.2 says to drop faults that cannot run on the laptop, so node faults may be absent from Unseen and untestable either way. | Medium | Co-location from kubectl alone (all unhealthy pods share one node while replicas elsewhere are fine; node conditions, taints, heartbeat age, node events). node-exporter USE metrics through PromQL (it is in the stack, landscape 4.1). State whether node faults are in Unseen. |
| Metastable loops and retry storms | trigger + amplifier | No evidence plan for "symptoms persist after the trigger stopped"; no baseline (N4); the load generator is hidden. Unsealed retry-storm faults name the ConfigMap holding the retry policy, not a path (landscape rows 16, 18). | High | Build the settings side first (timeouts and retries on both ends, from env, config files and ConfigMaps; cheap kubectl). Name the policy object. Add the trigger only when telemetry supports it. |
| Many components or several causes | grouping the same change | Faults that edit every Deployment need "all Deployments in namespace X", not a list (unsealed rows 14, 17). Incident Arena multi-cause faults are outside the Unseen apps. | Medium | A scope phrase when a grouped change covers every workload in a namespace. |
| Input and load (memory or connection exhaustion driven by a load source) | nothing specific | v2 never built its `resource` pattern; valkey_memory failed in all 16 arms; ground truth names the exhausted server, not the load source. | High | A generic "X ran out of resource R (OOMKilled, CPU throttled, connections, file descriptors), driven by load from Y" candidate. By the fan-out rule (N7), X leads. |
| Feature flags in a shared flag ConfigMap (astronomy) | not mentioned | A known config-object family on astronomy (landscape 2.2; unsealed example astronomy_shop_product_catalog_service_failure). ConfigMaps keep no old value, so "bad and good value" cannot come from history; ground truth names the affected service. | High | Decide whether OpenFeature/flagd JSON is tier-2 protocol knowledge (O6). If yes, parse flags whose active variant is not "off" and link each to the service whose errors or traces show its effect; lead with the service. |
| Workloads re-created or added by the injector | nothing | Several injectors delete and re-create the Deployment or add a new one, leaving no revision to diff (landscape table notes). | High | "Created after its siblings" as a change record (v1 has it) plus a sibling comparison (settings that differ from every sibling workload of the app: probe timings, ports, rollout strategy), stated as facts. |
| Deleted objects | nothing | A deleted object leaves nothing to diff; only broken references remain. | Medium | One generic dangling-reference detector over every reference field (env host to Service, volume to ConfigMap/Secret/PVC, PVC to StorageClass, Ingress backend to Service, pod to ServiceAccount, and so on). |
| Noise | nothing | SREGym can add Chaos Mesh noise (`enable_noise`, off by default); the paper reports about 10 points lost by LLM agents and "greedy" first-anomaly answers (sota 1). | Medium | One development pass on Lite with noise on. No change to Unseen. |

### 4.3 What stops it from being clearly best-in-class
- The goal is only "better than v1". There is no outside comparison on the same faults. Mitigation. Report Unseen
  next to published per-problem results where they exist, or run SREGym's built-in Stratus agent on the wider
  development set if budget allows, and report time to diagnose and cost, where this approach is strongest (blog:
  14.6 s median, about 200x cheaper than an LLM agent).
- Any public claim must carry the O1 caveat.
- Diagnosis only. The leaderboard ranks end to end with mitigation. Fine for this project, but say so.

---

## 5. Recommended edits to STRATEGY.md, in order

1. Fix F10, F13, F18, F19, F22 and F23; soften F1, F6, F9, F15 and F17; use one go-back count (F7).
2. Re-state what Unseen is (O1), re-seal it properly (O2), decide on a reserve (O3), report sample C separately,
   and run the provenance pass before any code.
3. Widen the development set and replace the per-fault Lite gate with totals plus a noise band (O4, O5).
4. Collect once, decide many times. Snapshot, detail, telemetry and the probe library are gathered once per fault
   and stored; every arm is a pure function of that bundle (N5, N12, M6).
5. Candidates. Typed change records, effect evidence, the "older than this deployment" leftover rule, slots by
   family, grouping by origin, a code-side coverage check and an explicit no-change candidate (N1-N3, N8, N14).
6. Report. The fan-out lead rule with both kinds, the changed object as the means, a slot-filled mechanism, a
   changed-fields line, and victims listed only with their own evidence (N7, N13).
7. Replace the token goal with a per-request size cap; hold one model out of all development (N10, N11).
8. Tie-breaks. Wider trigger, a written pair-type to test table with its coverage measured, and a stated fallback
   (N6).
9. Scope by expected gain per day. Stage 1 = report contract plus change-record fixes (W3, W4, W5, leftover rule,
   restart typing), because they touch every fault. Telemetry comes last, only after stage 0 shows it exists.
10. Copy into the pre-registration the rules from eval-methodology 2.4-2.5 that STRATEGY leaves out (clean cluster
    per fault, infrastructure-failure rule, judge drift check, credit check, random order, commit ids, runner and
    designer roles split).
