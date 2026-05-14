## Unit tests for ScoreTracker (S1-09) and UpgradeSettlement (S1-10)
## Validates: C5 AC1-AC6, C6 AC1-AC11
extends GutTest

const S = Card.Suit
const R = Card.Rank

var rc: RuleConfig


func before_each() -> void:
	rc = RuleConfig.new()
	rc.deck_count = 2


# ============================================================
# C5 Score Tracking
# ============================================================

func test_trick_score_mixed() -> void:
	# AC1: ♠5 ♥10 ♦K ♣3 = 5+10+10+0 = 25
	var cards: Array = [
		Card.normal(S.SPADE, R.FIVE),
		Card.normal(S.HEART, R.TEN),
		Card.normal(S.DIAMOND, R.KING),
		Card.normal(S.CLUB, R.THREE),
	]
	var tracker := ScoreTracker.new(200)
	var score := tracker.record_trick(cards, true)
	assert_eq(score, 25)
	assert_eq(tracker.get_attack_score(), 25)


func test_trick_score_zero() -> void:
	# AC2: no scoring cards
	var cards: Array = [
		Card.normal(S.SPADE, R.THREE),
		Card.normal(S.HEART, R.SEVEN),
		Card.normal(S.DIAMOND, R.JACK),
		Card.normal(S.CLUB, R.TWO),
	]
	var tracker := ScoreTracker.new(200)
	var score := tracker.record_trick(cards, true)
	assert_eq(score, 0)


func test_attack_vs_defend_score() -> void:
	var tracker := ScoreTracker.new(200)
	# Attack wins trick with 25 points
	tracker.record_trick([
		Card.normal(S.SPADE, R.FIVE), Card.normal(S.HEART, R.TEN),
		Card.normal(S.DIAMOND, R.KING), Card.normal(S.CLUB, R.THREE),
	], true)
	# Defend wins trick with 10 points
	tracker.record_trick([
		Card.normal(S.SPADE, R.TEN), Card.normal(S.HEART, R.THREE),
		Card.normal(S.DIAMOND, R.TWO), Card.normal(S.CLUB, R.SEVEN),
	], false)
	assert_eq(tracker.get_attack_score(), 25)
	assert_eq(tracker.get_defend_score(), 10)
	assert_eq(tracker.get_remaining_score(), 165)


# ============================================================
# C6 Upgrade Settlement
# ============================================================

func test_settlement_dealer_stays() -> void:
	# AC1: attack 70, dealer wins last trick → final=70, dealer stays, upgrades 1
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(70, [], 0, false, pattern, R.TWO, rc)
	assert_eq(result.final_score, 70)
	assert_eq(result.upgrading_side, 0, "dealer side")
	assert_eq(result.upgrade_levels, 1, "40-79 = dealer upgrades 1")
	assert_false(result.dealer_dethroned)
	assert_eq(result.new_dealer, -1, "dealer unchanged")


func test_settlement_bottom_pair() -> void:
	# AC2: attack 70, attack wins last (Pair), bottom has ♠5♥10 = 15
	var bottom: Array = [Card.normal(S.SPADE, R.FIVE), Card.normal(S.HEART, R.TEN)]
	var pattern := CardPattern.PatternResult.new(Card.CardType.PAIR, 2)
	pattern.pair_count = 1
	var result := UpgradeSettlement.calculate(70, bottom, 0, true, pattern, R.TWO, rc)
	assert_eq(result.bottom_score, 15)
	assert_eq(result.bottom_multiplier, 2)
	assert_eq(result.final_score, 100, "70 + 15*2 = 100")
	assert_true(result.dealer_dethroned, "100 >= 80")
	assert_eq(result.new_dealer, 1, "next seat becomes dealer")


func test_settlement_bottom_tractor() -> void:
	# AC3: attack 70, attack wins last (Tractor 2-pair), bottom has 25 points
	var bottom2: Array = [
		Card.normal(S.SPADE, R.FIVE), Card.normal(S.HEART, R.TEN),
		Card.normal(S.DIAMOND, R.TEN),
	]
	var pattern := CardPattern.PatternResult.new(Card.CardType.TRACTOR, 4)
	pattern.pair_count = 2
	var result := UpgradeSettlement.calculate(70, bottom2, 2, true, pattern, R.TWO, rc)
	# bottom = 5+10+10 = 25, multiplier = 4, bonus = 100, final = 170
	assert_eq(result.bottom_multiplier, 4)
	assert_eq(result.final_score, 170, "70 + 25*4 = 170")
	assert_eq(result.upgrade_levels, 2, "160-199 = attack upgrades 2")
	assert_eq(result.new_dealer, 3, "next seat becomes dealer")


func test_settlement_attack_zero() -> void:
	# AC4: attack 0 → dealer upgrades 3
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(0, [], 0, false, pattern, R.TWO, rc)
	assert_eq(result.upgrading_side, 0, "dealer")
	assert_eq(result.upgrade_levels, 3)


func test_settlement_attack_30() -> void:
	# AC5: attack 30 → dealer upgrades 2
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(30, [], 2, false, pattern, R.TWO, rc)
	assert_eq(result.upgrading_side, 0, "dealer")
	assert_eq(result.upgrade_levels, 2)


func test_settlement_attack_200() -> void:
	# AC6: attack 200 → attack upgrades 3
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(200, [], 0, true, pattern, R.TWO, rc)
	assert_eq(result.upgrading_side, 1, "attack")
	assert_eq(result.upgrade_levels, 3)
	assert_eq(result.new_dealer, 1, "next seat becomes dealer")


func test_upgrade_no_skip_rank_5() -> void:
	# AC7: rank=4, upgrade 2, no_skip=[5,10,K] → stops at 5
	var new_rank := UpgradeSettlement.apply_upgrade(R.FOUR, 2, rc)
	assert_eq(new_rank, R.FIVE, "should stop at 5")


func test_upgrade_from_5() -> void:
	# AC8: rank=5, upgrade 2 → 7 (no obstacle between 6 and 7)
	var new_rank := UpgradeSettlement.apply_upgrade(R.FIVE, 2, rc)
	assert_eq(new_rank, R.SEVEN)


func test_upgrade_no_skip_disabled() -> void:
	# AC11: no_skip_enabled=false, rank=4, upgrade 2 → 6
	rc.no_skip_enabled = false
	var new_rank := UpgradeSettlement.apply_upgrade(R.FOUR, 2, rc)
	assert_eq(new_rank, R.SIX)


func test_upgrade_3_levels_stopped_by_no_skip() -> void:
	# rank=3, dealer 大胜 upgrade 3 → 3→4→5, stops at 5 (no_skip)
	var new_rank := UpgradeSettlement.apply_upgrade(R.THREE, 3, rc)
	assert_eq(new_rank, R.FIVE, "3+3=6 but stops at 5")


func test_upgrade_3_levels_stopped_by_10() -> void:
	# rank=8, upgrade 3 → 8→9→10, stops at 10 (no_skip)
	var new_rank := UpgradeSettlement.apply_upgrade(R.EIGHT, 3, rc)
	assert_eq(new_rank, R.TEN, "8+3=J but stops at 10")


func test_upgrade_3_levels_stopped_by_king() -> void:
	# rank=Q, upgrade 3 → Q→K, stops at K (no_skip)
	var new_rank := UpgradeSettlement.apply_upgrade(R.QUEEN, 3, rc)
	assert_eq(new_rank, R.KING, "Q+3=past A but stops at K")


func test_upgrade_1_level_lands_on_no_skip_ok() -> void:
	# rank=4, upgrade 1 → exactly 5, no_skip doesn't block last level
	var new_rank := UpgradeSettlement.apply_upgrade(R.FOUR, 1, rc)
	assert_eq(new_rank, R.FIVE, "1 level lands on 5 = OK")


func test_upgrade_dealer_zero_score_from_rank_3() -> void:
	# Full settlement: rank=3, attack=0 → dealer upgrades 3 → stops at 5
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(0, [], 0, false, pattern, R.THREE, rc)
	assert_eq(result.upgrade_levels, 3)
	assert_eq(result.new_rank, R.FIVE, "3 + 3 levels stops at 5 (no_skip)")


func test_game_over_at_ace() -> void:
	# AC10: rank=A, attack wins → game over
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(120, [], 0, true, pattern, R.ACE, rc)
	assert_true(result.game_over)


func test_no_game_over_dealer_stays_at_ace() -> void:
	# rank=A, attack 50 → dealer upgrades 1 → past A → game over!
	var pattern := CardPattern.PatternResult.new(Card.CardType.SINGLE, 1)
	var result := UpgradeSettlement.calculate(50, [], 0, false, pattern, R.ACE, rc)
	assert_true(result.game_over, "rank=A + dealer upgrades 1 = game over")
	assert_eq(result.upgrade_levels, 1, "40-79 = dealer upgrades 1")
