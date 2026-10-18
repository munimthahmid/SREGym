"""OpenRouter Decisions client for jev_diag: wire format, answers, retries, errors and model routing."""

import io
import json
import urllib.error
from types import SimpleNamespace

import pytest
from typesafe_sdk import Choice, ChoiceAnswer, Noul, NoulAnswer

from clients.jev_diag import classifier, config
from clients.jev_diag.openrouter import OpenRouterClient, OpenRouterError

QUESTIONS = {
    "verdict": Choice(instructions={"question": "origin?"}, criteria={"origin": {"what": "here"}, "victim": "there"}),
    "blocked": Noul(instructions="stuck on one item?", criteria={"true": "yes", "false": "no"}),
}
ANSWERS = {
    "model": "openai/gpt-6-luna-decisions-20261006",
    "answers": {
        "verdict": {
            "type": "choice",
            "choice": "origin",
            "probabilities": {"origin": 0.8, "victim": 0.2},
            "confidence": 0.6,
        },
        "blocked": {"type": "noul", "noul": 0.1},
    },
    "usage": {"input_tokens": 300, "output_tokens": 0, "cost": 3e-05},
}


class _Resp(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return None


def _opener(*outcomes):
    """A urlopen stand-in that records requests and returns or raises each outcome in turn."""
    calls = []

    def open_(request, timeout):
        calls.append(request)
        outcome = outcomes[len(calls) - 1]
        if isinstance(outcome, Exception):
            raise outcome
        return _Resp(json.dumps(outcome).encode())

    return open_, calls


def _http_error(code, body=b'{"error": "nope"}', headers=None):
    return urllib.error.HTTPError("u", code, "err", headers or {}, io.BytesIO(body))


class _SlowBody(io.BytesIO):
    def read(self, *_):
        raise TimeoutError("read timed out")


@pytest.fixture(autouse=True)
def _key(monkeypatch):
    monkeypatch.setenv("OPENROUTER_API_KEY", "sk-test")


def test_sends_jev_wire_format_and_parses_answers():
    open_, calls = _opener(ANSWERS)
    client = OpenRouterClient("openrouter/openai/gpt-6-luna-decisions", opener=open_)
    response = client.system_one({"candidate": "rate"}, QUESTIONS)

    body = json.loads(calls[0].data)
    assert body["model"] == "openai/gpt-6-luna-decisions"
    assert body["questions"]["verdict"]["type"] == "choice"
    assert body["questions"]["blocked"] == {
        "type": "noul",
        "instructions": "stuck on one item?",
        "criteria": {"true": "yes", "false": "no"},
    }
    assert calls[0].get_header("Authorization") == "Bearer sk-test"
    assert response.choices["verdict"] == ChoiceAnswer(
        choice="origin", confidence=0.6, probabilities={"origin": 0.8, "victim": 0.2}
    )
    assert response.nouls["blocked"] == NoulAnswer(noul=0.1)
    assert response.usage.input_tokens == 300
    assert client.last_cost == pytest.approx(3e-05)


def test_missing_answer_is_an_error():
    partial = {**ANSWERS, "answers": {"verdict": ANSWERS["answers"]["verdict"]}}
    open_, _ = _opener(partial)
    with pytest.raises(OpenRouterError, match="no answer for blocked"):
        OpenRouterClient("openrouter/typesafe/jev-1.13", opener=open_).system_one({}, QUESTIONS)


def test_retries_honor_retry_after_and_unreadable_error_bodies():
    slow = urllib.error.HTTPError("u", 503, "err", {}, _SlowBody())
    open_, calls = _opener(_http_error(429, headers={"Retry-After": "5"}), slow, ANSWERS)
    sleeps = []
    client = OpenRouterClient("openrouter/typesafe/jev-1.13", opener=open_, sleep=sleeps.append)
    assert client.system_one({}, QUESTIONS).choices["verdict"].choice == "origin"
    assert len(calls) == 3 and sleeps == [5.0, 2.0]


def test_retry_budget_stops_retrying():
    now = [0.0]
    open_, calls = _opener(_http_error(429, headers={"Retry-After": "50"}), ANSWERS)
    client = OpenRouterClient(
        "openrouter/typesafe/jev-1.13", opener=open_, sleep=lambda s: None, clock=lambda: now[0], retry_budget=30
    )
    with pytest.raises(OpenRouterError, match="HTTP 429"):
        client.system_one({}, QUESTIONS)
    assert len(calls) == 1


def test_errors_never_contain_the_key(monkeypatch):
    echoed = b'{"error": "bad key sk-test and sk-or-v1-0123456789abcdef"}'
    open_, calls = _opener(_http_error(400, body=echoed))
    with pytest.raises(OpenRouterError) as exc:
        OpenRouterClient("openrouter/typesafe/jev-1.13", opener=open_, sleep=lambda _: None).system_one({}, QUESTIONS)
    assert len(calls) == 1 and "HTTP 400" in str(exc.value)
    assert "sk-test" not in str(exc.value) and "0123456789abcdef" not in str(exc.value)

    monkeypatch.setenv("OPENROUTER_API_KEY", "sk-te\nst")
    with pytest.raises(OpenRouterError) as bad:
        OpenRouterClient("openrouter/typesafe/jev-1.13")
    assert "sk-te" not in str(bad.value)


def test_openrouter_models_need_the_openrouter_key(monkeypatch):
    monkeypatch.delenv("TYPESAFE_API_KEY", raising=False)
    monkeypatch.setenv("AGENT_JEV_MODEL", "")
    args = SimpleNamespace(
        agent="jev_diag",
        use_external_harness=False,
        model="openrouter/typesafe/jev-1.13",
        judge_model="j",
        force_build=True,
    )
    config.configure(args)
    assert config.jev_model() == "openrouter/typesafe/jev-1.13"
    assert isinstance(classifier.make_client(), OpenRouterClient)

    monkeypatch.delenv("OPENROUTER_API_KEY")
    with pytest.raises(ValueError, match="OPENROUTER_API_KEY"):
        config.configure(args)


def test_filtered_internet_allows_the_decision_endpoint():
    from sregym.service.internet_policy import InternetPolicy
    from sregym.service.provider_endpoints import provider_endpoint_rules

    def hosts(model):
        policy = InternetPolicy.from_mode("filtered", agent_name="jev_diag", model_id=model)
        return [rule.host for rule in provider_endpoint_rules(policy, {})]

    assert hosts("openrouter/openai/gpt-6-luna-decisions") == ["openrouter.ai"]
    assert hosts("jev-latest") == ["api.typesafe.ai"]
