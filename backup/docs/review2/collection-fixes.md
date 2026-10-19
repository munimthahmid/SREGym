# v2 collection fixes (2026-10-19)

Branch `v2-collect-fixes` in `~/sregym/SREGym-v2fix`, cut from `feat/jev-diag-v2` at e131dda1. Twelve commits, not
pushed. Tests in `tests/clients` pass (378) and ruff is clean. The A/B replay of all 29 dev recordings was run again on
the final commit. Scripts and outputs are in `scratchpad/v2fix/` (`ab_after.*`, `cmp.py`, `tmpl.py`, `revtimes.py`,
`called.py`).

## Commits

| Commit | Fix | What changed |
|---|---|---|
| 3d3b820b | collection 1 | A rolling restart adds no evidence kind, so the telemetry collector is pushed down the queue again. |
| 1e7b153f | collection 2 | The MongoDB probe template is filled by plain replacement. The probe runs `listDatabases`, which fails without a login when the server needs one, and reports the server's error text. The legacy shell gets 128 MiB. One test case per role template. |
| 2cf4b002 | collection 3 | Pod template changes are diffed against the template current at deploy, and the pod-template-hash label is ignored. |
| 0702e9ba | collection 3, generality 4 | The baseline is the newest revision within 10 s of the application's deploy time. A workload re-created later by the fault is compared with its first revision. |
| f805bce0 | collection 6 | A related namespace never replaces an application component with the same id, and its workloads are marked `related`. Pods, events, Jobs and usage match a workload in their own namespace only. The deploy time comes from the application's own workloads. |
| d8d35d13 | collection 5 | The `changed` flags (NetworkPolicy, role, quota, webhook, CoreDNS) and kube-system findings are set only for writes the change ranking keeps. |
| 5fb479fb | collection 4 | An Ingress or PriorityClass is a finding only with a missing backend, 0 ready endpoints, or a kept write. Routes and values stay with the object as context. A default backend with a named port now prints the port name. |
| 8cfb5626 | collection 7 | A key repeated with different values in one config file is dropped as ambiguous. |
| bed46851 | generality 5 (B) | Call settings match a callee by whole words, need a numeric value, and telemetry settings are left out. |
| 62d0b191 | generality 1 wording (C) | The call path sentence names the retry and capacity settings instead of the unmeasured "multiplies" claim. The `feedback_loop` flag is unchanged. |
| 1b253dd9 | generality 2 (A) | Call paths are computed after change signals, so a callee with its own recent change gets no path. A restart does not count. |
| 838f6b16 | generality 3 (D) | The "called position" narrowing is removed, so a line naming several components points at each of them, as in v1. |

## What changed on the 29 recordings (v2 before vs after)

- **Telemetry demotion is back.** In all 12 Astronomy Shop recordings the otel collector's kinds went from `symptoms` to `error_logs_only`, so it is demoted again. This includes valkey_auth, valkey_memory and secret_rotation.
- **secret_rotation.** product-catalog's change signal now carries `env DB_CONNECTION_STRING: postgres://otelu:otelp@... -> from secretKeyRef product-catalog-db-conn`. Before, it showed only the restart and the hash.
- **Template change signals lead with the setting.** The pod-template-hash line is gone from every Deployment diff, so the real change is among the three shown. This affects 8 recordings, including incorrect_image, missing_env, update_incompatible (all 6 databases), internal_traffic_policy and env_shadowing.
- **Hotel setup patch is gone.** The benchmark's `failure-script` volume on mongodb-geo and mongodb-rate is no longer a template change in the 8 hotel recordings that had it. It was patched 3-4 s after deploy.
- **rolling_update.** custom-service's template change now shows `container hang-init added (initContainers, image busybox:1.36)` instead of only the restart.
- **CoreDNS flag.** `cluster_dns.changed` dropped from 15 recordings to 2. The 13 dropped ones are pre-deploy leftovers, and the 2 kept ones are the real DNS faults (held4 astronomy, lite6 social network).
- **missing_env.** quote and shipping get their `pointed_at` back, and frontend points at email, quote and shipping again (v1 behavior).
- **search_rate.** The call path still fires with the same settings. Only its sentence changed.
- **Unchanged.** Recent changes, findings and nearest-change flags are the same in all 29. checkout in unschedulable_incorrect_port_assignment keeps its `PRODUCT_CATALOG_ADDR 8080 -> 8082` diff.

**No fault lost a true fact.** The only item that disappeared from a fault's data is in mutating_webhook. There, the injector pre-patches nginx-thrift's memory limits 7 s after deploy, as a decoy that makes the spec look normal. It is now treated as part of deploying, so it is no longer listed as a template change. nginx-thrift's signals, kinds and findings are unchanged, and the ground truth is the webhook.

Synthetic cluster runs (`review-collect/synthetic*.py`) show the following.
- The app's `frontend` is no longer replaced by the related namespace's.
- The 1800 s old kube-proxy write is gone from changes and findings.
- A healthy PriorityClass and route are no findings.

The repeated `timeout_ms` case (two blocks, two values) is covered by a unit test, since no synthetic workload reads that ConfigMap.

## Not done here
- The H3 and CRD lines in IMPLEMENTATION (collection 6c) are a doc correction and were not touched. StatefulSet pod addresses (`mongo-0.mongo.ns.svc`) are still not found by the related-namespace scan.
- A key that has one value in a shared file is still given to every service that mounts it, because it is not ambiguous. An example is Social Network's `workers=32` and `timeout_ms=10000`. Scoping keys by JSON or YAML block would fix that.
- The smaller collection 10 items are open. They are fail-soft wrapping of the new readers, probe timing in the triage summary, `restart_only` in `recent_changes`, and kube-system `affects`.
