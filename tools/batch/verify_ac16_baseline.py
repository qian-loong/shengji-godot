#!/usr/bin/env python3
"""AC16 黄金基准只读比对（不写盘，绝不覆盖不可逆产物）。

用途：SMART 实现的每一步之后，用 `--lead-strategy=simple`（脚本内固定 simple）
重跑前 N 个 seed，重算规范化每墩哈希，与 `tests/fixtures/ac16_trick_hashes.json`
逐一比对。任一不一致 = SIMPLE 路径被破坏 / 引入非确定源，退出码非 0。

复用 capture_ac16_baseline.py 的 run_one / normalize_game / hash_game，
零重复规则逻辑；本脚本**只读基准、从不写基准**。

用法：
    GODOT_EXE=<console build> python tools/batch/verify_ac16_baseline.py --limit 50
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

# 复用 capture 的实现，保证归一化/哈希算法与黄金基准生成时逐字节一致
import capture_ac16_baseline as cap

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "src" / "godot" / "tests" / "fixtures"
HASHES = FIXTURES / "ac16_trick_hashes.json"
SEEDS = FIXTURES / "ac16_seeds.json"


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=50,
                    help="只比对前 N 个 seed（冒烟用；默认 50）")
    ap.add_argument("--timeout", type=int, default=180)
    args = ap.parse_args()

    if not HASHES.exists():
        print(f"[FATAL] 黄金基准不存在: {HASHES}", file=sys.stderr)
        return 2

    golden_doc = json.loads(HASHES.read_text(encoding="utf-8"))
    golden = golden_doc["hashes"]
    seeds_doc = json.loads(SEEDS.read_text(encoding="utf-8"))
    preset = seeds_doc["preset"]
    max_rounds = seeds_doc["max_rounds"]
    all_seeds = seeds_doc["seeds"]

    n = min(args.limit, len(all_seeds))
    seeds = all_seeds[:n]

    godot = cap.find_godot()
    print(f"GODOT_EXE={godot}")
    print(f"AC16 只读比对：preset={preset} 前 {n}/{len(all_seeds)} seed lead=simple")

    mismatches: list[tuple[int, str, str]] = []
    failures: list[int] = []
    checked = 0

    with tempfile.TemporaryDirectory() as tmp:
        tmp_log = Path(tmp) / "game.json"
        for i, seed in enumerate(seeds):
            if tmp_log.exists():
                tmp_log.unlink()
            ok = cap.run_one(godot, preset, seed, max_rounds, tmp_log, args.timeout)
            if not ok:
                failures.append(seed)
                print(f"  [FAIL] seed={seed} 对局未产出日志")
                continue
            log = json.loads(tmp_log.read_text(encoding="utf-8"))
            got = cap.hash_game(cap.normalize_game(log))
            want = golden.get(str(seed))
            if want is None:
                print(f"  [WARN] seed={seed} 不在黄金基准中，跳过")
                continue
            checked += 1
            if got != want:
                mismatches.append((seed, want, got))
                print(f"  [MISMATCH] seed={seed}\n      want={want}\n      got ={got}")
            if (i + 1) % 25 == 0 or i + 1 == len(seeds):
                print(f"  进度 {i+1}/{len(seeds)} …")

    print("\n==============================================")
    print(f"= AC16 比对结果：checked={checked} mismatch={len(mismatches)} fail={len(failures)}")
    print("==============================================")

    if failures:
        print(f"[FATAL] {len(failures)} 个 seed 对局未产出日志: {failures[:10]}", file=sys.stderr)
        return 2
    if mismatches:
        print(f"[FAIL] {len(mismatches)} 个 seed 哈希漂移 —— SIMPLE 路径被破坏或引入非确定源。",
              file=sys.stderr)
        return 1
    print("[PASS] 前 %d 个 seed 全部逐字节一致，SIMPLE 路径未被破坏。" % checked)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
