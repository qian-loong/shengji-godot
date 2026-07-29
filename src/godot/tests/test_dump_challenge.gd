## Unit tests for PlayValidator.challenge_dump
## Validates: F1 card-types.md §2.3（甩牌最大性与失败降级）
extends GutTest

const R := Card.Rank
const S := Card.Suit


func _config() -> RuleConfig:
	var rc := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	rc.allow_dump = true
	return rc


## 主♠、级2 ⇒ ♥ 是普通副牌域
func _challenge(dump: Array, others: Array) -> Dictionary:
	return PlayValidator.challenge_dump(dump, others, S.SPADE, R.TWO, _config())


func test_dump_of_top_cards_passes() -> void:
	# Arrange: 甩 ♥A♥A♥K —— 两张 ♥A 都在自己手里，对手拿不出更大的
	var dump := [
		Card.normal(S.HEART, R.ACE), Card.normal(S.HEART, R.ACE),
		Card.normal(S.HEART, R.KING),
	]
	var others := [
		[Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.QUEEN)],
		[Card.normal(S.HEART, R.JACK)],
		[],
	]

	# Act
	var result := _challenge(dump, others)

	# Assert
	assert_true(result["ok"], "对 A 无解、单 K 也无更大者，应恒合法")


func test_dump_kka_passes_because_ace_is_consumed() -> void:
	# ♥K♥K♥A：占掉一张 ♥A 后，对手凑不出 ♥A♥A 来压对 K
	var dump := [
		Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING),
		Card.normal(S.HEART, R.ACE),
	]
	var others := [
		[Card.normal(S.HEART, R.ACE)],  # 仅剩的另一张 ♥A
		[Card.normal(S.HEART, R.QUEEN), Card.normal(S.HEART, R.QUEEN)],
		[],
	]

	var result := _challenge(dump, others)

	assert_true(result["ok"], "对 K 只可能被对 A 压，而 ♥A 只剩 1 张")


func test_dump_fails_when_pair_is_beatable() -> void:
	# 甩 ♥Q♥Q♥J，对手握 ♥K♥K ⇒ 对 Q 不是最大
	var dump := [
		Card.normal(S.HEART, R.QUEEN), Card.normal(S.HEART, R.QUEEN),
		Card.normal(S.HEART, R.JACK),
	]
	var others := [
		[Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING)],
		[], [],
	]

	var result := _challenge(dump, others)

	assert_false(result["ok"], "对手有更大的对子，甩牌应失败")


func test_dump_fails_when_single_is_beatable() -> void:
	# 甩 ♥A♥A♥J，对手握 ♥K 单张 ⇒ 单 J 不是最大
	var dump := [
		Card.normal(S.HEART, R.ACE), Card.normal(S.HEART, R.ACE),
		Card.normal(S.HEART, R.JACK),
	]
	var others := [
		[Card.normal(S.HEART, R.KING)],
		[], [],
	]

	var result := _challenge(dump, others)

	assert_false(result["ok"], "对手单张 ♥K 大于 ♥J，甩牌应失败")


func test_failed_dump_falls_back_to_smallest_card() -> void:
	# GDD：失败后只出选中牌里最小的一张
	var dump := [
		Card.normal(S.HEART, R.QUEEN), Card.normal(S.HEART, R.QUEEN),
		Card.normal(S.HEART, R.JACK),
	]
	var others := [
		[Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING)],
		[], [],
	]

	var result := _challenge(dump, others)

	assert_false(result["ok"])
	var fallback: Card = result["fallback_card"]
	assert_true(fallback.equals(Card.normal(S.HEART, R.JACK)),
		"应降级为最小的 ♥J，实际 %s" % fallback.to_string_repr())


func test_equal_rank_does_not_challenge() -> void:
	# GDD 原文是"没有比它更大的"——相等不构成挑战。
	#
	# 要单独验证这一点，必须让甩牌的**最小分量恰好等于**对手的最大牌：
	# 甩 ♥A♥A♥K，对手仅剩 ♥K。对 A 无人可敌；单 K 与对手的 ♥K 相等，
	# 相等不算更大，因此整手甩牌成立。
	var dump := [
		Card.normal(S.HEART, R.ACE), Card.normal(S.HEART, R.ACE),
		Card.normal(S.HEART, R.KING),
	]
	var others := [
		[Card.normal(S.HEART, R.KING)],  # 与甩出的单 ♥K 相等
		[], [],
	]

	var result := _challenge(dump, others)

	assert_true(result["ok"], "对手持有相同点数不算更大")


func test_dump_fails_when_any_component_is_beatable() -> void:
	# 只要**任一**分量不是最大就整手失败：♥A 无敌，但单 ♥Q 会被对手 ♥K 压
	var dump := [
		Card.normal(S.HEART, R.ACE), Card.normal(S.HEART, R.ACE),
		Card.normal(S.HEART, R.QUEEN),
	]
	var others := [
		[Card.normal(S.HEART, R.KING)],
		[], [],
	]

	var result := _challenge(dump, others)

	assert_false(result["ok"], "单 ♥Q 被 ♥K 压，整手甩牌失败")


func test_no_opponent_cards_in_domain_passes() -> void:
	# 该域已被打空，无人可挑战
	var dump := [
		Card.normal(S.HEART, R.FIVE), Card.normal(S.HEART, R.FOUR),
		Card.normal(S.HEART, R.THREE),
	]
	var others := [
		[Card.normal(S.CLUB, R.ACE)],
		[Card.normal(S.DIAMOND, R.KING)],
		[],
	]

	var result := _challenge(dump, others)

	assert_true(result["ok"], "对手手中没有该域的牌，甩牌必然成立")
