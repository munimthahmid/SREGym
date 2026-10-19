# jev v2 handoff (2026-10-18 evening) — read this first on the new laptop

## Where things stand
- **Goal:** a v2 of the SREGym team's Jev diagnosis pipeline (`clients/jev_diag`, blog "Jev-Driven SRE Diagnosis")
  that scores higher on Jev and on OpenAI Decisions, with no LLM in the agent. Design: `jev-v2-final-design.md`.
- **v2 code:** pushed to github.com/munimthahmid/SREGym branch **`jev-v2`** (commit 6400cd46, 10-18); locally
  `~/sregym/SREGym-fixes` (worktree, branch `jev-v2-fixes` tracking `fork/jev-v2`). On a new laptop:
  `git clone --recurse-submodules -b jev-v2 git@github.com:munimthahmid/SREGym.git ~/sregym/SREGym`. Contents:
  `clients/jev_v2/` (explain, patterns, decide, report, agent, arms, grade, replay) + `clients/jev_diag/driver.py`
  modes `v2` and `arms` + harness changes (OpenRouter client, filtered-egress rule for jev_diag, judge
  `--judge-reasoning-effort`, `SREGYM_JUDGE_STARTUP_TIMEOUT`). 169 client tests pass; ruff clean (run pytest with `PYTEST_ADDOPTS=` here: the global `-n 4` breaks it).
- **PR:** SREGym/SREGym#1118 (base `jev`) — budget-trim crash fix + log filter fix. Review requested from yimingsu01.
- **Results so far:** `jev-v2-results.md`. Fault 1 (service_wrong_pod_selection): v2 Jev 100, v2 Decisions 100,
  v1 Jev 89, v1 Decisions 89.
- **In progress at handoff time:** hotel batch (retry collapse, cronjob sidecar, finalizer deadlock, namespace
  memory limit, network policy) and the social-network image preload.

## How a run works (arms mode)
- `jev-v2-runs/run.sh <label> openrouter/typesafe/jev-1.13 --problem <id>` (or `batch.sh <id> ...`), from
  `~/sregym/SREGym-fixes`. agents.yaml's jev_diag kickoff_env sets `JEV_DIAG_MODE=arms` and the four arms
  (v2/v1 x Jev 1.13/Decisions); arm 0 (v2 Jev) is submitted officially.
- Afterwards grade all arms: `SREGYM_AGENT_IMAGE=sregym-agent-base:latest uv run python -m clients.jev_v2.grade
  --problem <id> <path/*_arms.json> [...]` (one judge start per batch; ~3 min startup). Output `*_arms_graded.json`.
  `jev-v2-runs/grade-batch.sh NAME PROBLEM...` finds each problem's latest run, grades it, and copies files to
  `results/<problem>/`. `chain3.sh` = grade social, rerun duplicate PVC + cronjob live with the own-setting fix (3dc3e053), then the astronomy faults with `--profile svelte`, then grade astro and the reruns.
- Speedup (committed 7b199e08, fork only, not for upstream PRs): `docker/agents/Dockerfile` bakes the Codex CLI into the agent image and
  `install-codex.sh` skips the npm install when Codex is already there, so judge start no longer downloads it.
- Run outputs: `~/sregym/SREGym-fixes/results/<MMDD_HHMM>/.runtime/jev_diag/anon_*/` (git-ignored; copies of each
  fault's files go to `Priyo Work/jev-v2-runs/results/<problem>/` — move that folder to the new laptop) (`_arms.json`, `_snapshot.json`,
  per-arm `_requests.json`, trace).

## Setting up the new laptop (in order)
1. Clone or copy the code into a path **without spaces** (SREGym's helm calls break on spaces), e.g.
   `~/sregym/SREGym` with submodules (`git clone --recurse-submodules`), then restore the v2 branch/worktree.
2. Docker, user in the docker group; kernel limits:
   `fs.inotify.max_user_instances=1024`, `fs.inotify.max_user_watches=1048576` (`/etc/sysctl.d/99-sregym-kind.conf`).
3. kind v0.27.0, kubectl v1.32.1, helm v4.0.0 (the versions SREGym pins); `bash kind/setup_kind_cluster.sh`
   (on a slow link Calico may exceed its 300 s wait; then wait for `kubectl get nodes` Ready and finish by hand).
4. `uv sync` in the repo. Save the OpenRouter key yourself to `~/.config/openrouter/key` (chmod 600).
5. Codex CLI for the judge comes from the VS Code ChatGPT extension (`~/.codex` login = ChatGPT subscription).
6. **Slow connection only:** preload images into the kind nodes before runs (`jev-v2-runs/preload.sh`); SREGym's
   MCP rollout waits only 180 s. Lessons: kind nodes mount tmpfs on /tmp (export to /var), set
   `discard_unpacked_layers = false` on the source node, pull ghcr.io directly (mirror proxy corrupted blobs on cut
   downloads), docker.io via a `registry:2` pull-through mirror is fine. On a fast connection, skip all of this.
7. If two leftover `init-pvc-*` pods sit Completed in `openebs`, delete them (they block SREGym's readiness wait).
8. Some faults pull their own images and allow only 120 s (rolling update: `python:3.9-slim`, `busybox:1.36`). On a
   slow link, pull those on every node first (`docker exec <node> crictl pull <image>`); otherwise attempt 1 fails
   and SREGym retries (attempt 2 then works because the image is cached).

## Frozen v2: commit 676024e9 (2026-10-19 07:10; 1d22d925 + outside-object fix + v1's key-evidence step)
Held-out runs use 676024e9 (`chain9.sh`). Lite faults whose v2 candidates and concrete winner are unchanged keep
their 1d22d925 final-pass result; the three that can change (retry collapse, secret rotation, unschedulable) are
rerun on 676024e9. `chain5.sh` = final pass of all 17 Lite faults on it, then one grading
pass (results in `results/<problem>/final/`). Earlier Lite runs (mixed versions, during development) stay in the
results file as history.

## Held-out sample of 10 (decided 2026-10-19 06:25; list in `jev-v2-testsets.md`)
58 was more than the PR needs. `jev-v2-runs/chain7.sh` waits for OpenRouter credits (checks the balance every 5 min;
the account ran out at 00:50, free tier), then runs the 8 drawn faults on the frozen 1d22d925 and grades all 10. One
laptop is enough; the other device is not needed for this.

## Running on two devices at once
- Each device runs its own kind cluster and its own list of faults; nothing is shared but the OpenRouter key and the
  Codex (ChatGPT) login, which both work from two places.
- Device A (the first laptop) finishes SREGym-Lite. Device B sets up per the list above, then takes the fault list
  it is given (split by app, so each device downloads each app's images once).
- Only device A edits `docs/jev-v2-results.md`. Device B pushes its run files to its own branch `jev-v2-b`
  (`results/<problem>/` copies + `*_arms_graded.json`), and device A merges the scores into the table.
- RAM: astronomy shop needs `--profile svelte` on a 14-16 GB machine; stop other apps first.

### Held-out run (faults neither v1 nor v2 was built on; groups in `jev-v2-testsets.md`)
Run with `bash docs/jev-v2-batch.sh NAME PROBLEM...` from the repo root (one fault after another, then one grading
pass). Device B pushes `jev-v2-runs/` to its own branch `jev-v2-b` after each batch.

Device B (light apps, 35 faults), in this order:
```
bash docs/jev-v2-batch.sh hotel duplicate_pvc_mounts_hotel_reservation rolling_update_misconfigured_hotel_reservation \
  wrong_service_selector_hotel_reservation wrong_dns_policy_hotel_reservation readiness_probe_misconfiguration_hotel_reservation \
  liveness_probe_too_aggressive_hotel_reservation sidecar_port_conflict_hotel_reservation service_port_conflict_hotel_reservation \
  misconfig_app_hotel_res update_incompatible_correlated wrong_bin_usage missing_configmap_hotel_reservation \
  missing_service_hotel_reservation configmap_drift_hotel_reservation resource_request_too_small ingress_misroute
bash docs/jev-v2-batch.sh social stale_coredns_config_social_network wrong_dns_policy_social_network auth_miss_mongodb \
  liveness_probe_too_aggressive_social_network sidecar_port_conflict_social_network service_port_conflict_social_network \
  taint_no_toleration_social_network persistent_volume_affinity_violation scale_pod_zero_social_net
bash docs/jev-v2-batch.sh blueprint capacity_decrease_rpc_retry_storm gc_capacity_degradation
bash docs/jev-v2-batch.sh operator operator_invalid_affinity_toleration operator_non_existent_storage operator_overload_replicas \
  operator_security_context_fault operator_wrong_operator_image operator_wrong_update_strategy_fault
bash docs/jev-v2-batch.sh disk latent_sector_error silent_data_corruption   # may not run on kind; report as "not run"
```
Device A (this laptop, after Lite): the 21 astronomy shop faults with `EXTRA_ARGS="--profile svelte"` (images are
already loaded here), then train ticket (2) only if RAM allows.

## Next steps
1. Finish the Lite faults in arms mode: hotel (5 left at handoff), social network (4), astronomy shop (7; heavy,
   needs ~16 GB RAM). The blog's five failures: edge_request_filter_cpu_saturation, search_rate_retry_collapse,
   kafka_poison_pill_hol_block, valkey_auth_disruption, service_dns_resolution_failure_social_network.
2. Grade each batch, update `jev-v2-results.md`.
3. Grow v2 where the funnel shows losses (metrics/traces/logs via MCP, contrast sets, probes), per the design.
