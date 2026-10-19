#!/usr/bin/env bash
# One host-side pull of the OpenSearch image at full bandwidth, then load it into every kind node.
IMG=opensearchproject/opensearch:3.4.0
R="/home/priyo_software/Priyo Work/jev-v2-runs"
echo "[$(date -Is)] opensearch host pull start" >> "$R/runs.txt"
until docker pull "$IMG" > "$R/opensearch-pull.log" 2>&1; do sleep 10; done
kind load docker-image "$IMG" >> "$R/opensearch-pull.log" 2>&1 && echo "[$(date -Is)] opensearch image loaded into all nodes" >> "$R/runs.txt"
