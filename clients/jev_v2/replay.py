"""Run jev_v2 offline on saved jev_diag snapshots, without a cluster.

    uv run python -m clients.jev_v2.replay <path/to/*_snapshot.json> [...] --model openrouter/typesafe/jev-1.13

Prints the explanations built, each decision round and the report. Component detail is not re-read (no cluster),
so "look closer" rounds end the loop; this checks explanation coverage and the model's pick on recorded evidence.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sregym_root = Path(__file__).resolve().parents[2]
if str(sregym_root) not in sys.path:
    sys.path.insert(0, str(sregym_root))

from clients.jev_diag.classifier import make_client  # noqa: E402
from clients.jev_diag.replay import load_snapshot  # noqa: E402
from clients.jev_v2.agent import V2Diagnoser  # noqa: E402
from clients.jev_v2.patterns import build_explanations  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("snapshots", nargs="+")
    parser.add_argument("--model", required=True, help="e.g. openrouter/typesafe/jev-1.13")
    parser.add_argument("--no-model", action="store_true", help="only list the explanations; make no requests")
    args = parser.parse_args()
    for path in args.snapshots:
        snapshot = load_snapshot(path)
        explanations = build_explanations(snapshot)
        print(f"== {path}\n{len(explanations)} explanations:")
        for e in explanations:
            print(f"  [{e.pattern}] {e.key}")
        if args.no_model:
            continue
        diag = V2Diagnoser(client=make_client(args.model)).diagnose(snapshot)
        for n, r in enumerate(diag.investigation["rounds"], start=1):
            top = sorted(r["probabilities"].items(), key=lambda kv: -kv[1])[:3]
            print(f"round {n}: route={r['route']} picks={r['picks']} top={json.dumps(top)}")
        print(diag.text, "\n")


if __name__ == "__main__":
    main()
