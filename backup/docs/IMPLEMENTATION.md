# v2 implementation log (living document; update after every step)

Plan: `STRATEGY.md` (revision 2 with keep/cut list). Branch: `feat/jev-diag-v2` in `~/sregym/SREGym-pr-v2`
(continue on it, new commits only, no force push, commit messages read as progress, prefix "v2 pipeline:",
identity Munim Thahmid from repo config, no Claude attribution). Code location: `clients/jev_diag/v2/`.
Upstream `origin/jev` = 9d7246f1 (unchanged; branch already based on it).

## Ground rules
- v2 starts as a copy of v1's diagnosis modules (collector, derive, changes, checks, investigate, probes, trend,
  classifier, tree) inside `clients/jev_diag/v2/`; shared plumbing stays imported from v1 (config,
  decisions_client, timeutil, trace, replay). v1 itself is not modified except the driver hook.
- Reuse the team's `clients/jev_agent` evidence tools for stage 3 (metric_series, call_edges, client_check,
  backend_probe, cluster_objects, logs, events; its `mcp.py`; its replayable tool cache) instead of new code.
- Every change general: kinds, fields, symptom classes, technologies only. Lint + name-blind test.
- Before any credit-spending live run: several review subagents check implementation and correctness, and offline
  replays on saved kubectl recordings (`*_kubectl_raw.jsonl.gz`, v1 `replay.py --raw`) must pass.
- Evaluation harness (arms runner, grader, replay-arms) lives on a local-only eval branch, never in the PR.

## Models (reduced to 10 by the user, 2026-10-19: keep the best known)
Run set: typesafe/jev-1.13, openai/gpt-6-luna-decisions, microsoft/microsoft-decision-1, liquid/d1,
liquid/d1-ultra, cloudflare/clef, cloudflare/clef-omni, nace-ai/drex-v2.0, inception/mercury-decide,
upstage/solar-decide (10 models, 8 companies). Dropped: typesafe/jev-1.14 (same maker as 1.13, no public gain;
1.13 is the dev and submitted model), nace-ai/drex-v1.5 (older Drex), cloudflare/clef-flash (small sibling, last
in public test), jaredpalmer/kev-4b (8k context). ~$0.06 per problem, ~$2.1 for 35.

## Models (first list, 2026-10-19)
All decision models that answer our wire format, run at every stage checkpoint and in the final runs (dev uses Jev
1.13 + Luna): typesafe/jev-1.13, typesafe/jev-1.14, openai/gpt-6-luna-decisions, nace-ai/drex-v1.5,
nace-ai/drex-v2.0, cloudflare/clef, cloudflare/clef-flash, cloudflare/clef-omni, inception/mercury-decide,
liquid/d1, liquid/d1-ultra, microsoft/microsoft-decision-1, upstage/solar-decide, jaredpalmer/kev-4b (14, smoke-
tested). Perplexity Decider: id unknown (all guesses rejected); add if the user gives the id. Small-context models
(Clef 16k, Clef Flash 16k, Kev 8k) need v2's requests under ~15k chars; v1's triage will not fit them.

## Hard cases (fixed 2026-10-19 from past results, before any new code)
update_incompatible_correlated, auth_miss_mongodb, secret_rotation_stale_env_credentials_astronomy_shop
(old v2 worse than v1); valkey_memory_disruption, valkey_auth_disruption (both failed).

## Tasks and status
### Stage 0
- [x] origin/jev unchanged; branch already on it (no merge needed)
- [ ] PREREG.md (sets, models, metrics, analysis, Unseen hash 32c2634f...)
- [ ] cluster check: trace coverage, MCP latency, tools in images, `full` profile memory
- [x] credit: $4.64 left (top-up is the user's call)

### Stage 1 (base + plumbing + report)
- [x] S1.1 copy v1 modules into v2 package; pipeline entry; driver delegates mode v2; old v2 modules retired
- [x] S1.2a revision diff -> change signal (v1 W3)
- [x] S1.2b probe timing + termination grace into evidence (W5)
- [x] S1.2c evidence cap keeps events/logs (per-type slots)
- [x] S1.2d no links from names relayed inside error text (W8)
- [x] S1.2e symptom onset per component (folded into the timing facts)
- [x] S1.2f model-free fallback report on API failure
- [x] S1.2g change filter: app object, after deploy, visible effect; restartedAt-only = restart, not change
- [x] S1.2h cluster findings vs top workload (solved by the report rule + pre-deploy change filter)
- [skip] S1.2i evidence-kind relabeling (risk to triage, no measured gain)
- [x] S1.2j adaptive start wait (poll until symptoms settle, cap 120 s)
- [x] S1.3 report template (5 lines, subject rules, old -> new, affected callers, no fault-type line)
- [x] S1.4 stored bundle (snapshot + detail reads + probe/metric results) and local eval harness
- [ ] S1 check: offline replays on saved recordings; Lite >= v1 per fault; regression guards

### Stage 2 (say more)
- [x] S2.1 outside objects (Ingress, PriorityClass, kube-system, other namespaces, CRDs) + setup-object filter
- [x] S2.2 same change on N workloads = one candidate; call paths; data objects (topics)
- [x] S2.3 facts (old -> new, timing) on triage candidates
- [x] S2.4 ask triage twice (shuffled); agree -> accept, else investigate top two / tie-break
- [skip] S2.5 model-classified log lines (no measured case; re-derive risk)
- [ ] S2 check: Lite + dev pool, candidate recall, 5 models at checkpoint

### Stage 3 (see more; reuse jev_agent tools)
- [x] S3.1 PromQL summaries (jev_agent metrics), early vs late, replica vs replica, node-exporter
- [x] S3.2 call edges with error/latency (jev_agent call_edges) where traces are reliable
- [skip] S3.3 Loki (no jev_agent support, low value)
- [x] S3.4 probes: client_check (DNS/connect), backend_probe (auth/config) with memory headroom
- [x] S3.5 tie-break test when the two asks disagree
- [ ] S3 check: dev-pool runtime/node/interaction faults, 5 models

### Hard categories (in stages 2-3)
- [x] H1 two independent causes (uncovered failing components -> second candidate, both reported)
- [x] H2 feedback-loop checks on call paths (retry multiplication, timeout vs latency, overload outlives trigger)
- [x] H3 collect the app's other namespaces (operator, data, control plane)
- [x] H4 decoys/noise: no code needed (noise = transient pod kills / network blips, read as symptoms, never changes); checked with `--noise` in the later dev runs

### Before live credit runs
- [ ] review subagents (correctness, generality, tests) + fixes
### Order after implementation (user, 10-19): reviewers -> 5 hard cases live -> if promising, Unseen 15 -> then Lite
Scope (user, 10-19): only hard 5 + Unseen 15 + Lite 17 (2 overlap with hard: secret_rotation, valkey_auth) = 35
problems, the 10 models above, v1 + v2 arms. ~$0.045 per problem (measured) -> ~$1.6 of $4.42 credit (user: $2 fine).
Where: hard 5 + Unseen 15 on this laptop (run-set.sh: runs back to back, grading in the background, distinct reports
judged in parallel); Lite 15 on the user's home laptop (prepare a git bundle of v2-eval + run script + setup note).
### Stage 4: Unseen 15 + hard-case 5, all models
### Stage 5: mitigation (pending user's yes)

## Log
- 2026-10-19 16:xx: plan agreed; stage 0 started.
- S1.1 committed 065032a6 (v2 = copy of v1, v1 runner shared); 37bd9d0c, aa6241c9 driver split (collect = wait +
  read_cluster; make_diagnoser). Not pushed yet (push at stage checkpoints).
- Eval worktree ~/sregym/SREGym-v2eval, local branch v2-eval (PR branch + harness commit 9805d25f: v2_eval/arms.py
  live, replay_arms.py offline, grade.py; agents.yaml arms env). Offline replay verified (identical v1/v2 today);
  one paid replay ok.
- Commits (all local until the checkpoint push): 065032a6, 37bd9d0c, aa6241c9 (S1.1); 8008d24d (S1.2a/g);
  b4c9478f (S1.2b); aba4f2f8 (S1.2c); e1a65de7 (S1.2d); 6fc31a5d (S1.3 report); 75ddd377 (S1.2f); 83485d42 (S1.2j);
  fa5d98fd (S2.1/H3 outside objects, related namespaces); bbe5406d (deploy-time revision is not a change);
  c0cca9bb (S2.2 same change on N); 52325dad (S2.4 triage twice); 5c134aa6 (S3.4 probe on); cf354c03 (S3.1/S3.2
  telemetry via jev_agent); ae68e37e (H2 call paths, S3.5 tie-break, H1 second cause). 365 tests pass.
- H2 check (collection-only replay, 29 dev faults): the call path fires only on search_rate (search -> rate, both
  sides' settings, feedback loop); no other fault gets a path.
- Next: reviewer subagents (correctness, collection, generality, tests) -> fixes -> offline replay + grade on the
  latest code -> 5 hard cases live.
- 2026-10-19 evening: 4 reviewer subagents (decision flow, collection, generality, tests; review2/*.md). No leakage;
  name-blind identical up to name order. Fixed (all general, focused commits, nothing pushed):
  report by relation kinds (e131dda1); model chooses call paths, code never overrides (c3175da1); second cause needs
  no link + own change (d185468d); search returns to confirmed origin, failing model keeps work (be946b38); report
  states facts / small-context budget (4a738039); wait counts only new restarts, polls unrecorded (770fc24e); v1
  suite on v2 + no-app-name lint (c036b926); error-line quotes (9db228c9); 12 collection fixes by agent (4a8c2006..
  825e5ba7: restart no evidence kind, MongoDB probe, deploy-time template diff, related-namespace safety, changed
  flags after deploy filter, outside findings only when wrong, call-setting matching, call path after change
  signals, `_called` rule removed); side-by-side decisions for close/two-sided causes (6f180951). 417 tests.
- Old-code replay s1 (29 dev x v1/v2 x Jev/Luna): v1 46/58, v2 46/58. Fresh replay s2 (code 825e5ba7): no errors,
  no false second cause; grading in progress. Targeted s3 (6f180951) on hard/auth faults running.
- 2026-10-19 17:50: pipeline FROZEN at 12c0183a (user). Unseen: 1 live run each. Reports to user: Jev + Luna only (all 10 kept on file).
