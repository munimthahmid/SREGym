#!/usr/bin/env bash
# Run faults in arms mode one after another, then grade every arm with one judge.
# Usage, from the repo root:  bash docs/jev-v2-batch.sh NAME PROBLEM [PROBLEM...]
# Astronomy shop faults:      EXTRA_ARGS="--profile svelte" bash docs/jev-v2-batch.sh NAME PROBLEM...
# Needs ~/.config/openrouter/key and a Codex (ChatGPT) login in ~/.codex. Output: jev-v2-runs/ (logs, runs.txt,
# results/<problem>/ with each run's files and *_arms_graded.json).
set -u
name="$1"; shift
out="$(pwd)/jev-v2-runs"; mkdir -p "$out"
key="$(cat ~/.config/openrouter/key)"
args=(); pairs=()
for p in "$@"; do
  start=$(date +%s)
  echo "[$(date -Is)] START $p" >> "$out/runs.txt"
  # shellcheck disable=SC2086
  SREGYM_JUDGE_STARTUP_TIMEOUT=1800 OPENROUTER_API_KEY="$key" timeout 7200 uv run main.py --agent jev_diag \
    --model openrouter/typesafe/jev-1.13 --judge-model gpt-6-astra --judge-backend codex \
    --judge-reasoning-effort high --stages diagnosis --force-build --problem "$p" ${EXTRA_ARGS:-} \
    < /dev/null > "$out/$p.log" 2>&1
  echo "[$(date -Is)] END $p exit=$?" >> "$out/runs.txt"
  f=$(find results -name '*_arms.json' -newermt "@$start" 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    args+=(--problem "$p" "$f"); pairs+=("$p=$f")
    mkdir -p "$out/results/$p" && cp "${f%_arms.json}"* "$out/results/$p/"
  fi
done
[ ${#args[@]} -eq 0 ] && { echo "[$(date -Is)] nothing to grade for $name" >> "$out/runs.txt"; exit 1; }
echo "[$(date -Is)] GRADE START $name" >> "$out/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$out/grade-$name.log" 2>&1
echo "[$(date -Is)] GRADE DONE $name exit=$?" >> "$out/runs.txt"
for pf in "${pairs[@]}"; do
  p="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$out/results/$p/" 2>/dev/null
done
