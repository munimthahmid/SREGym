"""Grade every arm of `--mode arms` runs with SREGym's own diagnosis oracle (same checklist, same answer key).

    SREGYM_AGENT_IMAGE=sregym-agent-base:latest uv run python -m clients.jev_v2.grade \\
        --problem <problem_id> <path/to/*_arms.json> [--problem <id> <path> ...]

One judge bridge serves the whole batch. Results are written next to each input as `*_arms_graded.json`, and a
one-line summary per arm is printed. Needs the cluster (problems are instantiated to build their oracle).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sregym_root = Path(__file__).resolve().parents[2]
if str(sregym_root) not in sys.path:
    sys.path.insert(0, str(sregym_root))

from sregym.conductor.problems.registry import ProblemRegistry  # noqa: E402
from sregym.service.judge_runtime import managed_judge_backend  # noqa: E402


def pairs(argv: list[str]) -> list[tuple[str, Path]]:
    """`--problem ID PATH` repeated -> [(ID, PATH), ...]."""
    if not argv or len(argv) % 3 or any(argv[i] != "--problem" for i in range(0, len(argv), 3)):
        raise SystemExit("expected one or more: --problem <id> <arms.json>")
    return [(argv[i + 1], Path(argv[i + 2])) for i in range(0, len(argv), 3)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--judge-model", default="gpt-6-astra")
    parser.add_argument("--judge-backend", default="codex")
    parser.add_argument("--effort", default="high")
    args, rest = parser.parse_known_args()
    jobs = pairs(rest)
    os.environ["JUDGE_MODEL_ID"] = args.judge_model
    os.environ["JUDGE_REASONING_EFFORT"] = args.effort
    registry = ProblemRegistry()
    with managed_judge_backend(args.judge_backend, force_build=False):
        for problem_id, path in jobs:
            summary = json.loads(path.read_text(encoding="utf-8"))
            oracle = registry.get_problem_instance(problem_id).diagnosis_oracle
            for arm in summary["arms"]:
                arm["grade"] = oracle.evaluate(arm["text"]) if arm.get("text") else {"success": False, "accuracy": 0.0}
                g = arm["grade"]
                print(
                    f"{problem_id:52s} arm{arm['arm']} {arm['kind']} {arm['model']:42s} "
                    f"success={g.get('success')} accuracy={g.get('accuracy')}"
                )
            summary["judge"] = {"model": args.judge_model, "backend": args.judge_backend, "effort": args.effort}
            out = path.with_name(path.name.replace("_arms.json", "_arms_graded.json"))
            out.write_text(json.dumps(summary, indent=1, default=str), encoding="utf-8")


if __name__ == "__main__":
    main()
