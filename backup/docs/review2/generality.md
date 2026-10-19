# v2 generality and leakage review

Reviewed commit **85af8577** on `feat/jev-diag-v2`. The branch moved twice while I worked (dca2e34b, 85af8577), so every
result below was re-run on a read-only export of 85af8577. Uncommitted edits seen in the working tree around 16:45 are
covered in a short addendum at the end. I did not edit the repo, call a paid model, touch a live cluster, or open any
sealed or unseen file.

## Bottom line

- **No leakage found.** v2 reads only the cluster (kubectl), SREGym's MCP observability servers and the conductor's
  normal agent API. No ground truth, problem id or harness internals reach the diagnosis.
- **One rule is in effect tuned to a single dev fault.** The "feedback loop" call path (H2) judges setting names only,
  and every hotel-reservation deployment already carries those names. On other faults it replaces the model's answer in
  the report with the call path and an unmeasured claim. This is the one thing to fix before the held-out run.
- **The name-blind test passes on the code side.** On 7 dev recordings from 3 apps, renaming every app-specific name
  left the model's input, the call paths, the same-change groups and the code-built reports identical up to name order.
  One real name effect showed up (a tie-break), plus list order.

## How I checked

- Read the whole v2 diff (`065032a6..85af8577`; 065032a6 is a faithful copy of v1, I diffed it file by file).
- Replayed collection offline on all 29 dev recordings (`collect_snapshot` over the stored kubectl bundles) and looked
  at which v2 rules fire where.
- Built misfire cases two ways. "Transplant" means a real dev snapshot plus the log lines a different fault would cause.
  "Synthetic" means small hand-made components run through the real code (`derive.post_process`, `paths.call_paths`,
  `report.build_report`).
- Ran a name-blind test (method and result below).

## Findings, most severe first

### 1. HIGH. The "feedback loop" call path is a detector for one dev fault, and it overrides the model's answer

**Where.** `paths.py:17-22` (name patterns), `:51-63` (`_towards`), `:101-105` (`feedback_loop`), `:130-134` (the
"multiplies" sentence). `report.py:118-127` (`feedback_path`), `:152-154` and `:193-195` (the path becomes the subject
and the root-cause text).

**Why it is specific.** The rule looks only at setting names, never at values or measurements. In this SREGym version
every hotel-reservation deployment already has those names. In all 10 hotel recordings, `search` has
`RATE_RPC_TIMEOUT_MS=1000, RATE_RPC_MAX_ATTEMPTS=2` and `rate` has `RATE_BACKEND_QPS_LIMIT=500, RATE_QUEUE_CAPACITY=256`.
The search_rate fault only changes the values (750 ms, 3 attempts, 20 QPS). So the rule cannot tell the fault from the
healthy app. It fires whenever `search` logs timeouts naming a `rate` that has no failure of its own. The implementation
log's "fires only on search_rate" just means no other dev fault made search time out on rate. It does not show the rule
is selective.

**Misfire (CONFIRMED).** I took the real `lite6_network_policy_block` snapshot, which has the default values. I added the
timeout lines search would log in two cases, (A) a NetworkPolicy denies search's egress and (B) latency is injected
on rate's network. In both cases the report says
> Root cause: the call path from Deployment `search` to Deployment `rate` ... RATE_BACKEND_QPS_LIMIT=500 ... search
> retries calls that time out, so every slow period multiplies the requests rate receives while it is capped.

In (A) the model's own answer, the NetworkPolicy, is pushed down to the Mechanism line. The same happens in any app where
a caller has a retry name and a timeout name for a callee and the callee has any capacity-like name. A synthetic
checkout -> payment case misfires with just `WORKERS=4`, or with `QUEUE_NAME=payments`.

**Unbacked claim.** Nothing measures "multiplies the requests ... while it is capped". No request rate, retry count or
latency is compared with the cap or the timeout. In case (A) rate's cap is 500 QPS, and nothing shows it is reached.

**Smallest general replacement.**
1. Code should never replace the model's subject. Offer the call path as one more fault-object option in the
   investigation, like cluster findings, and lead with it only when the model picks it.
2. Set `feedback_loop` only when there is measured evidence. Examples are a callee span rate at or above the parsed cap,
   or a callee p95 latency at or above the caller's timeout. Both are available through `telemetry.py`. At minimum,
   require that a setting on the path changed after deploy (old -> new).
3. Without that evidence, list the settings as plain facts and drop the "multiplies" sentence.

### 2. HIGH. The callee's own change is invisible to the call-path check

**Where.** `call_paths` runs before `rank_changes` attaches change signals (`derive.py:814-815`), and `own_failure`
reads signals only (`paths.py:66-70`).

**Why it matters.** "Shows no failure of its own" is decided before the callee's own recent change becomes a signal.
Computing the paths again after `rank_changes` drops the path.

**Misfire (CONFIRMED, synthetic through the real `post_process`).** The callee `payment` had its pod template changed
2 minutes earlier (`WORKER_THREADS 16 -> 1`), so it is slow and its caller times out. The report leads with the call
path and says "payment shows no failure of its own". Its own Observed line then says "pod template changed 120s ago ...
WORKER_THREADS: 16 -> 1". The real cause ends up only in Details.

**Fix.** Move `paths.call_paths` after `rank_changes` (one line), or let `own_failure` count `template_changes` and
change records. I checked that the search_rate path still fires with that order, because rate has no change there.

### 3. MEDIUM. The "called position" narrowing was written from one dev log line, and on that line it picks the wrong service

**Where.** `derive.py:265-281` (`_called`), `:327-329` (where it is used). The message of commit e1a65de7 quotes the dev
line.

**Why it is specific.** Across all 29 dev recordings it changes targets on exactly one fault,
`tgt_missing_env_variable_astronomy_shop`, and on exactly the line it was written for: "shipping quote failure: failed
POST to email service". Before the change, that line pointed at shipping, quote and email. Now it points only at
`email`, because of the word "to".

**Misfire.** CONFIRMED that it fires only there and returns only `email`. PLAUSIBLE (high) that `email` is wrong. The
failing call is the shipping quote (shipping -> quote). "email" is the demo's own wording in that error message, and
the email service is not on that call. So the only effect on dev data is a wrong pointer. English cues like "to", "at"
and "server" will be at least as noisy on log formats nobody has seen yet.

**Fix.** Narrow only on address forms (host:port, a URL host, `name.ns.svc`) and never on English words. Or keep every
named component and just rank the address-form one first.

### 4. MEDIUM. Benchmark setup patches are printed as the root-cause value

**Where.** `report.py:81-86` (`changed_values`), `:89-112` (`same_change`), `:172`, `:195-196`.

**Why.** The deploy-time filter (bbe5406d) applies only to change records. The report reads `template_changes` directly.
In every hotel recording, mongodb-geo and mongodb-rate get a revision 3-4 s after they are created. It adds the
benchmark's failure-script volume (ConfigMap `failure-admin-geo` / `failure-admin-rate`).

**Misfire (CONFIRMED on 2 dev recordings).** If mongodb-geo or mongodb-rate is concluded with no key fact, the report
says "Root cause: Deployment `mongodb-geo` ...: volume failure-script added: {configMap failure-admin-geo}". If there is
a key fact, the same text goes to Details instead. Any fault on these two databases that leaves no Kubernetes write
(an in-database change or a network fault) would carry this false value. `same_change` would also group two workloads
whose deploy-time patches look alike.

**Fix.** In `changed_values`, return [] when `template_changes.changed_at` is within `MIN_CHANGE_SECONDS` of the
workload's creation. That is the same rule `object_change` already uses.

### 5. MEDIUM. Call settings are attributed loosely

**Where.** `setting_pairs` keeps only the first `key:` in a file (`paths.py:31-44`, at `:43`). `_towards` matches
by substring (`paths.py:59`) and falls back to "own ConfigMap" (`:60`). The capacity words are at `paths.py:20-22`, and
ConfigMap settings reach components at `collector.py:1637`.

**Misfires (CONFIRMED).**
- **Social network.** `service-config.json` holds 30 `timeout_ms` entries, one per downstream service. The code keeps
  the first one, which belongs to social-graph-service, and reports it as compose-post-service's setting "for"
  unique-id-service. It also reports the tracing client's buffer (`jaeger-config.yml:queueSize=1000000`) and
  `workers=32` as the callee's capacity. I checked this with a transplant on `held6_auth_miss_mongodb`. Here
  `feedback_loop` stays false, so it is only a misleading evidence line, not a report override.
- `QUEUE_NAME=payments` counts as a capacity cap.
- A callee named `ad` matches `READ_TIMEOUT`, `UPLOAD_RETRIES` and `HEADER_TIMEOUT` by substring. Renaming `ad` changes
  the result.

**Fix.**
- Keep the block path by parsing JSON or YAML, so the key becomes `social-graph-service.timeout_ms`.
- Match the callee by the name tokens of that path or env name (split on `_`, `-` and `.`), not by substring.
- Drop the "names no other component" fallback.
- Require a numeric value for capacity names, and drop bare `queue`.

### 6. MEDIUM. The second-cause search fires on single-cause faults, and the candidate it checks can depend on names

**Where.** `tree.py:482-498` (`explained_by`), `:500-516` (`unexplained_frontier`), `:1030-1034` (only `frontier[0]` is
examined).

**Why.** A failing component counts as explained only if its error lines name an explained component. Victims that crash
without naming their dependency stay "unexplained". The catch-all `configuration` evidence kind makes most failing
components eligible. When triage probabilities tie, the order is dictionary order, which is name order.

**Data (CONFIRMED on the code side).**
- For the correct conclusion, the frontier is non-empty in 2 of the 5 hard cases. In update_incompatible_correlated,
  concluding mongodb-rate leaves `rate`, which panics "no reachable servers" without naming it. In secret_rotation,
  concluding product-catalog leaves frontend, postgresql and recommendation.
- Across the 29 dev faults, 12 have a non-empty frontier for at least one failing component.
- In the name-blind test, the frontier order changed with names when probabilities were tied.

Whether a false second cause actually gets reported then depends on the model (PLAUSIBLE).

**Fix.**
- Count a component as explained when it calls an explained one through its env or config addresses (`_calls`, which
  is already collected) and fails with a dependency or crash class.
- Break ties by evidence (own change, then own configuration, then logs), never by order.
- Only consider candidates that have a change or configuration of their own.

### 7. LOW-MEDIUM. When changes happen in the same second, the "nearest change" flag goes to the first name

**Where.** `changes.py:520-537` (a stable sort followed by first match, inherited from v1).

**CONFIRMED by the name-blind test.** In update_incompatible_correlated, six workloads changed in the same second.
Renaming moved `nearest_change_before_symptoms` from mongodb-geo to mongodb-recommendation. All six are equivalent here.
But with a decoy changed in the same second, this flag (a strong triage hint) would be decided by name.

**Fix.** Flag every change tied for nearest, or break ties by evidence (whether the affected workloads are failing),
not by order.

### 8. LOW. Benchmark-harness knowledge in the code (disclose it)

- `outside.py:22` lists `chaos-mesh` and `khaos` (SREGym's injectors) and `local-path-storage` (kind). The list only
  filters namespaces that an app names in its env, and no dev app does that, so it has no effect today. Remove it or
  describe it as generic.
- The code also assumes the benchmark's protocol in three places:
  - The triage question says "Exactly one fault was injected ... after it was deployed and healthy"
    (`classifier.py:250`, v1).
  - Changes written before the first workload was created are dropped (`changes.py:474-503`, v2).
  - A revision within 10 s of creation is not counted as a change.

  These are fine for SREGym, but the write-up should say so. They would not hold on a real cluster.

### 9. LOW. Promised safeguards are missing, and the new readers are untested

- There is no generality lint and no name-blind test in the repo, although STRATEGY 3.5 and the IMPLEMENTATION ground
  rules promise both. The scripts listed at the end can become an offline test.
- `outside.py` (Ingress, PriorityClass, kube-system, related namespaces) has never run on a recording. The stored
  bundles are older than it, so every one of its calls fails in replay. Healthy Ingresses and any PriorityClass in use
  are always emitted as findings, and nobody knows yet how noisy that is.

### 10. LOW. Short names are invisible (v1)

`derive.py:252` and `:273` skip names shorter than 3 characters. Astronomy's `ad` can therefore never be named by an
error line, and renaming `ad` to a 3-letter name changes the links. Note this as a known limit.

### Report wording checked against the evidence

- The "N lines, still occurring" counts in paths and report are backed, because stopped lines are excluded.
- "The same change on N" is backed (the same normalized diff within 10 s), except for deploy-time patches (finding 4).
- "Shows no failure of its own" can be false (finding 2).
- "Multiplies the requests ... while it is capped" is not backed (finding 1).
- "Affected (symptoms only, not causes)" lists the other users of the fault object when no caller errors exist, even if
  they are healthy (`report.py:266`). Say "also uses" instead.
- The Effect line "its pods are Running and Ready" was removed in dca2e34b and 85af8577. Good.

## Name-blind test

**Method** (`scratchpad/review-general/nameblind.py`).
- Inside a stored kubectl bundle, rename every app-specific name token, wherever it appears. That covers commands,
  JSON, log lines, env var names, image tags and pod names.
- Matching is case-aware and boundary-aware, and ANSI colour codes count as word boundaries.
- Technology words (mongodb, memcached, valkey, kafka, postgresql, otel, jaeger) and Kubernetes vocabulary keep their
  names, as the generality rule allows.
- Each new name is random, has the same length, and contains no word the code reacts to.
- JSON lists are re-sorted by their new names, the way the API server would return them.
- Then I replayed collection and ran the code-side steps, namely `post_process` (log links, call paths, change ranking),
  `report.same_change`, `tree.explained_by`, `unexplained_frontier` and `link_facts`, the triage question and the
  budget-fitted state the model sees, and `report.build_report` for every failing component. That last step used a
  fixed fake Diagnosis, once without and once with a ConfigMap/Secret fault object.
- Finally I mapped names back and compared the outputs.

**Recordings.** search_rate (hotel, call path), update_incompatible_correlated (hotel, same change), valkey_auth,
secret_rotation, missing_env_variable, valkey_memory (astronomy) and auth_miss_mongodb (social network). Each had 11-20
tokens renamed.

**Result.**
- The model-facing state and fitted state, call paths, same-change groups, explained sets, link facts and all code-built
  reports are identical up to renaming, except for the items below.
- The `nearest_change_before_symptoms` flag moved between tied simultaneous changes in 1 recording (finding 7).
- Some lists follow name order, including triage options, `clients`, `calls_services`, the names in "the same change on 6", and
  the frontier when triage probabilities tie (finding 6). The report texts differ only in the order of those names.
- Log lines cut at a fixed length end mid-name, so they cannot be mapped back. This is a test artifact, not a code
  difference.

**Limits.**
- Same-length names do not test rules that depend on length. I tested those separately and they are real (findings 5
  and 10).
- English words that are also component names were renamed in log text too.
- Telemetry, probes and outside objects are live-only, so the test does not cover them.
- The test covers code only. The decision model still reads names, for example an injector Job named
  `valkey-memory-flood`.

## Leakage check

- **Driver** (`driver.py`). It uses `/status`, `/get_app` and `/submit` on the conductor, the standard agent API. The
  recorded app info is only `app_name`, `namespace(s)` and `descriptions`. The problem id comes from
  `SREGYM_ARTIFACT_ID`, an anonymised `anon_<hash>`, and is used only for file names and the trace. It is never passed
  to the diagnoser. The local arms harness (eval branch only) uses it just to shuffle arm order.
- **The model** receives only `state` and `questions` (`classifier._ask` -> `client.system_one`).
- **Telemetry** (`telemetry.py`, `jev_agent.metrics` and `call_edges`) uses fixed per-component PromQL and the Jaeger
  dependency graph through SREGym's MCP servers. The tool cache is off, there are no file reads, and the module turns
  itself off when MCP is unreachable.
- **Probes** are on by default (`driver.py:193`). They run read-only native commands through `kubectl exec` (PING,
  pg_isready, a mongo ping, Kafka consumer groups) after a memory-headroom check. That is technology-level knowledge
  only.
- **Other reads.** v2 has no `open()` calls and reads no env vars other than its own switches. kubectl reads cover the
  app namespaces, cluster-scoped webhooks, RBAC, nodes, namespaces, PriorityClasses, all Ingresses and kube-system
  DaemonSets and CronJobs. It reads no CRDs and nothing in the injector namespaces.
- **Not leakage, but worth disclosing.** The cluster itself contains injector objects in the app namespace, such as
  `failure-admin-*` ConfigMaps and the `valkey-memory-flood` Job. Every kubectl agent sees them, and no v2 code keys on
  their names.

## Addendum: uncommitted edits in the working tree (about 16:45, may change)

- `report.driven_target` (a Job that calls one failing component makes that component lead the report) fires on exactly
  one of the 29 dev faults, `held6_valkey_memory_disruption` (`job/valkey-memory-flood -> valkey-cart`), which is a
  hard case.
  Its Root-cause text prefers `OOMKilled|limit|evicted`. The risk is a Job that is the cause through its own spec while
  the component it calls fails for some other reason. In that case the subject would be swapped (PLAUSIBLE). Lead with
  it only when the model picks the called component, or when the Job's start precedes the target's symptoms.
- `checks.decoded_payloads` / `command_host_candidates` decode base64 in container commands. In practice that reads the
  injector's own script. It is fair in-cluster data, but disclose it.
- `report.BROKERS` / `broker_technology` is a technology table, which is allowed. It matches by substring on names and
  images, though (any name containing "nats"). Match tokens instead.

## Files (scratchpad/review-general/)

`pinned/` (export of 85af8577), `replay_lib.py`, `survey.py` (which rules fire on the 29 dev faults), `nameblind.py` +
`jdiff.py` and `nameblind/<label>/` (outputs), `misfire.py`, `transplant2.py`, `transplant_sn.py`, `deploytime.py`,
`called.py`, `frontier_hard.py`, `driven.py`, `pinned_results.txt`. Run with
`JEV_REPO=<path> uv run --project ~/sregym/SREGym-pr-v2 python <script>`.
