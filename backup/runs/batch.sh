#!/usr/bin/env bash
# Run several problems one after another in arms mode. Usage: batch.sh PROBLEM [PROBLEM...]
R="/home/priyo_software/Priyo Work/jev-v2-runs"
for p in "$@"; do
  "$R/run.sh" "arms_$p" openrouter/typesafe/jev-1.13 --problem "$p"
done
echo "[$(date -Is)] BATCH DONE $*" >> "$R/runs.txt"
