## Unit tests for PlayValidator (S1-07 + S1-08)
## Validates: C2 play-validation.md AC1-AC14
extends GutTest

const S = Card.Suit
const R = Card.Rank
const J = Card.JokerType

var rc: RuleConfig


func before_each() -> void:
	rc = RuleConfig.new()
	rc.deck_count = 2
	rc.current_rank = R.FOUR


# ============================================================
# S1-07: Lead validation (AC1-AC4)
# ============================================================

func test_lead_valid_pair() -> void:
	# AC1: lead ♠33 with pair in hand
	var hand: Array = [
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.SPADE, R.THREE, 1),
		Card.normal(S.HEART, R.ACE, 0),
	]
	var play: Array = [hand[0], hand[1]]
	var result := PlayValidator.validate_lead(play, hand, S.SPADE, R.FOUR, rc)
	assert_not_null(result, "valid pair lead")
	assert_eq(result.type, Card.CardType.PAIR)


func test_lead_invalid_not_in_hand() -> void:
	var hand: Array = [Card.normal(S.SPADE, R.THREE, 0)]
	var play: Array = [Card.normal(S.HEART, R.ACE, 0)]
	var result := PlayValidator.validate_lead(play, hand, S.SPADE, R.FOUR, rc)
	assert_null(result, "card not in hand")


func test_lead_invalid_mixed_domain() -> void:
	# AC2: ♠3♠5 not a valid pair, and different ranks in same suit — would be dump
	# But ♠3♥5 = different domains = invalid
	var hand: Array = [
		Card.normal(S.SPADE, R.THREE, 0), Card.normal(S.HEART, R.FIVE, 0),
	]
	var play: Array = [hand[0], hand[1]]
	var result := PlayValidator.validate_lead(play, hand, S.SPADE, R.FOUR, rc)
	assert_null(result, "mixed domain lead invalid")


func test_lead_dump_disabled() -> void:
	rc.allow_dump = false
	var hand: Array = [
		Card.normal(S.HEART, R.ACE, 0), Card.normal(S.HEART, R.ACE, 1),
		Card.normal(S.HEART, R.KING, 0),
	]
	var play: Array = [hand[0], hand[1], hand[2]]
	var result := PlayValidator.validate_lead(play, hand, S.SPADE, R.FOUR, rc)
	# Dump is disabled, so this multi-card play should be rejected
	assert_true(result == null or result.type != Card.CardType.DUMP, "dump should be rejected when disabled")


func test_lead_single() -> void:
	var hand: Array = [Card.normal(S.SPADE, R.ACE, 0)]
	var play: Array = [hand[0]]
	var result := PlayValidator.validate_lead(play, hand, S.SPADE, R.FOUR, rc)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.SINGLE)


func test_lead_tractor() -> void:
	var hand: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
		Card.normal(S.HEART, R.SIX, 0), Card.normal(S.HEART, R.SIX, 1),
	]
	var result := PlayValidator.validate_lead(hand, hand, S.SPADE, R.FOUR, rc)
	assert_not_null(result)
	assert_eq(result.type, Card.CardType.TRACTOR)


# ============================================================
# S1-07: Follow validation (AC5-AC7)
# ============================================================

func test_follow_must_play_domain_cards() -> void:
	# AC5: must play same domain cards if you have them
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var hand: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
		Card.normal(S.SPADE, R.ACE, 0),
	]
	# Playing spade when you have hearts = invalid
	var play: Array = [Card.normal(S.SPADE, R.ACE, 0), Card.normal(S.HEART, R.FIVE, 0)]
	# Lead was pair (2 cards), but playing 1 heart + 1 spade when you have 2 hearts
	var valid := PlayValidator.validate_follow(play, hand, 2, lead_domain, S.SPADE, R.FOUR, rc)
	assert_false(valid, "must play hearts first when you have them")


func test_follow_play_all_domain_cards() -> void:
	# AC5: has domain pair, must play pair
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var hand: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
		Card.normal(S.SPADE, R.ACE, 0),
	]
	var play: Array = [Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1)]
	var valid := PlayValidator.validate_follow(play, hand, 2, lead_domain, S.SPADE, R.FOUR, rc)
	assert_true(valid, "playing both hearts is valid")


func test_follow_not_enough_domain_cards() -> void:
	# AC7: only 3 cards of lead domain, lead was 4 cards
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var hand: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.SIX, 0),
		Card.normal(S.HEART, R.SEVEN, 0),
		Card.normal(S.SPADE, R.ACE, 0), Card.normal(S.SPADE, R.KING, 0),
	]
	# Must play all 3 hearts + 1 from other domain
	var play: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.SIX, 0),
		Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.SPADE, R.ACE, 0),
	]
	var valid := PlayValidator.validate_follow(play, hand, 4, lead_domain, S.SPADE, R.FOUR, rc)
	assert_true(valid, "3 hearts + 1 spade is valid when only 3 hearts in hand")


func test_follow_no_domain_cards_free_play() -> void:
	# No hearts in hand, can play anything
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var hand: Array = [
		Card.normal(S.SPADE, R.ACE, 0), Card.normal(S.CLUB, R.KING, 0),
	]
	var play: Array = [Card.normal(S.SPADE, R.ACE, 0), Card.normal(S.CLUB, R.KING, 0)]
	var valid := PlayValidator.validate_follow(play, hand, 2, lead_domain, S.SPADE, R.FOUR, rc)
	assert_true(valid, "no hearts = free play")


func test_follow_wrong_count() -> void:
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var hand: Array = [Card.normal(S.HEART, R.FIVE, 0)]
	var play: Array = [Card.normal(S.HEART, R.FIVE, 0)]
	# Lead was 2 cards, playing 1
	var valid := PlayValidator.validate_follow(play, hand, 2, lead_domain, S.SPADE, R.FOUR, rc)
	assert_false(valid, "wrong card count")


# ============================================================
# strict_follow_structure: 有对必须出对
# ============================================================

func test_follow_pair_must_play_pair_when_available() -> void:
	# Lead is Pair, hand has pair in same domain → must play pair, not singles
	rc.strict_follow_structure = true
	var lead_domain := {"type": TrumpJudge.DomainType.TRUMP, "suit": -1}
	var trump_suit := S.DIAMOND  # ♦ is trump
	var rank := R.TWO  # rank card = 2
	# Hand has: ♠2♠2 (trump pair) + ♦Q + ♦K
	var hand: Array = [
		Card.normal(S.SPADE, R.TWO, 0), Card.normal(S.SPADE, R.TWO, 1),
		Card.normal(S.DIAMOND, R.QUEEN, 0), Card.normal(S.DIAMOND, R.KING, 0),
	]
	# Lead is trump Pair (♦A♦A). Player tries to play ♦Q♦K (two singles, not a pair)
	var play: Array = [Card.normal(S.DIAMOND, R.QUEEN, 0), Card.normal(S.DIAMOND, R.KING, 0)]
	var lead_pattern := CardPattern.PatternResult.new(Card.CardType.PAIR, 2)
	var valid := PlayValidator.validate_follow(play, hand, 2, lead_domain, trump_suit, rank, rc, lead_pattern)
	assert_false(valid, "must play pair ♠2♠2 when available, not singles ♦Q♦K")


func test_follow_pair_singles_ok_when_no_pair() -> void:
	# Lead is Pair, hand has NO pair in domain → singles are OK
	rc.strict_follow_structure = true
	var lead_domain := {"type": TrumpJudge.DomainType.TRUMP, "suit": -1}
	var trump_suit := S.DIAMOND
	var rank := R.TWO
	# Hand has: ♦Q + ♦K + ♥2 (3 trump singles, no trump pair)
	var hand: Array = [
		Card.normal(S.DIAMOND, R.QUEEN, 0), Card.normal(S.DIAMOND, R.KING, 0),
		Card.normal(S.HEART, R.TWO, 0),
	]
	var play: Array = [Card.normal(S.DIAMOND, R.QUEEN, 0), Card.normal(S.DIAMOND, R.KING, 0)]
	var lead_pattern := CardPattern.PatternResult.new(Card.CardType.PAIR, 2)
	var valid := PlayValidator.validate_follow(play, hand, 2, lead_domain, trump_suit, rank, rc, lead_pattern)
	assert_true(valid, "no pair in hand, playing two singles is OK")


func test_follow_tractor_must_play_pair_when_no_tractor() -> void:
	# Lead is Tractor(2对=4张), hand has no tractor but has 1 pair → must include pair
	rc.strict_follow_structure = true
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	# Hand has: ♥5♥5 (pair) + ♥9 + ♥J (singles) — no tractor
	var hand: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.JACK, 0),
	]
	var lead_pattern := CardPattern.PatternResult.new(Card.CardType.TRACTOR, 4)
	lead_pattern.pair_count = 2

	# Bad play: break pair apart into 4 singles
	var play_bad: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.NINE, 0),
		Card.normal(S.HEART, R.JACK, 0), Card.normal(S.HEART, R.FIVE, 1),
	]
	var valid_bad := PlayValidator.validate_follow(play_bad, hand, 4, lead_domain, S.SPADE, R.FOUR, rc, lead_pattern)
	# The 4 cards include ♥5♥5 but they're not played as a pair unit — however
	# _count_pairs sees them as a pair by sort_value. So this actually passes.
	# The real violation is playing 0 pairs when you have 1.
	# Let's test a clearer violation: omit the pair entirely.

	# Bad play 2: skip the pair, play 4 different singles (if available)
	# Hand only has 4 cards total with 1 pair, so any 4-card play includes both ♥5s.
	# Need different hand to test: 2 pairs + 2 singles = 6 domain cards
	var hand2: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.NINE, 1),
		Card.normal(S.HEART, R.JACK, 0), Card.normal(S.HEART, R.QUEEN, 0),
	]
	# Bad: play 4 singles, skip both pairs
	var play_no_pairs: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.NINE, 0),
		Card.normal(S.HEART, R.JACK, 0), Card.normal(S.HEART, R.QUEEN, 0),
	]
	var valid_no_pairs := PlayValidator.validate_follow(play_no_pairs, hand2, 4, lead_domain, S.SPADE, R.FOUR, rc, lead_pattern)
	assert_false(valid_no_pairs, "has 2 pairs but played 0 pairs — must include pairs when following tractor")

	# Good: play 2 pairs (best match for tractor)
	var play_good: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.NINE, 1),
	]
	var valid_good := PlayValidator.validate_follow(play_good, hand2, 4, lead_domain, S.SPADE, R.FOUR, rc, lead_pattern)
	assert_true(valid_good, "playing 2 pairs to follow tractor is valid")


func test_follow_tractor_one_pair_plus_singles() -> void:
	# Lead Tractor(2对=4张), hand has 1 pair + singles → must include the 1 pair
	rc.strict_follow_structure = true
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var hand: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.JACK, 0),
		Card.normal(S.HEART, R.QUEEN, 0),
	]
	var lead_pattern := CardPattern.PatternResult.new(Card.CardType.TRACTOR, 4)
	lead_pattern.pair_count = 2

	# Good: pair + 2 singles
	var play_good: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.JACK, 0),
	]
	var valid_good := PlayValidator.validate_follow(play_good, hand, 4, lead_domain, S.SPADE, R.FOUR, rc, lead_pattern)
	assert_true(valid_good, "1 pair + 2 singles is valid when only 1 pair available")

	# Bad: skip pair, play 4 singles
	var play_bad: Array = [
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.JACK, 0),
		Card.normal(S.HEART, R.QUEEN, 0), Card.normal(S.HEART, R.FIVE, 0),
	]
	var valid_bad := PlayValidator.validate_follow(play_bad, hand, 4, lead_domain, S.SPADE, R.FOUR, rc, lead_pattern)
	assert_false(valid_bad, "has 1 pair but played 0 pairs — must include pair")


func test_follow_tractor_no_pairs_all_singles_ok() -> void:
	# Lead Tractor(2对=4张), hand has 0 pairs → 4 singles is OK
	rc.strict_follow_structure = true
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var hand: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.SEVEN, 0),
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.JACK, 0),
	]
	var lead_pattern := CardPattern.PatternResult.new(Card.CardType.TRACTOR, 4)
	lead_pattern.pair_count = 2

	var play: Array = [
		Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.SEVEN, 0),
		Card.normal(S.HEART, R.NINE, 0), Card.normal(S.HEART, R.JACK, 0),
	]
	var valid := PlayValidator.validate_follow(play, hand, 4, lead_domain, S.SPADE, R.FOUR, rc, lead_pattern)
	assert_true(valid, "no pairs in hand, 4 singles is OK")


func test_follow_pair_off_suit_rank_cards_not_pair() -> void:
	# Regression: off-suit rank cards (♥2 ♦2) have same sort_value but are NOT a pair.
	# If hand has a real pair (♣2♣2), must play that, not ♥2♦2.
	rc.strict_follow_structure = true
	var lead_domain := {"type": TrumpJudge.DomainType.TRUMP, "suit": -1}
	var trump_suit := S.SPADE
	var rank := R.TWO
	# Hand: ♣2♣2 (real pair) + ♥2 + ♦2 (same sort_value, NOT a pair)
	var hand: Array = [
		Card.normal(S.CLUB, R.TWO, 0), Card.normal(S.CLUB, R.TWO, 1),
		Card.normal(S.HEART, R.TWO, 0), Card.normal(S.DIAMOND, R.TWO, 0),
	]
	# Bad: play ♥2♦2 (looks like pair by sort_value but isn't)
	var play_bad: Array = [
		Card.normal(S.HEART, R.TWO, 0), Card.normal(S.DIAMOND, R.TWO, 0),
	]
	var lead_pattern := CardPattern.PatternResult.new(Card.CardType.PAIR, 2)
	var valid_bad := PlayValidator.validate_follow(play_bad, hand, 2, lead_domain, trump_suit, rank, rc, lead_pattern)
	assert_false(valid_bad, "♥2♦2 is NOT a pair — must play real pair ♣2♣2")

	# Good: play ♣2♣2 (real pair)
	var play_good: Array = [
		Card.normal(S.CLUB, R.TWO, 0), Card.normal(S.CLUB, R.TWO, 1),
	]
	var valid_good := PlayValidator.validate_follow(play_good, hand, 2, lead_domain, trump_suit, rank, rc, lead_pattern)
	assert_true(valid_good, "♣2♣2 is a real pair — valid")


# ============================================================
# S1-08: Trick winner (AC8-AC14)
# ============================================================

func _make_play(seat: int, cards: Array, pattern_type: int = -1) -> Dictionary:
	var pattern: CardPattern.PatternResult
	if pattern_type >= 0:
		pattern = CardPattern.PatternResult.new(pattern_type, cards.size())
	else:
		pattern = CardPattern.identify(cards, R.FOUR, rc.tractor_allow_rank_card, rc.four_same_is_tractor)
	return { "seat": seat, "cards": cards, "pattern": pattern }


func test_winner_trump_pair_beats_side_pair() -> void:
	# AC8: lead ♥22, follow ♠AA (trump pair) → ♠AA wins
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var plays: Array = [
		_make_play(0, [Card.normal(S.HEART, R.TWO, 0), Card.normal(S.HEART, R.TWO, 1)]),
		_make_play(1, [Card.normal(S.SPADE, R.ACE, 0), Card.normal(S.SPADE, R.ACE, 1)]),
		_make_play(2, [Card.normal(S.HEART, R.THREE, 0), Card.normal(S.HEART, R.THREE, 1)]),
		_make_play(3, [Card.normal(S.CLUB, R.FIVE, 0), Card.normal(S.CLUB, R.SIX, 0)]),
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	assert_eq(winner, 1, "trump pair ♠AA should win")


func test_winner_big_small_joker_not_pair() -> void:
	# AC9: lead ♥22, follow BigJoker+SmallJoker → NOT a pair, doesn't win
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var joker_play := [Card.joker(J.BIG, 0), Card.joker(J.SMALL, 0)]
	var plays: Array = [
		_make_play(0, [Card.normal(S.HEART, R.TWO, 0), Card.normal(S.HEART, R.TWO, 1)]),
		_make_play(1, joker_play),
		_make_play(2, [Card.normal(S.HEART, R.THREE, 0), Card.normal(S.HEART, R.THREE, 1)]),
		_make_play(3, [Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.SIX, 0)]),
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	# BigJoker+SmallJoker is not a pair, so seat 0's ♥22 should still win (or seat 2's ♥33)
	assert_ne(winner, 1, "BigJoker+SmallJoker is not a pair, should not win")


func test_winner_trump_tractor_beats_side_tractor() -> void:
	# AC10: lead ♥2233, follow ♠KKAA (trump tractor) → wins
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var plays: Array = [
		_make_play(0, [
			Card.normal(S.HEART, R.TWO, 0), Card.normal(S.HEART, R.TWO, 1),
			Card.normal(S.HEART, R.THREE, 0), Card.normal(S.HEART, R.THREE, 1),
		]),
		_make_play(1, [
			Card.normal(S.SPADE, R.KING, 0), Card.normal(S.SPADE, R.KING, 1),
			Card.normal(S.SPADE, R.ACE, 0), Card.normal(S.SPADE, R.ACE, 1),
		]),
		_make_play(2, [
			Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.FIVE, 1),
			Card.normal(S.HEART, R.SIX, 0), Card.normal(S.HEART, R.SIX, 1),
		]),
		_make_play(3, [
			Card.normal(S.CLUB, R.TWO, 0), Card.normal(S.CLUB, R.THREE, 0),
			Card.normal(S.CLUB, R.FIVE, 0), Card.normal(S.CLUB, R.SIX, 0),
		]),
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	assert_eq(winner, 1, "♠KKAA tractor should win")


func test_winner_non_tractor_trump_no_win() -> void:
	# AC11: lead ♥2233 (tractor), follow ♠99 ♠AA (not consecutive) → doesn't win
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var plays: Array = [
		_make_play(0, [
			Card.normal(S.HEART, R.TWO, 0), Card.normal(S.HEART, R.TWO, 1),
			Card.normal(S.HEART, R.THREE, 0), Card.normal(S.HEART, R.THREE, 1),
		]),
		_make_play(1, [
			Card.normal(S.SPADE, R.NINE, 0), Card.normal(S.SPADE, R.NINE, 1),
			Card.normal(S.SPADE, R.ACE, 0), Card.normal(S.SPADE, R.ACE, 1),
		]),
		_make_play(2, [
			Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.SIX, 0),
			Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.EIGHT, 0),
		]),
		_make_play(3, [
			Card.normal(S.CLUB, R.TWO, 0), Card.normal(S.CLUB, R.THREE, 0),
			Card.normal(S.CLUB, R.FIVE, 0), Card.normal(S.CLUB, R.SIX, 0),
		]),
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	assert_ne(winner, 1, "♠99♠AA not tractor, should not win")


func test_winner_bigger_trump_kill() -> void:
	# AC12: two trump kills, ♠55 vs ♠KK → ♠KK wins
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var plays: Array = [
		_make_play(0, [Card.normal(S.HEART, R.TWO, 0), Card.normal(S.HEART, R.TWO, 1)]),
		_make_play(1, [Card.normal(S.SPADE, R.FIVE, 0), Card.normal(S.SPADE, R.FIVE, 1)]),
		_make_play(2, [Card.normal(S.HEART, R.THREE, 0), Card.normal(S.HEART, R.THREE, 1)]),
		_make_play(3, [Card.normal(S.SPADE, R.KING, 0), Card.normal(S.SPADE, R.KING, 1)]),
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	assert_eq(winner, 3, "♠KK should beat ♠55")


func test_winner_highest_in_lead_domain() -> void:
	# AC13: lead ♥5, no trump, ♥A is highest
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var plays: Array = [
		_make_play(0, [Card.normal(S.HEART, R.FIVE, 0)]),
		_make_play(1, [Card.normal(S.HEART, R.ACE, 0)]),
		_make_play(2, [Card.normal(S.HEART, R.THREE, 0)]),
		_make_play(3, [Card.normal(S.CLUB, R.ACE, 0)]),  # discard, doesn't win
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	assert_eq(winner, 1, "♥A should win")


func test_winner_lead_wins_when_no_higher() -> void:
	# Lead player wins if no one beats them
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var plays: Array = [
		_make_play(0, [Card.normal(S.HEART, R.ACE, 0)]),
		_make_play(1, [Card.normal(S.HEART, R.THREE, 0)]),
		_make_play(2, [Card.normal(S.CLUB, R.ACE, 0)]),  # discard
		_make_play(3, [Card.normal(S.DIAMOND, R.ACE, 0)]),  # discard
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	assert_eq(winner, 0, "lead ♥A should win")


# ============================================================
# Regression: trump lead — bigger trump should win
# ============================================================

func test_winner_trump_lead_bigger_trump_wins() -> void:
	# Bug: when lead is trump, followers with bigger trump were not winning
	# Lead ♥2 (rank card sv=120), follow BlackJoker (sv=140), RedJoker (sv=150)
	# → RedJoker should win
	var lead_domain := {"type": TrumpJudge.DomainType.TRUMP, "suit": -1}
	var plays: Array = [
		_make_play(3, [Card.normal(S.HEART, R.TWO, 0)]),  # 级牌=主
		_make_play(2, [Card.normal(S.CLUB, R.NINE, 0)]),  # 垫牌
		_make_play(1, [Card.joker(J.SMALL, 0)]),           # BlackJoker
		_make_play(0, [Card.joker(J.BIG, 0)]),             # RedJoker
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.TWO, rc)
	assert_eq(winner, 0, "RedJoker (sv=150) should beat rank card (sv=120)")


func test_winner_trump_lead_same_value_first_wins() -> void:
	# Lead ♠4 (trump rank card), follow ♣4 (also rank card, same sv)
	# → Lead wins (first player wins tie)
	var lead_domain := {"type": TrumpJudge.DomainType.TRUMP, "suit": -1}
	var plays: Array = [
		_make_play(0, [Card.normal(S.SPADE, R.FOUR, 0)]),  # 主花级牌 sv=130
		_make_play(3, [Card.normal(S.HEART, R.FOUR, 0)]),  # 非主花级牌 sv=120
		_make_play(2, [Card.normal(S.CLUB, R.THREE, 0)]),   # 垫牌
		_make_play(1, [Card.normal(S.DIAMOND, R.FOUR, 0)]), # 非主花级牌 sv=120
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	assert_eq(winner, 0, "♠4 (sv=130) should beat ♥4/♦4 (sv=120)")


func test_winner_trump_lead_follower_bigger() -> void:
	# Lead small trump, follower has bigger trump → follower wins
	var lead_domain := {"type": TrumpJudge.DomainType.TRUMP, "suit": -1}
	var plays: Array = [
		_make_play(0, [Card.normal(S.SPADE, R.THREE, 0)]),  # ♠3 trump sv~100
		_make_play(3, [Card.normal(S.SPADE, R.ACE, 0)]),    # ♠A trump sv~111
		_make_play(2, [Card.normal(S.HEART, R.SEVEN, 0)]),  # 副牌垫牌
		_make_play(1, [Card.normal(S.SPADE, R.KING, 0)]),   # ♠K trump sv~110
	]
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)
	assert_eq(winner, 3, "♠A should beat ♠3 and ♠K")


# ============================================================
# Regression: structure-mismatch must NOT win lead pair/tractor
# (Bug observed in real play log: a Pair lead was beaten by a Dump)
# ============================================================

func test_winner_trump_pair_lead_dump_follower_cannot_win() -> void:
	# Arrange: lead ♠K♠K (trump pair). Follower has Dump with one larger single.
	# Expected: lead wins because Dump does not match Pair structure.
	var lead_domain := {"type": TrumpJudge.DomainType.TRUMP, "suit": -1}
	var plays: Array = [
		_make_play(0, [Card.normal(S.SPADE, R.KING, 0), Card.normal(S.SPADE, R.KING, 1)]),
		_make_play(3, [Card.normal(S.SPADE, R.TEN, 0), Card.normal(S.DIAMOND, R.THREE, 0)]),
		_make_play(2, [Card.normal(S.SPADE, R.NINE, 0), Card.normal(S.SPADE, R.JACK, 0)]),
		_make_play(1, [Card.normal(S.CLUB, R.THREE, 0), Card.normal(S.DIAMOND, R.THREE, 1)]),
	]

	# Act
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.THREE, rc)

	# Assert
	assert_eq(winner, 0, "lead trump pair must win against unstructured Dump follows")


func test_winner_trump_tractor_lead_dump_follower_cannot_win() -> void:
	# Arrange: side-suit tractor lead, follower has 4 random ♦ in dump form
	# Expected: lead wins, no follower can match the tractor structure
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.DIAMOND}
	var plays: Array = [
		_make_play(0, [
			Card.normal(S.DIAMOND, R.NINE, 0), Card.normal(S.DIAMOND, R.NINE, 1),
			Card.normal(S.DIAMOND, R.EIGHT, 0), Card.normal(S.DIAMOND, R.EIGHT, 1),
		]),
		_make_play(3, [
			Card.normal(S.DIAMOND, R.SIX, 0), Card.normal(S.DIAMOND, R.SEVEN, 0),
			Card.normal(S.DIAMOND, R.SEVEN, 1), Card.normal(S.DIAMOND, R.JACK, 0),
		]),
		_make_play(2, [
			Card.normal(S.DIAMOND, R.TWO, 0), Card.normal(S.DIAMOND, R.FOUR, 0),
			Card.normal(S.DIAMOND, R.FOUR, 1), Card.normal(S.DIAMOND, R.SIX, 1),
		]),
		_make_play(1, [
			Card.normal(S.DIAMOND, R.FIVE, 0), Card.normal(S.DIAMOND, R.TEN, 0),
			Card.normal(S.HEART, R.FOUR, 0), Card.normal(S.HEART, R.SIX, 0),
		]),
	]

	# Act
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.THREE, rc)

	# Assert
	assert_eq(winner, 0, "side-suit tractor must beat all unstructured follows")


func test_winner_side_pair_lead_dump_follower_cannot_win() -> void:
	# Arrange: side-suit pair lead, every follower plays Dump (no pairs)
	# Expected: lead wins because no follow has a matching Pair structure
	var lead_domain := {"type": TrumpJudge.DomainType.SIDE, "suit": S.HEART}
	var plays: Array = [
		_make_play(0, [Card.normal(S.HEART, R.QUEEN, 0), Card.normal(S.HEART, R.QUEEN, 1)]),
		_make_play(3, [Card.normal(S.HEART, R.SEVEN, 0), Card.normal(S.HEART, R.NINE, 0)]),
		_make_play(2, [Card.normal(S.HEART, R.FIVE, 0), Card.normal(S.HEART, R.SIX, 0)]),
		_make_play(1, [Card.normal(S.HEART, R.JACK, 0), Card.normal(S.HEART, R.TEN, 0)]),
	]

	# Act
	var winner := PlayValidator.determine_winner(plays, lead_domain, S.SPADE, R.FOUR, rc)

	# Assert
	assert_eq(winner, 0, "side-suit pair lead must beat all unstructured follows")
