#!/usr/bin/env python3
"""Expand a batch matrix into per-case RuleConfig JSON files.

Uses Godot-compatible RuleConfig.to_dict shape. Base fields come from
hardcoded preset mirrors of rule_config.gd factories (keep in sync).

Usage:
  python tools/batch/generate_matrix.py tools/batch/matrix_single_factor_quick.json
  python tools/batch/generate_matrix.py tools/batch/matrix_single_factor_quick.json --out configs/batch
"""

from __future__ import annotations

import argparse
import json
import sys
from copy import deepcopy
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

sys.path.insert(0, str(REPO / "tools"))
from validate_game_log import force_utf8_stdout  # noqa: E402

# Mirrors src/godot/scripts/core/rule_config.gd preset factories
PRESETS: dict[str, dict] = {
    "classic": {
        "source": 0,
        "base_preset": 0,
        "modified_fields": [],
        "deck_count": 2,
        "current_rank": 2,
        "trump_mode": 0,
        "fixed_trump_suit": -1,
        "joker_always_trump": True,
        "trump_joker_color_match": False,
        "bid_requires_joker": False,
        "allow_dump": True,
        "strict_follow_structure": True,
        "four_same_is_tractor": True,
        "tractor_allow_rank_card": True,
        "upgrade_threshold": 80,
        "upgrade_step": 1,
        "upgrade_table": [
            [0, 0, 3],
            [1, 0, 2],
            [40, 0, 1],
            [80, 1, 0],
            [120, 1, 1],
            [160, 1, 2],
            [200, 1, 3],
        ],
        "no_skip_enabled": False,
        "no_skip_ranks": [],
        "initial_dealer": -1,
    },
    "competitive": {
        "source": 1,
        "base_preset": 1,
        "modified_fields": [],
        "deck_count": 2,
        "current_rank": 2,
        "trump_mode": 0,
        "fixed_trump_suit": -1,
        "joker_always_trump": True,
        "trump_joker_color_match": False,
        "bid_requires_joker": False,
        "allow_dump": True,
        "strict_follow_structure": True,
        "four_same_is_tractor": True,
        "tractor_allow_rank_card": True,
        "upgrade_threshold": 100,
        "upgrade_step": 1,
        "upgrade_table": [
            [0, 0, 3],
            [1, 0, 2],
            [50, 0, 1],
            [100, 1, 0],
            [150, 1, 1],
            [200, 1, 2],
            [250, 1, 3],
        ],
        "no_skip_enabled": True,
        "no_skip_ranks": [5, 10, 13],
        "initial_dealer": -1,
    },
    "quick": {
        "source": 2,
        "base_preset": 2,
        "modified_fields": [],
        "deck_count": 1,
        "current_rank": 2,
        "trump_mode": 0,
        "fixed_trump_suit": -1,
        "joker_always_trump": True,
        "trump_joker_color_match": False,
        "bid_requires_joker": False,
        "allow_dump": False,
        "strict_follow_structure": False,
        "four_same_is_tractor": False,
        "tractor_allow_rank_card": False,
        "upgrade_threshold": 60,
        "upgrade_step": 2,
        "upgrade_table": [
            [0, 0, 3],
            [1, 0, 2],
            [30, 0, 1],
            [60, 1, 1],
            [90, 1, 2],
            [120, 1, 3],
        ],
        "no_skip_enabled": False,
        "no_skip_ranks": [],
        "initial_dealer": -1,
    },
}

PRESET_SOURCE = {"classic": 0, "competitive": 1, "quick": 2}


def attack_threshold(table: list) -> int:
    """升级表里的"攻方翻盘线"——首个 side==1 的档位。"""
    tiers = [int(r[0]) for r in table if len(r) >= 2 and int(r[1]) == 1]
    return min(tiers) if tiers else -1


def check_threshold_consistency(case_id: str, cfg: dict) -> None:
    """upgrade_threshold 必须与 upgrade_table 自洽。

    两者描述同一件事的两面：表里首个 side==1 的档位就是攻方翻盘线，
    而 upgrade_threshold 决定 dealer_dethroned。只改其一会造出矛盾配置——
    例如门槛 100 配 80 档表时，攻方拿 86 分会被表判"攻方赢"、被门槛判"没下庄"。

    与 RuleConfig.validate() 的同名检查对应，在生成阶段就拦住，
    免得跑完一整轮批跑才发现配置是废的。
    """
    threshold = int(cfg.get("upgrade_threshold", -1))
    tier = attack_threshold(cfg.get("upgrade_table") or [])
    if tier >= 0 and threshold != tier:
        raise SystemExit(
            f"[{case_id}] upgrade_threshold={threshold} 与升级表的攻方首档 {tier} 不一致。\n"
            f"  改门槛时必须同时给出配套的 upgrade_table（庄家中档=门槛/2，"
            f"攻方档距=门槛/2）。"
        )


def apply_overrides(base: dict, overrides: dict) -> dict:
    cfg = deepcopy(base)
    modified: list[str] = []
    for key, value in overrides.items():
        if key in ("source", "base_preset", "modified_fields"):
            continue
        if cfg.get(key) != value:
            modified.append(key)
        cfg[key] = value
    if modified:
        cfg["source"] = 3  # CUSTOM
        cfg["modified_fields"] = modified
    else:
        cfg["modified_fields"] = []
    return cfg


def main() -> int:
    force_utf8_stdout()

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("matrix", type=Path, help="Matrix JSON path")
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Output directory (default: configs/batch/<matrix.name>)",
    )
    args = ap.parse_args()

    matrix_path = args.matrix
    if not matrix_path.is_file():
        # try relative to repo
        alt = REPO / matrix_path
        if alt.is_file():
            matrix_path = alt
        else:
            print(f"matrix not found: {args.matrix}", file=sys.stderr)
            return 1

    matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    base_name = matrix.get("base_preset", "quick")
    if base_name not in PRESETS:
        print(f"unknown base_preset: {base_name}", file=sys.stderr)
        return 1

    out_dir = args.out
    if out_dir is None:
        out_dir = REPO / "configs" / "batch" / matrix.get("name", matrix_path.stem)
    else:
        out_dir = out_dir if out_dir.is_absolute() else REPO / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    base = deepcopy(PRESETS[base_name])
    base["base_preset"] = PRESET_SOURCE[base_name]
    base["source"] = PRESET_SOURCE[base_name]

    cases = []
    for factor in matrix.get("factors", []):
        case_id = factor["id"]
        cfg = apply_overrides(base, factor.get("overrides") or {})
        check_threshold_consistency(case_id, cfg)
        cfg_path = out_dir / f"{case_id}.json"
        cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        cases.append(
            {
                "id": case_id,
                "description": factor.get("description", ""),
                "config": str(cfg_path.relative_to(REPO)).replace("\\", "/"),
                "overrides": factor.get("overrides") or {},
            }
        )
        print(f"wrote {cfg_path.relative_to(REPO)}")

    manifest = {
        "matrix": str(matrix_path.relative_to(REPO)).replace("\\", "/")
        if matrix_path.is_relative_to(REPO)
        else str(matrix_path),
        "name": matrix.get("name", matrix_path.stem),
        "base_preset": base_name,
        "games_per_case": int(matrix.get("games_per_case", 3)),
        "max_rounds": int(matrix.get("max_rounds", 30)),
        "seed_base": int(matrix.get("seed_base", 42)),
        "cases": cases,
    }
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"manifest: {manifest_path.relative_to(REPO)}")
    print(f"{len(cases)} cases ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
