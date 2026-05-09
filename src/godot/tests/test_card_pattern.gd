## Unit tests for CardPattern (S1-03)
## Validates: F1 card-types.md AC9-AC14
extends GutTest

const S = Card.Suit
const R = Card.Rank
const J = Card.JokerType


func _card(suit: int, rank: int) -> Card:
	return Card.normal(suit, rank)


func _cards(defs: Array) -> Array:
	var result: Array = []
	for d: Array in defs:
		if d.size() == 2:
			result.append(Card.normal(d[0], d[1]))
		# For pairs in 2-deck, add twice
	return result


# ============================================================
# AC9: Tractor identification (rank=4, ♠3♠3♠5♠5)
# ============================================================

func test_tractor_skip_rank() -> void:
	# ♠3♠3♠5♠5 when rank=4 → Tractor (3→5 adjacent in skip sequence)
	var cards: Array = [
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.SPADE, R.THREE, 1),
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
	]
	var result := CardPattern.identify(cards, R.FOUR, true, false)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.TRACTOR)
	assert_eq(result.pair_count, 2)


# AC10: Tractor with rank card (♠3♠3♠4♠4 when rank=4)
func test_tractor_with_rank_card() -> void:
	var cards: Array = [
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.SPADE, R.THREE, 1),
		Card.normal(S.SPADE, R.FOUR, 0), Card.normal(S.SPADE, R.FOUR, 1),
	]
	var result := CardPattern.identify(cards, R.FOUR, true, false)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.TRACTOR)


# Tractor with rank card disabled
func test_tractor_rank_card_disabled() -> void:
	var cards: Array = [
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.SPADE, R.THREE, 1),
		Card.normal(S.SPADE, R.FOUR, 0), Card.normal(S.SPADE, R.FOUR, 1),
	]
	var result := CardPattern.identify(cards, R.FOUR, false, false)
	# Should NOT be tractor (rank card not allowed)
	if result != null:
		assert_ne(result.type, Card.CardType.TRACTOR, "should not be tractor when rank card disabled")


# AC11: Tractor ordering 3344 < 3355 < 4455 < 5566
func test_tractor_ordering() -> void:
	# We test by comparing the max pair rank
	var t3344 := CardPattern.identify([
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.SPADE, R.THREE, 1),
		Card.normal(S.SPADE, R.FOUR, 0), Card.normal(S.SPADE, R.FOUR, 1),
	], R.FOUR, true, false)

	var t3355 := CardPattern.identify([
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.SPADE, R.THREE, 1),
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
	], R.FOUR, true, false)

	var t4455 := CardPattern.identify([
		Card.normal(S.SPADE, R.FOUR, 0), Card.normal(S.SPADE, R.FOUR, 1),
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
	], R.FOUR, true, false)

	var t5566 := CardPattern.identify([
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
		Card.normal(S.SPADE, R.SIX, 0), Card.normal(S.SPADE, R.SIX, 1),
	], R.FOUR, true, false)

	assert_not_null(t3344)
	assert_not_null(t3355)
	assert_not_null(t4455)
	assert_not_null(t5566)

	# Compare by max pair rank, then min pair rank for tiebreaker
	var max_3344: int = t3344.pairs.max()
	var max_3355: int = t3355.pairs.max()
	var max_4455: int = t4455.pairs.max()
	var max_5566: int = t5566.pairs.max()
	var min_3344: int = t3344.pairs.min()
	var min_3355: int = t3355.pairs.min()
	var min_4455: int = t4455.pairs.min()
	assert_true(max_3344 < max_3355, "3344 < 3355 (max rank)")
	# 3355 and 4455 have same max (5), compare min: 3 < 4
	assert_true(min_3355 < min_4455, "3355 < 4455 (min rank tiebreaker)")
	assert_true(max_4455 < max_5566, "4455 < 5566")


# Single and Pair
func test_single() -> void:
	var cards: Array = [Card.normal(S.SPADE, R.ACE)]
	var result := CardPattern.identify(cards, R.FOUR, true, false)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.SINGLE)


func test_pair() -> void:
	var cards: Array = [
		Card.normal(S.SPADE, R.FIVE, 0),
		Card.normal(S.SPADE, R.FIVE, 1),
	]
	var result := CardPattern.identify(cards, R.FOUR, true, false)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.PAIR)


func test_joker_pair() -> void:
	var cards: Array = [
		Card.joker(J.BIG, 0),
		Card.joker(J.BIG, 1),
	]
	var result := CardPattern.identify(cards, R.FOUR, true, false)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.PAIR)


func test_not_pair_different_cards() -> void:
	var cards: Array = [
		Card.normal(S.SPADE, R.FIVE, 0),
		Card.normal(S.SPADE, R.SIX, 0),
	]
	var result := CardPattern.identify(cards, R.FOUR, true, false)
	# Should be dump or null, not pair
	if result != null:
		assert_ne(result.type, Card.CardType.PAIR)


# AC13: four_same_is_tractor = true
func test_four_same_is_tractor() -> void:
	var cards: Array = [
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
	]
	var result := CardPattern.identify(cards, R.FOUR, true, true)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.TRACTOR)


# AC14: four_same_is_tractor = false
func test_four_same_not_tractor() -> void:
	var cards: Array = [
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
	]
	var result := CardPattern.identify(cards, R.FOUR, true, false)
	# Should not be tractor
	if result != null:
		assert_ne(result.type, Card.CardType.TRACTOR, "4 same should not be tractor when disabled")


# Three-pair tractor
func test_three_pair_tractor() -> void:
	var cards: Array = [
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.SPADE, R.THREE, 1),
		Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1),
		Card.normal(S.SPADE, R.SIX, 0), Card.normal(S.SPADE, R.SIX, 1),
	]
	var result := CardPattern.identify(cards, R.FOUR, true, false)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.TRACTOR)
	assert_eq(result.pair_count, 3)


# Tractor when rank=2, 2233 valid
func test_tractor_rank_2() -> void:
	var cards: Array = [
		Card.normal(S.SPADE, R.TWO, 0), Card.normal(S.SPADE, R.TWO, 1),
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.SPADE, R.THREE, 1),
	]
	var result := CardPattern.identify(cards, R.TWO, true, false)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.TRACTOR)


# Bottom multiplier
func test_bottom_multiplier_single() -> void:
	var r := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	assert_eq(CardPattern.get_bottom_multiplier(r), 1)


func test_bottom_multiplier_pair() -> void:
	var r := CardPattern.PatternResult.new(Card.CardType.PAIR, 2)
	assert_eq(CardPattern.get_bottom_multiplier(r), 2)


func test_bottom_multiplier_tractor_2() -> void:
	var r := CardPattern.PatternResult.new(Card.CardType.TRACTOR, 4)
	r.pair_count = 2
	assert_eq(CardPattern.get_bottom_multiplier(r), 4)


func test_bottom_multiplier_tractor_3() -> void:
	var r := CardPattern.PatternResult.new(Card.CardType.TRACTOR, 6)
	r.pair_count = 3
	assert_eq(CardPattern.get_bottom_multiplier(r), 6)


func test_bottom_multiplier_dump_max_component() -> void:
	var dump := CardPattern.PatternResult.new(Card.CardType.DUMP, 5)
	var single := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var tractor := CardPattern.PatternResult.new(Card.CardType.TRACTOR, 4)
	tractor.pair_count = 2
	dump.components = [single, tractor]
	assert_eq(CardPattern.get_bottom_multiplier(dump), 4, "dump takes max component = tractor(4)")
