## Unit tests for Card data structure (S1-01)
## Validates: F1 card-types.md AC1-AC4
extends GutTest


# ============================================================
# AC1: Normal card creation
# ============================================================

func test_normal_card_creation() -> void:
	var c := Card.normal(Card.Suit.SPADE, Card.Rank.FIVE, 0)
	assert_false(c.is_joker, "should not be joker")
	assert_eq(c.suit, Card.Suit.SPADE, "suit should be SPADE")
	assert_eq(c.rank, Card.Rank.FIVE, "rank should be FIVE")
	assert_eq(c.deck_id, 0, "deck_id should be 0")


func test_joker_card_creation() -> void:
	var j := Card.joker(Card.JokerType.BIG, 1)
	assert_true(j.is_joker, "should be joker")
	assert_eq(j.joker_type, Card.JokerType.BIG, "should be BIG joker")
	assert_eq(j.deck_id, 1, "deck_id should be 1")


# ============================================================
# AC3: Equality ignores deck_id
# ============================================================

func test_equality_ignores_deck_id() -> void:
	var c1 := Card.normal(Card.Suit.SPADE, Card.Rank.FIVE, 0)
	var c2 := Card.normal(Card.Suit.SPADE, Card.Rank.FIVE, 1)
	assert_true(c1.equals(c2), "same suit+rank different deck_id should be equal")


func test_different_cards_not_equal() -> void:
	var c1 := Card.normal(Card.Suit.SPADE, Card.Rank.FIVE, 0)
	var c3 := Card.normal(Card.Suit.HEART, Card.Rank.FIVE, 0)
	assert_false(c1.equals(c3), "different suit should not be equal")


func test_joker_equality_ignores_deck_id() -> void:
	var j1 := Card.joker(Card.JokerType.SMALL, 0)
	var j2 := Card.joker(Card.JokerType.SMALL, 1)
	assert_true(j1.equals(j2), "same joker type different deck_id should be equal")


func test_joker_not_equal_to_normal() -> void:
	var c := Card.normal(Card.Suit.SPADE, Card.Rank.FIVE, 0)
	var j := Card.joker(Card.JokerType.SMALL, 0)
	assert_false(c.equals(j), "joker and normal should not be equal")


func test_different_jokers_not_equal() -> void:
	var j1 := Card.joker(Card.JokerType.SMALL, 0)
	var j2 := Card.joker(Card.JokerType.BIG, 0)
	assert_false(j1.equals(j2), "different joker types should not be equal")


# ============================================================
# AC4: Color derivation
# ============================================================

func test_suit_color() -> void:
	assert_eq(Card.suit_color(Card.Suit.SPADE), Card.CardColor.BLACK, "SPADE is BLACK")
	assert_eq(Card.suit_color(Card.Suit.HEART), Card.CardColor.RED, "HEART is RED")
	assert_eq(Card.suit_color(Card.Suit.DIAMOND), Card.CardColor.RED, "DIAMOND is RED")
	assert_eq(Card.suit_color(Card.Suit.CLUB), Card.CardColor.BLACK, "CLUB is BLACK")


func test_joker_color() -> void:
	assert_eq(Card.joker_color(Card.JokerType.BIG), Card.CardColor.RED, "BigJoker is RED")
	assert_eq(Card.joker_color(Card.JokerType.SMALL), Card.CardColor.BLACK, "SmallJoker is BLACK")


# ============================================================
# Point values
# ============================================================

func test_point_values() -> void:
	assert_eq(Card.card_point_value(Card.Rank.FIVE), 5, "5 = 5 points")
	assert_eq(Card.card_point_value(Card.Rank.TEN), 10, "10 = 10 points")
	assert_eq(Card.card_point_value(Card.Rank.KING), 10, "K = 10 points")
	assert_eq(Card.card_point_value(Card.Rank.ACE), 0, "A = 0 points")
	assert_eq(Card.card_point_value(Card.Rank.THREE), 0, "3 = 0 points")


func test_instance_point_value() -> void:
	var c := Card.normal(Card.Suit.SPADE, Card.Rank.FIVE, 0)
	assert_eq(c.get_point_value(), 5, "♠5 points = 5")
	var j := Card.joker(Card.JokerType.BIG, 0)
	assert_eq(j.get_point_value(), 0, "joker points = 0")


# ============================================================
# Display
# ============================================================

func test_to_string_repr() -> void:
	var c := Card.normal(Card.Suit.SPADE, Card.Rank.FIVE, 0)
	assert_eq(c.to_string_repr(), "♠5", "should be ♠5")
	var j := Card.joker(Card.JokerType.BIG, 0)
	assert_eq(j.to_string_repr(), "RedJoker", "should be RedJoker")
	var c2 := Card.normal(Card.Suit.HEART, Card.Rank.ACE, 0)
	assert_eq(c2.to_string_repr(), "♥A", "should be ♥A")


func test_instance_get_color() -> void:
	var c := Card.normal(Card.Suit.SPADE, Card.Rank.FIVE, 0)
	assert_eq(c.get_color(), Card.CardColor.BLACK, "♠5 color is BLACK")
	var j := Card.joker(Card.JokerType.BIG, 0)
	assert_eq(j.get_color(), Card.CardColor.RED, "RedJoker color is RED")


# ============================================================
# Rank sequence constant
# ============================================================

func test_rank_sequence() -> void:
	assert_eq(Card.RANK_SEQUENCE.size(), 13, "should have 13 ranks")
	assert_eq(Card.RANK_SEQUENCE[0], Card.Rank.TWO, "first rank is TWO")
	assert_eq(Card.RANK_SEQUENCE[12], Card.Rank.ACE, "last rank is ACE")
