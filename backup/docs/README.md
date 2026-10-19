# SREGym diagnosis pipeline: rethink from first principles (2026-10-19)

## Why this exists
SREGym is a benchmark used by serious AI labs (Cognition, DataGod; hopefully TypeSafe and OpenAI soon). We built
"v2" of the team's diagnosis pipeline (v1 = `jev_diag`) to be much better than v1 and general across any fault.
On faults it was developed on (SREGym-Lite) v2 looks better; on every set of faults it was NOT built on, it is at
best equal to v1 and often worse. We are stopping all patching and analysing from first principles. No decision
is made yet. The goal is to be top of the class, honestly, on unseen faults.

## Hard constraints of the task (do not propose designs that break these)
- No LLM inside the agent. The only model calls are to a **decision model**: TypeSafe **Jev** (`jev-1.13`) or
  the **OpenAI Decisions API** (`gpt-6-luna-decisions`), both via OpenRouter. A decision model answers typed
  questions (choice among options code builds, score, yes/no "noul") over a state (JSON) that code builds.
  It returns calibrated probabilities. It does not write text.
- The pipeline must work with both decision models.
- Graded by SREGym's own LLM judge (gpt-6-astra, high effort): a checklist with D1 fault localization, D2 fault
  characterization (mechanism, concrete values, fault type), D3 scope precision. Composite >= 0.70 passes.

## Where things are
- v1: `~/sregym/SREGym-fixes/clients/jev_diag/` (tree.py = IterativeDiagnoser, the v1 arms use it; classifier.py
  = questions, characterization, report text; collector.py = cluster snapshot; investigate.py = component detail;
  checks.py, derive.py, probes.py, changes.py, trace.py, trend.py).
- v2: `~/sregym/SREGym-fixes/clients/jev_v2/` (agent.py loop, patterns.py = hand-written cause patterns,
  explain.py, decide.py, report.py, arms.py = runs v1 and v2 on one snapshot, grade.py). Run tree code = 066c4d2f.
- SREGym itself: `~/sregym/SREGym-fixes/sregym/` (conductor/problems/*.py = 97 fault problems; service/apps;
  conductor/oracles/llm_as_a_judge = the judge). Apps' manifests: `~/sregym/SREGym-fixes/SREGym-applications/`.
- Our notes: `/home/priyo_software/Priyo Work/jev-v2-design.md`, `jev-v2-final-design.md`, `jev-v2-architecture.md`,
  `jev-v2-results.md`, `jev-v2-HANDOFF.md`, `jev-v2-testsets.md`, `jev-v2-blog.txt` (the team's v1 blog post).

## Run data
`runs-index.tsv` (this folder) maps every finished run label to its `*_arms.json`. Label prefixes: `lite5`/`lite6`
= SREGym-Lite (dev set) on the latest code; `held2..held6` = held-out sample A (now studied); `tgt` = targeted set T
(chosen for v2's strengths); `arms`, `arms01`, `final`, `rerun` = older v2 versions. Each arms file has 4 arms on one
snapshot: arm0 v2+Jev, arm1 v2+Decisions, arm2 v1+Jev, arm3 v1+Decisions. Next to it: `*_arms_graded.json` (judge
verdict and checklist per arm, in `arms[i].grade.reasoning`), `*_armN_vX_requests.json` (every model request: the
state, the questions, the answers with probabilities), `*_snapshot.json` (the collected cluster snapshot),
`*_trace.jsonl`, `*_kubectl_raw.jsonl.gz`.

## Headline numbers (pass = score >= 70)
- Lite (dev, 17): v2 15/17 Jev, 15/17 Decisions; v1 13/17, 12/17.
- Held-out sample A (10, studied after the run): v2 7 and 8; v1 7 and 7.
- Targeted set T (2 of 5 ran before a laptop restart): missing env var astronomy v2 11/89, v1 22/100; update
  incompatible correlated (6 MongoDB images bumped) v2 0/11, v1 89/89.
- v2's go-back (look closer when unsure) ran a second round in 1 of 56 runs. v2 uses ~1.5x v1's tokens.

## Evaluation sets (decided by the user)
Two sets only. **Lite** (17) is for development. **Unseen** is the final test: sample C (10, untouched) plus a
fresh draw from the ~55 problems nobody has looked at, frozen before any redesign and never looked at until the
final run. Sample A and set T were studied, so they are not reported. The pipeline should work across about 10
OpenRouter decision models, not just Jev and Decisions.

## Unseen is frozen (2026-10-19)
The 40 Unseen test problems (sample C + 30 drawn by a recorded seed) are listed only as per-id hashes in
`UNSEEN-HASHES.txt`; the plain list lives outside this folder. **Before opening any SREGym problem file,
injector, ground truth or run, hash its id as shown in that file; if the hash is listed, do not open it.** Their
rows in `benchmark-landscape.md` are redacted. Everything else in SREGym (Lite, sample A, set T and the other
problems) may be studied.

## Rules for analysts
- Read-only. Do not modify any repo, do not commit, do not run SREGym, docker, kind or kubectl, do not spawn
  subagents. Write only your assigned output file in this folder; write it early and update it as you go.
- Never print, copy or use API keys (`~/.config/openrouter/key` and similar).
- **Sample C is the reserved unseen test. Do not open the code, ground truth or runs of these problems:**
  configmap_drift_hotel_reservation, resource_request_too_small, missing_service_hotel_reservation,
  stale_coredns_config_social_network, scale_pod_zero_social_net, persistent_volume_affinity_violation,
  astronomy_shop_payment_service_failure, kafka_queue_problems, stale_coredns_config_astronomy_shop,
  astronomy_shop_ad_service_manual_gc. Counting them in a category table by name only is fine.
- Be concrete and evidence-based: cite files, functions, run labels, scores. Separate facts from opinions.
  Plain words. Say clearly when something is uncertain.
