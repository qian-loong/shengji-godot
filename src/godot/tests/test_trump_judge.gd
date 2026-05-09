## Unit tests for TrumpJudge (S1-06)
## Validates: C1 trump-determination.md AC1-AC11
extends GutTest

# Shortcuts
const S = Card.Suit
const R = Card.Rank
const J = Card.JokerType
const D = TrumpJudge.DomainType


func test_trump_suit_card() -> void:
	# AC1: trump_suit=♠, rank=4, input ♠7 → Trump
	var c := Card.normal(S.SPADE, R.SEVEN)
	var dom := TrumpJudge.get_suit_domain(c, S.SPADE, R.FOUR, true)
	assert_eq(dom["type"], D.TRUMP)


func test_side_suit_card() -> void:
	# AC2: trump_suit=♠, rank=4, input ♥7 → Side(♥)
	var c := Card.normal(S.HEART, R.SEVEN)
	var dom := TrumpJudge.get_suit_domain(c, S.SPADE, R.FOUR, true)
	assert_eq(dom["type"], D.SIDE)
	assert_eq(dom["suit"], S.HEART)


func test_off_suit_rank_card_is_trump() -> void:
	# AC3: trump_suit=♠, rank=4, input ♥4 → Trump (rank card)
	var c := Card.normal(S.HEART, R.FOUR)
	var dom := TrumpJudge.get_suit_domain(c, S.SPADE, R.FOUR, true)
	assert_eq(dom["type"], D.TRUMP)


func test_trump_suit_rank_card() -> void:
	# AC4: trump_suit=♠, rank=4, input ♠4 → Trump
	var c := Card.normal(S.SPADE, R.FOUR)
	var dom := TrumpJudge.get_suit_domain(c, S.SPADE, R.FOUR, true)
	assert_eq(dom["type"], D.TRUMP)


func test_big_joker_is_trump() -> void:
	# AC5: BigJoker → Trump
	var c := Card.joker(J.BIG)
	var dom := TrumpJudge.get_suit_domain(c, S.SPADE, R.FOUR, true)
	assert_eq(dom["type"], D.TRUMP)


func test_joker_always_trump_no_trump_game() -> void:
	# AC6: no trump suit, joker_always_trump=true → Trump
	var c := Card.joker(J.BIG)
	var dom := TrumpJudge.get_suit_domain(c, -1, R.FOUR, true)
	assert_eq(dom["type"], D.TRUMP)


func test_joker_not_trump_no_trump_game() -> void:
	# AC7: no trump suit, joker_always_trump=false → None
	var c := Card.joker(J.BIG)
	var dom := TrumpJudge.get_suit_domain(c, -1, R.FOUR, false)
	assert_eq(dom["type"], D.NONE)


func test_sort_skip_sequence() -> void:
	# AC8: ♠3 < ♠5 when rank=4 (skip 4)
	var c3 := Card.normal(S.SPADE, R.THREE)
	var c5 := Card.normal(S.SPADE, R.FIVE)
	var v3 := TrumpJudge.get_sort_value(c3, S.SPADE, R.FOUR, true)
	var v5 := TrumpJudge.get_sort_value(c5, S.SPADE, R.FOUR, true)
	assert_true(v3 < v5, "♠3 sort < ♠5 sort when rank=4")


func test_sort_full_trump_order() -> void:
	# AC9: ♠A < ♥4 < ♠4 < SmallJoker < BigJoker (trump=♠, rank=4)
	var sa := Card.normal(S.SPADE, R.ACE)
	var h4 := Card.normal(S.HEART, R.FOUR)
	var s4 := Card.normal(S.SPADE, R.FOUR)
	var sj := Card.joker(J.SMALL)
	var bj := Card.joker(J.BIG)

	var v_sa := TrumpJudge.get_sort_value(sa, S.SPADE, R.FOUR, true)
	var v_h4 := TrumpJudge.get_sort_value(h4, S.SPADE, R.FOUR, true)
	var v_s4 := TrumpJudge.get_sort_value(s4, S.SPADE, R.FOUR, true)
	var v_sj := TrumpJudge.get_sort_value(sj, S.SPADE, R.FOUR, true)
	var v_bj := TrumpJudge.get_sort_value(bj, S.SPADE, R.FOUR, true)

	assert_true(v_sa < v_h4, "♠A < ♥4")
	assert_true(v_h4 < v_s4, "♥4 < ♠4")
	assert_true(v_s4 < v_sj, "♠4 < SmallJoker")
	assert_true(v_sj < v_bj, "SmallJoker < BigJoker")


func test_sort_off_suit_rank_cards_equal() -> void:
	# AC10: ♥4 == ♦4 == ♣4 (off-suit rank cards same level)
	var h4 := Card.normal(S.HEART, R.FOUR)
	var d4 := Card.normal(S.DIAMOND, R.FOUR)
	var c4 := Card.normal(S.CLUB, R.FOUR)
	var v_h4 := TrumpJudge.get_sort_value(h4, S.SPADE, R.FOUR, true)
	var v_d4 := TrumpJudge.get_sort_value(d4, S.SPADE, R.FOUR, true)
	var v_c4 := TrumpJudge.get_sort_value(c4, S.SPADE, R.FOUR, true)
	assert_eq(v_h4, v_d4, "♥4 == ♦4")
	assert_eq(v_d4, v_c4, "♦4 == ♣4")


func test_is_trump_helper() -> void:
	assert_true(TrumpJudge.is_trump(Card.normal(S.SPADE, R.SEVEN), S.SPADE, R.FOUR, true))
	assert_true(TrumpJudge.is_trump(Card.normal(S.HEART, R.FOUR), S.SPADE, R.FOUR, true))
	assert_true(TrumpJudge.is_trump(Card.joker(J.BIG), S.SPADE, R.FOUR, true))
	assert_false(TrumpJudge.is_trump(Card.normal(S.HEART, R.SEVEN), S.SPADE, R.FOUR, true))
