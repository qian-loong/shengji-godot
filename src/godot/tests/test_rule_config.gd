## Unit tests for RuleConfig (S1-04)
## Validates: F3 rule-config.md AC1-AC6
extends GutTest


func test_default_values() -> void:
	var rc := RuleConfig.new()
	assert_eq(rc.deck_count, 2)
	assert_eq(rc.current_rank, Card.Rank.TWO)
	assert_eq(rc.hand_size, 25)
	assert_eq(rc.bottom_size, 8)
	assert_eq(rc.total_score, 200)
	assert_eq(rc.trump_mode, RuleConfig.TrumpMode.BID)
	assert_true(rc.joker_always_trump)
	assert_true(rc.bid_requires_joker)


func test_derived_1_deck() -> void:
	var rc := RuleConfig.new()
	rc.deck_count = 1
	assert_eq(rc.hand_size, 12)
	assert_eq(rc.bottom_size, 6)
	assert_eq(rc.total_cards, 54)
	assert_eq(rc.total_score, 100)


func test_derived_2_deck() -> void:
	var rc := RuleConfig.new()
	rc.deck_count = 2
	assert_eq(rc.hand_size, 25)
	assert_eq(rc.bottom_size, 8)
	assert_eq(rc.total_cards, 108)
	assert_eq(rc.total_score, 200)


func test_validate_four_same_forced_false_1_deck() -> void:
	var rc := RuleConfig.new()
	rc.deck_count = 1
	rc.four_same_is_tractor = true
	var errors := rc.validate()
	assert_eq(errors.size(), 0, "should pass but auto-correct")
	assert_false(rc.four_same_is_tractor, "should be forced to false")


func test_validate_fixed_trump_no_suit() -> void:
	var rc := RuleConfig.new()
	rc.trump_mode = RuleConfig.TrumpMode.FIXED
	rc.fixed_trump_suit = -1
	var errors := rc.validate()
	assert_true(errors.size() > 0, "should fail: fixed mode without suit")


func test_validate_threshold_exceeds_total() -> void:
	var rc := RuleConfig.new()
	rc.deck_count = 2
	rc.upgrade_threshold = 250
	var errors := rc.validate()
	assert_true(errors.size() > 0, "should fail: threshold > total_score")


func test_lock_unlock() -> void:
	var rc := RuleConfig.new()
	assert_false(rc.is_locked())
	var errors := rc.lock()
	assert_eq(errors.size(), 0)
	assert_true(rc.is_locked())
	rc.unlock()
	assert_false(rc.is_locked())


func test_lock_fails_on_invalid() -> void:
	var rc := RuleConfig.new()
	rc.trump_mode = RuleConfig.TrumpMode.FIXED
	rc.fixed_trump_suit = -1
	var errors := rc.lock()
	assert_true(errors.size() > 0)
	assert_false(rc.is_locked(), "should not lock on validation failure")


func test_snapshot() -> void:
	var rc := RuleConfig.new()
	rc.deck_count = 1
	rc.current_rank = Card.Rank.FIVE
	var snap := rc.create_snapshot()
	assert_eq(snap.deck_count, 1)
	assert_eq(snap.current_rank, Card.Rank.FIVE)
	# Modifying original should not affect snapshot
	rc.deck_count = 2
	assert_eq(snap.deck_count, 1, "snapshot should be independent")
