## AI basic decision — rule-correct AI for MVP
## Implements: FT1 AI Basic GDD (design/gdd/ai-basic.md)
class_name AIPlayer
extends RefCounted


# ============================================================
# Bid decision
# ============================================================

## Decide whether and what to bid
static func decide_bid(seat_id: int, hand: Array, current_rank: int, rule_config: RuleConfig) -> TrumpBidding.BidDeclaration:
	var bids := TrumpBidding.get_available_bids(seat_id, hand, current_rank, rule_config)
	if bids.is_empty():
		return null

	# Pick strongest available bid
	var best: TrumpBidding.BidDeclaration = bids[0]
	for i: int in range(1, bids.size()):
		if TrumpBidding.is_stronger(bids[i], best):
			best = bids[i]

	# Simple heuristic: only bid if we have decent trump potential
	# Count rank cards + jokers
	var trump_strength := 0
	for c: Card in hand:
		if c.is_joker:
			trump_strength += 3
		elif c.rank == current_rank:
			trump_strength += 2

	# Bid if strength >= 4 (at least a pair of rank cards or joker+rank)
	if trump_strength >= 4:
		return best
	# With lower strength, 30% chance to bid anyway
	if trump_strength >= 2 and randf() < 0.3:
		return best
	return null


# ============================================================
# Bury decision (when AI is dealer)
# ============================================================

## Select cards to bury. Returns array of indices into hand.
static func decide_bury(hand: Array, bottom_size: int, trump_suit: int, current_rank: int, rule_config: RuleConfig) -> Array[int]:
	var jat := rule_config.joker_always_trump

	# Score each card: lower score = more likely to bury
	var scores: Array[float] = []
	for c: Card in hand:
		var score := 0.0
		var is_trump := TrumpJudge.is_trump(c, trump_suit, current_rank, jat)

		# Keep trump cards (high score)
		if is_trump:
			score += 50.0
		# Keep point cards (moderate score, unless unprotected side suit)
		if c.get_point_value() > 0:
			score += 20.0
			if is_trump:
				score += 10.0  # Point cards in trump are safer

		# Prefer burying short side suits
		if not c.is_joker and not is_trump:
			var suit_count := _count_suit(hand, c.suit, trump_suit, current_rank, jat)
			# Fewer cards in suit = more valuable to bury (clear the suit)
			score += suit_count * 3.0

		# High rank side cards are somewhat valuable
		if not is_trump and not c.is_joker:
			var sort_val := TrumpJudge.get_sort_value(c, trump_suit, current_rank, jat)
			score += sort_val * 0.5

		scores.append(score)

	# Select bottom_size cards with lowest scores
	var indices: Array[int] = []
	for i: int in range(hand.size()):
		indices.append(i)

	indices.sort_custom(func(a: int, b: int) -> bool:
		return scores[a] < scores[b]
	)

	var result: Array[int] = []
	for i: int in range(bottom_size):
		result.append(indices[i])
	result.sort()  # Sort for cleaner output
	return result


# ============================================================
# Play decision
# ============================================================

## Decide which cards to play (lead or follow)
static func decide_play(seat_id: int, hand: Array, lead_info: Dictionary, game_state: Dictionary, rule_config: RuleConfig) -> Array:
	var trump_suit: int = game_state.get("trump_suit", -1)
	var current_rank: int = game_state.get("current_rank", Card.Rank.TWO)
	var jat: bool = rule_config.joker_always_trump

	if lead_info.is_empty():
		# We are leading
		return _decide_lead(hand, trump_suit, current_rank, rule_config)
	else:
		# We are following
		return _decide_follow(hand, lead_info, trump_suit, current_rank, rule_config)


# ============================================================
# Lead decision
# ============================================================

static func _decide_lead(hand: Array, trump_suit: int, current_rank: int, rc: RuleConfig) -> Array:
	var jat := rc.joker_always_trump

	# Count trump vs side
	var trump_cards: Array = []
	var side_suits: Dictionary = {}  # suit -> cards
	for c: Card in hand:
		if TrumpJudge.is_trump(c, trump_suit, current_rank, jat):
			trump_cards.append(c)
		elif not c.is_joker:
			if not side_suits.has(c.suit):
				side_suits[c.suit] = []
			side_suits[c.suit].append(c)

	# Strategy 1: If we have many trump, lead trump to clear
	if trump_cards.size() > hand.size() / 2 and not trump_cards.is_empty():
		# Lead smallest trump single
		trump_cards.sort_custom(func(a: Card, b: Card) -> bool:
			return TrumpJudge.get_sort_value(a, trump_suit, current_rank, jat) < TrumpJudge.get_sort_value(b, trump_suit, current_rank, jat)
		)
		return [trump_cards[0]]

	# Strategy 2: Lead from shortest side suit
	var shortest_suit: int = -1
	var shortest_len: int = 999
	for suit: int in side_suits:
		if side_suits[suit].size() < shortest_len:
			shortest_len = side_suits[suit].size()
			shortest_suit = suit

	if shortest_suit >= 0:
		var suit_cards: Array = side_suits[shortest_suit]
		suit_cards.sort_custom(func(a: Card, b: Card) -> bool:
			return TrumpJudge.get_sort_value(a, trump_suit, current_rank, jat) < TrumpJudge.get_sort_value(b, trump_suit, current_rank, jat)
		)
		return [suit_cards[0]]  # Lead smallest from shortest suit

	# Fallback: lead smallest card
	if not hand.is_empty():
		var sorted_hand := hand.duplicate()
		sorted_hand.sort_custom(func(a: Card, b: Card) -> bool:
			return TrumpJudge.get_sort_value(a, trump_suit, current_rank, jat) < TrumpJudge.get_sort_value(b, trump_suit, current_rank, jat)
		)
		return [sorted_hand[0]]

	return []


# ============================================================
# Follow decision
# ============================================================

static func _decide_follow(hand: Array, lead_info: Dictionary, trump_suit: int, current_rank: int, rc: RuleConfig) -> Array:
	var jat := rc.joker_always_trump
	var lead_domain: Dictionary = lead_info["domain"]
	var lead_count: int = lead_info["count"]
	var lead_pattern: CardPattern.PatternResult = lead_info.get("pattern")

	# Get cards in lead domain
	var domain_cards: Array = []
	var other_cards: Array = []
	for c: Card in hand:
		var dom := TrumpJudge.get_suit_domain(c, trump_suit, current_rank, jat)
		if _domains_eq(dom, lead_domain):
			domain_cards.append(c)
		else:
			other_cards.append(c)

	var result: Array = []

	if domain_cards.size() >= lead_count:
		# Have enough domain cards — must respect structure rules
		result = _pick_domain_follow(domain_cards, lead_count, lead_pattern, trump_suit, current_rank, rc)
	elif not domain_cards.is_empty():
		# Some domain cards — must play all, fill rest from other
		result.append_array(domain_cards)
		other_cards.sort_custom(func(a: Card, b: Card) -> bool:
			return TrumpJudge.get_sort_value(a, trump_suit, current_rank, jat) < TrumpJudge.get_sort_value(b, trump_suit, current_rank, jat)
		)
		var remaining := lead_count - domain_cards.size()
		for i: int in range(mini(remaining, other_cards.size())):
			result.append(other_cards[i])
	else:
		# No domain cards — free play, use smallest cards
		var all_sorted := hand.duplicate()
		all_sorted.sort_custom(func(a: Card, b: Card) -> bool:
			return TrumpJudge.get_sort_value(a, trump_suit, current_rank, jat) < TrumpJudge.get_sort_value(b, trump_suit, current_rank, jat)
		)
		for i: int in range(mini(lead_count, all_sorted.size())):
			result.append(all_sorted[i])

	return result


## Pick domain cards respecting structure rules (pair→must play pair, etc.)
## Strategy: play smallest legal combination (save big cards).
static func _pick_domain_follow(domain_cards: Array, lead_count: int, lead_pattern: CardPattern.PatternResult, trump_suit: int, current_rank: int, rc: RuleConfig) -> Array:
	var jat := rc.joker_always_trump

	# Group domain cards by card identity (suit+rank / joker_type) to find real pairs
	var by_id: Dictionary = {}  # card_id -> [Card, ...]
	for c: Card in domain_cards:
		var card_id: String
		if c.is_joker:
			card_id = "joker_%d" % c.joker_type
		else:
			card_id = "%d_%d" % [c.suit, c.rank]
		if not by_id.has(card_id):
			by_id[card_id] = []
		by_id[card_id].append(c)

	# Sort groups by sort_value (smallest first for "save big cards" strategy)
	var sorted_ids := by_id.keys()
	sorted_ids.sort_custom(func(a: String, b: String) -> bool:
		return TrumpJudge.get_sort_value(by_id[a][0], trump_suit, current_rank, jat) < TrumpJudge.get_sort_value(by_id[b][0], trump_suit, current_rank, jat)
	)

	var pairs: Array = []  # [[card, card], ...]
	var singles: Array = []  # [card, ...]
	for id: String in sorted_ids:
		var group: Array = by_id[id]
		while group.size() >= 2:
			pairs.append([group[0], group[1]])
			group = group.slice(2)
		for c: Card in group:
			singles.append(c)

	var result: Array = []

	if lead_pattern != null and rc.strict_follow_structure and lead_pattern.type == Card.CardType.PAIR:
		if not pairs.is_empty():
			# Must play a pair — pick smallest pair (strategy: save big)
			result.append_array(pairs[0])
			return result

	if lead_pattern != null and rc.strict_follow_structure and lead_pattern.type == Card.CardType.TRACTOR:
		# Must include as many pairs as possible, up to lead's pair_count
		var needed_pairs := mini(pairs.size(), lead_pattern.pair_count)
		for i: int in range(needed_pairs):
			result.append_array(pairs[i])
		# Fill remaining with singles
		var remaining := lead_count - result.size()
		for i: int in range(mini(remaining, singles.size())):
			result.append(singles[i])
		if result.size() >= lead_count:
			return result.slice(0, lead_count)

	# Default: play smallest cards
	domain_cards.sort_custom(func(a: Card, b: Card) -> bool:
		return TrumpJudge.get_sort_value(a, trump_suit, current_rank, jat) < TrumpJudge.get_sort_value(b, trump_suit, current_rank, jat)
	)
	result = []
	for i: int in range(lead_count):
		result.append(domain_cards[i])
	return result


# ============================================================
# Helpers
# ============================================================

static func _count_suit(hand: Array, suit: int, trump_suit: int, current_rank: int, jat: bool) -> int:
	var count := 0
	for c: Card in hand:
		if not c.is_joker and c.suit == suit and not TrumpJudge.is_trump(c, trump_suit, current_rank, jat):
			count += 1
	return count


static func _domains_eq(a: Dictionary, b: Dictionary) -> bool:
	if a["type"] != b["type"]:
		return false
	if a["type"] == TrumpJudge.DomainType.SIDE:
		return a["suit"] == b["suit"]
	return true
