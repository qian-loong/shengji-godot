## Unit tests for SessionController skeleton.
extends GutTest

const R = Card.Rank

var rc: RuleConfig
var logger: GameLogger
var controller: SessionController


func before_each() -> void:
	rc = RuleConfig.new()
	rc.deck_count = 2
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = true
	rc.allow_dump = false
	rc.strict_follow_structure = true
	logger = GameLogger.new(true)
	controller = SessionController.new()
	controller.start_new_session(rc, logger, 0)


func test_start_round_sets_up_game_round_with_fixed_seed() -> void:
	var result := controller.start_round(12345)

	assert_true(result["ok"])
	assert_eq(result["phase"], "bidding")
	assert_eq(controller.current_phase, "bidding")
	assert_eq(controller.state.round_num, 1)
	assert_eq(controller.state.current_rank, R.TWO)
	assert_not_null(controller.game_round)
	assert_eq(controller.game_round.dealer_seat, 0)
	assert_eq(controller.game_round.current_rank, R.TWO)
	assert_eq(controller.game_round.get_hand_size(0), rc.hand_size)
	assert_eq(controller.game_round.bottom.size(), rc.bottom_size)


func test_start_round_records_logger_metadata() -> void:
	controller.start_round(23456)

	var snapshot := logger.get_log()
	assert_eq(snapshot["rule_config"]["deck_count"], 2)
	assert_eq(snapshot["rounds"].size(), 0, "round is not ended yet")

	var saved := logger.to_json(false)
	assert_true(saved.contains("\"round_num\":1"))
	assert_true(saved.contains("\"seed\":23456"))


func test_sync_rank_to_actual_dealer_updates_rule_round_and_logger() -> void:
	controller.state.team_ranks = [R.EIGHT, R.FIVE]
	controller.state.current_dealer = 0
	controller.start_round(34567)
	controller.game_round.set_no_bid_default(1)

	var rank := controller.sync_rank_to_actual_dealer()

	assert_eq(rank, R.FIVE)
	assert_eq(controller.state.current_rank, R.FIVE)
	assert_eq(controller.rule_config.current_rank, R.FIVE)
	assert_eq(controller.game_round.current_rank, R.FIVE)
	assert_true(logger.to_json(false).contains("\"rank\":5"))


func test_finish_round_uses_attack_team_own_rank() -> void:
	controller.state.team_ranks = [R.FIVE, R.THREE]
	controller.state.current_dealer = 1
	controller.start_round(45678)
	_force_round_ready_for_settlement(controller.game_round, 1, true, 155)

	var result := controller.finish_round()

	assert_true(result["ok"])
	assert_eq(result["phase"], "round_end")
	assert_eq(result["upgrading_team"], 0)
	assert_eq(controller.state.team_ranks[0], R.SIX)
	assert_eq(controller.state.team_ranks[1], R.THREE)
	assert_false(controller.state.is_first_game)
	assert_eq(controller.state.current_dealer, 2)


func test_finish_round_rejects_second_finish() -> void:
	controller.start_round(56789)
	_force_round_ready_for_settlement(controller.game_round, 0, false, 70)

	var first := controller.finish_round()
	var second := controller.finish_round()

	assert_true(first["ok"])
	assert_false(second["ok"])
	assert_eq(second["error"], "round_already_finished")


func test_get_bidding_context_uses_seat_team_rank() -> void:
	controller.state.team_ranks = [R.EIGHT, R.FIVE]
	controller.start_round(11111)

	var context := controller.get_bidding_context(1)

	assert_true(context["ok"])
	assert_eq(context["seat"], 1)
	assert_eq(context["bid_rank"], R.FIVE)
	assert_true(context["available_bids"] is Array)


func test_submit_bid_syncs_rank_to_actual_dealer_and_enters_burying() -> void:
	controller.state.team_ranks = [R.EIGHT, R.FIVE]
	controller.state.current_dealer = 0
	controller.start_round(22222)
	var decl := TrumpBidding.BidDeclaration.new(1, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.HEART)

	var result := controller.submit_bid_or_pass(1, decl)

	assert_true(result["ok"])
	assert_eq(result["phase"], "burying")
	assert_eq(controller.current_phase, "burying")
	assert_eq(controller.game_round.dealer_seat, 1)
	assert_eq(controller.state.current_rank, R.FIVE)
	assert_eq(controller.rule_config.current_rank, R.FIVE)
	assert_eq(controller.game_round.current_rank, R.FIVE)


func test_resolve_no_bid_default_keeps_current_dealer_and_enters_burying() -> void:
	controller.state.current_dealer = 2
	controller.start_round(33333)

	var result := controller.resolve_no_bid_default()

	assert_true(result["ok"])
	assert_eq(result["phase"], "burying")
	assert_eq(controller.game_round.dealer_seat, 2)
	assert_eq(controller.game_round.trump_suit, -1)
	assert_eq(controller.current_phase, "burying")


func test_submit_bury_executes_bury_and_enters_playing() -> void:
	controller.start_round(44444)
	controller.resolve_no_bid_default()
	var context := controller.get_bury_context()
	var indices := AIPlayer.decide_bury(
		context["merged_hand"],
		context["bottom_size"],
		context["trump_suit"],
		context["current_rank"],
		rc
	)

	var result := controller.submit_bury(indices)

	assert_true(result["ok"])
	assert_eq(result["phase"], "playing")
	assert_eq(controller.current_phase, "playing")
	assert_eq(controller.game_round.get_hand_size(controller.game_round.dealer_seat), rc.hand_size)
	assert_eq(controller.game_round.buried_bottom.size(), rc.bottom_size)


func test_submit_play_rejects_wrong_turn() -> void:
	_prepare_playing_round(55555)
	var started := controller.begin_trick()
	var wrong_seat: int = (started["lead_seat"] + 1) % 4
	var card: Card = controller.game_round.get_hand(wrong_seat)[0]

	var result := controller.submit_play(wrong_seat, [card])

	assert_false(result["ok"])
	assert_eq(result["error"], "wrong_turn")


func test_submit_play_rejects_invalid_follow_without_mutating_hand() -> void:
	_prepare_known_follow_round()
	controller.begin_trick()
	var lead_card := Card.normal(Card.Suit.CLUB, R.THREE)
	var follow_card := Card.normal(Card.Suit.HEART, R.FIVE)

	var lead_result := controller.submit_play(0, [lead_card])
	var before_size := controller.game_round.get_hand_size(1)
	var follow_result := controller.submit_play(1, [follow_card])

	assert_true(lead_result["ok"])
	assert_false(follow_result["ok"])
	assert_eq(follow_result["error"], "invalid_follow")
	assert_eq(controller.game_round.get_hand_size(1), before_size)


func test_submit_play_resolves_trick_after_four_valid_plays() -> void:
	_prepare_known_follow_round()
	controller.begin_trick()

	var r1 := controller.submit_play(0, [Card.normal(Card.Suit.CLUB, R.THREE)])
	var r2 := controller.submit_play(1, [Card.normal(Card.Suit.CLUB, R.FOUR)])
	var r3 := controller.submit_play(2, [Card.normal(Card.Suit.CLUB, R.FIVE)])
	var r4 := controller.submit_play(3, [Card.normal(Card.Suit.CLUB, R.SIX)])

	assert_true(r1["ok"])
	assert_false(r1["trick_complete"])
	assert_true(r2["ok"])
	assert_true(r3["ok"])
	assert_true(r4["ok"])
	assert_true(r4["trick_complete"])
	assert_eq(r4["result"]["winner"], 3)
	assert_eq(controller.game_round.get_hand_size(0), 0)


func test_automatic_controller_path_finishes_round_and_updates_state() -> void:
	controller.state.team_ranks = [R.TWO, R.THREE]
	controller.state.current_dealer = 0
	controller.start_round(77777)
	controller.resolve_no_bid_default()
	var bury_context := controller.get_bury_context()
	var indices := AIPlayer.decide_bury(
		bury_context["merged_hand"],
		bury_context["bottom_size"],
		bury_context["trump_suit"],
		bury_context["current_rank"],
		rc
	)
	controller.submit_bury(indices)

	var safety := 0
	while controller.game_round.get_hand_size(0) > 0 and safety < 40:
		var started := controller.begin_trick()
		assert_true(started["ok"])
		for _i: int in range(4):
			var turn := controller.get_current_turn_context()
			var cards := AIPlayer.decide_play(
				turn["seat"],
				turn["hand"],
				turn["lead_info"],
				turn["game_state"],
				rc
			)
			var submitted := controller.submit_play(turn["seat"], cards)
			assert_true(submitted["ok"])
		safety += 1

	assert_lt(safety, 40)
	var finished := controller.finish_round()
	assert_true(finished["ok"])
	assert_false(controller.state.is_first_game)
	assert_true(controller.current_phase in ["round_end", "game_over"])
	assert_eq(logger.get_log()["rounds"].size(), 1)


func _force_round_ready_for_settlement(
	round: GameRound,
	dealer: int,
	last_winner_is_attack: bool,
	attack_score: int,
) -> void:
	round.dealer_seat = dealer
	round.dealer_team = [dealer, (dealer + 2) % 4]
	round.attack_team = []
	for seat: int in range(4):
		if seat not in round.dealer_team:
			round.attack_team.append(seat)
	round.buried_bottom = []
	round.last_trick_pattern = CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	round.last_trick_winner = round.attack_team[0] if last_winner_is_attack else round.dealer_team[0]
	round.score_tracker = ScoreTracker.new(rc.total_score)
	while attack_score >= 10:
		round.score_tracker.record_trick([Card.normal(Card.Suit.SPADE, R.TEN)], true)
		attack_score -= 10
	if attack_score >= 5:
		round.score_tracker.record_trick([Card.normal(Card.Suit.SPADE, R.FIVE)], true)


func _prepare_playing_round(seed_value: int) -> void:
	controller.start_round(seed_value)
	controller.resolve_no_bid_default()
	var context := controller.get_bury_context()
	var indices := AIPlayer.decide_bury(
		context["merged_hand"],
		context["bottom_size"],
		context["trump_suit"],
		context["current_rank"],
		rc
	)
	controller.submit_bury(indices)


func _prepare_known_follow_round() -> void:
	controller.start_round(66666)
	controller.resolve_no_bid_default()
	controller.current_phase = "playing"
	controller.game_round.current_lead_seat = 0
	controller.game_round.hands = [
		[Card.normal(Card.Suit.CLUB, R.THREE)],
		[Card.normal(Card.Suit.CLUB, R.FOUR), Card.normal(Card.Suit.HEART, R.FIVE)],
		[Card.normal(Card.Suit.CLUB, R.FIVE)],
		[Card.normal(Card.Suit.CLUB, R.SIX)],
	]
	controller.game_round.trump_suit = -1
	controller.game_round.current_rank = R.TWO
	controller.state.current_rank = R.TWO
	controller.rule_config.current_rank = R.TWO
