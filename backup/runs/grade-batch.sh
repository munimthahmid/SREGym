#!/usr/bin/env bash
# Grade the arms of each problem's latest run with one judge, copy run files + grades to results/<problem>/.
# Usage: grade-batch.sh NAME PROBLEM [PROBLEM...]
R="/home/priyo_software/Priyo Work/jev-v2-runs"
name="$1"; shift
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
args=(); files=()
for p in "$@"; do
  start=$(grep "START arms_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  [ -z "$start" ] && continue
  f=$(ls -t results/*/.runtime/jev_diag/*/*_arms.json 2>/dev/null | while read -r x; do
        [ "$(date -r "$x" +%s)" -ge "$(date -d "$start" +%s)" ] && echo "$x"; done | tail -1)
  [ -n "$f" ] && args+=(--problem "$p" "$f") && files+=("$p=$f") && mkdir -p "$R/results/$p" && cp "${f%_arms.json}"* "$R/results/$p/"
done
echo "[$(date -Is)] GRADE START $name ${#files[@]}" >> "$R/runs.txt"
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade "${args[@]}" > "$R/grade-$name.log" 2>&1
code=$?
for pf in "${files[@]}"; do
  p="${pf%%=*}"; f="${pf#*=}"; cp "${f%_arms.json}_arms_graded.json" "$R/results/$p/" 2>/dev/null
done
echo "[$(date -Is)] GRADE DONE $name exit=$code" >> "$R/runs.txt"
