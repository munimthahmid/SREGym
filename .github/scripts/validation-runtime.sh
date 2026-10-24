#!/usr/bin/env bash
# Run after the unchanged smoke test, so observation cannot delay bootstrap.
set -uo pipefail
mkdir -p /tmp/validation
printf 'node\timage\tcontainerd\tkubelet\tpackages\n' > /tmp/validation/runtime.tsv
failed=0
mapfile -t nodes < <(kind get nodes 2>/dev/null)
[[ ${#nodes[@]} == 4 ]] || failed=1
for node in "${nodes[@]}"; do
    image=$(timeout 15s docker inspect --format '{{.Config.Image}}' "$node") || failed=1
    runtime=$(timeout 15s docker exec "$node" containerd --version) || failed=1
    kubelet=$(timeout 15s docker exec "$node" kubelet --version) || failed=1
    packages=$(timeout 15s docker exec "$node" dpkg-query -W '-f=${Package}=${Version} ' udev socat) || failed=1
    timeout 15s docker exec "$node" test -d /run/udev || failed=1
    printf '%s\t%s\t%s\t%s\t%s\n' "$node" "$image" "$runtime" "$kubelet" "$packages" >> /tmp/validation/runtime.tsv
    if [[ $VALIDATION_IMAGE == fixed ]]; then
        [[ $runtime == *' v2.1.0 '* && $kubelet == 'Kubernetes v1.32.5' && $image == 'sregym-kind:smoke' ]] || failed=1
    else
        [[ $runtime == *' v2.0.2 '* && $kubelet == 'Kubernetes v1.32.1' && $image == *'sha256:ccab5d6cdca66e0b83a77c2711b641fa788024fe217526980da028ac07385b93' ]] || failed=1
    fi
done
cat /tmp/validation/runtime.tsv
exit "$failed"
