## TUI Game — interactive text-based game in Godot window
## Uses Label + buttons for card selection and gameplay
extends Control

const SEAT_NAMES: Array[String] = ["你(南)", "AI-东", "搭档(北)", "AI-西"]
# 逆时针座位顺序: 南(0/下) → 东(1/右) → 北(2/上) → 西(3/左)

# ============================================================
# UI nodes (created in _ready)
# ============================================================
var info_label: RichTextLabel
var table_label: RichTextLabel
var hand_container: HBoxContainer
var action_container: HBoxContainer
var log_label: RichTextLabel
var scroll_container: ScrollContainer

# ============================================================
# Game state
# ============================================================
var rule_config: RuleConfig
var game_round: GameRound
var logger: GameLogger

var human_seat: int = 0
var current_dealer: int = 0
var current_rank: int = Card.Rank.TWO
var is_first_game: bool = true
var round_num: int = 0

var selected_indices: Array[int] = []
var current_phase: String = "idle"  # idle, bidding, burying, leading, following, settlement
var waiting_for_input: bool = false
var _bid_seat_index: int = 0  # tracks position in bidding rotation

# Play phase state
var trick_play_cards: Array = []
var trick_seat_index: int = 0
var trick_seat_order: Array[int] = []
var trick_lead_info: Dictionary = {}
var trick_num: int = 0

# Display state
var table_cards: Dictionary = {}  # seat -> card string


func _ready() -> void:
	_build_ui()
	_start_new_game()


# ============================================================
# UI Construction
# ============================================================

func _build_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(PRESET_FULL_RECT)
	root_vbox.set_anchor_and_offset(SIDE_LEFT, 0, 10)
	root_vbox.set_anchor_and_offset(SIDE_TOP, 0, 10)
	root_vbox.set_anchor_and_offset(SIDE_RIGHT, 1, -10)
	root_vbox.set_anchor_and_offset(SIDE_BOTTOM, 1, -10)
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	# Info bar
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.custom_minimum_size = Vector2(0, 30)
	info_label.add_theme_font_size_override("normal_font_size", 18)
	root_vbox.add_child(info_label)

	# Table area (shows played cards)
	table_label = RichTextLabel.new()
	table_label.bbcode_enabled = true
	table_label.fit_content = true
	table_label.custom_minimum_size = Vector2(0, 120)
	table_label.add_theme_font_size_override("normal_font_size", 16)
	root_vbox.add_child(table_label)

	# Hand cards (scrollable button row)
	var hand_label := Label.new()
	hand_label.text = "你的手牌（点击选牌，再次点击取消）:"
	hand_label.add_theme_font_size_override("font_size", 14)
	hand_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	root_vbox.add_child(hand_label)

	var hand_scroll := ScrollContainer.new()
	hand_scroll.custom_minimum_size = Vector2(0, 60)
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(hand_scroll)

	hand_container = HBoxContainer.new()
	hand_container.add_theme_constant_override("separation", 4)
	hand_scroll.add_child(hand_container)

	# 常驻控制栏（重开/重置）
	var control_bar := HBoxContainer.new()
	control_bar.add_theme_constant_override("separation", 10)
	control_bar.custom_minimum_size = Vector2(0, 36)
	root_vbox.add_child(control_bar)

	var restart_btn := _make_button("重开本局", func() -> void: _restart_round())
	restart_btn.add_theme_color_override("font_color", Color(1, 0.7, 0.2))
	control_bar.add_child(restart_btn)

	var reset_btn := _make_button("回到首局", func() -> void: _reset_to_first_game())
	reset_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	control_bar.add_child(reset_btn)

	var sep := Label.new()
	sep.text = "  |  "
	sep.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	control_bar.add_child(sep)

	var save_btn2 := _make_button("保存日志", func() -> void: _save_log())
	save_btn2.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	control_bar.add_child(save_btn2)

	# Action buttons
	action_container = HBoxContainer.new()
	action_container.add_theme_constant_override("separation", 10)
	action_container.custom_minimum_size = Vector2(0, 40)
	root_vbox.add_child(action_container)

	# Log area
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll_container)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_size_override("normal_font_size", 13)
	scroll_container.add_child(log_label)


# ============================================================
# Game flow
# ============================================================

func _start_new_game() -> void:
	rule_config = RuleConfig.new()
	rule_config.deck_count = 2
	rule_config.current_rank = Card.Rank.TWO
	rule_config.bid_requires_joker = true
	rule_config.trump_joker_color_match = true
	rule_config.allow_dump = false
	rule_config.strict_follow_structure = true

	logger = GameLogger.new(true)
	logger.set_rule_config(rule_config)
	_auto_save_log()  # 立即保存初始日志文件

	current_rank = Card.Rank.TWO
	current_dealer = 0
	round_num = 0
	is_first_game = true

	_log("[color=yellow]═══ 双升对局 — TUI 版 ═══[/color]")
	_start_round()


func _start_round() -> void:
	round_num += 1
	rule_config.current_rank = current_rank
	var round_seed := randi()

	game_round = GameRound.new()
	game_round.setup(rule_config, current_dealer)
	game_round.logger = logger
	logger.begin_round(round_num, current_rank, current_dealer, round_seed)

	game_round.deal(round_seed)

	var trump_str := Card.rank_symbol(current_rank)
	_log("\n[color=cyan]══ 第 %d 局 | 级: %s | 庄家: %s ══[/color]" % [
		round_num, trump_str, SEAT_NAMES[current_dealer]])
	_log("发牌完成")

	_update_info()
	_start_bidding()


# ============================================================
# Bidding phase
# ============================================================

func _start_bidding() -> void:
	current_phase = "bidding"

	if is_first_game:
		_log("\n[color=green]— 亮主阶段（首局·先到先得）—[/color]")
		# MVP简化：首局一次发完牌，先问人类再轮询AI
		var human_bids := TrumpBidding.get_available_bids(human_seat,
			game_round.get_hand(human_seat), current_rank, rule_config)
		if not human_bids.is_empty():
			_show_bid_options(human_bids)
		else:
			_log("你没有可亮的牌")
			logger.log_bid_attempt(human_seat, "skip", "no_valid_cards")
			_finish_bidding_round()
	else:
		_log("\n[color=green]— 亮主阶段（从庄家开始轮询）—[/color]")
		_bid_seat_index = 0
		_process_next_bidder()


## Non-first-game: process bidders in seat order from current_dealer
func _process_next_bidder() -> void:
	if game_round.bid_declaration != null:
		_finish_bidding()
		return
	if _bid_seat_index >= 4:
		# All 4 players checked, no one bid
		game_round.set_no_bid_default(current_dealer)
		_log("无人亮主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])
		_finish_bidding()
		return

	var seat := (current_dealer + _bid_seat_index) % 4
	var hand := game_round.get_hand(seat)

	if seat == human_seat:
		var human_bids := TrumpBidding.get_available_bids(seat, hand, current_rank, rule_config)
		if not human_bids.is_empty():
			_show_bid_options(human_bids)
			return  # Wait for player input
		else:
			_log("你没有可亮的牌（跳过）")
			logger.log_bid_attempt(seat, "skip", "no_valid_cards")
	else:
		var decl := AIPlayer.decide_bid(seat, hand, current_rank, rule_config)
		if decl != null and game_round.process_bid(decl):
			var s := "公主" if decl.suit < 0 else Card.suit_symbol(decl.suit)
			_log("%s 亮主: %s" % [SEAT_NAMES[seat], s])
			logger.log_bid_attempt(seat, "bid", "", decl.suit)
			_finish_bidding()
			return
		else:
			_log("%s 跳过" % SEAT_NAMES[seat])
			logger.log_bid_attempt(seat, "skip", "ai_pass")

	_bid_seat_index += 1
	_process_next_bidder()


## First-game: after human, let AI try in seat order
func _finish_bidding_round() -> void:
	var bid_made := game_round.bid_declaration != null

	if not bid_made:
		for i: int in range(4):
			var seat := (current_dealer + i) % 4
			if seat == human_seat:
				continue
			var hand := game_round.get_hand(seat)
			var decl := AIPlayer.decide_bid(seat, hand, current_rank, rule_config)
			if decl != null and game_round.process_bid(decl):
				bid_made = true
				var s := "公主" if decl.suit < 0 else Card.suit_symbol(decl.suit)
				_log("%s 亮主: %s" % [SEAT_NAMES[seat], s])
				logger.log_bid_attempt(seat, "bid", "", decl.suit)
				break
			else:
				logger.log_bid_attempt(seat, "skip", "ai_pass")

	if not bid_made:
		game_round.set_no_bid_default(current_dealer)
		_log("无人亮主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])

	_finish_bidding()


func _finish_bidding() -> void:
	_log("主花色: %s | 庄家: %s" % [_trump_str(), SEAT_NAMES[game_round.dealer_seat]])
	_update_info()
	_start_bury()


func _show_bid_options(bids: Array) -> void:
	waiting_for_input = true
	_refresh_hand_display()
	_clear_actions()

	_log("请选择亮主:")
	for i: int in range(bids.size()):
		var b: TrumpBidding.BidDeclaration = bids[i]
		var s := "公主(无主)" if b.suit < 0 else Card.suit_symbol(b.suit)
		var btn := _make_button(s, func() -> void: _on_bid_selected(bids, i))
		action_container.add_child(btn)

	var skip_btn := _make_button("不亮", func() -> void: _on_bid_skip())
	skip_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	action_container.add_child(skip_btn)


func _on_bid_selected(bids: Array, index: int) -> void:
	if not waiting_for_input:
		return
	waiting_for_input = false
	var decl: TrumpBidding.BidDeclaration = bids[index]
	game_round.process_bid(decl)
	var s := "公主" if decl.suit < 0 else Card.suit_symbol(decl.suit)
	_log("你亮主: %s" % s)
	logger.log_bid_attempt(human_seat, "bid", "", decl.suit)
	_clear_actions()
	if is_first_game:
		_finish_bidding_round()  # First game: no more bids after first one
	else:
		_finish_bidding()  # Non-first: player bid accepted, done


func _on_bid_skip() -> void:
	if not waiting_for_input:
		return
	waiting_for_input = false
	_log("你选择不亮")
	logger.log_bid_attempt(human_seat, "skip", "player_choice")
	_clear_actions()
	if is_first_game:
		_finish_bidding_round()  # Let AI try
	else:
		_bid_seat_index += 1
		_process_next_bidder()  # Continue rotation


# ============================================================
# Bury phase
# ============================================================

func _start_bury() -> void:
	current_phase = "burying"
	var dealer := game_round.dealer_seat

	if dealer != human_seat:
		# AI bury
		var merged := game_round.get_dealer_hand_with_bottom()
		var indices := AIPlayer.decide_bury(merged, rule_config.bottom_size,
			game_round.trump_suit, current_rank, rule_config)
		game_round.execute_bury(indices)
		_log("%s 完成配底" % SEAT_NAMES[dealer])
		_auto_save_log()
		_start_play_phase()
	else:
		# Human bury
		var merged := game_round.get_dealer_hand_with_bottom()
		_log("\n[color=green]— 配底阶段 —[/color] 选 %d 张扣底" % rule_config.bottom_size)
		selected_indices = []
		_refresh_hand_display_for_bury(merged)
		_show_bury_actions()


func _refresh_hand_display_for_bury(cards: Array) -> void:
	_clear_hand()
	var display_cards := _sort_hand_for_display(cards)
	for i: int in range(display_cards.size()):
		var card: Card = display_cards[i]
		var idx := i
		var btn := _make_card_button(card, idx, func() -> void: _on_bury_card_clicked(idx))
		btn.set_meta("card_ref", card)
		hand_container.add_child(btn)


func _show_bury_actions() -> void:
	_clear_actions()
	var confirm_btn := _make_button("确认扣底 (0/%d)" % rule_config.bottom_size,
		func() -> void: _on_bury_confirm())
	confirm_btn.name = "ConfirmBury"
	action_container.add_child(confirm_btn)


func _on_bury_card_clicked(index: int) -> void:
	if not current_phase == "burying":
		return
	if index in selected_indices:
		selected_indices.erase(index)
	else:
		selected_indices.append(index)

	# Update button visuals
	for child: Node in hand_container.get_children():
		if child is Button:
			var btn := child as Button
			var btn_idx: int = btn.get_meta("card_index", -1)
			_set_card_button_selected(btn, btn_idx in selected_indices, Color(1, 0.3, 0.3))

	# Update confirm button text
	var confirm := action_container.get_node_or_null("ConfirmBury")
	if confirm is Button:
		(confirm as Button).text = "确认扣底 (%d/%d)" % [selected_indices.size(), rule_config.bottom_size]


func _on_bury_confirm() -> void:
	if selected_indices.size() != rule_config.bottom_size:
		_log("[color=red]请选择 %d 张牌扣底（当前选了 %d 张）[/color]" % [
			rule_config.bottom_size, selected_indices.size()])
		return

	var merged := game_round.get_dealer_hand_with_bottom()
	var actual_indices: Array[int] = []
	var used: Dictionary = {}
	for child: Node in hand_container.get_children():
		if child is Button:
			var btn := child as Button
			var btn_idx: int = btn.get_meta("card_index", -1)
			if btn_idx in selected_indices:
				var selected_card: Card = btn.get_meta("card_ref", null)
				for i: int in range(merged.size()):
					if used.has(i):
						continue
					var merged_card: Card = merged[i]
					if merged_card.equals(selected_card):
						actual_indices.append(i)
						used[i] = true
						break

	var result := game_round.execute_bury(actual_indices)
	if result["ok"]:
		_log("配底完成")
		_auto_save_log()
		selected_indices = []
		_start_play_phase()
	else:
		_log("[color=red]配底失败: %s[/color]" % result["error"])


# ============================================================
# Play phase
# ============================================================

func _start_play_phase() -> void:
	_log("\n[color=green]— 出牌阶段 —[/color]")
	trick_num = 0
	_start_next_trick()


func _start_next_trick() -> void:
	if game_round.get_hand_size(0) <= 0:
		_finish_round()
		return

	trick_num += 1
	trick_play_cards = []
	trick_seat_index = 0
	trick_seat_order = game_round.get_seat_order_from_lead()
	trick_lead_info = {}
	table_cards = {}

	_log("\n--- 第 %d 墩 | 先手: %s | 攻方: %d 分 ---" % [
		trick_num, SEAT_NAMES[game_round.current_lead_seat],
		game_round.score_tracker.get_attack_score()])

	_update_info()
	_update_table()
	_process_next_player()


func _process_next_player() -> void:
	if trick_seat_index >= 4:
		_resolve_trick()
		return

	var seat: int = trick_seat_order[trick_seat_index]

	if seat == human_seat:
		_show_play_options(seat)
	else:
		_ai_play(seat)


func _ai_play(seat: int) -> void:
	var hand := game_round.get_hand(seat)
	var gs := _make_game_state()
	var cards := AIPlayer.decide_play(seat, hand, trick_lead_info, gs, rule_config)

	if trick_lead_info.is_empty():
		_set_lead_info(cards)

	trick_play_cards.append(cards)
	table_cards[seat] = _cards_str(cards)
	_update_table()
	_log("  %s 出: %s" % [SEAT_NAMES[seat], _cards_str(cards)])

	trick_seat_index += 1
	# Small delay for readability
	get_tree().create_timer(0.3).timeout.connect(_process_next_player)


func _show_play_options(seat: int) -> void:
	var hand := game_round.get_hand(seat)
	var is_leading := trick_lead_info.is_empty()

	if is_leading:
		current_phase = "leading"
	else:
		current_phase = "following"

	waiting_for_input = true
	selected_indices = []
	_refresh_hand_display_for_play(hand)

	_clear_actions()
	var play_btn := _make_button("出牌", func() -> void: _on_play_confirm())
	play_btn.name = "PlayConfirm"
	action_container.add_child(play_btn)

	var hint := "你的回合 — " + ("请出牌（首出）" if is_leading else "请跟牌（%d 张）" % trick_play_cards[0].size())
	_log("[color=yellow]%s[/color]" % hint)


func _refresh_hand_display_for_play(hand: Array) -> void:
	_clear_hand()
	var display_hand := _sort_hand_for_display(hand)
	for i: int in range(display_hand.size()):
		var card: Card = display_hand[i]
		var idx := i
		var btn := _make_card_button(card, idx, func() -> void: _on_play_card_clicked(idx))
		btn.set_meta("card_ref", card)
		hand_container.add_child(btn)


func _on_play_card_clicked(index: int) -> void:
	if not waiting_for_input:
		return
	if index in selected_indices:
		selected_indices.erase(index)
	else:
		selected_indices.append(index)

	for child: Node in hand_container.get_children():
		if child is Button:
			var btn := child as Button
			var btn_idx: int = btn.get_meta("card_index", -1)
			_set_card_button_selected(btn, btn_idx in selected_indices, Color(0.3, 1, 0.3))


func _on_play_confirm() -> void:
	if not waiting_for_input or selected_indices.is_empty():
		_log("[color=red]请先选牌[/color]")
		return

	var cards: Array = []
	for child: Node in hand_container.get_children():
		if child is Button:
			var btn := child as Button
			var btn_idx: int = btn.get_meta("card_index", -1)
			if btn_idx in selected_indices:
				var selected_card: Card = btn.get_meta("card_ref", null)
				if selected_card != null:
					cards.append(selected_card)

	# Validate
	var jat := rule_config.joker_always_trump
	if trick_lead_info.is_empty():
		# Leading
		var pattern := PlayValidator.validate_lead(cards, game_round.get_hand(human_seat),
			game_round.trump_suit, current_rank, rule_config)
		if pattern == null:
			_log("[color=red]出牌不合法，请重新选择[/color]")
			return
		_set_lead_info(cards)
	else:
		# Following
		var lead_count: int = trick_play_cards[0].size()
		if cards.size() != lead_count:
			_log("[color=red]需要出 %d 张牌（当前选了 %d 张）[/color]" % [lead_count, cards.size()])
			return
		var valid := PlayValidator.validate_follow(cards, game_round.get_hand(human_seat),
			lead_count, trick_lead_info["domain"], game_round.trump_suit, current_rank, rule_config)
		if not valid:
			_log("[color=red]跟牌不合法，请重新选择[/color]")
			return

	waiting_for_input = false
	trick_play_cards.append(cards)
	table_cards[human_seat] = _cards_str(cards)
	_update_table()
	_log("  你出: %s" % _cards_str(cards))

	selected_indices = []
	_clear_actions()
	trick_seat_index += 1
	_process_next_player()


func _set_lead_info(cards: Array) -> void:
	var jat := rule_config.joker_always_trump
	var pattern := CardPattern.identify(cards, current_rank,
		rule_config.tractor_allow_rank_card, rule_config.four_same_is_tractor)
	trick_lead_info = {
		"domain": TrumpJudge.get_suit_domain(cards[0], game_round.trump_suit, current_rank, jat),
		"count": cards.size(),
		"pattern": pattern,
	}


func _resolve_trick() -> void:
	var result := game_round.play_trick(trick_play_cards)
	var winner_name := SEAT_NAMES[result["winner"]]
	var side := "攻方" if game_round.is_attack(result["winner"]) else "庄家方"
	_log("  → %s 赢墩 (%s) | 本墩: %d 分 | 攻方总分: %d" % [
		winner_name, side, result["score"], result["attack_score"]])

	_update_info()

	# 每墩结束后自动保存
	_auto_save_log()

	if result["is_last"]:
		_finish_round()
	else:
		# Continue to next trick after a short delay
		get_tree().create_timer(0.8).timeout.connect(_start_next_trick)


func _finish_round() -> void:
	var settlement := game_round.calculate_settlement()
	logger.end_round()

	_log("\n[color=yellow]═══════ 结算 ═══════[/color]")
	_log("出牌阶段攻方得分: %d" % settlement.attack_base_score)
	if settlement.bottom_multiplier > 0:
		_log("底牌: %d × %d 倍 = %d" % [settlement.bottom_score, settlement.bottom_multiplier, settlement.bottom_bonus])
	else:
		_log("庄家方赢最后一墩，底牌不计分")
	_log("最终得分: %d" % settlement.final_score)

	var side := "攻方" if settlement.upgrading_side == 1 else "庄家方"
	if settlement.upgrade_levels > 0:
		_log("%s 升 %d 级 → 新级: %s" % [side, settlement.upgrade_levels, Card.rank_symbol(settlement.new_rank)])
	elif settlement.dealer_dethroned:
		_log("攻方下庄")
	else:
		_log("庄家方守住")

	if settlement.game_over:
		_log("\n[color=yellow]🏆 游戏结束！%s 获胜！[/color]" % side)
		_save_log()
		_clear_actions()
		var restart_btn := _make_button("再来一局", func() -> void: _start_new_game())
		action_container.add_child(restart_btn)
	else:
		if settlement.upgrade_levels > 0:
			current_rank = settlement.new_rank
		if settlement.new_dealer >= 0:
			current_dealer = settlement.new_dealer

		_clear_actions()
		var next_btn := _make_button("下一局", func() -> void: _start_round())
		action_container.add_child(next_btn)
		var save_btn := _make_button("保存日志", func() -> void: _save_log())
		action_container.add_child(save_btn)


# ============================================================
# Log saving
# ============================================================

## 自动保存（静默，覆盖同一文件，不打日志）
func _auto_save_log() -> void:
	logger.save_to_file(_resolve_log_path("game_log_latest.json"))


## 手动保存（按钮触发，带时间戳，显示路径）
func _save_log() -> void:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var log_path := _resolve_log_path("game_log_%s.json" % timestamp)
	var err := logger.save_to_file(log_path)
	if err == OK:
		_log("[color=green]日志已保存: %s[/color]" % log_path)
	else:
		_log("[color=red]日志保存失败: %s[/color]" % error_string(err))

	var anomalies := logger.get_anomalies()
	if not anomalies.is_empty():
		_log("[color=red]⚠ 发现 %d 个异常:[/color]" % anomalies.size())
		for a: String in anomalies:
			_log("  - %s" % a)


## 把日志写到仓库 docs/game-logs/，不再写到 AppData/Roaming/Godot
## 项目根 = res:// 上两级（src/godot 的父父目录）
func _resolve_log_path(filename: String) -> String:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	# project_root 通常是 .../src/godot；向上两级 → 仓库根
	var repo_root := project_root.get_base_dir().get_base_dir()
	return "%s/docs/game-logs/%s" % [repo_root, filename]


# ============================================================
# UI Helpers
# ============================================================

func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(callback)
	return btn


func _make_card_button(card: Card, index: int, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = card.to_string_repr()
	btn.set_meta("card_index", index)
	btn.add_theme_font_size_override("font_size", 18)

	var col := _get_card_button_color(card)
	btn.set_meta("base_font_color", col)
	btn.add_theme_color_override("font_color", col)

	if callback.is_valid():
		btn.pressed.connect(callback)
	return btn


func _get_card_button_color(card: Card) -> Color:
	if TrumpJudge.is_trump(card, game_round.trump_suit, current_rank, rule_config.joker_always_trump):
		return Color(1, 0.5, 0.5) if card.get_color() == Card.CardColor.RED else Color(0.5, 0.8, 1)
	return Color(1, 0.3, 0.3) if card.get_color() == Card.CardColor.RED else Color(0.9, 0.9, 0.9)


func _set_card_button_selected(btn: Button, selected: bool, selected_color: Color) -> void:
	if selected:
		btn.add_theme_color_override("font_color", selected_color)
	else:
		var base_color: Color = btn.get_meta("base_font_color", Color(0.9, 0.9, 0.9))
		btn.add_theme_color_override("font_color", base_color)


func _clear_hand() -> void:
	for child: Node in hand_container.get_children():
		child.queue_free()


func _clear_actions() -> void:
	for child: Node in action_container.get_children():
		child.queue_free()


func _refresh_hand_display() -> void:
	_clear_hand()
	var hand := _sort_hand_for_display(game_round.get_hand(human_seat))
	for i: int in range(hand.size()):
		var card: Card = hand[i]
		var btn := _make_card_button(card, i, Callable())
		hand_container.add_child(btn)


func _update_info() -> void:
	var trump := _trump_str()
	var score := 0
	if game_round and game_round.score_tracker:
		score = game_round.score_tracker.get_attack_score()
	var dealer_name := SEAT_NAMES[game_round.dealer_seat] if game_round else "—"
	info_label.text = "[b]级: %s  |  主: %s  |  庄家: %s  |  攻方得分: %d[/b]" % [
		Card.rank_symbol(current_rank), trump, dealer_name, score]


func _update_table() -> void:
	var lines: Array[String] = []
	lines.append("         %s" % table_cards.get(2, ""))
	lines.append("")
	lines.append("  %s                %s" % [
		table_cards.get(3, ""), table_cards.get(1, "")])
	lines.append("")
	lines.append("         %s" % table_cards.get(0, ""))
	table_label.text = "\n".join(lines)


func _log(msg: String) -> void:
	log_label.append_text(msg + "\n")
	# Auto scroll to bottom
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(log_label.size.y)


func _trump_str() -> String:
	if game_round == null:
		return "—"
	return "公主" if game_round.trump_suit < 0 else Card.suit_symbol(game_round.trump_suit)


func _cards_str(cards: Array) -> String:
	var parts: Array[String] = []
	for c: Card in cards:
		parts.append(c.to_string_repr())
	return " ".join(parts)


func _sort_hand(hand: Array) -> Array:
	var sorted := hand.duplicate()
	var ts := -1
	var cr := current_rank
	var jat := true
	if game_round:
		ts = game_round.trump_suit
		jat = rule_config.joker_always_trump
	sorted.sort_custom(func(a: Card, b: Card) -> bool:
		return TrumpJudge.get_sort_value(a, ts, cr, jat) > TrumpJudge.get_sort_value(b, ts, cr, jat)
	)
	return sorted


func _sort_hand_for_display(hand: Array) -> Array:
	var sorted_logic := _sort_hand(hand)
	var ts := -1
	var cr := current_rank
	var jat := true
	if game_round:
		ts = game_round.trump_suit
		jat = rule_config.joker_always_trump

	var trumps: Array = []
	var clubs: Array = []
	var hearts: Array = []
	var spades: Array = []
	var diamonds: Array = []

	for card: Card in sorted_logic:
		if TrumpJudge.is_trump(card, ts, cr, jat):
			trumps.append(card)
		elif card.suit == Card.Suit.CLUB:
			clubs.append(card)
		elif card.suit == Card.Suit.HEART:
			hearts.append(card)
		elif card.suit == Card.Suit.SPADE:
			spades.append(card)
		elif card.suit == Card.Suit.DIAMOND:
			diamonds.append(card)

	var result: Array = []
	result.append_array(trumps)

	var groups: Array = [clubs, hearts, spades, diamonds]
	for g: Array in groups:
		result.append_array(g)
	return result


func _make_game_state() -> Dictionary:
	return {
		"trump_suit": game_round.trump_suit,
		"current_rank": current_rank,
		"dealer_seat": game_round.dealer_seat,
		"attack_score": game_round.score_tracker.get_attack_score(),
	}


# ============================================================
# Reset functions
# ============================================================

func _restart_round() -> void:
	waiting_for_input = false
	_clear_actions()
	_clear_hand()
	table_cards = {}
	_update_table()
	_log("\n[color=orange]══ 重开本局 ══[/color]")
	_start_round()


func _reset_to_first_game() -> void:
	waiting_for_input = false
	_clear_actions()
	_clear_hand()
	table_cards = {}
	_update_table()
	_log("\n[color=red]══ 回到首局 ══[/color]")
	_start_new_game()
