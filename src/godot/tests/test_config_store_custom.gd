## ConfigStore 自定义配置的存取语义（方案 A，2026-07-30）
##
## 核心约定：自定义一旦保存就跟随该预设，无论从哪个入口进入都生效。
## 回归的 bug：保存自定义 → 退出 → 直接点该预设 → 自定义被静默丢弃。
extends GutTest

var _disk_backup: String = ""
var _had_backup: bool = false


func before_all() -> void:
	# SAVE_PATH 指向 user://，和玩家实机存档是同一个文件。
	# 跑一次测试就把人家的自定义规则抹掉显然不合适，先备份、跑完还原。
	if FileAccess.file_exists(ConfigStore.SAVE_PATH):
		_disk_backup = FileAccess.get_file_as_string(ConfigStore.SAVE_PATH)
		_had_backup = true


func before_each() -> void:
	ConfigStore.current = null
	_remove_saved_config()


func after_all() -> void:
	ConfigStore.current = null
	if _had_backup:
		var file := FileAccess.open(ConfigStore.SAVE_PATH, FileAccess.WRITE)
		file.store_string(_disk_backup)
		file.close()
	else:
		_remove_saved_config()


func _remove_saved_config() -> void:
	if FileAccess.file_exists(ConfigStore.SAVE_PATH):
		DirAccess.remove_absolute(ConfigStore.SAVE_PATH)


## 造一份「经典 + 升级步数改为 2」的自定义并存盘
func _save_classic_with_step2() -> RuleConfig:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_step = 2
	ConfigStore.commit_custom(config)
	return config


# ============================================================
# 方案 A：自定义跟随预设
# ============================================================

func test_commit_preset_restores_saved_custom() -> void:
	# 这正是真机上报的路径：存了自定义，退出，再直接点该预设
	_save_classic_with_step2()
	ConfigStore.current = null  # 模拟退出游戏、内存清空

	var opened := ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(opened.upgrade_step, 2, "直接点预设也应带出已保存的自定义")


func test_custom_survives_repeated_preset_entry() -> void:
	# 反复进出不应逐步丢失自定义
	_save_classic_with_step2()

	for i: int in range(3):
		ConfigStore.current = null
		var opened := ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
		assert_eq(opened.upgrade_step, 2, "第 %d 次进入仍应保留自定义" % (i + 1))


func test_edit_page_sees_saved_custom_after_preset_entry() -> void:
	# 复现路径：存自定义 → 直接开预设 → 再打开自定义页，值不应被打回原样
	_save_classic_with_step2()
	ConfigStore.current = null
	ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var for_edit := ConfigStore.resolve_for_edit(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(for_edit.upgrade_step, 2, "自定义页应显示已保存的值，而非预设默认")


func test_pristine_preset_ignores_custom() -> void:
	# 需要原版预设时有明确入口，不与 commit_preset 混淆
	_save_classic_with_step2()
	ConfigStore.current = null

	var pristine := ConfigStore.commit_pristine_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(pristine.upgrade_step, 1, "显式要求原版时应忽略自定义")


func test_custom_does_not_leak_across_presets() -> void:
	# 经典的自定义不应影响快速模式
	_save_classic_with_step2()
	ConfigStore.current = null

	var quick := ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_eq(quick.upgrade_step, 2, "快速预设自身 step 就是 2")
	assert_eq(quick.upgrade_threshold, 60, "应取快速预设的门槛而非经典的")
	assert_eq(quick.base_preset, RuleConfig.ConfigSource.PRESET_QUICK)


# ============================================================
# 自定义标注（供预设卡片 / 配置页显示）
# ============================================================

func test_describe_custom_reports_zero_without_saved_config() -> void:
	var info := ConfigStore.describe_custom_for_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(info["count"], 0, "无自定义时应报 0 项")
	assert_eq((info["config"] as RuleConfig).upgrade_step, 1)


func test_describe_custom_counts_changed_fields() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_step = 2
	config.allow_dump = false
	ConfigStore.commit_custom(config)

	var info := ConfigStore.describe_custom_for_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(info["count"], 2, "应统计出 2 个被改字段")
	var fields: PackedStringArray = info["fields"]
	assert_true(fields.has("upgrade_step"))
	assert_true(fields.has("allow_dump"))


func test_describe_custom_ignores_other_preset() -> void:
	_save_classic_with_step2()

	var info := ConfigStore.describe_custom_for_preset(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_eq(info["count"], 0, "快速预设不应看到经典的自定义")


func test_is_field_customized_flags_only_changed_fields() -> void:
	var config := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	config.upgrade_step = 2

	assert_true(ConfigStore.is_field_customized(config, "upgrade_step"))
	assert_false(ConfigStore.is_field_customized(config, "allow_dump"))


func test_every_tracked_field_has_label() -> void:
	# 标注要显示中文名，漏一个就会在界面上露出字段名
	for field: String in ConfigStore.TRACKED_FIELDS:
		assert_true(ConfigStore.FIELD_LABELS.has(field),
			"字段 %s 缺少 FIELD_LABELS 中文名" % field)


func test_has_custom_for_preset() -> void:
	assert_false(ConfigStore.has_custom_for_preset(RuleConfig.ConfigSource.PRESET_CLASSIC))

	_save_classic_with_step2()

	assert_true(ConfigStore.has_custom_for_preset(RuleConfig.ConfigSource.PRESET_CLASSIC))
	assert_false(ConfigStore.has_custom_for_preset(RuleConfig.ConfigSource.PRESET_QUICK))
