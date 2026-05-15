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
	last_settlement = null

	return _ok({
		"phase": current_phase,
		"round_num": state.round_num,
		"seed": round_seed,
		"current_rank": state.current_rank,
		"current_dealer": state.current_dealer,
	})


func sync_rank_to_actual_dealer() -> int:
	if game_round == null:
		return state.current_rank
	var rank := state.sync_rank_to_dealer(game_round.dealer_seat)
	rule_config.current_rank = rank
	game_round.current_rank = rank
	if logger:
		logger.update_round_rank(rank, state.team_ranks)
	return rank


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
