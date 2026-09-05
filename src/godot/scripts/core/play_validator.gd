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
# Legal play enumeration (C2 §Formulas / ADR-0006)
# ============================================================

## 枚举所有合法出牌方案（供 AI SMART 评分流水线遍历）。
## lead == null → 枚举合法首出；lead != null → 枚举合法跟牌。
## 返回 Array（每个元素是 Array[Card]，一种合法出牌），已按规范全序排序（确定性）。
##
## ADR-0006：枚举沉到 C2 与校验器同源——每个候选经 validate_lead/validate_follow
## 复核（DEBUG assert），杜绝"AI 自造候选被引擎判非法"的历史 bug。
## 甩牌候选**只保证 shape 合法，不校验最大性**（最大性需 other_hands = 开天眼，
## AI 不得触碰）；最大性由 AI 记牌推断 + 引擎 submit_play 兜底裁决。
static func get_legal_plays(
	hand: Array,
	lead: CardPattern.PatternResult,   # null = 首出枚举
	trump_suit: int,
	current_rank: int,
	rule_config: RuleConfig,
	lead_cards: Array = [],            # lead != null 时必传：首出的实际牌（用于取域）
) -> Array:
	var candidates: Array
	if lead == null:
		candidates = _enumerate_leads(hand, trump_suit, current_rank, rule_config)
	else:
		candidates = _enumerate_follows(hand, lead, lead_cards, trump_suit, current_rank, rule_config)

	# 全序排序（确定性，对齐 ADR-0005 §可复现契约）
	candidates = _sort_candidates_canonical(candidates, trump_suit, current_rank, rule_config.joker_always_trump)

	# DEBUG 同源自检：首出候选须过 validate_lead（首出枚举未在生成时逐一校验）。
	# 跟牌候选已在 _enumerate_follows 内经 validate_follow 过滤，无需重复（避免 O(候选) 翻倍开销）。
	if OS.is_debug_build() and lead == null:
		for cand: Array in candidates:
			assert(validate_lead(cand, hand, trump_suit, current_rank, rule_config) != null,
				"get_legal_plays 产出的首出候选未通过 validate_lead（生成器/校验器分歧）")

	return candidates


## 首出枚举（lead == null）：按花色域分治，每域枚举 Single/Pair/Tractor/Dump。
static func _enumerate_leads(hand: Array, trump_suit: int, current_rank: int, rule_config: RuleConfig) -> Array:
	var jat := rule_config.joker_always_trump
	var result: Array = []

	# 按域分组（域内分治是主剪枝：合法牌型的所有牌必属同一域）
	var by_domain := _group_hand_by_domain(hand, trump_suit, current_rank, jat)

	for domain_key: String in by_domain:
		var domain_cards: Array = by_domain[domain_key]

		# Single：每一张牌都是合法单张首出
		for c: Card in domain_cards:
			result.append([c])

		# Pair：identity 分组后 size >= 2 的组各贡献一个对子
		for group: Array in _group_by_identity(domain_cards):
			if group.size() >= 2:
				result.append([group[0], group[1]])

		# Tractor：域内所有合法拖拉机（含四张王 / four_same 特例，由 identify 兜底确认）
		for tractor: Array in _enumerate_tractors_in_domain(domain_cards, current_rank, rule_config):
			result.append(tractor)

		# Dump：仅 allow_dump。域内 ≥2 张的多分量组合，只校验 shape。
		if rule_config.allow_dump:
			for dump: Array in _enumerate_dumps_in_domain(domain_cards, current_rank, rule_config):
				result.append(dump)

	return result


## 枚举一个域内的所有合法拖拉机。
## 策略：identity 分组取出所有对子的 rank，找出所有 ≥2 长的相邻 rank 窗口，
## 每个窗口构造一个拖拉机候选；再加四张王 / four_same 特例。
## 生成后用 CardPattern.identify 确认为 TRACTOR（同源兜底）。
static func _enumerate_tractors_in_domain(domain_cards: Array, current_rank: int, rule_config: RuleConfig) -> Array:
	var result: Array = []

	# identity 分组：拿到每个"对子"的两张牌与 rank
	var pairs_by_rank: Dictionary = {}   # rank -> Array[Card]（该 rank 的一个对子的两张）
	for group: Array in _group_by_identity(domain_cards):
		if group.size() >= 2 and not group[0].is_joker:
			pairs_by_rank[group[0].rank] = [group[0], group[1]]

	# 四张王特例：域内同时有 2 小王 + 2 大王
	var jokers := domain_cards.filter(func(c: Card) -> bool: return c.is_joker)
	var small_jokers := jokers.filter(func(c: Card) -> bool: return c.joker_type == Card.JokerType.SMALL)
	var big_jokers := jokers.filter(func(c: Card) -> bool: return c.joker_type == Card.JokerType.BIG)
	if small_jokers.size() >= 2 and big_jokers.size() >= 2:
		result.append([small_jokers[0], small_jokers[1], big_jokers[0], big_jokers[1]])

	# 所有 rank 对的相邻窗口（长度 2..N）
	var pair_ranks: Array = pairs_by_rank.keys()
	pair_ranks.sort_custom(func(a: int, b: int) -> bool:
		return Card.RANK_SEQUENCE.find(a) < Card.RANK_SEQUENCE.find(b)
	)
	# 枚举所有连续窗口：对每个起点，尽量向后延伸相邻 rank
	for i: int in range(pair_ranks.size()):
		var window: Array[int] = [pair_ranks[i]]
		for j: int in range(i + 1, pair_ranks.size()):
			if Card.is_adjacent(pair_ranks[j - 1], pair_ranks[j], current_rank):
				window.append(pair_ranks[j])
				# 窗口长度 >= 2 即构成拖拉机候选
				if window.size() >= 2:
					var cards: Array = []
					for wr: int in window:
						cards.append(pairs_by_rank[wr][0])
						cards.append(pairs_by_rank[wr][1])
					# 同源确认：identify 须判为 TRACTOR
					var pat := CardPattern.identify(cards, current_rank,
						rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
					if pat != null and pat.type == Card.CardType.TRACTOR:
						result.append(cards)
			else:
				break

	return result


## 枚举一个域内的所有合法甩牌（shape only，不校验最大性）。
## 甩牌 = 域内 ≥2 张、拆解出 ≥2 个分量的组合。枚举策略：从"该域全部牌"这个
## 最大甩牌开始，配合较小子集——但穷举子集会爆炸，故只枚举**有意义的甩牌**：
## 域内牌数 >= 2 时，用 identify 确认"整个域"及其去掉尾部单张的若干子集是否为 DUMP。
##
## MVP 剪枝：只枚举"域内全部牌"作为甩牌候选（若它是合法 DUMP）。更细的子集甩牌
## 组合空间大、AI 评分收益低，留待 FT4 按需扩展（记为已知窄化，见 ADR-0006 Consequences）。
static func _enumerate_dumps_in_domain(domain_cards: Array, current_rank: int, rule_config: RuleConfig) -> Array:
	var result: Array = []
	if domain_cards.size() < 2:
		return result
	var pat := CardPattern.identify(domain_cards, current_rank,
		rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
	if pat != null and pat.type == Card.CardType.DUMP:
		result.append(domain_cards.duplicate())
	return result


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
## precomputed_domain_cards: 预算好的"手中首出域的牌"（可选）。在批量枚举同一手牌时
##   （get_legal_plays），该集合对所有候选恒定，预算一次跳过每候选重算——纯性能优化，
##   不改判定逻辑（ADR-0006：与枚举器同源）。null 时内部照常计算，行为完全一致。
static func validate_follow(cards: Array, hand: Array, lead_count: int, lead_domain: Dictionary, trump_suit: int, current_rank: int, rule_config: RuleConfig, lead_pattern: CardPattern.PatternResult = null, precomputed_domain_cards = null) -> bool:
	# Must play exact same number of cards
	if cards.size() != lead_count:
		return false

	# All cards must be in hand
	if not _all_in_hand(cards, hand):
		return false

	var jat := rule_config.joker_always_trump

	# Count how many cards of lead domain in hand（可复用预算结果）
	var domain_cards_in_hand: Array = precomputed_domain_cards if precomputed_domain_cards != null else _get_domain_cards(hand, lead_domain, trump_suit, current_rank, jat)

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


# ============================================================
# Enumeration helpers (ADR-0006)
# ============================================================

## 按花色域把手牌分组。key = 域的规范字符串（TRUMP / SIDE_<suit> / NONE）。
static func _group_hand_by_domain(hand: Array, trump_suit: int, current_rank: int, jat: bool) -> Dictionary:
	var by_domain: Dictionary = {}
	for c: Card in hand:
		var dom := TrumpJudge.get_suit_domain(c, trump_suit, current_rank, jat)
		var key := _domain_key(dom)
		if not by_domain.has(key):
			by_domain[key] = []
		by_domain[key].append(c)
	return by_domain


static func _domain_key(dom: Dictionary) -> String:
	if dom["type"] == TrumpJudge.DomainType.SIDE:
		return "SIDE_%d" % dom["suit"]
	if dom["type"] == TrumpJudge.DomainType.TRUMP:
		return "TRUMP"
	return "NONE"


## 跟牌枚举（lead != null）：域内分治剪枝（ADR-0006 Constraints）。
##
## 关键剪枝：跟牌规则要求"域内牌优先出完"。故按首出域把手牌分为域内/域外：
##   - 域内牌 >= n：只在**域内**枚举 n 张组合（域内牌通常远少于 25）。
##   - 域内牌 <  n：域内牌**全部必出**（固定），只在**域外**枚举补齐的 (n - 域内数) 张。
## 这把最坏组合数从 C(手牌, n) 降到 C(域内, n) 或 C(域外, 补数)，避免 C(25,4) 爆炸。
## 拼出的候选仍过 validate_follow 复核——结构约束/张数由校验器把关，生成器与校验器同源。
static func _enumerate_follows(hand: Array, lead: CardPattern.PatternResult, lead_cards: Array, trump_suit: int, current_rank: int, rule_config: RuleConfig) -> Array:
	var jat := rule_config.joker_always_trump
	var lead_domain := TrumpJudge.get_suit_domain(lead_cards[0], trump_suit, current_rank, jat)
	var n := lead.card_count

	var domain_cards := _get_domain_cards(hand, lead_domain, trump_suit, current_rank, jat)
	var other_cards: Array = []
	for c: Card in hand:
		var dom := TrumpJudge.get_suit_domain(c, trump_suit, current_rank, jat)
		if not _domains_equal(dom, lead_domain):
			other_cards.append(c)

	var seen: Dictionary = {}
	var result: Array = []

	if domain_cards.size() >= n:
		# 域内够牌：只在域内枚举 n 张组合
		for combo: Array in _combinations(domain_cards, n):
			_try_add_follow(combo, hand, n, lead_domain, lead, trump_suit, current_rank, rule_config, seen, result, domain_cards)
	else:
		# 域内不够：域内全部必出，域外补齐剩余张数
		var need_from_other := n - domain_cards.size()
		if need_from_other <= 0 or other_cards.size() < need_from_other:
			# 补不齐（手牌不足 n 张，理论上不该发生）——退化为域内全出
			_try_add_follow(domain_cards.duplicate(), hand, n, lead_domain, lead, trump_suit, current_rank, rule_config, seen, result, domain_cards)
		else:
			for fill: Array in _combinations(other_cards, need_from_other):
				var combo := domain_cards.duplicate()
				combo.append_array(fill)
				_try_add_follow(combo, hand, n, lead_domain, lead, trump_suit, current_rank, rule_config, seen, result, domain_cards)

	return result


## 校验并去重后加入结果集。domain_cards = 预算好的手中首出域牌（传给 validate_follow 跳过重算）。
static func _try_add_follow(combo: Array, hand: Array, n: int, lead_domain: Dictionary, lead: CardPattern.PatternResult, trump_suit: int, current_rank: int, rule_config: RuleConfig, seen: Dictionary, result: Array, domain_cards: Array) -> void:
	if not validate_follow(combo, hand, n, lead_domain, trump_suit, current_rank, rule_config, lead, domain_cards):
		return
	var sig := _combo_signature(combo)
	if seen.has(sig):
		return
	seen[sig] = true
	result.append(combo)


## 生成 hand 中所有 k-张组合（按下标，保序）。k 通常很小（1/2/4）。
static func _combinations(hand: Array, k: int) -> Array:
	var result: Array = []
	var n := hand.size()
	if k <= 0 or k > n:
		return result
	var idx: Array[int] = []
	for i: int in range(k):
		idx.append(i)
	while true:
		var combo: Array = []
		for i: int in idx:
			combo.append(hand[i])
		result.append(combo)
		# 推进下标（字典序下一个组合）
		var pos := k - 1
		while pos >= 0 and idx[pos] == n - k + pos:
			pos -= 1
		if pos < 0:
			break
		idx[pos] += 1
		for j: int in range(pos + 1, k):
			idx[j] = idx[j - 1] + 1
	return result


## 组合的等价签名（按 identity 多重集，忽略 deck_id）——同 identity 的组合视为等价。
static func _combo_signature(combo: Array) -> String:
	var ids: Array[String] = []
	for c: Card in combo:
		ids.append(_card_identity(c))
	ids.sort()
	return "|".join(ids)


## 候选集全序排序（确定性，对齐 ADR-0005 §可复现契约）。
## 每个候选先内部按 (sort_value, deck_id) 排；候选之间按逐张 (sort_value, suit, rank, deck_id) 字典序。
static func _sort_candidates_canonical(candidates: Array, trump_suit: int, current_rank: int, jat: bool) -> Array:
	# 先把每个候选内部按规范序排（稳定的比较基准）
	for cand: Array in candidates:
		cand.sort_custom(func(a: Card, b: Card) -> bool:
			return _card_order_key(a, trump_suit, current_rank, jat) < _card_order_key(b, trump_suit, current_rank, jat)
		)
	# 候选之间：先按张数，再逐张比较规范键
	candidates.sort_custom(func(x: Array, y: Array) -> bool:
		if x.size() != y.size():
			return x.size() < y.size()
		for i: int in range(x.size()):
			var kx := _card_order_key(x[i], trump_suit, current_rank, jat)
			var ky := _card_order_key(y[i], trump_suit, current_rank, jat)
			if kx != ky:
				return kx < ky
		return false
	)
	return candidates


## 单张牌的全序键：sort_value 主序，deck_id 兜底 tie-break（两副牌同名牌唯一定序）。
## 打包成单一 int：sort_value 高位 + suit/rank/deck_id 低位，保证全序无并列。
static func _card_order_key(card: Card, trump_suit: int, current_rank: int, jat: bool) -> int:
	var sv := TrumpJudge.get_sort_value(card, trump_suit, current_rank, jat)
	var suit_bits := (card.suit + 1) if not card.is_joker else 0
	var rank_bits := card.rank if not card.is_joker else 0
	# sv(0..150) << 24 | suit(0..4) << 20 | rank(0..14) << 8 | deck_id
	return (sv << 24) | (suit_bits << 20) | (rank_bits << 8) | card.deck_id
