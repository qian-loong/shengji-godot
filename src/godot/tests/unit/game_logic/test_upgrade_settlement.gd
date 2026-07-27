extends GutTest

const UpgradeSettlement = preload("res://scripts/core/upgrade_settlement.gd")
const RuleConfig = preload("res://scripts/core/rule_config.gd")
const Card = preload("res://scripts/core/card.gd")
const CardPattern = preload("res://scripts/core/card_pattern.gd")


# ========== 经典模式测试 ==========

func test_classic_dealer_defends_upgrades_1_level():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		40,      # 闲家得40分（< 80门槛）
		[],
		0,       # dealer_seat
		false,   # 庄家赢最后一墩
		pattern,
		5,       # current_rank
		config
	)

	assert_eq(result.upgrading_side, 0, "庄家守住应升级")
	assert_eq(result.upgrade_levels, 1, "应升1级")
	assert_eq(result.new_rank, 6, "5 -> 6")
	assert_false(result.dealer_dethroned, "庄家未被推翻")
	assert_false(result.game_over, "游戏未结束")


func test_classic_attack_scores_80_upgrades_1_level():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		80,      # 闲家得80分（刚好达到门槛）
		[],
		0,
		false,
		pattern,
		5,
		config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 0, "80-119分换庄不升级")
	assert_eq(result.new_rank, 5, "换庄但等级不变")
	assert_true(result.dealer_dethroned, "庄家被推翻")


func test_classic_attack_scores_120_upgrades_2_levels():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		120,     # 闲家得120分
		[],
		0,
		false,
		pattern,
		5,
		config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 1, "120-159分→升1级")
	assert_eq(result.new_rank, 6, "5 -> 6")
	assert_true(result.dealer_dethroned, "庄家被推翻")


func test_classic_attack_scores_160_upgrades_3_levels():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		160,     # 闲家得160分
		[],
		0,
		false,
		pattern,
		5,
		config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 2, "160-199分→升2级")
	assert_eq(result.new_rank, 7, "5 -> 7")
	assert_true(result.dealer_dethroned, "庄家被推翻")


# ========== 快速模式测试 ==========

func test_quick_dealer_defends_upgrades_with_step():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 表：30–59 庄升 1；step=2 → 实际 2 级
	var result = UpgradeSettlement.calculate(
		30, [], 0, false, pattern, 5, config
	)

	assert_eq(config.upgrade_step, 2)
	assert_eq(result.upgrading_side, 0, "庄家守住应升级")
	assert_eq(result.upgrade_levels, 2, "表1 × step2 = 2")
	assert_eq(result.new_rank, 7, "5 升 2 级 → 7")
	assert_false(result.dealer_dethroned, "庄家未被推翻")


func test_quick_attack_scores_60_upgrades_with_step():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 表：60–89 攻升 1；step=2 → 2 级
	var result = UpgradeSettlement.calculate(
		60, [], 0, false, pattern, 5, config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 2, "表1 × step2 = 2")
	assert_eq(result.new_rank, 7, "5 升 2 级 → 7")
	assert_true(result.dealer_dethroned, "庄家被推翻")


func test_quick_attack_scores_90_upgrades_with_step():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 表：90–119 攻升 2；step=2 → 4 级
	var result = UpgradeSettlement.calculate(
		90, [], 0, false, pattern, 5, config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 4, "表2 × step2 = 4")
	assert_eq(result.new_rank, 9, "5 升 4 级 → 9")
	assert_true(result.dealer_dethroned, "庄家被推翻")


func test_quick_attack_scores_120_upgrades_with_step():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 表：120+ 攻升 3；step=2 → 6 级
	var result = UpgradeSettlement.calculate(
		120, [], 0, false, pattern, 5, config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 6, "表3 × step2 = 6")
	assert_eq(result.new_rank, 11, "5 升 6 级 → J")
	assert_true(result.dealer_dethroned, "庄家被推翻")


# ========== 竞技模式测试 ==========

func test_competitive_dealer_defends_upgrades_1_level():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		50,      # 闲家得50分（< 100门槛）
		[],
		0,
		false,
		pattern,
		5,
		config
	)

	assert_eq(result.upgrading_side, 0, "庄家守住应升级")
	assert_eq(result.upgrade_levels, 1, "应升1级")
	assert_eq(result.new_rank, 6, "5 -> 6")
	assert_false(result.dealer_dethroned, "庄家未被推翻")


func test_competitive_attack_scores_100_dethrones_no_upgrade():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 竞技表：100–149 攻方换庄不升级（levels=0）
	var result = UpgradeSettlement.calculate(
		100, [], 0, false, pattern, 5, config
	)

	assert_eq(result.upgrading_side, 1, "闲家下庄")
	assert_eq(result.upgrade_levels, 0, "100–149 换庄不升级")
	assert_eq(result.new_rank, 5, "等级不变")
	assert_true(result.dealer_dethroned, "庄家被推翻")


func test_competitive_attack_scores_150_upgrades_1_level():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 竞技表：150–199 攻升 1；step=1 → 1 级
	var result = UpgradeSettlement.calculate(
		150, [], 0, false, pattern, 5, config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 1, "150–199 升 1 级")
	assert_eq(result.new_rank, 6, "5 -> 6")
	assert_true(result.dealer_dethroned, "庄家被推翻")


# ========== 游戏结束检测 ==========

func test_game_over_when_dealer_reaches_ace():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		40,      # 庄家守住升级
		[],
		0,
		false,
		pattern,
		13,      # 当前K
		config
	)

	assert_eq(result.upgrading_side, 0, "庄家升级")
	assert_eq(result.upgrade_levels, 1, "应升1级")
	assert_eq(result.new_rank, 14, "K -> A")
	assert_false(result.game_over, "到达A不结束（需要从A开始打完再升级才结束）")


func test_dealer_defends_0_score_upgrades_3_levels():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		0,       # 闲家得0分（大胜）
		[],
		0,
		false,
		pattern,
		5,
		config
	)

	assert_eq(result.upgrading_side, 0, "庄家守住应升级")
	assert_eq(result.upgrade_levels, 3, "0分应升3级")
	assert_eq(result.new_rank, 8, "5 -> 8")
	assert_false(result.dealer_dethroned, "庄家未被推翻")


func test_dealer_defends_1_to_39_score_upgrades_2_levels():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		30,      # 闲家得30分（1-39范围）
		[],
		0,
		false,
		pattern,
		5,
		config
	)

	assert_eq(result.upgrading_side, 0, "庄家守住应升级")
	assert_eq(result.upgrade_levels, 2, "1-39分应升2级")
	assert_eq(result.new_rank, 7, "5 -> 7")
	assert_false(result.dealer_dethroned, "庄家未被推翻")


func test_game_over_when_attack_reaches_ace():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 快速：90 分表升 2 × step2 = 4 级；Q(12) 升 4 → 过 A 钳制为 A
	var result = UpgradeSettlement.calculate(
		90, [], 0, false, pattern, 12, config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 4, "表2 × step2 = 4")
	assert_eq(result.new_rank, 14, "Q 升多级后钳制到 A")
	assert_false(result.game_over, "到达A不结束（需要从A开始打完再升级才结束）")


# ========== 不可跳等级测试 ==========

func test_competitive_no_skip_stops_at_ten():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 250 分：表升 3；从 9 开始：9→10（必打且还有剩余级数）→ 停在 10
	var result = UpgradeSettlement.calculate(
		250, [], 0, false, pattern, 9, config
	)

	assert_eq(result.upgrading_side, 1, "闲家升级")
	assert_eq(result.upgrade_levels, 3, "表3 × step1 = 3（申报级数）")
	assert_eq(result.new_rank, 10, "必打 10：9→10 后停止")
	assert_true(result.dealer_dethroned)


# ========== 边界测试 ==========

func test_upgrade_past_ace_returns_ace():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 120 分：表 3 × step 2 = 6 级；从 K 起会钳制到 A
	var result = UpgradeSettlement.calculate(
		120, [], 0, false, pattern, 13, config
	)

	assert_eq(result.new_rank, 14, "超过A仍返回A")
	assert_false(result.game_over, "到达A不结束（需要从A开始打完再升级才结束）")


# ========== 庄家换位测试 ==========

func test_dealer_change_when_dethroned():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		80,      # 庄家被推翻
		[],
		2,       # 当前庄家座位2
		false,
		pattern,
		5,
		config
	)

	assert_eq(result.new_dealer, 3, "庄家换到下一座位")
	assert_true(result.dealer_dethroned, "庄家被推翻")


func test_dealer_unchanged_when_defends():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	var result = UpgradeSettlement.calculate(
		40,      # 庄家守住
		[],
		2,       # 当前庄家座位2
		false,
		pattern,
		5,
		config
	)

	assert_eq(result.new_dealer, 2, "庄家不变")
	assert_false(result.dealer_dethroned, "庄家守住")


# ========== upgrade_step 乘数（GDD：表级数 × step） ==========

func test_upgrade_step_multiplies_dealer_levels():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_step = 2
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 经典表：攻方 40–79 → 庄家升 1 级；× step2 → 2 级
	var result = UpgradeSettlement.calculate(
		40, [], 0, false, pattern, 5, config
	)

	assert_eq(result.upgrading_side, 0)
	assert_eq(result.upgrade_levels, 2, "表1级 × step2 = 2")
	assert_eq(result.new_rank, 7, "5 升 2 级 → 7")


func test_upgrade_step_multiplies_attack_levels():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_step = 2
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 经典表：攻方 120–159 → 攻方升 1 级；× step2 → 2 级
	var result = UpgradeSettlement.calculate(
		120, [], 0, false, pattern, 5, config
	)

	assert_eq(result.upgrading_side, 1)
	assert_eq(result.upgrade_levels, 2, "表1级 × step2 = 2")
	assert_eq(result.new_rank, 7, "5 升 2 级 → 7")
	assert_true(result.dealer_dethroned)


func test_quick_preset_default_step_two_on_dealer_defend():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)

	# 快速表：攻方 30–59 → 庄家升 1 级；默认 step=2 → 2 级
	var result = UpgradeSettlement.calculate(
		30, [], 0, false, pattern, 2, config
	)

	assert_eq(config.upgrade_step, 2)
	assert_eq(result.upgrading_side, 0)
	assert_eq(result.upgrade_levels, 2)
	assert_eq(result.new_rank, 4, "2 升 2 级 → 4")
