"""Results tables for the v2 evaluation, straight from the graded arms files.

    python3 report-results.py [set ...]      (default: hard hard_retry unseen unseen_retry lite lite_retry)

For each set: per problem, the Jev and OpenAI-Decisions scores for v1 and v2; pass counts; and over all ten models
the paired v1-vs-v2 pass comparison with an exact two-sided sign test (ties dropped). A retry set replaces the
original run of the same problem only when the original produced no answers (infrastructure failure).
"""

from __future__ import annotations

import glob
import json
import math
import os
import sys
from collections import defaultdict

R = os.path.dirname(os.path.abspath(__file__))
FOCUS = ("typesafe/jev-1.13", "openai/gpt-6-luna-decisions")
SHORT = {"typesafe/jev-1.13": "Jev", "openai/gpt-6-luna-decisions": "OpenAI"}


def load(set_name: str) -> dict[str, dict]:
    """problem -> {(kind, model): score}"""
    out = {}
    for f in glob.glob(os.path.join(R, "results", set_name, "*", "*_arms_graded.json")):
        d = json.load(open(f))
        out[d["problem_id"]] = {
            (a["kind"], a["model"].removeprefix("openrouter/")): float(a["grade"].get("accuracy") or 0) for a in d["arms"]
        }
    return out


def sign_test(wins: int, losses: int) -> float:
    n = wins + losses
    if n == 0:
        return 1.0
    k = min(wins, losses)
    p = sum(math.comb(n, i) for i in range(k + 1)) / 2**n
    return min(1.0, 2 * p)


def table(name: str, rows: dict[str, dict]) -> str:
    lines = [f"### {name} ({len(rows)} problems)", "", "| Problem | v1 Jev | v1 OpenAI | v2 Jev | v2 OpenAI |",
             "|---|---|---|---|---|"]
    passes = defaultdict(int)
    for p in sorted(rows):
        r = rows[p]
        cells = []
        for kind in ("v1", "v2"):
            for m in FOCUS:
                s = r.get((kind, m))
                cells.append("-" if s is None else f"{s:.0f}")
                passes[(kind, m)] += s is not None and s >= 70
        lines.append(f"| {p} | " + " | ".join(cells) + " |")
    lines.append("| **Passes** | " + " | ".join(f"**{passes[(k, m)]}**" for k in ("v1", "v2") for m in FOCUS) + " |")
    wins = losses = ties = 0
    for r in rows.values():
        for (kind, m), s in r.items():
            if kind != "v2" or ("v1", m) not in r:
                continue
            a, b = r[("v1", m)] >= 70, s >= 70
            wins += b and not a
            losses += a and not b
            ties += a == b
    lines += ["", f"All models, paired by problem and model: v2 passes where v1 fails {wins} times, the reverse "
              f"{losses} times ({ties} ties); exact sign test p = {sign_test(wins, losses):.3g}.", ""]
    return "\n".join(lines)


def main() -> None:
    sets = sys.argv[1:] or ["hard", "unseen", "lite"]
    for s in sets:
        rows = load(s)
        for extra in (f"{s}_retry", f"{s}_retry2"):
            for p, r in load(extra).items():
                if p not in rows:
                    rows[p] = r
        if rows:
            print(table(s, rows))


if __name__ == "__main__":
    main()
