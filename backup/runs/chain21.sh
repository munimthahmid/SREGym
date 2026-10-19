#!/usr/bin/env bash
# Set T ingress_misroute again after the queue: its first attempt failed in SREGym's setup (Helm v4 has no
# `helm list --all`), so this run puts a Helm v3-compatible wrapper first on PATH. Same code check, same grading.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
until grep -q "GRADE DONE targeted" "$R/runs.txt"; do sleep 30; done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet 066c4d2f -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] INGRESS ABORTED: code is not 066c4d2f" >> "$R/runs.txt"; exit 1
fi
p=ingress_misroute
PATH="$HOME/.local/share/helm-v3compat:$PATH" RUN_TIMEOUT=3600 "$R/run.sh" "tgt_$p" openrouter/typesafe/jev-1.13 --problem "$p"
start=$(grep "START tgt_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
end=$(grep "END tgt_$p " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)
if [ -n "$f" ]; then
  mkdir -p "$R/results/targeted/$p" && cp "${f%_arms.json}"* "$R/results/targeted/$p/"
  SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
    uv run python -m clients.jev_v2.grade --problem "$p" "$f" 2>&1 | grep -E " arm[0-9] v[12] " |
    sed "s/^/[tgt_$p] /" >> "$R/grade-targeted.log"
  cp "${f%_arms.json}_arms_graded.json" "$R/results/targeted/$p/" 2>/dev/null
else
  echo "[tgt_$p] no arms file" >> "$R/grade-targeted.log"
fi
echo "[$(date -Is)] GRADE DONE ingress" >> "$R/runs.txt"
