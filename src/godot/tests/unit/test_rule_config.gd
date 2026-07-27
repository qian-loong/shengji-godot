extends GutTest

## RuleConfig 单元测试
##
## 测试规则配置系统的所有功能：
## - 默认值初始化
## - 验证逻辑
## - 锁定/解锁机制
## - 快照创建

const Card = preload("res://scripts/core/card.gd")

# ============================================================
# Setup / Teardown
# ============================================================

var config: RuleConfig

func before_each() -> void:
	config = RuleConfig.new()

func after_each() -> void:
	config = null


# ============================================================
# Test: 默认值初始化
# ============================================================

func test_rule_config_default_initialization_sets_correct_values() -> void:
	# Arrange & Act
	var cfg := RuleConfig.new()

	# Assert — Deck defaults
	assert_eq(cfg.deck_count, 2, "默认使用 2 副牌")
	assert_eq(cfg.current_rank, Card.Rank.TWO, "默认从 2 开始")

	# Assert — Derived values
	assert_eq(cfg.hand_size, 25, "2 副牌手牌数应为 25")
	assert_eq(cfg.bottom_size, 8, "2 副牌底牌数应为 8")
	assert_eq(cfg.total_cards, 108, "2 副牌总牌数应为 108")
	assert_eq(cfg.total_score, 200, "2 副牌总分值应为 200")

	# Assert — Trump defaults
	assert_eq(cfg.trump_mode, RuleConfig.TrumpMode.BID, "默认亮主模式")
	assert_true(cfg.joker_always_trump, "大小王默认总是主牌")

	# Assert — Play defaults
	assert_true(cfg.allow_dump, "默认允许甩牌")
	assert_true(cfg.strict_follow_structure, "默认严格跟牌结构")

	# Assert — Settlement defaults
	assert_eq(cfg.upgrade_threshold, 80, "默认升级阈值 80 分")
	assert_eq(cfg.upgrade_step, 1, "默认升级步长 1 级")


func test_rule_config_single_deck_computes_correct_derived_values() -> void:
	# Arrange
	config.deck_count = 1

	# Act & Assert
	assert_eq(config.hand_size, 12, "1 副牌手牌数应为 12")
	assert_eq(config.bottom_size, 6, "1 副牌底牌数应为 6")
	assert_eq(config.total_cards, 54, "1 副牌总牌数应为 54")
	assert_eq(config.total_score, 100, "1 副牌总分值应为 100")


# ============================================================
# Test: 验证逻辑
# ============================================================

func test_rule_config_validate_passes_with_valid_config() -> void:
	# Arrange
	config.deck_count = 2
	config.trump_mode = RuleConfig.TrumpMode.BID
	config.upgrade_threshold = 80

	# Act
	var errors := config.validate()

	# Assert
	assert_eq(errors.size(), 0, "有效配置不应有错误")


func test_rule_config_validate_fails_with_invalid_deck_count() -> void:
	# Arrange
	config.deck_count = 0

	# Act
	var errors := config.validate()

	# Assert
	assert_gt(errors.size(), 0, "无效 deck_count 应产生错误")
	assert_string_contains(errors[0], "deck_count")


func test_rule_config_validate_fails_when_fixed_trump_missing_suit() -> void:
	# Arrange
	config.trump_mode = RuleConfig.TrumpMode.FIXED
	config.fixed_trump_suit = -1

	# Act
	var errors := config.validate()

	# Assert
	assert_gt(errors.size(), 0, "FIXED 模式缺少花色应产生错误")
	assert_string_contains(errors[0], "fixed_trump_suit")


func test_rule_config_validate_fails_when_threshold_exceeds_total() -> void:
	# Arrange
	config.deck_count = 1  # total_score = 100
	config.upgrade_threshold = 120

	# Act
	var errors := config.validate()

	# Assert
	assert_gt(errors.size(), 0, "阈值超过总分应产生错误")
	assert_string_contains(errors[0], "upgrade_threshold")


func test_rule_config_validate_auto_corrects_impossible_four_same() -> void:
	# Arrange
	config.deck_count = 1
	config.four_same_is_tractor = true

	# Act
	var errors := config.validate()

	# Assert
	assert_eq(errors.size(), 0, "自动修正不应产生错误")
	assert_false(config.four_same_is_tractor, "1 副牌不应允许四连")


# ============================================================
# Test: 锁定/解锁机制
# ============================================================

func test_rule_config_lock_succeeds_with_valid_config() -> void:
	# Arrange
	config.deck_count = 2
	config.trump_mode = RuleConfig.TrumpMode.BID

	# Act
	var errors := config.lock()

	# Assert
	assert_eq(errors.size(), 0, "有效配置应成功锁定")
	assert_true(config.is_locked(), "配置应处于锁定状态")


func test_rule_config_lock_fails_with_invalid_config() -> void:
	# Arrange
	config.deck_count = 0  # 无效值

	# Act
	var errors := config.lock()

	# Assert
	assert_gt(errors.size(), 0, "无效配置应无法锁定")
	assert_false(config.is_locked(), "配置应保持编辑状态")


func test_rule_config_unlock_allows_editing_again() -> void:
	# Arrange
	config.deck_count = 2
	config.lock()
	assert_true(config.is_locked(), "前置条件：配置已锁定")

	# Act
	config.unlock()

	# Assert
	assert_false(config.is_locked(), "解锁后应可编辑")


# ============================================================
# Test: 快照创建
# ============================================================

func test_rule_config_create_snapshot_produces_independent_copy() -> void:
	# Arrange
	config.deck_count = 1
	config.current_rank = Card.Rank.FIVE
	config.trump_mode = RuleConfig.TrumpMode.GRAB
	config.allow_dump = false

	# Act
	var snapshot := config.create_snapshot()

	# Assert — 快照值正确
	assert_eq(snapshot.deck_count, 1)
	assert_eq(snapshot.current_rank, Card.Rank.FIVE)
	assert_eq(snapshot.trump_mode, RuleConfig.TrumpMode.GRAB)
	assert_false(snapshot.allow_dump)

	# Assert — 快照独立（修改原配置不影响快照）
	config.deck_count = 2
	config.allow_dump = true
	assert_eq(snapshot.deck_count, 1, "快照应独立于原配置")
	assert_false(snapshot.allow_dump, "快照应独立于原配置")


func test_rule_config_snapshot_deep_copies_arrays() -> void:
	# Arrange
	config.no_skip_ranks = [Card.Rank.FIVE, Card.Rank.TEN]

	# Act
	var snapshot := config.create_snapshot()

	# Assert — 修改原数组不影响快照
	config.no_skip_ranks.append(Card.Rank.KING)
	assert_eq(snapshot.no_skip_ranks.size(), 2, "快照数组应独立")
	assert_eq(config.no_skip_ranks.size(), 3, "原数组已修改")


# ============================================================
# Test: 升级表逻辑
# ============================================================

func test_rule_config_upgrade_table_has_correct_default_structure() -> void:
	# Arrange & Act
	var table := config.upgrade_table

	# Assert
	assert_eq(table.size(), 7, "默认升级表应有 7 行")
	assert_eq(table[0], [0, 0, 3], "攻方 0 分：庄家升 3 级")
	assert_eq(table[3], [80, 1, 0], "攻方 80 分：攻方夺庄，不升级")
	assert_eq(table[6], [200, 1, 3], "攻方 200 分：攻方升 3 级")


func test_rule_config_no_skip_ranks_defaults_to_five_ten_king() -> void:
	# Arrange & Act
	var ranks := config.no_skip_ranks

	# Assert
	assert_eq(ranks.size(), 3)
	assert_true(Card.Rank.FIVE in ranks)
	assert_true(Card.Rank.TEN in ranks)
	assert_true(Card.Rank.KING in ranks)


# ============================================================
# Test: 边界值与特殊情况
# ============================================================

func test_rule_config_allows_no_trump_mode() -> void:
	# Arrange
	config.trump_mode = RuleConfig.TrumpMode.NO_TRUMP

	# Act
	var errors := config.validate()

	# Assert
	assert_eq(errors.size(), 0, "无主模式应为有效配置")


func test_rule_config_allows_disabling_joker_trump() -> void:
	# Arrange
	config.joker_always_trump = false

	# Act
	var errors := config.validate()

	# Assert
	assert_eq(errors.size(), 0, "允许大小王不做主牌")
	assert_false(config.joker_always_trump)
