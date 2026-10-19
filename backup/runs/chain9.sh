#!/usr/bin/env bash
# Final v2 676024e9 (outside-object fix + v1's key-evidence step). Runs every held-out sample fault whose result
# could differ under it (all but DNS astronomy, whose candidates and concrete winner are unchanged; duplicate PVC
# hotel only if its 272123ae run ended on "mechanism unknown"), reruns the 3 Lite faults it can change (retry
# collapse: Decisions ended mechanism-unknown; secret rotation and unschedulable: outside-object fix), then grades
# all 10 held-out faults and the 3 Lite reruns with one judge. 1 h cap per fault.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
FROZEN=676024e9
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
until grep -q "END held_duplicate_pvc_mounts_hotel_reservation " "$R/runs.txt"; do sleep 20; done
window() {  # label_problem -> this run's own arms file
  local start end
  start=$(grep "START $1 " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END $1 " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -n "$start" ] && [ -n "$end" ] && find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1
}
DUP=""
f=$(window held_duplicate_pvc_mounts_hotel_reservation)
if [ -z "$f" ] || python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if any(((a.get('investigation') or {}).get('winner') or '').startswith('partial:') for a in d['arms'][:2]) else 1)" "$f"; then
  DUP=duplicate_pvc_mounts_hotel_reservation
fi
HELD_LIGHT="sidecar_port_conflict_hotel_reservation $DUP readiness_probe_misconfiguration_hotel_reservation
            liveness_probe_too_aggressive_social_network service_port_conflict_social_network auth_miss_mongodb"
HELD_ASTRO="wrong_service_selector_astronomy_shop valkey_memory_disruption incorrect_image"
LITE_HOTEL="search_rate_retry_collapse_hotel_reservation"
LITE_ASTRO="secret_rotation_stale_env_credentials_astronomy_shop unschedulable_incorrect_port_assignment"
HELD_ALL="service_dns_resolution_failure_astronomy_shop sidecar_port_conflict_hotel_reservation
          duplicate_pvc_mounts_hotel_reservation readiness_probe_misconfiguration_hotel_reservation
          liveness_probe_too_aggressive_social_network service_port_conflict_social_network auth_miss_mongodb
          wrong_service_selector_astronomy_shop valkey_memory_disruption incorrect_image"
if ! git diff --quiet "$FROZEN" -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] FINALV2 ABORTED: code is not the frozen $FROZEN" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] FINALV2 START v2=$FROZEN dup_rerun=${DUP:-no}" >> "$R/runs.txt"
for p in $HELD_LIGHT; do RUN_TIMEOUT=3600 "$R/run.sh" "held_$p" openrouter/typesafe/jev-1.13 --problem "$p"; done
for p in $HELD_ASTRO; do RUN_TIMEOUT=3600 "$R/run.sh" "held_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
for p in $LITE_HOTEL; do RUN_TIMEOUT=3600 "$R/run.sh" "final_$p" openrouter/typesafe/jev-1.13 --problem "$p"; done
for p in $LITE_ASTRO; do RUN_TIMEOUT=3600 "$R/run.sh" "final_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
echo "[$(date -Is)] FINALV2 RUNS DONE" >> "$R/runs.txt"
args=(); pairs=()
for p in $HELD_ALL; do f=$(window "held_$p"); [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("held/$p=$f"); done
for p in $LITE_HOTEL $LITE_ASTRO; do f=$(window "final_$p"); [ -n "$f" ] && args+=(--problem "$p" "$f") && pairs+=("$p/final_v2=$f"); done
for pf in "${pairs[@]}"; do d="${pf%%=*}"; f="${pf#*=}"; mkdir -p "$R/results/$d" && cp "${f%_arms.json}"* "$R/results/$d/"; done
echo "[$(date -Is)] GRADE START finalv2 ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-finalv2.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do d="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/$d/" 2>/dev/null; done
echo "[$(date -Is)] GRADE DONE finalv2 exit=$code" >> "$R/runs.txt"
