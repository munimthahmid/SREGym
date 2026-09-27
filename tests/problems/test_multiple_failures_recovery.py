from types import SimpleNamespace

import pytest

from sregym.conductor.problems import multiple_failures
from sregym.conductor.problems.base import Problem
from sregym.conductor.problems.multiple_failures import MultipleIndependentFailures
from sregym.utils.decorators import mark_fault_injected


class ChildProblem(Problem):
    def __init__(self, namespace, recovered, *, fail_recovery=False, fail_injection=False):
        super().__init__(SimpleNamespace(namespace=namespace))
        self.recovered = recovered
        self.fail_recovery = fail_recovery
        self.fail_injection = fail_injection

    @mark_fault_injected
    def inject_fault(self):
        if self.fail_injection:
            raise RuntimeError("partial injection")

    @mark_fault_injected
    def recover_fault(self):
        self.recovered.append(self.namespace)
        if self.fail_recovery:
            raise RuntimeError(f"cannot recover {self.namespace}")


def compound(children, monkeypatch):
    monkeypatch.setattr(multiple_failures.time, "sleep", lambda _seconds: None)
    problem = MultipleIndependentFailures.__new__(MultipleIndependentFailures)
    Problem.__init__(problem, SimpleNamespace(namespace="compound"))
    problem.problems = children
    problem.namespaces = [child.namespace for child in children]
    return problem


@pytest.mark.parametrize("failed", [(), (0,), (0, 1)])
def test_recovery_attempts_every_child_and_reports_all_failures(monkeypatch, failed):
    recovered = []
    children = [ChildProblem(f"app-{i}", recovered, fail_recovery=i in failed) for i in range(3)]
    problem = compound(children, monkeypatch)
    problem.inject_fault()

    if failed:
        with pytest.raises(RuntimeError) as error:
            problem.recover_fault()
        for i in failed:
            assert f"cannot recover app-{i}" in str(error.value)
    else:
        problem.recover_fault()

    assert recovered == ["app-0", "app-1", "app-2"]
    assert problem.fault_injected is bool(failed)
    assert [child.fault_injected for child in children] == [i in failed for i in range(3)]


def test_recovery_after_partial_injection_does_not_require_success_metadata(monkeypatch):
    recovered = []
    children = [ChildProblem("first", recovered), ChildProblem("second", recovered, fail_injection=True)]
    problem = compound(children, monkeypatch)
    with pytest.raises(RuntimeError, match="partial injection"):
        problem.inject_fault()

    problem.recover_fault()

    assert recovered == ["first", "second"]
    assert problem.fault_injected is False
    assert all(not child.fault_injected for child in children)
