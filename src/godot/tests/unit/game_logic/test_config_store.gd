extends GutTest

const RuleConfig = preload("res://scripts/core/rule_config.gd")
const ConfigStore = preload("res://scripts/core/config_store.gd")


func before_each() -> void:
	ConfigStore.current = null


func after_each() -> void:
	ConfigStore.current = null


func test_commit_preset_sets_memory_without_requiring_disk():
	var cfg = ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	assert_eq(cfg.upgrade_step, 2)
	assert_eq(ConfigStore.current.deck_count, 1)
	var match_cfg = ConfigStore.take_for_match(-1)
	assert_same(match_cfg, ConfigStore.current, "开局应直接使用内存对象")


func test_take_for_match_prefers_memory_over_preset_arg():
	ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	ConfigStore.current.allow_dump = false
	var cfg = ConfigStore.take_for_match(int(RuleConfig.ConfigSource.PRESET_QUICK))
	assert_eq(cfg.deck_count, 2, "有内存时忽略 preferred_preset 的快速默认")
	assert_false(cfg.allow_dump)


func test_resolve_for_edit_uses_memory_when_same_base():
	var custom = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	custom.set_custom_value("allow_dump", true)
	ConfigStore.set_current(custom)

	var edit = ConfigStore.resolve_for_edit(RuleConfig.ConfigSource.PRESET_QUICK)
	assert_true(edit.allow_dump)
	assert_ne(edit, custom, "编辑应得到可改副本")


func test_resolve_for_edit_uses_preset_when_memory_is_other_base():
	ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var edit = ConfigStore.resolve_for_edit(RuleConfig.ConfigSource.PRESET_QUICK)
	assert_eq(edit.deck_count, 1)
	assert_eq(edit.upgrade_step, 2)


func test_from_dict_fills_upgrade_table_from_base_when_missing():
	# 旧版 JSON 无 upgrade_table 时，应从 base_preset 带出快速表
	var data := {
		"source": int(RuleConfig.ConfigSource.CUSTOM),
		"base_preset": int(RuleConfig.ConfigSource.PRESET_QUICK),
		"allow_dump": true,
		"upgrade_step": 2,
		"upgrade_threshold": 60,
		"deck_count": 1,
	}
	var cfg = RuleConfig.from_dict(data)
	assert_eq(cfg.upgrade_step, 2)
	assert_true(cfg.allow_dump)
	assert_eq(cfg.upgrade_table[3][0], 60, "缺表时应恢复快速表 60 分档")
