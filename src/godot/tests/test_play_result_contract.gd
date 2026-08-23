## submit_play 的 played_cards 契约
##
## 甩牌失败时引擎会把出牌降级为「只出最小的一张单牌」，但 UI 若仍按玩家
## 原本选中的牌渲染，就会出现"界面出两张、逻辑只出一张，墩结束后多的牌
## 又回到手里"的错觉（真机实测反馈）。
## submit_play 因此必须回传实际打出的 played_cards，所有渲染方以它为准。
extends GutTest

const R := Card.Rank
const S := Card.Suit


func _controller_with_dump_scenario() -> SessionController:
	var rc := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	rc.allow_dump = true
	var controller := SessionController.new()
	controller.start_new_session(rc, null, 0)
	return controller


func test_played_cards_present_on_normal_play() -> void:
	# 正常出牌时也要有该字段，UI 才能无条件读取
	var controller := _controller_with_dump_scenario()
	controller.start_round(42)
	controller.resolve_no_bid_default()
	var bury := controller.get_bury_context()
	if bury.get("ok", false):
		var merged: Array = controller.game_round.get_dealer_hand_with_bottom()
		var indices: Array[int] = []
		for i: int in range(controller.rule_config.bottom_size):
			indices.append(i)
		controller.submit_bury(indices)

	var turn := controller.get_current_turn_context()
	if not turn.get("ok", false):
		pending("牌局未进入出牌阶段")
		return

	var seat: int = turn["seat"]
	var hand: Array = turn["hand"]
	var result := controller.submit_play(seat, [hand[0]])

	assert_true(result.get("ok", false), "单张首出应合法")
	assert_true(result.has("played_cards"), "返回值必须带 played_cards")
	var played: Array = result["played_cards"]
	assert_eq(played.size(), 1)
	assert_true((played[0] as Card).equals(hand[0]), "正常出牌时应原样回传")


func test_dump_failure_reports_downgraded_single() -> void:
	# 直接验证挑战层：甩牌失败时给出的 fallback 必须是选中牌里最小的那张
	var rc := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var dump := [
		Card.normal(S.HEART, R.QUEEN), Card.normal(S.HEART, R.QUEEN),
		Card.normal(S.HEART, R.JACK),
	]
	var others := [
		[Card.normal(S.HEART, R.KING), Card.normal(S.HEART, R.KING)],
		[], [],
	]

	var challenge := PlayValidator.challenge_dump(dump, others, S.SPADE, R.TWO, rc)

	assert_false(challenge["ok"], "对 Q 被对 K 压，甩牌应失败")
	var fallback: Card = challenge["fallback_card"]
	assert_true(fallback.equals(Card.normal(S.HEART, R.JACK)),
		"应降级为最小的 ♥J，实际 %s" % fallback.to_string_repr())
	assert_false(str(challenge["reason"]).is_empty(), "应给出可展示的失败原因")


func test_successful_dump_keeps_all_cards() -> void:
	var rc := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	# ♥A♥A♥K：两张 ♥A 都在自己手上，对手拿不出更大的
	var dump := [
		Card.normal(S.HEART, R.ACE), Card.normal(S.HEART, R.ACE),
		Card.normal(S.HEART, R.KING),
	]
	var others := [[Card.normal(S.HEART, R.QUEEN)], [], []]

	var challenge := PlayValidator.challenge_dump(dump, others, S.SPADE, R.TWO, rc)

	assert_true(challenge["ok"], "顶端牌甩牌应恒合法")
	assert_null(challenge["fallback_card"], "成功时无需降级")
