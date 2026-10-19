#!/usr/bin/env bash
# Usage: run.sh <label> <model> <main.py selection args...>   e.g. run.sh run01 openrouter/typesafe/jev-1.13 --problem X
set -u
label="$1"; model="$2"; shift 2
cd "/home/priyo_software/sregym/SREGym-fixes" || exit 1
log="/home/priyo_software/Priyo Work/jev-v2-runs/${label}.log"
echo "[$(date -Is)] START $label $model $*" >> "/home/priyo_software/Priyo Work/jev-v2-runs/runs.txt"
SREGYM_JUDGE_STARTUP_TIMEOUT=1800 OPENROUTER_API_KEY="$(cat ~/.config/openrouter/key)" \
  timeout "${RUN_TIMEOUT:-36000}" uv run main.py --agent jev_diag --model "$model" --judge-model gpt-6-astra --judge-backend codex --judge-reasoning-effort high \
  --stages diagnosis --force-build "$@" < /dev/null > "$log" 2>&1
code=$?
echo "[$(date -Is)] END $label exit=$code" >> "/home/priyo_software/Priyo Work/jev-v2-runs/runs.txt"
