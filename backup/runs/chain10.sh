#!/usr/bin/env bash
# Final v2 6fec2c91, one clean pass: the 10 held-out sample faults, then all 17 Lite faults, four arms each
# (v2/v1 x Jev/Decisions), 1 h cap per fault, then one grading pass. Labels held2_<p> and lite2_<p>;
# files go to results/held/<p>/v2final/ and results/<p>/v2final/.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
FROZEN=6fec2c91
HELD_LIGHT="sidecar_port_conflict_hotel_reservation duplicate_pvc_mounts_hotel_reservation
            readiness_probe_misconfiguration_hotel_reservation liveness_probe_too_aggressive_social_network
            service_port_conflict_social_network auth_miss_mongodb"
HELD_ASTRO="service_dns_resolution_failure_astronomy_shop wrong_service_selector_astronomy_shop valkey_memory_disruption
            incorrect_image"
LITE_LIGHT="service_wrong_pod_selection_hotel_reservation search_rate_retry_collapse_hotel_reservation
            cronjob_sidecar_blocks_completion_hotel_reservation finalizer_deadlock_controller_hotel_reservation
            namespace_memory_limit network_policy_block service_dns_resolution_failure_social_network
            mutating_webhook_resource_limits_social_network duplicate_pvc_mounts_social_network
            rolling_update_misconfigured_social_network"
LITE_ASTRO="$(cat "$R/astro_ids.txt")"
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet "$FROZEN" -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] V2FINAL ABORTED: code is not the frozen $FROZEN" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] V2FINAL START v2=$FROZEN" >> "$R/runs.txt"
run() { RUN_TIMEOUT=3600 "$R/run.sh" "$1_$2" openrouter/typesafe/jev-1.13 --problem "$2" ${3:+--profile $3}; }
for p in $HELD_LIGHT; do run held2 "$p"; done
for p in $HELD_ASTRO; do run held2 "$p" svelte; done
for p in $LITE_LIGHT; do run lite2 "$p"; done
for p in $LITE_ASTRO; do run lite2 "$p" svelte; done
echo "[$(date -Is)] V2FINAL RUNS DONE" >> "$R/runs.txt"
window() {
  local start end
  start=$(grep "START $1 " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END $1 " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -n "$start" ] && [ -n "$end" ] && find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1
}
args=(); pairs=()
for p in $HELD_LIGHT $HELD_ASTRO; do f=$(window "held2_$p"); [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("held/$p/v2final=$f"); done
for p in $LITE_LIGHT $LITE_ASTRO; do f=$(window "lite2_$p"); [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("$p/v2final=$f"); done
for pf in "${pairs[@]}"; do d="${pf%%=*}"; f="${pf#*=}"; mkdir -p "$R/results/$d" && cp "${f%_arms.json}"* "$R/results/$d/"; done
echo "[$(date -Is)] GRADE START v2final ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-v2final.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do d="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/$d/" 2>/dev/null; done
echo "[$(date -Is)] GRADE DONE v2final exit=$code" >> "$R/runs.txt"
