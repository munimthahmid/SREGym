#!/usr/bin/env bash
# Finish the held-out sample on 30dd021e (same code as chain13): the 3 faults left, after the running one ends. No Lite.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
until grep -q "END held5_readiness_probe_misconfiguration_hotel_reservation " "$R/runs.txt"; do sleep 15; done
if ! git diff --quiet 30dd021e -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] HELD5B ABORTED: code is not 30dd021e" >> "$R/runs.txt"; exit 1
fi
for p in liveness_probe_too_aggressive_social_network service_port_conflict_social_network auth_miss_mongodb; do
  RUN_TIMEOUT=3600 "$R/run.sh" "held5_$p" openrouter/typesafe/jev-1.13 --problem "$p"
done
echo "[$(date -Is)] HELD5B DONE" >> "$R/runs.txt"
