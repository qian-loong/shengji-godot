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
	# 攻方按自己的队级升级，而不是本局级牌（current_rank=3）。
	# 起点特意选非必打级的 6，免得和必打级约束纠缠——那条规则有专门用例。
	state.team_ranks = [R.SIX, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(155, 1, true, R.THREE, R.SIX)

	var applied := state.apply_settlement(result, 1)

	assert_eq(state.team_ranks[0], R.SEVEN)
	assert_eq(state.team_ranks[1], R.THREE)
	assert_eq(applied.new_rank, R.SEVEN)
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
# 必打级 (no_skip) tests
#
# 语义：必打级必须「坐庄打过」才能升走。一队之所以还停在某级，正是因为
# 还没成功打过它——打过并守住就升走了。所以：
#   庄家方升级 → 起点是本局刚打完并守住的级 → 可以直接升走
#   攻方升级   → 起点是自己那一级但本局没人打 → 是必打级就停在起点
# ============================================================

func test_attack_upgrade_stops_at_unplayed_no_skip_rank() -> void:
	# Team0 at 10（从未以 10 坐过庄），team1 at 3。
	# Dealer=seat1(team1)，攻方=team0，130 分 → 提案升 1 级。
	# 10 是必打级且 team0 没打过 → 停在 10，下局 team0 坐庄打 10。
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.TEN, "team0(攻方) 停在未打过的必打级 10")
	assert_eq(applied.new_rank, R.TEN, "effective new_rank agrees with state")
	assert_eq(applied.proposal.new_rank, R.TEN, "proposal matches effective")


func test_attack_stopped_at_no_skip_still_dethrones_dealer() -> void:
	# 停在必打级只影响级数，不影响下庄——攻方照样把庄抢过来。
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_true(result.dealer_dethroned, "130 分已过 80 门槛，庄家下庄")
	assert_eq(state.current_dealer, 2, "换庄到下家 (seat1+1)")
	assert_eq(state.current_rank, R.TEN, "下一局打新庄家方的级 10")


func test_dealer_upgrade_from_no_skip_rank_allowed() -> void:
	# Team0 at 5, is dealer (seat 0), plays rank 5, scores 30 → dealer upgrades 2.
	# 庄家方坐庄打的就是自己那一级，本局已经打过 → 可以直接升走，不拦在 5。
	state.team_ranks = [R.FIVE, R.THREE]
	state.current_dealer = 0
	state.current_rank = R.FIVE
	var result := _settlement(30, 0, false, R.FIVE)

	var applied := state.apply_settlement(result, 0, rc)

	assert_eq(state.team_ranks[0], R.SEVEN, "team0: 5+2=7, allowed after dealer")


func test_attack_stops_at_unplayed_five() -> void:
	# Team1 at 5，从未以 5 坐过庄。Dealer=seat0(team0 at 8)，攻方=team1，120 分 → 升 1。
	# 这正是真机上报的场景：南北方等级 5、打东西方的 2、作为攻方赢了。
	state.team_ranks = [R.EIGHT, R.FIVE]
	state.current_dealer = 0
	state.current_rank = R.EIGHT
	var result := _settlement(120, 0, true, R.EIGHT, R.FIVE)

	var applied := state.apply_settlement(result, 0, rc)

	assert_eq(state.team_ranks[1], R.FIVE, "team1(攻方) 停在 5，而不是升到 6")


func test_attack_stops_at_unplayed_king() -> void:
	# Team0 at K，从未以 K 坐过庄。Dealer=seat1(team1 at 7)，攻方=team0，120 分 → 升 1。
	# Dealer=seat1 (team1 at 7), attack=team0. Attack scores 120 → upgrade 1.
	# K 是必打级且 team0 没以 K 坐过庄 → 停在 K。
	state.team_ranks = [R.KING, R.SEVEN]
	state.current_dealer = 1
	state.current_rank = R.SEVEN
	var result := _settlement(120, 1, true, R.SEVEN, R.KING)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.KING, "team0(攻方) 停在 K，不能直接进 A")
	assert_false(state.game_over, "停在 K，游戏当然没结束")


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


func test_apply_settlement_without_rule_config_still_works() -> void:
	# 向后兼容：apply_settlement 的 rule_config 是可选参数。
	# 必打级约束其实在 UpgradeSettlement.calculate() 阶段就已经算完并写进
	# proposal 了，这里传不传 rule_config 都不会改变 new_rank——所以起点取
	# 非必打级的 7，这条用例验证的是「不传也能正常应用」，不是约束本身。
	state.team_ranks = [R.SEVEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.SEVEN)

	var applied := state.apply_settlement(result, 1)

	assert_eq(state.team_ranks[0], R.EIGHT, "7→8 正常应用")
	assert_eq(applied.new_rank, R.EIGHT)


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


## P1 一致性：攻方停在必打级时，effective 与 proposal 各层保持自洽。
##
## 起点是 K（必打级、攻方没坐过庄）→ 停在 K。proposal.game_over 本身就是
## false（起点不是 A），这里验证 effective 层不被提案的其它字段"感染"。
func test_attack_stopped_at_king_keeps_layers_consistent() -> void:
	# Team0 at K (no_skip rank, never played as dealer).
	# Dealer=seat1 (team1 at 7), attack=team0 at K. Attack score=120 → upgrade 1.
	state.team_ranks = [R.KING, R.SEVEN]
	state.current_dealer = 1
	state.current_rank = R.SEVEN
	var result := _settlement(120, 1, true, R.SEVEN, R.KING)

	# Sanity：起点不是 A，所以本就不该 game_over
	assert_false(result.game_over, "sanity: proposal.game_over is false when starting from K")
	assert_eq(result.new_rank, R.KING, "sanity: 提案已被必打级钳制在 K")

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.KING, "team0(攻方) 停在 K")
	assert_false(state.game_over, "game not over yet")
	assert_false(applied.game_over, "effective.game_over synced with state")
	assert_eq(applied.proposal.new_rank, R.KING, "proposal 与 effective 一致")


func test_reproduces_bug_south_north_skipped_10() -> void:
	# 真机报过两次的同一个 bug：南北队等级 10、从未以 10 坐庄，
	# 东(seat1) 坐庄打 3，南北队作为攻方拿 130 分升 1 级，结果直接跳到 J，
	# 把必打的 10 跳过去了。现在应停在 10。
	state.team_ranks = [R.TEN, R.THREE]
	state.current_dealer = 1
	state.current_rank = R.THREE
	var result := _settlement(130, 1, true, R.THREE, R.TEN)

	var applied := state.apply_settlement(result, 1, rc)

	assert_eq(state.team_ranks[0], R.TEN, "team0(攻方) 必须停在未打过的 10")
	assert_eq(applied.new_rank, R.TEN, "effective new_rank agrees with team_ranks[0]")
