"""Live arms (`--mode arms`): v1 and v2 read the cluster at the same moment, then each arm (kind=model in
JEV_ARMS) diagnoses its own pipeline's snapshot. The arm at JEV_ARMS_SUBMIT (default 0) is submitted; every arm's
text and requests are saved to `<prefix>_arms.json` and `<prefix>_armN_<kind>_requests.json` for grading."""

from __future__ import annotations

import argparse
import copy
import json
import logging
import os
import random
import time
from pathlib import Path
from types import ModuleType

from clients.jev_diag.trace import DecisionTrace
from clients.jev_diag.v2_eval import arm_record, openrouter_client, parse_arms

logger = logging.getLogger("all.jev_diag.v2_eval.arms")


def run(
    args: argparse.Namespace, trace: DecisionTrace, prefix: Path, results: dict, started: float, host: ModuleType
) -> str:
    from clients.jev_diag import collector as v1_collector
    from clients.jev_diag import trend as v1_trend
    from clients.jev_diag.investigate import collect_component_detail as v1_detail
    from clients.jev_diag.tree import IterativeDiagnoser as V1Diagnoser
    from clients.jev_diag.v2 import driver as v2_driver

    arms = parse_arms(os.environ.get("JEV_ARMS", ""))
    submit_index = int(os.environ.get("JEV_ARMS_SUBMIT", "0"))
    with trace.timed("setup", "wait_for_stage") as info:
        stage = host.wait_for_stage(args.wait_timeout)
        info["stage"] = stage
    if stage != "diagnosis":
        return "skipped_stage"
    with trace.timed("setup", "get_app"):
        app_info = host.get_app_info()
    trace.record("setup", "app_info", source="conductor", app_info=app_info)
    problem_id = results.get("problem_id") or "problem"

    # v1's schedule for both pipelines, so both read the same moment of the fault
    delay = max(0.0, args.start_delay)
    interval = max(0.0, args.trend_interval if args.trend_interval is not None else host.DEFAULT_TREND_INTERVAL)
    if delay - interval > 0:
        time.sleep(delay - interval)
    baseline = None
    if interval > 0:
        baseline = v1_trend.collect_sample(list(app_info.get("namespaces") or [app_info.get("namespace")]))
        time.sleep(interval)
    snapshots = {
        "v1": v1_collector.collect_snapshot(
            app_info,
            log_tail=args.log_tail,
            alerts_fetcher=None if args.no_alerts else v1_collector.fetch_alerts_via_mcp,
            include_logs=not args.no_logs,
            trend_baseline=copy.deepcopy(baseline),
        ),
        "v2": v2_driver.read_cluster(args, app_info, trace, False, copy.deepcopy(baseline)),
    }
    for kind, snap in snapshots.items():
        host.write_json(
            prefix.with_name(f"{prefix.name}_{kind}_snapshot.json"),
            {
                **snap.to_state(include_private=True),
                "collection_errors": snap.errors,
                "collected_at": snap.collected_at,
            },
        )

    order = list(range(len(arms)))
    random.Random(problem_id).shuffle(order)
    records: list[dict] = [{} for _ in arms]
    for position, i in enumerate(order):
        kind, model = arms[i]
        diagnoser, diagnosis, error = None, None, None
        t0 = time.monotonic()
        trace.record("arm", "start", arm=i, kind=kind, model=model)
        try:
            client = openrouter_client(model)
            if kind == "v2":
                diagnoser = v2_driver.make_diagnoser(args, trace, client)
            else:
                diagnoser = V1Diagnoser(
                    client,
                    fetch_detail=v1_detail,
                    max_steps=args.max_steps,
                    state_token_budget=args.state_token_budget,
                    trace=trace,
                )
            diagnosis = diagnoser.diagnose(copy.deepcopy(snapshots[kind]))
        except Exception as exc:  # noqa: BLE001 - one arm failing must not stop the others
            error = f"{type(exc).__name__}: {exc}"
            logger.error("arm %d (%s %s) failed: %s", i, kind, model, error)
        records[i] = arm_record(i, kind, model, position, time.monotonic() - t0, diagnoser, error, diagnosis)
        if diagnoser is not None:
            prefix.with_name(f"{prefix.name}_arm{i}_{kind}_requests.json").write_text(
                json.dumps(diagnoser.requests, indent=1, default=str), encoding="utf-8"
            )
        trace.record("arm", "done", arm=i, seconds=records[i]["seconds"], error=error)

    summary = {"problem_id": problem_id, "submit_arm": submit_index, "order": order, "arms": records}
    text = records[submit_index]["text"] or next((r["text"] for r in records if r["text"]), "")
    try:
        summary["submission"] = host.submit_diagnosis(text)
    except Exception as exc:  # noqa: BLE001 - the arms are still worth recording
        summary["submission_error"] = f"{type(exc).__name__}: {exc}"
    prefix.with_name(prefix.name + "_arms.json").write_text(
        json.dumps(summary, indent=1, default=str), encoding="utf-8"
    )
    results.update({"success": True, "mode": "arms", "arms": records, "submission": summary.get("submission")})
    return "ok"
