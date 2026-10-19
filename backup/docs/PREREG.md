# v2 evaluation plan, fixed before any held-out result (2026-10-19)

## Sets
- **Lite (17)**: development. Results guide changes and are never the headline.
- **Hard cases (5)**: update_incompatible_correlated, auth_miss_mongodb,
  secret_rotation_stale_env_credentials_astronomy_shop, valkey_memory_disruption, valkey_auth_disruption. Chosen
  from past results before the new code was written. Development evidence only (none is sealed; checked by hash).
- **Unseen (15)**: sample C (10) plus 5 drawn by seed from the frozen 40. Plain list outside this folder; sha256 of
  the sorted id list `32c2634f4f4e79ab94b495b8b5cb73227e00540403b0047331dce524e0565da3`. No v2 change is made after
  the first Unseen run starts. Each problem is run once, and every result is reported.

## Runs
- SREGym `full` profile, the benchmark's own judge (gpt-6-astra, 9-item checklist, pass = 70).
- One cluster run per problem. On the same collected cluster state, every arm runs: v1 and v2, each with the 10
  decision models listed in IMPLEMENTATION.md (run set). Arm 0 (v2, Jev 1.13) is the submitted answer. The other arms are graded
  offline by the same judge on their own reports.
- A run that fails for infrastructure reasons (cluster, MCP, judge) is rerun once and noted. A model that errors on
  a request counts as that arm's result (the code-only fallback report), not as missing.

## Metrics
- Per arm, the judge score (0-100) and pass (score >= 70).
- Main comparison: v2 vs v1 on the same state and model, paired. Reported per model and pooled over models:
  pass counts, mean score difference, and the problems where they differ.
- Exact sign test on the paired pass differences (pooled over models, problems as the unit, ties dropped). Models are
  not independent, so the per-problem view (how many problems v2 wins, ties, loses) is reported next to it.
- Also reported: candidate recall (whether the true origin was among v2's options), requests and cost per diagnosis,
  and run time.

## Decisions tied to results
- Hard cases, then Unseen 15, then Lite 17; nothing else is run (user, 2026-10-19). Unseen starts only if the hard-case results are
  promising: v2 at least ties v1 pooled over models, and no hard case gets worse for most models.
- No result, good or bad, is dropped or re-run for a better score.

## Freeze (2026-10-19, user)
- v2 is frozen at `feat/jev-diag-v2` commit eade3b0a (12c0183a + listing failing callers by configured address; user OK 18:00). Unseen 15 runs on exactly this code (merged into the eval branch
  after the hard-case set finishes), 1 live run per problem (user's choice), every result reported as it comes.
- The live hard-case set started at 17:27 on code da179aab (12c0183a minus the request-fitting commit, which only
  changes requests some providers reject: Solar's 26-option cap, one-option questions).
- Judge noise measured (replays s2 vs s4): 49 of 58 reports identical word for word; the judge scored 6 of them
  differently (about +-11 points, one 34 -> 11). Single-problem differences of ~10 points are within judge noise.
