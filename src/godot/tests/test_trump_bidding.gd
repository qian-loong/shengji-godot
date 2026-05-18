## Unit tests for TrumpBidding (S1-12)
## Validates: C3 trump-bidding.md AC1-AC13
extends GutTest

const S = Card.Suit
const R = Card.Rank
const J = Card.JokerType
const BT = TrumpBidding.BidType

var rc: RuleConfig


func before_each() -> void:
	rc = RuleConfig.new()
	rc.current_rank = R.FOUR


func test_single_rank_available_no_joker_required() -> void:
	# AC1: bid_requires_joker=false, has ♠4 → SingleRank available
	rc.bid_requires_joker = false
	var hand: Array = [Card.normal(S.SPADE, R.FOUR)]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var has_single_rank := false
	for b: TrumpBidding.BidDeclaration in bids:
		if b.bid_type == BT.SINGLE_RANK and b.suit == S.SPADE:
			has_single_rank = true
	assert_true(has_single_rank, "SingleRank ♠ should be available")


func test_no_bid_when_no_rank_cards() -> void:
	# AC5: bid_requires_joker=true, only rank cards no joker → no bid
	rc.bid_requires_joker = true
	var hand: Array = [
		Card.normal(S.SPADE, R.FOUR),
		Card.normal(S.HEART, R.ACE),
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	# Should only have bids that require joker, but no joker in hand
	var non_princess := bids.filter(func(b: TrumpBidding.BidDeclaration) -> bool:
		return b.bid_type != BT.PAIR_JOKER
	)
	assert_eq(non_princess.size(), 0, "no bids without joker")


func test_no_bid_single_joker_only() -> void:
	# AC6: bid_requires_joker=true, only single joker, no rank card → no bid
	rc.bid_requires_joker = true
	var hand: Array = [
		Card.joker(J.BIG),
		Card.normal(S.HEART, R.ACE),
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var non_princess := bids.filter(func(b: TrumpBidding.BidDeclaration) -> bool:
		return b.bid_type != BT.PAIR_JOKER
	)
	assert_eq(non_princess.size(), 0, "single joker without rank card = no bid")


func test_joker_rank_available() -> void:
	# AC4: bid_requires_joker=true, has joker + rank card → JokerRank
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = false  # any color OK
	var hand: Array = [
		Card.joker(J.BIG),
		Card.normal(S.SPADE, R.FOUR),
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var has_joker_rank := false
	for b: TrumpBidding.BidDeclaration in bids:
		if b.bid_type == BT.JOKER_SINGLE_RANK:
			has_joker_rank = true
	assert_true(has_joker_rank, "JokerSingleRank should be available")


func test_pair_joker_available() -> void:
	# AC9: 2 BigJokers → PairJoker (公主)
	var hand: Array = [
		Card.joker(J.BIG, 0), Card.joker(J.BIG, 1),
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var has_princess := false
	for b: TrumpBidding.BidDeclaration in bids:
		if b.bid_type == BT.PAIR_JOKER:
			has_princess = true
	assert_true(has_princess, "PairJoker (公主) should be available")


func test_princess_cannot_be_countered() -> void:
	# AC9: 公主 cannot be countered
	var bid := TrumpBidding.BidDeclaration.new(0, BT.PAIR_JOKER, -1)
	assert_false(TrumpBidding.can_be_countered(bid), "公主 not counterable")


func test_single_rank_can_be_countered() -> void:
	var bid := TrumpBidding.BidDeclaration.new(0, BT.SINGLE_RANK, S.SPADE)
	assert_true(TrumpBidding.can_be_countered(bid))


func test_joker_pair_rank_immune_to_counter() -> void:
	# ADR-0002: JOKER_PAIR_RANK joins PAIR_JOKER as counter-immune top tier.
	var bid := TrumpBidding.BidDeclaration.new(0, BT.JOKER_PAIR_RANK, S.HEART)
	assert_false(TrumpBidding.can_be_countered(bid),
		"JOKER_PAIR_RANK is immune to counter-bid (ADR-0002)")
	# Sanity: JOKER_SINGLE_RANK (s=3) and below remain counterable.
	var jsr := TrumpBidding.BidDeclaration.new(0, BT.JOKER_SINGLE_RANK, S.HEART)
	assert_true(TrumpBidding.can_be_countered(jsr),
		"JOKER_SINGLE_RANK still counterable")
	var pair := TrumpBidding.BidDeclaration.new(0, BT.PAIR_RANK, S.HEART)
	assert_true(TrumpBidding.can_be_countered(pair),
		"PAIR_RANK still counterable")


func test_strength_pair_rank_beats_single_rank() -> void:
	# AC7: PairRank > SingleRank → can counter
	var single := TrumpBidding.BidDeclaration.new(0, BT.SINGLE_RANK, S.SPADE)
	var pair := TrumpBidding.BidDeclaration.new(1, BT.PAIR_RANK, S.HEART)
	assert_true(TrumpBidding.is_stronger(pair, single), "PairRank > SingleRank")


func test_strength_single_rank_not_beats_pair_rank() -> void:
	# AC8: SingleRank < PairRank → cannot counter
	var pair := TrumpBidding.BidDeclaration.new(0, BT.PAIR_RANK, S.SPADE)
	var single := TrumpBidding.BidDeclaration.new(1, BT.SINGLE_RANK, S.HEART)
	assert_false(TrumpBidding.is_stronger(single, pair), "SingleRank < PairRank")


func test_color_match_red_joker_red_suit() -> void:
	# AC13: trump_joker_color_match=true, red joker + ♥ rank → valid
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = true
	var hand: Array = [
		Card.joker(J.BIG),  # Red
		Card.normal(S.HEART, R.FOUR),  # Red suit
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var has_heart := false
	for b: TrumpBidding.BidDeclaration in bids:
		if b.bid_type == BT.JOKER_SINGLE_RANK and b.suit == S.HEART:
			has_heart = true
	assert_true(has_heart, "red joker + ♥ rank = valid")


func test_color_match_red_joker_black_suit_rejected() -> void:
	# AC12: trump_joker_color_match=true, red joker + ♠ rank → invalid
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = true
	var hand: Array = [
		Card.joker(J.BIG),  # Red
		Card.normal(S.SPADE, R.FOUR),  # Black suit
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var has_spade := false
	for b: TrumpBidding.BidDeclaration in bids:
		if b.bid_type == BT.JOKER_SINGLE_RANK and b.suit == S.SPADE:
			has_spade = true
	assert_false(has_spade, "red joker + ♠ rank = rejected (color mismatch)")


# ============================================================
# Bidding: skip / no-bid scenarios
# ============================================================

func test_no_available_bids_no_rank_no_joker() -> void:
	# Hand has zero rank cards and zero jokers → cannot bid at all
	rc.bid_requires_joker = false
	var hand: Array = [
		Card.normal(S.SPADE, R.ACE),
		Card.normal(S.HEART, R.KING),
		Card.normal(S.DIAMOND, R.SEVEN),
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	assert_eq(bids.size(), 0, "no rank cards = no bids available")


func test_no_bid_default_keeps_dealer_as_princess() -> void:
	# All 4 players skip → set_no_bid_default → dealer stays, 公主局
	var gr := GameRound.new()
	gr.setup(rc, 2)  # dealer = seat 2
	gr.deal(12345)
	# Nobody bids → fallback
	gr.set_no_bid_default(2)
	assert_eq(gr.dealer_seat, 2, "dealer stays at seat 2")
	assert_eq(gr.trump_suit, -1, "公主局 = no trump")
	assert_eq(gr.dealer_team, [2, 0] as Array[int], "dealer team = [2,0]")
	assert_eq(gr.current_lead_seat, 2, "first lead = dealer")


# ============================================================
# ADR-0001: 5-tier bid strength refinement
# ============================================================

func test_strength_ladder_monotonic() -> void:
	# Enum values must be strictly monotonic (NONE < SR < PR < JSR < JPR < PJ).
	assert_lt(int(BT.NONE), int(BT.SINGLE_RANK), "NONE < SINGLE_RANK")
	assert_lt(int(BT.SINGLE_RANK), int(BT.PAIR_RANK), "SINGLE_RANK < PAIR_RANK")
	assert_lt(int(BT.PAIR_RANK), int(BT.JOKER_SINGLE_RANK), "PAIR_RANK < JOKER_SINGLE_RANK")
	assert_lt(int(BT.JOKER_SINGLE_RANK), int(BT.JOKER_PAIR_RANK), "JOKER_SINGLE_RANK < JOKER_PAIR_RANK")
	assert_lt(int(BT.JOKER_PAIR_RANK), int(BT.PAIR_JOKER), "JOKER_PAIR_RANK < PAIR_JOKER")


func test_strength_joker_pair_rank_beats_joker_single_rank() -> void:
	# ADR-0001: JOKER_PAIR_RANK can counter JOKER_SINGLE_RANK.
	var jsr := TrumpBidding.BidDeclaration.new(0, BT.JOKER_SINGLE_RANK, S.HEART)
	var jpr := TrumpBidding.BidDeclaration.new(1, BT.JOKER_PAIR_RANK, S.SPADE)
	assert_true(TrumpBidding.is_stronger(jpr, jsr), "JOKER_PAIR_RANK > JOKER_SINGLE_RANK")
	assert_false(TrumpBidding.is_stronger(jsr, jpr), "JOKER_SINGLE_RANK < JOKER_PAIR_RANK")


func test_strength_same_tier_different_suit_not_stronger() -> void:
	# AC14: same tier different suit must NOT be considered stronger (strict >).
	var jsr_red := TrumpBidding.BidDeclaration.new(0, BT.JOKER_SINGLE_RANK, S.HEART)
	var jsr_black := TrumpBidding.BidDeclaration.new(1, BT.JOKER_SINGLE_RANK, S.SPADE)
	assert_false(TrumpBidding.is_stronger(jsr_red, jsr_black), "same tier different suit ≠ stronger")
	assert_false(TrumpBidding.is_stronger(jsr_black, jsr_red), "same tier different suit ≠ stronger (rev)")


func test_joker_pair_rank_available_same_suit() -> void:
	# ADR-0001 AC: joker + 2 same-suit rank cards → JOKER_PAIR_RANK generated.
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = true
	var hand: Array = [
		Card.joker(J.BIG),  # red joker
		Card.normal(S.HEART, R.FOUR),
		Card.normal(S.HEART, R.FOUR),  # 2nd deck duplicate
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var jpr_count := 0
	var jsr_count := 0
	for b: TrumpBidding.BidDeclaration in bids:
		if b.bid_type == BT.JOKER_PAIR_RANK and b.suit == S.HEART:
			jpr_count += 1
		elif b.bid_type == BT.JOKER_SINGLE_RANK and b.suit == S.HEART:
			jsr_count += 1
	assert_eq(jpr_count, 1, "JOKER_PAIR_RANK ♥ generated exactly once")
	assert_eq(jsr_count, 1, "JOKER_SINGLE_RANK ♥ also still generated (weaker fallback)")


func test_joker_pair_rank_not_available_cross_suit() -> void:
	# ADR-0001: joker + ♥4 + ♦4 (cross-suit) must NOT generate JOKER_PAIR_RANK.
	# Per Decision: pair must be strictly same-suit (consistent with PAIR_RANK).
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = true
	var hand: Array = [
		Card.joker(J.BIG),  # red joker
		Card.normal(S.HEART, R.FOUR),
		Card.normal(S.DIAMOND, R.FOUR),  # cross-suit, both red, both 4
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	for b: TrumpBidding.BidDeclaration in bids:
		assert_ne(b.bid_type, BT.JOKER_PAIR_RANK,
			"cross-suit pair must not produce JOKER_PAIR_RANK (suit=%d)" % b.suit)


func test_joker_pair_rank_color_match_constraint() -> void:
	# ADR-0001: trump_joker_color_match still gates joker color even for JOKER_PAIR_RANK.
	# Red joker + 2× ♠4 (black) must reject both JOKER_SINGLE_RANK and JOKER_PAIR_RANK on ♠.
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = true
	var hand: Array = [
		Card.joker(J.BIG),  # red
		Card.normal(S.SPADE, R.FOUR),
		Card.normal(S.SPADE, R.FOUR),
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var spade_joker_bids := bids.filter(func(b: TrumpBidding.BidDeclaration) -> bool:
		return (b.bid_type == BT.JOKER_PAIR_RANK or b.bid_type == BT.JOKER_SINGLE_RANK) and b.suit == S.SPADE
	)
	assert_eq(spade_joker_bids.size(), 0, "red joker + ♠ pair = rejected (color mismatch)")


func test_joker_pair_rank_color_match_disabled_allows_cross_color() -> void:
	# trump_joker_color_match=false → red joker can pair black rank.
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = false
	var hand: Array = [
		Card.joker(J.BIG),  # red
		Card.normal(S.SPADE, R.FOUR),
		Card.normal(S.SPADE, R.FOUR),
	]
	var bids := TrumpBidding.get_available_bids(0, hand, R.FOUR, rc)
	var has_jpr_spade := false
	for b: TrumpBidding.BidDeclaration in bids:
		if b.bid_type == BT.JOKER_PAIR_RANK and b.suit == S.SPADE:
			has_jpr_spade = true
	assert_true(has_jpr_spade, "no color-match → JOKER_PAIR_RANK ♠ generated")
