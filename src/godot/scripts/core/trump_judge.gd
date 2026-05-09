## Trump determination — suit domain classification and sort ordering
## Implements: C1 Trump Determination GDD (design/gdd/trump-determination.md)
class_name TrumpJudge
extends RefCounted


# ============================================================
# Suit Domain
# ============================================================

enum DomainType {
	TRUMP,     # TrumpDomain
	SIDE,      # SideDomain(suit)
	NONE,      # No domain (joker when not trump in no-trump game)
}


# ============================================================
# Domain classification (C1 §1)
# ============================================================

## Determine which domain a card belongs to
## Returns: { "type": DomainType, "suit": Card.Suit or -1 }
static func get_suit_domain(card: Card, trump_suit: int, current_rank: int, joker_always_trump: bool) -> Dictionary:
	# Priority 1-3: Joker handling
	if card.is_joker:
		if joker_always_trump:
			return { "type": DomainType.TRUMP, "suit": -1 }
		elif trump_suit < 0:  # No trump game + joker not always trump
			return { "type": DomainType.NONE, "suit": -1 }
		else:
			return { "type": DomainType.TRUMP, "suit": -1 }

	# Priority 4: Rank card (always trump — 级牌永远算主)
	if card.rank == current_rank:
		return { "type": DomainType.TRUMP, "suit": -1 }

	# Priority 5: Trump suit card
	if trump_suit >= 0 and card.suit == trump_suit:
		return { "type": DomainType.TRUMP, "suit": -1 }

	# Priority 6: Side suit
	return { "type": DomainType.SIDE, "suit": card.suit }


# ============================================================
# Sort value (C1 §2 Formulas)
# ============================================================

## Sort value layers:
##   0-99:   Side suits (4 groups of 0-12, each sorted by skip sequence)
##   100-112: Trump suit normal cards (by skip sequence)
##   120:    Off-suit rank cards (same level, first-play-wins)
##   130:    Trump suit rank card
##   140:    Small Joker
##   150:    Big Joker

static func get_sort_value(card: Card, trump_suit: int, current_rank: int, joker_always_trump: bool) -> int:
	var domain := get_suit_domain(card, trump_suit, current_rank, joker_always_trump)

	# Joker
	if card.is_joker:
		if domain["type"] == DomainType.NONE:
			return -1  # No domain
		if card.joker_type == Card.JokerType.SMALL:
			return 140
		return 150

	# Trump domain normal card
	if domain["type"] == DomainType.TRUMP:
		# Rank card in trump suit
		if card.rank == current_rank and trump_suit >= 0 and card.suit == trump_suit:
			return 130
		# Rank card in off-suit (all equal)
		if card.rank == current_rank:
			return 120
		# Normal trump suit card — sorted by skip sequence position
		var skip_seq := Card.get_skip_sequence(current_rank)
		var idx := skip_seq.find(card.rank)
		if idx >= 0:
			return 100 + idx
		return 100  # fallback

	# Side domain
	var suit_offset: int = card.suit * 15  # 0, 15, 30, 45
	var skip_seq := Card.get_skip_sequence(current_rank)
	var idx := skip_seq.find(card.rank)
	if idx >= 0:
		return suit_offset + idx
	return suit_offset


# ============================================================
# Compare two cards in same domain
# ============================================================

## Compare sort values. Higher = stronger.
## For equal values (off-suit rank cards), first player wins — handled by caller.
static func compare_cards(card_a: Card, card_b: Card, trump_suit: int, current_rank: int, joker_always_trump: bool) -> int:
	var va := get_sort_value(card_a, trump_suit, current_rank, joker_always_trump)
	var vb := get_sort_value(card_b, trump_suit, current_rank, joker_always_trump)
	return va - vb


# ============================================================
# Check if card is in trump domain
# ============================================================

static func is_trump(card: Card, trump_suit: int, current_rank: int, joker_always_trump: bool) -> bool:
	var domain := get_suit_domain(card, trump_suit, current_rank, joker_always_trump)
	return domain["type"] == DomainType.TRUMP
