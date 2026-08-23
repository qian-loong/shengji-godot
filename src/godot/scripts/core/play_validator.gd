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
# Dump challenge (C2 §1 / F1 §2.3)
# ============================================================

## 甩牌最大性挑战（GDD design/gdd/card-types.md §2.3）。
##
## 甩牌的每个组成部分（拆解为单张 / 对子 / 拖拉机后）都必须是该花色域中
## **当前最大**的——即其他玩家手中该域内没有比它*更大*的同类牌型。
## 相等不构成挑战（GDD 原文是"没有比它更大的"）。
##
## 不满足时甩牌失败：按 GDD 只出选中牌里**最小的一张单牌**，其余收回。
##
## other_hands 是其他三家的手牌，属于**引擎裁决用的全局视野**。
## AI 决策路径（AIPlayer.decide_play）绝不可调用本方法，否则等同开天眼。
##
## 返回：{ "ok": bool, "fallback_card": Card, "reason": String }
static func challenge_dump(
	dump_cards: Array,
	other_hands: Array,
	trump_suit: int,
	current_rank: int,
	rule_config: RuleConfig,
) -> Dictionary:
	var pass_result := { "ok": true, "fallback_card": null, "reason": "" }
	if dump_cards.is_empty():
		return pass_result

	var jat := rule_config.joker_always_trump
	var lead_domain := TrumpJudge.get_suit_domain(dump_cards[0], trump_suit, current_rank, jat)

	# 其他三家在该花色域内的牌
	var others: Array = []
	for hand: Array in other_hands:
		for c: Card in hand:
			var dom := TrumpJudge.get_suit_domain(c, trump_suit, current_rank, jat)
			if _domains_equal(dom, lead_domain):
				others.append(c)
	if others.is_empty():
		return pass_result

	# 对手在该域内能拿出的最大单张与最大对子
	var best_single := -1
	for c: Card in others:
		var v := TrumpJudge.get_sort_value(c, trump_suit, current_rank, jat)
		if v > best_single:
			best_single = v

	var best_pair := -1
	for group: Array in _group_by_identity(others):
		if group.size() >= 2:
			var v := TrumpJudge.get_sort_value(group[0], trump_suit, current_rank, jat)
			if v > best_pair:
				best_pair = v

	# 逐个分量比对。拖拉机在最大性上等价于"它包含的每个对子都最大"，
	# 因此按 identity 分组后逐组判定即可，无需还原拖拉机结构。
	for group: Array in _group_by_identity(dump_cards):
		var value := TrumpJudge.get_sort_value(group[0], trump_suit, current_rank, jat)
		var is_pair := group.size() >= 2
		var rival := best_pair if is_pair else best_single
		if rival > value:
			return {
				"ok": false,
				"fallback_card": _smallest_card(dump_cards, trump_suit, current_rank, jat),
				"reason": "%s %s 不是该域最大" % [
					"对子" if is_pair else "单张",
					group[0].to_string_repr(),
				],
			}

	return pass_result


## 按 identity（同花同点 / 同类型王）分组
static func _group_by_identity(cards: Array) -> Array:
	var by_id: Dictionary = {}
	for c: Card in cards:
		var key := _card_identity(c)
		if not by_id.has(key):
			by_id[key] = []
		by_id[key].append(c)
	var groups: Array = []
	for key: String in by_id:
		groups.append(by_id[key])
	return groups


static func _card_identity(card: Card) -> String:
	if card.is_joker:
		return "joker_%d" % card.joker_type
	return "%d_%d" % [card.suit, card.rank]


static func _smallest_card(cards: Array, trump_suit: int, current_rank: int, jat: bool) -> Card:
	var best: Card = cards[0]
	var best_value := TrumpJudge.get_sort_value(best, trump_suit, current_rank, jat)
	for c: Card in cards:
		var v := TrumpJudge.get_sort_value(c, trump_suit, current_rank, jat)
		if v < best_value:
			best = c
			best_value = v
	return best


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
##
## GDD play-validation.md 跟牌优先级：
##   Pair    → 手中有对子就必须出对子
##   Tractor → 有拖拉机出拖拉机；否则尽量多出对子
##   Dump    → 按甩牌的拆解结构逐分量匹配（GDD §跟牌优先级 + E5）
##
## 这条约束的意义不是"格式检查"，而是**平衡杠杆**：不许拆对意味着跟牌方
## 被迫交出更多分（首出对 K 时，手握对 10 就必须送 20 分而非拆开只送 10 分）。
## 因此首出为甩牌时同样要生效——否则甩牌反而比出对子更逼不出分，攻击力倒挂。
static func _check_follow_structure(
	played_domain: Array, hand_domain: Array,
	lead_pattern: CardPattern.PatternResult,
	trump_suit: int, current_rank: int, rule_config: RuleConfig,
) -> bool:
	var jat := rule_config.joker_always_trump
	var required_pairs := required_pair_count(lead_pattern)
	if required_pairs <= 0:
		return true

	var hand_pair_count := _count_pairs(hand_domain, trump_suit, current_rank, jat)
	if hand_pair_count <= 0:
		return true

	var needed := mini(hand_pair_count, required_pairs)
	var played_pair_count := _count_pairs(played_domain, trump_suit, current_rank, jat)
	return played_pair_count >= needed


## 首出结构里"必须被对上"的对子数。
## 甩牌取其各分量的对子数之和——拖拉机按 pair_count，对子按 1，单张不计。
##
## 公开给 AI 使用：跟牌决策必须和这里的判定同源，否则 AI 会挑出引擎判非法的牌。
## 曾经 AI 只认 PAIR / TRACTOR，跟甩牌时走"取最小的 N 张"分支，把对子留在手里
## 被引擎拒绝，而 GUI 又不检查返回值，整局就此卡死。
static func required_pair_count(lead_pattern: CardPattern.PatternResult) -> int:
	match lead_pattern.type:
		Card.CardType.PAIR:
			return 1
		Card.CardType.TRACTOR:
			return lead_pattern.pair_count
		Card.CardType.DUMP:
			var total := 0
			for comp: CardPattern.PatternResult in lead_pattern.components:
				total += required_pair_count(comp)
			return total
		_:
			return 0


## Count pairs in a set of cards (group by card identity: suit+rank or joker_type).
static func _count_pairs(cards: Array, _trump_suit: int, _current_rank: int, _jat: bool) -> int:
	var id_counts: Dictionary = {}
	for c: Card in cards:
		var card_id := _card_identity(c)
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
