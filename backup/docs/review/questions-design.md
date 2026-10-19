# Decision-model interaction design (questions, states, agreement)

Status: DONE (2026-10-19). Read-only design for STRATEGY.md section 3 items 4-5. Sources are README.md,
STRATEGY.md, decision-models.md, v1-architecture.md, v2-audit.md, forensics.md, the SDK in
`~/sregym/SREGym-fixes/.venv/.../typesafe_sdk/_core/question_types.py`, `clients/jev_diag/openrouter.py`, and the
snapshots and request files of the runs named in section 7. UNSEEN-SEALED.txt was read only as a list of names to
avoid; the `sealed/` folder and the 40 problems' files and runs were not opened (the noise script skips them).
No API call was made. One throwaway script (session scratchpad) measured order noise on existing request files
(section 5.2). "Fact" means read from code or run files. "Opinion" means my judgement.

---

## 0. Summary

1. The model answers one kind of question that decides things, a **slate**: "which of these 2-7 options is where the
   fault was injected", with a "none of these" option. Every option is a **fact card** with the same fields in the
   same order. Code fills the cards with facts and never with conclusions.
2. Five request types. (R1) optional symptom reading, (R2) a wide screen only when more than 6 candidates survive
   merging, (R3) the origin slate asked twice in reversed order, (R4) a tie-break only when the two asks are not
   stable, (R5) describe the fault with facts of the chosen origin. A typical diagnosis sends 5 requests and uses
   ~20-35k Jev tokens, about v1's median. Every request stays under ~16k characters (~7k Jev tokens), so 32k-context
   models, Clef (16k) and most of Kev-4b (8k) fit.
3. Candidates are objects, groups of objects with one identical edit, and call paths between two components. Merge
   rules guarantee one option per changed thing, so one cause never splits its vote over several options.
4. Accept rule. Both asks put the same option first and its lead over the runner-up is larger, in both asks, than
   the model's own **order noise** (how far one option's probability moves when only the order changes). Order noise
   is measured per model without labels. On v2's existing request pairs it is 0.16 for Jev and 0.43 for Decisions,
   and picks that pass this rule were right (by the judge's D1) 49 of 55 times for Jev and 40 of 41 for Decisions.
   Otherwise code runs one read-only test that separates the top two and asks a two-option slate in both orders.
5. No fitted probability threshold is used anywhere. Lite labels set only discrete per-model switches (always
   confirm, widen on a weak winner) and report accuracy per route.
6. No question asks the model about one candidate on its own ("is X the origin?"), which is where Decisions says
   yes 16 of 26 times on wrong candidates. The design uses Choice questions only.
7. Characterization picks among code-computed facts of the chosen origin (each fact states its values), and code
   derives the two names (the changed thing and the broken thing) from the graph. The model is asked to choose the
   broken thing only when the changed thing acts on two or more failing components.
8. The worked examples (section 7) show the new states for update_incompatible_correlated, missing_env_variable,
   secret_rotation, search_rate_retry_collapse and service_dns_resolution_failure. In update_incompatible,
   missing_env and service_dns the right option is the only card with a field edit shortly before the symptoms it
   reaches. In secret_rotation the deciding fact is a peer comparison (two of three clients of the same account moved
   to the new password and work), with a live-config test as tie-break. search_rate_retry stays a near tie unless
   metrics or traces are available. I say so plainly rather than add a rule.

---

## 1. What the measurements require

Each row is a measured problem and the design answer to it.

| Measured problem (source) | Design answer (section) |
|---|---|
| v2 options carried code verdicts ("Checks ... (supports)"), 432 supports vs 56 contradicts, true cause ahead on checks in only 28 of 56 decisions (v2-audit 3) | Cards hold facts only, with a word lint (2.4). No "supports", "breaks", "victim", "origin" in any card |
| One cause split over many options. Six identical image bumps became four options plus two cut (forensics 2.1). Env shadowing split over three near-identical change options, "none" won (forensics 2.13) | One option per changed thing; identical edits on several objects become one group option (2.1) |
| v2's focused state hid the components its options did not name (forensics 2.1) | `symptoms` in the state always lists every failing component, whatever the options are (2.3) |
| Decisions confirms the candidate it is asked about. v1 verdict "origin" on 16 of 26 wrong candidates with Decisions, 13 of 39 with Jev (decision-models 2.6) | No per-candidate conclusion question. Candidates always compete on one slate (3) |
| v1 stopped at the first workload with origin >= 0.6. CoreDNS never compared (forensics 2.6, 2.12) | All candidate kinds, cluster objects included, sit on the same slate (2.1, 3) |
| Decisions rarely uses "none" when the right answer is missing (0.11 vs Jev 0.30) (decision-models 2.6) | "None" is offered but never trusted alone. Code guarantees one candidate per origin kind and widens once when "none" leads (2.1, 5.4) |
| Order flips 12.5% (Jev) and 20% (Decisions). Right 85-88% when two orders agree, 55-72% when not (decision-models 2.4) | Two asks, the second in reversed order. Act on agreement plus a lead larger than the model's own order noise (5) |
| Thresholds do not transfer across models. Jev 0.7+ was always right on v2 decide, Decisions needed ~0.9 (decision-models 2.3) | The accept margin is each model's own order noise, measured without labels (5.2) |
| Near ties decided runs. Jev 0.41 vs 0.36 (secret_rotation), 0.405 vs 0.395 (missing_env) (forensics 2.2, 2.7) | A near tie triggers a read-only test plus a two-option re-ask, not an average (5.3) |
| v2's go-back re-read what it had read (2 of 82 runs had a second round) (v2-audit 4) | Tie-break tests bring a new fact by construction (5.3) |
| Jev on OpenRouter goes into a slower, less accurate long-context mode above ~32 kB. v1 triage was always above it (decision-models 2.1) | Every request stays under ~16k characters (3.7) |
| Long, negation-heavy instructions (v1 triage ~9.5k characters of "unless", "only if") (decision-models 3.4) | At most three guidance lines per question, positive, one step each (3) |
| `fault_visible` was 1.0 in 160 of 160 asks (decision-models 2.6) | Dropped |
| Category labels cost D2-Q3 when wrong (edge Jev chose resource_limits, liveness chose code_bug) (forensics 2.5, 2.11) | No category label in the report. An optional mechanism phrase is reported only when stable (6.4) |
| The global onset came from an alert that predated every injected write (secret_rotation snapshot: onset 07:02:26, writes 07:02:49-56) | Timing is stated per candidate, relative to the first symptom that candidate can reach (2.2) |

---

## 2. Candidates, fact cards and the shared state

### 2.1 Candidate generation and merging (code, no model)

Code builds a typed graph first. Nodes are every object read (workloads, Services, ConfigMaps, Secrets, the cluster
DNS config, webhooks, policies, quotas, nodes, PVCs, Jobs, and topics or queues when a broker read names them).
Edges are `calls` (A depends on B), `reads` (env, envFrom, volume), `selects`, `resolves through`, `admits`,
`schedules`. Call edges come from env addresses, addresses in config file content, `host:port` tokens in log lines
(for example rate's log "Read database URL: mongodb-rate:27017") and, if available, trace spans.

A **candidate** is one of the following.

| Kind | Made when | Key (for merging) |
|---|---|---|
| object | it has a recorded write within the horizon, or own symptoms, or is named in another component's ongoing errors, or carries a cross-object finding | the object |
| group | two or more objects carry the same edit (same field path up to the container or object name, same changed token before and after, written within 60 s) | the edit |
| path | A has ongoing errors about calls to B, and B shows no own symptoms (or trace spans show errors on A to B) | (A, B) |
| input | a consumer repeats the same failure on the same item (a constant offset or key) and the source is named in its config or by a broker read | the source |

Merge rules, applied in order. They guarantee one option per changed thing.
1. All writes to one object form one candidate (fields are listed inside its card, not split into options).
2. Identical edits on several objects form one group candidate, and the members leave the pool.
3. A ConfigMap or Secret read by exactly one workload merges into that workload's candidate, which then carries both
   names (for example "Deployment product-catalog, reading Secret product-catalog-db-conn").
4. Two options never name the same object. A path names two objects but has its own key.
5. Kubernetes bookkeeping is not an edit. The `pod-template-hash` label is dropped, and a write whose only field is
   the `kubectl.kubernetes.io/restartedAt` annotation is shown as "restart only" in the card, never as an edit.

Recall guard (coverage). Origin kinds are workload or group, config object, cluster-level object, path, input. If the
pool holds a candidate of a kind that has a write or a cross-object finding, at least one candidate of that kind
reaches the slate (section 3.3). This is how the CoreDNS ConfigMap reaches the slate even when workloads crowd it.

Recall is measured separately from the pick (STRATEGY 3.7). The number to watch on the dev set is "the true origin is
one of the slate options", per fault.

### 2.2 The fact card

Every option of every deciding question is a JSON object with these keys, always all present, always in this order.
A missing fact is written "none found" (looked, found nothing) or "not available" (could not look). These are kept
apart because "no call edge found" and "nothing it depends on has trouble" mean different things.

| Key | What code puts there | How it is computed |
|---|---|---|
| `object` | kind, namespace and name; for a group, the member list; for a path, "calls from A to B" | graph |
| `writes` | each recorded edit with its values, before and after, or "restart only", "created after the app", "none recorded since deploy" | revision diffs (v1 `changes.py`, now also when managedFields hold nothing, fixing W3), managedFields writers, creation times; old values from the previous ReplicaSet or ControllerRevision |
| `write_timing` | "N s before the first symptom it can reach" or "N s after ..." | per-candidate local onset (earliest first symptom among the components in `reaches`), not the global onset |
| `own_symptoms` | its own failures with one quoted line each (crash loop and exit code, OOMKilled, not ready, own error lines that name no other component, Pending message), or "none found (N/N ready, 0 restarts, no own error lines)" | pods, events, log signatures; R1 classes when R1 runs |
| `first_symptom_rank` | "1st of 11 failing components" and, when relevant, "67 s after mongodb-rate's" | first warning event, first error line, first restart; ranks, not clock times |
| `reaches` | the failing components that depend on it, by edge kind, with a count ("6 of 11 failing components") | graph reachability over `calls`, `reads`, `selects`, `resolves through` |
| `named_in_errors_of` | components whose ongoing error lines name it, with count and one line, and whether the same line names other components | v1 `_mentions`, plus R1 "which component failed" when R1 runs |
| `depends_on` | what it depends on that has a write or own symptoms, and whether that trouble started earlier than its own | graph plus first-symptom times |
| `settings` | values of the settings that touch the failing behaviour (env values whose names contain a neighbour's name or one of LIMIT, TIMEOUT, RETRY, ATTEMPT, QUEUE, CAPACITY, BACKOFF; probe timing fields; ports; rules that name it) | spec read |
| `peers` | the same setting in other workloads that use the same target ("checkout has CART_ADDR=cart:8080"; "accounting and product-reviews log in as otelu with a connection string updated at 07:02:53-56") | spec read across workloads |
| `measurements` | before vs now rates, errors or latency for it or its path, if metrics or traces exist | Prometheus, Jaeger (stage 2); "not available" otherwise |

Each value is at most ~240 characters. Quoted log lines are cut with "…". A card is ~600-1,000 characters, a
compact screen card (object, writes, own_symptoms, reaches, depends_on only) ~300.

Why these fields. They are the features named in STRATEGY 3.4 (symptoms reached, onset order, changed or not, own
symptoms, explained by a parent), plus `settings` and `peers`, which carry the concrete values the judge's D2 asks
for and the "good value" that v1 never showed. `depends_on` is the "explained by a parent" feature, written as a
fact about a dependency and its timing, never as "victim".

### 2.3 The shared state

The state holds what every option needs and is the same for both asks.

```json
{
  "app": {"name": "Hotel Reservation", "namespace": "hotel-reservation", "workloads": 19,
          "failing_components": 11},
  "symptoms": [
    {"component": "Deployment mongodb-geo", "rank": 1, "what": "crash loop, exit code 62, 0 of 1 ready",
     "line": "\"msg\":\"Wrong mongod version\" … \"UPGRADE PROBLEM: Found an invalid featureCompatibilityVersion\""},
    {"component": "Deployment rate", "rank": 8, "what": "crash loop, exit code 2",
     "line": "panic: no reachable servers"}
  ],
  "timeline": [
    "1. edit: 6 Deployments mongodb-* image mongo:4.4.6 -> mongo:8.0.14-rc0",
    "2. first symptom: mongodb-geo BackOff (5 s after edit 1)",
    "3. first symptom: rate BackOff (67 s after mongodb-rate's)"
  ],
  "calls": ["rate -> mongodb-rate (rate log: Read database URL: mongodb-rate:27017)",
            "search -> rate (search env RATE_RPC_*; search error lines)"]
}
```

`symptoms` has one entry per failing component and class (cap 20, own failures first, then call errors, then
alerts). `timeline` is in time order, with differences written by code in seconds (the model is not asked to compare
times). `calls` lists only edges that touch a candidate or a failing component.

### 2.4 Neutral wording, enforced by a lint

Card text may contain facts, quoted lines and relation words (reads, calls, selects, resolves through, is named in,
started N s before or after). A unit test fails when card or option text contains any of these words: supports,
contradicts, breaks, caused, causes, because, victim, origin, root, explains, likely, broken, fault, culprit,
responsible, symptom-free. Question instructions may use "fault" and "injected"; option texts, including the fixed
"none" texts, may not. Cards must also be symmetric. The
test fails when two cards in one slate have different keys or key order. The same lint enforces the generality rule
(STRATEGY 3.7) on the code that writes cards, which must never contain an app, service or problem name.

---

## 3. Question flow

### 3.1 Overview

```
code: collect -> graph -> candidates -> merge -> cards
R1 read      (optional) classify unclassified or multi-name error lines            1 request, asked once
R2 screen    (only if > 6 candidates) wide slate of compact cards                    2 requests (order A, reverse A)
R3 origin    slate of 2-6 full cards + none                                         2 requests (order A, reverse A)
             -> stable: go to R5 | close or split: R4 | none leads twice: widen once, repeat R3
R4 pair      code runs one read-only test for the top two, then a 2-option slate    2 requests per round, max 2 rounds
             -> both orders agree: go to R5 | otherwise: fallback (5.4)
R5 describe  facts of the chosen origin (+ broken thing, + optional phrase)         2 requests (order A, reverse A)
code: report
```

The two asks of one question go out as two requests, as in all measured runs (the agreement numbers in
decision-models 2.4 come from separate requests). Putting both orders into one request as two question names would
save the state tokens once; whether answers stay independent there is a Lite check (8.1), not an assumption.

Option labels are neutral (`o1`..`oN`, `f1`..`fN`) and drawn fresh for every ask. Ask B uses the reverse of ask A's
order, so the first option becomes the last. Any further ask uses a seeded random order. The seed is recorded in the
run file.

### 3.2 R1 read (optional; stage 2)

Purpose. Turn raw error lines into two facts the cards need, whether the line is the component's own failure or a
failed call, and which named component the line says failed (fixes v1's relayed-name links, W8). It runs only for
ongoing error signatures that v1's patterns leave unclassified or that name more than one component. Cap 16 lines per
request.

State: `{"lines": {"L1": {"component": "frontend", "count": 54, "line": "⨯ Error: Could not parse target name \"\""}, ...}}`

Questions, per line (fixed meaningful labels, label order rotated by line index so a first-option lean averages out):

```json
"class_L1": {"type": "choice",
  "instructions": "Which kind of event does the log line in `lines.L1` report?",
  "criteria": {
    "call_failed":  "a call to another component failed, timed out or was refused",
    "name_lookup":  "a host or service name could not be resolved",
    "auth_denied":  "a login, password, token, certificate or permission was rejected",
    "bad_setting":  "a setting or argument of the logging component is missing, empty or invalid",
    "bad_input":    "a message, record or request could not be processed",
    "own_crash":    "the logging component crashed, panicked or ran out of a resource",
    "telemetry":    "traces, metrics or logs could not be exported",
    "other":        "something else"}}
"failed_L2": {"type": "choice",
  "instructions": "Which component does the log line in `lines.L2` report as failing?",
  "criteria": {"email": "email", "quote": "quote", "shipping": "shipping",
               "self": "frontend itself (the component that wrote the line)", "none": "no component is named as failing"}}
```

`failed_*` is asked only for lines that name at least one other component. Answers are used only to word the cards
(own symptom or call error; direct or relayed naming). The raw line is always quoted in the card too, so a wrong class
stays visible to the deciding question. Size ~6-10k characters. Skip R1 if the Lite A/B in 8.1 shows no gain.

### 3.3 R2 screen (only when more than 6 candidates survive merging)

Same question and instructions as R3 (3.4), with compact cards (`object`, `writes`, `own_symptoms`, `reaches`,
`depends_on`) and up to 24 options plus none. If more than 24 candidates exist, "silent" ones (no write, no own
symptoms, not named in errors, no finding) go to a reserve list first; if still more than 24, the pool is split at
random into two screens. Asked twice (order A, reverse A).

Shortlist rule (code). Rank by the summed probability of the two asks, keep the top 5, then apply the recall guard of
2.1, which may add one candidate of a missing origin kind, for at most 6. Everything else goes to the reserve list
used by "widen" (5.4). The screen is a wide ranking, used for top-k only, never top-1, because Decisions spreads
probability thinly and is overconfident at 0.7-0.9 on 20+ options (decision-models 2.2, 2.3).

### 3.4 R3 origin (the deciding slate)

Options: 2-6 full cards plus one "none" option, so 3-7 options. If only one candidate exists after merging, the next
candidate from the reserve list fills the second place, so the model always compares (a lone candidate plus "none" is
a yes/no in disguise, where Decisions' yes-bias shows). If the whole pool holds one candidate, nothing is asked and R5
runs on it.

```json
"origin": {
  "type": "choice",
  "instructions": {
    "question": "A fault was injected into this application while it was running normally. Which option is the place where the fault was injected?",
    "how_to_read": [
      "Each option is a fact card about one object, one group of objects that received the same edit, or the calls from one component to another.",
      "`writes` lists recorded edits to it. `write_timing` says when they happened compared with the first symptom it can reach. `own_symptoms` lists failures of its own. `reaches` lists failing components that depend on it. `depends_on` lists things it depends on that have trouble.",
      "`symptoms` lists every failure still occurring in the application, `timeline` lists edits and first symptoms in time order, and `calls` lists who calls whom."
    ],
    "guidance": [
      "An injected fault usually shows as an edit made shortly before the first symptoms that the edited object can reach.",
      "When a component's trouble started after trouble in something it depends on, the fault is usually in the thing it depends on.",
      "Choose the option that says none of the options describes the place when no card fits `symptoms`."
    ]
  },
  "criteria": {
    "o1": {"object": "...", "writes": "...", "write_timing": "...", "own_symptoms": "...", "first_symptom_rank": "...",
           "reaches": "...", "named_in_errors_of": "...", "depends_on": "...", "settings": "...", "peers": "...",
           "measurements": "..."},
    "o2": {"...": "..."},
    "o5": "None of these options describes the place."
  }
}
```

Notes on the wording.
- The guidance is two priors from v1's triage order (K7), cut to one step each and phrased positively. The rest of
  v1's six rules (victims, telemetry, "never on their own") became card facts or merge rules. Whether the guidance
  helps at all is the first A/B on Lite (8.1).
- The question asks for "the place where the fault was injected", which matches the judge's D1 ("the component where
  the fault originated") and fits objects, groups and paths alike.
- No "explains the most symptoms" wording. v2 used it, and it pulled the model toward wide victim chains
  (forensics 5.2, root cause 1).

Size. 6 cards x ~900 + instructions ~1,100 + state ~6,000 = ~12.5k characters per ask (~5.5k Jev tokens, ~3.7k
Decisions tokens).

### 3.5 R4 pair (tie-break; only when R3 is not stable)

Code first runs one read-only test chosen for the top two options (5.3) and writes its result into the state as a
neutral fact.

```json
"state": {"...": "same as R3",
  "test": {"checked": "From a pod of compose-post-service, look up the names of the Services it calls.",
           "result": "user-service.social-network.svc.cluster.local: NXDOMAIN. post-storage-service.social-network.svc.cluster.local: 10.96.41.7. media-service.social-network.svc.cluster.local: 10.96.118.3."}}
"pair": {
  "type": "choice",
  "instructions": {
    "question": "A fault was injected into this application while it was running normally. Which of these two is the place where the fault was injected?",
    "how_to_read": ["`test` holds the result of a read-only check that code ran to tell these two apart.",
                    "Each option is a fact card, as in `symptoms`, `timeline` and `calls`."]
  },
  "criteria": {"o1": {"card A": "..."}, "o2": {"card B": "..."}, "o3": "Neither of these two."}
}
```

Asked in both orders. Size ~9-10k characters per ask.

### 3.6 R5 describe (characterization of the chosen origin)

Details in section 6. One request holds up to three questions, and the request is asked twice with reversed option
orders. State: `{"origin": {<the chosen card>}, "symptoms": [<entries of the origin and of the components in its
reaches>], "timeline": [...], "test": {<R4 result, if any>}}`. States per request type, in short: R1 has `lines` only;
R2, R3 and R4 share `app`, `symptoms`, `timeline` and `calls` (R4 adds `test`); R5 is focused on the origin as above.

```json
"fact": {"type": "choice",
  "instructions": {"question": "The fault was injected into the object described in `origin`. Which option states what was injected?",
                   "how_to_read": ["Each option is one recorded fact about `origin`, with its values before and now.",
                                   "`symptoms` lists the failures that depend on `origin`."]},
  "criteria": {"f1": {"fact": "container image changed", "object": "6 Deployments mongodb-*",
                      "before": "mongo:4.4.6", "now": "mongo:8.0.14-rc0",
                      "seen_in_failures": "all 6 log \"Wrong mongod version\""},
               "f2": {"...": "..."},
               "f4": "None of these states what was injected."}}
"broken": {"type": "choice",
  "instructions": "The fault was injected into the object described in `origin`. Which component fails first because of it?",
  "criteria": {"b1": "Deployment product-catalog (reads Secret product-catalog-db-conn through env DB_CONNECTION_STRING)",
               "b2": "Deployment postgresql (receives logins from the clients of this Secret)"}}
"phrase": {"type": "choice",
  "instructions": "Which phrase describes how the fault in `origin` leads to the failures in `symptoms`?",
  "criteria": {"p1": "the new image fails to start with the existing data or settings",
               "p2": "a setting the component needs was removed or emptied",
               "p3": "...", "p6": "none of these phrases"}}
```

`broken` is asked only when the changed thing acts directly on two or more failing components (6.3). `phrase` is
optional (6.4). Size ~7-9k characters per ask.

### 3.7 Request budget

Characters estimated from mock requests built with the example cards of section 7 (a 6-card R3 with 11 symptoms
came to ~9.9k characters) and from v2's request files; tokens at 2.3 characters per Jev token and 3.4 per Decisions
token (decision-models 2.1).

| Request | When | Characters per ask | Jev tokens per ask | Asks |
|---|---|---|---|---|
| R1 read | optional | 6-10k | 2.6-4.3k | 1 |
| R2 screen | > 6 candidates | 12-15k | 5.2-6.5k | 2 |
| R3 origin | always (2+ candidates) | 10-13k | 4.3-5.7k | 2 |
| R3 widen | "none" leads in both asks | 10-13k | 4.3-5.7k | 2 |
| R4 pair | not stable | 8-10k | 3.5-4.3k | 2 per round, max 2 rounds |
| R5 describe | always | 7-9k | 3-3.9k | 2 |

Per diagnosis, typical (R1 + R3 + R5) ~20-24k Jev tokens. With a screen ~33k, which is v1's median of 32k
(v1-architecture 6). Worst case (screen, widen, two tie-break rounds) ~60k, below v1's long walks (80-88k). Every
single request is at most ~15k characters, about half of Jev's ~32 kB long-context line, and ~7k tokens with Jev's
tokenizer. So 32k-context models (Microsoft-Decision-1, d1-ultra) fit with room, Clef's 16k fits, and Kev-4b's 8k
fits every request except a full screen.

Trim order when a request would pass 15k characters. Shorten quoted lines to 120 characters, then set `peers` and
then `measurements` to "not shown" in every card, then cut `symptoms` to the components the options reach. The
cards' key set never changes (2.4).

### 3.8 What is not asked

- No `fault_visible` (never varied).
- No per-candidate "is X the origin, a victim or unrelated" (Decisions' yes-bias).
- No next-hop question. There is no walk; the slate already holds every kind of candidate.
- No 18-way category for the report (6.4).
- No Score question. It is untested here and `openrouter.py` cannot parse Score answers yet (decision-models 1).
  A per-candidate Score ("how much of `symptoms` does this card account for", 4 levels) is a later experiment.

---

## 4. Presenting candidates as neutral facts, and the measured failure modes

### 4.1 Before and after, one real option

v2's option for the OpenTelemetry collector in `tgt_missing_env_variable_astronomy_shop` (decide:1, Jev 0.405, which
beat the true cause at 0.395):

> Origin: daemonset/astronomy-shop/otel-collector-agent. daemonset/otel-collector-agent is broken, so
> deployment/email, deployment/frontend, ... which call it, fail. | ... | Checks: ... (supports)

The new card for the same object, from the same snapshot:

```json
{"object": "DaemonSet otel-collector-agent (telemetry collector)",
 "writes": "restart only (annotation kubectl.kubernetes.io/restartedAt added); no field value changed",
 "write_timing": "22 s before the first symptom in the application",
 "own_symptoms": "none found in its own pods (1/1 ready, 0 restarts); its log has metric-scrape errors: \"call to /stats/summary endpoint failed\"",
 "first_symptom_rank": "not among the failing application components",
 "reaches": "none found (no ongoing application error line names it)",
 "named_in_errors_of": "none found",
 "depends_on": "none found",
 "settings": "application pods export telemetry to it (OTEL_EXPORTER_OTLP_ENDPOINT)",
 "peers": "not available",
 "measurements": "not available"}
```

The old text asserted "is broken, so ... fail". The new card states what code saw, and the reader can see that
nothing in the application's errors touches it.

### 4.2 Order sensitivity

- Cards sit inside the options, so reversing the order moves all of a card's content, not just a label.
- Labels are neutral and redrawn per ask. Ask B is the reverse of ask A (maximum displacement for every option).
  Measured with neutral labels, the first position gained +0.001 (Jev) and +0.022 (Decisions) on average
  (decision-models 2.4), so reversal mainly exposes noise rather than a steady lean. The agreement check then catches it.
- The state never lists candidates in candidate order. `symptoms` is in time order and `calls` in name order, so the
  state carries no ranking by code.
- All cards have the same keys in the same order, with "none found" instead of a missing key (2.2, lint 2.4). v2's
  options had uneven detail (some with "Checks", some without), which is itself a signal the model can latch on to.

### 4.3 Decisions confirming whatever it is asked about

Every deciding question is a slate of at least two real candidates plus "none". There is no question about a single
candidate's conclusion, and no slate with one candidate plus "none" (3.4). Yes/no questions appear nowhere in the
deciding path. In R1 the text questions are choices over fixed kinds, about a log line, not about a candidate.

### 4.4 Near ties

The two-ask rule (5.1) treats a lead below the model's order noise as no decision. A near tie is never settled by
averaging, which measured only +1.6 points (Jev) and +0.5 (Decisions) over a single ask (decision-models 2.4). It is
settled by a new fact (a test) and a two-option re-ask, which is the easier question.

### 4.5 Vote splitting across near-duplicates

- Merge rules (2.1) make one option per changed thing. In the measured cases that removes all three splits:
  update_incompatible (six bumps into one group), env shadowing (three change options on frontend-proxy into one),
  secret_rotation (Secret and product-catalog "stale read" into one, which in Decisions' ask 2 had split
  0.09 + 0.25 against the ConfigMap's 0.38).
- Safety net. If two options ever share an object (a merge bug), code sums their probabilities by object before
  applying the accept rule, and logs a lint failure.
- Components named only inside one relayed line (email, quote and shipping in missing_env) stay separate. They are
  all wrong, so splitting among them only lowers the wrong side.

### 4.6 "None of these"

Offered in R2, R3 and R4. Never trusted alone, because Decisions put only 0.11 on it on average when the right answer
was missing (decision-models 2.6). Three supports around it.
1. Recall guard (2.1). Every origin kind with a write or a finding is represented on the slate.
2. Widen (5.4). If "none" is the stable top, the slate is rebuilt once from the reserve list.
3. Per-model switch `widen_on_weak_winner` (5.5), set from a Lite replay with the true candidate removed.

### 4.7 Options per question

| Question | Options | Labels |
|---|---|---|
| R1 class | 8 fixed kinds | meaningful, order rotated per line |
| R1 failed | named components + self + none (3-6) | component names |
| R2 screen | up to 24 + none | neutral, shuffled |
| R3 origin | 2-6 cards + none (3-7) | neutral, shuffled |
| R4 pair | 2 cards + neither (3) | neutral, both orders |
| R5 fact | 2-6 facts + none (3-7); skipped when only one fact exists | neutral, shuffled |
| R5 broken | 2-5 components | neutral, shuffled |
| R5 phrase | 3-6 phrases + none | neutral, shuffled |

---

## 5. Agreement rule, tie-break tests, abstaining, calibration

### 5.1 The rule

For each ask a of a deciding question, let top(a) be the option with the highest probability and lead(a) its margin
over the second. Let `noise_m` be model m's order noise for that question type (5.2).

| Route | Condition | Action |
|---|---|---|
| stable | top(A) = top(B), it is not "none", and lead(A) > noise_m and lead(B) > noise_m | accept, go to R5 |
| close | top(A) = top(B) but a lead is at most noise_m | R4 with the leader and the runner-up (highest summed probability among the rest) |
| split | top(A) differs from top(B) | R4 with the two tops |
| none | "none" is top in both asks | widen once (5.4) |
| pair agreed | in R4, both orders give the same option, and it is not "neither" | accept, go to R5 |
| pair not agreed | R4 orders disagree, or "neither" leads | second R4 round with a different test, if one applies; else fallback (5.4) |

Nothing in the table is a probability level. The only number is `noise_m`, which is measured per model without labels.

For R5 the same two-ask agreement applies with lighter consequences. A stable `fact` is reported as the mechanism.
If the two asks pick different facts, both are reported, the one with the higher summed probability first (both are
true facts about the same origin, so this costs nothing on D3). A `phrase` is reported only when stable. `broken`
uses the stable pick; if not stable, code names both components as broken.

### 5.2 Order noise, measured (fact, from existing runs)

`noise_m` is the 90th percentile, over a model's ask pairs, of the largest probability change of any one option
between the two orders. It needs no labels: only the same question asked in two orders. I measured it on the 80
first-round v2 decide pairs per model in `runs-index.tsv` (all v2 versions; 6-7 options each; same state, only order
and labels changed; script in the session scratchpad).

| | Jev 1.13 | Decisions |
|---|---|---|
| pairs / same top | 80 / 68 | 80 / 67 |
| one option's change between orders, median / p90 | 0.01 / 0.07 | 0.02 / 0.20 |
| largest change in a pair, median / p75 / p90 (= `noise_m`) | 0.05 / 0.10 / **0.16** | 0.16 / 0.27 / **0.43** |
| largest lead in either ask among pairs that flipped | at most 0.25 | up to 0.96 (6 of 13 flips had one ask with lead >= 0.5) |

So a Decisions answer can look sure in one order and flip in the other, which is why one ask is never enough and why
a single fixed level (v2's 0.6) means different things per model.

Rough check of the routes against outcomes. Using "the arm's judge D1 >= 0.67" as a stand-in for "the pick was right"
(it also fails right picks with the wrong framing, such as auth_miss), the routes on the same pairs come out as
follows.

| Route | Jev | Decisions |
|---|---|---|
| stable (same top, both leads > noise_m) | 49 of 55 | 40 of 41 |
| close | 10 of 12 | 18 of 25 |
| split | 7 of 12 | 7 of 13 |
| for comparison, v2's gate (same top and averaged leader >= 0.6) | 47 of 51 | 51 of 54 |

Reading (opinion). The label-free rule is about as precise as v2's gate for Jev and more precise for Decisions,
because it sends more of Decisions' answers to a confirmation step (25 close vs Jev's 12). R4 would run on 38 of 80
Decisions decisions and 24 of 80 Jev decisions. Each costs one test and two small requests, which is affordable, but it
also means R4's own accuracy matters a lot for Decisions and must be measured (5.5). The gate's 0.6 happened to suit both
models on v2's question; nothing says it suits a third model or a new question, while `noise_m` is re-measured for each.

`noise_m` for the new questions must be re-measured on the new cards (5.5); the numbers above only show the size of
the effect.

### 5.3 Tie-break tests

A test is read-only, generic (Kubernetes kinds and symptom classes only), and chosen by a lookup on the two cards.
Its result goes into the state as a fact (`test.checked`, `test.result`), worded without a conclusion.

| Top two | Test | What code reads | Example result fact |
|---|---|---|---|
| cluster DNS object vs a workload or Service | resolve | from a client pod, look up the Service names that client calls | "user-service.social-network.svc.cluster.local: NXDOMAIN; post-storage-service...: 10.96.41.7" |
| a workload vs something it calls | connect | from the caller's pod, TCP connect to the callee's address; the callee's ready endpoints | "connect to valkey-cart:6379 open; 1 ready endpoint" |
| a client vs a server or the server's config, with auth errors | auth | a login check with the client's running settings, one command per server technology (v1 `probes.py` already has redis, postgres, mongo, mysql) | "PING with cart's settings: NOAUTH Authentication required" |
| a workload reading an object at start vs the current object | live config | hash of the running container's env value vs hash of the object's current value (no values printed) | "running DB_CONNECTION_STRING differs from the current Secret value" |
| a call path vs its callee, timeouts, callee without own failures | rates | metrics or traces: calls per second on the path, the callee's handled rate and its limit setting, the caller's incoming rate, before and now | "search sends 31 calls/s to rate; rate handles 20/s; search receives 8 requests/s" |
| a consumer vs an input source | lag | consumer group offsets twice, 15 s apart | "partition 0 committed offset stays at 20 while the log end grows by 140" |
| two edits, or anything else | order | first symptom per pod at 1 s resolution, for the components each candidate reaches | "pods reading edit A failed 5 s after it; pods reading edit B show no failure" |

Example results are illustrative. If the test cannot run (exec not allowed, metrics missing), its result is "not
available" and R4 still runs, because a
two-option comparison is easier than a seven-option one (decision-models 3.8). Whether exec probes are allowed is
STRATEGY open question 2. Without exec, only resolve-by-proxy, connect-by-endpoints, rates (if metrics exist) and
order remain.

### 5.4 None, widen, fallback (abstaining)

- **Widen.** When "none" is the top in both R3 asks, code rebuilds the slate from the reserve list in screen order,
  keeps at most two current options (highest summed probability), applies the recall guard, and asks R3 once more.
- **Weak winner.** For a model whose switch `widen_on_weak_winner` is on (5.5), a stable winner whose card has no
  write, no own symptoms and only `named_in_errors_of` also triggers one widen. This targets Decisions' habit of
  picking confidently when the right answer is missing.
- **Fallback.** After a second "none", or two R4 rounds without agreement, code picks the option with the most first
  places over all asks in this diagnosis, ties broken by summed probability, never "none". The benchmark always needs a
  diagnosis, so abstaining here means "the model's answer is not trusted, code's count of the model's answers
  decides", not "submit nothing". The report reads like any other. It has no "low confidence" or "budget ended" line
  (v2's line was false, v2-audit 4), and the runner-up appears only among abnormal components, never as a cause
  (D3-Q1). The run file records `route=fallback`.
- **Stop.** At most 12 requests and 120 s of wall time per diagnosis. Neither bound was reached by v2 (max 6 requests).

### 5.5 Per-model calibration on Lite, without thresholds that do not transfer

Dev data. Lite (17), plus the studied sample A (10) and set T (2) for development only. Never Unseen. Snapshots are
saved, so R1-R3 and R5 can be replayed offline per model with no cluster (tests cannot be replayed).

| Measured per model | Labels needed | Used for |
|---|---|---|
| `noise_m` per question type, from 4 orders per dev state | no | the accept margin (5.1) |
| flip rate of picks whose lead exceeds `noise_m`, over the 4 orders | no | check that the margin works (target: under 5% flips) |
| accuracy per route (stable, close, split, pair, fallback) | yes (problem files) | the switch `confirm_all`: on if stable accuracy is under 90%, then every R3 decision also gets R4 |
| missing-answer replay: true candidate removed, how often "none" is the stable top | yes | the switch `widen_on_weak_winner`: on if under half |
| duplicate replay: a reworded copy of the true card added, how often the pick splits | yes | a check of the merge rules, not a switch |
| screen recall: true candidate in the R2 top 5 | yes | a check of R2, not a switch |

What is never set per model: a probability level, a weight per question, a different question wording, or anything
per app. With 17-29 labelled faults, discrete switches are all the data supports; curves would fit noise.

Replays multiply the labelled asks cheaply (each request costs ~$0.0003-0.0005). For 29 dev faults, 3 variants
(normal, missing, duplicate) and 4 orders, that is ~350 asks per model, about $0.15 per model.

### 5.6 Optional, if the rules allow two models in one run

If the team decides a run may call two decision models (decision-models 4, point 6), the second model's answer
replaces ask B. Jev and Decisions agreed on 33 v2 decide picks and 32 were right. This is not part of the default
design, because the brief says the pipeline must work with each model, not with both at once.

---

## 6. Characterization (R5): mechanism fact, concrete values, two names

The judge's D2 asks for the injected mechanism, the concrete mutated values, and no wrong fault type. D1 matches
whichever object the ground truth names, which is sometimes the changed object (CoreDNS ConfigMap) and sometimes the
broken component (product-catalog, the MongoDB service). So R5 produces a mechanism fact with its values, and two
names. The model chooses among facts code computed; code writes every word of the report.

### 6.1 The facts offered (code)

For the chosen origin, code lists facts in this order and offers at most six, plus "none of these".
1. **Edits.** One per changed field (for a group, one per distinct edit), with `before` and `now`. A removal shows
   the previous value from the older ReplicaSet or ControllerRevision ("CART_ADDR: before cart:8080, now not set").
   Probe edits carry every timing field (initialDelaySeconds, periodSeconds, failureThreshold, timeoutSeconds) and
   terminationGracePeriodSeconds, which v1 drops (W5).
2. **Cross-object findings** that involve the origin, with values (selector vs labels, targetPort vs container ports,
   env read at start vs object rewritten later, a DNS rule naming its Service, quota or webhook rejections, RWO claim
   vs replicas, hostPort clashes).
3. **Settings** from the card's `settings`, each as its own fact with its value.
4. **Test results** from R4, if one ran ("PING with cart's settings: NOAUTH").
5. **Measurements**, if any.
6. **Behaviour.** The origin's own top error signature with its count. Last, and the only kind available when
   nothing else is.

Each fact has a `seen_in_failures` value that code computes by string matching only. It says whether the fact's
name or value (or an empty value where the old value used to be) appears in symptom lines, and quotes one, or says
"not seen in any symptom line". Example: "frontend logs an empty target name \"\" (54 lines), starting 32 s after
the edit".

If more than six facts exist, edits and findings go first, then facts that are seen in failures. If only one fact
exists, `fact` is not asked.

### 6.2 Concrete values

Taken by code from the chosen fact (`before`, `now`) and from `peers` when available ("checkout still has
CART_ADDR=cart:8080"). For a path, every setting on both ends is listed with its value. For runtime state, the test
output is quoted. Secret values are never read or printed; a test compares hashes (5.3).

### 6.3 The two names

- **Changed thing.** The object of the chosen fact. For a group, every member. For a path or any origin with no
  recorded write, "no recorded edit; the setting has been in place since deploy" (or the server object a test showed
  to be in a changed runtime state).
- **Broken thing.** The components that use the changed thing directly (`reads`, `selects`, `resolves through`,
  `calls`) and have own symptoms or call errors. If there is exactly one, code names it. If there are two or more,
  R5 asks `broken` (3.6). If there are none, the origin itself.
- **Which name leads the report.** A Kubernetes ownership rule, not fault knowledge. If the changed thing belongs to
  exactly one workload (its own spec, or a ConfigMap or Secret only it reads), the report leads with that workload and
  names the object in the same sentence. If the changed thing is shared or cluster-level (cluster DNS, a webhook, a
  quota, a NetworkPolicy, a Service that clients select through, a node), the report leads with that object, acting on
  the broken thing. A group leads with all its members; a path with "the call path A -> B". When a workload has a
  Service of the same name, both kinds are named ("Deployment and Service url-shorten-mongodb").
- Evidence for the rule. auth_miss (a ConfigMap read only by url-shorten-mongodb; v1 led with the workload and passed,
  v2 led with the ConfigMap and failed D1). service_dns (CoreDNS is cluster-level; v2 led with it and passed, v1 led
  with the workload and failed). internal_traffic_policy (a Service; v1 led with the Deployment and lost D1-Q3).
  secret_rotation (a Secret read only by product-catalog; leading with product-catalog matches the ground truth).

### 6.4 Optional mechanism phrase

A short fixed vocabulary of generic mechanism phrases, filtered by the kind of the chosen origin and its facts, 3-6
phrases plus "none". If the origin's kind yields fewer than three phrases, the phrases of the kinds of its other facts
are added; if there are still fewer than three, the phrase is neither asked nor reported. Reported only when stable
across both asks; otherwise omitted. No category label (such as
"config_value") is ever printed, because a wrong label costs D2-Q3 and the fact already carries the mechanism.

| Origin and fact kind | Phrases offered |
|---|---|
| image edit | the new image fails to start with the existing data or settings; the new image cannot be pulled; the new image crashes at start whatever the settings |
| env, args or config content edit | a setting the component needs was removed or emptied; a setting now has a wrong value; the same setting is defined twice and the wrong one wins |
| resources edit | a limit is too low for the work; a request is too large to schedule |
| probe edit | a health probe is too strict, so healthy containers are restarted or marked not ready; a probe checks the wrong port, path or command |
| Service, selector, port | traffic goes to the wrong pods or port, or to none |
| DNS or network policy | lookups of a Service name fail; traffic to a component is blocked |
| object read at start | a component still runs with an old value it read at start |
| path, timeouts, no edit | retries after timeouts keep the callee above its capacity; the callee's capacity limit is below the normal load; the caller's deadline is shorter than the callee's normal response time |
| server object after an auth test | the server's running settings no longer match what clients send |
| input source | one input item fails again and again and blocks the items behind it |
| object created after the app | a new workload uses up memory, CPU or connections of a component |

### 6.5 Scope

Affected components are the failing components in the origin's `reaches`, listed as affected, never as causes. A
group names every member as the cause (D3-Q2 for update_incompatible, where v1 named one of six and lost 11 points).

---

## 7. Worked examples (non-sealed faults, real snapshots)

All facts below are read from the run's `*_snapshot.json` or request files. "Expected" lines are my opinion about how
the models would answer; nothing was run. Run labels are from `runs-index.tsv`.

### 7.1 update_incompatible_correlated (`tgt_update_incompatible_correlated`)

What happened. Six MongoDB Deployments had their image bumped mongo:4.4.6 -> mongo:8.0.14-rc0 at 07:58:38-40 and
crash with exit code 62 ("Wrong mongod version"). rate crashes too ("panic: no reachable servers"); search logs
"downstream request failed dependency=rate". v2 offered four of the six bumps as separate options plus a "rate fails
its callers" option and a retry interaction; in its first ask Jev put 0.44 on rate and 0.08 + 0.26 + 0.01 + 0.01 on
four bumps (scores 0 and 11). v1 found mongodb-geo (89 and 89) but named one of six and lost D3-Q2.

Candidates after merging (6, so no screen). R3 has 6 cards plus none, ~12k characters per ask.

```json
"o?": {"object": "6 Deployments that received the same edit: mongodb-geo, mongodb-profile, mongodb-rate, mongodb-recommendation, mongodb-reservation, mongodb-user",
       "writes": "container image mongo:4.4.6 -> mongo:8.0.14-rc0 on all 6 (written within 2 s of each other)",
       "write_timing": "5 s before the first symptom it can reach",
       "own_symptoms": "all 6 in crash loop, exit code 62, 0 of 1 ready; logs \"Wrong mongod version\" … \"UPGRADE PROBLEM: Found an invalid featureCompatibilityVersion\"",
       "first_symptom_rank": "1st to 6th of 11 failing components",
       "reaches": "rate (rate's log names mongodb-rate:27017) and, through rate, search; no call edge found to profile, reservation or frontend",
       "named_in_errors_of": "none found",
       "depends_on": "none found",
       "settings": "args --auth (unchanged)", "peers": "not available", "measurements": "not available"}
"o?": {"object": "Deployment rate",
       "writes": "none recorded since deploy",
       "write_timing": "none recorded",
       "own_symptoms": "crash loop, exit code 2; last log lines \"Read database URL: mongodb-rate:27017\", \"panic: no reachable servers\"",
       "first_symptom_rank": "8th of 11 failing components, 67 s after mongodb-rate's first symptom",
       "reaches": "search (148 error lines)",
       "named_in_errors_of": "search: \"downstream request failed dependency=rate grpc_code=Unavailable\" (148 lines, still occurring)",
       "depends_on": "mongodb-rate (address in rate's own log): edited 126 s ago, crash loop since 67 s before rate's first symptom",
       "settings": "RATE_BACKEND_QPS_LIMIT=500, RATE_QUEUE_CAPACITY=256", "peers": "not available", "measurements": "not available"}
```

The other four cards (search, profile, reservation, frontend) all read "writes: none recorded since deploy", with own
lines that are call failures ("no reachable servers", "downstream request failed") or panics, and later first-symptom
ranks. profile's card says "depends_on: no call edge found; its error 'no reachable servers' names no host", which is
honest about a missing edge.

Why the right option wins. It is the only card with a write, the write precedes the first symptom by 5 s, its own logs
show a fatal version error, and every other failing card either depends on it or has no edit and later symptoms. The
three v2 failure causes are gone by construction: no vote split (one group card), nothing cut (the group is one
option, and `symptoms` lists all 11 failing components), and the rate-to-mongodb-rate link exists because the address
in rate's log becomes a call edge. Expected route: stable for both models (v1's per-component asks on the same
evidence gave origin 1.0 and 0.89).

R5. Facts offered: f1 image mongo:4.4.6 -> mongo:8.0.14-rc0 on all 6 (`seen_in_failures`: all 6 log "Wrong mongod
version"); f2 spec.replicas rewritten in the same edit (now 1); f3 behaviour, exit 62 after "UPGRADE PROBLEM: Found
an invalid featureCompatibilityVersion"; plus none. Changed thing = broken thing = the six Deployments, so `broken`
is not asked. Phrase options are the three image phrases plus none. Report: "Root cause: Deployments mongodb-geo,
mongodb-profile, mongodb-rate, mongodb-recommendation, mongodb-reservation and mongodb-user (hotel-reservation)
had their container image changed from mongo:4.4.6 to mongo:8.0.14-rc0, 5 s before the first symptom. Each now exits
with code 62 and logs 'Wrong mongod version' ... Affected: rate (crash loop, 'no reachable servers'), profile,
reservation, search, frontend." All six named, so D3-Q2 is met.

### 7.2 missing_env_variable_astronomy_shop (`tgt_missing_env_variable_astronomy_shop`)

What happened. Revision 2 of frontend (07:37:18) removed env CART_ADDR; nothing in managedFields recorded it, so v1
made no change record (W3). frontend logs 'Error: Could not parse target name ""' (54 lines) and a relayed line
naming shipping, quote and email. The harness restarted the otel collector at 07:37:04. v2 Jev: otel 0.405 vs the
true change 0.395 (11 points). v1 Jev walked email, frontend (called a victim at 0.82), shipping, quote, otel,
checkout and fell back to email (22). The Decisions arms passed (89, 100).

Candidates (6, no screen): frontend, otel-collector-agent, email, quote, shipping, and the path frontend -> shipping
(frontend has SHIPPING_ADDR, its errors name shipping, shipping has no own symptoms). Key card facts:

| Card | writes | own_symptoms | named_in_errors_of / depends_on |
|---|---|---|---|
| Deployment frontend | env CART_ADDR removed in revision 2, before cart:8080, now not set; 8 s before the first symptom | 'Could not parse target name ""' (54 lines, names no other component); 1/1 ready | depends_on email, quote, shipping (named in its line '... failed POST to email service: expected 200, got 400'), none of which shows own symptoms. peers: checkout has CART_ADDR=cart:8080 |
| DaemonSet otel-collector-agent | restart only, 22 s before | metric-scrape errors in its own log | reaches none found (no application error line names it) |
| Deployment email / quote / shipping (3 cards) | none recorded | none found (1/1 ready, 0 restarts, no own error lines) | named only inside frontend's relayed line (13 lines), which also names the other two |
| path frontend -> shipping | none recorded | callee has none found | errors on this path, the same relayed line |

Why the right option wins. frontend is the only card with a field edit, the edit removes an address and its own
errors quote an empty target name, and everything it depends on shows no trouble of its own, so the second guidance
line does not point away from it. otel's card no longer claims impact on five components; it says no application
error names it. Expected route: stable for both. If Jev still splits frontend and otel, the pair test is "connect"
(from frontend's pod to the collector's OTLP port, plus the collector's ready endpoints), which comes back open and
ready, and R4 asks the two cards in both orders.

R5. Facts: f1 env CART_ADDR removed (before cart:8080, now not set; `seen_in_failures`: frontend logs an empty
target name "" from 32 s after the edit); f2 behaviour 'Could not parse target name ""' (54 lines); plus none.
Changed thing and broken thing are both Deployment frontend (its own spec). Report: "Root cause: Deployment frontend
(astronomy-shop). Its env var CART_ADDR was removed in revision 2 (it was cart:8080, the address of Service cart;
checkout still has it), 8 s before the first symptom. Since then frontend logs 'Could not parse target name \"\"'
(54 lines) ..."

### 7.3 secret_rotation_stale_env_credentials_astronomy_shop (`lite6_...`)

What happened. Secret product-catalog-db-conn was created at 07:02:49 and rewritten at 07:02:52; product-catalog's
container started at 07:02:49 and reads it through env DB_CONNECTION_STRING. accounting and product-reviews got the
new password otelp_7k9m2q4x in their env at 07:02:53-56 and restarted. ConfigMap postgresql-init was rewritten at
07:02:53. postgresql rejects logins for otelu from 07:04:15. The snapshot's global onset is an alert at 07:02:26,
earlier than every injected write, so v1's facts read "22 s after the first active symptom" for the true Secret
while the harness's otel restart read "14 s before". v2: ConfigMap 0.41 vs stale read 0.36 (Jev, 11 points),
ConfigMap 0.555 (Decisions, 45); in Decisions' ask 2 the Secret and the stale-read options split 0.09 + 0.25 against
the ConfigMap's 0.38. v1 Jev 100; v1 Decisions 34 (origin 0.49 just under 0.6, then postgresql).

Candidates after merging (6): product-catalog with its Secret (merge rule 3), postgresql with its ConfigMap
postgresql-init (merge rule 3), the group accounting + product-reviews (same token edit otelp -> otelp_7k9m2q4x in
DB_CONNECTION_STRING), otel-collector-agent (restart only), frontend, recommendation.

| Card | writes and timing | own_symptoms | peers / depends_on |
|---|---|---|---|
| Deployment product-catalog, reading Secret product-catalog-db-conn | Secret created 07:02:49, rewritten 07:02:52, 3 s after the container started; env is fixed at container start, so the running container holds the value from before the rewrite; 83 s before postgresql began rejecting account otelu | none found in its own logs; 1/1 ready | peers: postgresql (the only database) rejects logins for account otelu; accounting and product-reviews log in as otelu with a connection string updated at 07:02:53-56, started after it, and log no errors |
| Deployment postgresql, reading ConfigMap postgresql-init | init.sql rewritten 07:02:53, 104 s after the container started; mounted as files, which the process sees only if it re-reads them; 82 s before its first symptom | 'FATAL: password authentication failed for user "otelu"' (19 lines) | the rejected account comes from clients: accounting, product-reviews, product-catalog |
| group accounting + product-reviews | DB_CONNECTION_STRING password otelp -> otelp_7k9m2q4x; pods started after the edit | none found | reaches none found |
| frontend, recommendation (2 cards) | none recorded | 'failed to query products: pq: password authentication failed for user "otelu"' (relayed, names no component) | depends_on product-catalog (PRODUCT_CATALOG_ADDR) |

Why the right option should win. Timing is now per candidate (82-83 s before the rejections), so
the alert that predates the injection no longer favours the otel restart. The deciding fact is in `peers`: two of the
three clients of the rejected account moved to the new value and work, and the third runs with a value fixed before
its Secret was rewritten. Expected route (opinion): stable for Jev, perhaps close or split for Decisions, which
preferred the server side twice before. Tie-break test for product-catalog vs postgresql: "live config" (hash of
product-catalog's running DB_CONNECTION_STRING vs the Secret's current value: differ) and "auth" (login as otelu with
the Secret's current value: accepted). Both results go into `test`, and R4 asks the pair in both orders. Without exec
the test is "not available" and the pair is decided on the cards alone.

R5. Facts: f1 Secret rewritten 3 s after product-catalog's container started, read through env; f2 accounting and
product-reviews now use password otelp_7k9m2q4x; f3 the live-config result if run; plus none. Changed thing = Secret
product-catalog-db-conn; broken thing = Deployment product-catalog (its only reader, so `broken` is not asked). The
Secret belongs to one workload, so the report leads with product-catalog, which is the ground truth.

### 7.4 search_rate_retry_collapse_hotel_reservation (`lite5_...`)

What happened. Nothing was edited. rate was deployed with RATE_BACKEND_QPS_LIMIT=20 (the app's normal is 500, as the
update_incompatible snapshot shows) and search with RATE_RPC_TIMEOUT_MS=750 and RATE_RPC_MAX_ATTEMPTS=3. A traffic
burst started a retry loop. search logs "downstream request failed dependency=rate grpc_code=DeadlineExceeded" (65
lines); rate shows no failure of its own. The ground truth is "search-to-rate RPC path". v1 named rate (34, 34). v2's
hand-written amplify pattern named the interaction (89, 89).

Candidates (3, no screen): rate, search, and the path search -> rate (made by the generic path rule: caller errors on
calls to a callee without own symptoms; no retry story attached).

| Card | own_symptoms | named_in_errors_of | settings |
|---|---|---|---|
| Deployment rate | none found (1/1 ready, 0 restarts, no own error lines) | search, DeadlineExceeded (65 lines, still occurring) | RATE_BACKEND_QPS_LIMIT=20, RATE_QUEUE_CAPACITY=256 |
| Deployment search | error lines about calls to rate only | none found | RATE_RPC_TIMEOUT_MS=750, RATE_RPC_MAX_ATTEMPTS=3, RATE_RPC_INITIAL_BACKOFF_MS=50, RATE_RPC_BACKOFF_MULTIPLIER=2.0, RATE_RPC_JITTER=0.2 |
| path search -> rate | callee none found; caller's calls end in DeadlineExceeded | (same 65 lines) | both sets above |

All three say "writes: none recorded since deploy". `peers` is "not available" for both settings in this run, since no
other workload sets them.

Honest expectation. Without metrics this is a near tie between rate (the limit) and the path (limit plus retries),
which is exactly the fault's own trap ("a diagnosis that only calls the static rate limit too low ... is incomplete").
Expected route: close or split. The tie-break test is "rates": if Prometheus or Jaeger is available during diagnosis
(STRATEGY open question 1), the path card gains `measurements` such as (illustrative numbers, not measured)
"search receives 8 requests/s; search sends ~27 calls/s to rate; rate completes 20/s", and calls per incoming
request well above 1 is a plain fact pointing at the retries. Then R4 should pick the path. Without metrics, R4 has no new fact and the result is a coin flip; I would
rather report this honestly than write a retry rule. This example is the clearest case for STRATEGY item 3 (metrics
and traces).

R5 for the path. Facts: f1 search retries up to 3 attempts with a 750 ms deadline and 50 ms backoff doubling; f2 rate
caps work at 20 per second with a 256-entry queue; f3 calls on this path end in DeadlineExceeded while rate shows no
failure; f4 the rates measurement if available. Phrase options are the three path phrases plus none. Changed thing:
"no recorded edit; settings in place since deploy". Broken thing: the call path search -> rate. Report leads with
"the search -> rate RPC call path" and lists every setting on both ends with its value, which is what earned v2's 89.

### 7.5 service_dns_resolution_failure_social_network (`lite6_...`), with the astronomy variant

What happened. At 05:43:28 the CoreDNS ConfigMap got a rule answering NXDOMAIN for
user-service.social-network.svc.cluster.local. 120 s later compose-post-service logs "getaddrinfo() <Host:
user-service Port: 9090> Temporary failure in name resolution" (52 lines) and nginx-thrift "Could not resolve host".
Ground truth is configmap/coredns in kube-system. v1 Decisions asked about user-service on its own and got origin
0.99, stopped, and scored 67; v1 Jev's 0.45 happened to fall under 0.6 and reached the cluster node (89). v2 named the
ConfigMap (100, 100).

Candidates (5, no screen): ConfigMap kube-system/coredns (a write and a finding), user-service, the path
compose-post-service -> user-service, compose-post-service, nginx-thrift.

| Card | writes and timing | own_symptoms | reaches / depends_on |
|---|---|---|---|
| ConfigMap kube-system/coredns (cluster DNS) | data.Corefile written 120 s before the first symptom it can reach; now holds 'template ANY ANY user-service.social-network.svc.cluster.local { match ... rcode NXDOMAIN fallthrough }'; previous content not available | CoreDNS pods 2/2 ready | reaches every client resolving user-service: compose-post-service (name lookup failures, 27 lines), nginx-thrift through it |
| Deployment user-service | none recorded | none ongoing (its own error lines are warm-up lines that stopped) | depends_on (acted on by): the rule in ConfigMap kube-system/coredns answers NXDOMAIN for its Service name, written 120 s before the first symptom |
| path compose-post-service -> user-service | none recorded | callee none ongoing | errors on the path: name lookup failures (27), connection failures (25) |
| compose-post-service, nginx-thrift | none recorded | name lookup failures; OTLP export errors classed as telemetry | depends_on user-service (name lookup fails) |

Why the right option wins. The ConfigMap is the only card with a write, its rule names the exact Service whose lookups
fail, and user-service's own card states that the rule acts on it. The v1 Decisions failure (a yes to a lone question
about user-service) cannot happen, because user-service only ever appears beside the ConfigMap on one slate. Expected
route: stable for both. If not, the pair test is "resolve" (from a compose-post-service pod: user-service ->
NXDOMAIN, the other Services it calls -> addresses).

R5. Facts: f1 the NXDOMAIN rule for user-service.social-network.svc.cluster.local in data.Corefile; f2 behaviour of
the clients ('Temporary failure in name resolution', 52 lines); plus none. Changed thing: ConfigMap
kube-system/coredns, which is cluster-level, so it leads the report. Broken thing: name resolution of Service
social-network/user-service for compose-post-service and nginx-thrift.

Astronomy variant (`held4_service_dns_resolution_failure_astronomy_shop`). Here the rule targets
frontend.astronomy-shop and the only ongoing symptom is the alert ServiceEndpointDown on frontend (frontend's own
error lines had stopped). The ConfigMap card reads "written 37 s before the first symptom it can reach", and the only
other write is the otel restart ("restart only, 51 s before; no application error names it"). v2 accepted the
ConfigMap at 0.915 / 0.875 with the old option text; the new card carries the same facts without the verdict words.

Trap variant (leftover CoreDNS rule from an earlier problem, as in `held5_liveness_probe_too_aggressive_social_network`
v1 Decisions, score 0). In that snapshot the Corefile was written 3,478 s before collection and holds no rule naming
any Service. The ConfigMap's card would read "data.Corefile written 3,350 s before the first symptom; it holds no rule
naming an application Service ... reaches none found (no ongoing error line reports a name lookup failure)". The first
guidance line asks for an edit shortly before the symptoms it can reach, and this card states that it reaches nothing.
aux-service has no recorded edit either, but its card now carries the probe timing values that v1 dropped
(periodSeconds 1, failureThreshold 1, terminationGracePeriodSeconds 0; 6.1) next to its restarts.

---

## 8. Checks before adopting, risks, and what it implies for code

### 8.1 Pre-registered checks on the dev set

Each runs on at least three models (Jev 1.13, Decisions, plus Jev 1.14 or Perplexity Decider), mostly as offline
replays of saved dev snapshots, so the unit is the decision (hundreds per model), not 17 pass/fail runs. A variant is
kept only if it is no worse on any model and better on at least one.
1. Guidance lines on vs off in R3.
2. Cards inside the options (default) vs cards in the state with short option pointers.
3. Both orders as two question names in one request vs two requests. If flip rates and accuracy match, use one
   request, which saves the state tokens once (about a third of R3's tokens).
4. R1 on vs off.
5. `peers` and `settings` on vs off. They are the fields most likely to act as distractors (TypeSafe's warning about
   unrelated detail).
6. `phrase` on vs off, judged by D2 on Lite.
7. Margin check. With 4 orders per state, picks whose lead exceeds `noise_m` should flip under 5% of the time.

Two recall numbers are reported next to accuracy. "The true origin is on the R3 slate" and "the mutated value appears
on some card or fact".

### 8.2 Risks and open points

- **Recall is the ceiling.** The model can only pick what code offers. A call address that appears nowhere in env,
  config or logs leaves `depends_on` and `reaches` as "no call edge found". Traces would close most of these gaps.
- **Code still chooses which facts reach a card.** The field rules are generic and the same for every card, but
  `settings` uses a small word list (LIMIT, TIMEOUT, RETRY, ...) and can miss a value that lives in a config file.
  The second recall number above measures this.
- **Merge rule 3 puts a ConfigMap or Secret behind its only reader.** The report still names the object in the lead
  sentence, but if a ground truth targets the config object itself, D1 may depend on which name leads. auth_miss is the
  measured case in the other direction. Check on dev faults whose target is a config object.
- **The first guidance line favours edits.** Harness writes (restarts, objects left by an earlier problem) can look
  like edits. "Restart only" wording and per-candidate timing reduce this; they do not remove it.
- **Tie-break tests need exec and telemetry** (STRATEGY open questions 1 and 2). Without them R4 is a two-option
  re-ask with no new fact, which helps against order noise only. search_rate_retry is the case where this decides
  pass or fail.
- **Two-ended faults** (a load source and its victim, as in valkey_memory_disruption) need an edge from source to
  victim. When the link hides in a base64 command, no card can show it; memory or connection metrics on the victim
  are the generic fix.
- **Other models and JSON options.** v1 sent object-valued options to Jev and Decisions without trouble; Jev 1.14,
  Perplexity and Liquid need a smoke test.
- **Sample size.** About 120 order pairs per model per question type give `noise_m` to within a few hundredths; the
  per-model switches rest on 17-29 labelled faults plus replays and should be read as coarse.

### 8.3 What this implies for code (no more than was decided)

- A card builder over v1's facts (collector, change detection, checks stay as they are, with the W3 and W5 fixes).
- One ask module (two orders, routes of 5.1, widen, fallback) that replaces v1's walk and v2's decide.
- A test catalog that reuses v1's `probes.py` commands.
- The word and symmetry lint of 2.4, as a unit test.
- Only Choice questions, so `clients/jev_diag/openrouter.py` needs no change.

---

Status: DONE (2026-10-19).
