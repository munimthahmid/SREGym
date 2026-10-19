"""Local experiment harness (not part of the pipeline): v1 and v2 on the same cluster state with several decision
models, live (`arms`) or from saved kubectl recordings (`replay_arms`), graded by SREGym's own judge (`grade`)."""

from __future__ import annotations

import os


def openrouter_client(model: str):
    """A decision-model client for `model` (an OpenRouter id such as typesafe/jev-1.13), via the team's
    OpenRouter Decisions backend. The key arrives as OPENROUTER_API_KEY (forwarded into agent containers)."""
    from clients.jev_diag.decisions_client import OPENROUTER_KEY_ENV, OpenRouterClient

    if not os.environ.get(OPENROUTER_KEY_ENV) and os.environ.get("OPENROUTER_API_KEY"):
        os.environ[OPENROUTER_KEY_ENV] = os.environ["OPENROUTER_API_KEY"]
    return OpenRouterClient(model.removeprefix("openrouter/"), timeout=float(os.getenv("JEV_DIAG_HTTP_TIMEOUT", "90")))


def parse_arms(spec: str) -> list[tuple[str, str]]:
    """'v1=model,v2=model' -> [('v1', 'model'), ('v2', 'model')]."""
    arms = []
    for part in [p.strip() for p in spec.split(",") if p.strip()]:
        kind, _, model = part.partition("=")
        if kind not in ("v1", "v2") or not model:
            raise ValueError(f"bad arm {part!r}; expected v1=<model> or v2=<model>")
        arms.append((kind, model))
    if not arms:
        raise ValueError("no arms given")
    return arms


def arm_record(i: int, kind: str, model: str, position: int, seconds: float, diagnoser, error, diagnosis) -> dict:
    return {
        "arm": i,
        "kind": kind,
        "model": model,
        "position": position,
        "seconds": round(seconds, 1),
        "requests": len(diagnoser.requests) if diagnoser else 0,
        "input_tokens": sum(
            (r.get("usage") or {}).get("input_tokens") or 0 for r in (diagnoser.requests if diagnoser else [])
        ),
        "error": error,
        "component": getattr(diagnosis, "component", None),
        "investigation": getattr(diagnosis, "investigation", None),
        "text": getattr(diagnosis, "text", "") or "",
    }
