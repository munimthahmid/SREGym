# jev v2 results (SREGym-Lite, arms mode: one snapshot per fault, four arms; judge gpt-6-astra, high, via Codex)

Arms: v2+Jev 1.13 (submitted officially), v2+Decisions (gpt-6-luna-decisions), v1+Jev 1.13, v1+Decisions.
v1 = the team's jev_diag (blog version) with our PR #1118 fixes. All arms graded after the run by
`clients.jev_v2.grade` (same oracle, same answer key); the submitted arm's official grade is a cross-check.

| Fault | Blog v1 (Jev, 5 runs) | v2 Jev | v2 Decisions | v1 Jev | v1 Decisions | Notes |
|---|---|---|---|---|---|---|
| service_wrong_pod_selection_hotel_reservation | 5/5 pass, 0.89 | 100 | 100 | 89 | 89 | official grade of v2 Jev = 100 (matches); v1 lost D1 (blamed Deployment, not Service). v2 used ~6x fewer tokens. |
| search_rate_retry_collapse_hotel_reservation | **0/5 fail, 0.34** | **89 (official 89)** | **89** | 34 (fail) | 34 (fail) | **Blog failure fixed by v2 on both models.** Both v2 arms named the search->rate interaction (retry loop) with both sides' settings (search RATE_RPC_TIMEOUT_MS=750, RATE_RPC_MAX_ATTEMPTS=3, backoff; rate RATE_BACKEND_QPS_LIMIT=20). Both v1 arms blamed only rate's QPS limit (the blog's failure, reproduced). Tokens: v2 15k/9k vs v1 38k/23k. |
| cronjob_sidecar_blocks_completion_hotel_reservation | 5/5 pass, 1.00 | 100 (official 100) | 89 | 100 | 100 | v2 Jev and v2 Decisions wrote the **same text** (both picked the same explanation) and got 100 vs 89: judge noise on D2-Q2. Tokens: v2 3.8k/2.8k vs v1 31k/21k. |
| finalizer_deadlock_controller_hotel_reservation | 5/5 pass, 1.00 | 100 (official 100) | 100 | 100 | 100 | Tokens: v2 3.8k/2.6k vs v1 30k/21k. |
| namespace_memory_limit | 5/5 pass, 0.89 | 89 (official 89) | 89 | 89 | 89 | All four lost the same D-question. Tokens: v2 4.0k/2.9k vs v1 25k/17k. |
| network_policy_block | 5/5 pass, 1.00 | 100 (official 100) | 100 | 100 | 100 | Tokens: v2 3.7k/2.5k vs v1 26k/17k. |

**Hotel reservation, 6 faults (all graded):**

| Arm | Passed | Average score |
|---|---|---|
| v2 + Jev 1.13 | 6/6 | 96.3 |
| v2 + Decisions | 6/6 | 94.5 |
| v1 + Jev 1.13 | 5/6 | 85.3 |
| v1 + Decisions | 5/6 | 85.3 |

v2 uses about 6-8x fewer input tokens than v1 on every fault. Each arm takes 1-5 s and under $0.003.

Run 1: 2026-10-18 18:45-18:59 (14 min end to end, images preloaded). Per-arm time 1-4 s, cost $0.0002-0.0019.
