## Terminal game session — playable prototype via console
## Run: godot --headless --script scripts/gameplay/game_session.gd
extends SceneTree


var rule_config: RuleConfig
var game_round: GameRound
var logger: GameLogger
var human_seat: int = 0
var current_dealer: int = 0
var current_rank: int = Card.Rank.TWO
var is_first_game: bool = true
var round_num: int = 0
var game_seed: int = -1  # -1 = random

const SEAT_NAMES: Array[String] = ["你(南)", "AI-东", "搭档(北)", "AI-西"]


func _init() -> void:
	_print_header()
	rule_config = _create_default_config()
	logger = GameLogger.new(true)  # debug enabled
	logger.set_rule_config(rule_config)

	# Parse command line for seed
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--seed="):
			game_seed = arg.split("=")[1].to_int()
			print("使用固定种子: %d" % game_seed)

	_run_game_loop()

	# Save log
	var log_path := "user://game_log_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var err := logger.save_to_file(log_path)
	if err == OK:
		print("\n日志已保存: %s" % ProjectSettings.globalize_path(log_path))
	else:
		printerr("日志保存失败: %s" % error_string(err))

	# Check anomalies
	var anomalies := logger.get_anomalies()
	if not anomalies.is_empty():
		print("\n⚠ 发现 %d 个异常:" % anomalies.size())
		for a: String in anomalies:
			print("  - %s" % a)
	else:
		print("✓ 日志无异常")

	quit(0)


func _print_header() -> void:
	print("")
	print("╔══════════════════════════════════════╗")
	print("║       双升对局 — 终端可玩原型         ║")
	print("╚══════════════════════════════════════╝")
	print("")


func _create_default_config() -> RuleConfig:
	var rc := RuleConfig.new()
	rc.deck_count = 2
	rc.current_rank = Card.Rank.TWO
	rc.bid_requires_joker = true
	rc.trump_joker_color_match = true
	rc.allow_dump = false  # MVP: no dump to simplify
	rc.strict_follow_structure = true
	return rc


# ============================================================
# Main game loop (multi-round)
# ============================================================

func _run_game_loop() -> void:
	var game_over := false
	while not game_over:
		rule_config.current_rank = current_rank
		print("\n====== 新局开始 | 级: %s | 庄家: %s ======" % [
			Card.rank_symbol(current_rank), SEAT_NAMES[current_dealer]])

		var settlement := _play_one_round()

		# Display settlement
		_display_settlement(settlement)

		# Update state
		if settlement.game_over:
			var winner_side := "攻方" if settlement.upgrading_side == 1 else "庄家方"
			print("\n🏆 游戏结束！%s 获胜！" % winner_side)
			game_over = true
		else:
			# Update rank
			if settlement.upgrade_levels > 0:
				current_rank = settlement.new_rank

			# Update dealer
			if settlement.new_dealer >= 0:
				current_dealer = settlement.new_dealer
				print("→ 新庄家: %s" % SEAT_NAMES[current_dealer])

			print("\n按 Enter 继续下一局...")
			# In headless mode we auto-continue
			# For interactive mode this would wait for input


# ============================================================
# Single round
# ============================================================

func _play_one_round() -> UpgradeSettlement.SettlementResult:
	round_num += 1
	var round_seed := game_seed if game_seed >= 0 else randi()

	game_round = GameRound.new()
	game_round.setup(rule_config, current_dealer)
	game_round.logger = logger

	# Begin round logging
	logger.begin_round(round_num, current_rank, current_dealer, round_seed)

	# Phase 1: Deal
	game_round.deal(round_seed)
	print("\n--- 发牌完成 ---")

	# Phase 2: Bidding
	_bidding_phase()

	# Phase 3: Bury bottom
	_bury_phase()

	# Phase 4: Play tricks
	_play_phase()

	# Phase 5: Settlement
	var settlement := game_round.calculate_settlement()
	logger.end_round()
	return settlement


# ============================================================
# Bidding phase
# ============================================================

func _bidding_phase() -> void:
	print("\n--- 亮主阶段 ---")
	var bid_made := false

	# Each player gets a chance to bid (in seat order from dealer)
	for i: int in range(4):
		var seat := (current_dealer + i) % 4
		var hand := game_round.get_hand(seat)

		if seat == human_seat:
			# Human player
			var bids := TrumpBidding.get_available_bids(seat, hand, current_rank, rule_config)
			if not bids.is_empty() and not bid_made:
				print("\n你的手牌:")
				_display_hand(hand, -1, current_rank)
				print("\n可选亮主:")
				for j: int in range(bids.size()):
					var b: TrumpBidding.BidDeclaration = bids[j]
					var suit_str := "公主(无主)" if b.suit < 0 else Card.suit_symbol(b.suit)
					print("  %d. %s" % [j + 1, suit_str])
				print("  0. 不亮")

				# Auto-pick for headless mode
				var choice := 1  # Default: pick first available
				var declaration: TrumpBidding.BidDeclaration = bids[choice - 1]
				print("→ 自动选择: %s" % ("公主" if declaration.suit < 0 else Card.suit_symbol(declaration.suit)))
				if game_round.process_bid(declaration):
					bid_made = true
					print("  ✓ 亮主成功！")
					logger.log_bid_attempt(seat, "bid", "", declaration.suit)
			else:
				logger.log_bid_attempt(seat, "skip", "no_valid_cards" if bids.is_empty() else "already_bid")
		else:
			# AI player
			if not bid_made:
				var declaration := AIPlayer.decide_bid(seat, hand, current_rank, rule_config)
				if declaration != null:
					if game_round.process_bid(declaration):
						bid_made = true
						var suit_str := "公主(无主)" if declaration.suit < 0 else Card.suit_symbol(declaration.suit)
						print("%s 亮主: %s" % [SEAT_NAMES[seat], suit_str])
						logger.log_bid_attempt(seat, "bid", "", declaration.suit)
					else:
						logger.log_bid_attempt(seat, "skip", "bid_rejected")
				else:
					logger.log_bid_attempt(seat, "skip", "ai_pass")
			else:
				logger.log_bid_attempt(seat, "skip", "already_bid")

		if bid_made and is_first_game:
			break  # First game: first come first served

	if not bid_made:
		game_round.set_no_bid_default(current_dealer)
		print("无人亮主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])

	var trump_str := "公主(无主)" if game_round.trump_suit < 0 else Card.suit_symbol(game_round.trump_suit)
	print("\n主花色: %s | 庄家: %s" % [trump_str, SEAT_NAMES[game_round.dealer_seat]])


# ============================================================
# Bury phase
# ============================================================

func _bury_phase() -> void:
	print("\n--- 配底阶段 ---")

	var dealer := game_round.dealer_seat
	var merged := game_round.get_dealer_hand_with_bottom()

	if dealer == human_seat:
		print("\n你的手牌（含底牌 %d 张）:" % rule_config.bottom_size)
		_display_hand(merged, game_round.trump_suit, current_rank)
		print("\n需要选 %d 张扣底" % rule_config.bottom_size)

		# Auto-select for headless: use AI logic
		var indices := AIPlayer.decide_bury(merged, rule_config.bottom_size,
			game_round.trump_suit, current_rank, rule_config)
		print("→ 自动扣底: ", _cards_to_str(_get_cards_by_indices(merged, indices)))
		game_round.execute_bury(indices)
	else:
		# AI bury
		var indices := AIPlayer.decide_bury(merged, rule_config.bottom_size,
			game_round.trump_suit, current_rank, rule_config)
		game_round.execute_bury(indices)
		print("%s 完成配底" % SEAT_NAMES[dealer])

	print("配底完成，开始出牌\n")


# ============================================================
# Play phase
# ============================================================

func _play_phase() -> void:
	print("--- 出牌阶段 ---")
	var trick_num := 0
	while game_round.get_hand_size(0) > 0:
		trick_num += 1
		print("\n--- 第 %d 墩 | 先手: %s | 攻方得分: %d ---" % [
			trick_num, SEAT_NAMES[game_round.current_lead_seat],
			game_round.score_tracker.get_attack_score()])

		var play_cards: Array = []
		var lead_info: Dictionary = {}
		var seat_order := game_round.get_seat_order_from_lead()
		var jat := rule_config.joker_always_trump

		for i: int in range(4):
			var seat: int = seat_order[i]
			var hand := game_round.get_hand(seat)

			if seat == human_seat:
				# Human play
				if lead_info.is_empty():
					# Leading
					print("\n你的手牌:")
					_display_hand(hand, game_round.trump_suit, current_rank)
					# Auto-play: use AI
					var cards := AIPlayer.decide_play(seat, hand, lead_info,
						_make_game_state(), rule_config)
					print("→ 自动出牌: %s" % _cards_to_str(cards))
					play_cards.append(cards)
					# Set lead info
					var pattern := CardPattern.identify(cards, current_rank,
						rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
					lead_info = {
						"domain": TrumpJudge.get_suit_domain(cards[0], game_round.trump_suit, current_rank, jat),
						"count": cards.size(),
						"pattern": pattern,
					}
				else:
					print("\n你的手牌:")
					_display_hand(hand, game_round.trump_suit, current_rank)
					var cards := AIPlayer.decide_play(seat, hand, lead_info,
						_make_game_state(), rule_config)
					print("→ 自动出牌: %s" % _cards_to_str(cards))
					play_cards.append(cards)
			else:
				# AI play
				var cards := AIPlayer.decide_play(seat, hand, lead_info,
					_make_game_state(), rule_config)
				play_cards.append(cards)

				if lead_info.is_empty():
					var pattern := CardPattern.identify(cards, current_rank,
						rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
					lead_info = {
						"domain": TrumpJudge.get_suit_domain(cards[0], game_round.trump_suit, current_rank, jat),
						"count": cards.size(),
						"pattern": pattern,
					}

				print("  %s 出: %s" % [SEAT_NAMES[seat], _cards_to_str(cards)])

		# Execute trick
		var result := game_round.play_trick(play_cards)
		var winner_name := SEAT_NAMES[result["winner"]]
		var side_str := "攻方" if game_round.is_attack(result["winner"]) else "庄家方"
		print("  → %s 赢墩 (%s) | 本墩得分: %d | 攻方总分: %d" % [
			winner_name, side_str, result["score"], result["attack_score"]])


# ============================================================
# Settlement display
# ============================================================

func _display_settlement(s: UpgradeSettlement.SettlementResult) -> void:
	print("\n╔══════════════ 结算 ══════════════╗")
	print("  出牌阶段攻方得分: %d" % s.attack_base_score)
	if s.bottom_multiplier > 0:
		print("  底牌分值: %d × %d 倍 = %d" % [s.bottom_score, s.bottom_multiplier, s.bottom_bonus])
	else:
		print("  庄家方赢最后一墩，底牌不计分")
	print("  最终得分: %d" % s.final_score)
	var side_str := "攻方" if s.upgrading_side == 1 else "庄家方"
	if s.upgrade_levels > 0:
		print("  %s 升 %d 级 → 新级: %s" % [side_str, s.upgrade_levels, Card.rank_symbol(s.new_rank)])
	elif s.dealer_dethroned:
		print("  攻方下庄（未升级）")
	else:
		print("  庄家方守住")
	print("╚══════════════════════════════════╝")


# ============================================================
# Display helpers
# ============================================================

func _display_hand(hand: Array, trump_suit: int, c_rank: int) -> void:
	var jat := rule_config.joker_always_trump
	# Sort hand
	var sorted_hand := hand.duplicate()
	sorted_hand.sort_custom(func(a: Card, b: Card) -> bool:
		return TrumpJudge.get_sort_value(a, trump_suit, c_rank, jat) > TrumpJudge.get_sort_value(b, trump_suit, c_rank, jat)
	)

	var line := "  "
	for i: int in range(sorted_hand.size()):
		line += sorted_hand[i].to_string_repr() + " "
		if (i + 1) % 13 == 0:
			print(line)
			line = "  "
	if line.strip_edges() != "":
		print(line)


func _cards_to_str(cards: Array) -> String:
	var parts: Array[String] = []
	for c: Card in cards:
		parts.append(c.to_string_repr())
	return " ".join(parts)


func _get_cards_by_indices(cards: Array, indices: Array[int]) -> Array:
	var result: Array = []
	for idx: int in indices:
		result.append(cards[idx])
	return result


func _make_game_state() -> Dictionary:
	return {
		"trump_suit": game_round.trump_suit,
		"current_rank": current_rank,
		"dealer_seat": game_round.dealer_seat,
		"attack_score": game_round.score_tracker.get_attack_score(),
	}
