#!/usr/bin/env bash
# Held-out astronomy shop faults (jev-v2-testsets.md) on the frozen v2 (1d22d925), four arms each, 1 h cap per
# fault, then one grading pass. kubelet_crash last (it crashes a node's kubelet). Files: results/held/<problem>/.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
FROZEN=1d22d925
ALL_HELD="service_dns_resolution_failure_astronomy_shop wrong_service_selector_astronomy_shop
      stale_coredns_config_astronomy_shop astronomy_shop_failed_readiness_probe kafka_queue_problems
      liveness_probe_too_aggressive_astronomy_shop sidecar_port_conflict_astronomy_shop
      service_port_conflict_astronomy_shop incorrect_image missing_env_variable_astronomy_shop workload_imbalance
      astronomy_shop_ad_service_failure astronomy_shop_ad_service_high_cpu astronomy_shop_ad_service_image_slow_load
      astronomy_shop_ad_service_manual_gc astronomy_shop_cart_service_failure astronomy_shop_payment_service_failure
      astronomy_shop_product_catalog_service_failure loadgenerator_flood_homepage valkey_memory_disruption
      kubelet_crash"
HELD="${HELD:-$ALL_HELD}"  # resume: HELD="<faults still to run>" ./chain6.sh; grading always covers ALL_HELD
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet "$FROZEN" -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] HELD ABORTED: code is not the frozen $FROZEN" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] HELD START astro v2=$FROZEN" >> "$R/runs.txt"
for p in $HELD; do
  RUN_TIMEOUT=3600 "$R/run.sh" "held_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte
done
echo "[$(date -Is)] HELD RUNS DONE astro" >> "$R/runs.txt"
args=(); pairs=()
for p in $ALL_HELD; do
  start=$(grep "START held_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END held_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -z "$start" ] || [ -z "$end" ] && continue
  f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)  # this fault's own
  [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("$p=$f") && mkdir -p "$R/results/held/$p" \
    && cp "${f%_arms.json}"* "$R/results/held/$p/"
done
echo "[$(date -Is)] GRADE START held-astro ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-held-astro.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do
  p="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/held/$p/" 2>/dev/null
done
echo "[$(date -Is)] GRADE DONE held-astro exit=$code" >> "$R/runs.txt"
