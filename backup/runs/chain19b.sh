#!/usr/bin/env bash
# Targeted set T (jev-v2-testsets.md): once the held-out reruns end (their grading runs alongside), on the same final code (066c4d2f),
# four arms each, 1 h cap per fault. Each fault is graded in the background as soon as its run ends, so the next
# run starts at once. Labels tgt_<problem>; files in results/targeted/; scores in grade-targeted.log.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
until grep -qE "GRADE START held6|HELD6 ABORTED" "$R/runs.txt"; do sleep 30; done
cd /home/priyo_software/sregym/SREGym-fixes || exit 1
if ! git diff --quiet 066c4d2f -- clients docker agents.yaml sregym llm_backend main.py; then
  echo "[$(date -Is)] TARGETED ABORTED: code is not 066c4d2f" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] TARGETED START v2=066c4d2f" >> "$R/runs.txt"
grade() {  # problem [label-prefix dest-dir]: grade this run's own arms file, keep its files in the dest dir
  local pre="${2:-tgt}" dest="${3:-$R/results/targeted/$1}" start end f
  start=$(grep "START ${pre}_$1 " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  end=$(grep "END ${pre}_$1 " "$R/runs.txt" | tail -1 | sed -E 's/^\[([^]]+)\].*/\1/')
  f=$(find results -name '*_arms.json' -newermt "$start" ! -newermt "$end" 2>/dev/null | head -1)
  [ -z "$f" ] && { echo "[${pre}_$1] no arms file" >> "$R/grade-targeted.log"; return; }
  mkdir -p "$dest" && cp "${f%_arms.json}"* "$dest/"
  SREGYM_AGENT_IMAGE=sregym-agent-base:latest SREGYM_JUDGE_STARTUP_TIMEOUT=1800 \
    uv run python -m clients.jev_v2.grade --problem "$1" "$f" 2>&1 | grep -E " arm[0-9] v[12] " |
    sed "s/^/[${pre}_$1] /" >> "$R/grade-targeted.log"
  cp "${f%_arms.json}_arms_graded.json" "$dest/" 2>/dev/null
}
CHAT=/home/priyo_software/sregym/SREGym-chat
claimed() {  # problem: Codex (other laptop) announced it on agent-chat, so skip it here
  git -C "$CHAT" fetch -q fork agent-chat 2>/dev/null
  git -C "$CHAT" log fork/agent-chat --format=%s | grep -qE "^\[codex.claude\].*(start|done) tgt_$1( |$)"
}
announce() {  # problem: tell Codex this laptop runs it
  git -C "$CHAT" pull -q --ff-only fork agent-chat 2>/dev/null
  git -C "$CHAT" commit -q --allow-empty -m "[claude→codex] start tgt_$1 (this laptop runs it; skip it)" &&
    { git -C "$CHAT" push -q fork HEAD:agent-chat 2>/dev/null ||
      { git -C "$CHAT" pull -q --rebase fork agent-chat && git -C "$CHAT" push -q fork HEAD:agent-chat; }; }
}
# Codex takes set T from the top of its list, this laptop from the bottom, so neither waits on the other.
for p in missing_env_variable_astronomy_shop ingress_misroute update_incompatible_correlated \
         capacity_decrease_rpc_retry_storm gc_capacity_degradation; do
  claimed "$p" && { echo "[$(date -Is)] SKIP tgt_$p (Codex has it)" >> "$R/runs.txt"; continue; }
  announce "$p"
  prof=""; [ "$p" = missing_env_variable_astronomy_shop ] && prof="--profile svelte"
  RUN_TIMEOUT=3600 "$R/run.sh" "tgt_$p" openrouter/typesafe/jev-1.13 --problem "$p" $prof
  grade "$p" &
done
# The two Lite faults where v2 Jev named resource limits before the limit-vs-change rule (066c4d2f).
for p in edge_request_filter_cpu_saturation env_variable_shadowing_astronomy_shop; do
  RUN_TIMEOUT=3600 "$R/run.sh" "lim_$p" openrouter/typesafe/jev-1.13 --problem "$p" --profile svelte
  grade "$p" lim "$R/results/$p/limit_rule" &
done
wait
echo "[$(date -Is)] GRADE DONE targeted" >> "$R/runs.txt"
