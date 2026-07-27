## Rule configuration system for 双升对局
## Implements: F3 Rule Config GDD (design/gdd/rule-config.md)
##
## Single source of truth for all configurable game rules.
## Generates an immutable snapshot (locked) before each round.
class_name RuleConfig
extends RefCounted


# ============================================================
# Enums
# ============================================================

enum ConfigSource {
	PRESET_CLASSIC,      ## 经典模式 - 传统玩法
	PRESET_COMPETITIVE,  ## 竞技模式 - 高手对决
	PRESET_QUICK,        ## 快速模式 - 休闲速战
	CUSTOM               ## 自定义配置
}

enum TrumpMode {
	BID,       # 亮主
	GRAB,      # 抢主 (first game only)
	COUNTER,   # 反主
	FIXED,     # 固定主
	NO_TRUMP,  # 无主
}

enum ConfigState {
	EDITING,
	LOCKED,
}


# ============================================================
# Preset Management
# ============================================================

## 配置来源（当前使用的模式）
var source: ConfigSource = ConfigSource.CUSTOM

## 基础预设（如果从预设修改而来，记录原始预设）
var base_preset: ConfigSource = ConfigSource.CUSTOM

## 被修改的字段列表（从预设修改后记录）
var modified_fields: Array[String] = []


# ============================================================
# Properties — Deck (F3 §2.1)
# ============================================================

var deck_count: int = 2
var current_rank: int = Card.Rank.TWO  # int to allow Rank enum values


# ============================================================
# Properties — Derived (read-only, computed from deck_count)
# ============================================================

var hand_size: int:
	get:
		return 25 if deck_count == 2 else 12

var bottom_size: int:
	get:
		return 8 if deck_count == 2 else 6

var total_cards: int:
	get:
		return deck_count * 54

var total_score: int:
	get:
		return deck_count * 100


# ============================================================
# Properties — Trump (F3 §2.2)
# ============================================================

var trump_mode: TrumpMode = TrumpMode.BID
var fixed_trump_suit: int = -1  # Card.Suit value or -1 for null
var joker_always_trump: bool = true
var trump_joker_color_match: bool = true
var bid_requires_joker: bool = true


# ============================================================
# Properties — Play (F3 §2.3)
# ============================================================

var allow_dump: bool = true
var strict_follow_structure: bool = true
var four_same_is_tractor: bool = false
var tractor_allow_rank_card: bool = true


# ============================================================
# Properties — Settlement (F3 §2.4)
# ============================================================

var upgrade_threshold: int = 80
var upgrade_step: int = 1

## Upgrade thresholds: [score_min, upgrading_side, levels]
## Side: 0 = dealer, 1 = attack
var upgrade_table: Array[Array] = [
	[0,   0, 3],  # attack=0: dealer upgrades 3
	[1,   0, 2],  # attack 1-39: dealer upgrades 2
	[40,  0, 1],  # attack 40-79: dealer upgrades 1
	[80,  1, 0],  # attack 80-119: attack dethrones, no upgrade
	[120, 1, 1],  # attack 120-159: attack upgrades 1
	[160, 1, 2],  # attack 160-199: attack upgrades 2
	[200, 1, 3],  # attack >=200: attack upgrades 3
]

## Ranks that cannot be skipped during upgrade
var no_skip_ranks: Array[int] = [Card.Rank.FIVE, Card.Rank.TEN, Card.Rank.KING]
var no_skip_enabled: bool = true


# ============================================================
# Properties — Dealer (F3 §2.5)
# ============================================================

var initial_dealer: int = -1  # -1 = determined by bidding


# ============================================================
# State
# ============================================================

var _state: ConfigState = ConfigState.EDITING


# ============================================================
# Validation (F3 §3)
# ============================================================

func validate() -> Array[String]:
	var errors: Array[String] = []

	if deck_count < 1 or deck_count > 2:
		errors.append("deck_count must be 1 or 2")

	if trump_mode == TrumpMode.FIXED and fixed_trump_suit < 0:
		errors.append("fixed_trump_suit required when trump_mode is FIXED")

	if upgrade_threshold > total_score:
		errors.append("upgrade_threshold (%d) exceeds total_score (%d)" % [upgrade_threshold, total_score])

	# Auto-correct: four_same_is_tractor impossible with 1 deck
	if deck_count == 1 and four_same_is_tractor:
		four_same_is_tractor = false

	return errors


# ============================================================
# Lock / Unlock
# ============================================================

func lock() -> Array[String]:
	var errors := validate()
	if errors.is_empty():
		_state = ConfigState.LOCKED
	return errors


func unlock() -> void:
	_state = ConfigState.EDITING


func is_locked() -> bool:
	return _state == ConfigState.LOCKED


# ============================================================
# Duplicate (for creating snapshot)
# ============================================================

func create_snapshot() -> RuleConfig:
	var snap := RuleConfig.new()
	snap.deck_count = deck_count
	snap.current_rank = current_rank
	snap.trump_mode = trump_mode
	snap.fixed_trump_suit = fixed_trump_suit
	snap.joker_always_trump = joker_always_trump
	snap.trump_joker_color_match = trump_joker_color_match
	snap.bid_requires_joker = bid_requires_joker
	snap.allow_dump = allow_dump
	snap.strict_follow_structure = strict_follow_structure
	snap.four_same_is_tractor = four_same_is_tractor
	snap.tractor_allow_rank_card = tractor_allow_rank_card
	snap.upgrade_threshold = upgrade_threshold
	snap.upgrade_step = upgrade_step
	snap.upgrade_table = upgrade_table.duplicate(true)
	snap.no_skip_ranks = no_skip_ranks.duplicate()
	snap.no_skip_enabled = no_skip_enabled
	snap.initial_dealer = initial_dealer
	return snap


## 创建可编辑副本（用于修改锁定的配置）
func duplicate_editable() -> RuleConfig:
	var dup := create_snapshot()
	dup.source = source
	dup.base_preset = base_preset
	dup.modified_fields = modified_fields.duplicate()
	dup._state = ConfigState.EDITING
	return dup


## 完整序列化（含 upgrade_table / upgrade_step，供磁盘与测试）
func to_dict() -> Dictionary:
	var table: Array = []
	for row: Array in upgrade_table:
		table.append([int(row[0]), int(row[1]), int(row[2])])
	return {
		"source": int(source),
		"base_preset": int(base_preset),
		"modified_fields": modified_fields.duplicate(),
		"deck_count": deck_count,
		"current_rank": current_rank,
		"trump_mode": int(trump_mode),
		"fixed_trump_suit": fixed_trump_suit,
		"joker_always_trump": joker_always_trump,
		"trump_joker_color_match": trump_joker_color_match,
		"bid_requires_joker": bid_requires_joker,
		"allow_dump": allow_dump,
		"strict_follow_structure": strict_follow_structure,
		"four_same_is_tractor": four_same_is_tractor,
		"tractor_allow_rank_card": tractor_allow_rank_card,
		"upgrade_threshold": upgrade_threshold,
		"upgrade_step": upgrade_step,
		"upgrade_table": table,
		"no_skip_enabled": no_skip_enabled,
		"no_skip_ranks": no_skip_ranks.duplicate(),
		"initial_dealer": initial_dealer,
	}


## 从字典恢复。优先以 base_preset 的预设表为底，再叠加存档字段（兼容旧 JSON 缺表）
static func from_dict(data: Dictionary) -> RuleConfig:
	if data.is_empty():
		return null

	var base_id: int = int(data.get("base_preset", ConfigSource.CUSTOM))
	var config: RuleConfig
	if base_id >= 0 and base_id <= int(ConfigSource.PRESET_QUICK):
		config = from_preset(base_id as ConfigSource)
	else:
		config = RuleConfig.new()

	if data.has("source"):
		config.source = int(data["source"]) as ConfigSource
	if data.has("base_preset"):
		config.base_preset = int(data["base_preset"]) as ConfigSource
	if data.has("deck_count"):
		config.deck_count = int(data["deck_count"])
	if data.has("current_rank"):
		config.current_rank = int(data["current_rank"])
	if data.has("trump_mode"):
		config.trump_mode = int(data["trump_mode"]) as TrumpMode
	if data.has("fixed_trump_suit"):
		config.fixed_trump_suit = int(data["fixed_trump_suit"])
	if data.has("joker_always_trump"):
		config.joker_always_trump = bool(data["joker_always_trump"])
	if data.has("trump_joker_color_match"):
		config.trump_joker_color_match = bool(data["trump_joker_color_match"])
	if data.has("bid_requires_joker"):
		config.bid_requires_joker = bool(data["bid_requires_joker"])
	if data.has("allow_dump"):
		config.allow_dump = bool(data["allow_dump"])
	if data.has("strict_follow_structure"):
		config.strict_follow_structure = bool(data["strict_follow_structure"])
	if data.has("four_same_is_tractor"):
		config.four_same_is_tractor = bool(data["four_same_is_tractor"])
	if data.has("tractor_allow_rank_card"):
		config.tractor_allow_rank_card = bool(data["tractor_allow_rank_card"])
	if data.has("upgrade_threshold"):
		config.upgrade_threshold = int(data["upgrade_threshold"])
	if data.has("upgrade_step"):
		config.upgrade_step = int(data["upgrade_step"])
	if data.has("no_skip_enabled"):
		config.no_skip_enabled = bool(data["no_skip_enabled"])
	if data.has("initial_dealer"):
		config.initial_dealer = int(data["initial_dealer"])

	if data.has("upgrade_table"):
		var raw_table: Array = data["upgrade_table"]
		var table: Array[Array] = []
		for row in raw_table:
			if row is Array and row.size() >= 3:
				table.append([int(row[0]), int(row[1]), int(row[2])])
		if not table.is_empty():
			config.upgrade_table = table

	if data.has("no_skip_ranks"):
		var ranks: Array[int] = []
		for r in data["no_skip_ranks"]:
			ranks.append(int(r))
		config.no_skip_ranks = ranks

	config.modified_fields.clear()
	if data.has("modified_fields"):
		for field in data["modified_fields"]:
			config.modified_fields.append(str(field))

	return config


# ============================================================
# Preset Factory Methods
# ============================================================

## 从预设模式创建配置
static func from_preset(preset: ConfigSource) -> RuleConfig:
	var config: RuleConfig
	match preset:
		ConfigSource.PRESET_CLASSIC:
			config = _create_classic_preset()
		ConfigSource.PRESET_COMPETITIVE:
			config = _create_competitive_preset()
		ConfigSource.PRESET_QUICK:
			config = _create_quick_preset()
		ConfigSource.CUSTOM:
			config = RuleConfig.new()  # 返回默认配置供用户修改
		_:
			push_error("Unknown preset: %s" % preset)
			config = RuleConfig.new()

	# 设置来源和基础预设
	config.source = preset
	config.base_preset = preset
	config.modified_fields.clear()
	return config


## 经典模式 - 传统升级玩法
static func _create_classic_preset() -> RuleConfig:
	var config := RuleConfig.new()
	# 牌副数：2副（经典玩法）
	config.deck_count = 2
	# 起始等级：2
	config.current_rank = 2
	# 定主方式：亮主
	config.trump_mode = TrumpMode.BID
	config.bid_requires_joker = false
	# 王牌规则：大小王始终是王牌
	config.joker_always_trump = true
	config.trump_joker_color_match = false
	# 出牌规则：允许甩牌，严格跟牌
	config.allow_dump = true
	config.strict_follow_structure = true
	# 拖拉机规则：四张相同算拖拉机，主牌可以参与
	config.four_same_is_tractor = true
	config.tractor_allow_rank_card = true
	# 升级规则：标准升级表
	# 格式：[最低分, 升级方(0=庄家/1=闲家), 升级级数]
	# 庄家守住：0分→3级，1-39分→2级，40-79分→1级
	# 闲家下庄：80-119分→不升级，120-159分→1级，160-199分→2级，200+分→3级
	config.upgrade_threshold = 80
	config.upgrade_step = 1
	config.upgrade_table = [
		[0, 0, 3],    # 庄家0分→升3级
		[1, 0, 2],    # 庄家1-39分→升2级
		[40, 0, 1],   # 庄家40-79分→升1级
		[80, 1, 0],   # 闲家80-119分→换庄不升级
		[120, 1, 1],  # 闲家120-159分→升1级
		[160, 1, 2],  # 闲家160-199分→升2级
		[200, 1, 3]   # 闲家200+分→升3级
	]
	config.no_skip_enabled = false
	config.no_skip_ranks = []
	# 发牌顺序：随机
	config.initial_dealer = -1
	return config


## 竞技模式 - 高手对决（更严格的规则）
static func _create_competitive_preset() -> RuleConfig:
	var config := RuleConfig.new()
	# 牌副数：2副（PRD 标准）
	config.deck_count = 2
	config.current_rank = 2
	# 定主方式：亮主（PRD 标准）
	config.trump_mode = TrumpMode.BID
	config.bid_requires_joker = false  # PRD：级牌可单独定主
	# 王牌规则：宽松定主规则
	config.joker_always_trump = true
	config.trump_joker_color_match = false  # PRD：降低定主门槛
	# 出牌规则：允许甩牌，严格跟牌结构
	config.allow_dump = true
	config.strict_follow_structure = true
	# 拖拉机规则：四张相同算拖拉机，主牌参与
	config.four_same_is_tractor = true
	config.tractor_allow_rank_card = true
	# 升级规则：100分门槛，50分间隔，完整四档
	# 庄家守住：0分→3级，1-49分→2级，50-99分→1级
	# 闲家下庄：100-149分→换庄不升级，150-199分→升1级，200-249分→升2级，250+分→升3级
	config.upgrade_threshold = 100
	config.upgrade_step = 1
	config.upgrade_table = [
		[0, 0, 3],     # 庄家0分→升3级
		[1, 0, 2],     # 庄家1-49分→升2级
		[50, 0, 1],    # 庄家50-99分→升1级
		[100, 1, 0],   # 闲家100-149分→换庄不升级
		[150, 1, 1],   # 闲家150-199分→升1级
		[200, 1, 2],   # 闲家200-249分→升2级
		[250, 1, 3]    # 闲家250+分→升3级
	]
	config.no_skip_enabled = true
	config.no_skip_ranks = [Card.Rank.FIVE, Card.Rank.TEN, Card.Rank.KING]  # PRD：5、10、K 不可跳过
	config.initial_dealer = -1
	return config


## 快速模式 - 休闲速战（简化规则，快速游戏）
static func _create_quick_preset() -> RuleConfig:
	var config := RuleConfig.new()
	# 牌副数：1副（最快速度）
	config.deck_count = 1
	config.current_rank = 2
	# 定主方式：亮主（保持标准）
	config.trump_mode = TrumpMode.BID
	config.bid_requires_joker = false  # 级牌可定主
	# 王牌规则：大小王始终是王牌（简化）
	config.joker_always_trump = true
	config.trump_joker_color_match = false
	# 出牌规则：禁用甩牌（简化），不严格跟牌（加快节奏）
	config.allow_dump = false  # PRD：禁用甩牌简化规则
	config.strict_follow_structure = false  # PRD：宽松跟牌
	config.strict_follow_structure = false
	# 拖拉机规则：简化（四张不算拖拉机）
	config.four_same_is_tractor = false
	config.tractor_allow_rank_card = false
	# 升级规则：低门槛快速升级
	# 庄家守住：0分→3级，1-29分→2级，30-59分→1级
	# 闲家下庄：60-89分→1级，90-119分→2级，120+分→3级
	config.upgrade_threshold = 60
	# GDD 快速模式：每次升 2 级（表中级数 × upgrade_step）
	config.upgrade_step = 2
	config.upgrade_table = [
		[0, 0, 3],     # 庄家0分→升3级
		[1, 0, 2],     # 庄家1-29分→升2级
		[30, 0, 1],    # 庄家30-59分→升1级
		[60, 1, 1],    # 闲家60-89分→升1级
		[90, 1, 2],    # 闲家90-119分→升2级
		[120, 1, 3]    # 闲家120+分→升3级
	]
	config.no_skip_enabled = false
	config.no_skip_ranks = []
	config.initial_dealer = -1
	return config


# ============================================================
# Preset Modification & Tracking
# ============================================================

## 设置自定义字段值（会自动标记为 CUSTOM）
func set_custom_value(field_name: String, value: Variant) -> void:
	if not field_name in self:
		push_error("Field '%s' does not exist in RuleConfig" % field_name)
		return

	# 设置字段值
	set(field_name, value)

	# 标记为自定义配置
	if source != ConfigSource.CUSTOM:
		source = ConfigSource.CUSTOM

	# 记录修改的字段（避免重复）
	if not modified_fields.has(field_name):
		modified_fields.append(field_name)


## 检查字段是否被修改过
func is_field_modified(field_name: String) -> bool:
	return modified_fields.has(field_name)


## 切换到新预设（丢弃所有修改）
func switch_preset(new_preset: ConfigSource) -> void:
	if new_preset == ConfigSource.CUSTOM:
		push_warning("Cannot switch to CUSTOM preset - use set_custom_value() instead")
		return

	# 加载新预设
	var new_config := from_preset(new_preset)
	_copy_from(new_config)


## 恢复到基础预设（丢弃所有修改）
func reset_to_base() -> void:
	if base_preset == ConfigSource.CUSTOM:
		push_warning("No base preset to reset to")
		return

	var base_config := from_preset(base_preset)
	_copy_from(base_config)


## 内部：从另一个配置复制所有字段
func _copy_from(other: RuleConfig) -> void:
	source = other.source
	base_preset = other.base_preset
	modified_fields = other.modified_fields.duplicate()

	deck_count = other.deck_count
	current_rank = other.current_rank
	trump_mode = other.trump_mode
	fixed_trump_suit = other.fixed_trump_suit
	joker_always_trump = other.joker_always_trump
	trump_joker_color_match = other.trump_joker_color_match
	bid_requires_joker = other.bid_requires_joker
	allow_dump = other.allow_dump
	strict_follow_structure = other.strict_follow_structure
	four_same_is_tractor = other.four_same_is_tractor
	tractor_allow_rank_card = other.tractor_allow_rank_card
	upgrade_threshold = other.upgrade_threshold
	upgrade_step = other.upgrade_step
	upgrade_table = other.upgrade_table.duplicate(true)
	no_skip_enabled = other.no_skip_enabled
	no_skip_ranks = other.no_skip_ranks.duplicate()
	initial_dealer = other.initial_dealer


## 获取配置描述（用于 UI 显示）
func get_config_description() -> String:
	match source:
		ConfigSource.PRESET_CLASSIC:
			return "经典模式"
		ConfigSource.PRESET_COMPETITIVE:
			return "竞技模式"
		ConfigSource.PRESET_QUICK:
			return "快速模式"
		ConfigSource.CUSTOM:
			var base_name := ""
			match base_preset:
				ConfigSource.PRESET_CLASSIC:
					base_name = "经典模式"
				ConfigSource.PRESET_COMPETITIVE:
					base_name = "竞技模式"
				ConfigSource.PRESET_QUICK:
					base_name = "快速模式"
				_:
					base_name = "默认"
			return "自定义配置（基于%s）" % base_name
		_:
			return "未知配置"
