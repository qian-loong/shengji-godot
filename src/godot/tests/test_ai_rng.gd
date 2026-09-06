## Unit tests for AIPlayer RNG injection (S5-05 Day-0 / ADR-0005 §可复现契约)
## Validates: FT1 ai-basic.md §可复现契约 — decide_bid 去全局 randf、
##            改由注入的确定性 RNG 驱动 → 同 seed 同输入逐字节可复现。
##
## 背景：decide_bid 的 trump_strength ∈ [2,4) 分支用随机决定是否亮主。
## 迁移前用全局 randf() → 同 seed 对局无法复现（AC16 死锁）。本测试隔离验证
## 注入 RNG 后该分支的确定性，是端到端哈希比对之外的确定性证据。
extends GutTest

const S = Card.Suit
const R = Card.Rank

var rc: RuleConfig


func before_each() -> void:
	rc = RuleConfig.new()
	rc.current_rank = R.FOUR
	# bid_requires_joker=false 使单张级牌即可定主，让 trump_strength=2（1 张级牌）
	# 的手牌能进入 decide_bid 的 randf 随机分支（否则无王时 get_available_bids 为空、提前返回）。
	rc.bid_requires_joker = false


## trump_strength 落在 [2,4) 随机分支的手牌：恰 1 张级牌（♠4，+2），无王。
## 其余为非级牌非王的杂牌，不加 trump_strength。
func _borderline_hand() -> Array:
	return [
		Card.normal(S.SPADE, R.FOUR),   # 级牌 → +2
		Card.normal(S.HEART, R.SEVEN),
		Card.normal(S.CLUB, R.NINE),
		Card.normal(S.DIAMOND, R.THREE),
	]


func _rng_with_seed(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_ai_rng_same_seed_same_bid_decision() -> void:
	# Arrange
	var hand := _borderline_hand()

	# Act — 同 seed 两个独立 RNG 实例，各调一次 decide_bid
	var decl_a := AIPlayer.new(0).decide_bid(0, hand, R.FOUR, rc, _rng_with_seed(12345))
	var decl_b := AIPlayer.new(0).decide_bid(0, hand, R.FOUR, rc, _rng_with_seed(12345))

	# Assert — 同 seed 同输入 → 决策一致（都亮或都不亮）
	var a_bid: bool = decl_a != null
	var b_bid: bool = decl_b != null
	assert_eq(a_bid, b_bid, "same seed must yield identical bid/pass decision")
	if a_bid and b_bid:
		assert_eq(decl_a.bid_type, decl_b.bid_type, "same seed → same bid type")
		assert_eq(decl_a.suit, decl_b.suit, "same seed → same suit")


func test_ai_rng_deterministic_across_many_seeds() -> void:
	# Arrange
	var hand := _borderline_hand()

	# Act + Assert — 对一批 seed，每个都调两次，逐一断言可复现。
	# 覆盖足够多 seed 以确保随机分支两侧（bid / pass）都被触及。
	for seed_value: int in range(0, 50):
		var d1 := AIPlayer.new(0).decide_bid(0, hand, R.FOUR, rc, _rng_with_seed(seed_value))
		var d2 := AIPlayer.new(0).decide_bid(0, hand, R.FOUR, rc, _rng_with_seed(seed_value))
		assert_eq(d1 != null, d2 != null,
			"seed %d must be reproducible (bid/pass)" % seed_value)


func test_ai_rng_seed_actually_drives_decision() -> void:
	# Arrange — 证明 RNG 确实驱动了随机分支：不同 seed 应能产生不同决策。
	# 若所有 seed 结果都相同，说明 randf 分支未被 RNG 影响（注入无效）。
	var hand := _borderline_hand()

	# Act — 扫一批 seed，统计"亮主"与"不亮"两种结果是否都出现
	var saw_bid := false
	var saw_pass := false
	for seed_value: int in range(0, 100):
		var decl := AIPlayer.new(0).decide_bid(0, hand, R.FOUR, rc, _rng_with_seed(seed_value))
		if decl != null:
			saw_bid = true
		else:
			saw_pass = true

	# Assert — 30% 概率分支下，100 个 seed 里两种结果都应出现，
	# 证明 _ai_rng 真正驱动了 decide_bid（而非常量行为）。
	assert_true(saw_bid, "some seeds should produce a bid (RNG drives the 30% branch)")
	assert_true(saw_pass, "some seeds should produce a pass (RNG drives the 30% branch)")


func test_ai_rng_null_falls_back_to_global_randf() -> void:
	# Arrange — rng=null（默认）时回退全局 randf()，不得报错、仍返回合法结果。
	# 这保证未迁移的调用点（早期测试、GUI/TUI 未传 rng）继续正常工作。
	var hand := _borderline_hand()

	# Act — 不传 rng（回退全局 randf）。多跑几次确保随机分支两侧都不崩溃。
	var all_legal := true
	for _i: int in range(20):
		var decl := AIPlayer.new(0).decide_bid(0, hand, R.FOUR, rc)
		# 合法结果 = null（pass）或 suit 为 ♠（唯一级牌花色）
		if decl != null and decl.suit != S.SPADE:
			all_legal = false

	# Assert — 回退路径永远返回合法结果、不崩溃（无条件断言，避免 risky）
	assert_true(all_legal, "rng=null fallback must always return a legal bid or pass")


# ============================================================
# set_private_known — 私有已知底牌注入的不可变约定 (步骤 D / ADR-0005 §4)
#
# GDScript 无 const 实例成员，靠 duplicate() 切引用 + 无 setter 暴露 +
# assert 单次注入 模拟不可变。这里验证 duplicate 切引用（改外部数组不污染
# 已注入的 private_known_cards）。
# ============================================================


func test_ai_set_private_known_duplicates_input() -> void:
	# Arrange
	var ai := AIPlayer.new(0)
	var cards := [Card.normal(S.SPADE, R.FIVE), Card.normal(S.HEART, R.KING)]

	# Act — 注入后改动原数组
	ai.set_private_known(cards)
	cards.clear()

	# Assert — 注入的快照不受外部改动影响（duplicate 切了引用）
	assert_eq(ai.private_known_cards.size(), 2,
		"set_private_known 存的是 duplicate，外部 clear 不影响")


func test_ai_private_known_defaults_empty() -> void:
	# Arrange + Act — 未注入时默认空
	var ai := AIPlayer.new(2)

	# Assert
	assert_eq(ai.private_known_cards.size(), 0, "未注入时 private_known_cards 默认空")
