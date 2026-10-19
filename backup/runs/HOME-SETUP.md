# Running Lite 15 on the home laptop

The 15 Lite problems not already run as hard cases, with v1 and v2 on all 10 decision models, graded by SREGym's
own judge. Each problem takes about 8-10 minutes; grading runs in the background. Total about 2.5 hours.

## What you need on the laptop
- Linux (or WSL2), at least 14 GB RAM, Docker running for your user, Python 3.12+.
- `kind`, `kubectl`, Helm 4+, `uv`, `git`.
- Codex logged in with the ChatGPT subscription (`codex login`), so `~/.codex/auth.json` exists. The judge uses it.
- The OpenRouter key in `~/.config/openrouter/key` (one line, no quotes). Never paste it anywhere else.

## One-time setup
1. Get the code from the bundle file (`v2-eval.bundle`, copied over by USB or drive; it is not on GitHub):

   ```bash
   git clone -b v2-eval v2-eval.bundle ~/sregym/SREGym-v2eval
   ```

2. Get the applications repo and link it in:

   ```bash
   git clone https://github.com/SREGym/SREGym-applications.git ~/sregym/SREGym-applications
   ```

   ```bash
   ln -s ~/sregym/SREGym-applications ~/sregym/SREGym-v2eval/SREGym-applications
   ```

3. Install the Python environment:

   ```bash
   cd ~/sregym/SREGym-v2eval && uv sync
   ```

4. Raise the inotify limits (Linux/WSL2 only), then create the 4-node cluster:

   ```bash
   sudo sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_user_watches=1048576
   ```

   ```bash
   cd ~/sregym/SREGym-v2eval && bash kind/setup_kind_cluster.sh
   ```

   ```bash
   kubectl get nodes
   ```

   All four nodes must say `Ready`.

5. Copy `run-set.sh` from the bundle folder to `~/jev-v2-runs/`.

The run script builds the agent image itself at the start (first time about 5-10 minutes).

## Run
```bash
RUNS_DIR=~/jev-v2-runs SREGYM_EVAL_DIR=~/sregym/SREGym-v2eval nohup ~/jev-v2-runs/run-set.sh lite cronjob_sidecar_blocks_completion_hotel_reservation duplicate_pvc_mounts_social_network edge_request_filter_cpu_saturation env_variable_shadowing_astronomy_shop finalizer_deadlock_controller_hotel_reservation internal_traffic_policy_local_astronomy_shop kafka_poison_pill_hol_block mutating_webhook_resource_limits_social_network namespace_memory_limit network_policy_block rolling_update_misconfigured_social_network search_rate_retry_collapse_hotel_reservation service_dns_resolution_failure_social_network service_wrong_pod_selection_hotel_reservation unschedulable_incorrect_port_assignment > ~/jev-v2-runs/lite.out 2>&1 &
```

Progress is in `~/jev-v2-runs/runs.txt` (START / END / GRADED per problem) and grades in
`~/jev-v2-runs/grade-lite.log`. Results land in `~/jev-v2-runs/results/lite/<problem>/`. When it says
`SET lite done`, send that `results/lite` folder back.

## If something goes wrong
- A node shows `NotReady` after a reboot: `docker exec <node> systemctl restart containerd kubelet`, for each such node.
- A run ends with `no arms file` in the grade log: that problem failed to start. Run it again alone with
  `run-set.sh lite <problem>` (allowed once, and noted).
- Keep the laptop plugged in and awake; sleep stops the run.
