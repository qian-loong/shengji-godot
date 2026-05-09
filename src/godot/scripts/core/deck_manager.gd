## Deck management — generation, shuffle, deal
## Implements: F2 Deck Management GDD (design/gdd/deck-management.md)
class_name DeckManager
extends RefCounted


# ============================================================
# Deck generation
# ============================================================

## Generate a full deck of cards
static func generate_deck(deck_count: int) -> Array[Card]:
	var cards: Array[Card] = []
	for d: int in range(deck_count):
		# Normal cards: 4 suits × 13 ranks
		for suit: int in [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.DIAMOND, Card.Suit.CLUB]:
			for rank: int in Card.RANK_SEQUENCE:
				cards.append(Card.normal(suit, rank, d))
		# Jokers
		cards.append(Card.joker(Card.JokerType.SMALL, d))
		cards.append(Card.joker(Card.JokerType.BIG, d))
	return cards


# ============================================================
# Shuffle (Fisher-Yates)
# ============================================================

## Shuffle cards in-place using Fisher-Yates algorithm
static func shuffle(cards: Array[Card], seed_value: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	var n := cards.size()
	for i: int in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


# ============================================================
# Deal
# ============================================================

## Deal cards to 4 players + bottom
## Returns: { "hands": Array[Array[Card]], "bottom": Array[Card] }
static func deal(cards: Array[Card], hand_size: int, bottom_size: int) -> Dictionary:
	var hands: Array[Array] = [[], [], [], []]
	var card_idx: int = 0

	# Deal hand_size cards to each player in round-robin
	for _round: int in range(hand_size):
		for seat: int in range(4):
			hands[seat].append(cards[card_idx])
			card_idx += 1

	# Remaining cards are bottom
	var bottom: Array[Card] = []
	while card_idx < cards.size():
		bottom.append(cards[card_idx])
		card_idx += 1

	assert(bottom.size() == bottom_size, "Bottom size mismatch: got %d, expected %d" % [bottom.size(), bottom_size])

	return { "hands": hands, "bottom": bottom }
