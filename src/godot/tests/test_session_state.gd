## Unit tests for shared multi-round SessionState.
extends GutTest

const R = Card.Rank

var rc: RuleConfig
var state: SessionState


func before_each() -> void:
	rc = RuleConfig.new()
	rc.deck_count = 2
	state = SessionState.new()
	state.reset()


func _settlement(
	attack_score: int,
	dealer: int,
	last_winner_is_attack: bool,
	current_rank: int,
	attack_rank: int = -1,
) -> UpgradeSettlement.SettlementResult:
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	return UpgradeSettlement.calculate(
		attack_score,
		[],
		dealer,
		last_winner_is_attack,
		pattern,
		current_rank,
		rc,
		attack_rank
	)


func test_reset_initializes_first_round_state() -> void:
	state.team_ranks = [R.NINE, R.JACK]
	state.current_dealer = 3
	state.current_rank = R.JACK
	state.round_num = 7
	state.is_first_game = false
	state.game_over = true

	state.reset(2)

	assert_eq(state.team_ranks, [R.TWO, R.TWO] as Array[int])
	assert_eq(state.current_dealer, 0)
	assert_eq(state.current_rank, R.TWO)
	assert_eq(state.round_num, 0)
	assert_true(state.is_first_game)
	assert_false(state.game_over)
	assert_eq(state.human_seat, 2)


func test_begin_round_uses_current_dealer_team_rank() -> void:
	state.team_ranks = [R.EIGHT, R.FIVE]
	state.current_dealer = 1

	var rank := state.begin_round_for_current_dealer()

	assert_eq(rank, R.FIVE)
	assert_eq(state.current_rank, R.FIVE)
	assert_eq(state.round_num, 1)


func test_dealer_team_upgrade_updates_dealer_team_only() -> void:
	state.team_ranks = [R.TWO, R.FIVE]
	state.current_dealer = 0
	state.current_rank = R.TWO
	var result := _settlement(30, 0, false, R.TWO)

	var applied := state.apply_settlement(result, 0)

	assert_eq(state.team_ranks[0], R.FOUR)
	assert_eq(state.team_ranks[1], R.FIVE)
	assert_eq(applied["upgrading_team"], 0)
	assert_false(state.is_first_game)


func test_attack_team_upgrade_uses_attack_own_rank() -> void:
	state.team_ranks = [R.FIVE, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(155, 1, true, R.THREE, R.FIVE)

	state.apply_settlement(result, 1)

	assert_eq(state.team_ranks[0], R.SIX)
	assert_eq(state.team_ranks[1], R.THREE)


func test_dethrone_without_upgrade_keeps_ranks_and_sets_next_dealer() -> void:
	state.team_ranks = [R.SEVEN, R.FOUR]
	state.current_dealer = 2
	state.current_rank = R.SEVEN
	var result := _settlement(100, 2, true, R.SEVEN, R.FOUR)

	state.apply_settlement(result, 2)

	assert_eq(state.team_ranks[0], R.SEVEN)
	assert_eq(state.team_ranks[1], R.FOUR)
	assert_eq(state.current_dealer, 3)
	assert_eq(state.current_rank, R.FOUR)


func test_no_dethrone_keeps_actual_dealer() -> void:
	state.team_ranks = [R.EIGHT, R.FOUR]
	state.current_dealer = 0
	state.current_rank = R.EIGHT
	var result := _settlement(70, 2, false, R.EIGHT, R.FOUR)

	state.apply_settlement(result, 2)

	assert_eq(state.current_dealer, 2)
	assert_eq(state.current_rank, R.NINE)


func test_game_over_records_winning_team_without_advancing_dealer() -> void:
	state.team_ranks = [R.ACE, R.FIVE]
	state.current_dealer = 0
	state.current_rank = R.ACE
	var result := _settlement(40, 0, false, R.ACE)

	state.apply_settlement(result, 0)

	assert_true(state.game_over)
	assert_eq(state.winning_team, 0)
	assert_eq(state.team_ranks[0], R.ACE)
	assert_eq(state.current_dealer, 0)
	assert_false(state.is_first_game)
