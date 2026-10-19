#!/usr/bin/env bash
# Frozen v2 272123ae (outside-object fix): rerun the faults whose candidates the fix changes (Lite: secret rotation,
# unschedulable; held-out: wrong service selector, sidecar port conflict), run the 7 held-out faults not run yet,
# then grade the 2 Lite reruns and all 10 held-out faults with one judge (held-out DNS astronomy keeps its run:
# identical candidates under the fix). 1 h cap per fault.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
FROZEN=272123ae
LITE_RERUN="secret_rotation_stale_env_credentials_astronomy_shop unschedulable_incorrect_port_assignment"
HELD_HOTEL_SOCIAL="sidecar_port_conflict_hotel_reservation duplicate_pvc_mounts_hotel_reservation
       readiness_probe_misconfiguration_hotel_reservation liveness_probe_too_aggressive_social_network
       service_port_conflict_social_network auth_miss_mongodb"
HELD_ASTRO="wrong_service_selector_astronomy_shop valkey_memory_disruption incorrect_image"
HELD_ALL="service_dns_resolution_failure_astronomy_shop $HELD_HOTEL_SOCIAL $HELD_ASTRO"
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet "$FROZEN" -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] V2B ABORTED: code is not the frozen $FROZEN" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] V2B START v2=$FROZEN" >> "$R/runs.txt"
for p in $HELD_HOTEL_SOCIAL; do RUN_TIMEOUT=3600 "$R/run.sh" "held_$p" openrouter/typesafe/jev-1.13 --problem "$p"; done
for p in $HELD_ASTRO; do RUN_TIMEOUT=3600 "$R/run.sh" "held_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
for p in $LITE_RERUN; do RUN_TIMEOUT=3600 "$R/run.sh" "final_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte; done
echo "[$(date -Is)] V2B RUNS DONE" >> "$R/runs.txt"
args=(); pairs=()
add() {  # label problem dest
  local start end f
  start=$(grep "START $1_$2 " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END $1_$2 " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -z "$start" ] || [ -z "$end" ] && return
  f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)
  [ -n "$f" ] && args+=(--problem "$2" "$f") && pairs+=("$3=$f") && mkdir -p "$R/results/$3" && cp "${f%_arms.json}"* "$R/results/$3/"
}
for p in $HELD_ALL; do add held "$p" "held/$p"; done
for p in $LITE_RERUN; do add final "$p" "$p/final_v2b"; done
echo "[$(date -Is)] GRADE START v2b ${#pairs[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-v2b.log" 2>&1
code=$?
for pf in "${pairs[@]}"; do
  d="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/$d/" 2>/dev/null
done
echo "[$(date -Is)] GRADE DONE v2b exit=$code" >> "$R/runs.txt"
