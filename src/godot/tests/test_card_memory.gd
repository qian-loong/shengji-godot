## Unit tests for CardMemory (FT1 SMART / ADR-0005 步骤 B)
## Validates: 公开记牌副本计数（identity 坐标）、record_trick 累加、
##            remaining_copies 的 own_known 扣减与 clamp、王计数、identity 区分。
##
## CardMemory 是 SMART「铁最大判定」(ai-basic.md §4b B2) 的副本计数基础设施。
## 本测覆盖计数正确性；铁最大判定逻辑本身留 SMART 决策测（步骤 E）。
extends GutTest

const S = Card.Suit
const R = Card.Rank
const J = Card.JokerType


func _plays(seat: int, cards: Array) -> Array:
	## 造一墩 plays 的单条 entry（record_trick 只读 cards）。
	return [{"seat": seat, "cards": cards}]


func test_card_memory_init_two_decks_all_counts_zero() -> void:
	# Arrange + Act
	var mem := CardMemory.new(2)

	# Assert — 初始所有副本未出，remaining = 上界 deck_count
	assert_eq(mem.played_copies(S.SPADE, R.FIVE), 0, "初始 ♠5 已出 0 份")
	assert_eq(mem.remaining_copies(S.SPADE, R.FIVE, 0), 2, "两副牌 ♠5 剩 2 份")
	assert_eq(mem.remaining_joker_copies(J.BIG, 0), 2, "两副牌大王剩 2 份")


func test_card_memory_init_one_deck_upper_bound_is_one() -> void:
	# Arrange + Act
	var mem := CardMemory.new(1)

	# Assert — 单副牌每 identity 上界 1
	assert_eq(mem.remaining_copies(S.HEART, R.KING, 0), 1, "单副牌 ♥K 剩 1 份")
	assert_eq(mem.remaining_joker_copies(J.SMALL, 0), 1, "单副牌小王剩 1 份")


func test_card_memory_record_trick_tallies_by_identity() -> void:
	# Arrange
	var mem := CardMemory.new(2)

	# Act — 一墩出了 ♠5 和 ♥5（不同 identity）
	mem.record_trick(_plays(0, [Card.normal(S.SPADE, R.FIVE), Card.normal(S.HEART, R.FIVE)]))

	# Assert — 各自 +1，互不影响（identity 坐标区分花色）
	assert_eq(mem.played_copies(S.SPADE, R.FIVE), 1, "♠5 已出 1 份")
	assert_eq(mem.played_copies(S.HEART, R.FIVE), 1, "♥5 已出 1 份")
	assert_eq(mem.remaining_copies(S.SPADE, R.FIVE, 0), 1, "♠5 剩 1 份")
	assert_eq(mem.remaining_copies(S.HEART, R.FIVE, 0), 1, "♥5 剩 1 份")


func test_card_memory_record_trick_accumulates_across_tricks() -> void:
	# Arrange
	var mem := CardMemory.new(2)

	# Act — 两墩各出一张 ♠5（两副牌下合法：两份物理副本）
	mem.record_trick(_plays(0, [Card.normal(S.SPADE, R.FIVE)]))
	mem.record_trick(_plays(1, [Card.normal(S.SPADE, R.FIVE)]))

	# Assert — 逐墩累加到 2 份，剩 0
	assert_eq(mem.played_copies(S.SPADE, R.FIVE), 2, "两墩后 ♠5 已出 2 份")
	assert_eq(mem.remaining_copies(S.SPADE, R.FIVE, 0), 0, "♠5 全出完，剩 0")


func test_card_memory_remaining_subtracts_own_known() -> void:
	# Arrange — 两副牌 ♠K，自己手里有 1 张（own_known=1）
	var mem := CardMemory.new(2)

	# Act + Assert — 没出牌但自己攥着 1 张 → 对手可及只剩 1
	assert_eq(mem.remaining_copies(S.SPADE, R.KING, 1), 1,
		"own_known=1 → 对手可及 ♠K 剩 1 份（铁最大判定用）")
	# 自己攥 2 张 → 对手 0 份（铁最大）
	assert_eq(mem.remaining_copies(S.SPADE, R.KING, 2), 0,
		"own_known=2 → 对手 ♠K 剩 0 份")


func test_card_memory_remaining_clamps_to_zero() -> void:
	# Arrange — 制造 played + own_known > 上界的越界情形
	var mem := CardMemory.new(2)
	mem.record_trick(_plays(0, [Card.normal(S.CLUB, R.ACE), Card.normal(S.CLUB, R.ACE)]))

	# Act + Assert — 2 份已出 + own_known=1 = 3 > 上界 2，clamp 到 0 不为负
	assert_eq(mem.remaining_copies(S.CLUB, R.ACE, 1), 0, "越界时 clamp 到 0，不返回负数")


func test_card_memory_joker_tally_and_remaining() -> void:
	# Arrange
	var mem := CardMemory.new(2)

	# Act — 出一张大王
	mem.record_trick(_plays(0, [Card.joker(J.BIG)]))

	# Assert — 大王 -1，小王不受影响
	assert_eq(mem.remaining_joker_copies(J.BIG, 0), 1, "出 1 张大王后剩 1 份")
	assert_eq(mem.remaining_joker_copies(J.SMALL, 0), 2, "小王未出仍剩 2 份")


func test_card_memory_begin_trick_clears_current_trick() -> void:
	# Arrange — 当前墩记了两条出牌
	var mem := CardMemory.new(2)
	mem.record_play({"seat_id": 0, "cards": [Card.normal(S.SPADE, R.THREE)], "play_order": 0})
	mem.record_play({"seat_id": 1, "cards": [Card.normal(S.SPADE, R.SEVEN)], "play_order": 1})
	assert_eq(mem.current_trick.size(), 2, "当前墩已记 2 条")

	# Act — 开新墩
	mem.begin_trick()

	# Assert — 当前墩清空（跨墩累积 played_count 不受影响）
	assert_eq(mem.current_trick.size(), 0, "begin_trick 清空当前墩记录")


func test_card_memory_record_trick_multi_seat_entry() -> void:
	# Arrange — 一墩四家出牌（record_trick 遍历所有 entry）
	var mem := CardMemory.new(2)
	var plays := [
		{"seat": 0, "cards": [Card.normal(S.SPADE, R.FIVE)]},
		{"seat": 1, "cards": [Card.normal(S.SPADE, R.FIVE)]},
		{"seat": 2, "cards": [Card.normal(S.HEART, R.TEN)]},
		{"seat": 3, "cards": [Card.joker(J.SMALL)]},
	]

	# Act
	mem.record_trick(plays)

	# Assert — 两张 ♠5 累加到 2；♥10 计 1；小王计 1
	assert_eq(mem.played_copies(S.SPADE, R.FIVE), 2, "四家里两张 ♠5 累加")
	assert_eq(mem.played_copies(S.HEART, R.TEN), 1, "♥10 计 1")
	assert_eq(mem.remaining_joker_copies(J.SMALL, 0), 1, "小王计 1，剩 1")
