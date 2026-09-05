## Unit tests for PlayValidator.get_legal_plays (ADR-0006 / FT1 AC0)
## Validates: C2 play-validation.md §Formulas get_legal_plays;
##            ai-basic.md AC0 (枚举合法出牌，首出+跟牌两语义，穷尽 + 同源 + 确定性)
##
## 枚举器把"生成所有合法出牌"沉到 C2，与 validate_lead/validate_follow 同源。
## 本测试验证：穷尽性、每候选过校验器、跨配置、确定性排序。
extends GutTest

const S = Card.Suit
const R = Card.Rank
const J = Card.JokerType
const CT = Card.CardType

var rc: RuleConfig
const TRUMP := S.SPADE
const RANK := R.FOUR   # current_rank = 4


func before_each() -> void:
	rc = RuleConfig.new()
	rc.current_rank = RANK
	rc.allow_dump = true
	rc.strict_follow_structure = true


# ============================================================
# 首出枚举 (lead == null)
# ============================================================

func test_lead_enumeration_includes_every_single() -> void:
	# Arrange — 一手无对子的杂牌（副牌域），每张都应可单张首出
	var hand: Array = [
		Card.normal(S.HEART, R.SEVEN),
		Card.normal(S.HEART, R.NINE),
		Card.normal(S.CLUB, R.THREE),
	]

	# Act
	var plays := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)

	# Assert — 每张牌都作为单张出现在枚举结果里
	var singles := plays.filter(func(p: Array) -> bool: return p.size() == 1)
	assert_eq(singles.size(), 3, "每张手牌都应可单张首出")


func test_lead_enumeration_includes_pair() -> void:
	# Arrange — 含一个对子 ♥7♥7
	var hand: Array = [
		Card.normal(S.HEART, R.SEVEN, 0),
		Card.normal(S.HEART, R.SEVEN, 1),
		Card.normal(S.CLUB, R.THREE),
	]

	# Act
	var plays := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)

	# Assert — 枚举含一个 2 张的对子候选
	var pairs := plays.filter(func(p: Array) -> bool:
		return p.size() == 2 and CardPattern.identify(p, RANK, rc.tractor_allow_rank_card, rc.four_same_is_tractor).type == CT.PAIR
	)
	assert_true(pairs.size() >= 1, "含对子的手牌应枚举出对子候选")


func test_lead_enumeration_includes_tractor() -> void:
	# Arrange — ♥7♥7♥8♥8（级=4，7-8 相邻）→ 拖拉机
	var hand: Array = [
		Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1),
		Card.normal(S.HEART, R.EIGHT, 0), Card.normal(S.HEART, R.EIGHT, 1),
	]

	# Act
	var plays := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)

	# Assert — 含一个 4 张拖拉机候选
	var tractors := plays.filter(func(p: Array) -> bool:
		if p.size() != 4:
			return false
		var pat := CardPattern.identify(p, RANK, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
		return pat != null and pat.type == CT.TRACTOR
	)
	assert_true(tractors.size() >= 1, "相邻对子应枚举出拖拉机候选")


func test_lead_every_candidate_passes_validate_lead() -> void:
	# Arrange — 混合手牌（含对子、拖拉机、杂牌，跨两个域）
	var hand: Array = [
		Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1),
		Card.normal(S.HEART, R.EIGHT, 0), Card.normal(S.HEART, R.EIGHT, 1),
		Card.normal(S.CLUB, R.THREE), Card.normal(S.CLUB, R.KING),
	]

	# Act
	var plays := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)

	# Assert — 生成器/校验器同源：每个候选都过 validate_lead
	for p: Array in plays:
		assert_not_null(
			PlayValidator.validate_lead(p, hand, TRUMP, RANK, rc),
			"枚举候选 %s 必须通过 validate_lead" % [_repr(p)]
		)


func test_lead_dump_only_when_allow_dump() -> void:
	# Arrange — 一个能构成甩牌的域（♥ 域：对子 + 单张）
	var hand: Array = [
		Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1),
		Card.normal(S.HEART, R.ACE),
	]

	# Act — allow_dump=false 时不应出现 3 张的甩牌候选
	rc.allow_dump = false
	var no_dump := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)
	var dumps_off := no_dump.filter(func(p: Array) -> bool: return p.size() == 3)

	rc.allow_dump = true
	var with_dump := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)
	var dumps_on := with_dump.filter(func(p: Array) -> bool: return p.size() == 3)

	# Assert
	assert_eq(dumps_off.size(), 0, "allow_dump=false 不应枚举甩牌")
	assert_true(dumps_on.size() >= 1, "allow_dump=true 应枚举出整域甩牌候选")


# ============================================================
# 跟牌枚举 (lead != null)
# ============================================================

func test_follow_matches_lead_count() -> void:
	# Arrange — 首出对子（2 张），跟牌方手牌
	var lead_cards: Array = [Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1)]
	var lead := CardPattern.identify(lead_cards, RANK, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
	var hand: Array = [
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.NINE, 1),
		Card.normal(S.HEART, R.THREE),
		Card.normal(S.CLUB, R.KING),
	]

	# Act
	var plays := PlayValidator.get_legal_plays(hand, lead, TRUMP, RANK, rc, lead_cards)

	# Assert — 所有候选张数 == 首出张数(2)，且非空
	assert_true(plays.size() >= 1, "应枚举出至少一种合法跟牌")
	for p: Array in plays:
		assert_eq(p.size(), 2, "跟牌张数必须等于首出张数")


func test_follow_every_candidate_passes_validate_follow() -> void:
	# Arrange
	var lead_cards: Array = [Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1)]
	var lead := CardPattern.identify(lead_cards, RANK, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
	var lead_domain := TrumpJudge.get_suit_domain(lead_cards[0], TRUMP, RANK, rc.joker_always_trump)
	var hand: Array = [
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.NINE, 1),
		Card.normal(S.HEART, R.THREE), Card.normal(S.HEART, R.TEN),
		Card.normal(S.CLUB, R.KING),
	]

	# Act
	var plays := PlayValidator.get_legal_plays(hand, lead, TRUMP, RANK, rc, lead_cards)

	# Assert — 每个候选过 validate_follow（同源）
	for p: Array in plays:
		assert_true(
			PlayValidator.validate_follow(p, hand, 2, lead_domain, TRUMP, RANK, rc, lead),
			"跟牌候选 %s 必须通过 validate_follow" % [_repr(p)]
		)


func test_follow_strict_structure_requires_pair() -> void:
	# Arrange — 首出对子，strict_follow_structure=true，手中有该域对子 ♥9♥9
	# 则每个合法跟牌候选都必须含该对子（不许拆）
	rc.strict_follow_structure = true
	var lead_cards: Array = [Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1)]
	var lead := CardPattern.identify(lead_cards, RANK, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
	var hand: Array = [
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.NINE, 1),
		Card.normal(S.HEART, R.THREE),
	]

	# Act
	var plays := PlayValidator.get_legal_plays(hand, lead, TRUMP, RANK, rc, lead_cards)

	# Assert — 每个候选都应是 ♥9♥9 这个对子（严格跟牌不许拆对）
	for p: Array in plays:
		var pat := CardPattern.identify(p, RANK, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
		assert_eq(pat.type, CT.PAIR, "strict 模式手握对子时跟牌须为对子")


# ============================================================
# 确定性 (全序排序)
# ============================================================

func test_enumeration_is_deterministic() -> void:
	# Arrange
	var hand: Array = [
		Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1),
		Card.normal(S.HEART, R.EIGHT, 0), Card.normal(S.HEART, R.EIGHT, 1),
		Card.normal(S.CLUB, R.THREE), Card.normal(S.CLUB, R.KING),
	]

	# Act — 同输入两次调用
	var a := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)
	var b := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)

	# Assert — 逐候选逐张一致（全序排序保证确定性）
	assert_eq(a.size(), b.size(), "同输入两次枚举数量必须一致")
	for i: int in range(a.size()):
		assert_eq(a[i].size(), b[i].size(), "候选 %d 张数一致" % i)
		for j: int in range(a[i].size()):
			assert_true(a[i][j].equals(b[i][j]), "候选 %d 第 %d 张一致" % [i, j])


# ============================================================
# 跨配置 (1副/2副 × strict × allow_dump)
# ============================================================

func test_enumeration_across_configs_all_legal() -> void:
	# Arrange — 同一手牌跨配置枚举，所有候选恒合法
	var hand: Array = [
		Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1),
		Card.normal(S.CLUB, R.THREE),
	]

	for strict: bool in [true, false]:
		for dump: bool in [true, false]:
			rc.strict_follow_structure = strict
			rc.allow_dump = dump
			# Act
			var plays := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)
			# Assert
			for p: Array in plays:
				assert_not_null(
					PlayValidator.validate_lead(p, hand, TRUMP, RANK, rc),
					"strict=%s dump=%s 候选 %s 须合法" % [strict, dump, _repr(p)]
				)


# ============================================================
# 已知窄化 (ADR-0006 Consequences：甩牌 MVP 只枚举整域)
# ============================================================

func test_dump_enumeration_is_whole_domain_mvp() -> void:
	# 记录型：ADR-0006 明确甩牌 MVP 只枚举"域内全部牌"这一个甩牌候选，
	# 不枚举子集甩牌（组合大、AI 评分收益低，留 FT4）。本测试固定该已知行为，
	# 若未来扩展为子集枚举，此断言会提醒同步更新 ADR。
	# Arrange — ♥ 域可构成甩牌（对子+单张），另加一张其它域牌
	var hand: Array = [
		Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1),
		Card.normal(S.HEART, R.ACE),
		Card.normal(S.CLUB, R.THREE),
	]

	# Act
	var plays := PlayValidator.get_legal_plays(hand, null, TRUMP, RANK, rc)
	var dumps := plays.filter(func(p: Array) -> bool:
		var pat := CardPattern.identify(p, RANK, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
		return pat != null and pat.type == CT.DUMP
	)

	# Assert — 恰有 1 个甩牌候选（整个 ♥ 域 3 张），非子集
	assert_eq(dumps.size(), 1, "MVP 甩牌枚举只产出整域候选（已知窄化，见 ADR-0006）")
	if dumps.size() == 1:
		assert_eq(dumps[0].size(), 3, "整域甩牌候选含该域全部 3 张")


# ============================================================
# 性能回归 (ADR-0006 分层约束)
# ============================================================

func test_extreme_follow_enumeration_under_budget() -> void:
	# 防退化：极端手牌（一门花色占近半手牌 + n=4 拖拉机跟牌）曾用暴力组合达 649ms，
	# 域内分治后 ~61ms。固化分层约束的"极端尾部 < 100ms"红线，防未来退化回暴力。
	# Arrange — 12 张 ♥ 副牌 + 主牌若干，凑满 25 张
	var hand: Array = []
	for r: int in [2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]:
		hand.append(Card.normal(S.HEART, r, hand.size() % 2))  # 12 张 ♥
	for r: int in [2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13]:
		if hand.size() >= 25:
			break
		hand.append(Card.normal(S.SPADE, r, 0))
	var lead_cards: Array = [
		Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.SEVEN, 1),
		Card.normal(S.HEART, R.EIGHT, 0), Card.normal(S.HEART, R.EIGHT, 1),
	]
	var lead := CardPattern.identify(lead_cards, RANK, rc.tractor_allow_rank_card, rc.four_same_is_tractor)

	# Act
	var t0 := Time.get_ticks_usec()
	var plays := PlayValidator.get_legal_plays(hand, lead, TRUMP, RANK, rc, lead_cards)
	var elapsed_ms := (Time.get_ticks_usec() - t0) / 1000.0

	# Assert — 枚举非空，且未退化回暴力组合。
	# 阈值 250ms：实测 ~61ms，暴力组合曾 649ms。取 250ms 给足抗 CI 抖动余量
	# （紧贴 100ms 会因机器负载偶发 flaky），同时仍能抓住"退化回暴力(649ms)"这个真问题，
	# 且远低于 ADR-0006 红线 < 1s。分层约束的 100ms 目标见 ADR，此处是防退化护栏。
	assert_true(plays.size() >= 1, "极端手牌应枚举出合法跟牌")
	assert_lt(elapsed_ms, 250.0,
		"极端跟牌枚举不得退化回暴力组合（须 < 250ms 护栏），实测 %.1fms" % elapsed_ms)


# ============================================================
# Helpers
# ============================================================

func _repr(cards: Array) -> String:
	var parts: Array[String] = []
	for c: Card in cards:
		parts.append(c.to_string_repr() if c.has_method("to_string_repr") else str(c))
	return "[%s]" % ", ".join(parts)
