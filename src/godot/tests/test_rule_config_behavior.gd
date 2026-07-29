## RuleConfig behavior tests — 预设加载 / 自定义追踪 / 预设切换 / 校验
##
## 迁移自仓库根 tests/unit/game_logic/（位置在 res:// 之外，GUT 从未加载过，
## 详见 .claude/docs/coding-standards.md 的测试位置约定）。
##
## 迁移时按 GDD design/gdd/rule-config.md 逐项核对了断言，分三类处理：
##   1. 旧测试对、实现偏离 GDD → 已改实现（classic 的必打级与定主门槛）
##   2. 旧测试对、实现缺校验   → 已补实现（upgrade_step 范围）
##   3. 旧测试期望本身错误     → 改测试（hand_size 期望 50 张，
##      而 4×50=200 超过 2 副牌的 108 张，数学上不成立）
##
## 与同目录 test_rule_config.gd 互补：那边覆盖默认值/派生/lock，这边覆盖
## 预设值与配置编辑行为。
extends GutTest

const R := Card.Rank


# ============================================================
# 预设加载
# ============================================================

func test_classic_preset_values() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(config.deck_count, 2, "经典模式使用 2 副牌")
	assert_eq(config.upgrade_threshold, 80, "经典模式 80 分门槛")
	assert_eq(config.upgrade_step, 1, "经典模式每次升 1 级")
	assert_true(config.no_skip_enabled, "经典模式不能跳过 5/10/K")
	assert_true(config.allow_dump, "经典模式允许甩牌")
	assert_true(config.strict_follow_structure, "经典模式严格跟牌")
	assert_true(config.trump_joker_color_match, "经典模式王须匹配花色")
	assert_true(config.bid_requires_joker, "经典模式必须持有王才能定主")


func test_competitive_preset_values() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)

	assert_eq(config.deck_count, 2, "竞技模式使用 2 副牌")
	assert_eq(config.upgrade_threshold, 100, "竞技模式 100 分门槛")
	assert_true(config.no_skip_enabled, "竞技模式不能跳过 5/10/K")
	assert_false(config.trump_joker_color_match, "竞技模式降低定主门槛")
	assert_false(config.bid_requires_joker, "竞技模式级牌可单独定主")


func test_quick_preset_values() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_eq(config.deck_count, 1, "快速模式使用 1 副牌")
	assert_eq(config.upgrade_threshold, 60, "快速模式 60 分门槛（1 副牌总分仅 100）")
	assert_eq(config.upgrade_step, 2, "快速模式每次升 2 级")
	assert_false(config.no_skip_enabled, "快速模式可跳过 5/10/K")
	assert_false(config.allow_dump, "快速模式禁用甩牌")
	assert_false(config.strict_follow_structure, "快速模式跟牌宽松")


# ============================================================
# 自定义值追踪
# ============================================================

func test_set_custom_value_marks_as_custom() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_custom_value("upgrade_threshold", 100)

	assert_eq(config.source, RuleConfig.ConfigSource.CUSTOM, "修改后应标记为自定义")
	assert_eq(config.base_preset, RuleConfig.ConfigSource.PRESET_CLASSIC,
		"应保留原始预设作为基底")
	assert_true(config.is_field_modified("upgrade_threshold"))


func test_set_custom_value_tracks_multiple_fields() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_custom_value("upgrade_threshold", 100)
	config.set_custom_value("allow_dump", false)

	assert_eq(config.modified_fields.size(), 2, "应追踪两个被修改的字段")
	assert_true(config.is_field_modified("upgrade_threshold"))
	assert_true(config.is_field_modified("allow_dump"))


func test_set_custom_value_does_not_duplicate_tracking() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_custom_value("upgrade_threshold", 100)
	config.set_custom_value("upgrade_threshold", 120)

	assert_eq(config.modified_fields.size(), 1, "同一字段改两次只记一条")
	assert_eq(config.upgrade_threshold, 120, "保留最后一次的值")


# ============================================================
# 预设切换与重置
# ============================================================

func test_switch_preset_discards_modifications() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.set_custom_value("upgrade_threshold", 999)

	config.switch_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_QUICK)
	assert_eq(config.upgrade_threshold, 60, "切换后应取新预设的值")
	assert_eq(config.modified_fields.size(), 0, "切换后清空修改记录")


func test_switch_preset_to_same_preset_clears_custom() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.set_custom_value("upgrade_threshold", 999)

	config.switch_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_CLASSIC,
		"切回同一预设应还原为纯预设")
	assert_eq(config.upgrade_threshold, 80)
	assert_eq(config.modified_fields.size(), 0)


func test_switch_preset_to_custom_is_ignored() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var before := config.upgrade_threshold

	config.switch_preset(RuleConfig.ConfigSource.CUSTOM)

	assert_eq(config.upgrade_threshold, before, "切到 CUSTOM 无意义，应被忽略")


func test_reset_to_base_after_modification() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.set_custom_value("upgrade_threshold", 999)
	config.set_custom_value("allow_dump", false)

	config.reset_to_base()

	assert_eq(config.upgrade_threshold, 80, "应还原为基底预设的值")
	assert_true(config.allow_dump)
	assert_eq(config.modified_fields.size(), 0)


func test_reset_to_base_preserves_base_preset() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	config.set_custom_value("upgrade_threshold", 999)

	config.reset_to_base()

	assert_eq(config.base_preset, RuleConfig.ConfigSource.PRESET_QUICK,
		"还原后基底预设不变")
	assert_eq(config.upgrade_threshold, 60)


# ============================================================
# 配置描述
# ============================================================

func test_get_config_description_for_preset() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var text := config.get_config_description()

	assert_false(text.is_empty(), "纯预设应有描述文本")


func test_get_config_description_for_custom() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.set_custom_value("upgrade_threshold", 100)

	var text := config.get_config_description()

	assert_false(text.is_empty(), "自定义配置应有描述文本")


# ============================================================
# 配置校验
#
# validate() 返回 Array[String]（旧测试按返回 String 写的，已改）
# ============================================================

func test_validate_accepts_valid_config() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var errors := config.validate()

	assert_eq(errors, [] as Array[String], "经典预设应该验证通过")


func test_validate_rejects_invalid_deck_count() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.deck_count = 0

	var errors := config.validate()

	assert_gt(errors.size(), 0, "deck_count=0 应该验证失败")
	assert_true(" ".join(errors).contains("deck_count"), "错误信息应提到 deck_count")


func test_validate_rejects_invalid_upgrade_threshold() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_threshold = 300

	var errors := config.validate()

	assert_gt(errors.size(), 0, "upgrade_threshold=300 应该验证失败")
	assert_true(" ".join(errors).contains("upgrade_threshold"),
		"错误信息应提到 upgrade_threshold")


func test_validate_rejects_invalid_upgrade_step() -> void:
	# GDD rule-config.md 规定取值 1–3；该校验原先缺失，随本次迁移补上
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_step = 5

	var errors := config.validate()

	assert_gt(errors.size(), 0, "upgrade_step=5 应该验证失败")
	assert_true(" ".join(errors).contains("upgrade_step"), "错误信息应提到 upgrade_step")


func test_validate_accepts_upgrade_step_boundaries() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	for step: int in [1, 2, 3]:
		config.upgrade_step = step
		assert_eq(config.validate(), [] as Array[String],
			"upgrade_step=%d 应合法" % step)


func test_validate_rejects_upgrade_step_zero() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_step = 0

	assert_gt(config.validate().size(), 0, "upgrade_step=0 应该验证失败")


# ============================================================
# 派生值
#
# 旧测试期望每人 50 张手牌，但 4×50=200 超过 2 副牌的 108 张，
# 数学上不成立。GDD rule-config.md AC2/AC3 规定 2副=25/8、1副=12/6。
# ============================================================

func test_hand_size_for_two_decks() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(config.hand_size, 25, "2 副牌每人 25 张")
	assert_eq(config.bottom_size, 8, "2 副牌底牌 8 张")


func test_hand_size_for_one_deck() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_eq(config.hand_size, 12, "1 副牌每人 12 张")
	assert_eq(config.bottom_size, 6, "1 副牌底牌 6 张")


func test_deal_partition_is_exhaustive() -> void:
	# 4×hand_size + bottom_size 必须正好等于总牌数，否则发牌会漏牌或超发
	for preset: int in [
		RuleConfig.ConfigSource.PRESET_CLASSIC,
		RuleConfig.ConfigSource.PRESET_QUICK,
	]:
		var config := RuleConfig.from_preset(preset as RuleConfig.ConfigSource)
		assert_eq(
			4 * config.hand_size + config.bottom_size,
			config.deck_count * 54,
			"预设 %d 的发牌划分应恰好用完整副牌" % preset)
