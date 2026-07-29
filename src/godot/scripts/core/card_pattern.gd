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
	# 四张王（大王对 + 小王对）视为拖拉机，扣底 ×4。
	#
	# 大小王在主牌域排序上紧邻（小王 140 / 大王 150），是主牌域最强的两个对子，
	# 按常见双升玩法视为连对。恒定生效，不受 four_same_is_tractor 控制——
	# 后者管的是级牌，两者是不同的规则。
	if cards.size() == 4 and _is_four_jokers(cards):
		var r := PatternResult.new(Card.CardType.TRACTOR, 4)
		r.pair_count = 2
		return r

	# four_same_is_tractor：四张同点数，如 ♠5♠5♥5♥5（两个同点数的对子）。
	#
	# 注意不是"四张完全相同的牌"：2 副牌下同一张牌最多 2 份，
	# ♠5♠5♠5♠5 需要 4 副牌，而 RuleConfig.validate() 限制 deck_count ∈ {1,2}。
	# 该规则实际只对**四张级牌**生效——非级牌的同点数 4 张必然跨花色域
	# （♠5 主 / ♥5 副），首出会被 PlayValidator._same_domain 拒绝。
	if four_same_is_tractor and cards.size() == 4 and _is_four_same_rank(cards):
		var r := PatternResult.new(Card.CardType.TRACTOR, 4)
		r.pair_count = 2
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


## 牌的等价键 —— 与 Card.equals 一致（忽略 deck_id）。
static func _identity_key(card: Card) -> String:
	if card.is_joker:
		return "joker_%d" % card.joker_type
	return "%d_%d" % [card.suit, card.rank]


## 四张王：大王 2 张 + 小王 2 张（1 副牌下凑不出，自然不触发）。
static func _is_four_jokers(cards: Array) -> bool:
	if cards.size() != 4:
		return false
	var small := 0
	var big := 0
	for c: Card in cards:
		if not c.is_joker:
			return false
		if c.joker_type == Card.JokerType.SMALL:
			small += 1
		else:
			big += 1
	return small == 2 and big == 2


## 四张同点数：4 张 rank 相同，且能配成两个对子。
## ♠5♠5♥5♥5 ✓（两个对子）；♠5♥5♦5♣5 ✗（每种花色仅 1 张，配不成对）。
static func _is_four_same_rank(cards: Array) -> bool:
	if cards.size() != 4 or cards[0].is_joker:
		return false
	var rank: int = cards[0].rank
	var id_counts: Dictionary = {}
	for c: Card in cards:
		if c.is_joker or c.rank != rank:
			return false
		var key := _identity_key(c)
		id_counts[key] = id_counts.get(key, 0) + 1
	for key: String in id_counts:
		if id_counts[key] % 2 != 0:
			return false
	return true


## Extract ranks that appear as pairs. Returns sorted array of ranks.
##
## 对子必须是"同花色同点数"（GDD card-types.md §2.1：2 张 suit 和 rank
## 完全相同的牌），因此按 identity 而非 rank 统计——♠5♥5 不是对子，
## 不能拿去凑拖拉机。
static func _extract_pair_ranks(cards: Array) -> Array[int]:
	var id_counts: Dictionary = {}
	var id_rank: Dictionary = {}
	for c: Card in cards:
		if c.is_joker:
			return []  # Jokers don't participate in tractors
		var key := _identity_key(c)
		id_counts[key] = id_counts.get(key, 0) + 1
		id_rank[key] = c.rank

	# Extract ranks with count >= 2
	var result: Array[int] = []
	for key: String in id_counts:
		var count: int = id_counts[key]
		while count >= 2:
			result.append(id_rank[key])
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
			# Remove these pairs from remaining。按 identity 移除，
			# 否则会把 ♠5♥5 这种"同点数不同花色"错当成一个对子拆掉。
			for rank: int in window:
				var target_key := ""
				var counts: Dictionary = {}
				for c: Card in remaining:
					if c.is_joker or c.rank != rank:
						continue
					var k := _identity_key(c)
					counts[k] = counts.get(k, 0) + 1
				for k: String in counts:
					if counts[k] >= 2:
						target_key = k
						break
				if target_key == "":
					return null
				var removed := 0
				var idx := 0
				while idx < remaining.size() and removed < 2:
					if not remaining[idx].is_joker and _identity_key(remaining[idx]) == target_key:
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
## 同样按 identity 统计——理由见 _extract_pair_ranks。
static func _extract_pair_ranks_from(cards: Array) -> Array[int]:
	var id_counts: Dictionary = {}
	var id_rank: Dictionary = {}
	for c: Card in cards:
		if c.is_joker:
			continue
		var key := _identity_key(c)
		id_counts[key] = id_counts.get(key, 0) + 1
		id_rank[key] = c.rank
	var result: Array[int] = []
	for key: String in id_counts:
		if id_counts[key] >= 2:
			result.append(id_rank[key])
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
