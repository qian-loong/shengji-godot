#!/usr/bin/env python3
"""tools/validate_game_log.py 的回归测试。

两类保障：

1. **基线不误报** —— 引擎真实产出的日志必须零 error。旧的
   export_game_log_html.py 正是栽在这里（quick 预设 20 条全假），
   噪声会把真错误淹没。
2. **变异必检出** —— 逐项篡改日志，校验器必须报错。只测"基线通过"
   是不够的：一个永远返回空的校验器也能通过基线。

运行:
  python -m unittest discover -s tools/tests -v
  python tools/tests/test_validate_game_log.py
"""

from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from validate_game_log import (  # noqa: E402
    Card,
    LogFormatError,
    LogValidator,
    RuleConfig,
    Rules,
    TYPE_DUMP,
    TYPE_PAIR,
    TYPE_TRACTOR,
    parse_cards,
)

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def load_fixture(name: str) -> dict:
    path = FIXTURES / name
    if not path.is_file():
        raise unittest.SkipTest(
            f"缺少 fixture {path}。重新生成:\n"
            f"  $GODOT_EXE --headless --path src/godot "
            f"--script res://scripts/gameplay/game_session.gd "
            f"--preset=quick --seed=42 --max-rounds=2 --log-path=<path>"
        )
    return json.loads(path.read_text(encoding="utf-8"))


def errors_of(log: dict) -> list:
    return [i for i in LogValidator(log).validate() if i.level == "error"]


def error_codes(log: dict) -> set[str]:
    return {i.code for i in errors_of(log)}


def make_config(**overrides) -> RuleConfig:
    """构造一份规则配置，默认贴近 classic 预设。"""
    base = dict(
        deck_count=2,
        total_score=200,
        joker_always_trump=True,
        allow_dump=True,
        strict_follow_structure=True,
        four_same_is_tractor=True,
        tractor_allow_rank_card=True,
        upgrade_threshold=80,
        upgrade_step=1,
        upgrade_table=[[0, 0, 3], [1, 0, 2], [40, 0, 1],
                       [80, 1, 0], [120, 1, 1], [160, 1, 2], [200, 1, 3]],
        no_skip_enabled=False,
        no_skip_ranks=[],
    )
    base.update(overrides)
    return RuleConfig(**base)


# ============================================================
# 规则引擎：升级推进
# ============================================================


class TestUpgradeProgression(unittest.TestCase):
    def test_upgrade_step_multiplies_table_levels(self) -> None:
        # Arrange: quick 预设语义 —— 表中 2 级 × step 2 = 实升 4 级
        rules = Rules(make_config(upgrade_step=2,
                                  upgrade_table=[[0, 0, 3], [1, 0, 2], [30, 0, 1]]))

        # Act: 攻方 25 分 → 命中 [1,0,2] → 庄家升 2 级 × 2
        result = rules.calculate_settlement(
            attack_score=25, bottom_cards=[], dealer_seat=0,
            last_trick_winner_is_attack=False, last_trick_pattern=None,
            current_rank=2,
        )

        # Assert
        self.assertEqual(result["upgrade_levels"], 4)
        self.assertEqual(result["new_rank"], 6, "2 升 4 级 → 6")

    def test_no_skip_stops_before_crossing_no_skip_rank(self) -> None:
        # Arrange: 必打级 5 开启，从 2 升 4 级会跨过 5
        rules = Rules(make_config(no_skip_enabled=True, no_skip_ranks=[5]))

        # Act
        landed = rules.apply_upgrade(current_rank=2, levels=4)

        # Assert: 停在 5，不得跨越
        self.assertEqual(landed, 5)

    def test_no_skip_allows_landing_exactly_on_no_skip_rank(self) -> None:
        # Arrange: 同样开启必打级 5，但升 3 级恰好落在 5 上
        rules = Rules(make_config(no_skip_enabled=True, no_skip_ranks=[5]))

        # Act
        landed = rules.apply_upgrade(current_rank=2, levels=3)

        # Assert: 落点是必打级并不拦截，只拦"跨越"
        self.assertEqual(landed, 5)

    def test_no_skip_disabled_passes_through_rank(self) -> None:
        # Arrange: classic 预设关闭必打级
        rules = Rules(make_config(no_skip_enabled=False, no_skip_ranks=[]))

        # Act
        landed = rules.apply_upgrade(current_rank=2, levels=4)

        # Assert: 一路升到 6
        self.assertEqual(landed, 6)

    def test_upgrade_caps_at_ace(self) -> None:
        rules = Rules(make_config())
        self.assertEqual(rules.apply_upgrade(current_rank=13, levels=5), 14)

    def test_dethrone_uses_configured_threshold(self) -> None:
        # Arrange: 门槛 60（quick），不是写死的 80
        rules = Rules(make_config(upgrade_threshold=60))

        # Act
        result = rules.calculate_settlement(
            attack_score=60, bottom_cards=[], dealer_seat=1,
            last_trick_winner_is_attack=False, last_trick_pattern=None,
            current_rank=2,
        )

        # Assert
        self.assertTrue(result["dealer_dethroned"])
        self.assertEqual(result["new_dealer"], 2, "下庄后由下家坐庄")

    def test_defended_dealer_keeps_seat(self) -> None:
        # 守庄时 new_dealer 应是原座位，而非 -1
        rules = Rules(make_config(upgrade_threshold=80))
        result = rules.calculate_settlement(
            attack_score=30, bottom_cards=[], dealer_seat=1,
            last_trick_winner_is_attack=False, last_trick_pattern=None,
            current_rank=2,
        )
        self.assertFalse(result["dealer_dethroned"])
        self.assertEqual(result["new_dealer"], 1)


# ============================================================
# 规则引擎：牌型识别的配置敏感性
# ============================================================


class TestPatternConfigSensitivity(unittest.TestCase):
    def test_four_same_is_tractor_when_enabled(self) -> None:
        rules = Rules(make_config(four_same_is_tractor=True))
        cards = parse_cards(["♠7", "♠7", "♠7", "♠7"])

        pattern = rules.identify(cards, current_rank=2)

        self.assertIsNotNone(pattern)
        self.assertEqual(pattern.kind, TYPE_TRACTOR)
        self.assertEqual(pattern.pair_count, 2)

    def test_four_same_is_not_tractor_when_disabled(self) -> None:
        # quick 预设关闭该规则 —— 同样四张牌必须判为非拖拉机
        rules = Rules(make_config(four_same_is_tractor=False))
        cards = parse_cards(["♠7", "♠7", "♠7", "♠7"])

        pattern = rules.identify(cards, current_rank=2)

        self.assertIsNotNone(pattern)
        self.assertNotEqual(pattern.kind, TYPE_TRACTOR)

    def test_tractor_rejects_rank_card_when_disallowed(self) -> None:
        rules = Rules(make_config(tractor_allow_rank_card=False))
        # 打 5 时，44+55 含级牌 5
        cards = parse_cards(["♠4", "♠4", "♠5", "♠5"])

        pattern = rules.identify(cards, current_rank=5)

        self.assertNotEqual(pattern.kind, TYPE_TRACTOR)

    def test_four_jokers_are_tractor(self) -> None:
        # GDD card-types.md AC14d：四张王恒为拖拉机，扣底 ×4
        rules = Rules(make_config())
        cards = parse_cards(["RedJoker", "RedJoker", "BlackJoker", "BlackJoker"])

        pattern = rules.identify(cards, current_rank=2)

        self.assertEqual(pattern.kind, TYPE_TRACTOR)
        self.assertEqual(pattern.pair_count, 2)
        self.assertEqual(rules.bottom_multiplier(pattern), 4)

    def test_four_jokers_ignore_four_same_switch(self) -> None:
        # 四王是固定规则，不受 four_same_is_tractor 控制（那个管级牌）
        rules = Rules(make_config(four_same_is_tractor=False))
        cards = parse_cards(["RedJoker", "RedJoker", "BlackJoker", "BlackJoker"])

        pattern = rules.identify(cards, current_rank=2)

        self.assertEqual(pattern.kind, TYPE_TRACTOR)

    def test_three_jokers_plus_card_is_not_tractor(self) -> None:
        # AC14e
        rules = Rules(make_config())
        cards = parse_cards(["RedJoker", "RedJoker", "BlackJoker", "♠5"])

        pattern = rules.identify(cards, current_rank=2)

        self.assertNotEqual(pattern.kind, TYPE_TRACTOR)

    def test_four_same_rank_is_tractor_when_enabled(self) -> None:
        # GDD card-types.md AC13：级=5 时 ♠5♠5♥5♥5 全在主牌域
        rules = Rules(make_config(four_same_is_tractor=True))
        cards = parse_cards(["♠5", "♠5", "♥5", "♥5"])

        pattern = rules.identify(cards, current_rank=5)

        self.assertEqual(pattern.kind, TYPE_TRACTOR)
        self.assertEqual(pattern.pair_count, 2)
        self.assertEqual(rules.bottom_multiplier(pattern), 4)

    def test_four_same_rank_is_not_tractor_when_disabled(self) -> None:
        # AC14
        rules = Rules(make_config(four_same_is_tractor=False))
        cards = parse_cards(["♠5", "♠5", "♥5", "♥5"])

        pattern = rules.identify(cards, current_rank=5)

        self.assertNotEqual(pattern.kind, TYPE_TRACTOR)

    def test_same_rank_without_pairs_is_not_tractor(self) -> None:
        # AC14b：四张同点数但每种花色仅 1 张，配不成对子
        rules = Rules(make_config(four_same_is_tractor=True))
        cards = parse_cards(["♠5", "♥5", "♦5", "♣5"])

        pattern = rules.identify(cards, current_rank=5)

        self.assertNotEqual(pattern.kind, TYPE_TRACTOR)

    def test_same_rank_different_suits_are_not_a_pair(self) -> None:
        # AC14c：对子必须同花同点（GDD §2.1）。
        # 曾因 _extract_pair_ranks 按 rank 统计而把这手散牌误判为拖拉机。
        rules = Rules(make_config())
        cards = parse_cards(["♠5", "♥5", "♠6", "♥6"])

        pattern = rules.identify(cards, current_rank=2)

        self.assertNotEqual(
            pattern.kind, TYPE_TRACTOR,
            "♠5♥5 不是对子，这手牌不构成拖拉机",
        )

    def test_tractor_adjacency_skips_rank_card(self) -> None:
        # 打 7 时，66 与 88 因跳过级牌 7 而相邻
        rules = Rules(make_config())
        cards = parse_cards(["♠6", "♠6", "♠8", "♠8"])

        pattern = rules.identify(cards, current_rank=7)

        self.assertEqual(pattern.kind, TYPE_TRACTOR)
        self.assertEqual(pattern.pair_count, 2)

    def test_pair_identified(self) -> None:
        rules = Rules(make_config())
        pattern = rules.identify(parse_cards(["♥9", "♥9"]), current_rank=2)
        self.assertEqual(pattern.kind, TYPE_PAIR)

    def test_mixed_cards_are_dump(self) -> None:
        rules = Rules(make_config())
        pattern = rules.identify(parse_cards(["♥9", "♥3"]), current_rank=2)
        self.assertEqual(pattern.kind, TYPE_DUMP)

    def test_bottom_multiplier_scales_with_tractor_length(self) -> None:
        rules = Rules(make_config())
        tractor = rules.identify(parse_cards(["♠6", "♠6", "♠7", "♠7"]), current_rank=2)
        self.assertEqual(rules.bottom_multiplier(tractor), 4)


# ============================================================
# 域判定 / 排序
# ============================================================


class TestDomainAndSort(unittest.TestCase):
    def test_rank_card_of_other_suit_is_trump(self) -> None:
        rules = Rules(make_config())
        card = parse_cards(["♣2"])[0]

        domain = rules.suit_domain(card, trump_suit=0, current_rank=2)

        self.assertEqual(domain[0], 0, "级牌恒为主牌域")

    def test_trump_suit_rank_card_outranks_offsuit_rank_card(self) -> None:
        rules = Rules(make_config())
        trump_rank_card = parse_cards(["♠2"])[0]
        offsuit_rank_card = parse_cards(["♣2"])[0]

        v_trump = rules.sort_value(trump_rank_card, trump_suit=0, current_rank=2)
        v_off = rules.sort_value(offsuit_rank_card, trump_suit=0, current_rank=2)

        self.assertGreater(v_trump, v_off)

    def test_big_joker_is_highest(self) -> None:
        rules = Rules(make_config())
        big = parse_cards(["RedJoker"])[0]
        small = parse_cards(["BlackJoker"])[0]
        trump_rank = parse_cards(["♠2"])[0]

        self.assertGreater(rules.sort_value(big, 0, 2), rules.sort_value(small, 0, 2))
        self.assertGreater(rules.sort_value(small, 0, 2), rules.sort_value(trump_rank, 0, 2))


# ============================================================
# Schema fail-fast
# ============================================================


class TestSchemaFailFast(unittest.TestCase):
    def test_missing_rule_config_raises(self) -> None:
        with self.assertRaises(LogFormatError):
            LogValidator({"rounds": []})

    def test_missing_upgrade_table_raises(self) -> None:
        # 2026-07-28 之前的 GameLogger 不写 upgrade_table。
        # 必须显式失败，而不是套用某个预设的默认表静默"通过"。
        log = load_fixture("game_log_quick.json")
        del log["rule_config"]["upgrade_table"]

        with self.assertRaises(LogFormatError) as ctx:
            LogValidator(log)

        self.assertIn("upgrade_table", str(ctx.exception))

    def test_missing_total_score_raises(self) -> None:
        log = load_fixture("game_log_quick.json")
        del log["rule_config"]["total_score"]

        with self.assertRaises(LogFormatError):
            LogValidator(log)


# ============================================================
# 基线：真实日志零误报
# ============================================================


class TestFixtureBaseline(unittest.TestCase):
    def test_quick_fixture_is_clean(self) -> None:
        log = load_fixture("game_log_quick.json")

        errors = errors_of(log)

        self.assertEqual(
            errors, [],
            "quick 预设基线应无 error，实际: %s"
            % [f"{e.code}: {e.message}" for e in errors],
        )

    def test_classic_fixture_is_clean(self) -> None:
        log = load_fixture("game_log_classic.json")

        errors = errors_of(log)

        self.assertEqual(
            errors, [],
            "classic 预设基线应无 error，实际: %s"
            % [f"{e.code}: {e.message}" for e in errors],
        )

    def test_competitive_fixture_is_clean(self) -> None:
        log = load_fixture("game_log_competitive.json")

        errors = errors_of(log)

        self.assertEqual(
            errors, [],
            "competitive 预设基线应无 error，实际: %s"
            % [f"{e.code}: {e.message}" for e in errors],
        )


class TestMatrixPresetMirror(unittest.TestCase):
    """generate_matrix.py 的 PRESETS 是手抄的 rule_config.gd 镜像。

    抄错了不会报错 —— 只会让批跑跑的配置不是你以为的那个。
    拿引擎按 --preset 跑出的日志当基准，把镜像钉住。
    """

    PRESET_FIXTURES = {
        "classic": "game_log_classic.json",
        "competitive": "game_log_competitive.json",
        "quick": "game_log_quick.json",
    }

    # 由 deck_count 推导的只读属性，不在 PRESETS 里
    DERIVED = {"total_score", "hand_size", "bottom_size"}

    def _presets(self) -> dict:
        sys.path.insert(0, str(TOOLS_DIR / "batch"))
        from generate_matrix import PRESETS  # noqa: PLC0415
        return PRESETS

    def test_mirrors_match_engine_presets(self) -> None:
        presets = self._presets()

        for name, fixture in self.PRESET_FIXTURES.items():
            with self.subTest(preset=name):
                engine_config = load_fixture(fixture)["rule_config"]
                mirror = presets[name]

                mismatches = {
                    key: (value, engine_config[key])
                    for key, value in mirror.items()
                    if key in engine_config
                    and key not in self.DERIVED
                    and engine_config[key] != value
                }

                self.assertEqual(
                    mismatches, {},
                    f"generate_matrix.PRESETS['{name}'] 与引擎预设不一致 "
                    f"（格式 字段: (镜像值, 引擎值)）。"
                    f"请同步 tools/batch/generate_matrix.py",
                )


# ============================================================
# 变异检出
# ============================================================


class TestScenarioFixtures(unittest.TestCase):
    """构造牌局 fixture —— 覆盖随机对局走不到的规则路径。

    随机批跑里 AI 只首出单张（实测 54387 墩 100% Single），
    这些 fixture 由 tools/scenarios/ 的构造牌局生成，是对子/拖拉机/
    严格跟牌/扣底倍数等分支的唯一真实对局证据。
    """

    def test_strict_follow_fixture_is_clean(self) -> None:
        log = load_fixture("game_log_strict_follow.json")

        errors = errors_of(log)

        self.assertEqual(
            errors, [],
            "严格跟牌场景应无 error，实际: %s"
            % [f"{e.code}: {e.message}" for e in errors],
        )

    def test_strict_follow_fixture_actually_exercises_pairs(self) -> None:
        # 防止 fixture 退化成"全是单张所以没错"
        log = load_fixture("game_log_strict_follow.json")
        rules = Rules(RuleConfig.from_log(log))
        rd = log["rounds"][0]

        pair_leads = 0
        for trick in rd["tricks"]:
            pattern = rules.identify(parse_cards(trick["plays"][0]["cards"]), rd["rank"])
            if pattern and pattern.kind in (TYPE_PAIR, TYPE_TRACTOR):
                pair_leads += 1

        self.assertGreater(pair_leads, 0, "该 fixture 应包含对子/拖拉机首出")

    def test_tractor_rank_fixture_is_clean(self) -> None:
        log = load_fixture("game_log_tractor_rank.json")

        errors = errors_of(log)

        self.assertEqual(
            errors, [],
            "级牌拖拉机场景应无 error，实际: %s"
            % [f"{e.code}: {e.message}" for e in errors],
        )

    def test_tractor_rank_fixture_contains_rank_card_tractor(self) -> None:
        log = load_fixture("game_log_tractor_rank.json")
        rules = Rules(RuleConfig.from_log(log))
        rd = log["rounds"][0]
        current_rank = rd["rank"]

        found = False
        for trick in rd["tricks"]:
            cards = parse_cards(trick["plays"][0]["cards"])
            pattern = rules.identify(cards, current_rank)
            if pattern and pattern.kind == TYPE_TRACTOR:
                if any(not c.is_joker and c.rank == current_rank for c in cards):
                    found = True
                    break

        self.assertTrue(found, "该 fixture 应包含级牌参与的拖拉机首出")


class TestHtmlExporter(unittest.TestCase):
    """HTML 导出器现在只负责渲染，规则判定全部委托校验器。

    改造前它自带一套过时的规则实现（不认 upgrade_step、按 rank 统计对子），
    对 quick 预设会报 20 条全假的错误。这些用例盯住"单一规则源"这个约束。
    """

    def _exporter(self):
        sys.path.insert(0, str(TOOLS_DIR))
        import export_game_log_html  # noqa: PLC0415
        return export_game_log_html

    def test_exporter_reports_no_false_errors_on_clean_log(self) -> None:
        exporter = self._exporter()
        log = load_fixture("game_log_quick.json")

        analysis = exporter.build_analysis(log)

        errors = [i for i in analysis["issues"] if i["level"] == "error"]
        self.assertEqual(errors, [], f"干净日志不应报错，实际: {errors}")

    def test_exporter_surfaces_real_violations(self) -> None:
        exporter = self._exporter()
        log = load_fixture("game_log_dump_illegal_legacy.json")

        analysis = exporter.build_analysis(log)

        codes = {i["code"] for i in analysis["issues"] if i["level"] == "error"}
        self.assertIn("dump_not_biggest", codes)

    def test_exporter_groups_issues_by_round_and_trick(self) -> None:
        exporter = self._exporter()
        log = load_fixture("game_log_dump_illegal_legacy.json")

        analysis = exporter.build_analysis(log)

        self.assertEqual(len(analysis["rounds"]), len(log["rounds"]))
        # 墩级问题应落到对应的墩，而不是堆在局级
        placed = sum(
            len(t["issues"])
            for rd in analysis["rounds"] for t in rd["tricks"]
        )
        self.assertGreater(placed, 0, "墩级问题应归位到具体的墩")

    def test_exporter_renders_full_html(self) -> None:
        exporter = self._exporter()
        log = load_fixture("game_log_classic.json")
        analysis = exporter.build_analysis(log)
        exporter.reconstruct_hand_snapshots(log)

        markup = exporter.render_html(log, analysis, FIXTURES / "game_log_classic.json")

        for fragment in ("round-section", "trick-card", "card-token", "<html"):
            self.assertIn(fragment, markup, f"渲染结果应包含 {fragment}")

    def test_exporter_rejects_stale_log_with_clear_message(self) -> None:
        exporter = self._exporter()
        log = load_fixture("game_log_quick.json")
        del log["rule_config"]["upgrade_table"]

        with self.assertRaises(LogFormatError):
            exporter.build_analysis(log)


class TestDumpMustBeBiggest(unittest.TestCase):
    """甩牌最大性（GDD card-types.md §2.3）。

    引擎侧由 PlayValidator.challenge_dump 裁决，失败时降级为只出最小单牌。
    这里两头都测：校验器抓得到违规日志，且引擎产出的日志是干净的。
    """

    def test_validator_detects_illegal_dump(self) -> None:
        # 这份 fixture 生成于引擎实现该校验之前，保留下来专门验证
        # 校验器的检出能力 —— 即便引擎已修复，这条防线也不能退化。
        log = load_fixture("game_log_dump_illegal_legacy.json")

        codes = error_codes(log)

        self.assertIn("dump_not_biggest", codes)

    def test_engine_enforced_dump_log_is_clean(self) -> None:
        # 同一个构造牌局，引擎实现校验后重新生成
        log = load_fixture("game_log_dump_enforced.json")

        errors = errors_of(log)

        self.assertEqual(
            errors, [],
            "引擎已拦截非法甩牌，日志应无 error，实际: %s"
            % [f"{e.code}: {e.message}" for e in errors],
        )

    def test_engine_actually_downgraded_some_dumps(self) -> None:
        # 防止 fixture 退化成"根本没人甩牌所以没错"
        log = load_fixture("game_log_dump_enforced.json")

        failures = log["rounds"][0].get("dump_failures") or []

        self.assertGreater(len(failures), 0, "该 fixture 应记录到甩牌失败降级")
        for f in failures:
            self.assertIn("attempted", f)
            self.assertIn("played", f)
            self.assertGreater(f["trick_num"], 0, "墩号应已正确填入")
            self.assertLess(
                len([f["played"]]), len(f["attempted"]),
                "降级后只出一张，应少于原本想甩的张数",
            )

    def test_downgraded_card_is_the_smallest_attempted(self) -> None:
        # GDD：失败后出"最小的一张单牌"
        log = load_fixture("game_log_dump_enforced.json")
        rules = Rules(RuleConfig.from_log(log))
        rd = log["rounds"][0]
        trump_suit = rd["trump_suit"]
        current_rank = rd["rank"]

        for f in (rd.get("dump_failures") or []):
            attempted = parse_cards(f["attempted"])
            played = parse_cards([f["played"]])[0]
            smallest = min(
                attempted,
                key=lambda c: rules.sort_value(c, trump_suit, current_rank),
            )
            self.assertEqual(
                played.identity, smallest.identity,
                f"降级应出最小的 {smallest}，实际出了 {played}",
            )

    def test_dump_rule_does_not_leak_into_normal_play(self) -> None:
        # 随机对局里 AI 不甩牌，这条规则不该影响常规基线
        for name in ("game_log_quick.json", "game_log_classic.json",
                     "game_log_competitive.json"):
            with self.subTest(fixture=name):
                self.assertNotIn("dump_not_biggest", error_codes(load_fixture(name)))


class TestMutationDetection(unittest.TestCase):
    """每个用例篡改一处，断言校验器抓得到。"""

    def setUp(self) -> None:
        self.log = load_fixture("game_log_quick.json")

    def _mutate(self, fn) -> set[str]:
        mutated = copy.deepcopy(self.log)
        fn(mutated)
        return error_codes(mutated)

    def test_tampered_trick_winner_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["tricks"][0].__setitem__("winner", 2)
        )
        self.assertIn("winner", codes)

    def test_tampered_final_score_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["settlement"].__setitem__("final_score", 99)
        )
        self.assertIn("settlement", codes)

    def test_tampered_upgrade_levels_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["settlement"].__setitem__("upgrade_levels", 1)
        )
        self.assertIn("settlement", codes)

    def test_tampered_new_rank_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["settlement"].__setitem__("new_rank", 9)
        )
        self.assertIn("settlement", codes)

    def test_tampered_new_dealer_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["settlement"].__setitem__("new_dealer", 3)
        )
        self.assertIn("settlement", codes)

    def test_tampered_dethrone_flag_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["settlement"].__setitem__("dealer_dethroned", True)
        )
        self.assertIn("settlement", codes)

    def test_tampered_running_score_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["tricks"][3].__setitem__("attack_score_after", 999)
        )
        self.assertIn("attack_score_after", codes)

    def test_tampered_trick_points_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["tricks"][0].__setitem__("trick_points", 55)
        )
        self.assertIn("trick_points", codes)

    def test_tampered_play_order_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["tricks"][0]["plays"].reverse()
        )
        self.assertIn("play_order", codes)

    def test_tampered_lead_seat_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["tricks"][2].__setitem__("lead_seat", 3)
        )
        self.assertIn("lead_seat", codes)

    def test_card_played_from_thin_air_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["tricks"][5]["plays"][0]["cards"].__setitem__(
                0, "RedJoker")
        )
        self.assertIn("card_not_in_hand", codes)

    def test_broken_team_rank_continuity_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][1].__setitem__("team_ranks", [3, 3])
        )
        self.assertIn("team_ranks_continuity", codes)

    def test_broken_dealer_rotation_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][1].__setitem__("dealer", 2)
        )
        self.assertIn("dealer_rotation", codes)

    def test_tampered_winner_side_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["tricks"][0].__setitem__("winner_side", "dealer")
        )
        self.assertIn("winner_side", codes)

    def test_effective_diverging_from_top_level_detected(self) -> None:
        # 顶层字段就是 effective 的副本，两者必须严格一致
        codes = self._mutate(
            lambda m: m["rounds"][0]["settlement"]["effective"].__setitem__("new_rank", 7)
        )
        self.assertIn("effective_divergence", codes)

    def test_tampered_proposed_field_detected(self) -> None:
        # proposed 记录提案层原值，被改动应对照提案层复算查出
        codes = self._mutate(
            lambda m: m["rounds"][0]["settlement"]["proposed"].__setitem__(
                "upgrade_levels", 99)
        )
        self.assertIn("proposed_field", codes)

    def test_missing_buried_card_detected(self) -> None:
        # 底牌少一张 —— 若该牌无分，总分守恒察觉不到，靠底牌张数兜住
        codes = self._mutate(
            lambda m: m["rounds"][0]["buried_cards"].pop()
        )
        self.assertIn("bottom_size", codes)

    def test_extra_buried_card_detected(self) -> None:
        codes = self._mutate(
            lambda m: m["rounds"][0]["buried_cards"].append("♠3")
        )
        self.assertIn("bottom_size", codes)

    def test_tampered_hand_snapshot_detected(self) -> None:
        # 把某人出牌前的一张手牌换掉 —— 他随后打出的原牌就成了无中生有
        def swap(m):
            hands = m["rounds"][0]["debug"]["hands_at_play_start"]
            for seat, hand in enumerate(hands):
                for i, c in enumerate(hand):
                    if c != "RedJoker":
                        hand[i] = "RedJoker"
                        return
        codes = self._mutate(swap)
        self.assertTrue(codes, "篡改出牌前手牌快照必须被检出")


if __name__ == "__main__":
    unittest.main(verbosity=2)
