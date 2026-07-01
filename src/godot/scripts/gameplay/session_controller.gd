## Shared multi-round session controller.
## This class owns session orchestration without depending on UI nodes.
class_name SessionController
extends RefCounted


var rule_config: RuleConfig
var logger: GameLogger
var state: SessionState
var game_round: GameRound
var current_phase: String = "idle"
## 最近一次 finish_round 产出的裁决对象。
## 类型是 EffectiveSettlement（会话层裁决后的值），与真实 state 一致；
## 需要读原始提案时用 last_settlement.proposal。
var last_settlement: EffectiveSettlement = null
var bid_seat_index: int = 0
var bidding_resolved: bool = false
var trick_num: int = 0
var trick_play_cards: Array = []
var trick_seat_index: int = 0
var trick_seat_order: Array[int] = []
var trick_lead_info: Dictionary = {}
var last_trick_result: Dictionary = {}

# Counter-bid window state.
# counter_seat_order: attack-team seats polled in seat order (clockwise from dealer+1)
# counter_seat_index: cursor inside counter_seat_order
var counter_seat_index: int = 0
var counter_seat_order: Array[int] = []


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
	counter_seat_order = []
	counter_seat_index = 0

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
		# bury_seat == dealer for the original bury; == counter_seat after counter.
		# Hosts that need to know "whose hand is being shown" should consume bury_seat.
		"bury_seat": game_round.bury_seat,
		"is_counter_re_bury": state.counter_attempted,
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

	# Two paths share this method:
	#   - Dealer's first bury (counter_attempted == false) -> may open counter window
	#   - Counter winner's re-bury  (counter_attempted == true) -> straight to playing
	if not state.counter_attempted:
		return _open_counter_window_or_play(result.get("buried", []))

	current_phase = "playing"
	trick_num = 0
	_reset_trick_state()
	return _ok({
		"phase": current_phase,
		"dealer": game_round.dealer_seat,
		"bury_seat": game_round.bury_seat,
		"buried": result.get("buried", []),
		"counter_seat": game_round.counter_seat,
	})


# ============================================================
# Counter-bid window
# ============================================================

## Decide whether to open the counter window (only after dealer's first bury).
## See counter-bid-plan.md §2 for the skip conditions.
func _should_open_counter_window() -> bool:
	if state.is_first_game:
		return false
	if game_round == null or game_round.bid_declaration == null:
		return false
	if not TrumpBidding.can_be_countered(game_round.bid_declaration):
		return false
	if state.counter_attempted:
		return false
	# At least one attack-team seat must be able to counter (i.e., own a stronger bid).
	# To keep this method cheap and side-effect free we skip the per-hand check here;
	# get_counter_context()/submit_counter_or_pass() will surface "no available counter"
	# as natural pass. The window may open and immediately close in that case.
	return true


func _open_counter_window_or_play(buried: Array = []) -> Dictionary:
	if _should_open_counter_window():
		counter_seat_order = []
		# Attack-team seats only, polled in clockwise order starting from dealer+1.
		var dealer := game_round.dealer_seat
		for offset: int in [1, 2, 3]:
			var seat := (dealer + offset) % 4
			if seat in game_round.attack_team:
				counter_seat_order.append(seat)
		counter_seat_index = 0
		current_phase = "counter_window"
		return _ok({
			"phase": current_phase,
			"dealer": dealer,
			"buried": buried,
			"counter_seat_order": counter_seat_order.duplicate(),
		})

	# No counter window: dealer's bury is final, jump straight to playing.
	state.counter_attempted = true
	current_phase = "playing"
	trick_num = 0
	_reset_trick_state()
	return _ok({
		"phase": current_phase,
		"dealer": game_round.dealer_seat,
		"bury_seat": game_round.bury_seat,
		"buried": buried,
		"counter_skipped": true,
	})


func get_current_counter_seat() -> int:
	if counter_seat_order.is_empty():
		return -1
	if counter_seat_index >= counter_seat_order.size():
		return -1
	return counter_seat_order[counter_seat_index]


## Returns counter-bid context for one attacker:
## { seat, hand, current_bid, current_rank, available_counter_bids[], has_any: bool }
func get_counter_context(seat: int) -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "counter_window":
		return _error("not_counter_window")
	if seat != get_current_counter_seat():
		return _error("wrong_counter_seat")

	var hand := game_round.get_hand(seat)
	# ADR-0004: counter-bids must use the *current round rank* (dealer's team
	# rank), not the counter-attacker's own team rank. This makes UI options
	# consistent with `AIPlayer.decide_counter` which already uses current_rank.
	var bid_rank := state.current_rank
	var available := TrumpBidding.get_available_bids(seat, hand, bid_rank, rule_config)
	var stronger: Array = []
	for b: TrumpBidding.BidDeclaration in available:
		if TrumpBidding.is_stronger(b, game_round.bid_declaration):
			stronger.append(b)
	return _ok({
		"phase": current_phase,
		"seat": seat,
		"hand": hand,
		"current_bid": game_round.bid_declaration,
		"current_rank": state.current_rank,
		"available_counter_bids": stronger,
		"has_any": not stronger.is_empty(),
	})


func submit_counter_or_pass(
	seat: int,
	declaration: TrumpBidding.BidDeclaration = null,
	pass_reason: String = "player_choice",
) -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase != "counter_window":
		return _error("not_counter_window")
	if seat != get_current_counter_seat():
		return _error("wrong_counter_seat")
	if not (seat in game_round.attack_team):
		return _error("not_attack_team")

	if declaration == null:
		# Pass — advance to next attacker, or close window if exhausted.
		if logger:
			logger.log_bid_attempt(seat, "counter_pass", pass_reason)
		counter_seat_index += 1
		if counter_seat_index >= counter_seat_order.size():
			return _finish_counter_window_no_change()
		return _ok({
			"phase": current_phase,
			"counter_made": false,
			"next_seat": get_current_counter_seat(),
		})

	if declaration.seat_id != seat:
		return _error("seat_mismatch")
	if not TrumpBidding.is_stronger(declaration, game_round.bid_declaration):
		if logger:
			logger.log_bid_attempt(seat, "counter_rejected", "not_stronger")
		return _error("counter_not_stronger")
	# ADR-0004 门 2: defensive rank check. Counter-bids must use current-round
	# rank cards (PAIR_JOKER exempt). Rejects hand-crafted declarations that
	# bypass `get_counter_context`'s candidate filter (门 1).
	if not TrumpBidding.matches_rank(declaration, state.current_rank):
		if logger:
			logger.log_bid_attempt(seat, "counter_rejected", "rank_mismatch")
		return _error("counter_rank_mismatch")
	if not _counter_declaration_is_available(seat, declaration):
		if logger:
			logger.log_bid_attempt(seat, "counter_rejected", "not_in_hand")
		return _error("counter_not_in_hand")

	return _apply_counter(declaration)


func _counter_declaration_is_available(seat: int, declaration: TrumpBidding.BidDeclaration) -> bool:
	var context := get_counter_context(seat)
	if not context.get("ok", false):
		return false
	for available: TrumpBidding.BidDeclaration in context.get("available_counter_bids", []):
		if _same_bid_declaration(available, declaration):
			return true
	return false


static func _same_bid_declaration(
	a: TrumpBidding.BidDeclaration,
	b: TrumpBidding.BidDeclaration,
) -> bool:
	return a != null and b != null \
		and a.seat_id == b.seat_id \
		and a.bid_type == b.bid_type \
		and a.suit == b.suit \
		and a.rank == b.rank


func _apply_counter(declaration: TrumpBidding.BidDeclaration) -> Dictionary:
	game_round.apply_counter_bid(declaration)
	state.counter_attempted = true
	# Counter winner now must re-bury — re-enter the burying phase.
	current_phase = "burying"
	counter_seat_order = []
	counter_seat_index = 0
	return _ok({
		"phase": current_phase,
		"counter_made": true,
		"counter_seat": declaration.seat_id,
		"trump_suit": game_round.trump_suit,
		"dealer": game_round.dealer_seat,           # 不变
		"current_lead_seat": game_round.current_lead_seat,  # 不变
		"current_rank": state.current_rank,         # 不变
	})


func _finish_counter_window_no_change() -> Dictionary:
	state.counter_attempted = true
	counter_seat_order = []
	counter_seat_index = 0
	current_phase = "playing"
	trick_num = 0
	_reset_trick_state()
	return _ok({
		"phase": current_phase,
		"counter_made": false,
		"dealer": game_round.dealer_seat,
		"trump_suit": game_round.trump_suit,
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


## 结算并推进到下一局／游戏结束。
##
## 严格顺序（必须保证）：
##   1. calculate_settlement()：得到得分层提案（不写日志）
##   2. record_dealer_round()：登记庄家资历，供必打级检查
##   3. apply_settlement()：叠加跨局约束，得到 EffectiveSettlement + 真实 state
##   4. log_settlement(effective)：日志记录的是最终裁决，不是提案
##   5. end_round()：flush 当前 round
## 反过来（比如在步骤 3 之前写日志）会让日志与真实状态发散。
func finish_round() -> Dictionary:
	if game_round == null:
		return _error("missing_game_round")
	if current_phase == "round_end" or current_phase == "game_over":
		return _error("round_already_finished")

	var actual_dealer := game_round.dealer_seat
	var attack_rank := state.team_ranks[SessionState.get_attack_team(actual_dealer)]
	var proposal := game_round.calculate_settlement(attack_rank)

	state.record_dealer_round(actual_dealer, state.current_rank)
	var effective := state.apply_settlement(proposal, actual_dealer, rule_config)
	last_settlement = effective
	current_phase = "game_over" if state.game_over else "round_end"

	if logger:
		logger.log_settlement(effective)
		logger.end_round()

	return _ok({
		"phase": current_phase,
		"settlement": effective,
		"upgrading_team": effective.upgrading_team,
		"game_over": effective.game_over,
		"upgrade_blocked": effective.upgrade_blocked,
		"current_dealer": state.current_dealer,
		"current_rank": state.current_rank,
		"team_ranks": state.team_ranks.duplicate(),
		"is_first_game": state.is_first_game,
	})


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
