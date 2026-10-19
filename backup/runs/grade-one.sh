#!/usr/bin/env bash
# Grade one finished run by its label (e.g. lite6_<problem>) into grade-rolling6.log.
R="/home/priyo_software/Priyo Work/jev-v2-runs"; label="$1"; p="${label#*_}"
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
start=$(grep "START $label " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
end=$(grep "END $label " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)
[ -z "$f" ] && { echo "[$label] no arms file" >> "$R/grade-rolling6.log"; exit 1; }
SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
  uv run python -m clients.jev_v2.grade --problem "$p" "$f" 2>&1 | grep -E " arm[0-9] v[12] " |
  sed "s/^/[$label] /" >> "$R/grade-rolling6.log"
echo "$label" >> "$R/grade-rolling6.done"
