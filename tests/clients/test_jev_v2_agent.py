"""jev_v2 diagnoser end to end with a stand-in decision model."""

from types import SimpleNamespace

from typesafe_sdk import ChoiceAnswer

from clients.jev_v2.agent import V2Diagnoser
from clients.jev_v2.decide import QUESTION


def snapshot():
    proxy = {
        "kind": "Deployment",
        "name": "frontend-proxy",
        "namespace": "shop",
        "healthy": False,
        "signals": ["CPU at its limit", "requests time out"],
        "template_changes": {
            "revision": "3",
            "changed_at": "2026-10-18T09:58:00+00:00",
            "changes": [
                "container envoy env WAF_RULE_REGEX added: ^([a-zA-Z]+)*$",
                "container envoy limits.cpu: unset -> 100m",
            ],
        },
    }
    return SimpleNamespace(
        app={"name": "shop", "namespaces": ["shop"]},
        components={"deployment/frontend-proxy": proxy},
        cluster={"symptom_onset": "2026-10-18T10:00:00+00:00"},
    )


class Client:
    """Answers each pick with the option whose text contains `prefer` (or none of these)."""

    def __init__(self, prefer):
        self.prefer = prefer

    def system_one(self, state, questions, **_):
        q = questions[QUESTION]
        label = next((lbl for lbl, text in q.criteria.items() if self.prefer in text), None)
        probs = {lbl: (0.9 if lbl == label else 0.1 / (len(q.criteria) - 1)) for lbl in q.criteria}
        choice = label or max(probs, key=probs.get)
        return SimpleNamespace(
            model="fake",
            usage=SimpleNamespace(input_tokens=100, output_tokens=0),
            answers={QUESTION: ChoiceAnswer(choice=choice, confidence=0.8, probabilities=probs)},
            choices={QUESTION: ChoiceAnswer(choice=choice, confidence=0.8, probabilities=probs)},
        )


def test_the_picked_change_is_reported_with_its_value():
    diag = V2Diagnoser(client=Client("change 'container envoy env WAF_RULE_REGEX")).diagnose(snapshot())
    assert diag.component == "deployment/frontend-proxy"
    assert "^([a-zA-Z]+)*$" in diag.text and "Confidence: low" not in diag.text
    assert diag.investigation["rounds"][0]["route"] == "accept" and len(diag.investigation["rounds"]) == 1


def test_none_of_these_reads_detail_then_submits_a_partial_marked_uncertain():
    read = []
    diagnoser = V2Diagnoser(
        client=Client("None of these"), fetch_detail=lambda snap, cid: read.append(cid) or {"events": []}
    )
    diag = diagnoser.diagnose(snapshot())
    assert read == ["deployment/frontend-proxy"]
    assert "not established" in diag.text and "Confidence: low" in diag.text
    assert diag.investigation["pattern"] == "partial"


def test_none_of_these_keeps_reading_components_not_read_yet():
    snap = snapshot()
    for name in ("cart", "orders-validator"):
        snap.components[f"deployment/{name}"] = {
            "kind": "Deployment",
            "name": name,
            "namespace": "shop",
            "healthy": False,
            "signals": ["pod phase Pending"],
        }
    snap.components["deployment/orders-validator"]["log_error_lines"] = 4
    read = []
    V2Diagnoser(client=Client("None of these"), fetch_detail=lambda s, cid: read.append(cid) or {}).diagnose(snap)
    assert sorted(read) == ["deployment/cart", "deployment/frontend-proxy", "deployment/orders-validator"]
    assert len(read) == len(set(read)) and read[0] == "deployment/frontend-proxy"  # most signals first, no rereads
