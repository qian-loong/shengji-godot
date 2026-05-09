#!/usr/bin/env python3
"""
游戏日志完整性分析工具 - 独立实现版本
基于双升规则文档独立实现检查逻辑，不依赖游戏代码
这样可以发现游戏代码中的bug
"""

import json
import sys
from typing import Dict, List, Any, Optional, Tuple
from collections import Counter

# 常量定义（与游戏代码对应，但独立定义）
SUIT_SPADE = 0
SUIT_HEART = 1
SUIT_DIAMOND = 2
SUIT_CLUB = 3
SUIT_JOKER = 4

RANK_TWO = 2
RANK_ACE = 14
RANK_SMALL_JOKER = 16
RANK_BIG_JOKER = 17

SUIT_NAMES = {0: "♠", 1: "♥", 2: "♦", 3: "♣", 4: "Joker"}
RANK_NAMES = {2: "2", 3: "3", 4: "4", 5: "5", 6: "6", 7: "7", 8: "8",
              9: "9", 10: "10", 11: "J", 12: "Q", 13: "K", 14: "A",
              16: "小王", 17: "大王"}

class Card:
    """独立实现的Card类"""
    def __init__(self, data):
        if isinstance(data, dict):
            # 字典格式
            self.suit = data['suit']
            self.rank = data['rank']
            self.deck_id = data.get('deck_id', 0)
        elif isinstance(data, str):
            # 字符串格式，需要解析
            self.suit, self.rank, self.deck_id = Card._parse_string(data)
        else:
            raise ValueError(f"Unsupported card data type: {type(data)}")

    @staticmethod
    def _parse_string(card_str: str) -> Tuple[int, int, int]:
        """解析字符串格式的牌，如 '♠2', 'BlackJoker'"""
        if card_str == "BlackJoker":
            return (SUIT_JOKER, RANK_SMALL_JOKER, 0)
        elif card_str == "RedJoker":
            return (SUIT_JOKER, RANK_BIG_JOKER, 0)

        # 普通牌：花色符号 + 点数
        suit_map = {"♠": SUIT_SPADE, "♥": SUIT_HEART, "♦": SUIT_DIAMOND, "♣": SUIT_CLUB}
        rank_map = {"2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
                    "9": 9, "10": 10, "J": 11, "Q": 12, "K": 13, "A": 14}

        suit_char = card_str[0]
        rank_str = card_str[1:]

        suit = suit_map.get(suit_char)
        rank = rank_map.get(rank_str)

        if suit is None or rank is None:
            raise ValueError(f"Cannot parse card string: {card_str}")

        return (suit, rank, 0)

    def __repr__(self):
        if self.suit == SUIT_JOKER:
            return RANK_NAMES.get(self.rank, str(self.rank))
        return f"{SUIT_NAMES.get(self.suit, '?')}{RANK_NAMES.get(self.rank, str(self.rank))}"

    def __eq__(self, other):
        return (self.suit == other.suit and
                self.rank == other.rank and
                self.deck_id == other.deck_id)

    def __hash__(self):
        return hash((self.suit, self.rank, self.deck_id))

class TrumpJudge:
    """独立实现的主牌判定逻辑"""
    @staticmethod
    def is_trump(card: Card, trump_suit: int, current_rank: int, joker_always_trump: bool = True) -> bool:
        # 大小王
        if card.suit == SUIT_JOKER:
            return joker_always_trump
        # 级牌
        if card.rank == current_rank:
            return True
        # 主花色
        if trump_suit >= 0 and card.suit == trump_suit:
            return True
        return False

    @staticmethod
    def get_trump_value(card: Card, trump_suit: int, current_rank: int) -> int:
        """获取主牌内部排序值（越大越强）"""
        if card.suit == SUIT_JOKER:
            if card.rank == RANK_BIG_JOKER:
                return 1000
            else:  # SMALL_JOKER
                return 900

        if card.rank == current_rank:
            if trump_suit >= 0 and card.suit == trump_suit:
                return 800  # 主花色级牌
            else:
                return 700  # 副花色级牌

        # 主花色普通牌
        if trump_suit >= 0 and card.suit == trump_suit:
            return card.rank

        return 0  # 不是主牌

class Pattern:
    """独立实现的牌型识别"""
    def __init__(self, pattern_type: str, cards: List[Card], value: int = 0):
        self.type = pattern_type  # 'Single', 'Pair', 'Tractor', 'Dump'
        self.cards = cards
        self.value = value  # 用于比较大小

    @staticmethod
    def identify(cards: List[Card], trump_suit: int, current_rank: int) -> Optional['Pattern']:
        """识别牌型"""
        if len(cards) == 0:
            return None

        if len(cards) == 1:
            return Pattern('Single', cards, Pattern._get_card_value(cards[0], trump_suit, current_rank))

        # 检查是否所有牌相同
        if Pattern._all_same(cards):
            if len(cards) == 2:
                return Pattern('Pair', cards, Pattern._get_card_value(cards[0], trump_suit, current_rank))
            else:
                # 3张或4张相同
                return Pattern('Multi', cards, Pattern._get_card_value(cards[0], trump_suit, current_rank))

        # 检查拖拉机
        if len(cards) >= 4 and len(cards) % 2 == 0:
            tractor = Pattern._check_tractor(cards, trump_suit, current_rank)
            if tractor:
                return tractor

        # 否则是散牌
        return Pattern('Dump', cards, 0)

    @staticmethod
    def _all_same(cards: List[Card]) -> bool:
        """检查是否所有牌相同"""
        first = cards[0]
        return all(c.suit == first.suit and c.rank == first.rank for c in cards)

    @staticmethod
    def _check_tractor(cards: List[Card], trump_suit: int, current_rank: int) -> Optional['Pattern']:
        """检查是否是拖拉机（连续的对子）"""
        # 按值排序
        sorted_cards = sorted(cards, key=lambda c: Pattern._get_card_value(c, trump_suit, current_rank))

        # 检查是否能分成对子
        pairs = []
        i = 0
        while i < len(sorted_cards) - 1:
            if (sorted_cards[i].suit == sorted_cards[i+1].suit and
                sorted_cards[i].rank == sorted_cards[i+1].rank):
                pairs.append((sorted_cards[i], sorted_cards[i+1]))
                i += 2
            else:
                return None  # 无法完全配对

        if i < len(sorted_cards):
            return None  # 有剩余牌

        # 检查对子是否连续
        if len(pairs) < 2:
            return None

        values = [Pattern._get_card_value(p[0], trump_suit, current_rank) for p in pairs]
        for i in range(len(values) - 1):
            if values[i+1] != values[i] + 1:
                return None  # 不连续

        return Pattern('Tractor', cards, values[0])

    @staticmethod
    def _get_card_value(card: Card, trump_suit: int, current_rank: int) -> int:
        """获取牌的比较值"""
        if TrumpJudge.is_trump(card, trump_suit, current_rank):
            return 100 + TrumpJudge.get_trump_value(card, trump_suit, current_rank)
        else:
            # 副牌：花色*20 + 点数
            return card.suit * 20 + card.rank

class LogAnalyzer:
    def __init__(self, log_path: str):
        with open(log_path, 'r', encoding='utf-8') as f:
            self.log = json.load(f)
        self.errors = []
        self.warnings = []

    def analyze(self):
        """运行所有完整性检查"""
        print(f"=== 分析游戏日志 ===")
        print(f"游戏ID: {self.log.get('game_id', 'N/A')}")
        print(f"开始时间: {self.log.get('start_time', 'N/A')}")
        print(f"轮数: {len(self.log.get('rounds', []))}")
        print()

        self._check_attack_score_continuity()
        self._check_winner_determination()
        self._check_play_order()
        self._check_follow_counts()
        self._check_structure_matching()

        self._print_results()

    def _check_attack_score_continuity(self):
        """检查攻方得分连续性"""
        print("检查攻方得分连续性...")
        rounds = self.log.get('rounds', [])

        for round_idx, round_data in enumerate(rounds):
            tricks = round_data.get('tricks', [])
            expected_score = 0

            for trick_idx, trick in enumerate(tricks):
                attack_gain = trick.get('attack_gain', 0)
                attack_score = trick.get('attack_score_after', 0)

                expected_score += attack_gain
                if attack_score != expected_score:
                    self.errors.append(
                        f"Round {round_idx+1} Trick {trick_idx+1}: "
                        f"攻方得分不连续 (期望={expected_score}, 实际={attack_score})"
                    )

    def _check_winner_determination(self):
        """检查赢家判定逻辑 - 独立重新计算赢家"""
        print("检查赢家判定逻辑...")
        rounds = self.log.get('rounds', [])

        for round_idx, round_data in enumerate(rounds):
            trump_suit = round_data.get('trump_suit')
            current_rank = round_data.get('rank')
            tricks = round_data.get('tricks', [])

            for trick_idx, trick in enumerate(tricks):
                plays = trick.get('plays', [])
                if len(plays) != 4:
                    continue

                logged_winner = trick.get('winner')
                lead_seat = trick.get('lead_seat')

                # 独立计算赢家
                calculated_winner = self._calculate_winner(plays, trump_suit, current_rank, lead_seat)

                if calculated_winner != logged_winner:
                    # 找到首出的牌
                    lead_cards = None
                    for p in plays:
                        if p['seat'] == lead_seat:
                            lead_cards = p['cards']
                            break
                    lead_cards_str = ', '.join(str(Card(c)) for c in lead_cards) if lead_cards else 'N/A'
                    self.errors.append(
                        f"Round {round_idx+1} Trick {trick_idx+1}: "
                        f"赢家判定错误 (日志={logged_winner}, 计算={calculated_winner}) "
                        f"首出=[{lead_cards_str}]"
                    )

    def _calculate_winner(self, plays: List[Dict], trump_suit: int, current_rank: int, lead_seat: int) -> int:
        """独立实现的赢家计算逻辑"""
        # 找到首出
        lead = None
        for p in plays:
            if p['seat'] == lead_seat:
                lead = p
                break

        if lead is None:
            return lead_seat  # 找不到首出，返回lead_seat

        lead_cards = [Card(c) for c in lead['cards']]

        # 判断首出域
        lead_is_trump = TrumpJudge.is_trump(lead_cards[0], trump_suit, current_rank)
        lead_pattern = Pattern.identify(lead_cards, trump_suit, current_rank)

        best_seat = lead_seat
        best_value = self._get_play_value(lead_cards, trump_suit, current_rank)

        for play in plays:
            if play['seat'] == lead_seat:
                continue  # 跳过首出自己

            play_cards = [Card(c) for c in play['cards']]
            play_seat = play['seat']

            play_is_trump = TrumpJudge.is_trump(play_cards[0], trump_suit, current_rank)

            # 分支1: 首出是主牌
            if lead_is_trump:
                if not play_is_trump:
                    continue  # 垫牌，不能赢

                # 检查结构匹配
                play_pattern = Pattern.identify(play_cards, trump_suit, current_rank)
                if not self._structure_matches(lead_pattern, play_pattern):
                    continue  # 结构不匹配，不能赢

                play_value = self._get_play_value(play_cards, trump_suit, current_rank)
                if play_value > best_value:
                    best_seat = play_seat
                    best_value = play_value

            # 分支2: 首出是副牌，跟牌是主牌（杀）
            elif play_is_trump:
                # 检查结构匹配
                play_pattern = Pattern.identify(play_cards, trump_suit, current_rank)
                if not self._structure_matches(lead_pattern, play_pattern):
                    continue  # 结构不匹配，不能赢

                play_value = self._get_play_value(play_cards, trump_suit, current_rank)
                if play_value > best_value:
                    best_seat = play_seat
                    best_value = play_value

            # 分支3: 首出是副牌，跟牌也是副牌
            else:
                # 检查是否同花色
                if play_cards[0].suit != lead_cards[0].suit:
                    continue  # 不同花色，不能赢

                # 检查结构匹配
                play_pattern = Pattern.identify(play_cards, trump_suit, current_rank)
                if not self._structure_matches(lead_pattern, play_pattern):
                    continue  # 结构不匹配，不能赢

                play_value = self._get_play_value(play_cards, trump_suit, current_rank)
                if play_value > best_value:
                    best_seat = play_seat
                    best_value = play_value

        return best_seat

    def _structure_matches(self, lead_pattern: Pattern, play_pattern: Pattern) -> bool:
        """检查结构是否匹配"""
        if lead_pattern is None or play_pattern is None:
            return False

        # Single总是匹配
        if lead_pattern.type == 'Single':
            return True

        # Pair必须对Pair
        if lead_pattern.type == 'Pair':
            return play_pattern.type == 'Pair'

        # Tractor必须对Tractor，且长度相同
        if lead_pattern.type == 'Tractor':
            return (play_pattern.type == 'Tractor' and
                    len(play_pattern.cards) == len(lead_pattern.cards))

        # Dump总是匹配（散牌）
        return True

    def _get_play_value(self, cards: List[Card], trump_suit: int, current_rank: int) -> int:
        """获取出牌的比较值（最大牌的值）"""
        return max(Pattern._get_card_value(c, trump_suit, current_rank) for c in cards)


    def _check_play_order(self):
        """检查出牌顺序（顺时针：0→3→2→1）"""
        print("检查出牌顺序...")
        rounds = self.log.get('rounds', [])

        for round_idx, round_data in enumerate(rounds):
            tricks = round_data.get('tricks', [])

            for trick_idx, trick in enumerate(tricks):
                plays = trick.get('plays', [])
                if len(plays) != 4:
                    continue

                lead_seat = plays[0]['seat']
                # 顺时针顺序：0→3→2→1→0
                expected_order = []
                current = lead_seat
                for _ in range(4):
                    expected_order.append(current)
                    current = (current - 1) % 4  # 顺时针递减

                actual_order = [p['seat'] for p in plays]

                if actual_order != expected_order:
                    self.errors.append(
                        f"Round {round_idx+1} Trick {trick_idx+1}: "
                        f"出牌顺序错误 (期望={expected_order}, 实际={actual_order})"
                    )

    def _check_follow_counts(self):
        """检查跟牌数量是否匹配首出"""
        print("检查跟牌数量...")
        rounds = self.log.get('rounds', [])

        for round_idx, round_data in enumerate(rounds):
            tricks = round_data.get('tricks', [])

            for trick_idx, trick in enumerate(tricks):
                plays = trick.get('plays', [])
                if len(plays) < 2:
                    continue

                lead_count = len(plays[0].get('cards', []))

                for play in plays[1:]:
                    play_count = len(play.get('cards', []))
                    if play_count != lead_count:
                        self.warnings.append(
                            f"Round {round_idx+1} Trick {trick_idx+1}: "
                            f"Seat {play['seat']} 跟牌数量不匹配 "
                            f"(首出={lead_count}, 跟牌={play_count})"
                        )

    def _check_structure_matching(self):
        """检查结构匹配规则 - 对子/拖拉机不能被散牌击败"""
        print("检查结构匹配规则...")
        rounds = self.log.get('rounds', [])

        for round_idx, round_data in enumerate(rounds):
            trump_suit = round_data.get('trump_suit')
            current_rank = round_data.get('rank')
            tricks = round_data.get('tricks', [])

            for trick_idx, trick in enumerate(tricks):
                plays = trick.get('plays', [])
                if len(plays) != 4:
                    continue

                lead = plays[0]
                lead_cards = [Card(c) for c in lead['cards']]
                lead_pattern = Pattern.identify(lead_cards, trump_suit, current_rank)

                winner_seat = trick.get('winner')

                # 如果首出是Pair或Tractor
                if lead_pattern and lead_pattern.type in ['Pair', 'Tractor']:
                    # 检查所有跟牌
                    for play in plays[1:]:
                        play_cards = [Card(c) for c in play['cards']]
                        play_pattern = Pattern.identify(play_cards, trump_suit, current_rank)

                        # 如果跟牌是Dump但赢了，这是错误
                        if play_pattern and play_pattern.type == 'Dump' and play['seat'] == winner_seat:
                            lead_str = ', '.join(str(c) for c in lead_cards)
                            play_str = ', '.join(str(c) for c in play_cards)
                            self.errors.append(
                                f"Round {round_idx+1} Trick {trick_idx+1}: "
                                f"首出{lead_pattern.type}被Dump击败! "
                                f"首出=[{lead_str}] 赢家=[{play_str}] seat={winner_seat}"
                            )

    def _print_results(self):
        """打印分析结果"""
        print()
        print("=== 分析结果 ===")

        if not self.errors and not self.warnings:
            print("[OK] 未发现问题")
            return

        # 输出到文件以避免编码问题
        output_file = "docs/game-logs/analysis_result.txt"
        with open(output_file, 'w', encoding='utf-8') as f:
            if self.errors:
                f.write(f"[ERROR] 发现 {len(self.errors)} 个错误:\n")
                for error in self.errors:
                    f.write(f"  - {error}\n")

            if self.warnings:
                f.write(f"\n[WARNING] 发现 {len(self.warnings)} 个警告:\n")
                for warning in self.warnings:
                    f.write(f"  - {warning}\n")

        print(f"[ERROR] 发现 {len(self.errors)} 个错误")
        if self.warnings:
            print(f"[WARNING] 发现 {len(self.warnings)} 个警告")
        print(f"详细结果已保存到: {output_file}")

def main():
    if len(sys.argv) < 2:
        print("用法: python analyze_game_log.py <log_file.json>")
        sys.exit(1)

    log_path = sys.argv[1]
    analyzer = LogAnalyzer(log_path)
    analyzer.analyze()

if __name__ == '__main__':
    main()
