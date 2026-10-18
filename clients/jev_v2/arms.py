"""Several diagnosers on one collected snapshot, in one benchmark run (`--mode arms`).

JEV_ARMS lists the arms as `kind=model` pairs, comma-separated, e.g.
`v1=openrouter/typesafe/jev-1.13,v1=openrouter/openai/gpt-6-luna-decisions,v2=...,v2=...` (kind: v1 = the team's
decision tree, v2 = jev_v2). Each arm gets its own copy of the snapshot and its own client; component detail is
read live by each arm. The arm order is shuffled per problem so no arm always runs first. Every arm's text,
requests, tokens, cost and time are saved to `<prefix>_arms.json`; the arm at JEV_ARMS_SUBMIT (default 0) is the
one submitted, and all arms are graded afterwards by `clients.jev_v2.grade` with the same judge.
"""

from __future__ import annotations

import copy
import json
import logging
import os
import random
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

from clients.jev_diag.classifier import make_client
from clients.jev_diag.investigate import collect_component_detail
from clients.jev_diag.tree import IterativeDiagnoser
from clients.jev_v2.agent import V2Diagnoser

logger = logging.getLogger("all.jev_v2.arms")

ARMS_ENV = "JEV_ARMS"
SUBMIT_ENV = "JEV_ARMS_SUBMIT"


def parse_arms(spec: str) -> list[tuple[str, str]]:
    """'v1=model,v2=model' -> [('v1', 'model'), ('v2', 'model')]; kinds other than v1/v2 are rejected."""
    arms = []
    for part in [p.strip() for p in spec.split(",") if p.strip()]:
        kind, _, model = part.partition("=")
        if kind not in ("v1", "v2") or not model:
            raise ValueError(f"bad arm {part!r}; expected v1=<model> or v2=<model>")
        arms.append((kind, model))
    if not arms:
        raise ValueError(f"{ARMS_ENV} names no arms")
    return arms


def run_arms(
    snapshot: Any,
    *,
    problem_id: str,
    prefix: Path,
    trace: Any,
    submit: Callable[[str], Any] | None,
    max_steps: int,
    state_token_budget: int,
) -> dict:
    """Run every arm, save their results, submit the chosen one. Returns the arms summary."""
    arms = parse_arms(os.environ.get(ARMS_ENV, ""))
    submit_index = int(os.environ.get(SUBMIT_ENV, "0"))
    order = list(range(len(arms)))
    random.Random(problem_id).shuffle(order)
    results: list[dict] = [{} for _ in arms]
    for i in order:
        kind, model = arms[i]
        client = make_client(model)
        if kind == "v2":
            diagnoser = V2Diagnoser(
                client, fetch_detail=collect_component_detail, state_token_budget=state_token_budget, trace=trace
            )
        else:
            diagnoser = IterativeDiagnoser(
                client,
                fetch_detail=collect_component_detail,
                max_steps=max_steps,
                state_token_budget=state_token_budget,
                trace=trace,
            )
        trace.record("arm", "start", arm=i, kind=kind, model=model)
        started = time.monotonic()
        text, error, investigation = "", None, None
        try:
            diagnosis = diagnoser.diagnose(copy.deepcopy(snapshot))
            text, investigation = diagnosis.text, diagnosis.investigation
        except Exception as exc:  # noqa: BLE001 - one arm failing must not stop the others
            error = f"{type(exc).__name__}: {exc}"
            logger.error("arm %d (%s %s) failed: %s", i, kind, model, error)
        results[i] = {
            "arm": i,
            "kind": kind,
            "model": model,
            "position": order.index(i),
            "seconds": round(time.monotonic() - started, 1),
            "requests": len(diagnoser.requests),
            "input_tokens": sum((r.get("usage") or {}).get("input_tokens") or 0 for r in diagnoser.requests),
            "cost_usd": round(getattr(client, "total_cost", 0.0) or 0.0, 6),
            "error": error,
            "investigation": investigation,
            "text": text,
        }
        (prefix.with_name(f"{prefix.name}_arm{i}_{kind}_requests.json")).write_text(
            json.dumps(diagnoser.requests, indent=1, default=str), encoding="utf-8"
        )
        trace.record("arm", "done", arm=i, seconds=results[i]["seconds"], error=error)
    summary = {"problem_id": problem_id, "submit_arm": submit_index, "order": order, "arms": results}
    submission = None
    if submit is not None:
        text = results[submit_index]["text"] or next((r["text"] for r in results if r["text"]), "")
        try:
            submission = submit(text)
        except Exception as exc:  # noqa: BLE001 - the arms are still worth recording
            summary["submission_error"] = f"{type(exc).__name__}: {exc}"
    summary["submission"] = submission
    (prefix.with_name(prefix.name + "_arms.json")).write_text(
        json.dumps(summary, indent=1, default=str), encoding="utf-8"
    )
    return summary
