#!/usr/bin/env python3
"""
Export a game log JSON file to an interactive single-file HTML replay.

The exporter intentionally re-implements the core rule checks instead of
importing Godot scripts, so replay pages can expose disagreements between the
logged game state and an independent analyzer.
"""

from __future__ import annotations

import argparse
import html
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


SUIT_SYMBOL_TO_ID = {"♠": 0, "♥": 1, "♦": 2, "♣": 3}
SUIT_ID_TO_SYMBOL = {v: k for k, v in SUIT_SYMBOL_TO_ID.items()}
RANK_SYMBOL_TO_VALUE = {
    "2": 2,
    "3": 3,
    "4": 4,
    "5": 5,
    "6": 6,
    "7": 7,
    "8": 8,
    "9": 9,
    "10": 10,
    "J": 11,
    "Q": 12,
    "K": 13,
    "A": 14,
}
RANK_VALUE_TO_SYMBOL = {v: k for k, v in RANK_SYMBOL_TO_VALUE.items()}
RANK_SEQUENCE = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
POINT_VALUES = {5: 5, 10: 10, 13: 10}
DEFAULT_UPGRADE_TABLE = [
    (0, 0, 3),
    (1, 0, 2),
    (40, 0, 1),
    (80, 1, 0),
    (120, 1, 1),
    (160, 1, 2),
    (200, 1, 3),
]
NO_SKIP_RANKS = {5, 10, 13}
SEAT_NAMES = ["南 / 你", "东", "北 / 搭档", "西"]
TEAM_NAMES = ["南北队", "东西队"]


@dataclass(frozen=True)
class Card:
    raw: str
    suit: int
    rank: int
    joker: Optional[str] = None

    @property
    def point(self) -> int:
        return POINT_VALUES.get(self.rank, 0)

    @property
    def identity(self) -> str:
        if self.joker:
            return self.joker
        return f"{self.suit}:{self.rank}"


@dataclass
class Pattern:
    kind: str
    card_count: int
    pair_count: int = 0
    components: Optional[List["Pattern"]] = None


def parse_card(raw: str) -> Card:
    if raw == "BlackJoker":
        return Card(raw=raw, suit=4, rank=16, joker="BlackJoker")
    if raw == "RedJoker":
        return Card(raw=raw, suit=4, rank=17, joker="RedJoker")
    if len(raw) < 2:
        raise ValueError(f"Bad card string: {raw}")
    suit = SUIT_SYMBOL_TO_ID[raw[0]]
    rank = RANK_SYMBOL_TO_VALUE[raw[1:]]
    return Card(raw=raw, suit=suit, rank=rank)


def cards(raw_cards: Iterable[str]) -> List[Card]:
    return [parse_card(c) for c in raw_cards]


def rank_symbol(rank: int) -> str:
    return RANK_VALUE_TO_SYMBOL.get(rank, str(rank))


def skip_sequence(current_rank: int) -> List[int]:
    return [r for r in RANK_SEQUENCE if r != current_rank]


def domain(card: Card, trump_suit: int, current_rank: int, joker_always_trump: bool = True) -> Tuple[str, int]:
    if card.joker:
        return ("TRUMP", -1) if joker_always_trump else ("NONE", -1)
    if card.rank == current_rank:
        return ("TRUMP", -1)
    if trump_suit >= 0 and card.suit == trump_suit:
        return ("TRUMP", -1)
    return ("SIDE", card.suit)


def domains_equal(a: Tuple[str, int], b: Tuple[str, int]) -> bool:
    if a[0] != b[0]:
        return False
    if a[0] == "SIDE":
        return a[1] == b[1]
    return True


def domain_label(dom: Tuple[str, int]) -> str:
    if dom[0] == "TRUMP":
        return "主牌"
    if dom[0] == "SIDE":
        return f"{SUIT_ID_TO_SYMBOL.get(dom[1], '?')}副"
    return "无域"


def sort_value(card: Card, trump_suit: int, current_rank: int, joker_always_trump: bool = True) -> int:
    dom = domain(card, trump_suit, current_rank, joker_always_trump)
    if card.joker:
        if dom[0] == "NONE":
            return -1
        return 140 if card.joker == "BlackJoker" else 150
    if dom[0] == "TRUMP":
        if card.rank == current_rank and trump_suit >= 0 and card.suit == trump_suit:
            return 130
        if card.rank == current_rank:
            return 120
        seq = skip_sequence(current_rank)
        return 100 + seq.index(card.rank) if card.rank in seq else 100
    seq = skip_sequence(current_rank)
    idx = seq.index(card.rank) if card.rank in seq else 0
    return card.suit * 15 + idx


def identify_pattern(play_cards: List[Card], current_rank: int) -> Optional[Pattern]:
    if not play_cards:
        return None
    if len(play_cards) == 1:
        return Pattern("Single", 1)
    if len(play_cards) == 2 and play_cards[0].identity == play_cards[1].identity:
        return Pattern("Pair", 2, 1)
    tractor = try_tractor(play_cards, current_rank)
    if tractor:
        return tractor
    if len(play_cards) >= 2:
        return Pattern("Dump", len(play_cards), components=decompose_dump(play_cards, current_rank))
    return None


def try_tractor(play_cards: List[Card], current_rank: int) -> Optional[Pattern]:
    if len(play_cards) < 4 or len(play_cards) % 2 != 0:
        return None
    counts: Dict[str, Tuple[Card, int]] = {}
    for c in play_cards:
        if c.joker:
            return None
        prev = counts.get(c.identity)
        counts[c.identity] = (c, (prev[1] if prev else 0) + 1)
    pair_ranks: List[int] = []
    for c, count in counts.values():
        pair_ranks.extend([c.rank] * (count // 2))
    if len(pair_ranks) * 2 != len(play_cards) or len(pair_ranks) < 2:
        return None
    pair_ranks.sort(key=lambda r: RANK_SEQUENCE.index(r))
    for a, b in zip(pair_ranks, pair_ranks[1:]):
        if not ranks_adjacent(a, b, current_rank):
            return None
    return Pattern("Tractor", len(play_cards), len(pair_ranks))


def ranks_adjacent(a: int, b: int, current_rank: int) -> bool:
    if abs(RANK_SEQUENCE.index(a) - RANK_SEQUENCE.index(b)) == 1:
        return True
    seq = skip_sequence(current_rank)
    return a in seq and b in seq and abs(seq.index(a) - seq.index(b)) == 1


def decompose_dump(play_cards: List[Card], current_rank: int) -> List[Pattern]:
    remaining = list(play_cards)
    components: List[Pattern] = []
    while len(remaining) >= 2:
        found = False
        for i in range(len(remaining)):
            for j in range(i + 1, len(remaining)):
                if remaining[i].identity == remaining[j].identity:
                    components.append(Pattern("Pair", 2, 1))
                    remaining.pop(j)
                    remaining.pop(i)
                    found = True
                    break
            if found:
                break
        if not found:
            break
    components.extend(Pattern("Single", 1) for _ in remaining)
    return components


def structure_matches(play_pattern: Optional[Pattern], lead_pattern: Optional[Pattern]) -> bool:
    if not play_pattern or not lead_pattern:
        return False
    if play_pattern.kind != lead_pattern.kind:
        return False
    if play_pattern.kind == "Tractor":
        return play_pattern.pair_count >= lead_pattern.pair_count
    return True


def play_value(play_cards: List[Card], trump_suit: int, current_rank: int) -> int:
    return max(sort_value(c, trump_suit, current_rank) for c in play_cards)


def determine_winner(plays: List[Dict[str, Any]], trump_suit: int, current_rank: int) -> int:
    parsed_plays = []
    for p in plays:
        cs = cards(p.get("cards", []))
        parsed_plays.append(
            {
                "seat": p["seat"],
                "cards": cs,
                "domain": domain(cs[0], trump_suit, current_rank) if cs else ("NONE", -1),
                "pattern": identify_pattern(cs, current_rank),
                "value": play_value(cs, trump_suit, current_rank) if cs else -1,
            }
        )
    lead = parsed_plays[0]
    lead_domain = lead["domain"]
    lead_pattern = lead["pattern"]
    lead_is_trump = domains_equal(lead_domain, ("TRUMP", -1))

    best_seat = lead["seat"]
    best_value = lead["value"]
    best_is_trump_kill = False

    for p in parsed_plays[1:]:
        play_is_trump = p["domain"][0] == "TRUMP"
        is_same_domain = domains_equal(p["domain"], lead_domain)
        if lead_is_trump:
            if is_same_domain and structure_matches(p["pattern"], lead_pattern) and p["value"] > best_value:
                best_seat = p["seat"]
                best_value = p["value"]
        elif play_is_trump and not is_same_domain:
            if not structure_matches(p["pattern"], lead_pattern):
                continue
            if not best_is_trump_kill or p["value"] > best_value:
                best_seat = p["seat"]
                best_value = p["value"]
                best_is_trump_kill = True
        elif is_same_domain and not best_is_trump_kill:
            if structure_matches(p["pattern"], lead_pattern) and p["value"] > best_value:
                best_seat = p["seat"]
                best_value = p["value"]
    return best_seat


def count_points(raw_cards: Iterable[str]) -> int:
    return sum(parse_card(c).point for c in raw_cards)


def count_pairs_in_domain(raw_cards: Iterable[str], lead_domain: Tuple[str, int], trump_suit: int, current_rank: int) -> List[str]:
    counts: Dict[str, int] = {}
    labels: Dict[str, str] = {}
    for c in cards(raw_cards):
        if domains_equal(domain(c, trump_suit, current_rank), lead_domain):
            counts[c.identity] = counts.get(c.identity, 0) + 1
            labels[c.identity] = c.raw
    return sorted(labels[k] for k, v in counts.items() if v >= 2)


def bottom_multiplier(pattern: Optional[Pattern]) -> int:
    if not pattern:
        return 1
    if pattern.kind == "Single":
        return 1
    if pattern.kind == "Pair":
        return 2
    if pattern.kind == "Tractor":
        return pattern.pair_count * 2
    if pattern.kind == "Dump":
        return max((bottom_multiplier(c) for c in pattern.components or []), default=1)
    return 1


def apply_upgrade(rank: int, levels: int, no_skip_enabled: bool = True) -> int:
    current = rank
    for i in range(levels):
        idx = RANK_SEQUENCE.index(current)
        if idx >= len(RANK_SEQUENCE) - 1:
            return 14
        current = RANK_SEQUENCE[idx + 1]
        if no_skip_enabled and i < levels - 1 and current in NO_SKIP_RANKS:
            return current
    return current


def expected_settlement(round_data: Dict[str, Any], next_round: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    tricks = round_data.get("tricks", [])
    settlement = round_data.get("settlement", {})
    dealer = round_data.get("dealer", 0)
    current_rank = round_data.get("rank", 2)
    final_trick = tricks[-1] if tricks else {}
    last_winner_is_attack = final_trick.get("winner_side") == "attack"
    base_score = tricks[-1].get("attack_score_after", 0) if tricks else 0
    bottom_cards = round_data.get("debug", {}).get("buried_cards", [])
    bottom_score = count_points(bottom_cards) if last_winner_is_attack else 0
    winner_play = None
    for p in final_trick.get("plays", []):
        if p.get("seat") == final_trick.get("winner"):
            winner_play = p
            break
    winner_pattern = identify_pattern(cards(winner_play.get("cards", [])), current_rank) if winner_play else None
    mult = bottom_multiplier(winner_pattern) if last_winner_is_attack else 0
    final_score = base_score + bottom_score * mult

    side, levels = 0, 0
    for minimum, row_side, row_levels in DEFAULT_UPGRADE_TABLE:
        if final_score >= minimum:
            side, levels = row_side, row_levels

    dealer_team = dealer % 2
    attack_team = (dealer + 1) % 2
    team_ranks = round_data.get("team_ranks") or []
    base_rank = current_rank
    if side == 1 and len(team_ranks) >= 2:
        base_rank = team_ranks[attack_team]
    new_rank = apply_upgrade(base_rank, levels) if levels > 0 else current_rank
    return {
        "attack_base_score": base_score,
        "bottom_score": bottom_score,
        "bottom_multiplier": mult,
        "bottom_bonus": bottom_score * mult,
        "final_score": final_score,
        "upgrading_side": side,
        "upgrade_levels": levels,
        "dealer_dethroned": final_score >= 80,
        "new_dealer": (dealer + 1) % 4 if final_score >= 80 else -1,
        "new_rank": new_rank,
        "upgrading_team": dealer_team if side == 0 else attack_team,
        "next_round_actual_dealer": None if not next_round else next_round.get("dealer"),
    }


def analyze_log(log: Dict[str, Any]) -> Dict[str, Any]:
    rounds = log.get("rounds", [])
    all_issues: List[Dict[str, Any]] = []
    round_reports = []
    previous_expected_dealer: Optional[int] = None
    previous_team_ranks: Optional[List[int]] = None

    for idx, round_data in enumerate(rounds):
        round_issues: List[Dict[str, Any]] = []
        trick_reports = []
        trump_suit = round_data.get("trump_suit", -1)
        current_rank = round_data.get("rank", 2)
        dealer = round_data.get("dealer", 0)
        attack_team = set(round_data.get("attack_team") or [s for s in range(4) if s % 2 != dealer % 2])
        dealer_reason = describe_dealer_rotation(previous_expected_dealer, dealer, round_data.get("bid_history", []))

        if previous_expected_dealer is not None:
            dealer_check = check_dealer_rotation(previous_expected_dealer, dealer, round_data.get("bid_history", []))
            if dealer_check:
                round_issues.append(dealer_check)

        team_ranks = round_data.get("team_ranks") or []
        if len(team_ranks) >= 2:
            expected_rank = team_ranks[dealer % 2]
            if current_rank != expected_rank:
                round_issues.append(issue("error", "round_rank", f"本局打级 {rank_symbol(current_rank)} 与庄家队等级 {rank_symbol(expected_rank)} 不一致。"))

        expected_score = 0
        previous_winner = None
        for t_idx, trick in enumerate(round_data.get("tricks", [])):
            plays = trick.get("plays", [])
            trick_issues: List[Dict[str, Any]] = []
            if len(plays) != 4:
                trick_issues.append(issue("error", "play_count", f"本墩出牌记录数为 {len(plays)}，期望 4。"))
            if plays:
                expected_lead = dealer if t_idx == 0 else previous_winner
                if expected_lead is not None and trick.get("lead_seat") != expected_lead:
                    trick_issues.append(issue("error", "lead_seat", f"先手 S{trick.get('lead_seat')} 与期望 S{expected_lead} 不一致。"))
                expected_order = [(plays[0]["seat"] + i) % 4 for i in range(len(plays))]
                actual_order = [p.get("seat") for p in plays]
                if actual_order != expected_order:
                    trick_issues.append(issue("error", "play_order", f"出牌顺序 {actual_order} 与期望 {expected_order} 不一致。"))
                lead_cards = cards(plays[0].get("cards", []))
                lead_count = len(lead_cards)
                lead_domain = domain(lead_cards[0], trump_suit, current_rank) if lead_cards else ("NONE", -1)
                lead_pattern = identify_pattern(lead_cards, current_rank)
                for play in plays[1:]:
                    raw_play = play.get("cards", [])
                    if len(raw_play) != lead_count:
                        trick_issues.append(issue("warning", "follow_count", f"S{play.get('seat')} 跟牌 {len(raw_play)} 张，首出 {lead_count} 张。"))
                    hand_before = find_hand_before(trick, play.get("seat"))
                    if hand_before:
                        pairs = count_pairs_in_domain(hand_before, lead_domain, trump_suit, current_rank)
                        played_cards = cards(raw_play)
                        played_domain_cards = [c for c in played_cards if domains_equal(domain(c, trump_suit, current_rank), lead_domain)]
                        required = min(len([c for c in cards(hand_before) if domains_equal(domain(c, trump_suit, current_rank), lead_domain)]), lead_count)
                        if len(played_domain_cards) < required:
                            trick_issues.append(issue("error", "follow_domain", f"S{play.get('seat')} 有 {required} 张首出域牌应跟，实际只跟 {len(played_domain_cards)} 张。"))
                        if lead_pattern and lead_pattern.kind == "Pair" and pairs:
                            played_pair = len(played_domain_cards) >= 2 and played_domain_cards[0].identity == played_domain_cards[1].identity
                            if not played_pair:
                                trick_issues.append(issue("error", "must_follow_pair", f"S{play.get('seat')} 有同域对子 {', '.join(pairs)}，但未跟对子。"))

                if len(plays) == 4:
                    calculated_winner = determine_winner(plays, trump_suit, current_rank)
                    if calculated_winner != trick.get("winner"):
                        trick_issues.append(issue("error", "winner", f"赢家日志为 S{trick.get('winner')}，独立复算为 S{calculated_winner}。"))

                trick_points = sum(count_points(p.get("cards", [])) for p in plays)
                if trick_points != trick.get("trick_points", trick.get("trick_score", 0)):
                    trick_issues.append(issue("error", "trick_points", f"本墩牌点日志 {trick.get('trick_points')}，复算 {trick_points}。"))
                attack_gain = trick_points if trick.get("winner") in attack_team else 0
                expected_score += attack_gain
                if expected_score != trick.get("attack_score_after", 0):
                    trick_issues.append(issue("error", "attack_score", f"攻方累计分日志 {trick.get('attack_score_after')}，复算 {expected_score}。"))
                previous_winner = trick.get("winner")

            round_issues.extend(trick_issues)
            trick_reports.append({"trick": trick, "issues": trick_issues})

        expected = expected_settlement(round_data, rounds[idx + 1] if idx + 1 < len(rounds) else None)
        settlement = round_data.get("settlement", {})
        if settlement:
            for key in ["attack_base_score", "bottom_score", "bottom_multiplier", "bottom_bonus", "final_score", "upgrading_side", "upgrade_levels", "new_dealer", "new_rank"]:
                if settlement.get(key) != expected.get(key):
                    round_issues.append(issue("error", "settlement", f"结算字段 {key} 日志={settlement.get(key)}，复算={expected.get(key)}。"))

        previous_expected_dealer = expected["new_dealer"] if expected["new_dealer"] >= 0 else dealer
        previous_team_ranks = update_team_ranks(team_ranks, expected)
        all_issues.extend(add_round_context(round_data.get("round_num", idx + 1), round_issues))
        round_reports.append(
            {
                "round": round_data,
                "tricks": trick_reports,
                "issues": round_issues,
                "expected_settlement": expected,
                "expected_next_dealer": previous_expected_dealer,
                "expected_team_ranks_after": previous_team_ranks,
                "dealer_reason": dealer_reason,
            }
        )

    return {"rounds": round_reports, "issues": all_issues}


def issue(level: str, code: str, message: str) -> Dict[str, Any]:
    return {"level": level, "code": code, "message": message}


def add_round_context(round_num: int, issues: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [dict(i, round_num=round_num) for i in issues]


def normalize_bid_history(raw_history: Any) -> List[Dict[str, Any]]:
    if isinstance(raw_history, list):
        return [h for h in raw_history if isinstance(h, dict)]
    if isinstance(raw_history, dict):
        return [raw_history]
    return []


def check_dealer_rotation(expected_dealer: int, actual_dealer: int, raw_bid_history: Any) -> Optional[Dict[str, Any]]:
    if actual_dealer == expected_dealer:
        return None

    bid_history = normalize_bid_history(raw_bid_history)
    first_bid = next((b for b in bid_history if b.get("action") == "bid"), None)
    if not first_bid:
        return issue(
            "error",
            "dealer_rotation",
            f"本局庄家 S{actual_dealer} 与上局结算期望 S{expected_dealer} 不一致，且没有亮主成功记录。",
        )

    if first_bid.get("seat") != actual_dealer:
        return issue(
            "error",
            "dealer_rotation",
            f"本局庄家 S{actual_dealer} 与首个亮主座位 S{first_bid.get('seat')} 不一致。",
        )

    seats_before_actual = []
    seat = expected_dealer
    while seat != actual_dealer:
        seats_before_actual.append(seat)
        seat = (seat + 1) % 4
        if len(seats_before_actual) > 4:
            break

    for seat in seats_before_actual:
        skip = next((b for b in bid_history if b.get("seat") == seat and b.get("action") == "skip"), None)
        if not skip:
            return issue(
                "error",
                "dealer_rotation",
                f"本局庄家从期望 S{expected_dealer} 顺延到 S{actual_dealer}，但 S{seat} 没有跳过记录。",
            )
    return None


def format_skip_reason(reason: Any) -> str:
    if reason == "no_valid_cards":
        return "无可定主牌"
    if reason == "player_choice":
        return "玩家选择不定主"
    if reason == "ai_pass":
        return "AI 放弃定主"
    if reason == "already_bid":
        return "已有他人定主"
    if reason == "bid_rejected":
        return "定主被拒"
    return str(reason or "unknown")


def describe_dealer_rotation(expected_dealer: Optional[int], actual_dealer: int, raw_bid_history: Any) -> str:
    bid_history = normalize_bid_history(raw_bid_history)
    first_bid = next((b for b in bid_history if b.get("action") == "bid"), None)
    if expected_dealer is None:
        if first_bid:
            return "首局由 S%d 亮 %s，成为庄家。" % (first_bid.get("seat"), first_bid.get("suit_symbol", "主"))
        return "首局未记录亮主成功者。"

    if actual_dealer == expected_dealer:
        if first_bid and first_bid.get("seat") == actual_dealer:
            return "上局结算期望庄家 S%d，本局由其成功亮 %s，庄家不变。" % (
                expected_dealer,
                first_bid.get("suit_symbol", "主"),
            )
        return "上局结算期望庄家 S%d，本局庄家不变。" % expected_dealer

    parts = ["上局结算期望庄家 S%d 先定主" % expected_dealer]
    seat = expected_dealer
    while seat != actual_dealer:
        skip = next((b for b in bid_history if b.get("seat") == seat and b.get("action") == "skip"), None)
        if skip:
            parts.append("S%d 跳过（%s）" % (seat, format_skip_reason(skip.get("reason"))))
        else:
            parts.append("S%d 未见跳过记录" % seat)
        seat = (seat + 1) % 4
        if len(parts) > 6:
            break
    if first_bid:
        parts.append("S%d 亮 %s，庄家顺延为 S%d" % (
            first_bid.get("seat"),
            first_bid.get("suit_symbol", "主"),
            actual_dealer,
        ))
    else:
        parts.append("最终庄家为 S%d，但未见亮主成功记录" % actual_dealer)
    return "；".join(parts) + "。"


def find_hand_before(trick: Dict[str, Any], seat: int) -> List[str]:
    for hand in trick.get("debug", {}).get("hands_before", []):
        if hand.get("seat") == seat:
            return hand.get("cards", [])
    return []


def find_hand_after(trick: Dict[str, Any], seat: int) -> List[str]:
    for hand in trick.get("debug", {}).get("hands_after", []):
        if hand.get("seat") == seat:
            return hand.get("cards", [])
    before = find_hand_before(trick, seat)
    play = next((p for p in trick.get("plays", []) if p.get("seat") == seat), None)
    if not before or not play:
        return []
    return remove_cards(before, play.get("cards", []))


def remove_cards(source: List[str], removed: Iterable[str]) -> List[str]:
    result = list(source)
    for card in removed:
        try:
            result.remove(card)
        except ValueError:
            pass
    return result


def update_team_ranks(team_ranks: List[int], expected: Dict[str, Any]) -> Optional[List[int]]:
    if len(team_ranks) < 2:
        return None
    result = list(team_ranks)
    if expected["upgrade_levels"] > 0:
        result[expected["upgrading_team"]] = expected["new_rank"]
    return result


def render_html(log: Dict[str, Any], analysis: Dict[str, Any], source_path: Path) -> str:
    title = f"双升日志复盘 - {source_path.name}"
    nav = []
    sections = []
    for idx, report in enumerate(analysis["rounds"]):
        r = report["round"]
        errors = sum(1 for i in report["issues"] if i["level"] == "error")
        warnings = sum(1 for i in report["issues"] if i["level"] == "warning")
        badge = f"{errors} 错 / {warnings} 警"
        nav.append(f'<button class="round-tab" data-target="round-{idx}">第 {esc(r.get("round_num", idx + 1))} 局 <span>{esc(badge)}</span></button>')
        sections.append(render_round(report, idx))

    corrections_seed = {"source": str(source_path), "created_from": log.get("created_at"), "corrections": {}}
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{esc(title)}</title>
  <style>{CSS}</style>
</head>
<body>
  <header class="app-header">
    <div>
      <h1>{esc(title)}</h1>
      <p>日志时间：{esc(log.get("created_at", "未知"))} · 总局数：{len(analysis["rounds"])} · 自动分析：{len(analysis["issues"])} 项问题/提示</p>
    </div>
    <div class="header-actions">
      <button id="expand-all">展开全部墩</button>
      <button id="collapse-all">收起全部墩</button>
      <button id="export-corrections">导出订正 JSON</button>
    </div>
  </header>
  <nav class="round-nav">{''.join(nav)}</nav>
  <main>{''.join(sections)}</main>
  <script>
    window.REPLAY_CORRECTIONS_SEED = {json.dumps(corrections_seed, ensure_ascii=False)};
{JS}
  </script>
</body>
</html>
"""


def render_round(report: Dict[str, Any], idx: int) -> str:
    r = report["round"]
    settlement = r.get("settlement", {})
    expected = report["expected_settlement"]
    issues_html = render_issues(report["issues"])
    tricks = "".join(render_trick(t_report, r, idx) for t_report in report["tricks"])
    team_ranks = r.get("team_ranks_symbols") or [rank_symbol(v) for v in r.get("team_ranks", [])]
    bid_history = ", ".join(render_bid(b) for b in r.get("bid_history", [])) or "无"
    bottom = " ".join(r.get("debug", {}).get("bottom_cards", [])) or "无"
    buried = " ".join(r.get("debug", {}).get("buried_cards", [])) or "无"
    initial_hands = render_initial_hands(r)
    correction_key = f"round-{r.get('round_num', idx + 1)}"
    return f"""
<section id="round-{idx}" class="round-section">
  <div class="round-grid">
    <article class="card summary">
      <h2>第 {esc(r.get("round_num", idx + 1))} 局概览</h2>
      <div class="kv">
        <span>庄家</span><b>S{esc(r.get("dealer"))} {esc(seat_name(r.get("dealer", 0)))}</b>
        <span>庄家队</span><b>{esc(team_label(r.get("dealer", 0) % 2))}</b>
        <span>攻方队</span><b>{esc(team_label((r.get("dealer", 0) + 1) % 2))}</b>
        <span>本局级</span><b>{esc(r.get("rank_symbol", rank_symbol(r.get("rank", 2))))}</b>
        <span>队伍级</span><b>{esc(" / ".join(team_ranks))}</b>
        <span>主花色</span><b>{esc(r.get("trump_suit_symbol") or r.get("bid", {}).get("suit_symbol", "未知"))}</b>
        <span>亮主</span><b>{esc(bid_history)}</b>
        <span>庄家原因</span><b>{esc(report.get("dealer_reason", ""))}</b>
      </div>
    </article>
    <article class="card summary">
      <h2>结算与轮庄</h2>
      <div class="kv">
        <span>攻方出牌分</span><b>{esc(settlement.get("attack_base_score"))}</b>
        <span>底牌奖励</span><b>{esc(settlement.get("bottom_score"))} × {esc(settlement.get("bottom_multiplier"))} = {esc(settlement.get("bottom_bonus"))}</b>
        <span>最终分</span><b>{esc(settlement.get("final_score"))}</b>
        <span>升级方</span><b>{esc("攻方" if settlement.get("upgrading_side") == 1 else "庄家方")}</b>
        <span>新级</span><b>{esc(settlement.get("new_rank_symbol", rank_symbol(settlement.get("new_rank", r.get("rank", 2)))))}</b>
        <span>新庄家</span><b>{esc(format_dealer(settlement.get("new_dealer")))}</b>
        <span>复算新庄家</span><b>{esc(format_dealer(expected.get("new_dealer")))}</b>
        <span>下局期望庄家</span><b>{esc(format_dealer(report.get("expected_next_dealer")))}</b>
      </div>
    </article>
    <article class="card summary wide">
      <h2>底牌与埋牌</h2>
      <p><b>底牌：</b>{render_cards(bottom.split())}</p>
      <p><b>埋牌：</b>{render_cards(buried.split())}</p>
    </article>
    {initial_hands}
  </div>
  {issues_html}
  <article class="card correction">
    <h2>本局人工订正</h2>
    <textarea data-correction-key="{esc(correction_key)}" placeholder="在这里记录本局订正、人工判定或待查问题。"></textarea>
  </article>
  <div class="trick-list">{tricks}</div>
</section>
"""


def render_initial_hands(round_data: Dict[str, Any]) -> str:
    hands = round_data.get("debug", {}).get("initial_hands", [])
    if not hands:
        return ""
    trump_suit = round_data.get("trump_suit", -1)
    current_rank = round_data.get("rank", 2)
    rows = []
    for seat, raw_hand in enumerate(hands):
        display_hand = sort_raw_cards_for_display(raw_hand, trump_suit, current_rank)
        rows.append(
            f"""
<details class="initial-hand">
  <summary>S{seat} {esc(seat_name(seat))} 初始手牌（{len(display_hand)} 张）</summary>
  <div class="hand-cards">{render_cards(display_hand)}</div>
</details>
"""
        )
    return f"""
<article class="card summary wide">
  <h2>初始手牌</h2>
  <div class="initial-hands">{"".join(rows)}</div>
</article>
"""


def render_trick(t_report: Dict[str, Any], round_data: Dict[str, Any], round_idx: int) -> str:
    t = t_report["trick"]
    issues = t_report["issues"]
    plays = {p.get("seat"): p for p in t.get("plays", [])}
    winner = t.get("winner")
    lead = t.get("lead_seat")
    title_class = "has-error" if any(i["level"] == "error" for i in issues) else ("has-warning" if issues else "")
    correction_key = f"round-{round_data.get('round_num')}-trick-{t.get('trick_num')}"
    seat_blocks = []
    for seat, pos in [(2, "north"), (3, "west"), (1, "east"), (0, "south")]:
        play = plays.get(seat, {})
        seat_blocks.append(render_seat_play(seat, play, pos, winner, lead))
    issue_html = render_issues(issues, compact=True)
    hand_html = render_hand_snapshots(t, round_data)
    return f"""
<details class="trick-card" open>
  <summary class="{title_class}">
    <span>第 {esc(t.get("trick_num"))} 墩</span>
    <span>先手 S{esc(lead)} · 赢家 S{esc(winner)} {esc("攻方" if t.get("winner_side") == "attack" else "庄家方")} · 本墩 {esc(t.get("trick_points", t.get("trick_score")))} 分 · 攻方 {esc(t.get("attack_score_before"))} → {esc(t.get("attack_score_after"))}</span>
  </summary>
  <div class="trick-table">
    {''.join(seat_blocks)}
    <div class="center-pot">
      <b>最大：S{esc(winner)} {esc(seat_name(winner))}</b>
      <span>{esc(t.get("debug", {}).get("winner_reason", ""))}</span>
    </div>
  </div>
  {issue_html}
  <div class="play-detail">
    {''.join(render_play_detail(p, round_data) for p in t.get("plays", []))}
  </div>
  {hand_html}
  <div class="correction-inline">
    <label>本墩人工订正</label>
    <textarea data-correction-key="{esc(correction_key)}" placeholder="记录这一墩的人工订正。"></textarea>
  </div>
</details>
"""


def render_hand_snapshots(trick: Dict[str, Any], round_data: Dict[str, Any]) -> str:
    trump_suit = round_data.get("trump_suit", -1)
    current_rank = round_data.get("rank", 2)
    rows = []
    for seat in range(4):
        before = sort_raw_cards_for_display(find_hand_before(trick, seat), trump_suit, current_rank)
        after = sort_raw_cards_for_display(find_hand_after(trick, seat), trump_suit, current_rank)
        play = next((p for p in trick.get("plays", []) if p.get("seat") == seat), {})
        played = play.get("cards", [])
        if not before and not after:
            continue
        rows.append(
            f"""
<details class="hand-snapshot">
  <summary>S{seat} {esc(seat_name(seat))} 手牌：{len(before)} → {len(after)}</summary>
  <div class="hand-compare">
    <div>
      <b>出牌前</b>
      <div class="hand-cards">{render_cards(before, highlighted=played)}</div>
    </div>
    <div>
      <b>出牌后</b>
      <div class="hand-cards">{render_cards(after)}</div>
    </div>
  </div>
</details>
"""
        )
    if not rows:
        return ""
    return f'<div class="hand-snapshots"><h3>本墩前后手牌</h3>{"".join(rows)}</div>'


def sort_raw_cards_for_display(raw_cards: List[str], trump_suit: int, current_rank: int) -> List[str]:
    parsed = cards(raw_cards)
    parsed.sort(key=lambda c: (
        card_display_group(c, trump_suit, current_rank),
        -sort_value(c, trump_suit, current_rank),
        card_identity_key(c),
    ))
    return [c.raw for c in parsed]


def card_display_group(card: Card, trump_suit: int, current_rank: int) -> int:
    if domain(card, trump_suit, current_rank)[0] == "TRUMP":
        return 0
    if card.suit == 3:
        return 1
    if card.suit == 1:
        return 2
    if card.suit == 0:
        return 3
    if card.suit == 2:
        return 4
    return 5


def card_identity_key(card: Card) -> str:
    if card.joker:
        return card.joker
    return f"{card.suit}:{card.rank:02d}"


def render_seat_play(seat: int, play: Dict[str, Any], pos: str, winner: int, lead: int) -> str:
    tags = []
    if seat == winner:
        tags.append('<span class="tag win">最大</span>')
    if seat == lead:
        tags.append('<span class="tag lead">先手</span>')
    return f"""
<div class="seat-play {pos} {'winner' if seat == winner else ''}">
  <div class="seat-title">S{seat} {esc(seat_name(seat))} {''.join(tags)}</div>
  <div class="cards">{render_cards(play.get("cards", []))}</div>
  <div class="meta">{esc(play.get("pattern", ""))} · {esc(format_domain(play.get("domain")))} · v={esc("/".join(str(v) for v in play.get("sort_values", [])))}</div>
</div>
"""


def render_play_detail(play: Dict[str, Any], round_data: Dict[str, Any]) -> str:
    return f"""
<div class="play-row">
  <b>S{esc(play.get("seat"))} {esc(seat_name(play.get("seat", 0)))}</b>
  <span>{render_cards(play.get("cards", []))}</span>
  <code>{esc(play.get("pattern", ""))}</code>
  <code>{esc(format_domain(play.get("domain")))}</code>
  <code>{esc("/".join(str(v) for v in play.get("sort_values", [])))}</code>
</div>
"""


def render_issues(issues: List[Dict[str, Any]], compact: bool = False) -> str:
    if not issues:
        return '<div class="issues ok">未发现自动检测问题</div>' if not compact else ""
    rows = []
    for i in issues:
        rows.append(f'<li class="{esc(i["level"])}"><b>{esc(i["level"].upper())}</b> <code>{esc(i["code"])}</code> {esc(i["message"])}</li>')
    cls = "issues compact" if compact else "issues"
    return f'<ul class="{cls}">{"".join(rows)}</ul>'


def render_cards(raw_cards: Iterable[str], highlighted: Optional[Iterable[str]] = None) -> str:
    highlight_counts: Dict[str, int] = {}
    for card in highlighted or []:
        highlight_counts[card] = highlight_counts.get(card, 0) + 1
    tokens = []
    for card in raw_cards:
        classes = ["card-token", card_color(card)]
        if highlight_counts.get(card, 0) > 0:
            classes.append("played-highlight")
            highlight_counts[card] -= 1
        tokens.append(f'<span class="{" ".join(classes)}">{esc(card)}</span>')
    return "".join(tokens)


def card_color(raw: str) -> str:
    return "red" if raw.startswith("♥") or raw.startswith("♦") or raw == "RedJoker" else "black"


def esc(value: Any) -> str:
    return html.escape("" if value is None else str(value))


def seat_name(seat: Optional[int]) -> str:
    if seat is None or seat < 0 or seat > 3:
        return "无"
    return SEAT_NAMES[seat]


def team_label(team_idx: int) -> str:
    return TEAM_NAMES[team_idx] if team_idx in (0, 1) else "未知队"


def format_dealer(seat: Any) -> str:
    try:
        seat_int = int(seat)
    except (TypeError, ValueError):
        return "无"
    if seat_int < 0:
        return "不换庄"
    return f"S{seat_int} {seat_name(seat_int)}"


def format_domain(dom: Any) -> str:
    if not isinstance(dom, dict):
        return ""
    dtype = dom.get("type")
    suit = dom.get("suit", -1)
    if dtype == 0:
        return "主牌"
    if dtype == 1:
        return f"{SUIT_ID_TO_SYMBOL.get(suit, '?')}副"
    return "无域"


def render_bid(bid: Dict[str, Any]) -> str:
    action = bid.get("action")
    seat = bid.get("seat")
    if action == "bid":
        return f"S{seat} 亮 {bid.get('suit_symbol', '')}"
    return f"S{seat} 跳过({bid.get('reason', '')})"


CSS = """
:root { color-scheme: light; --bg:#f6f7fb; --card:#fff; --ink:#172033; --muted:#667085; --line:#d9deea; --red:#b42318; --green:#087443; --amber:#b54708; --blue:#175cd3; }
* { box-sizing: border-box; }
body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif; background:var(--bg); color:var(--ink); }
.app-header { position:sticky; top:0; z-index:10; display:flex; justify-content:space-between; gap:20px; align-items:center; padding:18px 28px; background:rgba(255,255,255,.94); border-bottom:1px solid var(--line); backdrop-filter: blur(10px); }
h1 { margin:0 0 6px; font-size:22px; }
h2 { margin:0 0 12px; font-size:18px; }
p { margin:6px 0; }
button { border:1px solid var(--line); background:#fff; color:var(--ink); padding:8px 12px; border-radius:10px; cursor:pointer; }
button:hover, .round-tab.active { border-color:var(--blue); color:var(--blue); box-shadow:0 0 0 3px rgba(23,92,211,.08); }
.header-actions { display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end; }
.round-nav { display:flex; gap:10px; padding:14px 28px; overflow:auto; }
.round-tab span { margin-left:8px; color:var(--muted); font-size:12px; }
main { padding:0 28px 40px; }
.round-section { display:none; }
.round-section.active { display:block; }
.round-grid { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
.card, .trick-card { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px; box-shadow:0 8px 24px rgba(23,32,51,.05); }
.wide { grid-column:1 / -1; }
.kv { display:grid; grid-template-columns:120px 1fr; gap:8px 14px; }
.kv span, .meta, .app-header p { color:var(--muted); }
.issues { margin:14px 0; padding:12px 16px 12px 34px; background:#fff; border:1px solid var(--line); border-radius:14px; }
.issues.ok { padding:12px 16px; color:var(--green); }
.issues.compact { margin:10px 0; }
.issues li { margin:6px 0; }
.issues .error { color:var(--red); }
.issues .warning { color:var(--amber); }
textarea { width:100%; min-height:78px; resize:vertical; border:1px solid var(--line); border-radius:12px; padding:10px; font:inherit; }
.trick-list { display:grid; gap:14px; margin-top:16px; }
.trick-card { padding:0; overflow:hidden; }
.trick-card summary { display:flex; justify-content:space-between; gap:16px; padding:14px 16px; cursor:pointer; border-bottom:1px solid var(--line); }
.trick-card summary.has-error { background:#fff1f0; }
.trick-card summary.has-warning { background:#fff7ed; }
.trick-table { position:relative; display:grid; grid-template-columns:1fr 210px 1fr; grid-template-rows:auto auto auto; gap:12px; min-height:300px; padding:18px; align-items:center; }
.seat-play { border:1px solid var(--line); border-radius:14px; padding:12px; background:#fbfcff; min-height:92px; }
.seat-play.winner { border-color:var(--green); background:#ecfdf3; }
.north { grid-column:2; grid-row:1; }
.west { grid-column:1; grid-row:2; }
.east { grid-column:3; grid-row:2; }
.south { grid-column:2; grid-row:3; }
.center-pot { grid-column:2; grid-row:2; text-align:center; padding:14px; border:1px dashed var(--line); border-radius:999px; background:#fff; }
.center-pot span { display:block; margin-top:6px; color:var(--muted); font-size:12px; }
.seat-title { display:flex; gap:6px; align-items:center; font-weight:700; margin-bottom:8px; }
.tag { font-size:12px; padding:2px 7px; border-radius:999px; color:#fff; }
.tag.win { background:var(--green); }
.tag.lead { background:var(--blue); }
.card-token { display:inline-block; min-width:34px; text-align:center; margin:2px; padding:5px 7px; border-radius:8px; border:1px solid var(--line); background:#fff; font-weight:700; }
.card-token.red { color:#c0102e; }
.card-token.black { color:#111827; }
.card-token.played-highlight { border-color:var(--amber); background:#fff4d6; box-shadow:0 0 0 2px rgba(181,71,8,.18); }
.play-detail { display:grid; gap:8px; padding:0 16px 16px; }
.play-row { display:grid; grid-template-columns:110px 1fr 110px 100px 110px; gap:10px; align-items:center; padding:8px 0; border-top:1px solid #eef1f6; }
.hand-snapshots { margin:0 16px 16px; padding:12px; border:1px solid var(--line); border-radius:14px; background:#fbfcff; }
.hand-snapshots h3 { margin:0 0 10px; font-size:15px; }
.hand-snapshot, .initial-hand { border-top:1px solid #eef1f6; padding:8px 0; }
.hand-snapshot:first-of-type, .initial-hand:first-of-type { border-top:0; }
.hand-snapshot summary, .initial-hand summary { display:block; padding:4px 0; border:0; font-weight:700; color:var(--blue); cursor:pointer; }
.hand-compare { display:grid; grid-template-columns:1fr; gap:12px; margin-top:8px; }
.hand-cards { margin-top:6px; line-height:2.2; }
.initial-hands { display:grid; gap:4px; }
code { background:#eef2ff; padding:3px 6px; border-radius:6px; }
.correction-inline { padding:0 16px 16px; }
.correction-inline label { display:block; margin-bottom:6px; color:var(--muted); }
@media (max-width: 900px) {
  .app-header, .round-grid, .trick-card summary { display:block; }
  .round-grid { grid-template-columns:1fr; }
  .wide { grid-column:auto; }
  .trick-table { grid-template-columns:1fr; grid-template-rows:auto; }
  .north,.west,.east,.south,.center-pot { grid-column:1; grid-row:auto; }
  .play-row { grid-template-columns:1fr; }
}
"""


JS = """
const tabs = [...document.querySelectorAll('.round-tab')];
const sections = [...document.querySelectorAll('.round-section')];
function activate(id) {
  tabs.forEach(t => t.classList.toggle('active', t.dataset.target === id));
  sections.forEach(s => s.classList.toggle('active', s.id === id));
}
tabs.forEach(t => t.addEventListener('click', () => activate(t.dataset.target)));
if (tabs.length) activate(tabs[0].dataset.target);

document.getElementById('expand-all').addEventListener('click', () => {
  document.querySelectorAll('details.trick-card').forEach(d => d.open = true);
});
document.getElementById('collapse-all').addEventListener('click', () => {
  document.querySelectorAll('details.trick-card').forEach(d => d.open = false);
});

const storageKey = 'shengji-log-corrections:' + location.pathname;
const saved = JSON.parse(localStorage.getItem(storageKey) || '{}');
document.querySelectorAll('[data-correction-key]').forEach(el => {
  const key = el.dataset.correctionKey;
  el.value = saved[key] || '';
  el.addEventListener('input', () => {
    saved[key] = el.value;
    localStorage.setItem(storageKey, JSON.stringify(saved, null, 2));
  });
});
document.getElementById('export-corrections').addEventListener('click', () => {
  const payload = {...window.REPLAY_CORRECTIONS_SEED, corrections: saved, exported_at: new Date().toISOString()};
  const blob = new Blob([JSON.stringify(payload, null, 2)], {type:'application/json;charset=utf-8'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'game_log_corrections.json';
  a.click();
  URL.revokeObjectURL(a.href);
});
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Export a Shengji game log to HTML replay.")
    parser.add_argument("log_file", help="Path to game_log_*.json")
    parser.add_argument("-o", "--output", help="Output HTML path. Defaults next to the log file.")
    args = parser.parse_args()

    log_path = Path(args.log_file)
    with log_path.open("r", encoding="utf-8") as f:
        log = json.load(f)
    analysis = analyze_log(log)
    output = Path(args.output) if args.output else log_path.with_suffix(".html")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_html(log, analysis, log_path), encoding="utf-8")
    errors = sum(1 for i in analysis["issues"] if i["level"] == "error")
    warnings = sum(1 for i in analysis["issues"] if i["level"] == "warning")
    print(f"HTML replay written: {output}")
    print(f"Analysis issues: {errors} errors, {warnings} warnings")


if __name__ == "__main__":
    main()
