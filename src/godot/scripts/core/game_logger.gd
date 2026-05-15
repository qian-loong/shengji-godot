## Game logger — records complete game state for replay and debugging
## Two layers:
##   Replay: seed + config + decisions → exact reproduction
##   Debug:  hand snapshots, domain judgments, winner reasoning
class_name GameLogger
extends RefCounted


# ============================================================
# Log data structures
# ============================================================

var _game_log: Dictionary
var _current_round: Dictionary
var _current_trick: Dictionary
var _debug_enabled: bool


func _init(debug: bool = true) -> void:
	_debug_enabled = debug
	_game_log = {
		"version": 1,
		"created_at": Time.get_datetime_string_from_system(),
		"rounds": [],
	}


# ============================================================
# Game-level logging
# ============================================================

func set_rule_config(rc: RuleConfig) -> void:
	_game_log["rule_config"] = {
		"deck_count": rc.deck_count,
		"current_rank": rc.current_rank,
		"trump_mode": rc.trump_mode,
		"joker_always_trump": rc.joker_always_trump,
		"trump_joker_color_match": rc.trump_joker_color_match,
		"bid_requires_joker": rc.bid_requires_joker,
		"allow_dump": rc.allow_dump,
		"strict_follow_structure": rc.strict_follow_structure,
		"four_same_is_tractor": rc.four_same_is_tractor,
		"tractor_allow_rank_card": rc.tractor_allow_rank_card,
		"upgrade_threshold": rc.upgrade_threshold,
		"no_skip_enabled": rc.no_skip_enabled,
		"no_skip_ranks": rc.no_skip_ranks.duplicate(),
	}


# ============================================================
# Round-level logging
# ============================================================

func begin_round(round_num: int, rank: int, dealer: int, seed_value: int, p_team_ranks: Array = []) -> void:
	_current_round = {
		"round_num": round_num,
		"rank": rank,
		"rank_symbol": Card.rank_symbol(rank),
		"dealer": dealer,
		"seed": seed_value,
		"bid_history": [],
		"bid": null,
		"trump_suit": -1,
		"trump_suit_symbol": "",
		"buried_indices": [],
		"tricks": [],
		"settlement": {},
	}
	if not p_team_ranks.is_empty():
		_current_round["team_ranks"] = p_team_ranks.duplicate()
		_current_round["team_ranks_symbols"] = [
			Card.rank_symbol(p_team_ranks[0]),
			Card.rank_symbol(p_team_ranks[1]),
		]
	if _debug_enabled:
		_current_round["debug"] = {
			"initial_hands": [],
			"hand_with_bottom": [],
			"buried_cards": [],
			"bottom_cards": [],
		}


func log_initial_hands(hands: Array, bottom: Array) -> void:
	if not _debug_enabled:
		return
	var hand_strs: Array = []
	for h: Array in hands:
		hand_strs.append(_cards_to_strs(h))
	_current_round["debug"]["initial_hands"] = hand_strs
	_current_round["debug"]["bottom_cards"] = _cards_to_strs(bottom)


func log_bid_attempt(seat: int, action: String, reason: String = "", suit: int = -99) -> void:
	var entry: Dictionary = { "seat": seat, "action": action }
	if reason != "":
		entry["reason"] = reason
	if suit != -99:
		entry["suit"] = suit
		entry["suit_symbol"] = "公主" if suit < 0 else Card.suit_symbol(suit)
	_current_round["bid_history"].append(entry)


func log_bid(declaration, no_bid: bool = false) -> void:
	if no_bid:
		_current_round["bid"] = { "type": "NO_BID" }
		_current_round["trump_suit"] = -1
		_current_round["trump_suit_symbol"] = "公主"
		return

	_current_round["bid"] = {
		"seat": declaration.seat_id,
		"type": declaration.bid_type,
		"suit": declaration.suit,
		"suit_symbol": "公主" if declaration.suit < 0 else Card.suit_symbol(declaration.suit),
	}
	# 亮主后真正的 dealer 可能变化，更新到 round 元数据
	_current_round["dealer"] = declaration.seat_id
	_current_round["dealer_team"] = [declaration.seat_id, (declaration.seat_id + 2) % 4]
	_current_round["attack_team"] = _other_team(declaration.seat_id)


func update_round_rank(rank: int, p_team_ranks: Array = []) -> void:
	_current_round["rank"] = rank
	_current_round["rank_symbol"] = Card.rank_symbol(rank)
	if not p_team_ranks.is_empty():
		_current_round["team_ranks"] = p_team_ranks.duplicate()
		_current_round["team_ranks_symbols"] = [
			Card.rank_symbol(p_team_ranks[0]),
			Card.rank_symbol(p_team_ranks[1]),
		]


## 公主局：默认人类为庄
func set_no_bid_dealer(dealer_seat: int) -> void:
	_current_round["dealer"] = dealer_seat
	_current_round["dealer_team"] = [dealer_seat, (dealer_seat + 2) % 4]
	_current_round["attack_team"] = _other_team(dealer_seat)


static func _other_team(dealer_seat: int) -> Array:
	var dt := [dealer_seat, (dealer_seat + 2) % 4]
	var result: Array = []
	for i: int in range(4):
		if i not in dt:
			result.append(i)
	return result


func log_trump_determined(trump_suit: int) -> void:
	_current_round["trump_suit"] = trump_suit
	_current_round["trump_suit_symbol"] = "公主" if trump_suit < 0 else Card.suit_symbol(trump_suit)


func log_bury(merged_hand: Array, selected_indices: Array[int], buried_cards: Array, remaining_hand: Array) -> void:
	_current_round["buried_indices"] = selected_indices.duplicate()
	if _debug_enabled:
		_current_round["debug"]["hand_with_bottom"] = _cards_to_strs(merged_hand)
		_current_round["debug"]["buried_cards"] = _cards_to_strs(buried_cards)


# ============================================================
# Trick-level logging
# ============================================================

func begin_trick(trick_num: int, lead_seat: int, attack_score: int) -> void:
	_current_trick = {
		"trick_num": trick_num,
		"lead_seat": lead_seat,
		"attack_score_before": attack_score,
		"plays": [],
		"winner": -1,
		"trick_score": 0,
		"attack_score_after": 0,
	}
	if _debug_enabled:
		_current_trick["debug"] = {
			"domain_info": [],
			"winner_reason": "",
		}


func log_hands_before_trick(_hands: Array, _trump_suit: int, _current_rank: int, _jat: bool) -> void:
	pass


func log_hands_after_trick(_hands: Array, _trump_suit: int, _current_rank: int, _jat: bool) -> void:
	pass


func log_play(seat: int, cards: Array, trump_suit: int, current_rank: int, jat: bool) -> void:
	var play_entry: Dictionary = {
		"seat": seat,
		"cards": _cards_to_strs(cards),
	}
	if _debug_enabled and not cards.is_empty():
		var domain := TrumpJudge.get_suit_domain(cards[0], trump_suit, current_rank, jat)
		play_entry["domain"] = {
			"type": domain["type"],
			"suit": domain.get("suit", -1),
		}
		# Pattern identification
		var pattern := CardPattern.identify(cards, current_rank, true, false)
		if pattern:
			play_entry["pattern"] = _pattern_to_str(pattern)
		# Sort values
		var sort_vals: Array = []
		for c: Card in cards:
			sort_vals.append(TrumpJudge.get_sort_value(c, trump_suit, current_rank, jat))
		play_entry["sort_values"] = sort_vals

	_current_trick["plays"].append(play_entry)


func log_trick_result(winner: int, trick_score: int, attack_score: int, reason: String = "") -> void:
	_current_trick["winner"] = winner
	_current_trick["trick_score"] = trick_score   # 兼容字段：本墩牌点合计（K/10/5）
	_current_trick["trick_points"] = trick_score  # 别名：更明确表示是“牌点”而非“攻方得分”
	_current_trick["attack_score_after"] = attack_score
	# 攻方此墩实得 = after - before
	var before: int = _current_trick.get("attack_score_before", 0)
	_current_trick["attack_gain"] = attack_score - before
	# 明确标注本墩 winner 属于哪方（attack/dealer），便于复盘
	var attack_team: Array = _current_round.get("attack_team", [])
	if attack_team.is_empty():
		# 默认按 dealer = 0 推算
		var d: int = _current_round.get("dealer", 0)
		attack_team = _other_team(d)
	_current_trick["winner_side"] = "attack" if winner in attack_team else "dealer"
	if _debug_enabled and reason != "":
		_current_trick["debug"]["winner_reason"] = reason
	_current_round["tricks"].append(_current_trick.duplicate(true))
	_current_trick = {}


# ============================================================
# Settlement logging
# ============================================================

func log_settlement(s: UpgradeSettlement.SettlementResult) -> void:
	_current_round["settlement"] = {
		"attack_base_score": s.attack_base_score,
		"bottom_score": s.bottom_score,
		"bottom_multiplier": s.bottom_multiplier,
		"bottom_bonus": s.bottom_bonus,
		"final_score": s.final_score,
		"upgrading_side": s.upgrading_side,
		"upgrade_levels": s.upgrade_levels,
		"new_rank": s.new_rank,
		"new_rank_symbol": Card.rank_symbol(s.new_rank),
		"dealer_dethroned": s.dealer_dethroned,
		"new_dealer": s.new_dealer,
		"game_over": s.game_over,
	}


func end_round() -> void:
	_game_log["rounds"].append(_current_round.duplicate(true))
	_current_round = {}
	_current_trick = {}


# ============================================================
# Export
# ============================================================

func get_log() -> Dictionary:
	return _game_log


func to_json(pretty: bool = true) -> String:
	var snapshot := _build_snapshot()
	if pretty:
		return JSON.stringify(snapshot, "  ")
	return JSON.stringify(snapshot)


func save_to_file(path: String, pretty: bool = true) -> Error:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json(pretty))
	file.close()
	return OK


## 构造写盘快照：包含已结束的 rounds + 进行中的 _current_round（带 _in_progress 标记）
## 不修改原始 _game_log，避免影响 end_round() 的最终结构
func _build_snapshot() -> Dictionary:
	var snapshot := _game_log.duplicate(true)
	if not _current_round.is_empty():
		var round_copy: Dictionary = _current_round.duplicate(true)
		# 当前 trick 还没 push 到 tricks[]，临时挂上
		if not _current_trick.is_empty():
			var trick_copy: Dictionary = _current_trick.duplicate(true)
			trick_copy["_in_progress"] = true
			round_copy["tricks"].append(trick_copy)
		round_copy["_in_progress"] = true
		snapshot["rounds"].append(round_copy)
	return snapshot


# ============================================================
# Anomaly detection — flag suspicious results
# ============================================================

func get_anomalies() -> Array[String]:
	var anomalies: Array[String] = []
	for round_data: Dictionary in _game_log["rounds"]:
		var rnum: int = round_data["round_num"]

		# Check: attack score never negative
		var settlement: Dictionary = round_data.get("settlement", {})
		if settlement.get("final_score", 0) < 0:
			anomalies.append("Round %d: negative final score %d" % [rnum, settlement["final_score"]])

		# Check: total trick scores should not exceed total_score
		var total_trick_score := 0
		for trick: Dictionary in round_data.get("tricks", []):
			total_trick_score += trick.get("trick_score", 0)
			# Check for negative trick scores
			if trick.get("trick_score", 0) < 0:
				anomalies.append("Round %d Trick %d: negative trick score" % [rnum, trick["trick_num"]])

		# Check: exactly 25 tricks (2 deck) or 12 tricks (1 deck)
		var trick_count: int = round_data.get("tricks", []).size()
		if trick_count != 25 and trick_count != 12:
			anomalies.append("Round %d: unexpected trick count %d" % [rnum, trick_count])

		# Check: every trick has a valid winner (0-3)
		for trick: Dictionary in round_data.get("tricks", []):
			var winner: int = trick.get("winner", -1)
			if winner < 0 or winner > 3:
				anomalies.append("Round %d Trick %d: invalid winner %d" % [rnum, trick["trick_num"], winner])

	return anomalies


# ============================================================
# Helpers
# ============================================================

static func _cards_to_strs(cards: Array) -> Array[String]:
	var result: Array[String] = []
	for c: Card in cards:
		result.append(c.to_string_repr())
	return result


static func _pattern_to_str(pattern: CardPattern.PatternResult) -> String:
	match pattern.type:
		Card.CardType.SINGLE: return "Single"
		Card.CardType.PAIR: return "Pair"
		Card.CardType.TRACTOR: return "Tractor(%d对)" % pattern.pair_count
		Card.CardType.DUMP: return "Dump(%d组)" % pattern.components.size()
	return "Unknown"
