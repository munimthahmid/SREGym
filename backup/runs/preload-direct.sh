#!/usr/bin/env bash
# Pull images directly on each worker in parallel. For images whose shared base layers are already unpacked on the
# node, containerd never keeps those compressed blobs, so preload.sh's export/copy cannot work for them.
# Usage: preload-direct.sh IMAGE [IMAGE...]
set -u
for node in kind-worker kind-worker2 kind-worker3; do
  (for image in "$@"; do
     ok=""; for attempt in 1 2 3 4 5; do docker exec "$node" crictl pull "$image" >/dev/null 2>&1 && { ok=1; break; }; done
     [ -n "$ok" ] && echo "[$(date +%T)] ok   $node $image" || echo "[$(date +%T)] pull failed: $node $image"
   done) &
done
wait
echo "[$(date +%T)] DIRECT DONE"
