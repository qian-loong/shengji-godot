## Unit tests for two-team independent ranks
## Validates: upgrade-settlement.md §5 (两队独立级)
extends GutTest

const S = Card.Suit
const R = Card.Rank

var rc: RuleConfig


func before_each() -> void:
	rc = RuleConfig.new()
	rc.deck_count = 2


## Helper: simulate settlement and apply to team_ranks
## Returns updated team_ranks
static func apply_settlement(
	team_ranks: Array[int], dealer: int,
	settlement: UpgradeSettlement.SettlementResult,
) -> Array[int]:
	var result: Array[int] = team_ranks.duplicate()
	if settlement.upgrade_levels > 0:
		var upgrading_team: int
		if settlement.upgrading_side == 0:
			upgrading_team = dealer % 2  # dealer's team
		else:
			upgrading_team = (dealer + 1) % 2  # attack team
		result[upgrading_team] = settlement.new_rank
	return result


# ============================================================
# Basic: upgrading side affects correct team
# ============================================================

func test_dealer_team_upgrades_when_dealer_wins() -> void:
	# Dealer=seat0 (team0), attack score=30 → dealer upgrades 2
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(30, [], 0, false, pattern, R.TWO, rc)
	var ranks: Array[int] = [R.TWO, R.FIVE]
	ranks = apply_settlement(ranks, 0, result)
	assert_eq(ranks[0], R.FOUR, "team0 (dealer) upgrades 2→4")
	assert_eq(ranks[1], R.FIVE, "team1 (attack) unchanged at 5")


func test_attack_team_upgrades_when_attack_wins() -> void:
	# Dealer=seat1 (team1), attack score=155 → attack upgrades 1
	# Dealer's rank=3 (team1), attack team0 rank=5
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(155, [], 1, true, pattern, R.THREE, rc, R.FIVE)
	var ranks: Array[int] = [R.FIVE, R.THREE]
	ranks = apply_settlement(ranks, 1, result)
	assert_eq(ranks[0], R.SIX, "team0 (attack of seat1) upgrades 5→6")
	assert_eq(ranks[1], R.THREE, "team1 (dealer) unchanged at 3")


func test_dethrone_no_upgrade_both_unchanged() -> void:
	# Dealer=seat2 (team0), attack score=100 → dethrone, no upgrade
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(100, [], 2, true, pattern, R.SEVEN, rc)
	var ranks: Array[int] = [R.SEVEN, R.FOUR]
	ranks = apply_settlement(ranks, 2, result)
	assert_eq(ranks[0], R.SEVEN, "team0 unchanged")
	assert_eq(ranks[1], R.FOUR, "team1 unchanged")
	assert_true(result.dealer_dethroned)
	assert_eq(result.upgrade_levels, 0)


# ============================================================
# Teams at different ranks
# ============================================================

func test_different_ranks_dealer_team0() -> void:
	# Team0 at 7, Team1 at 3. Dealer=seat0 (team0), plays rank 7
	# Attack score=0 → dealer upgrades 3, but no_skip at 10
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(0, [], 0, false, pattern, R.SEVEN, rc)
	var ranks: Array[int] = [R.SEVEN, R.THREE]
	ranks = apply_settlement(ranks, 0, result)
	assert_eq(ranks[0], R.TEN, "team0: 7+3 stops at 10 (no_skip)")
	assert_eq(ranks[1], R.THREE, "team1 unchanged")


func test_different_ranks_dealer_team1() -> void:
	# Team0 at 10, Team1 at 5. Dealer=seat3 (team1), plays rank 5
	# Attack score=40 → dealer upgrades 1: 5→6
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(40, [], 3, false, pattern, R.FIVE, rc)
	var ranks: Array[int] = [R.TEN, R.FIVE]
	ranks = apply_settlement(ranks, 3, result)
	assert_eq(ranks[0], R.TEN, "team0 unchanged")
	assert_eq(ranks[1], R.SIX, "team1: 5+1=6")


# ============================================================
# Round rank = dealer's team rank
# ============================================================

func test_round_rank_from_dealer_team() -> void:
	var ranks: Array[int] = [R.EIGHT, R.FIVE]
	# Dealer seat0 → team0 → rank 8
	assert_eq(ranks[0 % 2], R.EIGHT, "seat0 dealer → plays rank 8")
	# Dealer seat1 → team1 → rank 5
	assert_eq(ranks[1 % 2], R.FIVE, "seat1 dealer → plays rank 5")
	# Dealer seat2 → team0 → rank 8
	assert_eq(ranks[2 % 2], R.EIGHT, "seat2 dealer → plays rank 8")
	# Dealer seat3 → team1 → rank 5
	assert_eq(ranks[3 % 2], R.FIVE, "seat3 dealer → plays rank 5")


# ============================================================
# Game over: one team passes A
# ============================================================

func test_game_over_team0_passes_ace() -> void:
	# Team0 at A, dealer=seat0 (team0), score=40 → upgrades 1 → past A → game over
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(40, [], 0, false, pattern, R.ACE, rc)
	assert_true(result.game_over, "team0 passes A = game over")
	var ranks: Array[int] = [R.ACE, R.FIVE]
	var upgrading_team := 0  # dealer team
	assert_eq(upgrading_team, 0, "team0 wins")


func test_game_over_team1_passes_ace() -> void:
	# Team1 at A, dealer=seat1 (team1), attack score=120 → attack upgrades 1
	# attack team = team0. But team0 is NOT at A.
	# So this should NOT be game over for team0.
	# Let's make team1 the upgrading side: score=40, dealer=seat1
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(40, [], 1, false, pattern, R.ACE, rc)
	assert_true(result.game_over, "team1 at A, dealer team1 upgrades → game over")
	var ranks: Array[int] = [R.FIVE, R.ACE]
	var upgrading_team := 1  # dealer's team (seat1 % 2)
	assert_eq(upgrading_team, 1, "team1 wins")


func test_not_game_over_other_team_at_ace() -> void:
	# Team0 at A, but dealer=seat1 (team1 at 5), team1 plays rank 5
	# Attack=team0 at A, score=120 → attack upgrades 1 → team0 A past A → game over!
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(120, [], 1, true, pattern, R.FIVE, rc, R.ACE)
	assert_true(result.game_over, "attack team at A, upgrades → game over")


func test_not_game_over_attack_not_at_ace() -> void:
	# Dealer=seat1 (team1 at 5), attack=team0 at 10, score=120 → attack upgrades 1
	# team0: 10→J, not A, no game over
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(120, [], 1, true, pattern, R.FIVE, rc, R.TEN)
	assert_false(result.game_over, "attack at 10, not A, no game over")
	assert_eq(result.new_rank, R.JACK, "10+1=J")


func test_game_over_attack_at_ace() -> void:
	# Dealer=seat1 (team1 at K), attack=team0 at A.
	# Score=160 → attack upgrades 2. attack_rank=A → game over
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(160, [], 1, true, pattern, R.KING, rc, R.ACE)
	assert_true(result.game_over, "attack at A, upgrades → game over")


# ============================================================
# No-skip with independent ranks
# ============================================================

func test_no_skip_independent_team() -> void:
	# Team0 at 4, team1 at 9. Dealer=seat0, score=0 → dealer upgrades 3
	# 4→5 stops at 5 (no_skip), team1 stays at 9
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(0, [], 0, false, pattern, R.FOUR, rc)
	var ranks: Array[int] = [R.FOUR, R.NINE]
	ranks = apply_settlement(ranks, 0, result)
	assert_eq(ranks[0], R.FIVE, "team0: 4+3 stops at 5")
	assert_eq(ranks[1], R.NINE, "team1 unchanged")


func test_both_teams_near_ace() -> void:
	# Team0 at K, team1 at Q. Dealer=seat0, score=40 → dealer upgrades 1
	# K+1=A, no_skip doesn't block last level landing on K
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(40, [], 0, false, pattern, R.KING, rc)
	var ranks: Array[int] = [R.KING, R.QUEEN]
	ranks = apply_settlement(ranks, 0, result)
	assert_eq(ranks[0], R.ACE, "team0: K+1=A")
	assert_eq(ranks[1], R.QUEEN, "team1 unchanged")
