# Task for Codex: run the Lite 15 set of the jev_diag v2 evaluation on this machine

You are running one part of a frozen evaluation. Do not change any code under `clients/` or `sregym/`. Do not
"improve" anything. Run, watch, fix only infrastructure, report.

## What this is
SREGym benchmark. Two diagnosis pipelines (v1 and v2) answer each fault on the same cluster moment with 10 decision
models (20 answers per problem), all graded by SREGym's own judge. v2 is frozen at commit eade3b0a. Another machine
runs the Unseen set at the same time; you run the 15 Lite problems below, one at a time.

## 1. Setup (once)
- Linux or WSL2, 14 GB+ RAM, Docker, `kind`, `kubectl`, Helm 4+, `uv`, `git`, Python 3.12+.
- Codex logged in with the ChatGPT subscription (`~/.codex/auth.json` exists). The judge uses it.
- The OpenRouter key must be in `~/.config/openrouter/key` (one line). Ask the user for it if missing. Never print it,
  never commit it, never put it in any file other than that one.

```bash
git clone -b v2-backup https://github.com/munimthahmid/SREGym.git ~/sregym/SREGym-v2eval
git clone https://github.com/SREGym/SREGym-applications.git ~/sregym/SREGym-applications
cd ~/sregym/SREGym-v2eval && rm -rf SREGym-applications && ln -s ~/sregym/SREGym-applications SREGym-applications
uv sync
sudo sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_user_watches=1048576   # Linux/WSL2 only
bash kind/setup_kind_cluster.sh && kubectl get nodes     # all 4 nodes must be Ready
mkdir -p ~/jev-v2-runs && cp backup/runs/run-set2.sh ~/jev-v2-runs/ && chmod +x ~/jev-v2-runs/run-set2.sh
```

## 2. Preload the OpenSearch image (required; this cost us 2 hours)
The online-shop app (astronomy-shop) needs `opensearchproject/opensearch:3.4.0` (1.1 GB). If it is not cached on the
nodes, the app cannot start within the benchmark's 10-minute limit and the run dies before diagnosis. `kind load`
fails on this multi-platform image, so import it directly:

```bash
docker pull opensearchproject/opensearch:3.4.0
docker save opensearchproject/opensearch:3.4.0 -o /tmp/opensearch.tar
for n in kind-control-plane kind-worker kind-worker2 kind-worker3; do docker exec -i $n ctr --namespace=k8s.io images import --platform linux/amd64 --snapshotter=overlayfs - < /tmp/opensearch.tar; done
```

## 3. Run
```bash
cd ~/jev-v2-runs && RUNS_DIR=~/jev-v2-runs SREGYM_EVAL_DIR=~/sregym/SREGym-v2eval nohup ./run-set2.sh lite \
  cronjob_sidecar_blocks_completion_hotel_reservation duplicate_pvc_mounts_social_network \
  edge_request_filter_cpu_saturation env_variable_shadowing_astronomy_shop finalizer_deadlock_controller_hotel_reservation \
  internal_traffic_policy_local_astronomy_shop kafka_poison_pill_hol_block mutating_webhook_resource_limits_social_network \
  namespace_memory_limit network_policy_block rolling_update_misconfigured_social_network \
  search_rate_retry_collapse_hotel_reservation service_dns_resolution_failure_social_network \
  service_wrong_pod_selection_hotel_reservation unschedulable_incorrect_port_assignment > lite.out 2>&1 &
```
About 13 minutes per problem, roughly 3.5 hours. Progress: `~/jev-v2-runs/runs.txt` (START / END / GRADED per
problem); grades: `~/jev-v2-runs/grade-lite.log`; results: `~/jev-v2-runs/results/lite/<problem>/`. Each problem is
graded in the background as soon as its answers exist. Done when `runs.txt` says `SET lite done`.

## 4. Infrastructure problems we hit (fix these, nothing else)
- A node `NotReady` ("container runtime is down", common after a reboot):
  `docker exec <node> systemctl restart containerd && docker exec <node> systemctl restart kubelet`.
- Pods stuck `Pending` / `Init` for minutes on one node while their image is cached: same restart on that node.
- An app namespace stuck `Terminating` after a run (pods that never started): force-delete those pods
  (`kubectl delete pod -n <ns> <pod> --grace-period=0 --force`). Only during cleanup, never during a diagnosis.
- A problem whose run produced no answers (`no arms file` in grade-lite.log) because of infrastructure: after the set,
  rerun it once with `./run-set2.sh lite_retry <problem>`. Never rerun a problem that produced answers.
- Never run two live sets at once on the same machine.

## 5. When done
Commit the results folder to a new branch and push it, if this machine has push access to the fork:
```bash
cd ~/sregym/SREGym-v2eval && git checkout -b v2-lite-results && mkdir -p backup/lite && cp -r ~/jev-v2-runs/results backup/lite/ && cp ~/jev-v2-runs/runs.txt ~/jev-v2-runs/grade-lite*.log backup/lite/ && git add -A backup/lite && git commit -m "Lite 15 results" && git push origin v2-lite-results
```
First check that no file contains the OpenRouter key (`grep -rF "$(cat ~/.config/openrouter/key)" backup/lite` must
print nothing). If you cannot push, zip `~/jev-v2-runs/results/lite` and tell the user where it is.
Report back a short table with, per problem, the v1 and v2 scores for `typesafe/jev-1.13` and
`openai/gpt-6-luna-decisions` (the `accuracy` field in each `*_arms_graded.json`).
