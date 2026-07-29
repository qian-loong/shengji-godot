## Terminal game session — playable prototype via console
## Run: godot --headless --script scripts/gameplay/game_session.gd
extends SceneTree


var rule_config: RuleConfig
var game_round: GameRound
var logger: GameLogger
var session_controller: SessionController
var human_seat: int = 0
var current_dealer: int = 0
var team_ranks: Array[int] = [Card.Rank.TWO, Card.Rank.TWO]  # [team_02, team_13]
var current_rank: int = Card.Rank.TWO  # current round's rank (derived from dealer's team)
var is_first_game: bool = true
var round_num: int = 0
var game_seed: int = -1  # -1 = random
var max_rounds: int = -1  # -1 = run until game over
var log_path_override: String = ""
var case_id: String = ""
var _cli_preset: String = ""
var _cli_config_path: String = ""
var _scenario: Dictionary = {}
var _scenario_consumed: bool = false

const SEAT_NAMES: Array[String] = ["你(南)", "AI-东", "搭档(北)", "AI-西"]
const TEAM_NAMES: Array[String] = ["南北队", "东西队"]


func _init() -> void:
	_print_header()
	_parse_cli_args()
	rule_config = _resolve_rule_config()
	_print_config_summary()
	logger = GameLogger.new(true)  # debug enabled
	logger.set_rule_config(rule_config)
	session_controller = SessionController.new()
	session_controller.start_new_session(rule_config, logger, human_seat)

	_run_game_loop()

	# Save log
	var log_path := _resolve_output_log_path()
	var err := logger.save_to_file(log_path, false)
	if err == OK:
		print("\n日志已保存: %s" % log_path)
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
	print("CLI: --preset=classic|competitive|quick  --config=<RuleConfig.json>")
	print("     --seed=N  --max-rounds=N  --log-path=<path>  --case-id=<id>")
	print("")


func _parse_cli_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		_apply_cli_arg(arg)
	for arg: String in OS.get_cmdline_args():
		_apply_cli_arg(arg)


func _apply_cli_arg(arg: String) -> void:
	if arg.begins_with("--seed="):
		game_seed = arg.split("=")[1].to_int()
		print("使用固定基础种子: %d" % game_seed)
	elif arg.begins_with("--max-rounds="):
		max_rounds = arg.split("=")[1].to_int()
		print("最多验证局数: %d" % max_rounds)
	elif arg.begins_with("--log-path="):
		log_path_override = arg.split("=")[1]
	elif arg.begins_with("--preset="):
		_cli_preset = arg.split("=")[1].strip_edges().to_lower()
	elif arg.begins_with("--config="):
		_cli_config_path = arg.split("=")[1].strip_edges()
	elif arg.begins_with("--case-id="):
		case_id = arg.split("=")[1].strip_edges()
	elif arg.begins_with("--scenario="):
		_load_scenario(arg.split("=")[1].strip_edges())
	elif arg.begins_with("--lead-strategy="):
		_apply_lead_strategy(arg.split("=")[1].strip_edges().to_lower(), true)
	elif arg == "--max-structure-lead":
		_apply_lead_strategy("max_structure", true)


## 设置 AI 首出策略。
##
## 引擎默认是 SIMPLE（只出单张），这是既有批跑基线的前提，不要随意改动默认值——
## MAX_STRUCTURE 是为了激活对子/拖拉机规则路径写的压测策略，不是经过设计的对局 AI
## （实测会让下庄率从 0.50 升到 0.75）。要跑覆盖率补充基线请显式传参。
func _apply_lead_strategy(name: String, verbose: bool = false) -> void:
	match name:
		"simple":
			AIPlayer.lead_strategy = AIPlayer.LeadStrategy.SIMPLE
		"dump", "dump_happy":
			AIPlayer.lead_strategy = AIPlayer.LeadStrategy.DUMP_HAPPY
		"max_structure", "maxstructure":
			AIPlayer.lead_strategy = AIPlayer.LeadStrategy.MAX_STRUCTURE
		_:
			printerr("未知 --lead-strategy=%s，保持默认 simple" % name)
			return
	if verbose:
		print("首出策略: %s" % name)


## 载入构造牌局 JSON。scenario 默认同时启用 MAX_STRUCTURE 首出策略 ——
## 否则即使把拖拉机发到手上，AI 也只会拆成单张出，白构造。
func _load_scenario(path: String) -> void:
	if not FileAccess.file_exists(path):
		printerr("scenario 文件不存在: %s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		printerr("scenario 解析失败: %s" % path)
		return
	_scenario = parsed
	print("构造牌局: %s" % path)
	if _scenario.has("description"):
		print("  说明: %s" % str(_scenario["description"]))

	# 构造牌局默认用 MAX_STRUCTURE —— 否则即使把拖拉机发到手上，
	# AI 也只会拆成单张出，白构造。可用 spec 的 lead_strategy 覆盖。
	var strategy := str(_scenario.get("lead_strategy", "max_structure")).to_lower()
	_apply_lead_strategy(strategy)
	print("  首出策略: %s" % strategy)


## Resolve config: --config JSON > --preset > classic preset
func _resolve_rule_config() -> RuleConfig:
	if not _cli_config_path.is_empty():
		var loaded := _load_config_from_path(_cli_config_path)
		if loaded != null:
			print("配置来源: --config=%s" % _cli_config_path)
			return loaded
		printerr("无法加载 --config，回退预设/默认")

	if not _cli_preset.is_empty():
		var preset := _parse_preset_name(_cli_preset)
		if preset >= 0:
			print("配置来源: --preset=%s" % _cli_preset)
			return RuleConfig.from_preset(preset as RuleConfig.ConfigSource)
		printerr("未知 --preset=%s，回退经典" % _cli_preset)

	print("配置来源: 默认经典预设")
	return RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)


func _parse_preset_name(name: String) -> int:
	match name:
		"classic", "0", "preset_classic":
			return int(RuleConfig.ConfigSource.PRESET_CLASSIC)
		"competitive", "comp", "1", "preset_competitive":
			return int(RuleConfig.ConfigSource.PRESET_COMPETITIVE)
		"quick", "2", "preset_quick":
			return int(RuleConfig.ConfigSource.PRESET_QUICK)
		_:
			return -1


func _load_config_from_path(path: String) -> RuleConfig:
	var abs_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		# Also try relative to repo root (parent of src/godot)
		var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
		var repo_root := project_root.get_base_dir().get_base_dir()
		var alt := "%s/%s" % [repo_root, path]
		if FileAccess.file_exists(alt):
			abs_path = alt
		else:
			printerr("配置文件不存在: %s" % path)
			return null

	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		printerr("无法打开配置文件: %s" % abs_path)
		return null
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		printerr("配置 JSON 解析失败: %s" % json.get_error_message())
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		printerr("配置 JSON 根节点必须是对象")
		return null
	return RuleConfig.from_dict(json.data as Dictionary)


func _print_config_summary() -> void:
	if rule_config == null:
		return
	print("RuleConfig: deck=%d threshold=%d step=%d dump=%s strict=%s no_skip=%s source=%d base=%d" % [
		rule_config.deck_count,
		rule_config.upgrade_threshold,
		rule_config.upgrade_step,
		str(rule_config.allow_dump),
		str(rule_config.strict_follow_structure),
		str(rule_config.no_skip_enabled),
		int(rule_config.source),
		int(rule_config.base_preset),
	])
	if not case_id.is_empty():
		print("case_id: %s" % case_id)


func _repo_root() -> String:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	return project_root.get_base_dir().get_base_dir()


func _resolve_output_log_path() -> String:
	if not log_path_override.is_empty():
		var parent := log_path_override.get_base_dir()
		if not parent.is_empty():
			DirAccess.make_dir_recursive_absolute(parent)
		return log_path_override

	var log_dir := "%s/logs" % _repo_root()
	DirAccess.make_dir_recursive_absolute(log_dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	if not case_id.is_empty():
		return "%s/game_log_%s_%s.json" % [log_dir, case_id, stamp]
	return "%s/game_log_%s.json" % [log_dir, stamp]


# ============================================================
# Main game loop (multi-round)
# ============================================================

func _run_game_loop() -> void:
	var game_over := false
	while not game_over:
		if max_rounds > 0 and round_num >= max_rounds:
			print("\n达到验证局数上限: %d" % max_rounds)
			break

		_sync_host_from_controller()
		current_rank = team_ranks[current_dealer % 2]
		rule_config.current_rank = current_rank
		print("\n====== 新局开始 | %s 打 %s 级 | 庄家: %s | %s:%s %s:%s ======" % [
			TEAM_NAMES[current_dealer % 2], Card.rank_symbol(current_rank),
			SEAT_NAMES[current_dealer],
			TEAM_NAMES[0], Card.rank_symbol(team_ranks[0]),
			TEAM_NAMES[1], Card.rank_symbol(team_ranks[1])])

		var settlement := _play_one_round()

		# Display settlement
		_display_settlement(settlement)

		_sync_host_from_controller()
		# settlement 现在是 EffectiveSettlement——game_over 与 upgrading_team
		# 已经反映必打级拦截后的真实状态，直接读即可，无需再从 state 反推。
		var upgrading_team := settlement.upgrading_team

		if settlement.game_over:
			print("\n🏆 游戏结束！%s 获胜！" % TEAM_NAMES[upgrading_team])
			game_over = true
		else:
			print("→ 新庄家: %s" % SEAT_NAMES[current_dealer])
			print("  %s: %s 级 | %s: %s 级" % [
				TEAM_NAMES[0], Card.rank_symbol(team_ranks[0]),
				TEAM_NAMES[1], Card.rank_symbol(team_ranks[1])])
			print("\n按 Enter 继续下一局...")


# ============================================================
# Single round
# ============================================================

func _play_one_round() -> EffectiveSettlement:
	round_num += 1
	var round_seed := game_seed + round_num - 1 if game_seed >= 0 else randi()

	session_controller.state.team_ranks = team_ranks.duplicate()
	session_controller.state.current_dealer = current_dealer
	session_controller.state.current_rank = current_rank
	session_controller.state.round_num = round_num - 1
	session_controller.state.is_first_game = is_first_game

	var scenario_trump_fixed := false
	if not _scenario.is_empty():
		var built := _build_scenario_round()
		if built.is_empty():
			printerr("scenario 构建失败，回退随机发牌")
			session_controller.start_round(round_seed)
		else:
			var res := session_controller.start_scenario_round(built)
			if not res.get("ok", false):
				printerr("scenario 起局失败: %s，回退随机发牌" % res.get("message", "?"))
				session_controller.start_round(round_seed)
			else:
				scenario_trump_fixed = built.has("trump_suit")
	else:
		session_controller.start_round(round_seed)

	game_round = session_controller.game_round
	round_num = session_controller.state.round_num
	print("\n--- 发牌完成 ---")

	# Phase 2: Bidding（scenario 指定了主花色时已跳过）
	if not scenario_trump_fixed:
		_bidding_phase()
	else:
		print("\n--- 亮主阶段 (scenario 指定: %s) ---" % (
			"公主" if game_round.trump_suit < 0 else Card.suit_symbol(game_round.trump_suit)))

	# Phase 3: Bury bottom
	_bury_phase()

	# Phase 4: Play tricks
	_play_phase()

	# Phase 5: Settlement
	var finish := session_controller.finish_round()
	_sync_host_from_controller()
	return finish["settlement"]


## 把 scenario JSON 里的牌面字符串转成 Card 对象。
## 只在第一局注入；后续局（若 --max-rounds > 1）回落到随机发牌，
## 因为构造牌局的意义是命中特定路径，不是打完整场比赛。
func _build_scenario_round() -> Dictionary:
	if _scenario_consumed:
		return {}
	_scenario_consumed = true

	var raw_hands: Array = _scenario.get("hands", [])
	if raw_hands.size() != 4:
		printerr("scenario.hands 必须是 4 个座位")
		return {}

	var hands: Array = []
	for seat: int in range(4):
		var parsed := _parse_card_list(raw_hands[seat])
		if parsed.is_empty():
			printerr("scenario.hands[%d] 解析为空" % seat)
			return {}
		hands.append(parsed)

	var bottom := _parse_card_list(_scenario.get("bottom", []))
	if bottom.is_empty():
		printerr("scenario.bottom 解析为空")
		return {}

	var built: Dictionary = { "hands": hands, "bottom": bottom }
	if _scenario.has("dealer"):
		built["dealer"] = int(_scenario["dealer"])
	if _scenario.has("trump_suit"):
		built["trump_suit"] = int(_scenario["trump_suit"])
	if _scenario.has("rank"):
		built["rank"] = int(_scenario["rank"])
	return built


## 解析 "♠5" / "RedJoker" 形式的牌面字符串数组。
static func _parse_card_list(raw: Variant) -> Array:
	if not (raw is Array):
		return []
	var result: Array = []
	for item: Variant in raw:
		var card := _parse_card_string(str(item))
		if card == null:
			printerr("无法解析牌面: %s" % str(item))
			return []
		result.append(card)
	return result


static func _parse_card_string(text: String) -> Card:
	if text == "RedJoker":
		return Card.joker(Card.JokerType.BIG)
	if text == "BlackJoker":
		return Card.joker(Card.JokerType.SMALL)
	if text.length() < 2:
		return null

	var suit_symbol := text.substr(0, 1)
	var suit := -1
	match suit_symbol:
		"♠": suit = Card.Suit.SPADE
		"♥": suit = Card.Suit.HEART
		"♦": suit = Card.Suit.DIAMOND
		"♣": suit = Card.Suit.CLUB
		_: return null

	var rank_text := text.substr(1)
	var rank := -1
	match rank_text:
		"J": rank = Card.Rank.JACK
		"Q": rank = Card.Rank.QUEEN
		"K": rank = Card.Rank.KING
		"A": rank = Card.Rank.ACE
		_:
			if rank_text.is_valid_int():
				var v := rank_text.to_int()
				if v >= 2 and v <= 10:
					rank = v
	if rank < 0:
		return null
	return Card.normal(suit, rank)


# ============================================================
# Bidding phase
# ============================================================

func _bidding_phase() -> void:
	print("\n--- 亮主阶段 ---")
	var bid_made := false

	# Each player gets a chance to bid (in seat order from dealer)
	for i: int in range(4):
		var seat := (current_dealer + i) % 4
		var context := session_controller.get_bidding_context(seat)
		var hand: Array = context["hand"]
		var bid_rank: int = context["bid_rank"]

		if seat == human_seat:
			# Human player
			var bids: Array = context["available_bids"]
			if not bids.is_empty() and not bid_made:
				print("\n你的手牌:")
				_display_hand(hand, -1, bid_rank)
				print("\n可选亮主:")
				for j: int in range(bids.size()):
					var b: TrumpBidding.BidDeclaration = bids[j]
					print("  %d. %s" % [j + 1, TrumpBidding.bid_label(b)])
				print("  0. 不亮")

				# Auto-pick for headless mode
				var choice := 1  # Default: pick first available
				var declaration: TrumpBidding.BidDeclaration = bids[choice - 1]
				print("→ 自动选择: %s" % TrumpBidding.bid_label(declaration))
				var bid_result := session_controller.submit_bid_or_pass(seat, declaration)
				if bid_result["ok"]:
					bid_made = true
					print("  ✓ 亮主成功！")
			else:
				session_controller.submit_bid_or_pass(seat, null, "no_valid_cards" if bids.is_empty() else "already_bid")
		else:
			# AI player
			if not bid_made:
				var available_bids: Array = context["available_bids"]
				var declaration := AIPlayer.decide_bid(seat, hand, bid_rank, rule_config)
				if declaration != null:
					var bid_result := session_controller.submit_bid_or_pass(seat, declaration)
					if bid_result["ok"]:
						bid_made = true
						print("%s 亮主: %s" % [SEAT_NAMES[seat], TrumpBidding.bid_label(declaration)])
					else:
						session_controller.submit_bid_or_pass(seat, null, "bid_rejected")
				else:
					var reason := "no_valid_cards" if available_bids.is_empty() else "ai_pass"
					session_controller.submit_bid_or_pass(seat, null, reason)
			else:
				session_controller.submit_bid_or_pass(seat, null, "already_bid")

		if bid_made and is_first_game:
			break  # First game: first come first served

	if not bid_made:
		session_controller.resolve_no_bid_default()
		print("无人亮主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])

	current_rank = session_controller.state.current_rank
	rule_config.current_rank = current_rank
	var trump_str := "公主(无主)" if game_round.trump_suit < 0 else Card.suit_symbol(game_round.trump_suit)
	print("\n主花色: %s | 庄家: %s" % [trump_str, SEAT_NAMES[game_round.dealer_seat]])


# ============================================================
# Bury phase
# ============================================================

func _bury_phase() -> void:
	print("\n--- 配底阶段 ---")
	_run_one_bury_round("庄家")

	# After dealer's bury, the controller may have opened a counter window.
	# Drain it (auto-pick AI / human via AIPlayer.decide_counter), then if a
	# counter succeeded the controller is back in "burying" for the counter
	# winner — run another bury round.
	if session_controller.current_phase == "counter_window":
		_counter_window_phase()
	if session_controller.current_phase == "burying" and session_controller.state.counter_attempted:
		print("\n--- 反主成功，反家重新配底 ---")
		_run_one_bury_round("反家")

	print("配底完成，开始出牌\n")


## Run a single bury round (dealer or counter winner) using AI heuristics.
## Works for any bury_seat — seat identity comes from get_bury_context().
func _run_one_bury_round(label: String) -> void:
	var context := session_controller.get_bury_context()
	var bury_seat: int = context.get("bury_seat", context["dealer"])
	var merged: Array = context["merged_hand"]
	var trump_suit: int = context["trump_suit"]
	var c_rank: int = context["current_rank"]

	if bury_seat == human_seat:
		print("\n你的手牌（含底牌 %d 张）:" % rule_config.bottom_size)
		_display_hand(merged, trump_suit, c_rank)
		print("\n需要选 %d 张扣底（%s）" % [rule_config.bottom_size, label])

	var indices := AIPlayer.decide_bury(merged, rule_config.bottom_size,
		trump_suit, c_rank, rule_config)
	if bury_seat == human_seat:
		print("→ 自动扣底: ", _cards_to_str(_get_cards_by_indices(merged, indices)))
	else:
		print("%s（%s）完成配底" % [SEAT_NAMES[bury_seat], label])
	session_controller.submit_bury(indices)


# ============================================================
# Counter-bid window (non-first-game, non-公主)
# ============================================================

func _counter_window_phase() -> void:
	print("\n--- 反主窗口 ---")
	while session_controller.current_phase == "counter_window":
		var seat := session_controller.get_current_counter_seat()
		if seat < 0:
			break
		var ctx := session_controller.get_counter_context(seat)
		if not ctx["ok"]:
			print("反主上下文异常: %s" % ctx.get("error", "?"))
			break
		var hand: Array = ctx["hand"]
		var current_bid: TrumpBidding.BidDeclaration = ctx["current_bid"]
		var c_rank: int = ctx["current_rank"]

		var decl := AIPlayer.decide_counter(seat, hand, c_rank, current_bid, rule_config)
		if decl == null:
			session_controller.submit_counter_or_pass(seat, null, "ai_pass")
			print("  %s 不反主" % SEAT_NAMES[seat])
		else:
			# Capture original bid label *before* submit (apply_counter overwrites bid_declaration).
			var original_label := TrumpBidding.bid_label(current_bid)
			var result := session_controller.submit_counter_or_pass(seat, decl)
			if result["ok"] and result.get("counter_made", false):
				print("  ★ %s 反主成功: %s（原:%s）" % [
					SEAT_NAMES[seat], TrumpBidding.bid_label(decl), original_label
				])
				current_rank = session_controller.state.current_rank  # invariant: unchanged
				break
			# Should not happen with decide_counter (which only returns stronger), but be defensive.
			session_controller.submit_counter_or_pass(seat, null, "fallback_pass")


# ============================================================
# Play phase
# ============================================================

func _play_phase() -> void:
	print("--- 出牌阶段 ---")
	while game_round.get_hand_size(0) > 0:
		var trick_context := session_controller.begin_trick()
		var trick_num: int = trick_context["trick_num"]
		print("\n--- 第 %d 墩 | 先手: %s | 攻方得分: %d ---" % [
			trick_num, SEAT_NAMES[game_round.current_lead_seat],
			game_round.score_tracker.get_attack_score()])

		for i: int in range(4):
			var turn := session_controller.get_current_turn_context()
			var seat: int = turn["seat"]
			var hand: Array = turn["hand"]
			var lead_info: Dictionary = turn["lead_info"]

			if seat == human_seat:
				# Human play
				if lead_info.is_empty():
					# Leading
					print("\n你的手牌:")
					_display_hand(hand, game_round.trump_suit, current_rank)
					# Auto-play: use AI
					var cards := AIPlayer.decide_play(seat, hand, lead_info,
						session_controller.make_game_state(), rule_config)
					print("→ 自动出牌: %s" % _cards_to_str(cards))
					session_controller.submit_play(seat, cards)
				else:
					print("\n你的手牌:")
					_display_hand(hand, game_round.trump_suit, current_rank)
					var cards := AIPlayer.decide_play(seat, hand, lead_info,
						session_controller.make_game_state(), rule_config)
					print("→ 自动出牌: %s" % _cards_to_str(cards))
					session_controller.submit_play(seat, cards)
			else:
				# AI play
				var cards := AIPlayer.decide_play(seat, hand, lead_info,
					session_controller.make_game_state(), rule_config)
				session_controller.submit_play(seat, cards)

				print("  %s 出: %s" % [SEAT_NAMES[seat], _cards_to_str(cards)])

		# Execute trick
		var result := session_controller.last_trick_result
		var winner_name := SEAT_NAMES[result["winner"]]
		var side_str := "攻方" if game_round.is_attack(result["winner"]) else "庄家方"
		print("  → %s 赢墩 (%s) | 本墩得分: %d | 攻方总分: %d" % [
			winner_name, side_str, result["score"], result["attack_score"]])


# ============================================================
# Settlement display
# ============================================================

func _display_settlement(s: EffectiveSettlement) -> void:
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


func _sync_host_from_controller() -> void:
	if session_controller == null:
		return
	game_round = session_controller.game_round
	team_ranks = session_controller.state.team_ranks.duplicate()
	current_dealer = session_controller.state.current_dealer
	current_rank = session_controller.state.current_rank
	round_num = session_controller.state.round_num
	is_first_game = session_controller.state.is_first_game
