# v2 strategy: from first principles (draft for review, 2026-10-19)

Based on seven analyses in this folder (forensics, v1-architecture, v2-audit, benchmark-landscape,
decision-models, sota, eval-methodology). Nothing gets built until this is agreed.

## 1. What went wrong (evidence, not opinion)

- **v2 was a closed list of hand-written fault stories.** Its 20 rules in `patterns.py` match the 17 Lite faults,
  and 12 of 15 commits added or tuned a rule right after one failed run. On faults it was not built on, it ties
  or loses to v1 (held-out 7 and 8 vs 7 and 7; set T 1 of 4 arms vs 3 of 4). It is signature matching, which only
  covers faults already seen.
- **Its checks did not tell the true cause apart.** The model saw 432 "supports" against 56 "contradicts". The true
  cause was ahead on checks in only 28 of 56 decisions, which is why we kept seeing near ties.
- **Its "look closer" step never ran.** It made a second round in 2 of 82 runs, because it re-read what it had
  already read.
- **v1's strength is not its walk** (it makes 2 model calls in 39 of 44 runs). Its strength is a library of neutral
  Kubernetes fact detectors (selector vs labels, pod vs template, a Secret rewritten after start, a revision diff),
  plus "recent change before the symptoms", with the report quoting those facts word for word.
- **v1's limits are specific.** It can only name one workload, never a ConfigMap, topic, node or interaction as the
  cause. It sees nothing its detectors don't cover, and it has a few plain bugs (CoreDNS ordering, revision diffs that
  never become signals, probe timing dropped).
- **Lite is the wrong target.** Top LLM agents already score 100% diagnosis on it. The full SREGym has 117
  problems, and 42% of them sit where both pipelines are weak: runtime state 17%, interactions 10%, node faults 7%,
  several causes 6%, plus outside objects. Both pipelines use only kubectl and Prometheus alerts. Neither touches
  the metrics, traces or logs SREGym provides.

## 2. Goal (measurable)

v2 keeps everything v1 does well and goes clearly beyond it on faults nobody has looked at.
- **Primary:** on the Unseen set, pooled over all models, v2 passes at least 15 points more than v1. With 40 faults
  that is the smallest gain we can prove.
- **Guard:** v2 is never worse than v1 by more than 2 faults with Jev or with Decisions.
- **Breadth:** it can express every origin kind the benchmark uses, works on 5 decision models, and uses no more
  tokens than v1.

## 3. Design (separate package, starting as a full copy of v1)

1. **Start from v1's code and fix its known bugs.** The bugs are cluster objects demoted behind workloads, outside
   objects never leading the report, revision diffs never becoming change signals, evidence kinds tagged by string
   matching, probe timing and termination grace dropped, false links from names relayed in error text, and "first
   origin above 0.6 wins" with no comparison. All are general fixes to v1's own code.
2. **Let it say what the benchmark needs.** The origin can be any object kind (ConfigMap, Service, CoreDNS,
   webhook, node, topic, a path between two services). One cause can span several workloads (same change on 6
   databases), and two-sided causes can be a trigger plus an amplifier. Every answer names both the changed thing and
   the broken thing, because the ground truth names one or the other depending on the problem.
3. **Let it see more.** Add PromQL metrics (before vs after onset), Jaeger edges and errors, Loki, and objects outside
   the app namespace (Ingress, PriorityClass, kube-system, other namespaces). Add read-only probes such as a DB auth
   check, Valkey `CONFIG GET` or Kafka offsets, which v1 has but never runs.
4. **One general decision core instead of fault stories.** Code builds a typed graph of all objects plus call edges,
   and for each candidate computes neutral facts. Those facts are which symptoms it can reach, onset order, whether it
   changed, its own symptoms, and whether a parent already explains it. The model answers short slate questions over
   2-7 options, asked twice in shuffled order, and we act on agreement. The options carry facts, never code's
   verdicts.
5. **Break ties with new evidence.** When the two asks disagree, code picks a generic read-only test that separates
   the top two (resolve, connect, auth, live config, lag), runs it, and asks again. This is the "look closer" step,
   working.
6. **Shape the report for the judge.** One origin sentence names the changed object and the component it breaks. It
   gives the bad value and the good value when known, lists affected components clearly as victims, and has no
   fault-category label.
7. **Generality rule.** Knowledge may name only Kubernetes kinds, fields and symptom classes, never an app, service
   or problem-specific value. A lint check enforces it. Candidate recall (is the true cause among the options?) is
   measured on its own, separately from the model's pick.

## 4. Evaluation (pre-registered before any building)

- **Lite (17) is for development only.** **Unseen** is sample C plus 30 fresh faults drawn by seed from the untouched
  pool. The list is written by id, hashed and frozen before stage 1. It is run once, at the end.
- **Models:** Jev 1.13 and GPT-6 Luna Decisions are required. Jev 1.14, Perplexity Decider V1.2 and Liquid d1-ultra
  are added for robustness, with Drex v2.0 as reserve. All models share one snapshot per fault.
- **Report:** the per-fault pass difference pooled over models, with a sign test and a bootstrap interval, plus
  results per fault category. Every result is reported. Cost is about $3 of the $4.64 left, and the run takes about
  one night.

## 5. Stages and checkpoints (you review at each one)

| Stage | Work | Check | Time |
|---|---|---|---|
| 0 | Freeze Unseen list and pre-registration; verify open questions below | you approve this doc | 0.5 day |
| 1 | Copy of v1 + bug fixes + report shape | Lite: at least v1 on every fault | 0.5-1 day |
| 2 | Wider answers + metrics, traces, outside objects, probes | Lite + candidate recall | 1-1.5 days |
| 3 | General decision core + tie-breaking tests | Lite, 3+ models | 1 day |
| 4 | Unseen run, once | final numbers | 1 night |

Realistic total is 3-4 days. If we need a result sooner, stage 1 plus the cheapest parts of stage 2 is a solid
first step on its own.

## 6. Open questions to settle in stage 0

1. Do all apps have Prometheus history and Jaeger traces during the diagnosis stage? (MCP tools exist; coverage not
   verified.)
2. Are read-only exec probes into pods fair under SREGym's rules? (kubectl exec is allowed through the proxy; exec
   into host-network pods is refused in filtered mode.)
3. Must the submitted diagnosis use only Jev or Decisions, with the other models for robustness checks only?
4. We will not read the shipped manifests on disk, since SREGym hides Helm release Secrets on purpose.
