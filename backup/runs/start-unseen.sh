#!/usr/bin/env bash
# Wait for the hard set to finish, put the eval checkout on the frozen v2, then run Unseen 15 (ids read from the
# sealed file straight into the run script).
R="/home/priyo_software/Priyo Work/jev-v2-runs"; E=/home/priyo_software/sregym/SREGym-v2eval; FROZEN=eade3b0a
until [ "$(grep -c 'SET hard done' "$R/runs.txt")" -ge 2 ]; do sleep 20; done
until ! pgrep -f "v2_eval.grade --problem valkey_auth_disruption" >/dev/null; do sleep 20; done  # last hard grading
cd "$E" || exit 1
git merge -q --no-edit feat/jev-diag-v2 >/dev/null 2>&1
git checkout "$FROZEN" -- clients/jev_diag/v2 tests/clients && git add -A clients/jev_diag/v2 tests/clients
git commit -q --no-edit -m "eval at frozen v2 $FROZEN" >/dev/null 2>&1
if ! git diff --quiet "$FROZEN" -- clients/jev_diag/v2 || ! grep -q "def failing_callers" clients/jev_diag/v2/report.py \
   || ! grep -q "def fit_choices" clients/jev_diag/v2/classifier.py; then
  echo "[$(date -Is)] UNSEEN NOT STARTED: eval checkout is not at frozen $FROZEN" >> "$R/runs.txt"; exit 1
fi
echo "[$(date -Is)] UNSEEN eval checkout at frozen v2 $FROZEN ($(git rev-parse --short HEAD))" >> "$R/runs.txt"
mapfile -t IDS < <(grep -v '^#' ~/.local/share/jev-v2-sealed/UNSEEN-15.txt | sed '/^\s*$/d')
"$R/run-set2.sh" unseen "${IDS[@]}"
