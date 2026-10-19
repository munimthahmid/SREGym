#!/usr/bin/env bash
# During cleanup only: when an application namespace has been deleting for more than 4 minutes, force-remove the
# pods that keep it from going away (as on 2026-10-19 18:10). A namespace is deleted only after a run ends, so a fault
# under diagnosis is never touched. System namespaces are skipped. Runs until all sets are done.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
SKIP="kube-system|kube-public|kube-node-lease|local-path-storage|observe|sregym|openebs|chaos-mesh|khaos|default"
until grep -q "ALL SETS DONE" "$R/runs.txt"; do
  kubectl get ns -o json 2>/dev/null | python3 -c '
import json,sys,datetime,re
skip=re.compile(r"^('"$SKIP"')$")
now=datetime.datetime.now(datetime.timezone.utc)
for n in json.load(sys.stdin).get("items",[]):
    m=n["metadata"]; t=m.get("deletionTimestamp")
    if t and not skip.match(m["name"]):
        age=(now-datetime.datetime.fromisoformat(t.replace("Z","+00:00"))).total_seconds()
        if age>240: print(m["name"], int(age))
' | while read -r ns age; do
    for pod in $(kubectl get pods -n "$ns" -o name 2>/dev/null); do
      kubectl delete -n "$ns" "$pod" --grace-period=0 --force >/dev/null 2>&1 &&
        echo "[$(date -Is)] WATCHDOG force-removed $ns/$pod (namespace deleting ${age}s)" >> "$R/runs.txt"
    done
  done
  sleep 60
done
