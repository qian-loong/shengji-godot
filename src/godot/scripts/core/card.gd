## Card data structures for 双升对局
## Implements: F1 Card Types GDD (design/gdd/card-types.md)
##
## Pure data layer — no game logic. Defines:
## - Suit, Rank, Joker enums
## - Card class (immutable value object)
## - CardType enum
## - SuitDomain interface
class_name Card
extends RefCounted


# ============================================================
# Enums
# ============================================================

enum Suit {
	SPADE,    # ♠ Black
	HEART,    # ♥ Red
	DIAMOND,  # ♦ Red
	CLUB,     # ♣ Black
}

enum CardColor {
	BLACK,
	RED,
}

enum Rank {
	TWO = 2,
	THREE = 3,
	FOUR = 4,
	FIVE = 5,
	SIX = 6,
	SEVEN = 7,
	EIGHT = 8,
	NINE = 9,
	TEN = 10,
	JACK = 11,
	QUEEN = 12,
	KING = 13,
	ACE = 14,
}

enum JokerType {
	SMALL,  # 黑王 (Black)
	BIG,    # 红王 (Red)
}

enum CardType {
	SINGLE,
	PAIR,
	TRACTOR,
	DUMP,
}


# ============================================================
# Constants
# ============================================================

## Ordered rank sequence (smallest to largest)
const RANK_SEQUENCE: Array[int] = [
	Rank.TWO, Rank.THREE, Rank.FOUR, Rank.FIVE, Rank.SIX,
	Rank.SEVEN, Rank.EIGHT, Rank.NINE, Rank.TEN,
	Rank.JACK, Rank.QUEEN, Rank.KING, Rank.ACE,
]

## Point values for scoring (F1 Formulas)
const RANK_POINTS: Dictionary = {
	Rank.FIVE: 5,
	Rank.TEN: 10,
	Rank.KING: 10,
}


# ============================================================
# Static helpers — Suit / Color
# ============================================================

static func suit_color(suit: Suit) -> CardColor:
	match suit:
		Suit.HEART, Suit.DIAMOND:
			return CardColor.RED
		_:
			return CardColor.BLACK


static func joker_color(joker_type: JokerType) -> CardColor:
	match joker_type:
		JokerType.BIG:
			return CardColor.RED
		_:
			return CardColor.BLACK


static func suit_symbol(suit: Suit) -> String:
	match suit:
		Suit.SPADE:   return "♠"
		Suit.HEART:   return "♥"
		Suit.DIAMOND: return "♦"
		Suit.CLUB:    return "♣"
		_:            return "?"


static func rank_symbol(rank: Rank) -> String:
	match rank:
		Rank.JACK:  return "J"
		Rank.QUEEN: return "Q"
		Rank.KING:  return "K"
		Rank.ACE:   return "A"
		_:          return str(rank)


static func joker_symbol(joker_type: JokerType) -> String:
	match joker_type:
		JokerType.BIG:   return "RedJoker"
		JokerType.SMALL: return "BlackJoker"
		_:               return "Joker"


# ============================================================
# Static helpers — Point value
# ============================================================

static func card_point_value(rank: Rank) -> int:
	return RANK_POINTS.get(rank, 0)


# ============================================================
# Static helpers — Skip sequence & adjacency (F1 Formulas)
# ============================================================

## Returns rank sequence with current_rank removed
static func get_skip_sequence(current_rank: Rank) -> Array[int]:
	var result: Array[int] = []
	for r: int in RANK_SEQUENCE:
		if r != current_rank:
			result.append(r)
	return result


## Check if two ranks are adjacent (either in base or skip sequence)
static func is_adjacent(rank_a: Rank, rank_b: Rank, current_rank: Rank) -> bool:
	# Check base sequence adjacency (rank card participates in tractor)
	var base_idx_a := RANK_SEQUENCE.find(rank_a)
	var base_idx_b := RANK_SEQUENCE.find(rank_b)
	if base_idx_a >= 0 and base_idx_b >= 0 and absi(base_idx_a - base_idx_b) == 1:
		return true

	# Check skip sequence adjacency (rank card skipped)
	var skip_seq := get_skip_sequence(current_rank)
	var skip_idx_a := skip_seq.find(rank_a)
	var skip_idx_b := skip_seq.find(rank_b)
	if skip_idx_a >= 0 and skip_idx_b >= 0 and absi(skip_idx_a - skip_idx_b) == 1:
		return true

	return false


# ============================================================
# Card instance properties
# ============================================================

## True if this is a joker card, false if normal card
var is_joker: bool

## Normal card properties (valid when is_joker == false)
var suit: Suit
var rank: Rank

## Joker card property (valid when is_joker == true)
var joker_type: JokerType

## Deck identifier (0 or 1), debug/render only, ignored in equality
var deck_id: int


# ============================================================
# Constructors (static factory methods)
# ============================================================

static func normal(p_suit: Suit, p_rank: Rank, p_deck_id: int = 0) -> Card:
	var card := Card.new()
	card.is_joker = false
	card.suit = p_suit
	card.rank = p_rank
	card.deck_id = p_deck_id
	return card


static func joker(p_joker_type: JokerType, p_deck_id: int = 0) -> Card:
	var card := Card.new()
	card.is_joker = true
	card.joker_type = p_joker_type
	card.deck_id = p_deck_id
	return card


# ============================================================
# Equality (ignores deck_id per F1 spec)
# ============================================================

func equals(other: Card) -> bool:
	if is_joker != other.is_joker:
		return false
	if is_joker:
		return joker_type == other.joker_type
	return suit == other.suit and rank == other.rank


# ============================================================
# Display
# ============================================================

func to_string_repr() -> String:
	if is_joker:
		return joker_symbol(joker_type)
	return suit_symbol(suit) + rank_symbol(rank)


func get_color() -> CardColor:
	if is_joker:
		return joker_color(joker_type)
	return suit_color(suit)


func get_point_value() -> int:
	if is_joker:
		return 0
	return card_point_value(rank)
