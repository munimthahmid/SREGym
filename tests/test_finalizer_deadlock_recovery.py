from unittest.mock import Mock

import pytest
from kubernetes.client.rest import ApiException

from sregym.conductor.problems.finalizer_deadlock_controller import FinalizerDeadlockController


def _problem(deleted):
    problem = FinalizerDeadlockController.__new__(FinalizerDeadlockController)
    problem.namespace = "hotel-reservation"
    problem.clusterrole_name = "configmap-cleanup-controller"
    problem.configmap_name = "reservation-cleanup-token"
    problem.fault_injected = True
    problem.kubectl = Mock()
    problem._restore_clusterrole = Mock()
    problem._force_clear_finalizer = Mock()
    problem._wait_until_configmap_deleted = Mock(side_effect=deleted)
    return problem


def test_recovery_leaves_finalizer_removal_to_a_working_controller():
    problem = _problem([True])
    problem.recover_fault()
    problem._restore_clusterrole.assert_called_once()
    problem._force_clear_finalizer.assert_not_called()
    problem.kubectl.core_v1_api.delete_namespaced_config_map.assert_not_called()
    assert problem.fault_injected is False


def test_recovery_clears_stuck_finalizers_when_the_controller_cannot_finish():
    problem = _problem([False, True])
    problem.recover_fault()
    problem._force_clear_finalizer.assert_called_once()
    assert problem.fault_injected is False


def test_recovery_deletes_a_configmap_left_by_partial_injection():
    problem = _problem([])
    configmap = {"exists": True, "finalizers": ["cleanup.reservations.io/pending-cleanup"]}
    problem._wait_until_configmap_deleted.side_effect = lambda **kwargs: not configmap["exists"]
    problem._force_clear_finalizer.side_effect = lambda: configmap.update(finalizers=[])

    def delete(*args, **kwargs):
        if not configmap["finalizers"]:
            configmap["exists"] = False

    problem.kubectl.core_v1_api.delete_namespaced_config_map.side_effect = delete
    problem.recover_fault()
    assert configmap["exists"] is False


def test_recovery_tolerates_configmap_deletion_during_finalizer_removal():
    problem = _problem([False, True])
    problem.kubectl.core_v1_api.delete_namespaced_config_map.side_effect = ApiException(status=404)
    problem.recover_fault()
    assert problem.fault_injected is False


@pytest.mark.parametrize("failure", ["patch", "delete_request", "deletion"])
def test_failed_finalizer_cleanup_propagates_and_preserves_fault_state(failure):
    problem = _problem([False, False])
    if failure == "patch":
        problem._force_clear_finalizer.side_effect = RuntimeError("patch failed")
    elif failure == "delete_request":
        problem.kubectl.core_v1_api.delete_namespaced_config_map.side_effect = RuntimeError("delete failed")
    with pytest.raises((RuntimeError, TimeoutError)):
        problem.recover_fault()
    assert problem.fault_injected is True
