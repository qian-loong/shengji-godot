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
	state.dealer_played_ranks = [[R.TWO, R.THREE], [R.TWO]]

	state.reset(2)

	assert_eq(state.team_ranks, [R.TWO, R.TWO] as Array[int])
	assert_eq(state.current_dealer, 0)
	assert_eq(state.current_rank, R.TWO)
	assert_eq(state.round_num, 0)
	assert_true(state.is_first_game)
	assert_false(state.game_over)
	assert_eq(state.human_seat, 2)
	assert_eq(state.dealer_played_ranks, [[], []])


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
	assert_false(applied.upgrade_blocked)
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

	var applied := state.apply_settlement(result, 2)

	assert_eq(state.team_ranks[0], R.SEVEN)
	assert_eq(state.team_ranks[1], R.FOUR)
	assert_eq(state.current_dealer, 3)
	assert_eq(state.current_rank, R.FOUR)
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

func test_record_dealer_round_tracks_rank() -> void:
	state.record_dealer_round(0, R.TWO)
	state.record_dealer_round(0, R.FIVE)
	state.record_dealer_round(1, R.THREE)

	assert_true(R.TWO in state.dealer_played_ranks[0], "team0 played 2 as dealer")
	assert_true(R.FIVE in state.dealer_played_ranks[0], "team0 played 5 as dealer")
	assert_true(R.THREE in state.dealer_played_ranks[1], "team1 played 3 as dealer")
	assert_false(R.THREE in state.dealer_played_ranks[0], "team0 did NOT play 3")


func test_record_dealer_round_no_duplicates() -> void:
	state.record_dealer_round(0, R.FIVE)
	state.record_dealer_round(2, R.FIVE)

	assert_eq(state.dealer_played_ranks[0].size(), 1, "no duplicate entries")


func test_attack_upgrade_blocked_at_no_skip_rank_without_dealer() -> void:
	# Team0 at 10 (never played as dealer at 10), team1 at 3.
	# Dealer=seat1 (team1), attack=team0. Attack scores 130 → upgrade 1 level.
	# Team0 should NOT advance from 10 to J — they haven't been dealer at 10.
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.TEN, "team0 blocked at 10")
	assert_true(applied.upgrade_blocked, "upgrade was blocked")
	# P0 一致性：effective.new_rank / upgrade_levels 必须与 team_ranks 对齐。
	assert_eq(applied.new_rank, R.TEN, "effective new_rank agrees with state")
	assert_eq(applied.upgrade_levels, 0, "blocked → effective upgrade_levels == 0")
	# 提案值仍保留原样，用于展示"本来会怎么升"。
	assert_eq(applied.proposal.new_rank, R.JACK, "proposal keeps original 10→J")
	assert_eq(applied.proposal.upgrade_levels, 1)


func test_attack_upgrade_allowed_at_no_skip_rank_after_dealer() -> void:
	# Same setup as above, but team0 HAS played as dealer at 10.
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	state.record_dealer_round(0, R.TEN)
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.JACK, "team0 advances 10→J after playing as dealer")
	assert_false(applied.upgrade_blocked, "upgrade not blocked")
	assert_eq(applied.new_rank, R.JACK)


func test_dealer_upgrade_from_no_skip_rank_allowed() -> void:
	# Team0 at 5, is dealer (seat 0), plays rank 5, scores 30 → dealer upgrades 2.
	# Since team0 IS the dealer at rank 5, record it, then apply.
	state.team_ranks = [R.FIVE, R.THREE]
	state.current_dealer = 0
	state.current_rank = R.FIVE
	state.record_dealer_round(0, R.FIVE)
	var result := _settlement(30, 0, false, R.FIVE)

	var applied := state.apply_settlement(result, 0, rc)

	assert_eq(state.team_ranks[0], R.SEVEN, "team0: 5+2=7, allowed after dealer")
	assert_false(applied.upgrade_blocked)


func test_attack_blocked_at_five_never_dealer() -> void:
	# Team1 at 5, never played as dealer at 5.
	# Dealer=seat0 (team0 at 8), attack=team1. Attack scores 120 → upgrade 1.
	state.team_ranks = [R.EIGHT, R.FIVE]
	state.current_dealer = 0
	state.current_rank = R.EIGHT
	var result := _settlement(120, 0, true, R.EIGHT, R.FIVE)

	var applied := state.apply_settlement(result, 0, rc)

	assert_eq(state.team_ranks[1], R.FIVE, "team1 blocked at 5")
	assert_true(applied.upgrade_blocked)


func test_attack_blocked_at_king_never_dealer() -> void:
	# Team0 at K, never played as dealer at K.
	# Dealer=seat1 (team1 at 7), attack=team0. Attack scores 120 → upgrade 1.
	state.team_ranks = [R.KING, R.SEVEN]
	state.current_dealer = 1
	state.current_rank = R.SEVEN
	var result := _settlement(120, 1, true, R.SEVEN, R.KING)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.KING, "team0 blocked at K")
	assert_true(applied.upgrade_blocked)


func test_no_skip_constraint_does_not_affect_non_skip_ranks() -> void:
	# Team0 at 7 (not a no_skip rank), never played dealer at 7.
	# Should still be able to upgrade.
	state.team_ranks = [R.SEVEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.SEVEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.EIGHT, "team0: 7→8, non-skip rank unblocked")
	assert_false(applied.upgrade_blocked)


func test_no_skip_disabled_allows_upgrade() -> void:
	# Same as blocked case but with no_skip_enabled=false.
	rc.no_skip_enabled = false
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.JACK, "no_skip disabled → 10→J allowed")
	assert_false(applied.upgrade_blocked)


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
	# Team0 at 4, dealer=seat1 (team1 at 3). Attack 200 → 提案升 3 级 (4→5→6→7)。
	# 得分层的 apply_upgrade 已经把新级钳制到 5（因为 5 在 no_skip_ranks 且
	# 循环中间检查会 break）。所以提案 new_rank == 5。
	# 会话层必打级再检查一次 [4→5] 的路径：起点 4 不在 no_skip_ranks，可以推进；
	# 到达 5 之后循环结束，不再向前推进，因此不需要 team0 打过 5 就能落到 5。
	state.team_ranks = [R.FOUR, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(200, 1, true, R.THREE, R.FOUR)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.FIVE, "team0: 4→5 via existing no_skip + new constraint OK")
	assert_false(applied.upgrade_blocked)


## P1 一致性：必打级拦截时，effective.game_over 必须与 state.game_over 同步归零。
##
## 本场景（K→A 被拦回 K）里 proposal.game_over 本身就是 false，
## 因为 UpgradeSettlement 的 game_over 判据是 "rank_for_game_over==ACE 且 levels>0"，
## 而此处 attack_rank=K（起点是 K，不是 A）。所以这里只能验证 effective 层不被
## 提案的其它错误"感染"，不能验证"提案 true → effective false"的分歧修复。
## 后者由 test_session_controller.gd 里的 test_effective_settlement_forces_game_over_false_when_blocked
## 契约测试直接覆盖，与场景解耦。
func test_game_over_blocked_if_upgrade_blocked_at_no_skip() -> void:
	# Team0 at K (no_skip rank, never played as dealer).
	# Dealer=seat1 (team1 at 7), attack=team0 at K. Attack score=120 → upgrade 1.
	# 得分层提案：K→A（new_rank 变化，但 game_over=false）。
	# 会话层：必打级拦回 K，effective.game_over 也必须是 false。
	state.team_ranks = [R.KING, R.SEVEN]
	state.current_dealer = 1
	state.current_rank = R.SEVEN
	var result := _settlement(120, 1, true, R.SEVEN, R.KING)

	# Sanity：本场景 proposal 自身就没有 game_over（起点不是 A）。
	assert_false(result.game_over, "sanity: proposal.game_over is false when starting from K")
	assert_eq(result.new_rank, R.ACE, "sanity: proposal 想升到 A")

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.KING, "blocked at K")
	assert_false(state.game_over, "game not over because upgrade was blocked")
	assert_true(applied.upgrade_blocked)
	# P1 一致性：effective.game_over 与 state.game_over 严格一致。
	assert_false(applied.game_over, "effective.game_over synced with state")
	# 提案值透传保留，供日志复盘。
	assert_eq(applied.proposal.new_rank, R.ACE, "proposal keeps 'would-be' new_rank=A")


func test_upgrade_allowed_after_dealer_at_king() -> void:
	# Same scenario but team0 has played dealer at K.
	state.team_ranks = [R.KING, R.SEVEN]
	state.current_dealer = 1
	state.current_rank = R.SEVEN
	state.record_dealer_round(0, R.KING)
	var result := _settlement(120, 1, true, R.SEVEN, R.KING)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.ACE, "K→A allowed after dealer at K")
	assert_false(state.game_over, "reaching A is not game over; must upgrade FROM A")
	assert_false(applied.upgrade_blocked)


func test_reproduces_bug_south_north_skipped_10() -> void:
	# Reproduces the exact bug: 南北队 at 10, never dealer at 10.
	# 东(seat1) is dealer at rank 3 (东西队), attack=南北队.
	# Attack scores 130 → upgrade 1. Without fix: 10→J. With fix: stays at 10.
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	# Team0 has been dealer at 2,3,5,8 but NOT 10.
	state.record_dealer_round(0, R.TWO)
	state.record_dealer_round(0, R.THREE)
	state.record_dealer_round(0, R.FIVE)
	state.record_dealer_round(0, R.EIGHT)
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.TEN, "bug fix: team0 stays at 10")
	assert_true(applied.upgrade_blocked)
	# P0 一致性：effective.new_rank 与 team_ranks 严格一致。
	assert_eq(applied.new_rank, R.TEN, "effective new_rank agrees with team_ranks[0]")
