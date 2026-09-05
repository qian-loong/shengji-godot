#!/usr/bin/env python3
"""Capture the AC16 golden baseline (FT1 ai-basic.md AC16 / ADR-0005 §可复现契约).

⚠️ 一次性不可逆窗口：黄金基准必须在**代码仍默认 SIMPLE、SMART 未上线时**抓取。
SMART 上线后 lead_strategy 默认改变，同 seed 输出漂移，此基准永久无法复现。
前置：RNG 注入（decide_bid 去全局 randf）必须已完成——否则同 seed 也不逐字节可复现。

产出三项归档（GDD AC16 要求，缺一则 AC16+AC20 不可测），写到 src/godot/tests/fixtures/：
  1. ac16_trick_hashes.json    每局每墩输出的规范化哈希（逐字节可复现的黄金基准）
  2. baseline_simple_stats.json 聚合统计（局数/平均墩数/stddev/下庄率）——供 AC20
  3. ac16_seeds.json            seed 列表

用法：
  GODOT_EXE=<console build> python tools/batch/capture_ac16_baseline.py \
      --preset classic --seeds 1000 --max-rounds 30
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GODOT_PROJECT = REPO / "src" / "godot"
SESSION_SCRIPT = "res://scripts/gameplay/game_session.gd"
FIXTURES = GODOT_PROJECT / "tests" / "fixtures"


def find_godot() -> str:
    exe = os.environ.get("GODOT_EXE") or os.environ.get("GODOT")
    if exe and Path(exe).exists():
        return exe
    print("Set GODOT_EXE to Godot console executable", file=sys.stderr)
    sys.exit(2)


def run_one(godot: str, preset: str, seed: int, max_rounds: int, log_path: Path, timeout: int) -> bool:
    """跑一局固定 seed 的 SIMPLE 对局，写日志。返回是否成功。"""
    cmd = [
        godot, "--headless", "--path", str(GODOT_PROJECT), "--script", SESSION_SCRIPT,
        f"--preset={preset}", f"--seed={seed}", f"--max-rounds={max_rounds}",
        "--lead-strategy=simple", f"--log-path={log_path}",
    ]
    try:
        proc = subprocess.run(
            cmd, cwd=str(GODOT_PROJECT), capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
        return proc.returncode == 0 and log_path.is_file()
    except subprocess.TimeoutExpired:
        return False


def normalize_game(log: dict) -> list:
    """把一局日志规范化为可哈希的每墩输出序列。

    只取**决定性、SMART 迁移后可同样重算**的字段：每墩的
    (trick_num, lead_seat, [(seat, cards)...], winner)。
    忽略计时/调试字段（debug、created_at）——它们非决定性、不该进基准。
    """
    rounds_out = []
    for rnd in log.get("rounds", []):
        tricks_out = []
        for t in rnd.get("tricks", []):
            plays = [
                {"seat": p.get("seat"), "cards": p.get("cards", [])}
                for p in t.get("plays", [])
            ]
            tricks_out.append({
                "trick_num": t.get("trick_num"),
                "lead_seat": t.get("lead_seat"),
                "plays": plays,
                "winner": t.get("winner"),
            })
        settle = rnd.get("settlement") or {}
        rounds_out.append({
            "round_num": rnd.get("round_num"),
            "dealer": rnd.get("dealer"),
            "trump_suit": rnd.get("trump_suit"),
            "rank": rnd.get("rank"),
            "bid": rnd.get("bid"),
            "tricks": tricks_out,
            "dealer_dethroned": settle.get("dealer_dethroned"),
            "final_score": settle.get("final_score"),
        })
    return rounds_out


def hash_game(normalized: list) -> str:
    """对规范化的每局输出算稳定哈希（sort_keys 保证字段序无关）。"""
    blob = json.dumps(normalized, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--preset", default="classic", choices=["classic", "competitive", "quick"])
    ap.add_argument("--seeds", type=int, default=1000, help="seed 数量（从 seed-base 起连续）")
    ap.add_argument("--seed-base", type=int, default=1000)
    ap.add_argument("--max-rounds", type=int, default=30)
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--limit", type=int, default=None, help="只跑前 N 个 seed（冒烟用）")
    args = ap.parse_args()

    godot = find_godot()
    FIXTURES.mkdir(parents=True, exist_ok=True)

    n = args.limit if args.limit is not None else args.seeds
    seeds = list(range(args.seed_base, args.seed_base + n))
    print(f"GODOT_EXE={godot}")
    print(f"AC16 基准抓取：preset={args.preset} seeds={n} max_rounds={args.max_rounds} lead=simple")
    print(f"归档目录：{FIXTURES.relative_to(REPO)}")

    trick_hashes: dict[str, str] = {}
    tricks_per_round: list[int] = []   # AC20：每个牌局(round)打了多少墩(trick)
    games_run = 0
    dethrone_events = 0
    dethrone_total = 0                  # 结算的 round 总数
    failures: list[int] = []

    with tempfile.TemporaryDirectory() as tmp:
        tmp_log = Path(tmp) / "game.json"
        for i, seed in enumerate(seeds):
            if tmp_log.exists():
                tmp_log.unlink()
            ok = run_one(godot, args.preset, seed, args.max_rounds, tmp_log, args.timeout)
            if not ok:
                failures.append(seed)
                print(f"  [FAIL] seed={seed}")
                continue
            log = json.loads(tmp_log.read_text(encoding="utf-8"))
            normalized = normalize_game(log)
            trick_hashes[str(seed)] = hash_game(normalized)
            games_run += 1
            # 统计：AC20 要的是"每个 round 打了多少墩(trick)"，非"每 game 多少 round"
            for rnd in normalized:
                tricks_per_round.append(len(rnd.get("tricks", [])))
                dethrone_total += 1
                if rnd.get("dealer_dethroned"):
                    dethrone_events += 1
            if (i + 1) % 50 == 0 or i + 1 == len(seeds):
                print(f"  进度 {i+1}/{len(seeds)} …")

    # 聚合统计
    n_rounds = len(tricks_per_round)
    mean_tricks = sum(tricks_per_round) / n_rounds if n_rounds else 0.0
    var = sum((c - mean_tricks) ** 2 for c in tricks_per_round) / n_rounds if n_rounds else 0.0
    std_tricks = math.sqrt(var)
    dethrone_rate = dethrone_events / dethrone_total if dethrone_total else 0.0

    # 写三项归档
    (FIXTURES / "ac16_seeds.json").write_text(
        json.dumps({"preset": args.preset, "seed_base": args.seed_base, "count": n,
                    "max_rounds": args.max_rounds, "lead_strategy": "simple",
                    "seeds": seeds}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")

    (FIXTURES / "ac16_trick_hashes.json").write_text(
        json.dumps({"preset": args.preset, "lead_strategy": "simple",
                    "hash_algo": "sha256", "note": "每 seed 一局对局的规范化每墩输出哈希（AC16 黄金基准）",
                    "hashes": trick_hashes}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")

    (FIXTURES / "baseline_simple_stats.json").write_text(
        json.dumps({"preset": args.preset, "lead_strategy": "simple",
                    "games_run": games_run,
                    "total_rounds": n_rounds,
                    "mean_tricks_per_round": round(mean_tricks, 4),
                    "std_tricks_per_round": round(std_tricks, 4),
                    "dethrone_rate": round(dethrone_rate, 4),
                    "dethrone_events": dethrone_events, "round_settlements": dethrone_total,
                    "note": ("AC20 基线：mean_tricks_per_round 供 SMART 墩数降幅(<=10%)比对；"
                             "dethrone_rate 供 AC19 走廊[0.45,0.60]对照。max_rounds 会截断每 game "
                             "的 round 数但不影响单个 round 的墩数统计")},
                   ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")

    print("\n=== 归档完成 ===")
    print(f"  成功局数(game): {games_run}  失败: {len(failures)}  结算牌局(round): {n_rounds}")
    print(f"  平均墩数/牌局: {mean_tricks:.2f} (std {std_tricks:.2f})")
    print(f"  下庄率: {dethrone_rate:.4f} ({dethrone_events}/{dethrone_total})")
    print(f"  三项归档 → {FIXTURES.relative_to(REPO)}/")
    if failures:
        print(f"  ⚠️ 失败 seed: {failures[:10]}{' …' if len(failures) > 10 else ''}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
