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


# ============================================================
# Counter-bid tests (counter-bid-plan.md §5 step 3)
# Covers GDD §4 reverse-bid: counter window, eligibility, strength,
# at-most-once, dealer-position invariance, re-bury bottom transfer.
# ============================================================


## Drive controller into "burying" phase with a chosen dealer + bid (first
## bury, before any counter). Bypasses real hand validation by injecting bid
## directly via process_bid, which doesn't check seat ownership.
func _setup_at_burying(
	is_first_game: bool,
	dealer_seat: int,
	bid_type: int,
	bid_suit: int,
	seed_value: int = 99999,
) -> void:
	controller.state.is_first_game = is_first_game
	controller.state.current_dealer = dealer_seat
	controller.start_round(seed_value)
	if bid_type == TrumpBidding.BidType.NONE:
		controller.resolve_no_bid_default()
	else:
		var decl := TrumpBidding.BidDeclaration.new(dealer_seat, bid_type, bid_suit)
		controller.submit_bid_or_pass(dealer_seat, decl)
	assert_eq(controller.current_phase, "burying")


func _dealer_burys_and_advance() -> Array:
	var ctx := controller.get_bury_context()
	var indices := AIPlayer.decide_bury(
		ctx["merged_hand"],
		ctx["bottom_size"],
		ctx["trump_suit"],
		ctx["current_rank"],
		rc
	)
	controller.submit_bury(indices)
	return indices


func test_counter_window_skipped_on_first_game() -> void:
	_setup_at_burying(true, 0, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.HEART)
	_dealer_burys_and_advance()

	assert_eq(controller.current_phase, "playing")
	assert_true(controller.state.counter_attempted)


func test_counter_window_skipped_on_pair_joker_bid() -> void:
	# Non-first-game; dealer plays 公主 (PAIR_JOKER, suit = -1) — cannot be countered.
	_setup_at_burying(false, 0, TrumpBidding.BidType.PAIR_JOKER, -1)
	_dealer_burys_and_advance()

	assert_eq(controller.current_phase, "playing")
	assert_true(controller.state.counter_attempted)


func test_counter_window_skipped_on_no_bid() -> void:
	# Non-first-game with 公主局（no bid declared）— cannot be countered.
	_setup_at_burying(false, 0, TrumpBidding.BidType.NONE, -1)
	_dealer_burys_and_advance()

	assert_eq(controller.current_phase, "playing")
	assert_true(controller.state.counter_attempted)


func test_counter_succeeds_with_stronger_bid() -> void:
	# Non-first-game; dealer 0 (team 0,2) bids SINGLE_RANK ♥; attacker 1 counters with PAIR_RANK ♠.
	_setup_at_burying(false, 0, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.HEART)
	_dealer_burys_and_advance()

	assert_eq(controller.current_phase, "counter_window")
	assert_eq(controller.get_current_counter_seat(), 1)

	var counter_decl := TrumpBidding.BidDeclaration.new(1, TrumpBidding.BidType.PAIR_RANK, Card.Suit.SPADE)
	var result := controller.submit_counter_or_pass(1, counter_decl)

	assert_true(result["ok"])
	assert_true(result["counter_made"])
	assert_eq(result["counter_seat"], 1)
	assert_eq(controller.current_phase, "burying")
	assert_true(controller.state.counter_attempted)
	# Trump replaced; dealer position invariants preserved.
	assert_eq(controller.game_round.trump_suit, Card.Suit.SPADE)
	assert_eq(controller.game_round.dealer_seat, 0)
	assert_eq(controller.game_round.current_lead_seat, 0)
	assert_eq(controller.game_round.bury_seat, 1)
	assert_eq(controller.game_round.counter_seat, 1)


func test_counter_rejected_with_equal_strength() -> void:
	_setup_at_burying(false, 0, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.HEART)
	_dealer_burys_and_advance()

	var counter_decl := TrumpBidding.BidDeclaration.new(1, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.SPADE)
	var result := controller.submit_counter_or_pass(1, counter_decl)

	assert_false(result["ok"])
	assert_eq(result["error"], "counter_not_stronger")
	# Window stays open; no state change.
	assert_eq(controller.current_phase, "counter_window")
	assert_eq(controller.game_round.trump_suit, Card.Suit.HEART)


func test_counter_rejected_with_weaker_bid() -> void:
	# Dealer JOKER_RANK (strength 3); attacker tries SINGLE_RANK (strength 1) — weaker.
	_setup_at_burying(false, 0, TrumpBidding.BidType.JOKER_RANK, Card.Suit.HEART)
	_dealer_burys_and_advance()

	var counter_decl := TrumpBidding.BidDeclaration.new(1, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.SPADE)
	var result := controller.submit_counter_or_pass(1, counter_decl)

	assert_false(result["ok"])
	assert_eq(result["error"], "counter_not_stronger")


func test_counter_rejected_from_dealer_team() -> void:
	# Dealer 0 → dealer_team = {0, 2}; attack_team = {1, 3}.
	# counter_seat_order should never include dealer-team seats.
	_setup_at_burying(false, 0, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.HEART)
	_dealer_burys_and_advance()

	assert_eq(controller.current_phase, "counter_window")
	assert_eq(controller.counter_seat_order, [1, 3])
	assert_false(0 in controller.counter_seat_order)
	assert_false(2 in controller.counter_seat_order)

	# Manually attempting to counter from dealer-team seat 2 is rejected as
	# wrong_counter_seat (current poll cursor points at 1).
	var bad_decl := TrumpBidding.BidDeclaration.new(2, TrumpBidding.BidType.PAIR_RANK, Card.Suit.SPADE)
	var result := controller.submit_counter_or_pass(2, bad_decl)
	assert_false(result["ok"])
	assert_eq(result["error"], "wrong_counter_seat")


func test_counter_at_most_once_per_round() -> void:
	# After a successful counter + reburial, phase becomes "playing"; submitting
	# another counter is rejected with not_counter_window (no second window opens).
	_setup_at_burying(false, 0, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.HEART)
	_dealer_burys_and_advance()

	var counter_decl := TrumpBidding.BidDeclaration.new(1, TrumpBidding.BidType.PAIR_RANK, Card.Suit.SPADE)
	controller.submit_counter_or_pass(1, counter_decl)
	# Counter winner re-buries.
	_dealer_burys_and_advance()

	assert_eq(controller.current_phase, "playing")
	assert_true(controller.state.counter_attempted)

	var second_decl := TrumpBidding.BidDeclaration.new(3, TrumpBidding.BidType.JOKER_RANK, Card.Suit.CLUB)
	var second_result := controller.submit_counter_or_pass(3, second_decl)
	assert_false(second_result["ok"])
	assert_eq(second_result["error"], "not_counter_window")


func test_counter_preserves_dealer_lead_rank() -> void:
	# D1 invariants: dealer_seat / dealer_team / attack_team / current_lead_seat
	# / current_rank all unchanged after a successful counter.
	controller.state.team_ranks = [Card.Rank.EIGHT, Card.Rank.FIVE]
	_setup_at_burying(false, 0, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.HEART)
	_dealer_burys_and_advance()

	var dealer_before: int = controller.game_round.dealer_seat
	var lead_before: int = controller.game_round.current_lead_seat
	var rank_before: int = controller.state.current_rank
	var dealer_team_before: Array = controller.game_round.dealer_team.duplicate()
	var attack_team_before: Array = controller.game_round.attack_team.duplicate()

	var counter_decl := TrumpBidding.BidDeclaration.new(1, TrumpBidding.BidType.PAIR_RANK, Card.Suit.SPADE)
	controller.submit_counter_or_pass(1, counter_decl)

	assert_eq(controller.game_round.dealer_seat, dealer_before)
	assert_eq(controller.game_round.current_lead_seat, lead_before)
	assert_eq(controller.state.current_rank, rank_before)
	assert_eq(controller.game_round.dealer_team, dealer_team_before)
	assert_eq(controller.game_round.attack_team, attack_team_before)


func test_counter_re_bury_uses_dealer_buried_as_new_bottom() -> void:
	# After successful counter:
	#   - bottom = the 8 cards dealer had buried (handed off)
	#   - buried_bottom = []
	#   - dealer hand size = 25 (unchanged)
	#   - counter winner hand size = 25 (unchanged)
	#   - bury_seat = counter winner
	# After counter winner buries 8:
	#   - buried_bottom.size() = 8
	#   - counter winner hand size = 25
	#   - dealer hand size still = 25
	_setup_at_burying(false, 0, TrumpBidding.BidType.SINGLE_RANK, Card.Suit.HEART)
	var dealer_buried: Array = _dealer_burys_and_advance()  # noqa: unused
	dealer_buried = dealer_buried  # silence unused
	var dealer_hand_after_bury: int = controller.game_round.get_hand_size(0)
	var attacker_hand_at_window: int = controller.game_round.get_hand_size(1)
	var dealer_buried_bottom_snapshot: Array = controller.game_round.buried_bottom.duplicate()

	var counter_decl := TrumpBidding.BidDeclaration.new(1, TrumpBidding.BidType.PAIR_RANK, Card.Suit.SPADE)
	controller.submit_counter_or_pass(1, counter_decl)

	# Right after counter applied: dealer hand untouched; buried_bottom emptied;
	# new bottom = previously buried 8.
	assert_eq(controller.game_round.get_hand_size(0), dealer_hand_after_bury)
	assert_eq(controller.game_round.get_hand_size(1), attacker_hand_at_window)
	assert_eq(controller.game_round.bottom.size(), rc.bottom_size)
	assert_eq(controller.game_round.buried_bottom.size(), 0)
	# Bottom transferred verbatim from dealer's buried_bottom snapshot.
	assert_eq(controller.game_round.bottom.size(), dealer_buried_bottom_snapshot.size())
	for i: int in range(dealer_buried_bottom_snapshot.size()):
		assert_true(controller.game_round.bottom[i].equals(dealer_buried_bottom_snapshot[i]))

	# Counter winner re-buries; ends with same hand size as a normal post-bury.
	_dealer_burys_and_advance()
	assert_eq(controller.current_phase, "playing")
	assert_eq(controller.game_round.get_hand_size(1), rc.hand_size)
	assert_eq(controller.game_round.get_hand_size(0), rc.hand_size)
	assert_eq(controller.game_round.buried_bottom.size(), rc.bottom_size)


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
