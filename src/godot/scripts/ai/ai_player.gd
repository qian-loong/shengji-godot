## AI basic decision — rule-correct AI for MVP
## Implements: FT1 AI Basic GDD (design/gdd/ai-basic.md)
class_name AIPlayer
extends RefCounted


# ============================================================
# Lead strategy switch
# ============================================================

enum LeadStrategy {
	SIMPLE,         ## 只首出单张（既有行为）
	MAX_STRUCTURE,  ## 优先首出最大结构：拖拉机 > 对子 > 单张
	DUMP_HAPPY,     ## 尽量甩牌：同域多张一次打出（用于压测甩牌规则）
	SMART,          ## 攻守身份驱动的自主决策（首出+跟牌，见 ai-basic.md §4b；S5-05）
}


# ============================================================
# Instance state (ADR-0005: static→实例迁移)
# ============================================================

## 该实例代表的座位（0-3）。
var seat_id: int = -1

## 局级确定性 RNG（四家共享同一实例，构造注入）。null 时 _decision_randf 回退全局 randf()。
var rng: RandomNumberGenerator = null

## 局内记牌状态（GameRound 持有的那一份，构造注入）。步骤 B 前为 null。
## 类型标注留待 CardMemory 类落地（步骤 B）后收紧；现用 Object 以免前向引用。
var card_memory: Object = null

## 该 AI 私有已知的离场牌（配底/反主后注入的不可变快照）。默认空。
## 不可变性由约定+防御强制（见 set_private_known）：GDScript 无 const 实例成员。
var private_known_cards: Array = []

## 是否已注入过 private_known_cards（防重复注入，模拟不可变）。
var _private_known_injected: bool = false

## 首出策略（实例成员，原 static var）。默认 SIMPLE 以保持既有对局基线不变。
##
## SIMPLE 下 AI 永远只出单张，导致 allow_dump / strict_follow_structure /
## tractor_allow_rank_card / four_same_is_tractor 等规则分支在批跑中永不触发
## （实测 54387 墩首出 100% 单张）。scenario 模式会切到 MAX_STRUCTURE
## 来激活这些路径。SMART 为 S5-05 默认对局路径。
var lead_strategy: LeadStrategy = LeadStrategy.SIMPLE


## 构造 AI 实例。
## p_seat: 座位 id；p_memory: GameRound 共享的 CardMemory（步骤 B 前传 null）；
## p_rng: 局级确定性 RNG（四家共享，null 时回退全局 randf()）。
func _init(p_seat: int = -1, p_memory: Object = null, p_rng: RandomNumberGenerator = null) -> void:
	seat_id = p_seat
	card_memory = p_memory
	rng = p_rng


## 注入 private_known_cards（配底/反主后一次性调用）。
## 不可变模拟：duplicate() 切断外部引用 + assert 只注入一次 + 无 setter 暴露。
func set_private_known(cards: Array) -> void:
	assert(not _private_known_injected, "private_known_cards 只能注入一次")
	private_known_cards = cards.duplicate()
	_private_known_injected = true


# ============================================================
# Bid decision
# ============================================================

## 决策随机数取值：注入了确定性 RNG 时走它，否则回退全局 randf()。
##
## ADR-0005 §可复现契约：SMART/AC16 要求同 seed 逐字节可复现，全局 randf()
## 会使亮主序列随进程漂移。故 rng 一旦注入（从局种子派生、四家共享同一实例、
## 座位按固定顺序调用），decide_bid 的随机分支就完全确定。
## rng == null 时保留旧行为——尚未迁移的调用点（早期测试等）不因此报错。
func _decision_randf(p_rng: RandomNumberGenerator) -> float:
	return p_rng.randf() if p_rng != null else randf()


## Decide whether and what to bid.
## rng: 局级确定性 RNG（四家共享），null 时回退全局 randf()（见 _decision_randf）。
func decide_bid(seat_id: int, hand: Array, current_rank: int, rule_config: RuleConfig, rng: RandomNumberGenerator = null) -> TrumpBidding.BidDeclaration:
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
	if trump_strength >= 2 and _decision_randf(rng) < 0.3:
		return best
	return null


# ============================================================
# Counter-bid decision (attacker may reverse trump after dealer's bury)
# ============================================================

## Decide whether to counter-bid against the current dealer's declaration.
## Returns null when AI declines (pass).
## Mirrors decide_bid's hand-strength heuristic so the AI doesn't mass-counter
## with weak hands and destabilize automated regressions.
func decide_counter(
	seat_id: int,
	hand: Array,
	current_rank: int,
	current_bid: TrumpBidding.BidDeclaration,
	rule_config: RuleConfig
) -> TrumpBidding.BidDeclaration:
	if current_bid == null:
		return null
	if not TrumpBidding.can_be_countered(current_bid):
		return null

	var available := TrumpBidding.get_available_bids(seat_id, hand, current_rank, rule_config)
	var stronger: Array = []
	for b: TrumpBidding.BidDeclaration in available:
		if TrumpBidding.is_stronger(b, current_bid):
			stronger.append(b)
	if stronger.is_empty():
		return null

	# Pick strongest stronger option.
	var best: TrumpBidding.BidDeclaration = stronger[0]
	for i: int in range(1, stronger.size()):
		if TrumpBidding.is_stronger(stronger[i], best):
			best = stronger[i]

	# Same hand-strength gate as decide_bid: only counter if the hand is decent.
	var trump_strength := 0
	for c: Card in hand:
		if c.is_joker:
			trump_strength += 3
		elif c.rank == current_rank:
			trump_strength += 2
	if trump_strength >= 4:
		return best
	# Otherwise pass — don't counter on weak hands.
	return null


# ============================================================
# Bury decision (when AI is dealer)
# ============================================================

## Select cards to bury. Returns array of indices into hand.
func decide_bury(hand: Array, bottom_size: int, trump_suit: int, current_rank: int, rule_config: RuleConfig) -> Array[int]:
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
func decide_play(seat_id: int, hand: Array, lead_info: Dictionary, game_state: Dictionary, rule_config: RuleConfig) -> Array:
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

## 找出手牌中"最大的可首出结构"：最长拖拉机 > 对子 > 空（空则回退单张策略）。
##
## 首出必须同一花色域，因此先按域分组，再在组内找连续对子。
## 是否构成拖拉机交给 CardPattern.identify 判定，从而自动尊重
## tractor_allow_rank_card / four_same_is_tractor 等配置。
func _decide_lead_max_structure(hand: Array, trump_suit: int, current_rank: int, rc: RuleConfig) -> Array:
	var jat := rc.joker_always_trump

	# 按花色域分组
	var groups: Dictionary = {}
	for c: Card in hand:
		var dom := TrumpJudge.get_suit_domain(c, trump_suit, current_rank, jat)
		var key: String
		if dom["type"] == TrumpJudge.DomainType.TRUMP:
			key = "trump"
		elif dom["type"] == TrumpJudge.DomainType.SIDE:
			key = "side_%d" % dom["suit"]
		else:
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(c)

	var best: Array = []

	for key: String in groups:
		var group: Array = groups[key]

		# 组内按 identity 找对子
		var by_identity: Dictionary = {}
		for c: Card in group:
			var id_key: String
			if c.is_joker:
				id_key = "joker_%d" % c.joker_type
			else:
				id_key = "%d_%d" % [c.suit, c.rank]
			if not by_identity.has(id_key):
				by_identity[id_key] = []
			by_identity[id_key].append(c)

		var pairs: Array = []
		for id_key: String in by_identity:
			var same: Array = by_identity[id_key]
			if same.size() >= 2:
				pairs.append({ "rank": same[0].rank, "cards": [same[0], same[1]] })

		if pairs.is_empty():
			continue

		pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return Card.RANK_SEQUENCE.find(a["rank"]) < Card.RANK_SEQUENCE.find(b["rank"])
		)

		# 从最长窗口往下试，命中拖拉机即止
		var found_tractor := false
		for length: int in range(pairs.size(), 1, -1):
			for start: int in range(pairs.size() - length + 1):
				var candidate: Array = []
				for i: int in range(start, start + length):
					candidate.append_array(pairs[i]["cards"])
				var pattern := CardPattern.identify(
					candidate, current_rank,
					rc.tractor_allow_rank_card, rc.four_same_is_tractor)
				if pattern != null and pattern.type == Card.CardType.TRACTOR:
					if candidate.size() > best.size():
						best = candidate
					found_tractor = true
					break
			if found_tractor:
				break

		# 没有拖拉机时退而求其次：出一个对子
		if not found_tractor and best.size() < 2:
			best = pairs[0]["cards"]

	return best


## 尽量甩牌：在同一花色域内挑 3 张打出去（对子 + 单张的组合最易构成 Dump）。
##
## 只用于压测甩牌规则路径 —— 它**故意不判断**"每个组成部分是否该域最大"，
## 因为那正是要检验引擎有没有拦住的东西（GDD card-types.md §2.3）。
func _decide_lead_dump(hand: Array, trump_suit: int, current_rank: int, rc: RuleConfig) -> Array:
	if not rc.allow_dump:
		return []

	var jat := rc.joker_always_trump
	var groups: Dictionary = {}
	for c: Card in hand:
		var dom := TrumpJudge.get_suit_domain(c, trump_suit, current_rank, jat)
		if dom["type"] != TrumpJudge.DomainType.SIDE:
			continue  # 只在副牌域甩，避免动用主牌
		var key: int = dom["suit"]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(c)

	for key: int in groups:
		var group: Array = groups[key]
		if group.size() < 3:
			continue
		group.sort_custom(func(a: Card, b: Card) -> bool:
			return TrumpJudge.get_sort_value(a, trump_suit, current_rank, jat) \
				> TrumpJudge.get_sort_value(b, trump_suit, current_rank, jat)
		)
		var candidate: Array = [group[0], group[1], group[2]]
		var pattern := CardPattern.identify(
			candidate, current_rank, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
		if pattern != null and pattern.type == Card.CardType.DUMP:
			return candidate

	return []


func _decide_lead(hand: Array, trump_suit: int, current_rank: int, rc: RuleConfig) -> Array:
	var jat := rc.joker_always_trump

	if lead_strategy == LeadStrategy.DUMP_HAPPY:
		var dumped := _decide_lead_dump(hand, trump_suit, current_rank, rc)
		if not dumped.is_empty():
			return dumped

	if lead_strategy == LeadStrategy.MAX_STRUCTURE:
		var structured := _decide_lead_max_structure(hand, trump_suit, current_rank, rc)
		if not structured.is_empty():
			return structured

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

func _decide_follow(hand: Array, lead_info: Dictionary, trump_suit: int, current_rank: int, rc: RuleConfig) -> Array:
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
func _pick_domain_follow(domain_cards: Array, lead_count: int, lead_pattern: CardPattern.PatternResult, trump_suit: int, current_rank: int, rc: RuleConfig) -> Array:
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

	# 结构要求一律走引擎的 required_pair_count：对子=1、拖拉机=pair_count、
	# 甩牌=各分量之和。此前这里只认 PAIR / TRACTOR，跟甩牌时会掉进下面的
	# "取最小的 N 张"分支，把对子留在手里，被 validate_follow 判非法。
	var required_pairs := 0
	if lead_pattern != null and rc.strict_follow_structure:
		required_pairs = PlayValidator.required_pair_count(lead_pattern)

	if required_pairs > 0 and not pairs.is_empty():
		# 引擎只要求 min(手里对子数, 首出对子数) 个，多的不必贴上去
		var needed: int = mini(pairs.size(), required_pairs)
		for i: int in range(needed):
			result.append_array(pairs[i])

		# 先用单张补足张数（留着大对子）
		var si := 0
		while result.size() < lead_count and si < singles.size():
			result.append(singles[si])
			si += 1

		# 单张不够时再拆剩余的对子来填
		var pi := needed
		while result.size() < lead_count and pi < pairs.size():
			for c: Card in pairs[pi]:
				if result.size() < lead_count:
					result.append(c)
			pi += 1

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

func _count_suit(hand: Array, suit: int, trump_suit: int, current_rank: int, jat: bool) -> int:
	var count := 0
	for c: Card in hand:
		if not c.is_joker and c.suit == suit and not TrumpJudge.is_trump(c, trump_suit, current_rank, jat):
			count += 1
	return count


func _domains_eq(a: Dictionary, b: Dictionary) -> bool:
	if a["type"] != b["type"]:
		return false
	if a["type"] == TrumpJudge.DomainType.SIDE:
		return a["suit"] == b["suit"]
	return true
