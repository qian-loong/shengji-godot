## Shared multi-round session controller.
## This class owns session orchestration without depending on UI nodes.
class_name SessionController
extends RefCounted


var rule_config: RuleConfig
var logger: GameLogger
var state: SessionState
var game_round: GameRound
var current_phase: String = "idle"
var last_settlement: UpgradeSettlement.SettlementResult = null
var bid_seat_index: int = 0
var bidding_resolved: bool = false
var trick_num: int = 0
var trick_play_cards: Array = []
var trick_seat_index: int = 0
var trick_seat_order: Array[int] = []
var trick_lead_info: Dictionary = {}
var last_trick_result: Dictionary = {}


func _init(
	p_rule_config: RuleConfig = null,
	p_logger: GameLogger = null,
	p_state: SessionState = null,
) -> void:
	state = p_state if p_state != null else SessionState.new()
	state.reset()
	if p_rule_config != null:
		start_new_session(p_rule_config, p_logger, state.human_seat)


func start_new_session(
	p_rule_config: RuleConfig,
	p_logger: GameLogger = null,
	p_human_seat: int = 0,
) -> void:
	rule_config = p_rule_config
	logger = p_logger
	state.reset(p_human_seat)
	game_round = null
	last_settlement = null
	current_phase = "idle"
	if logger:
		logger.set_rule_config(rule_config)


func start_round(seed_value: int = -1) -> Dictionary:
	if rule_config == null:
		return _error("missing_rule_config")

	var round_seed := seed_value if seed_value >= 0 else randi()
	var round_rank := state.begin_round_for_current_dealer()
	rule_config.current_rank = round_rank

	game_round = GameRound.new()
	game_round.setup(rule_config, state.current_dealer)
	game_round.logger = logger

	if logger:
		logger.begin_round(
			state.round_num,
			state.current_rank,
			state.current_dealer,
			round_seed,
			state.team_ranks
		)

	game_round.deal(round_seed)
	current_phase = "bidding"
	bid_seat_index = 0
	bidding_resolved = false
	last_settlement = null

	return _ok({
		"phase": current_phase,
		"round_num": state.round_num,
		"seed": round_seed,
		"current_rank": state.current_rank,
		"current_dealer": state.current_dealer,
	})


func get_bidding_context(seat: int) -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	var hand := game_round.get_hand(seat)
	var bid_rank := state.get_team_rank_for_seat(seat)
	return _ok({
		"phase": current_phase,
		"seat": seat,
		"hand": hand,
		"bid_rank": bid_rank,
		"available_bids": TrumpBidding.get_available_bids(seat, hand, bid_rank, rule_config),
		"is_first_game": state.is_first_game,
	})


func get_current_bid_seat() -> int:
	return (state.current_dealer + bid_seat_index) % 4


func submit_bid_or_pass(
	seat: int,
	declaration: TrumpBidding.BidDeclaration = null,
	pass_reason: String = "player_choice",
) -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "bidding":
		return _error("not_bidding")
	if game_round.bid_declaration != null:
		_log_bid_skip(seat, "already_bid")
		return finish_bidding_if_ready()

	if declaration == null:
		_log_bid_skip(seat, pass_reason)
		return _ok({ "phase": current_phase, "bid_made": false })

	if game_round.process_bid(declaration):
		bidding_resolved = true
		if logger:
			logger.log_bid_attempt(seat, "bid", "", declaration.suit)
		return finish_bidding_if_ready()

	_log_bid_skip(seat, "bid_rejected")
	return _error("bid_rejected")


func resolve_no_bid_default() -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "bidding":
		return _error("not_bidding")
	if game_round.bid_declaration == null:
		game_round.set_no_bid_default(state.current_dealer)
	bidding_resolved = true
	return finish_bidding_if_ready()


func finish_bidding_if_ready() -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if not bidding_resolved:
		return _ok({ "phase": current_phase, "bid_made": false })
	sync_rank_to_actual_dealer()
	current_phase = "burying"
	return _ok({
		"phase": current_phase,
		"bid_made": game_round.bid_declaration != null,
		"dealer": game_round.dealer_seat,
		"trump_suit": game_round.trump_suit,
		"current_rank": state.current_rank,
	})


func get_bury_context() -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "burying":
		return _error("not_burying")
	return _ok({
		"phase": current_phase,
		"dealer": game_round.dealer_seat,
		"merged_hand": game_round.get_dealer_hand_with_bottom(),
		"bottom_size": rule_config.bottom_size,
		"trump_suit": game_round.trump_suit,
		"current_rank": state.current_rank,
	})


func submit_bury(indices: Array[int]) -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "burying":
		return _error("not_burying")
	var result := game_round.execute_bury(indices)
	if not result.get("ok", false):
		return _error(str(result.get("error", "bury_failed")))
	current_phase = "playing"
	trick_num = 0
	_reset_trick_state()
	return _ok({
		"phase": current_phase,
		"dealer": game_round.dealer_seat,
		"buried": result.get("buried", []),
	})


func begin_trick() -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "playing":
		return _error("not_playing")
	if game_round.get_hand_size(0) <= 0:
		return _ok({ "phase": "settlement", "round_complete": true })

	trick_num += 1
	trick_play_cards = []
	trick_seat_index = 0
	trick_seat_order = game_round.get_seat_order_from_lead()
	trick_lead_info = {}
	last_trick_result = {}
	return _ok({
		"phase": current_phase,
		"trick_num": trick_num,
		"lead_seat": game_round.current_lead_seat,
		"seat_order": trick_seat_order.duplicate(),
		"attack_score": game_round.score_tracker.get_attack_score(),
	})


func get_current_turn_context() -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "playing":
		return _error("not_playing")
	if trick_seat_order.is_empty():
		var started := begin_trick()
		if not started["ok"]:
			return started
	if trick_seat_index >= trick_seat_order.size():
		return _ok({ "phase": current_phase, "trick_ready": true })
	var seat: int = trick_seat_order[trick_seat_index]
	return _ok({
		"phase": current_phase,
		"seat": seat,
		"hand": game_round.get_hand(seat),
		"is_leading": trick_lead_info.is_empty(),
		"lead_info": trick_lead_info.duplicate(),
		"lead_count": 0 if trick_play_cards.is_empty() else trick_play_cards[0].size(),
		"game_state": make_game_state(),
		"trick_num": trick_num,
	})


func submit_play(seat: int, cards: Array) -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "playing":
		return _error("not_playing")
	if trick_seat_order.is_empty():
		var started := begin_trick()
		if not started["ok"]:
			return started
	if trick_seat_index >= trick_seat_order.size():
		return _error("trick_already_ready")

	var expected_seat: int = trick_seat_order[trick_seat_index]
	if seat != expected_seat:
		return _error("wrong_turn")
	if cards.is_empty():
		return _error("empty_play")

	var hand := game_round.get_hand(seat)
	var is_leading := trick_lead_info.is_empty()
	if is_leading:
		var pattern := PlayValidator.validate_lead(
			cards,
			hand,
			game_round.trump_suit,
			state.current_rank,
			rule_config
		)
		if pattern == null:
			return _error("invalid_lead")
		trick_lead_info = _make_lead_info(cards, pattern)
	else:
		var lead_count: int = trick_play_cards[0].size()
		if cards.size() != lead_count:
			return _error("wrong_card_count")
		var valid := PlayValidator.validate_follow(
			cards,
			hand,
			lead_count,
			trick_lead_info["domain"],
			game_round.trump_suit,
			state.current_rank,
			rule_config,
			trick_lead_info.get("pattern")
		)
		if not valid:
			return _error("invalid_follow")

	trick_play_cards.append(cards)
	trick_seat_index += 1

	if trick_seat_index >= trick_seat_order.size():
		last_trick_result = game_round.play_trick(trick_play_cards)
		_reset_trick_state()
		return _ok({
			"phase": current_phase,
			"trick_complete": true,
			"result": last_trick_result,
		})

	return _ok({
		"phase": current_phase,
		"trick_complete": false,
		"next_seat": trick_seat_order[trick_seat_index],
		"lead_info": trick_lead_info.duplicate(),
	})


func make_game_state() -> Dictionary:
	if game_round == null:
		return {}
	return {
		"trump_suit": game_round.trump_suit,
		"current_rank": state.current_rank,
		"dealer_seat": game_round.dealer_seat,
		"attack_score": game_round.score_tracker.get_attack_score(),
	}


func sync_rank_to_actual_dealer() -> int:
	if game_round == null:
		return state.current_rank
	var rank := state.sync_rank_to_dealer(game_round.dealer_seat)
	rule_config.current_rank = rank
	game_round.current_rank = rank
	if logger:
		logger.update_round_rank(rank, state.team_ranks)
	return rank


func _make_lead_info(cards: Array, pattern: CardPattern.PatternResult) -> Dictionary:
	return {
		"domain": TrumpJudge.get_suit_domain(
			cards[0],
			game_round.trump_suit,
			state.current_rank,
			rule_config.joker_always_trump
		),
		"count": cards.size(),
		"pattern": pattern,
	}


func _reset_trick_state() -> void:
	trick_play_cards = []
	trick_seat_index = 0
	trick_seat_order = []
	trick_lead_info = {}


func _log_bid_skip(seat: int, reason: String) -> void:
	if logger:
		logger.log_bid_attempt(seat, "skip", reason)


func finish_round() -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase == "round_end" or current_phase == "game_over":
		return _error("round_already_finished")

	var actual_dealer := game_round.dealer_seat
	var attack_rank := state.team_ranks[SessionState.get_attack_team(actual_dealer)]
	last_settlement = game_round.calculate_settlement(attack_rank)
	if logger:
		logger.end_round()

	var applied := state.apply_settlement(last_settlement, actual_dealer)
	current_phase = "game_over" if state.game_over else "round_end"
	applied["phase"] = current_phase
	applied["settlement"] = last_settlement
	return _ok(applied)


func get_round_summary() -> Dictionary:
	return {
		"phase": current_phase,
		"round_num": state.round_num,
		"current_dealer": state.current_dealer,
		"current_rank": state.current_rank,
		"team_ranks": state.team_ranks.duplicate(),
		"is_first_game": state.is_first_game,
		"game_over": state.game_over,
	}


static func _ok(extra: Dictionary = {}) -> Dictionary:
	var result := { "ok": true }
	for key in extra:
		result[key] = extra[key]
	return result


static func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
