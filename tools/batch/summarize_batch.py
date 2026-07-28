#!/usr/bin/env python3
"""Summarize a batch run from logs/batch/<run_id>/ or run_results.json.

Reads each game_log JSON and groups metrics by case_id / rule_config.

Usage:
  python tools/batch/summarize_batch.py logs/batch/<run_id>/run_results.json
  python tools/batch/summarize_batch.py logs/batch/<run_id>
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def load_game(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"warn: cannot read {path}: {e}", file=sys.stderr)
        return None


def metrics_from_log(data: dict) -> dict:
    rounds = data.get("rounds") or []
    finished = [r for r in rounds if not r.get("_in_progress") and r.get("settlement")]
    scores = []
    levels = []
    dethrones = 0
    for r in finished:
        s = r.get("settlement") or {}
        if "final_score" in s:
            scores.append(int(s["final_score"]))
        if "upgrade_levels" in s:
            levels.append(int(s["upgrade_levels"]))
        if s.get("dealer_dethroned"):
            dethrones += 1

    rc = data.get("rule_config") or {}
    return {
        "round_count": len(finished),
        "in_progress_rounds": sum(1 for r in rounds if r.get("_in_progress")),
        "avg_final_score": round(statistics.mean(scores), 2) if scores else None,
        "avg_upgrade_levels": round(statistics.mean(levels), 2) if levels else None,
        "dethrone_rate": round(dethrones / len(finished), 3) if finished else None,
        "game_over": any((r.get("settlement") or {}).get("game_over") for r in finished),
        "rule_config": {
            "deck_count": rc.get("deck_count"),
            "upgrade_threshold": rc.get("upgrade_threshold"),
            "upgrade_step": rc.get("upgrade_step"),
            "allow_dump": rc.get("allow_dump"),
            "strict_follow_structure": rc.get("strict_follow_structure"),
            "no_skip_enabled": rc.get("no_skip_enabled"),
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("target", type=Path, help="run_results.json or batch run directory")
    args = ap.parse_args()

    target = args.target
    if not target.exists():
        alt = REPO / target
        if alt.exists():
            target = alt
        else:
            print(f"not found: {args.target}", file=sys.stderr)
            return 1

    if target.is_dir():
        results_path = target / "run_results.json"
        run_dir = target
    else:
        results_path = target
        run_dir = target.parent

    case_rows = []
    if results_path.is_file():
        results = json.loads(results_path.read_text(encoding="utf-8"))
        for case in results.get("cases", []):
            case_id = case["id"]
            game_metrics = []
            for g in case.get("games", []):
                log_rel = g.get("log") or ""
                log_path = REPO / log_rel if log_rel else None
                if log_path and log_path.is_file():
                    data = load_game(log_path)
                    if data:
                        m = metrics_from_log(data)
                        m["seed"] = g.get("seed")
                        m["ok"] = g.get("ok")
                        m["elapsed_sec"] = g.get("elapsed_sec")
                        game_metrics.append(m)
                else:
                    game_metrics.append(
                        {
                            "ok": g.get("ok", False),
                            "seed": g.get("seed"),
                            "elapsed_sec": g.get("elapsed_sec"),
                            "error": "missing_log",
                        }
                    )
            case_rows.append(
                {
                    "id": case_id,
                    "description": case.get("description", ""),
                    "overrides": case.get("overrides", {}),
                    "games": game_metrics,
                }
            )
    else:
        # scan directories
        for case_dir in sorted(p for p in run_dir.iterdir() if p.is_dir()):
            logs = sorted(case_dir.glob("game_*.json"))
            game_metrics = []
            for lp in logs:
                data = load_game(lp)
                if data:
                    game_metrics.append(metrics_from_log(data))
            case_rows.append({"id": case_dir.name, "description": "", "overrides": {}, "games": game_metrics})

    # Aggregate per case
    lines = ["# Batch summary", "", f"run_dir: `{run_dir}`", ""]
    lines.append("| case | n_ok | avg_rounds | avg_score | avg_levels | dethrone_rate | step | dump | notes |")
    lines.append("|------|------|------------|-----------|------------|---------------|------|------|-------|")

    summary_json = {"run_dir": str(run_dir), "cases": []}
    for case in case_rows:
        ok_games = [g for g in case["games"] if g.get("ok", True) and g.get("round_count") is not None]
        n_ok = len(ok_games)
        def avg(key):
            vals = [g[key] for g in ok_games if g.get(key) is not None]
            return round(statistics.mean(vals), 2) if vals else None

        rc = ok_games[0].get("rule_config", {}) if ok_games else {}
        row = {
            "id": case["id"],
            "description": case.get("description", ""),
            "overrides": case.get("overrides", {}),
            "n_ok": n_ok,
            "n_total": len(case["games"]),
            "avg_rounds": avg("round_count"),
            "avg_final_score": avg("avg_final_score"),
            "avg_upgrade_levels": avg("avg_upgrade_levels"),
            "avg_dethrone_rate": avg("dethrone_rate"),
            "rule_config": rc,
        }
        summary_json["cases"].append(row)
        lines.append(
            "| {id} | {n_ok}/{n_total} | {avg_rounds} | {avg_final_score} | {avg_upgrade_levels} | {avg_dethrone_rate} | {step} | {dump} | {desc} |".format(
                id=row["id"],
                n_ok=row["n_ok"],
                n_total=row["n_total"],
                avg_rounds=row["avg_rounds"],
                avg_final_score=row["avg_final_score"],
                avg_upgrade_levels=row["avg_upgrade_levels"],
                avg_dethrone_rate=row["avg_dethrone_rate"],
                step=rc.get("upgrade_step"),
                dump=rc.get("allow_dump"),
                desc=(case.get("description") or "")[:40],
            )
        )

    md = "\n".join(lines) + "\n"
    out_md = run_dir / "summary.md"
    out_json = run_dir / "summary.json"
    out_md.write_text(md, encoding="utf-8")
    out_json.write_text(json.dumps(summary_json, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(md)
    print(f"wrote {out_md}")
    print(f"wrote {out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
