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

sys.path.insert(0, str(REPO / "tools"))
from validate_game_log import (  # noqa: E402
    RuleConfig,
    Rules,
    force_utf8_stdout,
    parse_cards,
)


def lead_type_mix(data: dict) -> dict:
    """统计首出牌型分布 —— 覆盖率补充跑的核心指标。

    默认 simple 策略下 AI 只出单张，对子/拖拉机/甩牌规则分支全程不触发。
    这一列能直接看出某次批跑到底覆盖了多少牌型。
    """
    try:
        rules = Rules(RuleConfig.from_log(data))
    except Exception:
        return {}
    counts: dict[str, int] = {}
    for rd in data.get("rounds") or []:
        if not rd.get("settlement"):
            continue
        for trick in rd.get("tricks") or []:
            plays = trick.get("plays") or []
            if not plays:
                continue
            try:
                pattern = rules.identify(parse_cards(plays[0].get("cards", [])), rd["rank"])
            except Exception:
                continue
            if pattern:
                counts[pattern.kind] = counts.get(pattern.kind, 0) + 1
    return counts


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
        "lead_types": lead_type_mix(data),
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
    force_utf8_stdout()

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
                        v = g.get("validation")
                        if isinstance(v, dict):
                            m["valid"] = v.get("ok")
                            m["violations"] = v.get("errors", 0)
                            m["violation_codes"] = v.get("codes", [])
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
    lead_strategy = "simple"
    if results_path.is_file():
        try:
            lead_strategy = json.loads(
                results_path.read_text(encoding="utf-8")).get("lead_strategy", "simple")
        except (OSError, json.JSONDecodeError):
            pass

    lines = ["# Batch summary", "", f"run_dir: `{run_dir}`",
             f"lead_strategy: `{lead_strategy}`", ""]
    if lead_strategy != "simple":
        lines.append(
            "> ⚠ 本次使用非默认首出策略，**平衡指标（avg_score / dethrone_rate / "
            "avg_rounds）不可与 simple 基线直接对比**。它的用途是提升规则路径覆盖率。")
        lines.append("")
    lines.append("| case | n_ok | valid | avg_rounds | avg_score | avg_levels | dethrone_rate | 首出牌型 | step | dump | notes |")
    lines.append("|------|------|-------|------------|-----------|------------|---------------|----------|------|------|-------|")

    summary_json = {"run_dir": str(run_dir), "lead_strategy": lead_strategy, "cases": []}
    total_violations = 0
    violation_codes: dict[str, int] = {}
    overall_lead_types: dict[str, int] = {}
    for case in case_rows:
        ok_games = [g for g in case["games"] if g.get("ok", True) and g.get("round_count") is not None]
        n_ok = len(ok_games)
        def avg(key):
            vals = [g[key] for g in ok_games if g.get(key) is not None]
            return round(statistics.mean(vals), 2) if vals else None

        judged = [g for g in case["games"] if g.get("valid") is not None]
        n_valid = sum(1 for g in judged if g["valid"])
        for g in judged:
            total_violations += g.get("violations", 0)
            for code in g.get("violation_codes", []):
                violation_codes[code] = violation_codes.get(code, 0) + 1
        valid_cell = f"{n_valid}/{len(judged)}" if judged else "—"

        case_lead_types: dict[str, int] = {}
        for g in ok_games:
            for k, v in (g.get("lead_types") or {}).items():
                case_lead_types[k] = case_lead_types.get(k, 0) + v
                overall_lead_types[k] = overall_lead_types.get(k, 0) + v
        total_leads = sum(case_lead_types.values())
        if total_leads:
            mix = " ".join(
                f"{k[:3]}{100 * v // total_leads}%"
                for k, v in sorted(case_lead_types.items(), key=lambda kv: -kv[1])
            )
        else:
            mix = "—"

        rc = ok_games[0].get("rule_config", {}) if ok_games else {}
        row = {
            "id": case["id"],
            "description": case.get("description", ""),
            "overrides": case.get("overrides", {}),
            "n_ok": n_ok,
            "n_total": len(case["games"]),
            "n_valid": n_valid if judged else None,
            "n_judged": len(judged),
            "avg_rounds": avg("round_count"),
            "avg_final_score": avg("avg_final_score"),
            "avg_upgrade_levels": avg("avg_upgrade_levels"),
            "avg_dethrone_rate": avg("dethrone_rate"),
            "lead_types": case_lead_types,
            "rule_config": rc,
        }
        summary_json["cases"].append(row)
        lines.append(
            "| {id} | {n_ok}/{n_total} | {valid} | {avg_rounds} | {avg_final_score} | {avg_upgrade_levels} | {avg_dethrone_rate} | {mix} | {step} | {dump} | {desc} |".format(
                id=row["id"],
                n_ok=row["n_ok"],
                n_total=row["n_total"],
                valid=valid_cell,
                avg_rounds=row["avg_rounds"],
                avg_final_score=row["avg_final_score"],
                avg_upgrade_levels=row["avg_upgrade_levels"],
                avg_dethrone_rate=row["avg_dethrone_rate"],
                mix=mix,
                step=rc.get("upgrade_step"),
                dump=rc.get("allow_dump"),
                desc=(case.get("description") or "")[:40],
            )
        )

    summary_json["total_violations"] = total_violations
    summary_json["violation_codes"] = violation_codes
    summary_json["lead_types"] = overall_lead_types

    lines.append("")
    total_leads = sum(overall_lead_types.values())
    if total_leads:
        lines.append("## 首出牌型覆盖")
        lines.append("")
        lines.append("| 牌型 | 次数 | 占比 |")
        lines.append("|------|------|------|")
        for kind, n in sorted(overall_lead_types.items(), key=lambda kv: -kv[1]):
            lines.append(f"| {kind} | {n} | {100 * n / total_leads:.1f}% |")
        missing = {"Pair", "Tractor", "Dump"} - set(overall_lead_types)
        if missing:
            lines.append("")
            lines.append(
                f"> ⚠ 未触发的牌型：{'、'.join(sorted(missing))} —— "
                "这些规则分支本次未被覆盖。")
        lines.append("")
    if not any(g.get("valid") is not None for c in case_rows for g in c["games"]):
        lines.append("> ⚠ 本次汇总无规则校验数据 —— 统计值不能证明对局逻辑正确。")
        lines.append("> 用 `run_batch.py`（不加 `--no-validate`）重跑以获得校验结论。")
    elif total_violations:
        lines.append(f"## 规则违规 {total_violations} 处")
        lines.append("")
        lines.append("| 次数 | 违规类型 |")
        lines.append("|------|----------|")
        for code, n in sorted(violation_codes.items(), key=lambda kv: -kv[1]):
            lines.append(f"| {n} | `{code}` |")
    else:
        lines.append("> ✅ 全部对局通过规则校验。")

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
