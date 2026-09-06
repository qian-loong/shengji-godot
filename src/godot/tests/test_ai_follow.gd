## AI 跟牌合法性回归
##
## 真机 bug（2026-07-31）：玩家甩 ♦A♦A♦K（对子+单张），东家手里有 ♦J♦J，
## AI 却挑了 ♦3♦6♦8 三张散牌。严格跟牌要求对子接对子，引擎判非法、
## submit_play 返回 ok=false，而 GUI 不检查返回值照样把牌画到桌上，
## 于是界面出了牌、手牌数不变、轮次推不动，整局卡死。
##
## 根因：_pick_domain_follow 只处理 PAIR / TRACTOR 两种首出牌型，
## DUMP 落到"取最小的 N 张"分支，完全不管结构。
##
## 核心不变量：**AI 挑出来的牌必须能通过 PlayValidator.validate_follow**。
## 这条比任何具体选牌策略都重要——AI 可以打得不好，但不能打出非法牌。
extends GutTest

const R := Card.Rank
const S := Card.Suit

var rc: RuleConfig


func before_each() -> void:
	rc = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)


# ============================================================
# Helpers
# ============================================================

func _c(suit: int, rank: int) -> Card:
	return Card.normal(suit as Card.Suit, rank as Card.Rank)


## 造 lead_info，与 SessionController._make_lead_info 结构一致
func _lead_info(cards: Array, trump_suit: int, current_rank: int) -> Dictionary:
	var pattern := PlayValidator.validate_lead(
		cards, cards.duplicate(), trump_suit, current_rank, rc)
	assert_not_null(pattern, "测试用的首出本身必须合法")
	return {
		"domain": TrumpJudge.get_suit_domain(
			cards[0], trump_suit, current_rank, rc.joker_always_trump),
		"count": cards.size(),
		"pattern": pattern,
	}


## 让 AI 决策并用引擎校验——把两边接起来才是这组测试的意义
func _ai_follow_is_legal(
	hand: Array, lead: Array, trump_suit: int, current_rank: int
) -> Dictionary:
	var info := _lead_info(lead, trump_suit, current_rank)
	var cards: Array = AIPlayer.new(1).decide_play(
		1, hand, info, {"trump_suit": trump_suit, "current_rank": current_rank}, rc)
	var ok := PlayValidator.validate_follow(
		cards, hand, lead.size(), info["domain"],
		trump_suit, current_rank, rc, info["pattern"])
	return {"cards": cards, "ok": ok}


func _count_pairs(cards: Array) -> int:
	var counts: Dictionary = {}
	for c: Card in cards:
		var key := "j%d" % c.joker_type if c.is_joker else "%d_%d" % [c.suit, c.rank]
		counts[key] = counts.get(key, 0) + 1
	var pairs := 0
	for k: String in counts:
		@warning_ignore("integer_division")
		pairs += int(counts[k]) / 2
	return pairs


# ============================================================
# 真机场景复现
# ============================================================

func test_ai_follow_dump_keeps_pair_real_device_case() -> void:
	# 真机 R3：主♠、级5。东家开打手牌减去前两墩已出的 ♣2 ♣3。
	# 方块部分：♦6 ♦K ♦J ♦3 ♦8 ♦J ♦10 —— 含一对 ♦J。
	var hand: Array = [
		_c(S.SPADE, R.JACK), _c(S.DIAMOND, R.SIX), _c(S.CLUB, R.SIX),
		_c(S.CLUB, R.FIVE), _c(S.CLUB, R.QUEEN), _c(S.DIAMOND, R.KING),
		_c(S.DIAMOND, R.JACK), _c(S.HEART, R.JACK), _c(S.CLUB, R.TEN),
		_c(S.CLUB, R.ACE), _c(S.DIAMOND, R.THREE), _c(S.DIAMOND, R.EIGHT),
		_c(S.HEART, R.EIGHT), _c(S.CLUB, R.KING), _c(S.DIAMOND, R.JACK),
		_c(S.SPADE, R.FOUR), _c(S.CLUB, R.ACE), _c(S.DIAMOND, R.TEN),
		_c(S.HEART, R.ACE), _c(S.HEART, R.EIGHT), _c(S.HEART, R.FOUR),
		_c(S.CLUB, R.TEN), _c(S.HEART, R.JACK),
	]
	# 玩家甩牌：一对 ♦A + 单张 ♦K
	var lead: Array = [
		_c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.KING),
	]

	var got := _ai_follow_is_legal(hand, lead, S.SPADE, R.FIVE)

	assert_true(got["ok"], "AI 跟甩牌必须合法，实际出了: %s" % _fmt(got["cards"]))
	assert_eq(_count_pairs(got["cards"]), 1, "手里有 ♦J♦J，必须用对子接对子")


func test_ai_follow_dump_pattern_is_recognized_as_dump() -> void:
	# 前置校验：这一手确实被识别为甩牌，否则上面的用例就测不到 DUMP 分支
	var lead: Array = [
		_c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.KING),
	]
	var info := _lead_info(lead, S.SPADE, R.FIVE)
	var pattern: CardPattern.PatternResult = info["pattern"]

	assert_eq(pattern.type, Card.CardType.DUMP, "♦A♦A♦K 应识别为甩牌")
	assert_eq(PlayValidator.required_pair_count(pattern), 1,
		"甩牌的对子需求 = 各分量之和 = 1")


# ============================================================
# 结构要求的其它牌型
# ============================================================

func test_ai_follow_pair_plays_pair() -> void:
	var hand: Array = [
		_c(S.DIAMOND, R.THREE), _c(S.DIAMOND, R.SIX), _c(S.DIAMOND, R.JACK),
		_c(S.DIAMOND, R.JACK), _c(S.CLUB, R.ACE),
	]
	var lead: Array = [_c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.ACE)]

	var got := _ai_follow_is_legal(hand, lead, S.SPADE, R.FIVE)

	assert_true(got["ok"], "跟对子必须合法，实际: %s" % _fmt(got["cards"]))
	assert_eq(_count_pairs(got["cards"]), 1, "有对子就得出对子")


func test_ai_follow_tractor_plays_pairs() -> void:
	var hand: Array = [
		_c(S.DIAMOND, R.THREE), _c(S.DIAMOND, R.THREE), _c(S.DIAMOND, R.SIX),
		_c(S.DIAMOND, R.SIX), _c(S.DIAMOND, R.NINE), _c(S.CLUB, R.ACE),
	]
	# 拖拉机：♦J♦J♦Q♦Q
	var lead: Array = [
		_c(S.DIAMOND, R.JACK), _c(S.DIAMOND, R.JACK),
		_c(S.DIAMOND, R.QUEEN), _c(S.DIAMOND, R.QUEEN),
	]

	var got := _ai_follow_is_legal(hand, lead, S.SPADE, R.FIVE)

	assert_true(got["ok"], "跟拖拉机必须合法，实际: %s" % _fmt(got["cards"]))
	assert_eq(_count_pairs(got["cards"]), 2, "有两对就得都贴上")


func test_ai_follow_without_pairs_is_still_legal() -> void:
	# 手里一对都没有时，引擎不强求结构，AI 出散牌应当合法
	var hand: Array = [
		_c(S.DIAMOND, R.THREE), _c(S.DIAMOND, R.SIX), _c(S.DIAMOND, R.EIGHT),
		_c(S.DIAMOND, R.TEN), _c(S.CLUB, R.ACE),
	]
	var lead: Array = [
		_c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.KING),
	]

	var got := _ai_follow_is_legal(hand, lead, S.SPADE, R.FIVE)

	assert_true(got["ok"], "无对子时出散牌应合法，实际: %s" % _fmt(got["cards"]))


func test_ai_follow_short_suit_is_legal() -> void:
	# 同域牌不够：必须全出，再用别的花色补
	var hand: Array = [
		_c(S.DIAMOND, R.THREE), _c(S.CLUB, R.ACE), _c(S.CLUB, R.KING),
		_c(S.HEART, R.TWO),
	]
	var lead: Array = [
		_c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.KING),
	]

	var got := _ai_follow_is_legal(hand, lead, S.SPADE, R.FIVE)

	assert_true(got["ok"], "同域不足时应合法，实际: %s" % _fmt(got["cards"]))
	assert_eq(got["cards"].size(), 3, "张数必须与首出一致")


func test_ai_follow_relaxed_structure_still_legal() -> void:
	# 宽松跟牌下不强制结构，同样不能出非法牌
	rc.strict_follow_structure = false
	var hand: Array = [
		_c(S.DIAMOND, R.THREE), _c(S.DIAMOND, R.SIX), _c(S.DIAMOND, R.JACK),
		_c(S.DIAMOND, R.JACK), _c(S.CLUB, R.ACE),
	]
	var lead: Array = [
		_c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.KING),
	]

	var got := _ai_follow_is_legal(hand, lead, S.SPADE, R.FIVE)

	assert_true(got["ok"], "宽松跟牌也必须合法，实际: %s" % _fmt(got["cards"]))


func test_ai_follow_pairs_only_hand_fills_by_splitting() -> void:
	# 手里全是对子、没有单张时，补足张数只能拆对子
	var hand: Array = [
		_c(S.DIAMOND, R.THREE), _c(S.DIAMOND, R.THREE),
		_c(S.DIAMOND, R.SIX), _c(S.DIAMOND, R.SIX),
		_c(S.CLUB, R.ACE),
	]
	var lead: Array = [
		_c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.ACE), _c(S.DIAMOND, R.KING),
	]

	var got := _ai_follow_is_legal(hand, lead, S.SPADE, R.FIVE)

	assert_true(got["ok"], "全对子手牌也要凑够张数且合法，实际: %s" % _fmt(got["cards"]))
	assert_eq(got["cards"].size(), 3)


func _fmt(cards: Array) -> String:
	var out := PackedStringArray()
	for c: Card in cards:
		if c.is_joker:
			out.append("大王" if c.joker_type == Card.JokerType.BIG else "小王")
		else:
			out.append("%s%s" % [Card.suit_symbol(c.suit), Card.rank_symbol(c.rank)])
	return " ".join(out)


# ============================================================
# 穷举采样：AI 跟牌永远不能被引擎判非法
#
# 自动对局覆盖不到这个 bug——headless 里四家都是 AI，而 AI 首出极少甩牌，
# 真机上是人类主动甩牌才撞出来的。所以这里用固定种子铺开大量首出组合，
# 补上那块盲区。种子固定 → 每次运行结果一致，符合确定性要求。
# ============================================================

const SAMPLE_SEED := 20260731
const SAMPLE_COUNT := 240


func test_ai_follow_never_illegal_across_sampled_hands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SAMPLE_SEED

	var failures: Array[String] = []
	var checked := 0
	var dump_leads := 0

	for i: int in range(SAMPLE_COUNT):
		var deck := _fresh_deck()
		_shuffle(deck, rng)

		# 首出方与跟牌方各抓一手
		var lead_hand: Array = deck.slice(0, 13)
		var follow_hand: Array = deck.slice(13, 26)

		var lead := _pick_lead(lead_hand, rng)
		if lead.is_empty():
			continue
		var pattern := PlayValidator.validate_lead(
			lead, lead_hand, S.SPADE, R.FIVE, rc)
		if pattern == null:
			continue
		if pattern.type == Card.CardType.DUMP:
			dump_leads += 1

		var info := {
			"domain": TrumpJudge.get_suit_domain(
				lead[0], S.SPADE, R.FIVE, rc.joker_always_trump),
			"count": lead.size(),
			"pattern": pattern,
		}
		var cards: Array = AIPlayer.new(1).decide_play(
			1, follow_hand, info,
			{"trump_suit": S.SPADE, "current_rank": R.FIVE}, rc)

		checked += 1
		if not PlayValidator.validate_follow(
				cards, follow_hand, lead.size(), info["domain"],
				S.SPADE, R.FIVE, rc, pattern):
			failures.append("首出 %s | 手牌 %s | AI 出 %s" % [
				_fmt(lead), _fmt(follow_hand), _fmt(cards)])

	assert_gt(checked, 100, "采样量太小说明构造逻辑有问题")
	assert_gt(dump_leads, 0, "样本里必须包含甩牌，否则测不到本次修复的分支")
	assert_eq(failures.size(), 0,
		"AI 出了 %d 手非法牌，前 3 例：\n%s" % [
			failures.size(), "\n".join(failures.slice(0, 3))])


## 造一副完整的牌（2 副装，与经典预设一致）
func _fresh_deck() -> Array:
	var deck: Array = []
	for d: int in range(2):
		for suit: int in [S.SPADE, S.HEART, S.DIAMOND, S.CLUB]:
			for rank: int in range(2, 15):
				deck.append(_c(suit, rank))
	return deck


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 从手牌里挑一个首出：优先凑出带对子的多张组合，好让甩牌分支被覆盖到
func _pick_lead(hand: Array, rng: RandomNumberGenerator) -> Array:
	# 按花色分组，只在同花色内组合（首出必须同域）
	var by_suit: Dictionary = {}
	for c: Card in hand:
		if c.is_joker:
			continue
		if not by_suit.has(c.suit):
			by_suit[c.suit] = []
		by_suit[c.suit].append(c)

	var suits := by_suit.keys()
	if suits.is_empty():
		return []
	var suit: int = suits[rng.randi_range(0, suits.size() - 1)]
	var group: Array = by_suit[suit]
	if group.is_empty():
		return []

	var mode := rng.randi_range(0, 3)
	match mode:
		0:
			return [group[0]]
		1:
			# 找一对
			for a: int in range(group.size()):
				for b: int in range(a + 1, group.size()):
					if group[a].rank == group[b].rank:
						return [group[a], group[b]]
			return [group[0]]
		_:
			# 多张（可能构成甩牌）
			var n: int = mini(group.size(), rng.randi_range(2, 4))
			return group.slice(0, n)
