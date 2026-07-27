extends GutTest

## RuleConfig 预设系统单元测试
##
## 测试预设加载、字段修改追踪、预设切换等功能

const RuleConfig = preload("res://scripts/core/rule_config.gd")


# ============================================================
# 预设加载测试
# ============================================================

func test_classic_preset_loads_correctly():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_CLASSIC, "source 应该是 PRESET_CLASSIC")
	assert_eq(config.base_preset, RuleConfig.ConfigSource.PRESET_CLASSIC, "base_preset 应该是 PRESET_CLASSIC")
	assert_eq(config.deck_count, 2, "经典模式应该是 2 副牌")
	assert_eq(config.upgrade_threshold, 80, "经典模式升级门槛应该是 80")
	assert_true(config.allow_dump, "经典模式应该允许甩牌")
	assert_true(config.strict_follow_structure, "经典模式应该严格跟牌")
	assert_eq(config.modified_fields.size(), 0, "初始配置不应有修改字段")


func test_competitive_preset_loads_correctly():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_COMPETITIVE)
	assert_eq(config.deck_count, 2, "竞技模式应该是 2 副牌")
	assert_eq(config.upgrade_threshold, 100, "竞技模式升级门槛应该是 100")
	assert_false(config.trump_joker_color_match, "竞技模式不需要王牌颜色匹配")
	assert_false(config.bid_requires_joker, "竞技模式级牌可单独定主")
	assert_true(config.no_skip_enabled, "竞技模式启用不可跳过规则")


func test_quick_preset_loads_correctly():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_QUICK)
	assert_eq(config.deck_count, 1, "快速模式应该是 1 副牌")
	assert_eq(config.current_rank, 2, "快速模式从 2 开始")
	assert_eq(config.upgrade_threshold, 60, "快速模式升级门槛 60")
	assert_eq(config.upgrade_step, 2, "快速模式每次升 2 级")
	assert_false(config.strict_follow_structure, "快速模式跟牌规则宽松")
	assert_false(config.four_same_is_tractor, "快速模式单副牌四张不算拖拉机")
	assert_false(config.allow_dump, "快速模式默认禁用甩牌")
	assert_false(config.no_skip_enabled, "快速模式可跳过等级")


func test_to_dict_from_dict_roundtrip_preserves_upgrade_table_and_step():
	var original = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	original.set_custom_value("allow_dump", true)
	original.set_custom_value("upgrade_step", 2)

	var restored = RuleConfig.from_dict(original.to_dict())

	assert_eq(restored.upgrade_step, 2)
	assert_eq(restored.upgrade_threshold, 60)
	assert_true(restored.allow_dump)
	assert_eq(restored.upgrade_table.size(), original.upgrade_table.size())
	assert_eq(restored.upgrade_table[3][0], 60, "快速表闲家门槛应为 60")
	assert_eq(restored.base_preset, RuleConfig.ConfigSource.PRESET_QUICK)


# ============================================================
# 自定义配置测试
# ============================================================

func test_set_custom_value_marks_as_custom():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_custom_value("upgrade_threshold", 100)

	assert_eq(config.source, RuleConfig.ConfigSource.CUSTOM, "修改后 source 应该是 CUSTOM")
	assert_eq(config.base_preset, RuleConfig.ConfigSource.PRESET_CLASSIC, "base_preset 应该保持为 CLASSIC")
	assert_eq(config.upgrade_threshold, 100, "字段值应该被修改")
	assert_eq(config.modified_fields.size(), 1, "应该记录 1 个修改字段")
	assert_true(config.is_field_modified("upgrade_threshold"))


func test_set_custom_value_tracks_multiple_fields():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_custom_value("upgrade_threshold", 100)
	config.set_custom_value("deck_count", 1)
	config.set_custom_value("allow_dump", false)

	assert_eq(config.modified_fields.size(), 3, "应该记录 3 个修改字段")
	assert_true(config.is_field_modified("upgrade_threshold"))
	assert_true(config.is_field_modified("deck_count"))
	assert_true(config.is_field_modified("allow_dump"))
	assert_false(config.is_field_modified("upgrade_step"), "未修改的字段不应该被标记")


func test_set_custom_value_does_not_duplicate_tracking():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_custom_value("upgrade_threshold", 100)
	config.set_custom_value("upgrade_threshold", 90)
	config.set_custom_value("upgrade_threshold", 110)

	assert_eq(config.modified_fields.size(), 1, "同一字段多次修改只记录一次")
	assert_eq(config.upgrade_threshold, 110, "字段值应该是最后一次修改的值")


# ============================================================
# 预设切换测试
# ============================================================

func test_switch_preset_discards_modifications():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_custom_value("upgrade_threshold", 100)
	config.set_custom_value("deck_count", 1)
	assert_eq(config.source, RuleConfig.ConfigSource.CUSTOM)

	config.switch_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_COMPETITIVE, "source 应该是新预设")
	assert_eq(config.base_preset, RuleConfig.ConfigSource.PRESET_COMPETITIVE, "base_preset 应该更新")
	assert_eq(config.upgrade_threshold, 100, "应该加载竞技模式的门槛")
	assert_eq(config.deck_count, 2, "应该加载竞技模式的牌副数")
	assert_eq(config.modified_fields.size(), 0, "modified_fields 应该被清空")


func test_switch_preset_to_same_preset_clears_custom():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	config.set_custom_value("upgrade_threshold", 100)
	assert_eq(config.source, RuleConfig.ConfigSource.CUSTOM)

	config.switch_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_CLASSIC)
	assert_eq(config.upgrade_threshold, 80, "应该恢复为经典模式的默认值")
	assert_eq(config.modified_fields.size(), 0)


# ============================================================
# 恢复预设测试
# ============================================================

func test_reset_to_base_after_modification():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)

	config.set_custom_value("upgrade_threshold", 80)
	config.set_custom_value("allow_dump", false)
	assert_eq(config.source, RuleConfig.ConfigSource.CUSTOM)

	config.reset_to_base()

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_COMPETITIVE, "应该恢复为竞技模式")
	assert_eq(config.upgrade_threshold, 100, "应该恢复为竞技模式的门槛")
	assert_eq(config.allow_dump, true, "应该恢复为竞技模式的甩牌设置")
	assert_eq(config.modified_fields.size(), 0)


func test_reset_to_base_preserves_base_preset():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	config.set_custom_value("deck_count", 2)
	assert_eq(config.base_preset, RuleConfig.ConfigSource.PRESET_QUICK)

	config.reset_to_base()

	assert_eq(config.source, RuleConfig.ConfigSource.PRESET_QUICK)
	assert_eq(config.base_preset, RuleConfig.ConfigSource.PRESET_QUICK)
	assert_eq(config.deck_count, 1, "应该恢复为快速模式的牌副数")


# ============================================================
# 配置描述测试
# ============================================================

func test_get_config_description_for_preset():
	var classic = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var competitive = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)
	var quick = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_eq(classic.get_config_description(), "经典模式")
	assert_eq(competitive.get_config_description(), "竞技模式")
	assert_eq(quick.get_config_description(), "快速模式")


func test_get_config_description_for_custom():
	var config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_COMPETITIVE)
	config.set_custom_value("upgrade_threshold", 90)

	var description = config.get_config_description()
	assert_true(description.contains("自定义配置"), "应该显示为自定义配置")
	assert_true(description.contains("竞技模式"), "应该显示基于哪个预设")
