"""Run configuration for the jev_diag agent. No SDK imports: main.py imports this at startup."""

from __future__ import annotations

import os

from clients.jev.config import KEY_ENV, MODEL_ENV

AGENT_NAME = "jev_diag"
DEFAULT_MODEL = "jev-latest"
OPENROUTER_PREFIX = "openrouter/"  # e.g. openrouter/typesafe/jev-1.13, openrouter/openai/gpt-6-luna-decisions
OPENROUTER_KEY_ENV = "OPENROUTER_API_KEY"


def is_openrouter(model: str | None) -> bool:
    """Whether `model` is served through OpenRouter's Decisions endpoint instead of TypeSafe directly."""
    return bool(model) and model.startswith(OPENROUTER_PREFIX)


def configure(args) -> None:
    """Take the Jev model from ``--model`` for ``--agent jev_diag`` and reject unsupported runs early.

    The model goes into AGENT_JEV_MODEL, the variable ``--jev-model`` sets for Codex decision support.
    The container runner forwards TYPESAFE_API_KEY only while it is set, so other runs never receive the
    key. Because ``--model`` names a Jev model here, the judge needs its own ``--judge-model``.
    """
    if getattr(args, "agent", None) != AGENT_NAME or getattr(args, "use_external_harness", False):
        return
    model = (getattr(args, "model", None) or DEFAULT_MODEL).strip()
    if not model:
        raise ValueError("--model must name a Jev model for --agent jev_diag")
    if not getattr(args, "judge_model", None):
        raise ValueError("--agent jev_diag takes the Jev model from --model; set the judge's model with --judge-model")
    if not getattr(args, "force_build", False):
        # The agent runs from the released image unless rebuilt, which would not contain this code.
        raise ValueError("--agent jev_diag currently requires --force-build")
    key_env = OPENROUTER_KEY_ENV if is_openrouter(model) else KEY_ENV
    if not os.environ.get(key_env, "").strip():
        raise ValueError(f"--agent jev_diag with model {model} requires {key_env}")
    args.model = model
    os.environ[MODEL_ENV] = model


def jev_model() -> str | None:
    """The Jev model for this run.

    main.py sets AGENT_JEV_MODEL from ``--model`` for ``--agent jev_diag``. A standalone run falls back
    to TYPESAFE_DEFAULT_MODEL and then to the SDK default (jev-latest).
    """
    return os.getenv(MODEL_ENV) or os.getenv("TYPESAFE_DEFAULT_MODEL") or None
