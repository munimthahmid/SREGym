# jev v2 results (SREGym-Lite, arms mode: one snapshot per fault, four arms; judge gpt-6-astra, high, via Codex)

## Final pass: frozen v2 1d22d925, all 17 SREGym-Lite faults (2026-10-18 22:05 to 2026-10-19 00:32)

One run per fault, four arms on the same snapshot, all graded by gpt-6-astra (high) through Codex with the
same SREGym oracle. ✗ = fail (below 0.70).

| Arm | Passed | Average | Input tokens (all 17) | Model cost (all 17) |
|---|---|---|---|---|
| **v2 + Jev 1.13** | **16/17** | 92.2 | 164k | $0.0069 |
| v2 + Decisions | 14/17 | 83.1 | 133k | $0.0133 |
| v1 + Jev 1.13 | 13/17 | 86.4 | 606k | $0.0255 |
| v1 + Decisions | 13/17 | 83.2 | 388k | $0.0388 |
| Blog v1 (Jev 1.13, 5 runs each) | 12/17 | | | |

| Fault | Blog v1 | v2 Jev | v2 Decisions | v1 Jev | v1 Decisions |
|---|---|---|---|---|---|
| service_wrong_pod_selection_hotel_reservation | 5/5 | 89 | 89 | 100 | 89 |
| search_rate_retry_collapse_hotel_reservation | **0/5** | 89 | 45 ✗ | 34 ✗ | 34 ✗ |
| cronjob_sidecar_blocks_completion_hotel_reservation | 5/5 | 100 | 100 | 100 | 100 |
| finalizer_deadlock_controller_hotel_reservation | 5/5 | 100 | 100 | 100 | 100 |
| namespace_memory_limit | 5/5 | 89 | 89 | 89 | 89 |
| network_policy_block | 5/5 | 100 | 100 | 100 | 100 |
| service_dns_resolution_failure_social_network | **0/5** | 100 | 100 | 89 | 67 ✗ |
| mutating_webhook_resource_limits_social_network | 5/5 | 89 | 89 | 89 | 89 |
| duplicate_pvc_mounts_social_network | 5/5 | 100 | 100 | 100 | 100 |
| rolling_update_misconfigured_social_network | 5/5 | 100 | 100 | 100 | 100 |
| edge_request_filter_cpu_saturation | **0/5** | 89 | 89 | 67 ✗ | 89 |
| env_variable_shadowing_astronomy_shop | 5/5 | 89 | 89 | 89 | 89 |
| kafka_poison_pill_hol_block | **0/5** | 89 | 89 | 67 ✗ | 56 ✗ |
| internal_traffic_policy_local_astronomy_shop | 5/5 | 89 | 89 | 100 | 89 |
| valkey_auth_disruption | **0/5** | 67 ✗ | 67 ✗ | 45 ✗ | 23 ✗ |
| secret_rotation_stale_env_credentials_astronomy_shop | 5/5 | 100 | 0 ✗ | 100 | 100 |
| unschedulable_incorrect_port_assignment | 5/5 | 89 | 78 | 100 | 100 |

**What it shows:**
- v2 + Jev passes 16/17 (blog v1: 12/17; v1 here: 13/17). It passes four of the blog's five failures (retry
  collapse, DNS, edge request filter, kafka) and loses none of the faults v1 passes. Only valkey fails, for every arm.
- v2 uses about 3.7x fewer input tokens than v1 with Jev (2.9x with Decisions), and costs about a quarter.
- v2 + Decisions passes 14/17. Its two extra misses are choices, not missing candidates: on retry collapse it
  accepted "fault in rate, mechanism unknown" at 0.62 without reading detail; on secret rotation it moved from
  the stale-read explanation (0.34) to the ConfigMap (0.45) and the budget ended.
- Known v2 weaknesses (not fixed; the version is frozen): accepting a mechanism-unknown answer while budget
  remains; valkey's runtime password needs a live check against the server (not built).
- v1 + Decisions: on valkey, OpenAI's Decisions API refused one of v1's questions in the first pass (HTTP 502).

The development runs below used v2 versions that changed during the day; they are kept as history.

Arms: v2+Jev 1.13 (submitted officially), v2+Decisions (gpt-6-luna-decisions), v1+Jev 1.13, v1+Decisions.
v1 = the team's jev_diag (blog version) with our PR #1118 fixes. All arms graded after the run by
`clients.jev_v2.grade` (same oracle, same answer key); the submitted arm's official grade is a cross-check.

| Fault | Blog v1 (Jev, 5 runs) | v2 Jev | v2 Decisions | v1 Jev | v1 Decisions | Notes |
|---|---|---|---|---|---|---|
| service_wrong_pod_selection_hotel_reservation | 5/5 pass, 0.89 | 100 | 100 | 89 | 89 | official grade of v2 Jev = 100 (matches); v1 lost D1 (blamed Deployment, not Service). v2 used ~6x fewer tokens. |
| search_rate_retry_collapse_hotel_reservation | **0/5 fail, 0.34** | **89 (official 89)** | **89** | 34 (fail) | 34 (fail) | **Blog failure fixed by v2 on both models.** Both v2 arms named the search->rate interaction (retry loop) with both sides' settings (search RATE_RPC_TIMEOUT_MS=750, RATE_RPC_MAX_ATTEMPTS=3, backoff; rate RATE_BACKEND_QPS_LIMIT=20). Both v1 arms blamed only rate's QPS limit (the blog's failure, reproduced). Tokens: v2 15k/9k vs v1 38k/23k. |
| cronjob_sidecar_blocks_completion_hotel_reservation | 5/5 pass, 1.00 | 100 (official 100) | 89 | 100 | 100 | Rerun on 8912490e: 100 / 89 / 100 / 100 (unchanged). v2 Jev and v2 Decisions wrote the **same text** (both picked the same explanation) and got 100 vs 89: judge noise on D2-Q2. Tokens: v2 3.8k/2.8k vs v1 31k/21k. |
| finalizer_deadlock_controller_hotel_reservation | 5/5 pass, 1.00 | 100 (official 100) | 100 | 100 | 100 | Tokens: v2 3.8k/2.6k vs v1 30k/21k. |
| namespace_memory_limit | 5/5 pass, 0.89 | 89 (official 89) | 89 | 89 | 89 | All four lost the same D-question. Tokens: v2 4.0k/2.9k vs v1 25k/17k. |
| network_policy_block | 5/5 pass, 1.00 | 100 (official 100) | 100 | 100 | 100 | Tokens: v2 3.7k/2.5k vs v1 26k/17k. |
| service_dns_resolution_failure_social_network | **0/5 fail, 0.56-0.67** | 100 (official 100) | 100 | 89 | 67 (fail) | All arms but v1 Decisions named ConfigMap coredns and the NXDOMAIN rule for user-service; v1 Decisions blamed Deployment user-service. v1 Jev also passes here with today's answer key, so this is not a clean "v2 fixed it" case. |
| mutating_webhook_resource_limits_social_network | 5/5 pass, 0.89 | 89 (official 89) | 89 | 89 | 89 | All four named the gatekeeper webhook. |
| duplicate_pvc_mounts_social_network | 5/5 pass, 1.00 | **0 (official 0)** | **11** | 100 | 100 | **v2 gap.** v2 had no candidate for "a component's own setting is wrong" and skipped jaeger as a monitoring component; Jev picked a CoreDNS change left over from the previous (DNS) fault. Fixed in 3dc3e053 + c25fde1a; **Live rerun with the fix (3dc3e053): v2 Jev 100, v2 Decisions 100, v1 Jev 100, v1 Decisions 0** (v1 Decisions blamed the CoreDNS change left over from the DNS fault, the same trap v2 fell into before). |
| rolling_update_misconfigured_social_network | 5/5 pass, 1.00 | 89 (official 89) | 78 | 100 | 100 | v2 found custom-service but said "mechanism not established" (lost D2). With the own-setting fix, replay on this snapshot names the hang-init container and the rollout settings on both models. First attempt hit SREGym's 120 s image-pull limit; attempt 2 ran. |
| edge_request_filter_cpu_saturation | **0/5 fail** | 89 (official 89) | 89 | 67 (fail) | 89 | **Blog failure fixed by v2 on both models.** v2 named frontend-proxy's new filter script with the catastrophic regex; v1 Jev blamed only the CPU limit (the blog's failure); v1 Decisions named the script too. |
| env_variable_shadowing_astronomy_shop | 5/5 pass | 89 (official 89) | 89 | 89 | 89 | |
| kafka_poison_pill_hol_block | **0/5 fail** | **11 (official 11)** | **11** | 67 (fail) | 56 (fail) | **v2 bug:** when no explanation fit, v2 re-read the same component instead of the next one, so it never read orders-validator's logs (the same message failing 51 times). Fixed in f0f42805; checked in the final pass. |
| internal_traffic_policy_local_astronomy_shop | 5/5 pass | 89 (official 89) | 89 | 89 | 100 | |
| valkey_auth_disruption | **0/5 fail** | 67 (official 67, fail) | 67 | 34 | 0 (API refused) | Everyone failed. v2 named valkey-cart but not the password; the password is set at runtime and nothing collected shows it (needs a probe, not built). v1 Decisions: OpenAI's Decisions API refused one of v1's questions (HTTP 502), so v1 Decisions submitted nothing. |
| secret_rotation_stale_env_credentials_astronomy_shop | 5/5 pass | **0 (official 0)** | **0** | 100 | 100 | **v2 gap:** v2 framed the rewritten Secret, not the stale product-catalog, and both models picked a ConfigMap instead. Fixed in 1d22d925 (stale-read explanations + ranking); replay picks product-catalog on both models. |
| unschedulable_incorrect_port_assignment | 5/5 pass | 89 (official 89) | 78 | 100 | 100 | |

**All 17 Lite faults, first pass (development runs; v2 changed during the day, see Notes):**

| Arm | Passed | Average score |
|---|---|---|
| v2 + Jev 1.13 | 13/17 | 75.9 |
| v2 + Decisions | 13/17 | 74.6 |
| v1 + Jev 1.13 | 13/17 | 84.5 |
| v1 + Decisions | 13/17 | 82.5 |
| Blog v1 (Jev 1.13, 5 runs each) | 12/17 | |

v2 fixed two blog failures on both models (retry collapse, edge request filter) but had three gaps of its own
(duplicate PVC, kafka, secret rotation), each a full miss, which pulls its average down. All three are fixed in the
frozen v2 (**1d22d925**); valkey stays a miss for every arm. **Final pass:** all 17 faults again on the frozen
1d22d925, four arms each (running overnight 2026-10-18); that table replaces this one for the PR.

**Hotel + social, 10 faults, live runs (before the own-setting fix):**

| Arm | Passed | Average score |
|---|---|---|
| v2 + Jev 1.13 | 9/10 | 85.6 |
| v2 + Decisions | 9/10 | 84.5 |
| v1 + Jev 1.13 | 9/10 | 89.0 |
| v1 + Decisions | 8/10 | 86.8 |

v2 fixed the blog's retry-collapse failure on both models but missed duplicate PVC (see the row). The own-setting fix
is in; reruns of duplicate PVC and cronjob with it are graded at the end. The v2 code is frozen after this fix: the
astronomy faults and every held-out fault run on the same version.

**Hotel reservation, 6 faults (all graded):**

| Arm | Passed | Average score |
|---|---|---|
| v2 + Jev 1.13 | 6/6 | 96.3 |
| v2 + Decisions | 6/6 | 94.5 |
| v1 + Jev 1.13 | 5/6 | 85.3 |
| v1 + Decisions | 5/6 | 85.3 |

v2 uses about 6-8x fewer input tokens than v1 on every fault. Each arm takes 1-5 s and under $0.003.

Run 1: 2026-10-18 18:45-18:59 (14 min end to end, images preloaded). Per-arm time 1-4 s, cost $0.0002-0.0019.
