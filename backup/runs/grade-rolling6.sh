#!/usr/bin/env bash
# Grade each held2_/lite2_ fault of chain10 as soon as it ends (one judge start per fault, ~3 min), alongside the
# runs. Stops after "V2H RUNS DONE" once everything is graded. Results: grade-rolling6.log (one block per fault).
R="/home/priyo_software/Priyo Work/jev-v2-runs"
done_list="$R/grade-rolling6.done"; touch "$done_list"
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
while true; do
  pending=0
  while read -r label; do
    grep -qx "$label" "$done_list" && continue
    p="${label#*_}"
    start=$(grep "START $label " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
    end=$(grep "END $label " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
    f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)
    if [ -n "$f" ]; then
      SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
        uv run python -m clients.jev_v2.grade --problem "$p" "$f" 2>&1 | grep -E " arm[0-9] v[12] " |
        sed "s/^/[$label] /" >> "$R/grade-rolling6.log"
    else
      echo "[$label] no arms file" >> "$R/grade-rolling6.log"
    fi
    echo "$label" >> "$done_list"; pending=1
  done < <(grep -oE "END (lite6)_[a-z0-9_]+" "$R/runs.txt" | awk '{print $2}')
  if [ $pending -eq 0 ] && grep -q "V2H RUNS DONE" "$R/runs.txt"; then
    n_end=$(grep -cE "END (lite6)_" "$R/runs.txt"); n_done=$(wc -l < "$done_list")
    [ "$n_done" -ge "$n_end" ] && { echo "[$(date -Is)] ROLLING GRADE DONE $n_done" >> "$R/runs.txt"; exit 0; }
  fi
  sleep 30
done
