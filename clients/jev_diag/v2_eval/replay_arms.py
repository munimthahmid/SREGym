"""Offline arms: replay saved kubectl recordings through v1 and v2 collection, ask each model, and write
`<out>/<label>_arms.json` files that `clients.jev_diag.v2_eval.grade` can grade. No cluster is read; component
detail reads are served from the recording when the original run made them. Alerts are not replayed (they did not
go through kubectl), for both pipelines alike.

    uv run python -m clients.jev_diag.v2_eval.replay_arms --index runs-index.tsv --labels lite6_x,held5_y \\
        --arms v1=typesafe/jev-1.13,v2=typesafe/jev-1.13 --out /tmp/replays
    (--no-model: collection only; prints each pipeline's top signals and changes)
"""

from __future__ import annotations

import argparse
import copy
import csv
import json
import os
import sys
import time
from pathlib import Path

sregym_root = Path(__file__).resolve().parents[3]
if str(sregym_root) not in sys.path:
    sys.path.insert(0, str(sregym_root))

from clients.jev_diag.v2_eval import arm_record, fit_to_model, openrouter_client, parse_arms  # noqa: E402

os.environ["JEV_DIAG_V2_TELEMETRY"] = "0"  # a replay must not read today's Prometheus into an old fault


def app_info_of(trace_path: Path) -> dict:
    with open(trace_path) as handle:
        for line in handle:
            rec = json.loads(line)
            if rec.get("phase") == "setup" and rec.get("event") == "app_info":
                return rec.get("app_info") or {}
    raise SystemExit(f"no app_info in {trace_path}")


def pipeline(kind: str):
    if kind == "v1":
        from clients.jev_diag import collector, trend
        from clients.jev_diag.investigate import collect_component_detail
        from clients.jev_diag.tree import IterativeDiagnoser
    else:
        from clients.jev_diag.v2 import collector, trend
        from clients.jev_diag.v2.investigate import collect_component_detail
        from clients.jev_diag.v2.tree import IterativeDiagnoser
    return collector, trend, collect_component_detail, IterativeDiagnoser


def replay_one(label: str, prefix: str, problem: str, arms: list[tuple[str, str]], out: Path | None, no_model: bool):
    from clients.jev_diag.collector import set_kubectl_replay

    bundle = Path(prefix + "_kubectl_raw.jsonl.gz")
    app_info = app_info_of(Path(prefix + "_trace.jsonl"))
    namespaces = list(app_info.get("namespaces") or [app_info.get("namespace")])
    snaps = {}
    for kind in sorted({k for k, _ in arms}):
        collector, trend, _, _ = pipeline(kind)
        set_kubectl_replay(str(bundle))
        try:
            baseline = trend.collect_sample(namespaces)
            snaps[kind] = collector.collect_snapshot(app_info, alerts_fetcher=None, trend_baseline=baseline)
        finally:
            set_kubectl_replay(None)
    if no_model:
        for kind, snap in snaps.items():
            print(f"== {label} [{kind}] onset={snap.cluster.get('symptom_onset')}")
            for change in (snap.cluster.get("recent_changes") or [])[:6]:
                print(f"   change: {str(change)[:200]}")
            for cid, comp in snap.components.items():
                if comp.get("signals"):
                    print(f"   {cid} {comp.get('evidence_kinds')}: {'; '.join(comp['signals'])[:220]}")
        return None
    records = []
    for i, (kind, model) in enumerate(arms):
        _, _, detail, Diagnoser = pipeline(kind)
        diagnoser, diagnosis, error = None, None, None
        t0 = time.monotonic()
        set_kubectl_replay(str(bundle))  # detail reads come from the recording too
        try:
            diagnoser = Diagnoser(openrouter_client(model), fetch_detail=detail)
            fit_to_model(diagnoser, model)
            diagnosis = diagnoser.diagnose(copy.deepcopy(snaps[kind]))
        except Exception as exc:  # noqa: BLE001
            error = f"{type(exc).__name__}: {exc}"
        finally:
            set_kubectl_replay(None)
        records.append(arm_record(i, kind, model, i, time.monotonic() - t0, diagnoser, error, diagnosis))
        if out and diagnoser is not None:
            (out / f"{label}_arm{i}_{kind}_requests.json").write_text(json.dumps(diagnoser.requests, default=str))
        print(f"{label:58s} arm{i} {kind} {model:32s} -> {records[-1]['component']} {error or ''}")
    summary = {"problem_id": problem, "source": label, "replay": True, "arms": records}
    if out:
        (out / f"{label}_arms.json").write_text(json.dumps(summary, indent=1, default=str))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--index", required=True, help="runs-index.tsv (label, problem, start, end, arms_json)")
    parser.add_argument("--labels", required=True, help="comma-separated run labels")
    parser.add_argument("--arms", default="v1=typesafe/jev-1.13,v2=typesafe/jev-1.13")
    parser.add_argument("--out", help="directory for *_arms.json and request files")
    parser.add_argument("--no-model", action="store_true", help="collection only")
    args = parser.parse_args()
    with open(args.index) as handle:
        rows = {r["label"]: r for r in csv.DictReader(handle, delimiter="\t")}
    out = Path(args.out) if args.out else None
    if out:
        out.mkdir(parents=True, exist_ok=True)
    arms = parse_arms(args.arms)
    for label in [x.strip() for x in args.labels.split(",") if x.strip()]:
        row = rows[label]
        replay_one(label, row["arms_json"].removesuffix("_arms.json"), row["problem"], arms, out, args.no_model)


if __name__ == "__main__":
    main()
