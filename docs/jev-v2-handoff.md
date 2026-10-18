# jev v2 handoff (2026-10-18 evening) — read this first on the new laptop

## Where things stand
- **Goal:** a v2 of the SREGym team's Jev diagnosis pipeline (`clients/jev_diag`, blog "Jev-Driven SRE Diagnosis")
  that scores higher on Jev and on OpenAI Decisions, with no LLM in the agent. Design: `jev-v2-final-design.md`.
- **v2 code:** pushed to github.com/munimthahmid/SREGym branch **`jev-v2`** (commit 6400cd46, 10-18); locally
  `~/sregym/SREGym-fixes` (worktree, branch `jev-v2-fixes` tracking `fork/jev-v2`). On a new laptop:
  `git clone --recurse-submodules -b jev-v2 git@github.com:munimthahmid/SREGym.git ~/sregym/SREGym`. Contents:
  `clients/jev_v2/` (explain, patterns, decide, report, agent, arms, grade, replay) + `clients/jev_diag/driver.py`
  modes `v2` and `arms` + harness changes (OpenRouter client, filtered-egress rule for jev_diag, judge
  `--judge-reasoning-effort`, `SREGYM_JUDGE_STARTUP_TIMEOUT`). 168 client tests pass; ruff clean.
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

## Next steps
1. Finish the Lite faults in arms mode: hotel (5 left at handoff), social network (4), astronomy shop (7; heavy,
   needs ~16 GB RAM). The blog's five failures: edge_request_filter_cpu_saturation, search_rate_retry_collapse,
   kafka_poison_pill_hol_block, valkey_auth_disruption, service_dns_resolution_failure_social_network.
2. Grade each batch, update `jev-v2-results.md`.
3. Grow v2 where the funnel shows losses (metrics/traces/logs via MCP, contrast sets, probes), per the design.
