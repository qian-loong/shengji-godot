## 进程内规则配置仓库
## - 开局 / 场景切换：只读内存 current
## - 磁盘 JSON：进程冷启动恢复 + 用户确认自定义时覆写
class_name ConfigStore
extends RefCounted


const SAVE_PATH := "user://custom_rule_config.json"

## 参与「是否被自定义」比对的字段。
## 派生值（hand_size/total_score 等）与元信息（source/base_preset）不在其中。
const TRACKED_FIELDS: PackedStringArray = [
	"deck_count", "upgrade_threshold", "upgrade_step", "upgrade_table",
	"allow_dump", "strict_follow_structure", "four_same_is_tractor",
	"tractor_allow_rank_card", "joker_always_trump", "trump_joker_color_match",
	"bid_requires_joker", "no_skip_enabled", "no_skip_ranks",
]

## 字段的中文短名，供 UI 标注「已改哪几项」
const FIELD_LABELS: Dictionary = {
	"deck_count": "副牌数",
	"upgrade_threshold": "升级门槛",
	"upgrade_step": "升级步数",
	"upgrade_table": "升级表",
	"allow_dump": "甩牌",
	"strict_follow_structure": "严格跟牌",
	"four_same_is_tractor": "四张同点拖拉机",
	"tractor_allow_rank_card": "级牌参与拖拉机",
	"joker_always_trump": "王恒为主",
	"trump_joker_color_match": "王色匹配",
	"bid_requires_joker": "需持王定主",
	"no_skip_enabled": "必打级",
	"no_skip_ranks": "必打级列表",
}

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


## 选择某预设开局：优先带出该预设已保存的自定义。
##
## 方案 A（2026-07-30）：自定义一旦保存就跟随该预设，无论从哪个入口进入。
## 此前这里无条件用纯预设覆盖 current，导致「保存自定义 → 退出 → 直接点该预设」
## 会静默丢弃自定义（磁盘上其实还在，只是被内存里的纯预设挡住）。
## 用户不会预期「点一下经典模式」等同于「放弃我存过的自定义」。
##
## 想要原版预设请用 commit_pristine_preset()。
static func commit_preset(preset: RuleConfig.ConfigSource) -> RuleConfig:
	var from_disk := load_custom_for_preset(preset)
	if from_disk:
		current = from_disk
		return current

	var config := RuleConfig.from_preset(preset)
	current = config
	return config


## 明确要求原版预设（忽略磁盘上的自定义），不写盘
static func commit_pristine_preset(preset: RuleConfig.ConfigSource) -> RuleConfig:
	var config := RuleConfig.from_preset(preset)
	current = config
	return config


## 该预设是否存在已保存的自定义；用于 UI 标注
static func has_custom_for_preset(preset: RuleConfig.ConfigSource) -> bool:
	return load_custom_for_preset(preset) != null


## 取某预设的自定义摘要，供预设卡片显示「已改 N 项」。
##
## 返回 { "count": int, "fields": PackedStringArray, "config": RuleConfig }；
## 无自定义时 count == 0、config 为纯预设。
static func describe_custom_for_preset(preset: RuleConfig.ConfigSource) -> Dictionary:
	var saved := load_custom_for_preset(preset)
	if saved == null:
		return {
			"count": 0,
			"fields": PackedStringArray(),
			"config": RuleConfig.from_preset(preset),
		}

	var base := RuleConfig.from_preset(preset)
	var changed := PackedStringArray()
	for field: String in TRACKED_FIELDS:
		if saved.get(field) != base.get(field):
			changed.append(field)

	return { "count": changed.size(), "fields": changed, "config": saved }


## 某字段相对其基底预设是否被改过
static func is_field_customized(config: RuleConfig, field: String) -> bool:
	if config == null:
		return false
	var base_id := config.base_preset
	if base_id < 0 or base_id > int(RuleConfig.ConfigSource.PRESET_QUICK):
		return false
	var base := RuleConfig.from_preset(base_id as RuleConfig.ConfigSource)
	return config.get(field) != base.get(field)


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
	config.modified_fields.clear()
	for field: String in TRACKED_FIELDS:
		if config.get(field) != base.get(field):
			config.modified_fields.append(field)

	if not config.modified_fields.is_empty():
		config.source = RuleConfig.ConfigSource.CUSTOM
	else:
		config.source = base_id
