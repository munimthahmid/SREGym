#!/usr/bin/env bash
# Pull each image once on kind-worker (keeps compressed layers; ghcr.io direct so cut downloads resume, docker.io
# through the local mirror), then copy it to the other kind nodes with ctr export/import --local (keeps digests).
# Usage: preload.sh IMAGE [IMAGE...]
set -u
src=kind-worker
others=$(kind get nodes | grep -v "^${src}$")
pull() { for attempt in 1 2 3 4 5; do docker exec "$src" crictl pull "$1" >/dev/null 2>&1 && return 0; echo "  retry $attempt"; done; return 1; }
export_to() {  # image tarfile
  local repo="${1%%@*}"; repo="${repo%:*}"
  local names; names=$(docker exec "$src" ctr -n k8s.io images ls -q | grep -F "$repo" | tr '\n' ' ')
  docker exec "$src" sh -c "ctr -n k8s.io images export --local --platform linux/amd64 $2 $names" >/dev/null 2>&1
}
for image in "$@"; do
  echo "[$(date +%T)] pull $image"
  pull "$image" || { echo "  pull failed: $image"; continue; }
  tar="/var/preload/img-$$-$RANDOM.tar"  # not /tmp: kind nodes mount tmpfs there and docker cp cannot read it
  if ! export_to "$image" "$tar"; then  # layers discarded by an earlier pull: pull again so they are kept
    docker exec "$src" crictl rmi "$image" >/dev/null 2>&1
    pull "$image" && export_to "$image" "$tar" || { echo "  export failed: $image"; continue; }
  fi
  mkdir -p /var/tmp/preload 2>/dev/null; host="/var/tmp/preload/$(basename "$tar")"
  docker cp "$src:$tar" "$host" >/dev/null && docker exec "$src" rm -f "$tar"
  for node in $others; do
    docker cp "$host" "$node:$tar" >/dev/null
    docker exec "$node" sh -c "ctr -n k8s.io images import --local --platform linux/amd64 $tar >/dev/null; rm -f $tar" \
      || echo "  import failed on $node: $image"
  done
  rm -f "$host"
  echo "[$(date +%T)] ok   $image"
done
