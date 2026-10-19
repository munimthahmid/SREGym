#!/usr/bin/env bash
# Resume after the OpenRouter credit stop: wait until real calls work (both models), then the rest of Lite on
# 30dd021e (finalizer rerun, namespace memory, network policy, social 4, astronomy 7), then the two held-out
# reruns on 4a9b25e0 (chain17). Graded per fault by grade-rolling5.sh.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
api_ok() {
  for m in openrouter/typesafe/jev-1.13 openrouter/openai/gpt-6-luna-decisions; do
    (cd /home/priyo_software/sregym/SREGym-fixes && OPENROUTER_API_KEY="$(cat ~/.config/openrouter/key)" AGENT_JEV_MODEL="$m" \
      timeout 120 uv run python -c 'from clients.jev_diag import driver; driver.run_preflight()' > /dev/null 2>&1) || return 1
  done
}
until ! ps -eo args | grep -q '^/home/priyo_software/sregym/SREGym-fixes/.venv/bin/python main.py'; do sleep 10; done
echo "[$(date -Is)] LITE6 PAUSED: OpenRouter credits; waiting for working calls" >> "$R/runs.txt"
until api_ok; do sleep 120; done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet 30dd021e -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] LITE6 RESUME ABORTED: code is not 30dd021e" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] LITE6 RESUMED" >> "$R/runs.txt"
LIGHT="finalizer_deadlock_controller_hotel_reservation namespace_memory_limit network_policy_block
       service_dns_resolution_failure_social_network mutating_webhook_resource_limits_social_network
       duplicate_pvc_mounts_social_network rolling_update_misconfigured_social_network"
for p in $LIGHT; do RUN_TIMEOUT=3600 "$R/run.sh" "lite6_$p" openrouter/typesafe/jev-1.13 --problem "$p"; done
for p in $(cat "$R/astro_ids.txt"); do RUN_TIMEOUT=3600 "$R/run.sh" "lite6_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
echo "[$(date -Is)] V2H RUNS DONE" >> "$R/runs.txt"
setsid nohup "$R/chain17.sh" > "$R/chain17.out" 2>&1 < /dev/null &
