# v2 diagnosis pipeline + Jev and Decision API run

## What this does
Adds a second version of the jev_diag diagnosis pipeline, in its own package next to v1, chosen with
`JEV_DIAG_MODE=v2`. v1 is unchanged.

v2 starts from v1 and keeps how v1 works. There is no language model inside the agent. The cluster is read with
kubectl, code turns what it reads into facts, decision models (Jev, or any model behind the Decisions API) only answer
typed questions over those facts, and code writes the final report.

On top of v1 it adds the following.
- A report that names the object holding the bad value with its relation to the workload (a ConfigMap through which a
  Deployment is broken, a policy acting on a workload, a job flooding a cache), instead of always naming a workload.
- More it can see. Objects outside the application's namespaces (Ingresses, PriorityClasses, kube-system), namespaces
  the application addresses, the same change made to several workloads, retry and timeout settings on a call path,
  addresses inside container commands, and metric and call facts from the existing jev_agent tools.
- Fewer false leads. Changes made while the application was being deployed and restarts no longer count as changes.
- Better decisions on hard cases. The first ranking is asked twice with the options reversed when it is not
  decisive; a login failure is settled by asking which side holds the stale value; a second independent cause is
  reported only when nothing links the two and each changed on its own.
- Robustness. Every question fits what the chosen decision model accepts, and if the model fails partway the
  answer from the work already done is still submitted.

## Results
Same cluster moment for v1 and v2, scored by SREGym's own judge (pass = 70). Shown for Jev 1.13 and OpenAI's
Decisions model; eight more decision models were run the same way and are in the results folder.

| Set | v1 Jev | v1 OpenAI | v2 Jev | v2 OpenAI |
|---|---|---|---|---|
| Unseen 15 (never looked at during development, live) | TBD | TBD | TBD | TBD |
| Lite (live) | TBD | TBD | TBD | TBD |
| 29 development faults (replayed recordings) | 22 / 29 | 24 / 29 | 27 / 29 | 28 / 29 |

## Things to know
- The judge is itself a model. Scoring the same report twice moves the score by about 10 points in some cases, so
  single-problem differences of that size are noise.
- In a live comparison v1 reads the cluster a few seconds before v2; on fast-changing logs this can give either side a
  slightly different picture.
- Development used 29 problems; the 15 Unseen problems were fixed by hash before any code was written and were never
  opened. The code was frozen before the Unseen run.

## Setup
No new settings are required. `JEV_DIAG_MODE=v2` selects the pipeline; `JEV_DIAG_V2_TELEMETRY=0` turns off the
metric facts and `JEV_DIAG_V2_PROBES=0` the read-only data store check.
