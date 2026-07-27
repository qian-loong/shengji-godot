extends GutTest

const UpgradeSettlement = preload("res://scripts/core/upgrade_settlement.gd")
const RuleConfig = preload("res://scripts/core/rule_config.gd")
const CardPattern = preload("res://scripts/core/card_pattern.gd")


func test_debug_classic_dealer_defends():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result = UpgradeSettlement.calculate(40, [], 0, false, pattern, 5, config)

	assert_eq(result.upgrading_side, 0)
	assert_eq(result.upgrade_levels, 1)
	assert_eq(result.new_rank, 6)


func test_debug_quick_dealer_defends():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	var pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	# 表 1 × step 2
	var result = UpgradeSettlement.calculate(30, [], 0, false, pattern, 5, config)

	assert_eq(result.upgrading_side, 0)
	assert_eq(result.upgrade_levels, 2)
	assert_eq(result.new_rank, 7)
