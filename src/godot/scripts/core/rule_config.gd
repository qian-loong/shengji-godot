## Rule configuration system for 双升对局
## Implements: F3 Rule Config GDD (design/gdd/rule-config.md)
##
## Single source of truth for all configurable game rules.
## Generates an immutable snapshot (locked) before each round.
class_name RuleConfig
extends RefCounted


# ============================================================
# Enums
# ============================================================

enum TrumpMode {
	BID,       # 亮主
	GRAB,      # 抢主 (first game only)
	COUNTER,   # 反主
	FIXED,     # 固定主
	NO_TRUMP,  # 无主
}

enum ConfigState {
	EDITING,
	LOCKED,
}


# ============================================================
# Properties — Deck (F3 §2.1)
# ============================================================

var deck_count: int = 2
var current_rank: int = Card.Rank.TWO  # int to allow Rank enum values


# ============================================================
# Properties — Derived (read-only, computed from deck_count)
# ============================================================

var hand_size: int:
	get:
		return 25 if deck_count == 2 else 12

var bottom_size: int:
	get:
		return 8 if deck_count == 2 else 6

var total_cards: int:
	get:
		return deck_count * 54

var total_score: int:
	get:
		return deck_count * 100


# ============================================================
# Properties — Trump (F3 §2.2)
# ============================================================

var trump_mode: TrumpMode = TrumpMode.BID
var fixed_trump_suit: int = -1  # Card.Suit value or -1 for null
var joker_always_trump: bool = true
var trump_joker_color_match: bool = true
var bid_requires_joker: bool = true


# ============================================================
# Properties — Play (F3 §2.3)
# ============================================================

var allow_dump: bool = true
var strict_follow_structure: bool = true
var four_same_is_tractor: bool = false
var tractor_allow_rank_card: bool = true


# ============================================================
# Properties — Settlement (F3 §2.4)
# ============================================================

var upgrade_threshold: int = 80
var upgrade_step: int = 1

## Upgrade thresholds: [score_min, upgrading_side, levels]
## Side: 0 = dealer, 1 = attack
var upgrade_table: Array[Array] = [
	[0,   0, 2],  # attack=0: dealer upgrades 2
	[1,   0, 1],  # attack 1-39: dealer upgrades 1
	[40,  0, 0],  # attack 40-79: dealer stays, no upgrade
	[80,  1, 0],  # attack 80-119: attack dethrones, no upgrade
	[120, 1, 1],  # attack 120-149: attack upgrades 1
	[150, 1, 2],  # attack 150-199: attack upgrades 2
	[200, 1, 3],  # attack 200: attack upgrades 3
]

## Ranks that cannot be skipped during upgrade
var no_skip_ranks: Array[int] = [Card.Rank.FIVE, Card.Rank.TEN, Card.Rank.KING]
var no_skip_enabled: bool = true


# ============================================================
# Properties — Dealer (F3 §2.5)
# ============================================================

var initial_dealer: int = -1  # -1 = determined by bidding


# ============================================================
# State
# ============================================================

var _state: ConfigState = ConfigState.EDITING


# ============================================================
# Validation (F3 §3)
# ============================================================

func validate() -> Array[String]:
	var errors: Array[String] = []

	if deck_count < 1 or deck_count > 2:
		errors.append("deck_count must be 1 or 2")

	if trump_mode == TrumpMode.FIXED and fixed_trump_suit < 0:
		errors.append("fixed_trump_suit required when trump_mode is FIXED")

	if upgrade_threshold > total_score:
		errors.append("upgrade_threshold (%d) exceeds total_score (%d)" % [upgrade_threshold, total_score])

	# Auto-correct: four_same_is_tractor impossible with 1 deck
	if deck_count == 1 and four_same_is_tractor:
		four_same_is_tractor = false

	return errors


# ============================================================
# Lock / Unlock
# ============================================================

func lock() -> Array[String]:
	var errors := validate()
	if errors.is_empty():
		_state = ConfigState.LOCKED
	return errors


func unlock() -> void:
	_state = ConfigState.EDITING


func is_locked() -> bool:
	return _state == ConfigState.LOCKED


# ============================================================
# Duplicate (for creating snapshot)
# ============================================================

func create_snapshot() -> RuleConfig:
	var snap := RuleConfig.new()
	snap.deck_count = deck_count
	snap.current_rank = current_rank
	snap.trump_mode = trump_mode
	snap.fixed_trump_suit = fixed_trump_suit
	snap.joker_always_trump = joker_always_trump
	snap.trump_joker_color_match = trump_joker_color_match
	snap.bid_requires_joker = bid_requires_joker
	snap.allow_dump = allow_dump
	snap.strict_follow_structure = strict_follow_structure
	snap.four_same_is_tractor = four_same_is_tractor
	snap.tractor_allow_rank_card = tractor_allow_rank_card
	snap.upgrade_threshold = upgrade_threshold
	snap.upgrade_step = upgrade_step
	snap.upgrade_table = upgrade_table.duplicate(true)
	snap.no_skip_ranks = no_skip_ranks.duplicate()
	snap.no_skip_enabled = no_skip_enabled
	snap.initial_dealer = initial_dealer
	return snap
