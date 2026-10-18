"""jev_v2 arms mode: arm parsing and one run over several arms with stand-in clients."""

import json
from types import SimpleNamespace

import pytest

from clients.jev_v2 import arms


def test_parse_arms_accepts_v1_v2_pairs_and_rejects_the_rest():
    assert arms.parse_arms("v1=openrouter/a, v2=openrouter/b") == [("v1", "openrouter/a"), ("v2", "openrouter/b")]
    with pytest.raises(ValueError):
        arms.parse_arms("v3=x")


def test_every_arm_runs_on_its_own_copy_and_the_chosen_one_is_submitted(tmp_path, monkeypatch):
    monkeypatch.setenv(arms.ARMS_ENV, "v1=m1,v2=m2")
    monkeypatch.setenv(arms.SUBMIT_ENV, "1")
    seen = []

    class Fake:
        def __init__(self, client, **_):
            self.requests = [{"usage": {"input_tokens": 10}}]
            self.client = client

        def diagnose(self, snap):
            snap.components["x"] = "touched"  # an arm may mutate its copy
            seen.append(self.client)
            return SimpleNamespace(text=f"text from {self.client}", investigation={})

    monkeypatch.setattr(arms, "make_client", lambda model: model)
    monkeypatch.setattr(arms, "V2Diagnoser", Fake)
    monkeypatch.setattr(arms, "IterativeDiagnoser", Fake)
    snapshot = SimpleNamespace(components={})
    submitted = []
    trace = SimpleNamespace(record=lambda *a, **k: None)
    arms.run_arms(
        snapshot,
        problem_id="p",
        prefix=tmp_path / "run",
        trace=trace,
        submit=submitted.append,
        max_steps=5,
        state_token_budget=100,
    )
    assert sorted(seen) == ["m1", "m2"] and snapshot.components == {}
    assert submitted == ["text from m2"]
    assert json.loads((tmp_path / "run_arms.json").read_text())["arms"][0]["input_tokens"] == 10
