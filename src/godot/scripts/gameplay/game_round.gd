## Game round — complete single-round game loop
## Implements: C7 Game State Machine GDD (design/gdd/game-state-machine.md)
## This is the logic layer; terminal interaction is in game_session.gd
class_name GameRound
extends RefCounted


signal trick_completed(trick_result: Dictionary)
signal round_completed(settlement: UpgradeSettlement.SettlementResult)


# ============================================================
# Round state
# ============================================================

var rule_config: RuleConfig
var hands: Array  # Array of Array[Card], index = seat_id
var bottom: Array  # Card[]
var buried_bottom: Array  # Card[] — what dealer actually buried
var trump_suit: int = -1
var current_rank: int
var dealer_seat: int = 0
var current_lead_seat: int = 0
var score_tracker: ScoreTracker
var tricks_played: int = 0
var last_trick_winner: int = -1
var last_trick_pattern: CardPattern.PatternResult = null
var bid_declaration: TrumpBidding.BidDeclaration = null
var logger: GameLogger = null

# Team config: seats 0,2 vs 1,3
# Dealer's team = dealer side, other team = attack side
var dealer_team: Array[int] = []
var attack_team: Array[int] = []


# ============================================================
# Initialize round
# ============================================================

func setup(rc: RuleConfig, p_dealer_seat: int) -> void:
	rule_config = rc
	current_rank = rc.current_rank
	dealer_seat = p_dealer_seat
	current_lead_seat = p_dealer_seat
	score_tracker = ScoreTracker.new(rc.total_score)

	# Set teams
	dealer_team = [dealer_seat, (dealer_seat + 2) % 4]
	attack_team = []
	for i: int in range(4):
		if i not in dealer_team:
			attack_team.append(i)


# ============================================================
# Phase 1: Deal
# ============================================================

func deal(seed_value: int = -1) -> void:
	var cards := DeckManager.generate_deck(rule_config.deck_count)
	DeckManager.shuffle(cards, seed_value)
	var result := DeckManager.deal(cards, rule_config.hand_size, rule_config.bottom_size)
	hands = result["hands"]
	bottom = result["bottom"]
	if logger:
		logger.log_initial_hands(hands, bottom)


# ============================================================
# Phase 2: Bidding
# ============================================================

## Process bid from a player. Returns true if bid was accepted.
func process_bid(declaration: TrumpBidding.BidDeclaration) -> bool:
	if bid_declaration != null:
		# First game: first come first served, cannot override
		return false
	bid_declaration = declaration
	trump_suit = declaration.suit  # -1 for 公主
	dealer_seat = declaration.seat_id
	# Recalculate teams
	dealer_team = [dealer_seat, (dealer_seat + 2) % 4]
	attack_team = []
	for i: int in range(4):
		if i not in dealer_team:
			attack_team.append(i)
	current_lead_seat = dealer_seat
	if logger:
		logger.log_bid(declaration)
		logger.log_trump_determined(trump_suit)
	return true


## If no one bid, set defaults (公主)
func set_no_bid_default(human_seat: int) -> void:
	trump_suit = -1  # 公主 = no trump suit
	dealer_seat = human_seat
	dealer_team = [dealer_seat, (dealer_seat + 2) % 4]
	attack_team = []
	for i: int in range(4):
		if i not in dealer_team:
			attack_team.append(i)
	current_lead_seat = dealer_seat
	# Force joker_always_trump for 公主
	rule_config.joker_always_trump = true
	if logger:
		logger.log_bid(null, true)
		logger.set_no_bid_dealer(dealer_seat)
		logger.log_trump_determined(trump_suit)


# ============================================================
# Phase 3: Bottom bury
# ============================================================

func get_dealer_hand_with_bottom() -> Array:
	return BottomManager.reveal_bottom(hands[dealer_seat], bottom)


func execute_bury(selected_indices: Array[int]) -> Dictionary:
	var merged := get_dealer_hand_with_bottom()
	var result := BottomManager.bury_bottom(merged, selected_indices, rule_config.bottom_size)
	if result["ok"]:
		hands[dealer_seat] = result["new_hand"]
		buried_bottom = result["buried"]
		if logger:
			logger.log_bury(merged, selected_indices, buried_bottom, hands[dealer_seat])
	return result


# ============================================================
# Phase 4: Play tricks
# ============================================================

## Play one complete trick (4 plays).
## Returns: { "plays": Array, "winner": int, "score": int, "is_last": bool }
func play_trick(play_cards: Array) -> Dictionary:
	var plays: Array = []
	var all_trick_cards: Array = []
	var jat := rule_config.joker_always_trump

	# Log hands before trick
	if logger:
		logger.begin_trick(tricks_played + 1, current_lead_seat, score_tracker.get_attack_score())
		logger.log_hands_before_trick(hands, trump_suit, current_rank, jat)

	for i: int in range(4):
		var seat := (current_lead_seat + i) % 4  # 逆时针: 0南→1东→2北→3西
		var cards: Array = play_cards[i]

		# Log each play
		if logger:
			logger.log_play(seat, cards, trump_suit, current_rank, jat)

		# Remove cards from hand
		for c: Card in cards:
			_remove_card_from_hand(seat, c)

		var pattern := CardPattern.identify(cards, current_rank,
			rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)

		plays.append({
			"seat": seat,
			"cards": cards,
			"pattern": pattern,
		})
		all_trick_cards.append_array(cards)

	# Determine winner
	var lead_domain := TrumpJudge.get_suit_domain(
		plays[0]["cards"][0], trump_suit, current_rank, jat)
	var winner := PlayValidator.determine_winner(plays, lead_domain, trump_suit, current_rank, rule_config)

	# Record score
	var winner_is_attack := winner in attack_team
	var trick_score := score_tracker.record_trick(all_trick_cards, winner_is_attack)

	tricks_played += 1
	last_trick_winner = winner
	last_trick_pattern = plays[_get_winner_play_index(plays, winner)]["pattern"]
	current_lead_seat = winner

	var is_last := _is_last_trick()

	var result := {
		"plays": plays,
		"winner": winner,
		"score": trick_score,
		"is_last": is_last,
		"attack_score": score_tracker.get_attack_score(),
	}

	if logger:
		var side_str := "attack" if winner_is_attack else "dealer"
		logger.log_trick_result(winner, trick_score, score_tracker.get_attack_score(),
			"winner=%d (%s), lead_domain=%s" % [winner, side_str, str(lead_domain)])

	return result


func _get_winner_play_index(plays: Array, winner_seat: int) -> int:
	for i: int in range(plays.size()):
		if plays[i]["seat"] == winner_seat:
			return i
	return 0


func _is_last_trick() -> bool:
	for h: Array in hands:
		if h.size() > 0:
			return false
	return true


func _remove_card_from_hand(seat: int, card: Card) -> void:
	for i: int in range(hands[seat].size()):
		if hands[seat][i].equals(card):
			hands[seat].remove_at(i)
			return


# ============================================================
# Phase 5: Settlement
# ============================================================

func calculate_settlement() -> UpgradeSettlement.SettlementResult:
	var last_winner_is_attack := last_trick_winner in attack_team
	var s := UpgradeSettlement.calculate(
		score_tracker.get_attack_score(),
		buried_bottom,
		dealer_seat,
		last_winner_is_attack,
		last_trick_pattern,
		current_rank,
		rule_config,
	)
	if logger:
		logger.log_settlement(s)
	return s


# ============================================================
# Helpers
# ============================================================

func is_attack(seat: int) -> bool:
	return seat in attack_team

func get_hand(seat: int) -> Array:
	return hands[seat]

func get_hand_size(seat: int) -> int:
	return hands[seat].size()

func get_seat_order_from_lead() -> Array[int]:
	# 逆时针: 0南→1东→2北→3西
	var order: Array[int] = []
	for i: int in range(4):
		order.append((current_lead_seat + i) % 4)
	return order
