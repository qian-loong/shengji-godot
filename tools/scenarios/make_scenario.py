#!/usr/bin/env python3
"""从"关键牌"约束生成合法的构造牌局（scenario）。

手写 scenario 极易违反牌张守恒（2 副牌每张恰好 2 份、4×hand_size + bottom_size
= deck_count×54），本工具只让你指定**关心的那几张**，其余自动补齐。

用法:
  python tools/scenarios/make_scenario.py spec.json -o scenario.json

spec 格式:
{
  "description": "...",
  "deck_count": 2,
  "dealer": 0,
  "trump_suit": 0,
  "rank": 5,
  "require": {
    "0": ["♠5","♠5","♥5","♥5"],   // 座位 0 必须持有
    "3": ["RedJoker","RedJoker"]
  },
  "bottom_require": ["♠K","♠K"],
  "seed": 42
}
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from collections import Counter
from pathlib import Path

SUITS = ["♠", "♥", "♦", "♣"]
RANKS = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
JOKERS = ["BlackJoker", "RedJoker"]

SEAT_COUNT = 4


def full_deck(deck_count: int) -> list[str]:
    """复刻 DeckManager.generate_deck：每副牌每张各一份。"""
    deck: list[str] = []
    for _ in range(deck_count):
        for s in SUITS:
            for r in RANKS:
                deck.append(f"{s}{r}")
        deck.extend(JOKERS)
    return deck


def hand_size(deck_count: int) -> int:
    return 25 if deck_count == 2 else 12


def bottom_size(deck_count: int) -> int:
    return 8 if deck_count == 2 else 6


def take(pool: Counter, cards: list[str], where: str) -> list[str]:
    """从牌池取走指定牌，取不到就报错（说明 spec 要求超过了牌堆存量）。"""
    taken = []
    for c in cards:
        if pool[c] <= 0:
            raise SystemExit(
                f"[{where}] 牌堆里没有足够的 {c} —— "
                f"检查 deck_count 或是否在多处重复要求同一张牌"
            )
        pool[c] -= 1
        taken.append(c)
    return taken


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        enc = (getattr(stream, "encoding", "") or "").lower()
        if enc.replace("-", "") != "utf8":
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except (AttributeError, OSError):
                pass

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec", type=Path)
    ap.add_argument("-o", "--out", type=Path, required=True)
    args = ap.parse_args()

    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    deck_count = int(spec.get("deck_count", 2))
    hs = hand_size(deck_count)
    bs = bottom_size(deck_count)

    pool = Counter(full_deck(deck_count))
    total = sum(pool.values())
    if SEAT_COUNT * hs + bs != total:
        raise SystemExit(f"牌张守恒不成立: 4×{hs}+{bs} != {total}")

    rng = random.Random(spec.get("seed", 42))

    hands: list[list[str]] = [[] for _ in range(SEAT_COUNT)]
    require = spec.get("require", {})
    for seat_key, cards in require.items():
        seat = int(seat_key)
        if not 0 <= seat < SEAT_COUNT:
            raise SystemExit(f"require 里的座位越界: {seat}")
        if len(cards) > hs:
            raise SystemExit(f"座位 {seat} 要求 {len(cards)} 张，超过手牌上限 {hs}")
        hands[seat].extend(take(pool, list(cards), f"require[{seat}]"))

    bottom = take(pool, list(spec.get("bottom_require", [])), "bottom_require")
    if len(bottom) > bs:
        raise SystemExit(f"bottom_require {len(bottom)} 张，超过底牌上限 {bs}")

    # 剩余牌打散后补齐
    rest = []
    for card, n in pool.items():
        rest.extend([card] * n)
    rng.shuffle(rest)

    idx = 0
    for seat in range(SEAT_COUNT):
        need = hs - len(hands[seat])
        hands[seat].extend(rest[idx:idx + need])
        idx += need
    bottom.extend(rest[idx:idx + (bs - len(bottom))])
    idx += bs - (len(bottom) - (bs - len(bottom)) if False else 0)

    # 守恒自检
    used = Counter()
    for h in hands:
        used.update(h)
    used.update(bottom)
    expected = Counter(full_deck(deck_count))
    if used != expected:
        missing = expected - used
        extra = used - expected
        raise SystemExit(f"牌张守恒自检失败 缺={dict(missing)} 多={dict(extra)}")
    for seat, h in enumerate(hands):
        if len(h) != hs:
            raise SystemExit(f"座位 {seat} 得到 {len(h)} 张，期望 {hs}")
    if len(bottom) != bs:
        raise SystemExit(f"底牌 {len(bottom)} 张，期望 {bs}")

    scenario = {
        "description": spec.get("description", ""),
        "hands": hands,
        "bottom": bottom,
    }
    for key in ("dealer", "trump_suit", "rank", "lead_strategy"):
        if key in spec:
            scenario[key] = spec[key]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(scenario, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"已生成 {args.out}")
    print(f"  每人 {hs} 张 / 底牌 {bs} 张 / 共 {total} 张，守恒自检通过")
    for seat, cards in require.items():
        print(f"  座位 {seat} 保证持有: {' '.join(cards)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
