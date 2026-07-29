## Unit tests for shared multi-round SessionState.
extends GutTest

const R = Card.Rank

var rc: RuleConfig
var state: SessionState


func before_each() -> void:
	rc = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
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
	assert_eq(applied.upgrading_team, 0)
	assert_eq(applied.new_rank, R.FOUR, "effective new_rank agrees with team_ranks")
	assert_false(state.is_first_game)


func test_attack_team_upgrade_uses_attack_own_rank() -> void:
	state.team_ranks = [R.FIVE, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(155, 1, true, R.THREE, R.FIVE)

	var applied := state.apply_settlement(result, 1)

	assert_eq(state.team_ranks[0], R.SIX)
	assert_eq(state.team_ranks[1], R.THREE)
	assert_eq(applied.new_rank, R.SIX)
	assert_eq(applied.upgrading_team, 0)


func test_dethrone_without_upgrade_keeps_ranks_and_sets_next_dealer() -> void:
	state.team_ranks = [R.SEVEN, R.FOUR]
	state.current_dealer = 2
	state.current_rank = R.SEVEN
	var result := _settlement(100, 2, true, R.SEVEN, R.FOUR)

	var applied := state.apply_settlement(result, 2, rc)

	assert_eq(state.team_ranks[0], R.SEVEN, "defending team unchanged")
	assert_eq(state.team_ranks[1], R.FOUR, "attacking team: 100-119 = dethrone only, no upgrade")
	assert_eq(state.current_dealer, 3, "dealer dethroned, next seat")
	assert_eq(state.current_rank, R.FOUR, "follows new dealer's team rank")
	assert_eq(applied.new_dealer, 3, "effective new_dealer follows dethrone")


func test_no_dethrone_keeps_actual_dealer() -> void:
	state.team_ranks = [R.EIGHT, R.FOUR]
	state.current_dealer = 0
	state.current_rank = R.EIGHT
	var result := _settlement(70, 2, false, R.EIGHT, R.FOUR)

	var applied := state.apply_settlement(result, 2)

	assert_eq(state.current_dealer, 2)
	assert_eq(state.current_rank, R.NINE)
	assert_eq(applied.new_dealer, 2, "no dethrone → new_dealer == actual dealer")


func test_game_over_records_winning_team_without_advancing_dealer() -> void:
	state.team_ranks = [R.ACE, R.FIVE]
	state.current_dealer = 0
	state.current_rank = R.ACE
	var result := _settlement(40, 0, false, R.ACE)

	var applied := state.apply_settlement(result, 0)

	assert_true(state.game_over)
	assert_true(applied.game_over, "effective.game_over matches state.game_over")
	assert_eq(state.winning_team, 0)
	assert_eq(state.team_ranks[0], R.ACE)
	assert_eq(state.current_dealer, 0)
	assert_false(state.is_first_game)


# ============================================================
# 必打级 (no_skip dealer constraint) tests
# ============================================================

func test_attack_upgrade_at_no_skip_rank_without_dealer() -> void:
	# NEW RULE: 必打级约束仅对庄家方生效，攻方升级不受限制
	# Team0 at 10 (never played as dealer at 10), team1 at 3.
	# Dealer=seat1 (team1), attack=team0. Attack scores 130 → upgrade 1 level.
	# Team0 (攻方) CAN advance from 10 to J — 攻方不受必打级约束。
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.JACK, "team0 (攻方) advances 10→J without constraint")
	assert_eq(applied.new_rank, R.JACK, "effective new_rank agrees with state")
	assert_eq(applied.upgrade_levels, 1, "攻方正常升1级")
	assert_eq(applied.proposal.new_rank, R.JACK, "proposal matches effective")
	assert_eq(applied.proposal.upgrade_levels, 1)


func test_attack_upgrade_allowed_at_no_skip_rank() -> void:
	# 攻方升级不受必打级约束，无需打过庄即可跨过 no_skip_rank
	# Team0 at 10, team1 at 3.
	# Dealer=seat1 (team1), attack=team0. Attack scores 130 → upgrade 1 level.
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	# 不需要 record_dealer_round — 攻方不受约束
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.JACK, "team0 (攻方) advances 10→J")
	assert_eq(applied.new_rank, R.JACK)


func test_dealer_upgrade_from_no_skip_rank_allowed() -> void:
	# Team0 at 5, is dealer (seat 0), plays rank 5, scores 30 → dealer upgrades 2.
	# 庄家方在自己的级别上坐庄，自动记录，可以升级。
	state.team_ranks = [R.FIVE, R.THREE]
	state.current_dealer = 0
	state.current_rank = R.FIVE
	var result := _settlement(30, 0, false, R.FIVE)

	var applied := state.apply_settlement(result, 0, rc)

	assert_eq(state.team_ranks[0], R.SEVEN, "team0: 5+2=7, allowed after dealer")


func test_attack_at_five_without_dealer() -> void:
	# NEW RULE: 攻方升级不受必打级约束
	# Team1 at 5, never played as dealer at 5.
	# Dealer=seat0 (team0 at 8), attack=team1. Attack scores 120 → upgrade 1.
	# Team1 (攻方) CAN advance from 5 to 6 — 攻方不受限制。
	state.team_ranks = [R.EIGHT, R.FIVE]
	state.current_dealer = 0
	state.current_rank = R.EIGHT
	var result := _settlement(120, 0, true, R.EIGHT, R.FIVE)

	var applied := state.apply_settlement(result, 0, rc)

	assert_eq(state.team_ranks[1], R.SIX, "team1 (攻方) advances 5→6")


func test_attack_at_king_without_dealer() -> void:
	# NEW RULE: 攻方升级不受必打级约束
	# Team0 at K, never played as dealer at K.
	# Dealer=seat1 (team1 at 7), attack=team0. Attack scores 120 → upgrade 1.
	# Team0 (攻方) CAN advance from K to A — 攻方不受限制。
	state.team_ranks = [R.KING, R.SEVEN]
	state.current_dealer = 1
	state.current_rank = R.SEVEN
	var result := _settlement(120, 1, true, R.SEVEN, R.KING)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.ACE, "team0 (攻方) advances K→A")


func test_no_skip_constraint_does_not_affect_non_skip_ranks() -> void:
	# Team0 at 7 (not a no_skip rank), never played dealer at 7.
	# Should still be able to upgrade.
	state.team_ranks = [R.SEVEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.SEVEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.EIGHT, "team0: 7→8, non-skip rank unblocked")


func test_no_skip_disabled_allows_upgrade() -> void:
	# Same as blocked case but with no_skip_enabled=false.
	rc.no_skip_enabled = false
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.JACK, "no_skip disabled → 10→J allowed")


func test_no_rule_config_skips_constraint() -> void:
	# Calling apply_settlement without rule_config (backward compat).
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1)

	assert_eq(state.team_ranks[0], R.JACK, "no rule_config → no constraint → 10→J")
	assert_eq(applied.new_rank, R.JACK)


func test_multi_level_attack_upgrade_stops_at_first_unplayed_no_skip() -> void:
	# 启用必打级约束
	rc.no_skip_enabled = true
	rc.no_skip_ranks = [R.FIVE, R.TEN, R.KING]

	# Team0 at 4, dealer=seat1 (team1 at 3). Attack 200 → 提案升 3 级。
	# UpgradeSettlement.apply_upgrade(4, 3) 会在必打级5处停止（还有2级未升，不能跨越）。
	state.team_ranks = [R.FOUR, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(200, 1, true, R.THREE, R.FOUR)

	# Sanity check: UpgradeSettlement 应该已经钳制到 5
	assert_eq(result.new_rank, R.FIVE, "sanity: UpgradeSettlement 在 5 处停止")

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.FIVE, "team0 (攻方): 4→5 (UpgradeSettlement 层已钳制)")


## P1 一致性：攻方升级不受必打级约束。
##
## 本场景（K→A）攻方升级不受必打级限制，正常到达 A。
## proposal.game_over 本身就是 false（起点是 K，不是 A），所以这里只能验证
## effective 层不被提案的其它错误"感染"。
func test_attack_upgrade_at_king_no_constraint() -> void:
	# NEW RULE: 攻方升级不受必打级约束
	# Team0 at K (no_skip rank, never played as dealer).
	# Dealer=seat1 (team1 at 7), attack=team0 at K. Attack score=120 → upgrade 1.
	# 攻方从 K→A 不受限制，正常升级。
	state.team_ranks = [R.KING, R.SEVEN]
	state.current_dealer = 1
	state.current_rank = R.SEVEN
	var result := _settlement(120, 1, true, R.SEVEN, R.KING)

	# Sanity：本场景 proposal 自身就没有 game_over（起点不是 A）。
	assert_false(result.game_over, "sanity: proposal.game_over is false when starting from K")
	assert_eq(result.new_rank, R.ACE, "sanity: proposal 想升到 A")

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.ACE, "team0 (攻方) advances K→A")
	assert_false(state.game_over, "game not over yet (need to win at A)")
	assert_false(applied.game_over, "effective.game_over synced with state")
	# 提案值透传保留，供日志复盘。
	assert_eq(applied.proposal.new_rank, R.ACE, "proposal keeps 'would-be' new_rank=A")


func test_reproduces_bug_south_north_skipped_10() -> void:
	# NEW RULE: 攻方升级不受必打级约束
	# 南北队 at 10, never dealer at 10.
	# 东(seat1) is dealer at rank 3 (东西队), attack=南北队.
	# Attack scores 130 → upgrade 1. 攻方可以 10→J。
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.JACK, "team0 (攻方) advances 10→J")
	assert_eq(applied.new_rank, R.JACK, "effective new_rank agrees with team_ranks[0]")
