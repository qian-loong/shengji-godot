## Trump bidding — bid declarations and strength comparison
## Implements: C3 Trump Bidding GDD (design/gdd/trump-bidding.md) — bid logic only
class_name TrumpBidding
extends RefCounted


# ============================================================
# Bid types
# ============================================================

## Bid types — 5 tiers, enum value = strength (see ADR-0001)
##   bid_requires_joker=false : SINGLE_RANK(1) < PAIR_RANK(2) < PAIR_JOKER(5)
##   bid_requires_joker=true  : JOKER_SINGLE_RANK(3) < JOKER_PAIR_RANK(4) < PAIR_JOKER(5)
enum BidType {
	NONE = 0,
	SINGLE_RANK = 1,         # 1 rank card (mode A only)
	PAIR_RANK = 2,           # 2 same-suit rank cards (mode A only)
	JOKER_SINGLE_RANK = 3,   # joker + 1 rank card (mode B only)
	JOKER_PAIR_RANK = 4,     # joker + 2 same-suit rank cards (mode B only)
	PAIR_JOKER = 5,          # 2 same jokers (公主, highest, cannot be countered)
}


## Bid declaration
class BidDeclaration:
	var seat_id: int
	var bid_type: int  # BidType
	var suit: int      # Card.Suit or -1 for 公主 (no trump suit)

	func _init(p_seat: int, p_type: int, p_suit: int) -> void:
		seat_id = p_seat
		bid_type = p_type
		suit = p_suit


# ============================================================
# Get available bids for a hand
# ============================================================

## Returns all valid bids a player can make given their hand and config
static func get_available_bids(seat_id: int, hand: Array, current_rank: int, rule_config: RuleConfig) -> Array:
	var bids: Array = []

	# Count rank cards per suit and jokers
	var rank_per_suit: Dictionary = {}  # suit -> count
	var joker_counts: Dictionary = {}   # JokerType -> count
	for c: Card in hand:
		if c.is_joker:
			joker_counts[c.joker_type] = joker_counts.get(c.joker_type, 0) + 1
		elif c.rank == current_rank:
			rank_per_suit[c.suit] = rank_per_suit.get(c.suit, 0) + 1

	# Check for PairJoker (公主) — always available if you have 2 same jokers
	for jt: int in joker_counts:
		if joker_counts[jt] >= 2:
			bids.append(BidDeclaration.new(seat_id, BidType.PAIR_JOKER, -1))
			break  # Only one 公主 bid possible

	if rule_config.bid_requires_joker:
		# JokerSingleRank / JokerPairRank: joker + 1 or 2 same-suit rank cards
		# trump_joker_color_match (if true) constrains joker color to match the suit color.
		for suit: int in rank_per_suit:
			var suit_color := Card.suit_color(suit)
			var has_matching_joker := false
			for jt: int in joker_counts:
				if joker_counts[jt] >= 1:
					var jcolor := Card.joker_color(jt)
					if not rule_config.trump_joker_color_match or jcolor == suit_color:
						has_matching_joker = true
						break
			if has_matching_joker:
				var rank_count: int = rank_per_suit[suit]
				bids.append(BidDeclaration.new(seat_id, BidType.JOKER_SINGLE_RANK, suit))
				if rank_count >= 2:
					bids.append(BidDeclaration.new(seat_id, BidType.JOKER_PAIR_RANK, suit))
	else:
		# SingleRank / PairRank
		for suit: int in rank_per_suit:
			var count: int = rank_per_suit[suit]
			bids.append(BidDeclaration.new(seat_id, BidType.SINGLE_RANK, suit))
			if count >= 2:
				bids.append(BidDeclaration.new(seat_id, BidType.PAIR_RANK, suit))

	return bids


# ============================================================
# Bid strength comparison
# ============================================================

## Returns true if challenger bid is strictly stronger than current bid
static func is_stronger(challenger: BidDeclaration, current: BidDeclaration) -> bool:
	return _bid_strength(challenger) > _bid_strength(current)


## Check if a bid can be countered.
## ADR-0002: PAIR_JOKER (公主) AND JOKER_PAIR_RANK (王+对) are both immune.
##   - PAIR_JOKER: highest strength tier, no stronger bid exists by enum value.
##   - JOKER_PAIR_RANK: only PAIR_JOKER would be strictly stronger; per ADR-0002
##                     we shield it as well, making JPR a "counter-shield" so
##                     that the dealer's 3-key-card investment can't be reversed
##                     by attackers' 2-card pair-joker hand.
static func can_be_countered(bid: BidDeclaration) -> bool:
	if bid.bid_type == BidType.PAIR_JOKER:
		return false
	if bid.bid_type == BidType.JOKER_PAIR_RANK:
		return false
	return true


static func _bid_strength(bid: BidDeclaration) -> int:
	return bid.bid_type  # Enum values are ordered by strength


# ============================================================
# Display helpers (ADR-0001)
# ============================================================

## Human-readable label for a bid declaration covering all 5 tiers.
##   PAIR_JOKER         → "公主(无主)"
##   JOKER_PAIR_RANK    → "王+对 ♥"
##   JOKER_SINGLE_RANK  → "王+单 ♥"
##   PAIR_RANK          → "对 ♥"
##   SINGLE_RANK        → "单 ♥"
##   null / NONE        → "—"
static func bid_label(decl: BidDeclaration) -> String:
	if decl == null:
		return "—"
	if decl.bid_type == BidType.PAIR_JOKER or decl.suit < 0:
		return "公主(无主)"
	var suit_sym := Card.suit_symbol(decl.suit)
	match decl.bid_type:
		BidType.SINGLE_RANK: return "单 %s" % suit_sym
		BidType.PAIR_RANK: return "对 %s" % suit_sym
		BidType.JOKER_SINGLE_RANK: return "王+单 %s" % suit_sym
		BidType.JOKER_PAIR_RANK: return "王+对 %s" % suit_sym
		_: return suit_sym
