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
##
## `rank` records the Card.Rank of the rank-card part of the declaration
## (ADR-0004). It is `-1` for `PAIR_JOKER` (公主) which consumes only jokers
## and has no rank component. All other bid types carry the exact rank they
## were generated with — for the dealer this is the current game round rank;
## for a counter-bid this must equal `state.current_rank`, enforced by
## `SessionController.submit_counter_or_pass` via `matches_rank`.
class BidDeclaration:
	var seat_id: int
	var bid_type: int  # BidType
	var suit: int      # Card.Suit or -1 for 公主 (no trump suit)
	var rank: int      # Card.Rank; -1 for PAIR_JOKER (rank 无关)

	func _init(p_seat: int, p_type: int, p_suit: int, p_rank: int = -1) -> void:
		seat_id = p_seat
		bid_type = p_type
		suit = p_suit
		rank = p_rank


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
	# ADR-0004: PAIR_JOKER consumes only jokers, no rank component (rank = -1).
	for jt: int in joker_counts:
		if joker_counts[jt] >= 2:
			bids.append(BidDeclaration.new(seat_id, BidType.PAIR_JOKER, -1, -1))
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
				bids.append(BidDeclaration.new(seat_id, BidType.JOKER_SINGLE_RANK, suit, current_rank))
				if rank_count >= 2:
					bids.append(BidDeclaration.new(seat_id, BidType.JOKER_PAIR_RANK, suit, current_rank))
	else:
		# SingleRank / PairRank
		for suit: int in rank_per_suit:
			var count: int = rank_per_suit[suit]
			bids.append(BidDeclaration.new(seat_id, BidType.SINGLE_RANK, suit, current_rank))
			if count >= 2:
				bids.append(BidDeclaration.new(seat_id, BidType.PAIR_RANK, suit, current_rank))

	return bids


# ============================================================
# Bid strength comparison
# ============================================================

## Returns true if challenger bid is strictly stronger than current bid.
##
## Compares strength (BidType enum value) only — rank matching is a separate
## dimension enforced by `matches_rank` for counter-bids (ADR-0004).
static func is_stronger(challenger: BidDeclaration, current: BidDeclaration) -> bool:
	return _bid_strength(challenger) > _bid_strength(current)


## Returns true if the bid's rank-card part matches the given rank.
##
## Used by `SessionController.submit_counter_or_pass` (ADR-0004) to enforce
## that a counter-bid's rank cards must equal `state.current_rank`
## (the current round's rank, = dealer's team rank). `PAIR_JOKER` is
## exempt because it consumes only jokers and carries no rank component.
static func matches_rank(bid: BidDeclaration, current_rank: int) -> bool:
	return bid.bid_type == BidType.PAIR_JOKER or bid.rank == current_rank


## Whether a winning bid can still be overturned in the counter window.
##
## Rule (ADR-0002 + ADR-0003): only the *single* entry tier of each ladder is
## counterable. The "pair" tier and everything above it is counter-immune,
## symmetrically across both bid modes:
##
##   mode A (no joker): SINGLE_RANK ✅ | PAIR_RANK ❌ | PAIR_JOKER ❌
##   mode B (joker):    JOKER_SINGLE_RANK ✅ | JOKER_PAIR_RANK ❌ | PAIR_JOKER ❌
##
## Rationale: committing a *pair* of key cards (or a pair of jokers) is a real
## investment that should not be reversible by an opponent's single 2-card
## hand. Single-card declarations carry no such investment and stay contestable.
## NONE / unknown types are treated as non-counterable (nothing to overturn).
static func can_be_countered(bid: BidDeclaration) -> bool:
	return bid.bid_type == BidType.SINGLE_RANK or bid.bid_type == BidType.JOKER_SINGLE_RANK


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
