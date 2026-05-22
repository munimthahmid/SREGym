import contextlib
import shlex
import subprocess
import time

from kubernetes import client
from kubernetes.client.rest import ApiException

from sregym.conductor.oracles.mitigation import MitigationOracle

CONNTRACK_CMD = "cat /proc/sys/net/netfilter/nf_conntrack_count; cat /proc/sys/net/netfilter/nf_conntrack_max"


def read_node_conntrack_usage(kubectl, node_name: str) -> tuple[int, int]:
    if node_name.startswith("kind-"):
        output = subprocess.run(
            ["docker", "exec", node_name, "bash", "-lc", CONNTRACK_CMD],
            capture_output=True,
            check=True,
            text=True,
            timeout=10,
        ).stdout
    else:
        cmd = (
            f"kubectl debug node/{node_name} --quiet --attach=true --rm --image=busybox -- "
            f"chroot /host sh -c {shlex.quote(CONNTRACK_CMD)}"
        )
        output = kubectl.exec_command(cmd)

    values = [int(line.strip()) for line in output.splitlines() if line.strip().isdigit()]
    if len(values) < 2:
        raise RuntimeError(f"Could not parse conntrack usage from {node_name}: {output}")
    return values[0], values[1]


class ConntrackMitigationOracle(MitigationOracle):
    def __init__(self, problem, ratio_threshold: float = 0.70, probe_attempts: int = 20):
        super().__init__(problem=problem)
        self.core_v1 = client.CoreV1Api()
        self.ratio_threshold = ratio_threshold
        self.probe_attempts = probe_attempts

    def evaluate(self) -> dict:
        print("== Conntrack Mitigation Evaluation ==")
        results = super().evaluate()
        if not results.get("success"):
            return results

        node_name = self._victim_node()
        count, maximum = read_node_conntrack_usage(self.problem.kubectl, node_name)
        ratio = count / maximum if maximum else 1
        client_reduced = self._client_reduced()
        probe_ok = self._frontend_probe_succeeds(node_name)

        results.update(
            {
                "conntrack_ratio": ratio,
                "client_reduced": client_reduced,
                "frontend_probe": probe_ok,
                "success": ratio < self.ratio_threshold and client_reduced and probe_ok,
            }
        )
        print(f"Node {node_name} conntrack usage: {count}/{maximum} ({ratio:.2%})")
        return results

    def _victim_node(self) -> str:
        if getattr(self.problem, "victim_node", None):
            return self.problem.victim_node
        return self.problem.select_worker_nodes()[0]

    def _client_reduced(self) -> bool:
        try:
            dep = self.problem.kubectl.get_deployment(self.problem.client_deployment, self.problem.namespace)
            allowed = max(1, self.problem.client_replicas // 10)
            return (dep.spec.replicas or 0) <= allowed
        except ApiException as e:
            return e.status == 404

    def _frontend_probe_succeeds(self, node_name: str) -> bool:
        pod_name = f"frontend-conntrack-probe-{int(time.time())}"
        script = (
            f"ok=0; fail=0; for i in $(seq 1 {self.probe_attempts}); do "
            "wget -q -T 2 -O /dev/null http://frontend:5000/ && ok=$((ok+1)) || fail=$((fail+1)); "
            'sleep 0.1; done; echo "PROBE_OK=${ok} PROBE_FAIL=${fail}"; test "$fail" -le 1'
        )
        pod = {
            "metadata": {"name": pod_name, "namespace": self.problem.namespace, "labels": {"app": "conntrack-probe"}},
            "spec": {
                "restartPolicy": "Never",
                "automountServiceAccountToken": False,
                "nodeSelector": {"kubernetes.io/hostname": node_name},
                "containers": [{"name": "probe", "image": "busybox:1.36", "command": ["sh", "-c", script]}],
            },
        }
        try:
            self.core_v1.create_namespaced_pod(self.problem.namespace, pod)
            phase = self._wait_for_probe_pod(pod_name)
            logs = self.core_v1.read_namespaced_pod_log(pod_name, self.problem.namespace)
            print(logs.strip())
            return phase == "Succeeded"
        except ApiException:
            return False
        finally:
            with contextlib.suppress(ApiException):
                self.core_v1.delete_namespaced_pod(pod_name, self.problem.namespace, grace_period_seconds=0)

    def _wait_for_probe_pod(self, pod_name: str, timeout: int = 60) -> str:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            pod = self.core_v1.read_namespaced_pod(pod_name, self.problem.namespace)
            if pod.status.phase in ("Succeeded", "Failed"):
                return pod.status.phase
            time.sleep(1)
        return "Pending"
