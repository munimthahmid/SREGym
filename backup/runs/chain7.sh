#!/usr/bin/env bash
# Held-out sample of 10 (jev-v2-testsets.md, "Held-out sample"): the 2 already run + 8 drawn with seed
# "jev-v2-heldout-10". Waits until real OpenRouter calls work, runs the 8 on the frozen v2 (1d22d925),
# 1 h cap per fault, then grades all 10 with one judge. Files: results/held/<problem>/.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
FROZEN=1d22d925
DONE="service_dns_resolution_failure_astronomy_shop wrong_service_selector_astronomy_shop"
LIGHT="sidecar_port_conflict_hotel_reservation duplicate_pvc_mounts_hotel_reservation
       readiness_probe_misconfiguration_hotel_reservation liveness_probe_too_aggressive_social_network
       service_port_conflict_social_network auth_miss_mongodb"
ASTRO="valkey_memory_disruption incorrect_image"
api_ok() {  # one tiny real decision request per model (the agent's own pre-flight); pay-as-you-go keeps the balance at 0
  for m in openrouter/typesafe/jev-1.13 openrouter/openai/gpt-6-luna-decisions; do
    (cd /home/priyo_software/sregym/SREGym-fixes && OPENROUTER_API_KEY="$(cat ~/.config/openrouter/key)" AGENT_JEV_MODEL="$m" \
      timeout 120 uv run python -c 'from clients.jev_diag import driver; driver.run_preflight()' > /dev/null 2>&1) || return 1
  done
}
echo "[$(date -Is)] HELD10 WAITING for OpenRouter credits" >> "$R/runs.txt"
until api_ok; do sleep 120; done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet "$FROZEN" -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] HELD10 ABORTED: code is not the frozen $FROZEN" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] HELD10 START v2=$FROZEN (OpenRouter calls work)" >> "$R/runs.txt"
for p in $LIGHT; do RUN_TIMEOUT=3600 "$R/run.sh" "held_$p" openrouter/typesafe/jev-1.13 --problem "$p"; done
for p in $ASTRO; do RUN_TIMEOUT=3600 "$R/run.sh" "held_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
echo "[$(date -Is)] HELD10 RUNS DONE" >> "$R/runs.txt"
args=(); pairs=()
for p in $DONE $LIGHT $ASTRO; do
  start=$(grep "START held_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END held_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -z "$start" ] || [ -z "$end" ] && continue
  f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)  # this fault's own
  [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("$p=$f") && mkdir -p "$R/results/held/$p" \
    && cp "${f%_arms.json}"* "$R/results/held/$p/"
done
echo "[$(date -Is)] GRADE START held10 ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-held10.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do
  p="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/held/$p/" 2>/dev/null
done
echo "[$(date -Is)] GRADE DONE held10 exit=$code" >> "$R/runs.txt"
