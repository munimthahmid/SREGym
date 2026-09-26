from unittest.mock import Mock

import pytest

from sregym.conductor.problems.finalizer_deadlock_controller import FinalizerDeadlockController


def _problem(deleted):
    problem = FinalizerDeadlockController.__new__(FinalizerDeadlockController)
    problem.namespace = "hotel-reservation"
    problem.clusterrole_name = "configmap-cleanup-controller"
    problem.configmap_name = "reservation-cleanup-token"
    problem.fault_injected = True
    problem._restore_clusterrole = Mock()
    problem._force_clear_finalizer = Mock()
    problem._wait_until_configmap_deleted = Mock(side_effect=deleted)
    return problem


def test_recovery_leaves_finalizer_removal_to_a_working_controller():
    problem = _problem([True])
    problem.recover_fault()
    problem._restore_clusterrole.assert_called_once()
    problem._force_clear_finalizer.assert_not_called()
    assert problem.fault_injected is False


def test_recovery_clears_stuck_finalizers_when_the_controller_cannot_finish():
    problem = _problem([False, True])
    problem.recover_fault()
    problem._force_clear_finalizer.assert_called_once()
    assert problem.fault_injected is False


@pytest.mark.parametrize("failure", ["patch", "deletion"])
def test_failed_finalizer_cleanup_propagates_and_preserves_fault_state(failure):
    problem = _problem([False, False])
    if failure == "patch":
        problem._force_clear_finalizer.side_effect = RuntimeError("patch failed")
    with pytest.raises((RuntimeError, TimeoutError)):
        problem.recover_fault()
    assert problem.fault_injected is True
