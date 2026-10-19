# Decision models: how to get the best answers out of them

Study date 2026-10-19. Read-only. The numbers come from all 81 runs in `runs-index.tsv` (324 arms, 1,136 model
requests, 1 run lost to an OpenRouter 402 "insufficient credits" error, `lite5_finalizer_deadlock_controller_hotel_reservation`).
No sample C run is in the index, and none was opened. Analysis scripts were throwaway (in the session scratchpad).
Each claim says where it comes from, using these tags. **[measured]** means our runs. **[vendor]** means the model
maker's docs. **[3rd party]** means someone else's write-up. **[opinion]** means my judgement.

## 0. Summary

1. Both models are reliable when they are confident and unreliable when they are not **[measured]**. In v2's final pick,
   Jev was right on 100% of asks at top probability >= 0.7 (102 asks) and 50% below 0.5. Decisions was right on 98%
   at >= 0.9 and 64% below 0.5. v2's "accept" gate (both shuffled asks agree and the averaged leader >= 0.6) was right
   57 of 59 times with Jev and 58 of 60 with Decisions. The problem is the other third of decisions, where they are
   right only 56-61% of the time.
2. The models add only a little on top of the code's own ranking in v2 **[measured]**. The code's top-ranked candidate
   was already the right origin in 77% of first rounds. Jev picked it 62% of the time and lifted accuracy to 80%;
   Decisions moved away from it more often and reached 87%.
3. Jev and Decisions often disagree on byte-identical requests: same pick only 77-80% of the time **[measured]**.
   When they do agree they are nearly always right (v2: 32 of 33; v1 triage: 56 of 62).
4. They fail differently **[measured]**. Decisions is more sensitive to option order (two shuffled asks give different
   picks 20% of the time vs 12.5% for Jev). It also tends to say "yes, this one" about whatever candidate it is asked
   about, and it is confidently wrong when the right answer is not among the options. Jev hedges more and puts more
   weight on "none of these".
5. State size up to ~45k characters showed no accuracy effect once the app is held fixed **[measured]**. The app and
   fault type dominate, and Astronomy Shop is hard for both models. But Jev on OpenRouter switches to a
   "long-context mode" above about 32,000 bytes, which TypeSafe says is slower and less accurate **[vendor]**. Every
   v1 triage request was above that line.
6. A design tuned on one model does not carry over automatically **[measured, opinion]**. Thresholds, the meaning of
   a 0.8, and order sensitivity all differ. Making the pipeline robust means per-model calibration on a dev set,
   decisions based on agreement (across orderings and across models), and testing every change on at least three
   models.
7. There are now ~22 decision models on OpenRouter, all on the same Decisions API **[3rd party]**. For an evaluation
   beyond the two required ones I recommend adding Jev 1.14, Perplexity Decider V1.2 and Liquid d1-ultra, with
   Nace Drex v2.0 as the reserve (section 5).

## 1. What these models are, what they are good and bad at, hard limits

A decision model ("System One" model) reads a state (text, a JSON object or an array) and answers typed questions
in one forward pass. It returns a probability for every option and never writes text. There are three question
types, plus a fourth image-only one in Jev 1.14 **[vendor]**.

| type | Jev name | OpenAI name | returns |
|---|---|---|---|
| pick one of N | Choice | choice | the pick, a probability per option, a "confidence" derived from the spread |
| yes/no | Noul | predicate | probability of yes |
| ordered rubric | Score | score | probability per level and the probability-weighted level |
| image box (Jev 1.14 only) | Box | - | box edges |

OpenRouter accepts the Jev wire format (`noul`, `choice`, `score`) for every decision model at
`POST https://openrouter.ai/api/alpha/decisions` **[vendor, and `clients/jev_diag/openrouter.py`]**.

### Hard limits

| | Jev 1.13 / 1.14 | OpenAI Decisions (gpt-6-luna-decisions) | Laya (open weights) |
|---|---|---|---|
| context | TypeSafe direct: 64k tokens per request, 32k per question (state + that question); 262k with a "long context" header. OpenRouter: 262k, and long-context mode switches on above about 32,000 bytes of text **[vendor]** | 1.05M tokens on OpenRouter; OpenAI publishes no limit **[vendor/3rd party]** | 512 tokens per question (English checkpoint), 1,024 multilingual, optional `max_len=8192`; ~192-256 tokens for all option text together **[vendor]** |
| options per Choice | up to 255 **[vendor]** | not published **[3rd party]** | no hard cap, but a 77-option task gets ~3-4 tokens per option and accuracy falls (0.425 vs Jev 0.870) **[vendor]** |
| questions per request | no separate limit **[vendor]**; OpenRouter says up to 200 **[3rd party]** | up to 200 **[3rd party]** | - |
| score levels | any (the team's `clients/jev/client.py` caps at 10) | - | - |
| price | $0.042 per 1M input tokens, output free | $0.10 per 1M input tokens, output free | free, self-hosted |
| input | text and JSON (1.14 adds images) | text and inline base64 images | text |

The team's Codex agent (`clients/jev/client.py`) enforces its own tighter caps (Choice 2-64 options, Score 2-10
levels, 16 questions, 8,000-character instructions, 64 KiB request). `clients/jev_diag/openrouter.py` parses only
`choice` and `noul` answers, so a Score question would currently fail with "malformed answer".

### Good at **[vendor, measured]**
- Choosing between well-described alternatives, and saying how sure it is. In our runs the probability is a usable
  confidence signal for both models (section 2).
- Many questions over one state at almost no extra cost (questions run in parallel; latency in our runs was
  0.6-0.8 s per request whatever the number of questions).
- Clear yes/no facts. Our yes/no answers sat at 0 or 1, and the one real "yes" case (kafka poison pill,
  `blocked_input`) was found by both models every time.
- Cheap. A full diagnosis cost $0.0012-0.0014 (Jev) and $0.0020-0.0022 (Decisions) at the median **[measured]**.

### Bad at **[vendor: TypeSafe's "jev-1.13 jaggedness" page and the OpenRouter skill page]**
- Counting, arithmetic, comparing numbers or dates ("Jev is not a calculator"; "reads dates as text"). Code must do
  all of that and hand over the result as a plain fact.
- Instructions with negations, double negatives, indirection, or several reasoning hops. It "answers the question
  you wrote, not the one you meant".
- Instructions and criteria that pull in different directions.
- Unrelated content in the state ("Unrelated detail acts as a distractor").
- Option order. TypeSafe says jev-1.13 "leans toward the option that comes first". We could not see this with
  shuffled neutral labels (section 2), but it is the documented risk.
- Explanations. They cannot say why, so a wrong pick is hard to debug.

### Laya, briefly
Laya (Convai, 421M ModernBERT-large encoder, Apache 2.0) is fast (~33-40 ms on a T4) but **[vendor]** the base
checkpoints are "near chance" zero-shot (0.362 vs a 0.318 random baseline) and ship over-confident (ECE 0.466
before per-question-type temperature fitting). Only the fine-tuned `laya-typed-decisions` beats Jev (0.766 vs 0.727)
on its maker's own benchmark. With 512 tokens per question it cannot read our states (10-48k characters). It is not
on OpenRouter. Using it would mean fine-tuning on our own labelled decisions and cutting states to a few hundred
tokens. **Not a fit for this task as it stands [opinion]**.

## 2. Measured behaviour in our runs

Ground truth for "right or wrong" is the `component=` in each problem's `build_structured_root_cause` call
(`sregym/conductor/problems/*.py`), matched by object name. I widened it in two places where the option names the
real mechanism object. `network_policy_block` also accepts NetworkPolicy `deny-all-recommendation`, and
`search_rate_retry_collapse` also accepts the `search--rate` interaction. Cases where the model's answer is
arguably right but the label differs (the `valkey-memory-flood` Job in valkey_memory_disruption, the
`cleanup-controller` Deployment in finalizer_deadlock) are counted as wrong, so the accuracies below are slightly
pessimistic. In 78 of 80 runs the v2 shortlist contained a correct option.

### 2.1 Request sizes (p50 / p90 / max per request)

| request | model | n | state chars | question chars p50 | input tokens p50 / p90 / max | chars per token | latency p50 |
|---|---|---|---|---|---|---|---|
| v1 triage | Jev | 80 | 39.5k / 47.8k / 48.0k | 9.5k | 21.4k / 26.3k / 26.8k | 2.2 | 0.77 s |
| v1 triage | Decisions | 80 | same states | 9.5k | 14.0k / 16.9k / 17.3k | 3.4 | 0.74 s |
| v1 investigate | Jev | 106 | 11.9k / 16.3k / 19.8k | 14.2k | 9.7k / 12.1k / 13.7k | 2.7 | 0.60 s |
| v1 investigate | Decisions | 95 | 11.8k / 16.1k / 19.8k | 13.9k | 7.2k / 8.8k / 10.8k | 3.6 | 0.71 s |
| v2 decide | Jev | 192 | 12.7k / 35.3k / 40.0k | 3.3k | 7.1k / 18.0k / 20.6k | 2.3 | 0.65 s |
| v2 decide | Decisions | 188 | 12.7k / 36.2k / 39.8k | 3.3k | 4.8k / 12.3k / 13.6k | 3.4 | 0.66 s |
| v2 characterize | Jev | 82 | 10.8k / 14.1k / 17.8k | 8.2k | 7.6k / 9.2k / 11.7k | 2.5 | 0.56 s |
| v2 characterize | Decisions | 82 | 10.5k / 14.1k / 17.8k | 8.3k | 5.2k / 6.4k / 8.3k | 3.5 | 0.63 s |

Per diagnosis (one arm, all requests): v1 median 22k tokens (Decisions) / 32k (Jev), max 57k / 102k. v2 median
20k / 28k, max 58k / 89k. Jev's tokenizer counts about 1.5x more tokens than Decisions' for the same JSON.

Over the ~32,000-byte line where Jev on OpenRouter goes into long-context mode: all 160 v1 triage requests, 35 of
201 v1 investigate requests, 64 of 380 v2 decide requests, 0 characterize requests. Latency above the line was
~100-400 ms higher. Accuracy above vs below the line could not be separated from the app (too few big requests in
the easy apps).

v1 instructions are long. The triage question carries ~9.5k characters of instructions (rules 1-6 with "unless",
"only if", "never ... on their own"), which is the kind of multi-hop, negation-heavy instruction TypeSafe's
limitations page warns about.

### 2.2 Options, probability shape, near ties

| question | options | near ties (top-2 gap < 0.1) Jev / Dec | top p median Jev / Dec | options with p >= 0.01 Jev / Dec |
|---|---|---|---|---|
| v2 best_explanation | 3-7 (7 typical) | 17% / 8% | 0.76 / 0.76 | 4 / 5 |
| v2 fault_category | 18 | 0% / 7% | 0.95 / 0.79 | 2 / 10 |
| v2 key_evidence | 3-24 (18) | 9% / 6% | 0.84 / 0.92 | 3 / 5 |
| v1 root_cause_component | 20-29 (23) | 5% / 5% | 0.80 / 0.95 | 3 / 4 |
| v1 fault_object_kind | 10 | 8% / 5% | 0.92 / 0.86 | 3 / 6.5 |
| v1 verdict | 4 | 0% / 11% | 0.94 / 0.94 | 3 / 4 |
| v1 next_component | 3-13 (5) | 6% / 8% | 0.82 / 0.63 | 3 / 5 |
| v1 fault_category | 18 | 10% / 9% | 0.89 / 0.76 | 3 / 12 |
| v1 key_evidence | 3-32 (17) | 11% / 9% | 0.78 / 0.84 | 4 / 5 |
| yes/no (fault_visible, blocked_input) | 2 | 0% / 0% | 0.96-0.99 / 1.0 | - |

Decisions spreads probability over many more options when there are many (fault_category: 10 of 18 options above
1% vs Jev's 2). Jev peaks harder. Neither shape tells you on its own whether the answer is right; calibration does.

### 2.3 Calibration: is a high probability a right answer?

v2 decide, one ask (Jev 186 asks, Decisions 182):

| top probability | Jev right | Decisions right |
|---|---|---|
| < 0.5 | 50% (48) | 64% (33) |
| 0.5-0.7 | 64% (36) | 78% (45) |
| 0.7-0.9 | 100% (35) | 85% (41) |
| >= 0.9 | 100% (67) | 98% (63) |
| all | 80.1% | 84.1% |

v1 triage (20-29 component options, one ask):

| top probability | Jev right | Decisions right |
|---|---|---|
| < 0.5 | 0% (5) | 71% (7) |
| 0.5-0.7 | 79% (19) | 62% (8) |
| 0.7-0.9 | 89% (28) | 53% (17) |
| >= 0.9 | 96% (28) | 92% (48) |
| all | 84% | 79% |

v1 verdict (origin / victim / unrelated / undetermined about one candidate): at >= 0.9 Jev was right 95% of the time
(65 asks) and Decisions 78% (65 asks).

So the same number means different things per model and per question. Jev at 0.7+ was right every time on v2's
7-option question; Decisions needs about 0.9 for the same trust, and on v1's 23-option triage it is overconfident
in the 0.7-0.9 band.

The v2 gate works for both models. "Accept" (both asks agree and averaged leader >= 0.6) was right 57/59 (Jev) and
58/60 (Decisions). "Unsure" was right 19/34 and 19/31. About a third of decisions land in "unsure".

### 2.4 Asking the same question twice (v2 decide: identical state, only option order and o1..o7 labels change)

| model | pairs | same pick | mean total-variation distance | pairs with TV > 0.3 | right when the asks agree | right when they disagree |
|---|---|---|---|---|---|---|
| Jev | 96 | 87.5% | 0.074 | 2 | 85% (82) | 55% (11) |
| Decisions | 94 | 79.8% | 0.224 | 29 | 88% (73) | 72% (18) |

No pair disagreed with both asks confident (>= 0.7). Averaging the two asks lifted accuracy only slightly (Jev
80.1% to 81.7%, Decisions 84.1% to 84.6%). The value of the second ask is the agreement signal, not the average.

Position bias, measured on options that moved between the two asks: an option shown first gained +0.001 probability
on average with Jev and +0.022 with Decisions; shown earlier by half the list or more, +0.005 and +0.021; about half
of options gained and half lost. So with neutral labels and long option texts the flips are order noise, not a
steady first-option lean. (TypeSafe documents a first-option lean for jev-1.13; it may show with short or
meaningful labels, which v1 uses unshuffled.)

v2 characterize asks the category twice with the 18 categories in a fixed order and only the evidence list
shuffled in the state. fault_category gave the same pick 100% (Jev, TV 0.02) and 88% (Decisions, TV 0.07).
key_evidence, whose options are shuffled, gave 80% and 83% (TV 0.11 and 0.21).

### 2.5 Jev vs Decisions on byte-identical requests

| question | pairs | same pick | mean TV | disagreements with both top-2 gaps >= 0.3 |
|---|---|---|---|---|
| v2 best_explanation | 88 | 77% | 0.25 | 1 |
| v1 root_cause_component | 80 | 78% | 0.22 | 8 |
| v1 fault_object_kind | 80 | 80% | 0.23 | 3 |
| v2 fault_category | 32 | 75% | 0.24 | 4 |
| v2 key_evidence | 32 | 88% | 0.18 | 0 |
| yes/no fault_visible | 80 | 100% | 0.01 | 0 |

Agreement between the two models is the strongest signal found. In v2 decide, 32 of 33 agreed picks were right.
In v1 triage, 56 of 62 agreed picks were right (90%, vs 80% overall). Averaging the two models' probabilities does
not beat the better single model (v2: 38 of 42 vs Jev 37 and Decisions 39; v1 triage: 64 of 80 vs 67 and 63).

### 2.6 Failure modes seen

- **The right answer is not an option** (6 v2 asks, 2 runs). Jev put 0.30 on "none of these" on average, Decisions
  0.11. With a correct option present, "none" got 0.10 and 0.07. Small sample, but it matches the next point.
- **Decisions confirms the candidate it is asked about.** On candidates that were not the root cause, v1's verdict
  said "origin" 16 of 26 times with Decisions and 13 of 39 with Jev. The clearest case is the CoreDNS faults
  (`service_dns_resolution_failure_*`), where the true cause is not a workload. Decisions called the symptomatic
  `frontend` / `user-service` the origin at 0.94-0.99, and Jev did the same at 0.45-0.67. The v1 triage shows the
  same thing: Decisions picked `deployment/frontend` at 0.96 (held, held3) instead of `other`.
- **Questions that never vary.** `fault_visible` was 1.0 in all 160 asks for both models. It costs tokens and carries
  no information.
- **Yes/no hedging differs.** On `blocked_input`, Jev gave 33 of 106 answers between 0.05 and 0.95; Decisions gave
  none. Both found the true case 3/3. Jev also said yes 3 times for the finalizer `cleanup-controller` (arguably
  right: it keeps failing on one stuck object). Decisions had 0 false yes out of 92.

### 2.7 Do long states or many options cause wrong or split answers?

- **State size: no measurable effect once the app is fixed.** Accuracy looks lower for big states overall (v2 Jev
  84% under 15k characters vs 72% over 25k), but big states come from Astronomy Shop, which is hard for everything.
  Inside Astronomy Shop alone, v2 accuracy by state size (<12k / 12-25k / 25-50k characters) was 71 / 77 / 68% for
  Jev and 68 / 69 / 73% for Decisions. By app, v2 decide was right 97% (Hotel Reservation, both), 72% / 97% (Social
  Network, Jev / Decisions) and 72% / 70% (Astronomy Shop). v1 triage: 89 / 89% Hotel, 89 / 79% Social Network,
  76 / 71% Astronomy Shop.
- **Option count: cannot be isolated.** v2 almost always has 7 options; v1 has 20-29. Option count tracks the app
  (Hotel 20, Astronomy 23, Social Network 28). v1 triage with 20-29 options was right 79-84% of the time, so many
  options are not by themselves a problem. Decisions spreads probability more as options grow.
- **What does drive splits:** low top probability and disagreement between the two asks (2.3, 2.4) and missing right
  answers (2.6). Those are where to spend extra checks.

## 3. Best practices for states and questions

Each item says what it is based on.

1. **Let code compute, let the model judge.** Code should do every count, comparison, time difference and
   string match, and put the result in the state as a plain sentence or field (e.g. "Service frontend was modified
   133s ago ... 124s after the first active symptom", which v1 and v2 already do). **[vendor]**: arithmetic, dates,
   numeric closeness and counting are on TypeSafe's list of things Jev does badly.

2. **Raw evidence vs code-written summaries: give facts, keep code's verdicts out of the options.** v2's option
   text includes code's own verdicts ("Checks: ... (supports)", "(contradicts)") and the shortlist is pre-sorted by
   code. The model then mostly ratifies code: Jev kept code's top candidate in 62% of asks, which already had the
   right origin in 77% of first rounds, and Jev's overrides fixed 16 asks and broke 12. Decisions overrode more
   (fixed 24, broke 6). **[measured]**. My reading **[opinion]** is that verdict words in the options pull the model
   toward code's answer, so code errors pass through. Better is to put the checked facts in the state, with the
   source field named ("`evidence.frontend.spec_checks[0]`"), and keep each option a plain claim (origin,
   mechanism, values). Raw logs are a poor state: they are long, mostly unrelated, and TypeSafe says unrelated detail
   is a distractor **[vendor]**. The middle ground is short code-extracted facts, verbatim where it matters (the
   error line, the env value), without code's conclusion attached. This needs an A/B test on the dev set; it is not
   proven.

3. **Keep states focused, and for Jev on OpenRouter keep a request under ~32,000 bytes when you can.** No accuracy
   loss was measurable from size alone (2.7), but TypeSafe documents a slower, less accurate long-context mode above
   ~32 kB and a general loss from unrelated content **[vendor]**. v2's focused state (only the components the
   candidates are about) is the right idea. v1's ~40-48k-character triage state always ran in long-context mode.
   **Put related information together** in one named object and point to it from the instructions with backticked
   paths **[vendor]**.

4. **Short, literal, single-hop instructions.** v1's triage carries 9.5k characters of ordered rules with "unless",
   "only if", "never on their own". TypeSafe warns that negations, double negatives, indirection and multi-hop
   instructions are answered less reliably, and that conflicting instructions and criteria hurt **[vendor]**. Move
   rules like "symptoms never select a component on their own" into code (filter or annotate the candidates)
   instead of asking the model to apply them **[opinion, backed by vendor guidance "keep deterministic work in
   code"]**.

5. **Number of options: a handful for the deciding question; many is fine for coarse ranking.** All models accept
   up to 255 **[vendor]**. 18-29 options worked in our runs (v1 triage 79-84%, category answers stable)
   **[measured]**, but Decisions spreads probability thinly over long lists and is overconfident in the 0.7-0.9 band
   on them. So use a wide Choice only to rank or shortlist (take the top-k, not the top-1), and make the decision
   that you threshold on over 2-7 well-separated options **[opinion from measured]**. This is TypeSafe's own
   "rank-then-recheck" cookbook: a wide Choice over 182 options, then a re-check of the top 3 with fuller text
   **[vendor]**.

6. **Always offer a way out, and do not trust it alone.** Include "none of these" / `other` **[vendor]**. But
   Decisions rarely uses it when the right answer is missing (0.11 average), and confidently picks a wrong candidate
   instead **[measured]**. So code must also check coverage: is there a candidate for each kind of origin (workload,
   Service, policy, cluster DNS, webhook, quota)? The CoreDNS miss is exactly a coverage gap.

7. **Per-candidate yes/no checks: use them as an independent filter, phrased neutrally.** TypeSafe's recheck step
   asks one Noul per shortlisted candidate so that "they can all come back low" **[vendor]**, which is a natural
   abstention. But a leading per-candidate question ("is this candidate the origin?") drew "yes" from Decisions on
   16 of 26 wrong candidates **[measured]**. Ask about a checkable fact, not about the conclusion ("Do the error
   lines in `evidence.X.logs` name a DNS lookup failure?" rather than "Is X the origin?"). One condition per Noul
   ("Ask two Nouls and combine them in code") **[vendor]**. Combine the answers in code, and require the
   per-candidate check to agree with the Choice before accepting **[opinion]**.

8. **Pairwise for the final call when unsure.** When the top two are close or the asks disagree, a two-option
   question ("which side holds the wrong setting", as v1's `build_pair_questions` does) is easier than a 7-way one,
   and TypeSafe's re-ranking cookbook gets its gains from scoring each candidate on its own (top-1 from 5% to 18% on
   a legal dataset) **[vendor]**. Our runs have too few pair questions to measure. **[opinion]** Ask the pair in
   both orders and only accept when both orders and both phrasings agree.

9. **Scoring each candidate separately (Score) is untested here.** A Score rubric per candidate ("how much of the
   observed impact does this explanation account for", 4-5 levels with clearly different criteria) would give
   comparable numbers across rounds and models. OpenAI's guide asks that "adjacent levels have distinct criteria"
   **[vendor]**. Our OpenRouter client cannot parse Score answers yet, and no run used Score, so this is an idea to
   test, not a finding.

10. **Ask the same question differently, and use agreement, not averages.** Two shuffled orderings: agreement means
    85-88% right, disagreement 55-72% **[measured]**. Across models: 32 of 33 right when Jev and Decisions agree
    **[measured]**. Averaging probabilities adds little. Costs are tiny (about $0.0003-0.0005 per extra request at the
    median), so a third ordering, or a rephrased version of the question (say a per-candidate Noul next to the
    Choice), is affordable. Use neutral labels (o1..oN) so the label carries no meaning; v2 already does **[measured
    design, vendor bias note]**.

11. **Drop questions that cannot vary.** `fault_visible` was 1.0 in 160 of 160 asks for both models **[measured]**.

12. **Set thresholds per model and per question from labelled runs.** "A threshold does not carry from a noul to a
    choice or from one model to another" **[vendor, OpenRouter skill page]**. Our numbers agree: 0.7 is safe for Jev
    on v2's 7-option question but not for Decisions on v1's 23-option triage **[measured]**.

## 4. Does a design built for one model transfer to the other?

**Mechanically yes, behaviourally only partly.** The wire format is the same for every model on OpenRouter, so
code runs unchanged. But on byte-identical requests Jev and Decisions picked the same answer only 77-80% of the
time, and they differ in ways that matter to a design:

| behaviour | Jev 1.13 | Decisions | design risk if tuned on one |
|---|---|---|---|
| tokens for the same JSON | ~1.5x more | baseline | a token budget set for one model is wrong for the other (`fit_state_to_budget` estimates with 2 chars per token, which is closer to Jev) |
| order sensitivity (shuffled asks) | 12.5% flips, TV 0.07 | 20% flips, TV 0.22 | a "one ask is enough" design tuned on Jev fails on Decisions |
| probability shape | peaked | spread out over long lists | a fixed probability threshold (v2's `CONFIDENT_P = 0.6`) means different things |
| calibration at the high end | 0.7+ trustworthy on v2 decide | needs ~0.9; overconfident at 0.7-0.9 on v1 triage | accept rules tuned on one model over- or under-accept on the other |
| answering about a named candidate | moderate yes-bias (13/39) | strong yes-bias (16/26) | verdict-style "is X the origin?" designs tuned on Jev over-confirm on Decisions |
| abstaining ("none of these") when the answer is missing | 0.30 | 0.11 | a "none wins, so look wider" route (v2's `coverage`) fires for Jev but rarely for Decisions |
| hedging on yes/no | sometimes in the middle | always at the ends | a three-way yes / unsure / no route only ever sees "unsure" with Jev |

The headline results already show the transfer gap. On SREGym-Lite, v1 gave 13/17 with Jev and 12/17 with
Decisions. Per-question accuracy differs by model in both directions (Decisions better on v2 decide, Jev better on
v1 triage and verdicts).

**How to make a pipeline robust to the model choice [opinion, built on the measurements above]:**

1. **Rely on agreement and rank, not absolute probability.** Use "the leader agrees across two orderings" and "the
   leader is first by a margin" rather than "p >= 0.6". Both held up for both models (2.3, 2.4).
2. **Calibrate per model on the dev set.** Keep a small table per model and question (raw probability band to
   observed accuracy) and act on the mapped number. It needs tens of labelled decisions per question, which the
   existing runs already provide.
3. **Prefer questions whose answers both models agree on.** On the same requests, yes/no facts agreed 100%, key
   evidence 88%, and component and category picks 75-80%. Narrow, factual questions transfer best.
4. **Design out each model's known weak spot.** Code coverage checks for Decisions' missing-option overconfidence.
   Neutral-fact Nouls instead of "is X the origin?" for its yes-bias. Shuffled double asks for order noise.
   Requests under ~32 kB for Jev.
5. **Test every design change on at least three models** (the two required ones plus Jev 1.14 or another strong
   model from section 5) and on held-out faults, and report per-model results. A change that helps one model and
   hurts another is tuned to a quirk.
6. **Optional, if allowed by the task rules: ask both models and gate on agreement.** It costs one more request per
   decision (fractions of a cent) and was 32/33 right when they agreed. Whether calling two decision models in one
   run is allowed is a rules question to settle first; the brief says the pipeline must "work with both", not that
   it may use both at once.

## 5. Other decision models (Microsoft, Perplexity and the rest)

Context and per-token prices are the coordinator's confirmed OpenRouter figures unless marked. Our per-diagnosis
use is about 20-32k input tokens at the median and up to ~58k (Decisions-like tokenizer) to ~100k (Jev tokenizer)
for the biggest arm. Every request is sent separately; the largest single request is ~57k characters, which is
~17k tokens with a GPT/Qwen-like tokenizer and ~25k with Jev's. So **context limits apply per request, not per
diagnosis.** At 16k, 56-82% of v1 requests and 90-100% of v2 requests fit. At 8k, only 9-32% of v1 and 52-81% of v2
fit.

| model (OpenRouter id) | maker, base, access | context | price per 1M input | est. cost per diagnosis (median / max) | question types | fits our states? | public quality signals |
|---|---|---|---|---|---|---|---|
| `typesafe/jev-1.13` | TypeSafe, closed | 262k (long-context mode above ~32 kB) | $0.042 | $0.0013 / $0.0043 (measured) | choice, noul, score | yes | AA Decision Index 57.5; 79/82 in a dev.to 14-model test; most used (980M requests this week) |
| `typesafe/jev-1.14` | TypeSafe, closed, released 14 Oct | 262k (same) | $0.042 | same as 1.13 | + box (images) | yes | AA index 57.1 (no gain over 1.13 there); d1-ultra's maker says it beat 1.14 on all 112 of its evals |
| `openai/gpt-6-luna-decisions` | OpenAI, closed, beta since 6 Oct | 1.05M | $0.10 | $0.0022 / $0.0057 (measured) | predicate (noul), choice, score | yes | AA index 48.5; 76/82 with 2 order flips in 25 (dev.to) |
| `perplexity/pplx-decider-v1.2` (id from third-party listings; my fetch of the OpenRouter page returned 404) | Perplexity, 27B on Qwen3.8-27B, **open weights Apache 2.0** | 262k (Perplexity: "under 256K") | $0.02 | ~$0.0006 / $0.002 | noul, choice (up to 255 options), score (up to 10 levels); 1-128 questions per request | yes | Perplexity: Decision Index 65.5 (Full), 3rd. v1.1 27B: Decision Index 0.3 62.8 (1st), AA index 53.1, 80/82 and 0 flips on dev.to (1st of 14) |
| `perplexity/pplx-decider-flash-v1.2` (third-party id) | Perplexity, 4B, open weights | 262k | $0.01 | ~$0.0003 / $0.001 | same | yes | "top 4B" per Perplexity; no independent numbers found |
| `perplexity/pplx-decider-v1.1-27b` (id from dev.to test) | Perplexity, 27B, open weights | 262k | ~$0.02 | ~$0.0006 / $0.002 | same | yes | see above; 53M requests this week |
| `microsoft/microsoft-decision-1` | Microsoft, on Qwen3.5-9B, closed (Foundry + OpenRouter), text only | 32k | $0.042 | ~$0.0013 / $0.0042 | noul, choice, score | yes, but little headroom (v1 triage ~17-27k tokens) | Microsoft: 83.5% vs Jev 82.3% on its 36 suites, calibration 92.2 vs Jev 93.7. AA index 53.8. dev.to: 75/82, 6th of 14, only cloud model fooled by a prompt injection |
| `liquid/d1-ultra` | Liquid AI, closed, released 15 Oct | 32k | $0.042 | ~$0.0013 / $0.0042 | noul, choice, score | yes, little headroom | AA index leader 65.2 (+8 over Jev); 85% "non-hallucination" vs next best 40%, which matters for "none of these" |
| `liquid/d1` | Liquid AI | 65k | $0.02 | ~$0.0006 / $0.002 | noul, choice, score | yes | AA index 50.3; 79/82 on dev.to (2nd) |
| `nace-ai/drex-v2.0` | Nace, 35B MoE (3B active) on Qwen3.6, **open weights** (RAIL-M) | 131k | $0.06 | ~$0.0018 / $0.006 | noul, choice, score | yes | Nace: Decision Index 0.3.1 61.25 (+3.3 over Jev 1.13); "up to 38% faster on 32K-128K inputs", so built for long inputs |
| `nace-ai/drex-v1.5` | Nace, open weights | 131k | $0.04 | ~$0.0012 / $0.004 | same | yes | 72/82 on dev.to |
| `inception/mercury-decide` | Inception (diffusion LM maker) | 65k | $0.02 (free tier exists) | ~$0.0006 / $0.002 | choice, score, noul | yes | AA index 52.7; 76/82 on dev.to |
| `cloudflare/clef` | Cloudflare, 27B, open weights Apache 2.0 | 16k hosted | $0.042 | - | noul, choice, score | **no** for v1 triage; most v2 requests | AA index 48.6; 71/82 |
| `cloudflare/clef-flash` | Cloudflare, 9B, open weights | 16k hosted (weights trained to 256k) | $0.021 | - | same | **no** for v1 triage | AA index 45.8; 65/82 (last of 14) |
| `cloudflare/clef-omni` | Cloudflare, 30B-A3B multimodal, open weights | 65k | $0.15 | ~$0.0045 / $0.015 | same | yes | AA index 44.3; 72/82 |
| `upstage/solar-decide` | Upstage, on Solar Mini | 524k | $0.05 | ~$0.0015 / $0.005 | same | yes | 66/82 and 2 order flips in 26 on dev.to; slowest (1.5 s) |
| `jaredpalmer/kev-4b` | Jared Palmer, LoRA + pointer head on Qwen3.5-4B, open weights Apache 2.0 | 8k | $0.042 | - | same | **no** (9-32% of v1 requests, 52-81% of v2) | 72/82 on dev.to |
| Laya (`convaiinnovations/laya`, not on OpenRouter) | Convai, 421M encoder, Apache 2.0 | 512 tokens per question | self-hosted | - | choice, score, noul | **no** | near chance zero-shot; needs fine-tuning (section 1) |

What "public quality" is worth here: the indexes test short, general decisions (knowledge, safety, tool-call
judgement, ticket routing). None tests long JSON states with 7-29 technical options like ours. Rankings disagree
with each other (Luna is last-ish on the AA index but beat Jev on our v2 decide). Usage numbers measure popularity,
not accuracy. **Our own dev-set runs are the only evidence that counts for this task [opinion].**

**On Microsoft and Perplexity specifically.** Microsoft-Decision-1 exists (9 Oct, Foundry and OpenRouter,
`microsoft/microsoft-decision-1`). It is text only, has 32k context and is mid-pack in public tests, and nothing
about it suits long SRE states in particular. It is usable but not a priority. Perplexity's Decider family exists
(V1 27B, V1.1 27B, V1.2 27B, Flash V1.2 4B). Ids on OpenRouter per third-party listings are
`perplexity/pplx-decider-v1-27b`, `perplexity/pplx-decider-v1.1-27b`, `perplexity/pplx-decider-v1.2` and
`perplexity/pplx-decider-flash-v1.2`; they are not verified by me, since the OpenRouter pages returned 404 to my
fetch. The family is also on Perplexity's own API (`POST https://api.perplexity.ai/v1/decisions`). It has 256k
context, Apache 2.0 weights and the same noul/choice/score contract. It leads or is near the top of every public
ranking found, and it is cheap. **It is a near drop-in third model** (same OpenRouter wire format), apart from
checking whether the OpenRouter id answers.

**Recommended evaluation set (5) [opinion]:**
1. `typesafe/jev-1.13` (required; baseline).
2. `openai/gpt-6-luna-decisions` (required).
3. `typesafe/jev-1.14`. It is the same vendor and API, and it tests whether our design survives a version bump of
   the same model. That is the most likely real-world change, and it shows quirk-tuning directly.
4. `perplexity/pplx-decider-v1.2`. Strongest public results, 256k context, open weights, a different base
   (Qwen-derived), $0.02/M.
5. `liquid/d1-ultra`. Top of the AA index and far ahead on not answering when it should not (85% vs 40%
   "non-hallucination"), which is the weak spot we measured in Decisions. Its 32k context fits every current request
   but leaves little headroom. If a state redesign makes requests bigger, swap in `nace-ai/drex-v2.0` (131k, built
   for 32-128k inputs, open weights).

Skip Clef / Clef-flash (16k) and Kev-4b (8k) unless states are redesigned to be small. Skip Solar Decide (order
flips, slow) and Laya (not on OpenRouter, 512 tokens). Microsoft-Decision-1 and Mercury Decide are acceptable
extras if a sixth model is wanted. Note the brief's hard constraint names only Jev and Decisions. The extra models
are for checking robustness (is the design tuned to one model's quirks?), not for submission, unless the team
changes the rule.

## Method notes and caveats

- "Right" means the picked option names the ground-truth object (section 2). This is localization only (D1), not
  the judge's full checklist.
- v2's two asks in a round use `random.Random(0)` from a fresh diagnoser, so round 1 has the same shuffle in both v2
  arms. That is why many Jev and Decisions requests are byte-identical. Later rounds and investigate steps differ
  because the live cluster reads differ.
- The code's shortlist rank (section 3, item 2) was rebuilt by replaying that seeded shuffle. It was checked by
  confirming that "None of these" lands where the replay predicts (it did for every first-round pair, 78-80 per model).
- Small samples: missing-option cases (6 asks), pair questions (2), runs above 32 kB in easy apps (12). Treat those
  findings as leads.
- The runs mix code versions (`arms`, `final`, `lite5/6`, `held*`, `tgt`). Per-question model behaviour should be
  comparable across them, but absolute accuracies are not one experiment.

## Sources

Local: `~/sregym/SREGym-fixes/.venv/lib/python3.12/site-packages/typesafe_sdk/` (0.6.0),
`clients/jev_diag/{openrouter.py,classifier.py,tree.py,collector.py}`, `clients/jev_v2/{decide.py,agent.py,explain.py}`,
`clients/jev/{client.py,planning.py,review.py,config.py}`, `sregym/conductor/problems/*.py` (ground truth), run files
listed in `runs-index.tsv`.

Web (read 2026-10-19):
- OpenRouter Jev guide, https://openrouter.ai/docs/guides/community/jev (262k context, long-context mode above ~32 kB)
- OpenRouter decisions skill, https://openrouter.ai/skills/openrouter-decisions (thresholds do not carry across models)
- TypeSafe docs: https://docs.typesafe.ai/primitives/choice, /primitives/noul, /concepts/state,
  /concepts/how-to-build-with-system-one, /confidence.md, /models.md, /model-jaggedness/jev-1.13.md,
  /cookbooks/rerank_typesafe.md, /cookbooks/skill_suggestion.md
- OpenAI Decisions guide, https://developers.openai.com/api/docs/guides/decisions
- Microsoft-Decision-1: https://www.eesel.ai/blog/microsoft-decision-1, https://www.marktechpost.com/2026/10/09/microsoft-ai-releases-microsoft-decision-1-a-qwen3-5-9b-decision-scoring-model/
- Perplexity Decisions API, https://docs.perplexity.ai/docs/decisions/quickstart; X post by @perplexitydevs on v1.2
- 14-model test, https://dev.to/akartit/microsoft-decision-1-vs-every-decision-model-on-openrouter-6th-of-14-42l1
- AA Decision Index snapshot, https://benchlm.ai/benchmarks/artificial-analysis-decision-index;
  Decision Index 0.3, https://benchlm.ai/benchmarks/decisionindex
- Liquid d1-ultra, https://www.liquid.ai/blog/d1-ultra; Cloudflare Clef, https://blog.cloudflare.com/clef-faster-cheaper-multimodal
- Nace Drex v2.0, https://huggingface.co/nace-ai/drex-v2.0; Kev, https://openrouter.ai/jaredpalmer/kev-4b (search listing)
- Laya model card, https://huggingface.co/convaiinnovations/laya
- Firecrawl, OpenAI Decisions vs Jev, https://www.firecrawl.dev/blog/openai-decisions-api-vs-jev
