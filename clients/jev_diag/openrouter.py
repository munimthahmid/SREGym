"""OpenRouter Decisions client: the slice of TypeSafeClient that jev_diag uses (`system_one`).

Selected by a model id with the ``openrouter/`` prefix, for example ``openrouter/typesafe/jev-1.13`` or
``openrouter/openai/gpt-6-luna-decisions``. The prefix also lets filtered internet access allow openrouter.ai.
Questions go over in Jev's wire format, which OpenRouter accepts for every Decisions model, and answers come back
as typesafe_sdk structs, so the rest of the pipeline is unchanged.
"""

from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from typing import Any

import msgspec
from typesafe_sdk import ChoiceAnswer, NoulAnswer, SystemOneResponse, Usage

from clients.jev_diag.config import OPENROUTER_KEY_ENV, OPENROUTER_PREFIX

URL_ENV = "OPENROUTER_DECISIONS_URL"
DEFAULT_URL = "https://openrouter.ai/api/alpha/decisions"
RETRY_STATUS = {408, 409, 429, 500, 502, 503, 504}
MAX_RETRY_WAIT = 60.0  # longest single wait, also for a server's Retry-After
_KEY_LIKE = re.compile(r"sk-[A-Za-z0-9_-]{8,}")


class OpenRouterError(RuntimeError):
    """A Decisions request that failed or returned an unusable answer."""


def parse_response(body: dict, questions: dict[str, Any]) -> SystemOneResponse:
    """OpenRouter's answers as a typesafe_sdk response; every asked question must be answered."""
    answers: dict[str, Any] = {}
    for name, item in (body.get("answers") or {}).items():
        try:
            answers[name] = _answer(item)
        except (AttributeError, KeyError, TypeError, ValueError):
            raise OpenRouterError(f"malformed answer for question {name!r}") from None
    missing = sorted(set(questions) - set(answers))
    if missing:
        raise OpenRouterError(f"no answer for {', '.join(missing)}")
    usage = body.get("usage") or {}
    return SystemOneResponse(
        model=str(body.get("model") or ""),
        usage=Usage(input_tokens=usage.get("input_tokens"), output_tokens=usage.get("output_tokens")),
        answers=answers,
    )


def _answer(item: dict) -> ChoiceAnswer | NoulAnswer:
    """One typed answer; raises on a missing field or an unknown type."""
    kind = item["type"]
    if kind == "choice":
        return ChoiceAnswer(
            choice=str(item["choice"]),
            confidence=float(item.get("confidence") or 0.0),
            probabilities={str(k): float(v) for k, v in (item.get("probabilities") or {}).items()},
        )
    if kind == "noul":
        return NoulAnswer(noul=float(item["noul"]))
    raise ValueError(kind)


class OpenRouterClient:
    """`system_one` over OpenRouter's Decisions endpoint, with retries on rate limits and server errors."""

    def __init__(
        self,
        model: str,
        *,
        timeout: float = 90.0,
        max_retries: int = 3,
        retry_budget: float = 240.0,
        opener: Callable[..., Any] = urllib.request.urlopen,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        """`model` may keep its ``openrouter/`` prefix; the key comes from OPENROUTER_API_KEY. `retry_budget`
        caps the seconds one call may spend across all its attempts, as v1's TypeSafe RetryPolicy did."""
        self.model = model.removeprefix(OPENROUTER_PREFIX)
        self.url = os.getenv(URL_ENV, DEFAULT_URL)
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_budget = retry_budget
        self._open = opener
        self._sleep = sleep
        self._clock = clock
        self._key = os.getenv(OPENROUTER_KEY_ENV, "").strip()
        if not self._key:
            raise OpenRouterError(f"{OPENROUTER_KEY_ENV} is not set")
        if not re.fullmatch(r"[\x21-\x7e]+", self._key):
            raise OpenRouterError(f"{OPENROUTER_KEY_ENV} contains spaces or non-printable characters")
        self.last_cost: float | None = None  # USD of the latest request, as OpenRouter reports it
        self.total_cost = 0.0

    def __enter__(self) -> OpenRouterClient:
        return self

    def __exit__(self, *_: Any) -> None:
        return None

    def system_one(self, state: Any, questions: dict[str, Any], **_: Any) -> SystemOneResponse:
        """Ask `questions` about `state` in one request."""
        payload = {
            "model": self.model,
            "state": msgspec.to_builtins(state),
            "questions": {name: msgspec.to_builtins(q) for name, q in questions.items()},
        }
        data = json.dumps(payload, ensure_ascii=False).encode()
        headers = {"Authorization": f"Bearer {self._key}", "Content-Type": "application/json"}
        deadline = self._clock() + self.retry_budget
        for attempt in range(self.max_retries + 1):
            remaining = deadline - self._clock()
            if remaining <= 0:
                break
            request = urllib.request.Request(self.url, data=data, headers=headers, method="POST")
            try:
                with self._open(request, timeout=min(self.timeout, remaining)) as resp:
                    body = json.loads(resp.read())
            except urllib.error.HTTPError as exc:
                detail = self._redact(_read_quietly(exc))
                wait = max(min(10.0, 2.0**attempt), _retry_after(exc))
                if exc.code in RETRY_STATUS and attempt < self.max_retries and self._can_wait(wait, deadline):
                    self._sleep(wait)
                    continue
                raise OpenRouterError(f"HTTP {exc.code} from {self.model}: {detail}") from None
            except Exception as exc:  # noqa: BLE001 - transport errors, timeouts, bad JSON
                wait = min(10.0, 2.0**attempt)
                if attempt < self.max_retries and self._can_wait(wait, deadline):
                    self._sleep(wait)
                    continue
                raise OpenRouterError(
                    f"{self.model} request failed: {self._redact(f'{type(exc).__name__}: {exc}')}"
                ) from None
            if body.get("error"):
                raise OpenRouterError(f"{self.model} returned an error: {self._redact(str(body['error']))}")
            cost = (body.get("usage") or {}).get("cost")
            self.last_cost = float(cost) if cost is not None else None
            self.total_cost += self.last_cost or 0.0
            return parse_response(body, questions)
        raise OpenRouterError(f"{self.model}: retry budget of {self.retry_budget:.0f}s used up")

    def _can_wait(self, wait: float, deadline: float) -> bool:
        """Whether a wait of `wait` seconds still leaves time for another attempt."""
        return self._clock() + wait < deadline

    def _redact(self, text: str) -> str:
        """`text` cut to 300 characters with the key, and anything shaped like a key, removed."""
        return _KEY_LIKE.sub("[redacted]", text.replace(self._key, "[redacted]"))[:300]


def _read_quietly(exc: urllib.error.HTTPError) -> str:
    """The error body, or "" when reading it fails (a timeout or a cut-off body)."""
    try:
        return exc.read(2000).decode(errors="replace")
    except Exception:  # noqa: BLE001
        return ""


def _retry_after(exc: urllib.error.HTTPError) -> float:
    """Seconds the server asks us to wait (Retry-After), capped; 0 when absent or unreadable."""
    try:
        return min(MAX_RETRY_WAIT, max(0.0, float((exc.headers or {}).get("Retry-After") or 0)))
    except (TypeError, ValueError):
        return 0.0
