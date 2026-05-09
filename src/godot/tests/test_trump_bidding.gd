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
		if b.bid_type == BT.JOKER_RANK:
			has_joker_rank = true
	assert_true(has_joker_rank, "JokerRank should be available")


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
		if b.bid_type == BT.JOKER_RANK and b.suit == S.HEART:
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
		if b.bid_type == BT.JOKER_RANK and b.suit == S.SPADE:
			has_spade = true
	assert_false(has_spade, "red joker + ♠ rank = rejected (color mismatch)")
