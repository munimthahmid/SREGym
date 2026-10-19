#!/usr/bin/env bash
# As soon as the held-out part of chain10 is done (first lite2_ run starts), grade the 10 held-out faults.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
until grep -q "START lite2_" "$R/runs.txt"; do sleep 30; done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
args=()
for p in sidecar_port_conflict_hotel_reservation duplicate_pvc_mounts_hotel_reservation readiness_probe_misconfiguration_hotel_reservation \
         liveness_probe_too_aggressive_social_network service_port_conflict_social_network auth_miss_mongodb \
         service_dns_resolution_failure_astronomy_shop wrong_service_selector_astronomy_shop valkey_memory_disruption incorrect_image; do
  start=$(grep "START held2_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END held2_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -n "$start" ] && [ -n "$end" ] || continue
  f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)
  [ -n "$f" ] && args+=(--problem "$p" "$f")
done
echo "[$(date -Is)] GRADE START held-early $(( ${#args[@]} / 3 ))" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-held-early.log" 2>&1
echo "[$(date -Is)] GRADE DONE held-early exit=$?" >> "$R/runs.txt"
