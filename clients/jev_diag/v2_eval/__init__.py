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


# Models whose context window is smaller than the default state budgets need: (triage, investigation) token budgets
# that leave room for the questions. The same budget applies to v1 and v2.
SMALL_CONTEXT_BUDGETS = {"cloudflare/clef": (9000, 9000), "cloudflare/clef-flash": (9000, 9000)}


# Models that accept at most this many options per choice question (their API rejects more).
OPTION_LIMITS = {"upstage/solar-decide": 26}


def fit_to_model(diagnoser, model: str) -> None:
    model = model.removeprefix("openrouter/")
    if diagnoser is not None and model in OPTION_LIMITS:
        diagnoser.max_choice_options = OPTION_LIMITS[model]  # used by v2; v1 has no such setting
    budgets = SMALL_CONTEXT_BUDGETS.get(model)
    if budgets and diagnoser is not None:
        diagnoser.state_token_budget = budgets[0]
        if hasattr(diagnoser, "detail_token_budget"):
            diagnoser.detail_token_budget = budgets[1]


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
        "model_failed": "decision model"
        in str(((getattr(diagnosis, "investigation", None) or {}).get("fallback")) or ""),
        "component": getattr(diagnosis, "component", None),
        "investigation": getattr(diagnosis, "investigation", None),
        "text": getattr(diagnosis, "text", "") or "",
    }
