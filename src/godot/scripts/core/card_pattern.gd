## Card pattern recognition — identify card types from a set of cards
## Implements: F1 Card Types GDD §2 (CardType identification)
##
## Pure functions: input cards + context → output CardType
## Does NOT validate legality (that's C2's job)
class_name CardPattern
extends RefCounted


# ============================================================
# Pattern result
# ============================================================

## Result of pattern recognition
## type: Card.CardType
## pairs: Array of pair ranks (for Tractor/Dump analysis)
## components: Array of sub-patterns (for Dump decomposition)
class PatternResult:
	var type: Card.CardType
	var card_count: int
	var pairs: Array[int]  # ranks of pairs found
	var pair_count: int
	var components: Array  # Array of PatternResult for Dump

	func _init(p_type: Card.CardType, p_count: int) -> void:
		type = p_type
		card_count = p_count
		pairs = []
		pair_count = 0
		components = []


# ============================================================
# Pattern identification
# ============================================================

## Identify the pattern type of a group of cards
## All cards must be in the same suit domain (caller's responsibility)
## Returns null if cards don't form a valid pattern
static func identify(cards: Array, current_rank: int, tractor_allow_rank_card: bool, four_same_is_tractor: bool) -> PatternResult:
	if cards.is_empty():
		return null

	if cards.size() == 1:
		var r := PatternResult.new(Card.CardType.SINGLE, 1)
		return r

	if cards.size() == 2:
		if _is_pair(cards[0], cards[1]):
			var r := PatternResult.new(Card.CardType.PAIR, 2)
			r.pair_count = 1
			if not cards[0].is_joker:
				r.pairs = [cards[0].rank]
			return r

	# Try tractor
	var tractor_result := _try_tractor(cards, current_rank, tractor_allow_rank_card, four_same_is_tractor)
	if tractor_result != null:
		return tractor_result

	# Try dump (2+ cards, mixed singles/pairs/tractors)
	if cards.size() >= 2:
		var dump_result := _try_dump(cards, current_rank, tractor_allow_rank_card, four_same_is_tractor)
		if dump_result != null:
			return dump_result

	return null


# ============================================================
# Pair check
# ============================================================

static func _is_pair(a: Card, b: Card) -> bool:
	return a.equals(b)


# ============================================================
# Tractor detection
# ============================================================

## Try to identify cards as a tractor (≥2 consecutive pairs)
static func _try_tractor(cards: Array, current_rank: int, tractor_allow_rank_card: bool, four_same_is_tractor: bool) -> PatternResult:
	# Special case: four_same_is_tractor with exactly 4 identical cards
	if four_same_is_tractor and cards.size() == 4 and _all_same(cards):
		var r := PatternResult.new(Card.CardType.TRACTOR, 4)
		r.pair_count = 2
		if not cards[0].is_joker:
			r.pairs = [cards[0].rank, cards[0].rank]
		return r

	if cards.size() < 4 or cards.size() % 2 != 0:
		return null

	# Group into pairs by rank
	var pair_ranks := _extract_pair_ranks(cards)
	if pair_ranks.is_empty():
		return null

	# Need at least 2 pairs
	if pair_ranks.size() < 2:
		return null

	# All cards must be accounted for as pairs
	if pair_ranks.size() * 2 != cards.size():
		return null

	# Filter out rank card if not allowed
	if not tractor_allow_rank_card:
		for pr: int in pair_ranks:
			if pr == current_rank:
				return null

	# Check consecutive in either base or skip sequence
	if _are_consecutive(pair_ranks, current_rank):
		var r := PatternResult.new(Card.CardType.TRACTOR, cards.size())
		r.pairs = pair_ranks
		r.pair_count = pair_ranks.size()
		return r

	return null


## Check if all cards are identical
static func _all_same(cards: Array) -> bool:
	for i: int in range(1, cards.size()):
		if not cards[i].equals(cards[0]):
			return false
	return true


## Extract ranks that appear as pairs. Returns sorted array of ranks.
## Only works for normal cards (not jokers in pairs).
static func _extract_pair_ranks(cards: Array) -> Array[int]:
	# Count occurrences of each rank
	var rank_counts: Dictionary = {}
	for c: Card in cards:
		if c.is_joker:
			return []  # Jokers don't participate in tractors
		var key: int = c.rank
		rank_counts[key] = rank_counts.get(key, 0) + 1

	# Extract ranks with count >= 2
	var result: Array[int] = []
	for rank: int in rank_counts:
		var count: int = rank_counts[rank]
		while count >= 2:
			result.append(rank)
			count -= 2

	# Sort by base sequence position
	result.sort_custom(func(a: int, b: int) -> bool:
		return Card.RANK_SEQUENCE.find(a) < Card.RANK_SEQUENCE.find(b)
	)
	return result


## Check if ranks are consecutive in base or skip sequence
static func _are_consecutive(ranks: Array[int], current_rank: int) -> bool:
	if ranks.size() < 2:
		return true

	# Sort by base sequence
	var sorted_ranks := ranks.duplicate()
	sorted_ranks.sort_custom(func(a: int, b: int) -> bool:
		return Card.RANK_SEQUENCE.find(a) < Card.RANK_SEQUENCE.find(b)
	)

	# Check: all adjacent pairs must be adjacent
	for i: int in range(sorted_ranks.size() - 1):
		if not Card.is_adjacent(sorted_ranks[i], sorted_ranks[i + 1], current_rank):
			return false
	return true


# ============================================================
# Dump decomposition (greedy: tractor > pair > single)
# ============================================================

## Try to decompose cards into a valid dump (mixed singles/pairs/tractors)
static func _try_dump(cards: Array, current_rank: int, tractor_allow_rank_card: bool, four_same_is_tractor: bool) -> PatternResult:
	if cards.size() < 2:
		return null

	var remaining := cards.duplicate()
	var components: Array = []

	# Phase 1: Extract tractors (greedy, longest first)
	var found_tractor := true
	while found_tractor:
		found_tractor = false
		# Try decreasing lengths
		var max_pairs := remaining.size() / 2
		for pair_count: int in range(max_pairs, 1, -1):
			var tractor := _find_and_remove_tractor(remaining, pair_count, current_rank, tractor_allow_rank_card, four_same_is_tractor)
			if tractor != null:
				components.append(tractor)
				found_tractor = true
				break

	# Phase 2: Extract pairs
	var found_pair := true
	while found_pair and remaining.size() >= 2:
		found_pair = false
		for i: int in range(remaining.size()):
			for j: int in range(i + 1, remaining.size()):
				if _is_pair(remaining[i], remaining[j]):
					var pair_cards: Array = [remaining[i], remaining[j]]
					var pr := PatternResult.new(Card.CardType.PAIR, 2)
					pr.pair_count = 1
					if not remaining[i].is_joker:
						pr.pairs = [remaining[i].rank]
					components.append(pr)
					remaining.remove_at(j)
					remaining.remove_at(i)
					found_pair = true
					break
			if found_pair:
				break

	# Phase 3: Remaining are singles
	for c: Card in remaining:
		components.append(PatternResult.new(Card.CardType.SINGLE, 1))

	# A dump must have multiple components
	if components.size() < 2:
		return null

	# If only singles, it's not a valid pattern (just random cards)
	var has_non_single := false
	for comp: PatternResult in components:
		if comp.type != Card.CardType.SINGLE:
			has_non_single = true
			break
	# Actually a dump CAN be all singles + pairs + any mix, as long as it's from same domain
	# The "validity" (all components are the biggest) is C2's responsibility

	var r := PatternResult.new(Card.CardType.DUMP, cards.size())
	r.components = components
	return r


## Find and remove a tractor of exactly pair_count pairs from remaining cards
static func _find_and_remove_tractor(remaining: Array, pair_count: int, current_rank: int, tractor_allow_rank_card: bool, four_same_is_tractor: bool) -> PatternResult:
	var pair_ranks := _extract_pair_ranks_from(remaining)
	if pair_ranks.size() < pair_count:
		return null

	# Sort pair ranks
	pair_ranks.sort_custom(func(a: int, b: int) -> bool:
		return Card.RANK_SEQUENCE.find(a) < Card.RANK_SEQUENCE.find(b)
	)

	# Try all windows of pair_count consecutive ranks
	for start: int in range(pair_ranks.size() - pair_count + 1):
		var window: Array[int] = []
		for k: int in range(pair_count):
			window.append(pair_ranks[start + k])

		if not tractor_allow_rank_card:
			var has_rank := false
			for wr: int in window:
				if wr == current_rank:
					has_rank = true
					break
			if has_rank:
				continue

		if _are_consecutive(window, current_rank):
			# Remove these pairs from remaining
			for rank: int in window:
				var removed := 0
				var idx := 0
				while idx < remaining.size() and removed < 2:
					if not remaining[idx].is_joker and remaining[idx].rank == rank:
						remaining.remove_at(idx)
						removed += 1
					else:
						idx += 1
			var r := PatternResult.new(Card.CardType.TRACTOR, pair_count * 2)
			r.pairs = window
			r.pair_count = pair_count
			return r

	return null


## Extract pair ranks from a subset of cards (doesn't modify input)
static func _extract_pair_ranks_from(cards: Array) -> Array[int]:
	var rank_counts: Dictionary = {}
	for c: Card in cards:
		if c.is_joker:
			continue
		rank_counts[c.rank] = rank_counts.get(c.rank, 0) + 1
	var result: Array[int] = []
	for rank: int in rank_counts:
		if rank_counts[rank] >= 2:
			result.append(rank)
	return result


# ============================================================
# Get bottom multiplier (F3 Formulas)
# ============================================================

## Calculate bottom score multiplier based on last trick's card type
static func get_bottom_multiplier(pattern: PatternResult) -> int:
	if pattern == null:
		return 1

	match pattern.type:
		Card.CardType.SINGLE:
			return 1
		Card.CardType.PAIR:
			return 2
		Card.CardType.TRACTOR:
			return pattern.pair_count * 2
		Card.CardType.DUMP:
			# Take max multiplier from components
			var max_mult := 1
			for comp: PatternResult in pattern.components:
				var m := get_bottom_multiplier(comp)
				if m > max_mult:
					max_mult = m
			return max_mult
	return 1
