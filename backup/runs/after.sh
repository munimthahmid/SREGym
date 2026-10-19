#!/usr/bin/env bash
# Wait for the current preload to reach its last image, then preload the hotel image.
R="/home/priyo_software/Priyo Work/jev-v2-runs"
until grep -qE "(ok   |failed: )docker.io/jaegertracing/all-in-one:1.57" "$R/preload.log"; do sleep 10; done
"$R/preload.sh" "ghcr.io/sregym/hotel-reservation:sha-d2c036bc3d1138f5a0bdaffd3d87f37522c3461a@sha256:1c685e1c4c304f327952397b3a99c54dadb086607774d71f222b200ec0d2e65e" >> "$R/preload.log" 2>&1
