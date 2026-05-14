## Play validation — lead/follow legality checks + trick winner
## Implements: C2 Play Validation GDD (design/gdd/play-validation.md)
class_name PlayValidator
extends RefCounted


# ============================================================
# Lead validation (C2 §1)
# ============================================================

## Validate a lead play. Returns PatternResult or null if invalid.
static func validate_lead(cards: Array, hand: Array, trump_suit: int, current_rank: int, rule_config: RuleConfig) -> CardPattern.PatternResult:
	# All cards must be in hand
	if not _all_in_hand(cards, hand):
		return null

	if cards.is_empty():
		return null

	# All cards must be in same suit domain
	if not _same_domain(cards, trump_suit, current_rank, rule_config.joker_always_trump):
		return null

	# Identify pattern
	var pattern := CardPattern.identify(cards, current_rank, rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
	if pattern == null:
		return null

	# Dump requires allow_dump
	if pattern.type == Card.CardType.DUMP and not rule_config.allow_dump:
		return null

	return pattern


# ============================================================
# Follow validation (C2 §2)
# ============================================================

## Validate a follow play. Returns true if legal.
## lead_pattern: the CardPattern.PatternResult of the lead play (null = skip structure check)
static func validate_follow(cards: Array, hand: Array, lead_count: int, lead_domain: Dictionary, trump_suit: int, current_rank: int, rule_config: RuleConfig, lead_pattern: CardPattern.PatternResult = null) -> bool:
	# Must play exact same number of cards
	if cards.size() != lead_count:
		return false

	# All cards must be in hand
	if not _all_in_hand(cards, hand):
		return false

	var jat := rule_config.joker_always_trump

	# Count how many cards of lead domain in hand
	var domain_cards_in_hand := _get_domain_cards(hand, lead_domain, trump_suit, current_rank, jat)

	# Get played cards that are in lead domain
	var played_domain_cards: Array = []
	for c: Card in cards:
		var dom := TrumpJudge.get_suit_domain(c, trump_suit, current_rank, jat)
		if _domains_equal(dom, lead_domain):
			played_domain_cards.append(c)

	# If hand has cards in lead domain, must play them first
	var required_domain_count := mini(domain_cards_in_hand.size(), lead_count)
	if played_domain_cards.size() < required_domain_count:
		return false

	# strict_follow_structure: must match lead pattern structure when possible
	if rule_config.strict_follow_structure and lead_pattern != null and played_domain_cards.size() >= lead_count:
		if not _check_follow_structure(played_domain_cards, domain_cards_in_hand, lead_pattern, trump_suit, current_rank, rule_config):
			return false

	return true


# ============================================================
# Trick winner determination (C2 §3)
# ============================================================

## Determine the winner of a trick
## plays: Array of { "seat": int, "cards": Array[Card], "pattern": PatternResult }
## lead_domain: suit domain of the lead play
## Returns winning seat_id
static func determine_winner(plays: Array, lead_domain: Dictionary, trump_suit: int, current_rank: int, rule_config: RuleConfig) -> int:
	var jat := rule_config.joker_always_trump
	var lead_pattern: CardPattern.PatternResult = plays[0]["pattern"]
	var lead_is_trump: bool = _domains_equal(lead_domain, {"type": TrumpJudge.DomainType.TRUMP, "suit": -1})

	var best_seat: int = plays[0]["seat"]
	var best_is_trump_kill: bool = false  # 是否有人用主牌杀（首出非主牌时）
	var best_value: int = _get_play_sort_value(plays[0]["cards"], trump_suit, current_rank, jat)

	for i: int in range(1, plays.size()):
		var play: Dictionary = plays[i]
		var play_cards: Array = play["cards"]
		var play_domain := _get_play_domain(play_cards, trump_suit, current_rank, jat)

		var play_is_trump: bool = (play_domain["type"] == TrumpJudge.DomainType.TRUMP)
		var is_same_domain: bool = _domains_equal(play_domain, lead_domain)

		if lead_is_trump:
			# 首出是主牌：跟牌必须同主牌域 + 同结构（对/拖拉机），否则视为垫牌
			if is_same_domain:
				var play_pattern := CardPattern.identify(play_cards, current_rank, rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
				if play_pattern == null or not _structure_matches(play_pattern, lead_pattern):
					continue  # 拆牌跟主：不构成同结构，不能赢
				var play_value := _get_play_sort_value(play_cards, trump_suit, current_rank, jat)
				if play_value > best_value:
					best_seat = play["seat"]
					best_value = play_value
			# 非主牌域的牌 = 垫牌，不参与比较

		elif play_is_trump and not is_same_domain:
			# 主牌杀（首出非主牌时，跟牌出主牌）
			var play_pattern := CardPattern.identify(play_cards, current_rank, rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
			if play_pattern == null or not _structure_matches(play_pattern, lead_pattern):
				continue  # 结构不匹配，无法赢墩

			var play_value := _get_play_sort_value(play_cards, trump_suit, current_rank, jat)
			if not best_is_trump_kill:
				# 首个合法主牌杀，直接赢
				best_seat = play["seat"]
				best_is_trump_kill = true
				best_value = play_value
			elif play_value > best_value:
				# 更大的主牌杀
				best_seat = play["seat"]
				best_value = play_value

		elif is_same_domain and not best_is_trump_kill:
			# 同副花色域跟牌（且没有人主牌杀过）：同样要求同结构
			var play_pattern := CardPattern.identify(play_cards, current_rank, rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
			if play_pattern == null or not _structure_matches(play_pattern, lead_pattern):
				continue  # 拆牌跟副：不构成同结构，不能赢
			var play_value := _get_play_sort_value(play_cards, trump_suit, current_rank, jat)
			if play_value > best_value:
				best_seat = play["seat"]
				best_value = play_value
		# else: 垫牌（非首出域、非主牌域），不参与

	return best_seat


# ============================================================
# Helpers
# ============================================================

static func _all_in_hand(cards: Array, hand: Array) -> bool:
	var hand_copy := hand.duplicate()
	for c: Card in cards:
		var found := false
		for i: int in range(hand_copy.size()):
			if c.equals(hand_copy[i]):
				hand_copy.remove_at(i)
				found = true
				break
		if not found:
			return false
	return true


static func _same_domain(cards: Array, trump_suit: int, current_rank: int, jat: bool) -> bool:
	if cards.size() <= 1:
		return true
	var first_dom := TrumpJudge.get_suit_domain(cards[0], trump_suit, current_rank, jat)
	for i: int in range(1, cards.size()):
		var dom := TrumpJudge.get_suit_domain(cards[i], trump_suit, current_rank, jat)
		if not _domains_equal(dom, first_dom):
			return false
	return true


static func _domains_equal(a: Dictionary, b: Dictionary) -> bool:
	if a["type"] != b["type"]:
		return false
	if a["type"] == TrumpJudge.DomainType.SIDE:
		return a["suit"] == b["suit"]
	return true


static func _get_domain_cards(hand: Array, domain: Dictionary, trump_suit: int, current_rank: int, jat: bool) -> Array:
	var result: Array = []
	for c: Card in hand:
		var dom := TrumpJudge.get_suit_domain(c, trump_suit, current_rank, jat)
		if _domains_equal(dom, domain):
			result.append(c)
	return result


static func _get_play_domain(cards: Array, trump_suit: int, current_rank: int, jat: bool) -> Dictionary:
	# Use first card's domain as representative
	if cards.is_empty():
		return {"type": TrumpJudge.DomainType.NONE, "suit": -1}
	return TrumpJudge.get_suit_domain(cards[0], trump_suit, current_rank, jat)


static func _get_play_sort_value(cards: Array, trump_suit: int, current_rank: int, jat: bool) -> int:
	# For comparison: use the max sort value among all cards
	var max_val := -1
	for c: Card in cards:
		var v := TrumpJudge.get_sort_value(c, trump_suit, current_rank, jat)
		if v > max_val:
			max_val = v
	return max_val


## Check that played domain cards respect lead pattern structure.
## GDD rule: Pair → must play pair if hand has one; Tractor → tractor > pairs > singles.
static func _check_follow_structure(
	played_domain: Array, hand_domain: Array,
	lead_pattern: CardPattern.PatternResult,
	trump_suit: int, current_rank: int, rule_config: RuleConfig,
) -> bool:
	var jat := rule_config.joker_always_trump

	if lead_pattern.type == Card.CardType.PAIR:
		var hand_pair_count := _count_pairs(hand_domain, trump_suit, current_rank, jat)
		if hand_pair_count > 0:
			var played_pair_count := _count_pairs(played_domain, trump_suit, current_rank, jat)
			if played_pair_count < 1:
				return false

	elif lead_pattern.type == Card.CardType.TRACTOR:
		var hand_pair_count := _count_pairs(hand_domain, trump_suit, current_rank, jat)
		if hand_pair_count > 0:
			var required_pairs := mini(hand_pair_count, lead_pattern.pair_count)
			var played_pair_count := _count_pairs(played_domain, trump_suit, current_rank, jat)
			if played_pair_count < required_pairs:
				return false

	return true


## Count pairs in a set of cards (group by card identity: suit+rank or joker_type).
static func _count_pairs(cards: Array, _trump_suit: int, _current_rank: int, _jat: bool) -> int:
	var id_counts: Dictionary = {}
	for c: Card in cards:
		var card_id: String
		if c.is_joker:
			card_id = "joker_%d" % c.joker_type
		else:
			card_id = "%d_%d" % [c.suit, c.rank]
		id_counts[card_id] = id_counts.get(card_id, 0) + 1
	var pairs := 0
	for id: String in id_counts:
		pairs += id_counts[id] / 2
	return pairs


static func _structure_matches(play_pattern: CardPattern.PatternResult, lead_pattern: CardPattern.PatternResult) -> bool:
	# Trump kill must have same card type as lead
	if play_pattern.type != lead_pattern.type:
		return false
	# For tractors, must have at least as many pairs
	if play_pattern.type == Card.CardType.TRACTOR:
		return play_pattern.pair_count >= lead_pattern.pair_count
	return true
