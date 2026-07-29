#!/usr/bin/env python3
"""对局日志正确性校验器 —— 配置驱动的独立复算实现。

设计约束（与 tools/export_game_log_html.py 的旧校验逻辑相反）：

1. **零硬编码规则常量**。升级表、必打级、门槛、甩牌/跟牌开关等全部从日志的
   `rule_config` 读取。唯一允许写死的是牌序与牌点这类引擎侧同样是 const 的
   编码约定（Card.RANK_SEQUENCE / Card.RANK_POINTS）。
2. **缺字段即报错，绝不静默默认**。`.get(key, default)` 式的宽容会把"日志漏字段"
   伪装成"校验通过"，这正是旧脚本最危险的地方。
3. **独立实现**。刻意不调用引擎代码，从规则文档/GDScript 语义各自实现一遍，
   两边不一致时才有交叉验证的价值。

用法:
  python tools/validate_game_log.py <game_log.json> [-v] [--json]
  python tools/validate_game_log.py logs/batch/<run_id>/ --json

退出码: 0 = 无 error；1 = 有 error；2 = 用法/读取错误
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Optional

# ============================================================
# 编码约定常量（引擎侧同为 const，非可配置规则）
# ============================================================

SUIT_SYMBOL_TO_ID = {"♠": 0, "♥": 1, "♦": 2, "♣": 3}
SUIT_ID_TO_SYMBOL = {v: k for k, v in SUIT_SYMBOL_TO_ID.items()}

RANK_SYMBOL_TO_VALUE = {
    "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
    "9": 9, "10": 10, "J": 11, "Q": 12, "K": 13, "A": 14,
}
RANK_VALUE_TO_SYMBOL = {v: k for k, v in RANK_SYMBOL_TO_VALUE.items()}

# Card.RANK_SEQUENCE
RANK_SEQUENCE = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
RANK_ACE = 14

# Card.RANK_POINTS
RANK_POINTS = {5: 5, 10: 10, 13: 10}

# Card.JokerType
JOKER_SMALL = 0
JOKER_BIG = 1

# TrumpJudge.DomainType
DOMAIN_TRUMP = 0
DOMAIN_SIDE = 1
DOMAIN_NONE = 2

# Card.CardType
TYPE_SINGLE = "Single"
TYPE_PAIR = "Pair"
TYPE_TRACTOR = "Tractor"
TYPE_DUMP = "Dump"

SEAT_COUNT = 4


class LogFormatError(Exception):
    """日志结构不符合预期 —— 属于工具/schema 问题，不是游戏逻辑问题。"""


# ============================================================
# Card
# ============================================================


@dataclass(frozen=True)
class Card:
    is_joker: bool
    suit: int = -1
    rank: int = -1
    joker_type: int = -1
    raw: str = ""

    @property
    def identity(self) -> tuple:
        """Card.equals() 的等价键 —— 忽略 deck_id。"""
        if self.is_joker:
            return ("J", self.joker_type)
        return ("N", self.suit, self.rank)

    @property
    def point(self) -> int:
        if self.is_joker:
            return 0
        return RANK_POINTS.get(self.rank, 0)

    def __str__(self) -> str:
        return self.raw or ("Joker" if self.is_joker else "?")


def parse_card(raw: Any) -> Card:
    """解析日志中的牌。日志写的是 Card.to_string_repr() 的结果。"""
    if not isinstance(raw, str) or not raw:
        raise LogFormatError(f"无法解析的牌: {raw!r}")
    if raw == "BlackJoker":
        return Card(is_joker=True, joker_type=JOKER_SMALL, raw=raw)
    if raw == "RedJoker":
        return Card(is_joker=True, joker_type=JOKER_BIG, raw=raw)

    suit = SUIT_SYMBOL_TO_ID.get(raw[0])
    rank = RANK_SYMBOL_TO_VALUE.get(raw[1:])
    if suit is None or rank is None:
        raise LogFormatError(f"无法解析的牌: {raw!r}")
    return Card(is_joker=False, suit=suit, rank=rank, raw=raw)


def parse_cards(raws: Iterable[Any]) -> list[Card]:
    return [parse_card(r) for r in raws]


def count_points(cards: Iterable[Card]) -> int:
    return sum(c.point for c in cards)


def rank_symbol(rank: Any) -> str:
    return RANK_VALUE_TO_SYMBOL.get(rank, str(rank))


# ============================================================
# RuleConfig —— 全部字段来自日志，缺失即报错
# ============================================================

# 复算必需的字段。缺任何一个都无法可信地校验，直接 fail-fast。
REQUIRED_CONFIG_FIELDS = [
    "deck_count",
    "total_score",
    "joker_always_trump",
    "allow_dump",
    "strict_follow_structure",
    "four_same_is_tractor",
    "tractor_allow_rank_card",
    "upgrade_threshold",
    "upgrade_step",
    "upgrade_table",
    "no_skip_enabled",
    "no_skip_ranks",
]


@dataclass
class RuleConfig:
    deck_count: int
    total_score: int
    joker_always_trump: bool
    allow_dump: bool
    strict_follow_structure: bool
    four_same_is_tractor: bool
    tractor_allow_rank_card: bool
    upgrade_threshold: int
    upgrade_step: int
    upgrade_table: list[list[int]]
    no_skip_enabled: bool
    no_skip_ranks: list[int]
    base_preset: Optional[int] = None

    @staticmethod
    def from_log(log: dict) -> "RuleConfig":
        rc = log.get("rule_config")
        if not isinstance(rc, dict):
            raise LogFormatError("日志缺少 rule_config —— 无法进行配置驱动校验")

        missing = [f for f in REQUIRED_CONFIG_FIELDS if f not in rc]
        if missing:
            raise LogFormatError(
                "rule_config 缺少字段 %s。"
                "该日志可能由 2026-07-28 之前的 GameLogger 生成"
                "（当时 set_rule_config 只写了手选的字段子集）。"
                "请用当前版本重新生成日志。" % ", ".join(missing)
            )

        table: list[list[int]] = []
        for row in rc["upgrade_table"]:
            if not isinstance(row, (list, tuple)) or len(row) < 3:
                raise LogFormatError(f"upgrade_table 行格式非法: {row!r}")
            table.append([int(row[0]), int(row[1]), int(row[2])])
        if not table:
            raise LogFormatError("upgrade_table 为空")

        return RuleConfig(
            deck_count=int(rc["deck_count"]),
            total_score=int(rc["total_score"]),
            joker_always_trump=bool(rc["joker_always_trump"]),
            allow_dump=bool(rc["allow_dump"]),
            strict_follow_structure=bool(rc["strict_follow_structure"]),
            four_same_is_tractor=bool(rc["four_same_is_tractor"]),
            tractor_allow_rank_card=bool(rc["tractor_allow_rank_card"]),
            upgrade_threshold=int(rc["upgrade_threshold"]),
            upgrade_step=int(rc["upgrade_step"]),
            upgrade_table=table,
            no_skip_enabled=bool(rc["no_skip_enabled"]),
            no_skip_ranks=[int(r) for r in rc["no_skip_ranks"]],
            base_preset=rc.get("base_preset"),
        )


# ============================================================
# Pattern
# ============================================================


@dataclass
class Pattern:
    kind: str
    card_count: int
    pair_count: int = 0
    pairs: list[int] = field(default_factory=list)
    components: list["Pattern"] = field(default_factory=list)


# ============================================================
# 规则引擎 —— 所有方法都以 RuleConfig 为准
# ============================================================


class Rules:
    """双升规则的独立实现。构造时绑定一份 RuleConfig。"""

    def __init__(self, config: RuleConfig) -> None:
        self.c = config

    # ---- 牌序 / 邻接（Card.gd）----

    @staticmethod
    def skip_sequence(current_rank: int) -> list[int]:
        return [r for r in RANK_SEQUENCE if r != current_rank]

    @classmethod
    def is_adjacent(cls, a: int, b: int, current_rank: int) -> bool:
        """Card.is_adjacent —— 基础序列相邻 或 跳过级牌后相邻。"""
        if a in RANK_SEQUENCE and b in RANK_SEQUENCE:
            if abs(RANK_SEQUENCE.index(a) - RANK_SEQUENCE.index(b)) == 1:
                return True
        seq = cls.skip_sequence(current_rank)
        if a in seq and b in seq:
            if abs(seq.index(a) - seq.index(b)) == 1:
                return True
        return False

    # ---- 域判定（TrumpJudge.get_suit_domain）----

    def suit_domain(self, card: Card, trump_suit: int, current_rank: int) -> tuple[int, int]:
        if card.is_joker:
            if self.c.joker_always_trump:
                return (DOMAIN_TRUMP, -1)
            if trump_suit < 0:
                return (DOMAIN_NONE, -1)
            return (DOMAIN_TRUMP, -1)
        if card.rank == current_rank:
            return (DOMAIN_TRUMP, -1)
        if trump_suit >= 0 and card.suit == trump_suit:
            return (DOMAIN_TRUMP, -1)
        return (DOMAIN_SIDE, card.suit)

    @staticmethod
    def domains_equal(a: tuple[int, int], b: tuple[int, int]) -> bool:
        if a[0] != b[0]:
            return False
        if a[0] == DOMAIN_SIDE:
            return a[1] == b[1]
        return True

    @staticmethod
    def domain_label(dom: tuple[int, int]) -> str:
        if dom[0] == DOMAIN_TRUMP:
            return "主"
        if dom[0] == DOMAIN_SIDE:
            return f"{SUIT_ID_TO_SYMBOL.get(dom[1], '?')}副"
        return "无域"

    # ---- 排序值（TrumpJudge.get_sort_value）----

    def sort_value(self, card: Card, trump_suit: int, current_rank: int) -> int:
        dom = self.suit_domain(card, trump_suit, current_rank)
        if card.is_joker:
            if dom[0] == DOMAIN_NONE:
                return -1
            return 140 if card.joker_type == JOKER_SMALL else 150

        if dom[0] == DOMAIN_TRUMP:
            if card.rank == current_rank and trump_suit >= 0 and card.suit == trump_suit:
                return 130
            if card.rank == current_rank:
                return 120
            seq = self.skip_sequence(current_rank)
            return 100 + seq.index(card.rank) if card.rank in seq else 100

        seq = self.skip_sequence(current_rank)
        idx = seq.index(card.rank) if card.rank in seq else 0
        return card.suit * 15 + idx

    def play_sort_value(self, cards: list[Card], trump_suit: int, current_rank: int) -> int:
        """PlayValidator._get_play_sort_value —— 取牌组内最大值。"""
        if not cards:
            return -1
        return max(self.sort_value(c, trump_suit, current_rank) for c in cards)

    # ---- 牌型识别（CardPattern.identify）----

    def identify(self, cards: list[Card], current_rank: int) -> Optional[Pattern]:
        if not cards:
            return None
        if len(cards) == 1:
            return Pattern(TYPE_SINGLE, 1)
        if len(cards) == 2 and cards[0].identity == cards[1].identity:
            p = Pattern(TYPE_PAIR, 2, pair_count=1)
            if not cards[0].is_joker:
                p.pairs = [cards[0].rank]
            return p

        tractor = self._try_tractor(cards, current_rank)
        if tractor is not None:
            return tractor

        if len(cards) >= 2:
            return self._try_dump(cards, current_rank)
        return None

    def _try_tractor(self, cards: list[Card], current_rank: int) -> Optional[Pattern]:
        # 四张王（大王对 + 小王对）恒为拖拉机，扣底 ×4。
        # 大小王在主牌域排序上紧邻（140/150），是最强的两个对子。
        # 不受 four_same_is_tractor 控制 —— 那个开关管的是级牌。
        if len(cards) == 4 and self._is_four_jokers(cards):
            return Pattern(TYPE_TRACTOR, 4, pair_count=2)

        # four_same_is_tractor：四张同点数（如 ♠5♠5♥5♥5 = 两个同点数的对子）。
        # 不是"四张完全相同的牌"—— 2 副牌下同一张牌最多 2 份。
        # 实际只对四张级牌生效：非级牌的同点数 4 张必然跨域，首出会被拒。
        if self.c.four_same_is_tractor and len(cards) == 4 and self._is_four_same_rank(cards):
            return Pattern(TYPE_TRACTOR, 4, pair_count=2,
                           pairs=[cards[0].rank, cards[0].rank])

        if len(cards) < 4 or len(cards) % 2 != 0:
            return None

        pair_ranks = self._extract_pair_ranks(cards)
        if not pair_ranks or len(pair_ranks) < 2:
            return None
        if len(pair_ranks) * 2 != len(cards):
            return None

        if not self.c.tractor_allow_rank_card:
            if any(pr == current_rank for pr in pair_ranks):
                return None

        if self._are_consecutive(pair_ranks, current_rank):
            return Pattern(TYPE_TRACTOR, len(cards),
                           pair_count=len(pair_ranks), pairs=list(pair_ranks))
        return None

    @staticmethod
    def _is_four_jokers(cards: list[Card]) -> bool:
        """大王 2 张 + 小王 2 张。1 副牌下凑不出，自然不触发。"""
        if len(cards) != 4 or not all(c.is_joker for c in cards):
            return False
        small = sum(1 for c in cards if c.joker_type == JOKER_SMALL)
        return small == 2 and len(cards) - small == 2

    @staticmethod
    def _is_four_same_rank(cards: list[Card]) -> bool:
        """4 张 rank 相同且能配成两个对子。♠5♥5♦5♣5 配不成对，不算。"""
        if len(cards) != 4 or cards[0].is_joker:
            return False
        rank = cards[0].rank
        counts: dict[tuple, int] = {}
        for c in cards:
            if c.is_joker or c.rank != rank:
                return False
            counts[c.identity] = counts.get(c.identity, 0) + 1
        return all(n % 2 == 0 for n in counts.values())

    @staticmethod
    def _all_same(cards: list[Card]) -> bool:
        return all(c.identity == cards[0].identity for c in cards[1:])

    @staticmethod
    def _extract_pair_ranks(cards: list[Card]) -> list[int]:
        """对子必须同花色同点数（GDD card-types.md §2.1），故按 identity 统计。

        按 rank 统计会把 ♠5♥5 当成对子，进而把 ♠5♥5♠6♥6 误判为拖拉机。
        """
        counts: dict[tuple, int] = {}
        ranks: dict[tuple, int] = {}
        for c in cards:
            if c.is_joker:
                return []
            counts[c.identity] = counts.get(c.identity, 0) + 1
            ranks[c.identity] = c.rank
        result: list[int] = []
        for key, count in counts.items():
            while count >= 2:
                result.append(ranks[key])
                count -= 2
        result.sort(key=RANK_SEQUENCE.index)
        return result

    @classmethod
    def _are_consecutive(cls, ranks: list[int], current_rank: int) -> bool:
        if len(ranks) < 2:
            return True
        ordered = sorted(ranks, key=RANK_SEQUENCE.index)
        return all(
            cls.is_adjacent(ordered[i], ordered[i + 1], current_rank)
            for i in range(len(ordered) - 1)
        )

    def _try_dump(self, cards: list[Card], current_rank: int) -> Optional[Pattern]:
        """CardPattern._try_dump —— 贪心：先拖拉机，再对子，剩余单张。"""
        remaining = list(cards)
        components: list[Pattern] = []

        # Phase 1: 拖拉机（长的优先）
        found = True
        while found:
            found = False
            max_pairs = len(remaining) // 2
            for pair_count in range(max_pairs, 1, -1):
                tractor = self._find_and_remove_tractor(remaining, pair_count, current_rank)
                if tractor is not None:
                    components.append(tractor)
                    found = True
                    break

        # Phase 2: 对子
        found = True
        while found and len(remaining) >= 2:
            found = False
            for i in range(len(remaining)):
                for j in range(i + 1, len(remaining)):
                    if remaining[i].identity == remaining[j].identity:
                        p = Pattern(TYPE_PAIR, 2, pair_count=1)
                        if not remaining[i].is_joker:
                            p.pairs = [remaining[i].rank]
                        components.append(p)
                        del remaining[j]
                        del remaining[i]
                        found = True
                        break
                if found:
                    break

        # Phase 3: 单张
        components.extend(Pattern(TYPE_SINGLE, 1) for _ in remaining)

        if len(components) < 2:
            return None
        return Pattern(TYPE_DUMP, len(cards), components=components)

    def _find_and_remove_tractor(
        self, remaining: list[Card], pair_count: int, current_rank: int
    ) -> Optional[Pattern]:
        """CardPattern._find_and_remove_tractor —— 命中则就地移除对应牌。"""
        counts: dict[tuple, int] = {}
        ranks: dict[tuple, int] = {}
        for c in remaining:
            if c.is_joker:
                continue
            counts[c.identity] = counts.get(c.identity, 0) + 1
            ranks[c.identity] = c.rank
        pair_ranks = sorted(
            (ranks[k] for k, n in counts.items() if n >= 2), key=RANK_SEQUENCE.index)
        if len(pair_ranks) < pair_count:
            return None

        for start in range(len(pair_ranks) - pair_count + 1):
            window = pair_ranks[start:start + pair_count]
            if not self.c.tractor_allow_rank_card and current_rank in window:
                continue
            if not self._are_consecutive(window, current_rank):
                continue
            # 按 identity 移除，避免把 ♠5♥5 当成一个对子拆掉
            for rank in window:
                target = None
                for key, n in counts.items():
                    if ranks[key] == rank and n >= 2:
                        target = key
                        break
                if target is None:
                    return None
                counts[target] -= 2
                removed = 0
                idx = 0
                while idx < len(remaining) and removed < 2:
                    if remaining[idx].identity == target:
                        del remaining[idx]
                        removed += 1
                    else:
                        idx += 1
            return Pattern(TYPE_TRACTOR, pair_count * 2,
                           pair_count=pair_count, pairs=list(window))
        return None

    @staticmethod
    def structure_matches(play: Optional[Pattern], lead: Optional[Pattern]) -> bool:
        """PlayValidator._structure_matches。"""
        if play is None or lead is None:
            return False
        if play.kind != lead.kind:
            return False
        if play.kind == TYPE_TRACTOR:
            return play.pair_count >= lead.pair_count
        return True

    # ---- 赢墩判定（PlayValidator.determine_winner）----

    def determine_winner(
        self, plays: list[dict], trump_suit: int, current_rank: int
    ) -> int:
        """plays: [{seat, cards: list[Card]}, ...]，按实际出牌顺序，plays[0] 为首出。"""
        lead = plays[0]
        lead_cards: list[Card] = lead["cards"]
        lead_domain = self.suit_domain(lead_cards[0], trump_suit, current_rank)
        lead_pattern = self.identify(lead_cards, current_rank)
        lead_is_trump = lead_domain[0] == DOMAIN_TRUMP

        best_seat = lead["seat"]
        best_value = self.play_sort_value(lead_cards, trump_suit, current_rank)
        best_is_trump_kill = False

        for play in plays[1:]:
            cards: list[Card] = play["cards"]
            if not cards:
                continue
            play_domain = self.suit_domain(cards[0], trump_suit, current_rank)
            play_is_trump = play_domain[0] == DOMAIN_TRUMP
            is_same_domain = self.domains_equal(play_domain, lead_domain)

            if lead_is_trump:
                if not is_same_domain:
                    continue  # 垫牌
                pattern = self.identify(cards, current_rank)
                if not self.structure_matches(pattern, lead_pattern):
                    continue
                value = self.play_sort_value(cards, trump_suit, current_rank)
                if value > best_value:
                    best_seat = play["seat"]
                    best_value = value

            elif play_is_trump and not is_same_domain:
                # 主牌杀
                pattern = self.identify(cards, current_rank)
                if not self.structure_matches(pattern, lead_pattern):
                    continue
                value = self.play_sort_value(cards, trump_suit, current_rank)
                if not best_is_trump_kill:
                    best_seat = play["seat"]
                    best_value = value
                    best_is_trump_kill = True
                elif value > best_value:
                    best_seat = play["seat"]
                    best_value = value

            elif is_same_domain and not best_is_trump_kill:
                pattern = self.identify(cards, current_rank)
                if not self.structure_matches(pattern, lead_pattern):
                    continue
                value = self.play_sort_value(cards, trump_suit, current_rank)
                if value > best_value:
                    best_seat = play["seat"]
                    best_value = value

        return best_seat

    # ---- 扣底倍数（CardPattern.get_bottom_multiplier）----

    def bottom_multiplier(self, pattern: Optional[Pattern]) -> int:
        if pattern is None:
            return 1
        if pattern.kind == TYPE_SINGLE:
            return 1
        if pattern.kind == TYPE_PAIR:
            return 2
        if pattern.kind == TYPE_TRACTOR:
            return pattern.pair_count * 2
        if pattern.kind == TYPE_DUMP:
            return max((self.bottom_multiplier(c) for c in pattern.components), default=1)
        return 1

    # ---- 升级推进（UpgradeSettlement.apply_upgrade）----

    def apply_upgrade(self, current_rank: int, levels: int) -> int:
        rank = current_rank
        for i in range(levels):
            nxt = self._next_rank(rank)
            if nxt < 0:
                return RANK_ACE
            rank = nxt
            if self.c.no_skip_enabled:
                if rank in self.c.no_skip_ranks and (i + 1) < levels:
                    return rank
        return rank

    @staticmethod
    def _next_rank(rank: int) -> int:
        if rank not in RANK_SEQUENCE:
            return -1
        idx = RANK_SEQUENCE.index(rank)
        if idx >= len(RANK_SEQUENCE) - 1:
            return -1
        return RANK_SEQUENCE[idx + 1]

    @staticmethod
    def apply_session_verdict(proposal: dict, actual_dealer: int) -> dict:
        """SessionState.apply_settlement 的会话层裁决。

        提案（UpgradeSettlement）只看本局得分；会话层再叠加一层：
        游戏结束时不切庄，保留实际庄家便于展示
        （见 effective_settlement.gd: "game_over 时 == actual_dealer"）。
        这是 proposed 与 effective 之间唯一的合法分歧点。
        """
        effective = dict(proposal)
        if proposal["game_over"] or proposal["new_dealer"] < 0:
            effective["new_dealer"] = actual_dealer
        return effective

    # ---- 结算（UpgradeSettlement.calculate）----
    def calculate_settlement(
        self,
        attack_score: int,
        bottom_cards: list[Card],
        dealer_seat: int,
        last_trick_winner_is_attack: bool,
        last_trick_pattern: Optional[Pattern],
        current_rank: int,
        attack_rank: int = -1,
    ) -> dict:
        if last_trick_winner_is_attack:
            bottom_score = count_points(bottom_cards)
            multiplier = self.bottom_multiplier(last_trick_pattern)
            bonus = bottom_score * multiplier
        else:
            bottom_score = 0
            multiplier = 0
            bonus = 0
        final_score = attack_score + bonus

        # 命中最高档（threshold 最大且 <= final_score）
        matched_side = -1
        matched_levels = 0
        matched_threshold = -1
        for row in self.c.upgrade_table:
            if final_score >= row[0] and row[0] > matched_threshold:
                matched_side = row[1]
                matched_levels = row[2]
                matched_threshold = row[0]

        if matched_side >= 0:
            side = matched_side
            levels = matched_levels
        else:
            # 未命中任何档：庄家方按 side==0 的最高档升级
            dealer_threshold = -1
            dealer_levels = 1
            for row in self.c.upgrade_table:
                if row[1] == 0 and final_score >= row[0] and row[0] > dealer_threshold:
                    dealer_threshold = row[0]
                    dealer_levels = row[2]
            side = 0
            levels = dealer_levels

        step = max(1, self.c.upgrade_step)
        effective_levels = levels * step if levels > 0 else 0

        dealer_dethroned = final_score >= self.c.upgrade_threshold
        new_dealer = (dealer_seat + 1) % SEAT_COUNT if dealer_dethroned else dealer_seat

        if effective_levels > 0:
            if side == 0:
                base_rank = current_rank
            elif attack_rank >= 0:
                base_rank = attack_rank
            else:
                base_rank = current_rank
            new_rank = self.apply_upgrade(base_rank, effective_levels)
            game_over = base_rank == RANK_ACE
        else:
            new_rank = current_rank
            game_over = False

        return {
            "attack_base_score": attack_score,
            "bottom_score": bottom_score,
            "bottom_multiplier": multiplier,
            "bottom_bonus": bonus,
            "final_score": final_score,
            "upgrading_side": side,
            "upgrade_levels": effective_levels,
            "dealer_dethroned": dealer_dethroned,
            "new_dealer": new_dealer,
            "new_rank": new_rank,
            "game_over": game_over,
        }


# ============================================================
# Issue
# ============================================================


@dataclass
class Issue:
    level: str      # "error" | "warning"
    code: str
    message: str
    round_num: Optional[int] = None
    trick_num: Optional[int] = None

    def location(self) -> str:
        parts = []
        if self.round_num is not None:
            parts.append(f"R{self.round_num}")
        if self.trick_num is not None:
            parts.append(f"T{self.trick_num}")
        return ".".join(parts) if parts else "-"

    def to_dict(self) -> dict:
        return {
            "level": self.level,
            "code": self.code,
            "message": self.message,
            "round": self.round_num,
            "trick": self.trick_num,
        }


def remove_cards(source: list[Card], removed: list[Card]) -> tuple[list[Card], list[Card]]:
    """从 source 移除 removed（按 identity 逐张匹配）。

    返回 (剩余牌, 未能匹配的牌)。未能匹配说明打出了手上没有的牌。
    """
    pool = list(source)
    missing: list[Card] = []
    for card in removed:
        for i, held in enumerate(pool):
            if held.identity == card.identity:
                del pool[i]
                break
        else:
            missing.append(card)
    return pool, missing


# ============================================================
# Validator
# ============================================================

REQUIRED_ROUND_FIELDS = ["rank", "dealer", "trump_suit", "tricks", "settlement"]

SETTLEMENT_FIELDS = [
    "attack_base_score",
    "bottom_score",
    "bottom_multiplier",
    "bottom_bonus",
    "final_score",
    "upgrading_side",
    "upgrade_levels",
    "dealer_dethroned",
    "new_dealer",
    "new_rank",
    "game_over",
]


class LogValidator:
    def __init__(self, log: dict, source: str = "<log>") -> None:
        self.log = log
        self.source = source
        self.config = RuleConfig.from_log(log)
        self.rules = Rules(self.config)
        self.issues: list[Issue] = []
        self.skipped_checks: list[str] = []
        # 每局的复算结果，供可视化工具做"日志 vs 复算"对照展示。
        # 键：round_num；值：{"proposal": {...}, "effective": {...}}
        self.round_reports: dict[int, dict] = {}
        self._round_num: Optional[int] = None
        self._trick_num: Optional[int] = None

    # ---- issue helpers ----

    def _err(self, code: str, message: str) -> None:
        self.issues.append(Issue("error", code, message, self._round_num, self._trick_num))

    def _warn(self, code: str, message: str) -> None:
        self.issues.append(Issue("warning", code, message, self._round_num, self._trick_num))

    def _skip(self, what: str) -> None:
        if what not in self.skipped_checks:
            self.skipped_checks.append(what)

    # ---- entry ----

    def validate(self) -> list[Issue]:
        rounds = self.log.get("rounds")
        if not isinstance(rounds, list):
            raise LogFormatError("日志缺少 rounds 数组")

        prev_expected_dealer: Optional[int] = None
        prev_expected_team_ranks: Optional[list[int]] = None

        for idx, round_data in enumerate(rounds):
            self._round_num = round_data.get("round_num", idx + 1)
            self._trick_num = None

            if round_data.get("_in_progress"):
                self._skip(f"R{self._round_num} 未完成（_in_progress），跳过该局校验")
                continue

            missing = [f for f in REQUIRED_ROUND_FIELDS if f not in round_data]
            if missing:
                self._err("round_schema", f"局字段缺失: {', '.join(missing)}")
                continue

            prev_expected_dealer, prev_expected_team_ranks = self._validate_round(
                round_data, prev_expected_dealer, prev_expected_team_ranks
            )

        self._round_num = None
        self._trick_num = None
        return self.issues

    # ---- round ----

    def _validate_round(
        self,
        rd: dict,
        prev_expected_dealer: Optional[int],
        prev_expected_team_ranks: Optional[list[int]],
    ) -> tuple[Optional[int], Optional[list[int]]]:
        dealer = int(rd["dealer"])
        current_rank = int(rd["rank"])
        trump_suit = int(rd["trump_suit"])
        tricks = rd["tricks"]
        team_ranks = rd.get("team_ranks")

        # 跨局：庄家轮转
        if prev_expected_dealer is not None and dealer != prev_expected_dealer:
            self._check_dealer_rotation(prev_expected_dealer, dealer, rd.get("bid_history"))

        # 跨局：队伍等级连续性
        if prev_expected_team_ranks is not None and isinstance(team_ranks, list):
            if [int(r) for r in team_ranks] != prev_expected_team_ranks:
                self._err(
                    "team_ranks_continuity",
                    "队伍等级为 %s，按上局结算应为 %s"
                    % (
                        [rank_symbol(r) for r in team_ranks],
                        [rank_symbol(r) for r in prev_expected_team_ranks],
                    ),
                )

        # 本局打级 == 庄家队等级
        if isinstance(team_ranks, list) and len(team_ranks) >= 2:
            expected_rank = int(team_ranks[dealer % 2])
            if current_rank != expected_rank:
                self._err(
                    "round_rank",
                    f"本局打级 {rank_symbol(current_rank)} 与庄家队等级 "
                    f"{rank_symbol(expected_rank)} 不一致",
                )

        attack_team = rd.get("attack_team")
        if not isinstance(attack_team, list):
            attack_team = [s for s in range(SEAT_COUNT) if s % 2 != dealer % 2]
        attack_seats = {int(s) for s in attack_team}

        hands = self._reconstruct_hands(rd, dealer)

        expected_attack_score = 0
        prev_winner: Optional[int] = None
        total_trick_points = 0
        last_trick_winner: Optional[int] = None
        last_trick_pattern: Optional[Pattern] = None

        for t_idx, trick in enumerate(tricks):
            self._trick_num = trick.get("trick_num", t_idx + 1)
            res = self._validate_trick(
                trick, t_idx, dealer, trump_suit, current_rank,
                attack_seats, hands, prev_winner, expected_attack_score,
            )
            expected_attack_score = res["attack_score"]
            prev_winner = res["winner"]
            total_trick_points += res["trick_points"]
            last_trick_winner = res["winner"]
            last_trick_pattern = res["winner_pattern"]

        self._trick_num = None

        # 底牌
        buried_raw = rd.get("buried_cards")
        if buried_raw is None:
            buried_raw = (rd.get("debug") or {}).get("buried_cards")
        if buried_raw is None:
            self._skip(f"R{self._round_num} 缺 buried_cards，结算与总分守恒未校验")
            return (None, None)
        buried = parse_cards(buried_raw)

        # 底牌张数。与每人手牌张数一起构成牌张守恒：
        # SEAT_COUNT × hand_size + bottom_size == deck_count × 54
        rc_raw = self.log.get("rule_config") or {}
        if "bottom_size" in rc_raw:
            expected_bottom = int(rc_raw["bottom_size"])
            if len(buried) != expected_bottom:
                self._err(
                    "bottom_size",
                    f"底牌 {len(buried)} 张，期望 {expected_bottom} 张",
                )

        # 总分守恒：所有墩牌点 + 底牌牌点 == total_score
        conserved = total_trick_points + count_points(buried)
        if tricks and conserved != self.config.total_score:
            self._err(
                "score_conservation",
                f"全局牌点 {conserved}（墩内 {total_trick_points} + 底牌 "
                f"{count_points(buried)}）≠ total_score {self.config.total_score}",
            )

        # 结算复算
        return self._validate_settlement(
            rd, dealer, current_rank, team_ranks, attack_seats,
            expected_attack_score, buried, last_trick_winner, last_trick_pattern,
        )

    # ---- 庄家轮转 ----

    def _check_dealer_rotation(
        self, expected: int, actual: int, raw_bid_history: Any
    ) -> None:
        """庄家换人未必是错 —— 定主轮转可以合法夺庄。

        GDD design/gdd/trump-bidding.md §3.3 / §5.3：
        非首局按座位从庄家起轮询，庄家定不了就顺延到下家，
        "能定主 → 定主成功，该人成为庄家"。
        因此只有当"换人"无法由 skip + bid 记录解释时才算违规。
        """
        history = raw_bid_history if isinstance(raw_bid_history, list) else []
        history = [h for h in history if isinstance(h, dict)]

        first_bid = next((h for h in history if h.get("action") == "bid"), None)
        if first_bid is None:
            self._err(
                "dealer_rotation",
                f"庄家为 S{actual}，按上局结算应为 S{expected}，且本局无定主成功记录",
            )
            return

        if first_bid.get("seat") != actual:
            self._err(
                "dealer_rotation",
                f"庄家为 S{actual}，但首个定主的是 S{first_bid.get('seat')}",
            )
            return

        # 从原庄家顺延到实际庄家，中间每个座位都必须有跳过记录
        skipped_seats: list[int] = []
        seat = expected
        while seat != actual and len(skipped_seats) < SEAT_COUNT:
            skipped_seats.append(seat)
            seat = (seat + 1) % SEAT_COUNT

        for s in skipped_seats:
            if not any(
                h.get("seat") == s and h.get("action") == "skip" for h in history
            ):
                self._err(
                    "dealer_rotation",
                    f"庄家由 S{expected} 顺延至 S{actual}，但 S{s} 没有跳过定主的记录",
                )
                return

    # ---- 手牌重建 ----
    def _reconstruct_hands(self, rd: dict, dealer: int) -> Optional[list[list[Card]]]:
        """取得每人"出牌开始时"的手牌。

        首选 debug.hands_at_play_start —— 由 SessionController 在进入出牌阶段时
        直接快照，无需推导。

        回退路径是 initial_hands 减去埋底，但**反抢局下不可靠**：庄家先埋一次、
        反家再埋一次，log_bury 第二次会覆盖第一次，原庄家埋了哪几张无从得知。
        这种情况下宁可放弃校验并明确列入 skipped，也不能拿错误的手牌去误报。
        """
        debug = rd.get("debug")
        if not isinstance(debug, dict):
            self._skip(f"R{self._round_num} 无 debug 块，跟牌合法性/牌张归属未校验")
            return None

        expected_size = self._expected_hand_size()

        # 首选：出牌前快照
        snapshot = debug.get("hands_at_play_start")
        if isinstance(snapshot, list) and len(snapshot) == SEAT_COUNT and all(snapshot):
            try:
                hands = [parse_cards(h) for h in snapshot]
            except LogFormatError as exc:
                self._err("hand_parse", f"hands_at_play_start 解析失败: {exc}")
                return None
            for seat, hand in enumerate(hands):
                if len(hand) != expected_size:
                    self._err(
                        "hand_size",
                        f"S{seat} 出牌前手牌 {len(hand)} 张，期望 {expected_size} 张",
                    )
                    return None
            return hands

        # 回退：由初始手牌推导
        initial = debug.get("initial_hands")
        if not isinstance(initial, list) or len(initial) != SEAT_COUNT:
            self._skip(f"R{self._round_num} 无手牌数据，跟牌合法性/牌张归属未校验")
            return None

        if self._had_successful_counter(rd, dealer):
            self._skip(
                f"R{self._round_num} 发生反抢且无 hands_at_play_start 快照，"
                "原庄家配底后手牌无法复原，跟牌合法性/牌张归属未校验"
            )
            return None

        try:
            hands = [parse_cards(h) for h in initial]
        except LogFormatError as exc:
            self._err("hand_parse", f"initial_hands 解析失败: {exc}")
            return None

        bid = rd.get("bid")
        bury_seat = int(bid["seat"]) if isinstance(bid, dict) and "seat" in bid else dealer

        hwb = debug.get("hand_with_bottom")
        buried_raw = rd.get("buried_cards")
        if buried_raw is None:
            buried_raw = debug.get("buried_cards")

        if isinstance(hwb, list) and hwb and isinstance(buried_raw, list):
            try:
                merged = parse_cards(hwb)
                buried = parse_cards(buried_raw)
            except LogFormatError as exc:
                self._err("hand_parse", f"埋底数据解析失败: {exc}")
                return None
            remaining, missing = remove_cards(merged, buried)
            if missing:
                self._err(
                    "bury_not_in_hand",
                    "埋底牌 %s 不在手牌+底牌中" % ", ".join(str(c) for c in missing),
                )
            hands[bury_seat] = remaining

        for seat, hand in enumerate(hands):
            if len(hand) != expected_size:
                self._err(
                    "hand_size",
                    f"S{seat} 起手牌 {len(hand)} 张，期望 {expected_size} 张"
                    f"（重建自 initial_hands{'/埋底' if seat == bury_seat else ''}）",
                )
                return None
        return hands

    def _expected_hand_size(self) -> int:
        rc_raw = self.log.get("rule_config") or {}
        if "hand_size" in rc_raw:
            return int(rc_raw["hand_size"])
        return 25 if self.config.deck_count == 2 else 12

    @staticmethod
    def _had_successful_counter(rd: dict, dealer: int) -> bool:
        """反抢成功的判据：最终定主者不是庄家，或 bid 上带有 countered_from_trump。"""
        bid = rd.get("bid")
        if not isinstance(bid, dict):
            return False
        if bid.get("countered_from_trump") is not None:
            first_bid_seat = None
            history = rd.get("bid_history")
            if isinstance(history, list):
                for h in history:
                    if isinstance(h, dict) and h.get("action") == "bid":
                        first_bid_seat = h.get("seat")
                        break
            # 定主者与首个亮主者不同 → 中途被反
            if first_bid_seat is not None and bid.get("seat") != first_bid_seat:
                return True
        return False

    # ---- trick ----

    def _validate_trick(
        self,
        trick: dict,
        t_idx: int,
        dealer: int,
        trump_suit: int,
        current_rank: int,
        attack_seats: set[int],
        hands: Optional[list[list[Card]]],
        prev_winner: Optional[int],
        attack_score_before: int,
    ) -> dict:
        fallback = {
            "attack_score": attack_score_before,
            "winner": prev_winner,
            "trick_points": 0,
            "winner_pattern": None,
        }

        plays_raw = trick.get("plays")
        if not isinstance(plays_raw, list) or not plays_raw:
            self._err("play_missing", "本墩无 plays 记录")
            return fallback

        try:
            plays = [
                {"seat": int(p["seat"]), "cards": parse_cards(p.get("cards", []))}
                for p in plays_raw
            ]
        except (KeyError, TypeError, LogFormatError) as exc:
            self._err("play_parse", f"plays 解析失败: {exc}")
            return fallback

        if len(plays) != SEAT_COUNT:
            self._err("play_count", f"出牌记录 {len(plays)} 条，期望 {SEAT_COUNT} 条")

        # 先手座位
        logged_lead = trick.get("lead_seat")
        expected_lead = dealer if t_idx == 0 else prev_winner
        if expected_lead is not None and logged_lead != expected_lead:
            reason = "首墩应由庄家先手" if t_idx == 0 else "应由上墩赢家先手"
            self._err("lead_seat", f"先手 S{logged_lead}，期望 S{expected_lead}（{reason}）")
        if logged_lead is not None and plays[0]["seat"] != logged_lead:
            self._err(
                "lead_order",
                f"plays[0] 是 S{plays[0]['seat']}，但 lead_seat 记为 S{logged_lead}",
            )

        # 出牌顺序：自先手起逆时针
        expected_order = [(plays[0]["seat"] + i) % SEAT_COUNT for i in range(len(plays))]
        actual_order = [p["seat"] for p in plays]
        if actual_order != expected_order:
            self._err("play_order", f"出牌顺序 {actual_order}，期望 {expected_order}")

        lead_cards = plays[0]["cards"]
        if not lead_cards:
            self._err("lead_empty", "首出为空")
            return fallback

        lead_count = len(lead_cards)
        lead_domain = self.rules.suit_domain(lead_cards[0], trump_suit, current_rank)
        lead_pattern = self.rules.identify(lead_cards, current_rank)

        # 首出同域约束
        if not all(
            self.rules.domains_equal(
                self.rules.suit_domain(c, trump_suit, current_rank), lead_domain
            )
            for c in lead_cards
        ):
            self._err(
                "lead_mixed_domain",
                "首出 %s 跨域（首出必须同一花色域）"
                % " ".join(str(c) for c in lead_cards),
            )

        # 甩牌开关
        if lead_pattern is not None and lead_pattern.kind == TYPE_DUMP:
            if not self.config.allow_dump:
                self._err(
                    "dump_disabled",
                    "首出 %s 判定为甩牌，但 allow_dump=false"
                    % " ".join(str(c) for c in lead_cards),
                )
            elif hands is not None:
                self._check_dump_is_biggest(
                    plays[0]["seat"], lead_cards, lead_pattern,
                    hands, lead_domain, trump_suit, current_rank,
                )

        # 逐个跟牌校验（并消耗手牌）
        for order_idx, play in enumerate(plays):
            seat = play["seat"]
            cards = play["cards"]
            hand_before = hands[seat] if hands is not None else None

            if hand_before is not None:
                remaining, missing = remove_cards(hand_before, cards)
                if missing:
                    self._err(
                        "card_not_in_hand",
                        "S%d 打出 %s，但手牌中没有"
                        % (seat, ", ".join(str(c) for c in missing)),
                    )
                hands[seat] = remaining

            if order_idx == 0:
                continue

            if len(cards) != lead_count:
                self._err(
                    "follow_count",
                    f"S{seat} 跟牌 {len(cards)} 张，首出 {lead_count} 张",
                )

            if hand_before is None:
                continue

            self._check_follow_legality(
                seat, cards, hand_before, lead_count, lead_domain,
                lead_pattern, trump_suit, current_rank,
            )

        # 赢家复算
        logged_winner = trick.get("winner")
        if len(plays) == SEAT_COUNT:
            calculated = self.rules.determine_winner(plays, trump_suit, current_rank)
            if calculated != logged_winner:
                self._err(
                    "winner",
                    "赢家日志 S%s，复算 S%s（首出 %s，域=%s）"
                    % (
                        logged_winner, calculated,
                        " ".join(str(c) for c in lead_cards),
                        self.rules.domain_label(lead_domain),
                    ),
                )

        # 墩分
        all_cards = [c for p in plays for c in p["cards"]]
        trick_points = count_points(all_cards)
        for key in ("trick_points", "trick_score"):
            if key in trick and trick[key] != trick_points:
                self._err(
                    "trick_points",
                    f"{key} 日志 {trick[key]}，复算 {trick_points}",
                )

        # 攻方累计分
        winner_is_attack = logged_winner in attack_seats
        gain = trick_points if winner_is_attack else 0
        if "attack_gain" in trick and trick["attack_gain"] != gain:
            self._err("attack_gain", f"attack_gain 日志 {trick['attack_gain']}，复算 {gain}")
        if "attack_score_before" in trick and trick["attack_score_before"] != attack_score_before:
            self._err(
                "attack_score_before",
                f"attack_score_before 日志 {trick['attack_score_before']}，"
                f"复算 {attack_score_before}",
            )
        attack_score_after = attack_score_before + gain
        if "attack_score_after" in trick and trick["attack_score_after"] != attack_score_after:
            self._err(
                "attack_score_after",
                f"攻方累计分日志 {trick['attack_score_after']}，复算 {attack_score_after}",
            )

        # winner_side
        logged_side = trick.get("winner_side")
        if logged_side is not None:
            expected_side = "attack" if winner_is_attack else "dealer"
            if logged_side != expected_side:
                self._err(
                    "winner_side",
                    f"winner_side 日志 {logged_side}，S{logged_winner} 应为 {expected_side}",
                )

        winner_pattern = None
        for p in plays:
            if p["seat"] == logged_winner:
                winner_pattern = self.rules.identify(p["cards"], current_rank)
                break

        return {
            "attack_score": attack_score_after,
            "winner": logged_winner,
            "trick_points": trick_points,
            "winner_pattern": winner_pattern,
        }

    def c_allow_dump(self) -> bool:
        return self.config.allow_dump

    def _check_dump_is_biggest(
        self,
        seat: int,
        lead_cards: list[Card],
        lead_pattern: Pattern,
        hands: list[list[Card]],
        lead_domain: tuple[int, int],
        trump_suit: int,
        current_rank: int,
    ) -> None:
        """GDD card-types.md §2.3：甩牌的每个组成部分必须是该花色域当前最大。

        「当前最大」= 其他玩家手中该域内没有**更大**的同类牌型（相等不算）。
        失败时按 GDD 只能出最小的一张单牌，其余收回。

        引擎侧目前未实现这条（play_validator.validate_lead 只检查 allow_dump），
        因此这里报出的 dump_not_biggest 属于**已知功能缺口**，不是新回归。
        随机批跑不会触发（AI 从不甩牌），只有构造牌局能命中。
        """
        # 其他三家在该域内的牌
        others: list[Card] = []
        for other_seat in range(SEAT_COUNT):
            if other_seat == seat:
                continue
            for c in hands[other_seat]:
                dom = self.rules.suit_domain(c, trump_suit, current_rank)
                if self.rules.domains_equal(dom, lead_domain):
                    others.append(c)
        if not others:
            return

        # 对手在该域内能组成的最大单张 / 最大对子（按 pair_count 分档）
        best_single = max(
            (self.rules.sort_value(c, trump_suit, current_rank) for c in others),
            default=-1,
        )
        pair_values: list[int] = []
        counts: dict[tuple, list[Card]] = {}
        for c in others:
            counts.setdefault(c.identity, []).append(c)
        for same in counts.values():
            if len(same) >= 2:
                pair_values.append(
                    self.rules.sort_value(same[0], trump_suit, current_rank))
        best_pair = max(pair_values, default=-1)

        for comp in lead_pattern.components:
            comp_cards = self._component_cards(lead_cards, comp)
            if not comp_cards:
                continue
            value = self.rules.play_sort_value(comp_cards, trump_suit, current_rank)
            if comp.kind == TYPE_SINGLE:
                if best_single > value:
                    self._err(
                        "dump_not_biggest",
                        "S%d 甩牌 %s 中的单张 %s 不是%s域最大，"
                        "对手持有更大的牌（GDD card-types.md §2.3 应甩牌失败）"
                        % (seat, " ".join(str(c) for c in lead_cards),
                           " ".join(str(c) for c in comp_cards),
                           self.rules.domain_label(lead_domain)),
                    )
                    return
            elif comp.kind in (TYPE_PAIR, TYPE_TRACTOR):
                if best_pair > value:
                    self._err(
                        "dump_not_biggest",
                        "S%d 甩牌 %s 中的%s %s 不是%s域最大，"
                        "对手持有更大的对子（GDD card-types.md §2.3 应甩牌失败）"
                        % (seat, " ".join(str(c) for c in lead_cards),
                           "对子" if comp.kind == TYPE_PAIR else "拖拉机",
                           " ".join(str(c) for c in comp_cards),
                           self.rules.domain_label(lead_domain)),
                    )
                    return

    @staticmethod
    def _component_cards(lead_cards: list[Card], comp: Pattern) -> list[Card]:
        """从甩牌里取出该分量对应的牌。

        Pattern 只记了 pairs/张数没记具体牌，这里按 pairs 记录的点数回捞；
        单张分量取剩下的最小一张作近似（用于给出可读的报错文本）。
        """
        if comp.kind in (TYPE_PAIR, TYPE_TRACTOR) and comp.pairs:
            wanted = list(comp.pairs)
            picked: list[Card] = []
            for rank in wanted:
                for c in lead_cards:
                    if not c.is_joker and c.rank == rank and c not in picked:
                        picked.append(c)
                        if len([x for x in picked if x.rank == rank]) >= 2:
                            break
            return picked
        if comp.kind == TYPE_SINGLE:
            counts: dict[tuple, int] = {}
            for c in lead_cards:
                counts[c.identity] = counts.get(c.identity, 0) + 1
            singles = [c for c in lead_cards if counts[c.identity] == 1]
            return singles[:1]
        return []

    def _check_follow_legality(
        self,
        seat: int,
        cards: list[Card],
        hand_before: list[Card],
        lead_count: int,
        lead_domain: tuple[int, int],
        lead_pattern: Optional[Pattern],
        trump_suit: int,
        current_rank: int,
    ) -> None:
        """PlayValidator.validate_follow 的复算。"""
        domain_in_hand = [
            c for c in hand_before
            if self.rules.domains_equal(
                self.rules.suit_domain(c, trump_suit, current_rank), lead_domain
            )
        ]
        played_domain = [
            c for c in cards
            if self.rules.domains_equal(
                self.rules.suit_domain(c, trump_suit, current_rank), lead_domain
            )
        ]

        required = min(len(domain_in_hand), lead_count)
        if len(played_domain) < required:
            self._err(
                "follow_domain",
                "S%d 手中有 %d 张%s牌须跟，实际只跟 %d 张（出 %s）"
                % (
                    seat, required, self.rules.domain_label(lead_domain),
                    len(played_domain), " ".join(str(c) for c in cards),
                ),
            )
            return

        if not self.config.strict_follow_structure or lead_pattern is None:
            return
        if len(played_domain) < lead_count:
            return

        # 首出结构里"必须被对上"的对子数。甩牌取各分量之和 ——
        # 不许拆对是平衡杠杆（逼跟牌方交分），甩牌首出同样要生效，
        # 否则甩牌反而比出对子更逼不出分。
        required_pairs = self._required_pair_count(lead_pattern)
        if required_pairs <= 0:
            return

        hand_pairs = self._count_pairs(domain_in_hand)
        if hand_pairs <= 0:
            return

        needed = min(hand_pairs, required_pairs)
        got = self._count_pairs(played_domain)
        if got < needed:
            kind_label = {
                TYPE_PAIR: "对子",
                TYPE_TRACTOR: "拖拉机",
                TYPE_DUMP: "甩牌",
            }.get(lead_pattern.kind, lead_pattern.kind)
            self._err(
                "follow_structure",
                "S%d 手中有 %d 个同域对子，跟%s须出 %d 个，实际只出 %d 个（%s）"
                % (seat, hand_pairs, kind_label, needed, got,
                   " ".join(str(c) for c in cards)),
            )

    @staticmethod
    def _required_pair_count(pattern: Pattern) -> int:
        if pattern.kind == TYPE_PAIR:
            return 1
        if pattern.kind == TYPE_TRACTOR:
            return pattern.pair_count
        if pattern.kind == TYPE_DUMP:
            return sum(
                LogValidator._required_pair_count(c) for c in pattern.components
            )
        return 0

    @staticmethod
    def _count_pairs(cards: list[Card]) -> int:
        counts: dict[tuple, int] = {}
        for c in cards:
            counts[c.identity] = counts.get(c.identity, 0) + 1
        return sum(n // 2 for n in counts.values())

    # ---- settlement ----

    def _validate_settlement(
        self,
        rd: dict,
        dealer: int,
        current_rank: int,
        team_ranks: Any,
        attack_seats: set[int],
        attack_score: int,
        buried: list[Card],
        last_winner: Optional[int],
        last_pattern: Optional[Pattern],
    ) -> tuple[Optional[int], Optional[list[int]]]:
        settlement = rd.get("settlement")
        if not isinstance(settlement, dict) or not settlement:
            self._skip(f"R{self._round_num} settlement 为空，结算未校验")
            return (None, None)

        if last_winner is None:
            self._skip(f"R{self._round_num} 无有效末墩，结算未校验")
            return (None, None)

        attack_rank = -1
        if isinstance(team_ranks, list) and len(team_ranks) >= 2:
            attack_rank = int(team_ranks[(dealer + 1) % 2])

        proposal_expected = self.rules.calculate_settlement(
            attack_score=attack_score,
            bottom_cards=buried,
            dealer_seat=dealer,
            last_trick_winner_is_attack=last_winner in attack_seats,
            last_trick_pattern=last_pattern,
            current_rank=current_rank,
            attack_rank=attack_rank,
        )
        # 顶层字段与 effective 记录的是会话层裁决后的值，不是原始提案
        effective_expected = self.rules.apply_session_verdict(proposal_expected, dealer)

        if self._round_num is not None:
            self.round_reports[self._round_num] = {
                "proposal": proposal_expected,
                "effective": effective_expected,
            }

        for f in SETTLEMENT_FIELDS:
            if f not in settlement:
                self._err("settlement_missing", f"结算缺字段 {f}")
                continue
            if settlement[f] != effective_expected[f]:
                extra = ""
                if f in ("new_rank",):
                    extra = " [%s vs %s]" % (
                        rank_symbol(settlement[f]), rank_symbol(effective_expected[f]))
                self._err(
                    "settlement",
                    f"结算 {f} 日志={settlement[f]}，复算={effective_expected[f]}{extra}",
                )

        # upgrading_team
        if "upgrading_team" in settlement:
            side = settlement.get("upgrading_side", effective_expected["upgrading_side"])
            expected_team = dealer % 2 if side == 0 else (dealer + 1) % 2
            if settlement["upgrading_team"] != expected_team:
                self._err(
                    "upgrading_team",
                    f"upgrading_team 日志={settlement['upgrading_team']}，"
                    f"复算={expected_team}（庄家 S{dealer}, side={side}）",
                )

        verdict_keys = ("upgrade_levels", "new_rank", "new_dealer", "game_over")

        # proposed 子结构对照"提案层"复算值。
        # 它与 effective 的差异是合法的（game_over 时不切庄），
        # 所以两者各自与对应层的复算值比对，而不是互相比对。
        proposed = settlement.get("proposed")
        if isinstance(proposed, dict):
            for key in verdict_keys:
                if key in proposed and proposed[key] != proposal_expected[key]:
                    self._err(
                        "proposed_field",
                        f"proposed.{key} 日志={proposed[key]}，"
                        f"提案层复算={proposal_expected[key]}",
                    )

        # effective 子结构必须与顶层字段严格一致（顶层就是 effective 的副本）
        effective = settlement.get("effective")
        if isinstance(effective, dict):
            for key in verdict_keys:
                if key in effective and key in settlement:
                    if effective[key] != settlement[key]:
                        self._err(
                            "effective_divergence",
                            f"settlement.{key}={settlement[key]} 与 "
                            f"effective.{key}={effective[key]} 不一致"
                            "（顶层字段应等于 effective）",
                        )

        # 推进到下局的预期状态。用日志值而非复算值推进，
        # 使"结算算错"与"结算没被正确应用到下局"成为两条独立信号，避免级联误报。
        next_dealer, next_team_ranks = self._project_next_round(
            rd, dealer, settlement, team_ranks
        )
        return (next_dealer, next_team_ranks)

    def _project_next_round(
        self, rd: dict, dealer: int, settlement: dict, team_ranks: Any
    ) -> tuple[Optional[int], Optional[list[int]]]:
        """复算 SessionState.apply_settlement 对下一局的影响。"""
        if settlement.get("game_over"):
            return (None, None)

        ranks: Optional[list[int]] = None
        if isinstance(team_ranks, list) and len(team_ranks) >= 2:
            ranks = [int(r) for r in team_ranks]
            levels = settlement.get("upgrade_levels")
            new_rank = settlement.get("new_rank")
            side = settlement.get("upgrading_side")
            if isinstance(levels, int) and levels > 0 and isinstance(new_rank, int):
                if side == 0:
                    upgrading_team = dealer % 2
                else:
                    upgrading_team = (dealer + 1) % 2
                ranks[upgrading_team] = new_rank

        new_dealer = settlement.get("new_dealer")
        next_dealer = new_dealer if isinstance(new_dealer, int) and new_dealer >= 0 else dealer
        return (next_dealer, ranks)


# ============================================================
# 报告
# ============================================================


def validate_file(path: Path) -> dict:
    """校验单个日志文件，返回结构化结果。"""
    try:
        log = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return {
            "file": str(path),
            "ok": False,
            "fatal": f"无法读取日志: {exc}",
            "errors": 0,
            "warnings": 0,
            "issues": [],
            "skipped": [],
        }

    try:
        validator = LogValidator(log, str(path))
        issues = validator.validate()
    except LogFormatError as exc:
        return {
            "file": str(path),
            "ok": False,
            "fatal": str(exc),
            "errors": 0,
            "warnings": 0,
            "issues": [],
            "skipped": [],
        }

    errors = [i for i in issues if i.level == "error"]
    warnings = [i for i in issues if i.level == "warning"]
    return {
        "file": str(path),
        "ok": not errors,
        "fatal": None,
        "errors": len(errors),
        "warnings": len(warnings),
        "rounds": len(log.get("rounds") or []),
        "preset": (log.get("rule_config") or {}).get("base_preset"),
        "issues": [i.to_dict() for i in issues],
        "skipped": validator.skipped_checks,
    }


def print_report(result: dict, verbose: bool) -> None:
    name = Path(result["file"]).name
    if result["fatal"]:
        print(f"[FATAL] {name}: {result['fatal']}")
        return

    status = "OK" if result["ok"] else "FAIL"
    print(
        f"[{status}] {name} — {result['rounds']} 局，"
        f"{result['errors']} error / {result['warnings']} warning"
    )

    issues = result["issues"]
    if issues:
        shown = issues if verbose else issues[:20]
        for i in shown:
            loc_parts = []
            if i["round"] is not None:
                loc_parts.append(f"R{i['round']}")
            if i["trick"] is not None:
                loc_parts.append(f"T{i['trick']}")
            loc = ".".join(loc_parts) or "-"
            tag = "E" if i["level"] == "error" else "W"
            print(f"  [{tag}] {loc:>8} {i['code']}: {i['message']}")
        if len(issues) > len(shown):
            print(f"  ... 另有 {len(issues) - len(shown)} 条（-v 查看全部）")

    for s in result["skipped"]:
        print(f"  [跳过] {s}")


def collect_logs(target: Path) -> list[Path]:
    if target.is_file():
        return [target]
    if target.is_dir():
        return sorted(p for p in target.rglob("game_*.json"))
    return []


def force_utf8_stdout() -> None:
    """Windows 控制台默认 GBK，会把中文与花色符号打成乱码。

    批跑脚本也调用本函数，保持三处输出一致。
    """
    for stream in (sys.stdout, sys.stderr):
        enc = (getattr(stream, "encoding", "") or "").lower()
        if enc.replace("-", "") != "utf8":
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except (AttributeError, OSError):
                pass


def main() -> int:
    force_utf8_stdout()

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", type=Path, help="日志文件，或含 game_*.json 的目录")
    ap.add_argument("-v", "--verbose", action="store_true", help="打印全部问题")
    ap.add_argument("--json", dest="as_json", action="store_true",
                    help="输出 JSON（供批跑工具消费）")
    args = ap.parse_args()

    target = args.target
    if not target.exists():
        repo_relative = Path(__file__).resolve().parents[1] / target
        if repo_relative.exists():
            target = repo_relative
        else:
            print(f"路径不存在: {args.target}", file=sys.stderr)
            return 2

    paths = collect_logs(target)
    if not paths:
        print(f"未找到日志: {target}", file=sys.stderr)
        return 2

    results = [validate_file(p) for p in paths]

    if args.as_json:
        total_errors = sum(r["errors"] for r in results)
        fatals = sum(1 for r in results if r["fatal"])
        print(json.dumps(
            {
                "files": len(results),
                "failed": sum(1 for r in results if not r["ok"]),
                "total_errors": total_errors,
                "fatal_files": fatals,
                "results": results,
            },
            ensure_ascii=False, indent=2,
        ))
        return 1 if (total_errors or fatals) else 0

    for r in results:
        print_report(r, args.verbose)

    if len(results) > 1:
        failed = [r for r in results if not r["ok"]]
        print()
        print(f"=== 汇总: {len(results)} 个日志，{len(failed)} 个有问题 ===")
        for r in failed:
            reason = r["fatal"] or f"{r['errors']} error"
            print(f"  {Path(r['file']).name}: {reason}")

    return 1 if any(not r["ok"] for r in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())



