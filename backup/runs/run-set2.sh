#!/usr/bin/env bash
# Live arms runs, one problem at a time, from the eval worktree; each run is graded (all arms) before the next.
# Usage: run-set.sh <set-name> <problem> [<problem> ...]
set -u
SET="$1"; shift
R="${RUNS_DIR:-/home/priyo_software/Priyo Work/jev-v2-runs}"   # logs and copied results
E="${SREGYM_EVAL_DIR:-/home/priyo_software/sregym/SREGym-v2eval}"  # checkout of the v2-eval branch
OUT="$R/results/$SET"
mkdir -p "$OUT"
cd "$E" || exit 1
echo "[$(date -Is)] SET $SET start, code $(git rev-parse --short HEAD) + $(git diff --stat | tail -1)" >> "$R/runs.txt"
# the agent image once per set; the judge looks for the same image under the release name this branch pins
bash docker/agents/build.sh >> "$R/build-$SET.log" 2>&1 || { echo "[$(date -Is)] SET $SET image build failed" >> "$R/runs.txt"; exit 1; }
docker tag sregym-agent-base:latest ghcr.io/sregym/agent-base:sha-b97d6810e994bb7354b4bc15c6bc81cb66e816b9
grade_when_ready() {  # grade a problem as soon as its answers file exists (cleanup continues in parallel)
  local p="$1" label="$2" start="$3" f=""
  for _ in $(seq 1 720); do
    f=$(find results -name '*_arms.json' -newermt "$start" 2>/dev/null | head -1)
    [ -n "$f" ] && break
    [ -f "$R/.done_$label" ] && break
    sleep 5
  done
  if [ -z "$f" ]; then echo "[$label] no arms file" >> "$R/grade-$SET.log"; return; fi
  sleep 5  # let the file be fully written
  mkdir -p "$OUT/$p" && cp "${f%_arms.json}"* "$OUT/$p/"
  SREGYM_JUDGE_STARTUP_TIMEOUT=1800 .venv/bin/python -m clients.jev_diag.v2_eval.grade --problem "$p" "$f" 2>&1 |
    grep -E " arm[0-9]+ v[12] |Traceback|Error" | sed "s/^/[$label] /" >> "$R/grade-$SET.log"
  cp "${f%_arms.json}_arms_graded.json" "$OUT/$p/" 2>/dev/null
  echo "[$(date -Is)] GRADED $label" >> "$R/runs.txt"
}
for p in "$@"; do
  label="${SET}_$p"
  start=$(date -Is)
  echo "[$start] START $label" >> "$R/runs.txt"
  grade_when_ready "$p" "$label" "$start" &
  KEY="$(cat ~/.config/openrouter/key)"
  # decision models come through OpenRouter (the eval arms pick each model themselves)
  SREGYM_JUDGE_STARTUP_TIMEOUT=1800 OPENROUTER_API_KEY="$KEY" DECISIONS_OPENROUTER_API_KEY="$KEY" JEV_DIAG_BACKEND=openrouter \
    timeout "${RUN_TIMEOUT:-5400}" uv run main.py --agent jev_diag --model openrouter/typesafe/jev-1.13 \
    --judge-model gpt-6-astra --judge-backend codex --judge-reasoning-effort high \
    --stages diagnosis --agent-timeout 3600 --force-build --problem "$p" < /dev/null > "$R/$label.log" 2>&1
  code=$?
  touch "$R/.done_$label"
  echo "[$(date -Is)] END $label exit=$code" >> "$R/runs.txt"
done
wait
echo "[$(date -Is)] SET $SET done" >> "$R/runs.txt"
