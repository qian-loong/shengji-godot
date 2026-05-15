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
