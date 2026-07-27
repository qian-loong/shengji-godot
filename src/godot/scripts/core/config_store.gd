## 进程内规则配置仓库
## - 开局 / 场景切换：只读内存 current
## - 磁盘 JSON：进程冷启动恢复 + 用户确认自定义时覆写
class_name ConfigStore
extends RefCounted


const SAVE_PATH := "user://custom_rule_config.json"

## 当前进程内生效配置（开局直接用）
static var current: RuleConfig = null


## 设为即将开局 / 已确认的配置（内存）
static func set_current(config: RuleConfig) -> void:
	current = config


## 取开局配置：优先内存；否则按预设；可选叠磁盘自定义
static func take_for_match(preferred_preset: int = -1) -> RuleConfig:
	if current != null:
		return current

	if preferred_preset >= 0 and preferred_preset <= int(RuleConfig.ConfigSource.PRESET_QUICK):
		var preset := preferred_preset as RuleConfig.ConfigSource
		var from_disk := load_custom_for_preset(preset)
		if from_disk:
			current = from_disk
			return current
		current = RuleConfig.from_preset(preset)
		return current

	current = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	return current


## 打开自定义页：内存同预设优先 → 磁盘同预设 → 预设默认
static func resolve_for_edit(preset: RuleConfig.ConfigSource) -> RuleConfig:
	if current != null and _matches_preset(current, preset):
		return current.duplicate_editable()

	var from_disk := load_custom_for_preset(preset)
	if from_disk:
		return from_disk.duplicate_editable()

	return RuleConfig.from_preset(preset)


## 确认自定义：写入内存 + 磁盘
static func commit_custom(config: RuleConfig) -> bool:
	_mark_custom_relative_to_base(config)
	current = config
	return save_to_disk(config)


## 直接开预设（未自定义）：写入内存，不强制写盘
static func commit_preset(preset: RuleConfig.ConfigSource) -> RuleConfig:
	# 若磁盘有该预设的自定义，直接开「选择此模式」仍用纯预设（用户没点自定义）
	var config := RuleConfig.from_preset(preset)
	current = config
	return config


static func save_to_disk(config: RuleConfig) -> bool:
	var json_string := JSON.stringify(config.to_dict(), "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("ConfigStore: 无法写入 %s" % SAVE_PATH)
		return false
	file.store_string(json_string)
	file.close()
	return true


static func load_custom_for_preset(preset: RuleConfig.ConfigSource) -> RuleConfig:
	var data := _read_disk_dict()
	if data.is_empty():
		return null

	var saved_base: int = int(data.get("base_preset", -1))
	if saved_base != int(preset):
		return null

	return RuleConfig.from_dict(data)


static func _read_disk_dict() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("ConfigStore: 无法读取 %s" % SAVE_PATH)
		return {}

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_error("ConfigStore: JSON 解析失败: %s" % json.get_error_message())
		return {}

	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data as Dictionary


static func _matches_preset(config: RuleConfig, preset: RuleConfig.ConfigSource) -> bool:
	if config.base_preset == preset:
		return true
	if config.source == preset:
		return true
	return false


## 相对 base_preset 标记 CUSTOM 与 modified_fields
static func _mark_custom_relative_to_base(config: RuleConfig) -> void:
	var base_id := config.base_preset
	if base_id == RuleConfig.ConfigSource.CUSTOM:
		base_id = RuleConfig.ConfigSource.PRESET_CLASSIC
		config.base_preset = base_id

	var base := RuleConfig.from_preset(base_id)
	var fields := [
		"deck_count", "upgrade_threshold", "upgrade_step", "allow_dump",
		"strict_follow_structure", "four_same_is_tractor", "tractor_allow_rank_card",
		"joker_always_trump", "trump_joker_color_match", "bid_requires_joker",
		"no_skip_enabled",
	]
	config.modified_fields.clear()
	for name: String in fields:
		if config.get(name) != base.get(name):
			config.modified_fields.append(name)

	if not config.modified_fields.is_empty():
		config.source = RuleConfig.ConfigSource.CUSTOM
	else:
		config.source = base_id
