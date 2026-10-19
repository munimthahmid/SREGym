# jev_diag v2: full working backup (2026-10-19)

Everything needed to continue the v2 work on another machine. The repository around this folder is the `v2-eval`
branch: the v2 pipeline (`clients/jev_diag/v2/`, identical to the PR branch `feat/jev-diag-v2`) plus the evaluation
harness (`clients/jev_diag/v2_eval/`). No API key is included; put the OpenRouter key in `~/.config/openrouter/key`.

| Folder | What it holds |
|---|---|
| `docs/` | Plan and analysis: `README.md`, `STRATEGY.md`, `IMPLEMENTATION.md` (log of every step), `PREREG.md` (evaluation plan, freeze), reviews (`review/`, `review2/`), `runs-index.tsv` (original paths) |
| `runs/` | Run scripts (`run-set2.sh` live sets, `replay-parallel.sh` offline replays, `start-unseen.sh`), `HOME-SETUP.md`, run logs, `runs.txt`, live results (`results/<set>/<problem>/`), offline replays (`replays/`) |
| `recordings/` | The saved kubectl recordings of 81 earlier runs, with `recordings/runs-index.tsv` pointing at them (paths relative to the repository root) for `clients.jev_diag.v2_eval.replay_arms --index backup/recordings/runs-index.tsv` |
| `sealed/` | The Unseen test list (`UNSEEN-15.txt`, sha256 of the sorted list 32c2634f...) and the unredacted benchmark landscape |

State at backup time: v2 frozen at `eade3b0a`; 29-fault offline replay v2 Jev 27-28 / Luna 28 of 29 vs v1 22 / 24; live
hard cases in progress, then Unseen 15 (1 live run each). Lite 15 is meant for the home laptop (`runs/HOME-SETUP.md`).
