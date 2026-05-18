## TUI Game — interactive text-based game in Godot window
## Uses Label + buttons for card selection and gameplay
extends Control

const SEAT_NAMES: Array[String] = ["你(南)", "AI-东", "搭档(北)", "AI-西"]
# 逆时针座位顺序: 南(0/下) → 东(1/右) → 北(2/上) → 西(3/左)
const UI_LOG_MAX_LINES: int = 300

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
var session_controller: SessionController

var human_seat: int = 0
var current_dealer: int = 0
var team_ranks: Array[int] = [Card.Rank.TWO, Card.Rank.TWO]  # [team_02, team_13]
var current_rank: int = Card.Rank.TWO  # current round's rank (derived from dealer's team)
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
var ui_log_lines: Array[String] = []


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
	ui_log_lines = []
	if log_label != null:
		log_label.clear()

	rule_config = RuleConfig.new()
	rule_config.deck_count = 2
	rule_config.current_rank = Card.Rank.TWO
	rule_config.bid_requires_joker = true
	rule_config.trump_joker_color_match = true
	rule_config.allow_dump = false
	rule_config.strict_follow_structure = true

	logger = GameLogger.new(true)
	logger.set_rule_config(rule_config)
	session_controller = SessionController.new()
	session_controller.start_new_session(rule_config, logger, human_seat)
	_auto_save_log()

	team_ranks = [Card.Rank.TWO, Card.Rank.TWO]
	current_dealer = 0
	round_num = 0
	is_first_game = true
	_sync_controller_from_host_state()

	_log("[color=yellow]═══ 双升对局 — TUI 版 ═══[/color]")
	_start_round()


func _start_round() -> void:
	round_num += 1
	current_rank = team_ranks[current_dealer % 2]
	rule_config.current_rank = current_rank
	var round_seed := randi()

	# Controller owns round_num increment; host increments only for legacy display state.
	round_num -= 1
	_sync_controller_from_host_state()
	session_controller.start_round(round_seed)
	_sync_host_from_controller()

	var trump_str := Card.rank_symbol(current_rank)
	var dealer_team_name: String = ["南北队", "东西队"][current_dealer % 2] as String
	_log("\n[color=cyan]══ 第 %d 局 | %s 打 %s 级 | 庄家: %s ══[/color]" % [
		round_num, dealer_team_name, trump_str, SEAT_NAMES[current_dealer]])
	_log("  南北队: %s 级 | 东西队: %s 级" % [
		Card.rank_symbol(team_ranks[0]), Card.rank_symbol(team_ranks[1])])
	_log("发牌完成")

	_update_info()
	_start_bidding()


# ============================================================
# Bidding phase
# ============================================================

func _start_bidding() -> void:
	current_phase = "bidding"
	session_controller.current_phase = "bidding"

	if is_first_game:
		_log("\n[color=green]— 亮主阶段（首局·先到先得）—[/color]")
		# MVP简化：首局一次发完牌，先问人类再轮询AI
		var context := session_controller.get_bidding_context(human_seat)
		var human_bids: Array = context["available_bids"]
		if not human_bids.is_empty():
			_show_bid_options(human_bids)
		else:
			_log("你没有可亮的牌")
			session_controller.submit_bid_or_pass(human_seat, null, "no_valid_cards")
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
		session_controller.resolve_no_bid_default()
		_log("无人亮主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])
		_finish_bidding()
		return

	var seat := (current_dealer + _bid_seat_index) % 4
	var context := session_controller.get_bidding_context(seat)
	var hand: Array = context["hand"]
	var bid_rank: int = context["bid_rank"]

	if seat == human_seat:
		var human_bids: Array = context["available_bids"]
		if not human_bids.is_empty():
			_show_bid_options(human_bids)
			return  # Wait for player input
		else:
			_log("你没有可亮的牌（跳过）")
			session_controller.submit_bid_or_pass(seat, null, "no_valid_cards")
	else:
		var available_bids: Array = context["available_bids"]
		var decl := AIPlayer.decide_bid(seat, hand, bid_rank, rule_config)
		var bid_result := session_controller.submit_bid_or_pass(seat, decl) if decl != null else session_controller.submit_bid_or_pass(seat, null, "no_valid_cards" if available_bids.is_empty() else "ai_pass")
		if decl != null and bid_result["ok"] and session_controller.current_phase == "burying":
			var s := "公主" if decl.suit < 0 else Card.suit_symbol(decl.suit)
			_log("%s 亮主: %s" % [SEAT_NAMES[seat], s])
			_sync_host_from_controller()
			_finish_bidding()
			return
		else:
			_log("%s 跳过" % SEAT_NAMES[seat])

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
			var context := session_controller.get_bidding_context(seat)
			var hand: Array = context["hand"]
			var bid_rank: int = context["bid_rank"]
			var available_bids: Array = context["available_bids"]
			var decl := AIPlayer.decide_bid(seat, hand, bid_rank, rule_config)
			var bid_result := session_controller.submit_bid_or_pass(seat, decl) if decl != null else session_controller.submit_bid_or_pass(seat, null, "no_valid_cards" if available_bids.is_empty() else "ai_pass")
			if decl != null and bid_result["ok"] and session_controller.current_phase == "burying":
				bid_made = true
				var s := "公主" if decl.suit < 0 else Card.suit_symbol(decl.suit)
				_log("%s 亮主: %s" % [SEAT_NAMES[seat], s])
				break

	if not bid_made:
		session_controller.resolve_no_bid_default()
		_log("无人亮主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])

	_finish_bidding()


func _finish_bidding() -> void:
	if session_controller.current_phase == "bidding":
		session_controller.finish_bidding_if_ready()
	_sync_host_from_controller()
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
	session_controller.submit_bid_or_pass(human_seat, decl)
	_sync_host_from_controller()
	var s := "公主" if decl.suit < 0 else Card.suit_symbol(decl.suit)
	_log("你亮主: %s" % s)
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
	session_controller.submit_bid_or_pass(human_seat, null, "player_choice")
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
	var context := session_controller.get_bury_context()
	var dealer: int = context["dealer"]

	if dealer != human_seat:
		# AI bury
		var merged: Array = context["merged_hand"]
		var indices := AIPlayer.decide_bury(merged, rule_config.bottom_size,
			game_round.trump_suit, current_rank, rule_config)
		session_controller.submit_bury(indices)
		_log("%s 完成配底" % SEAT_NAMES[dealer])
		_auto_save_log()
		_after_bury_done()
	else:
		# Human bury
		var merged: Array = context["merged_hand"]
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

	var result := session_controller.submit_bury(actual_indices)
	if result["ok"]:
		_log("配底完成")
		_auto_save_log()
		selected_indices = []
		_after_bury_done()
	else:
		_log("[color=red]配底失败: %s[/color]" % result["error"])


# ============================================================
# Counter-bid window — TUI short-circuit (full UI deferred)
# ============================================================

## 配底完成后调用：若进入反主窗口，让所有反家自动 pass，
## 然后进入出牌阶段。TUI 暂不暴露反主交互（后续单独 sprint）。
func _after_bury_done() -> void:
	_sync_host_from_controller()
	if session_controller.current_phase == "counter_window":
		_skip_counter_window_all_pass()
	_start_play_phase()


func _skip_counter_window_all_pass() -> void:
	_log("[color=gray](反主窗口 — TUI 暂不支持，自动跳过)[/color]")
	# 在窗口内循环让当前反家 pass；若意外触发反主，phase 会变成 "burying" 跳出循环。
	var safety: int = 8
	while session_controller.current_phase == "counter_window" and safety > 0:
		var seat := session_controller.get_current_counter_seat()
		if seat < 0:
			break
		var res := session_controller.submit_counter_or_pass(seat, null, "tui_short_circuit")
		if not res.get("ok", false):
			push_warning("TUI counter-window short-circuit failed: %s" % res.get("error", "?"))
			break
		safety -= 1
	_sync_host_from_controller()


# ============================================================
# Play phase
# ============================================================

func _start_play_phase() -> void:
	_log("\n[color=green]— 出牌阶段 —[/color]")
	trick_num = 0
	session_controller.current_phase = "playing"
	_start_next_trick()


func _start_next_trick() -> void:
	if game_round.get_hand_size(0) <= 0:
		_finish_round()
		return

	var trick_context := session_controller.begin_trick()
	trick_num = trick_context["trick_num"]
	trick_play_cards = session_controller.trick_play_cards
	trick_seat_index = session_controller.trick_seat_index
	trick_seat_order = session_controller.trick_seat_order
	trick_lead_info = session_controller.trick_lead_info
	table_cards = {}

	_log("\n--- 第 %d 墩 | 先手: %s | 攻方: %d 分 ---" % [
		trick_num, SEAT_NAMES[game_round.current_lead_seat],
		game_round.score_tracker.get_attack_score()])

	_update_info()
	_update_table()
	_process_next_player()


func _process_next_player() -> void:
	var turn := session_controller.get_current_turn_context()
	if turn.get("trick_ready", false):
		_resolve_trick()
		return

	var seat: int = turn["seat"]

	if seat == human_seat:
		_show_play_options(seat)
	else:
		_ai_play(seat)


func _ai_play(seat: int) -> void:
	var turn := session_controller.get_current_turn_context()
	var hand: Array = turn["hand"]
	var cards := AIPlayer.decide_play(seat, hand, turn["lead_info"], turn["game_state"], rule_config)
	var result := session_controller.submit_play(seat, cards)
	_sync_trick_host_from_controller()
	table_cards[seat] = _cards_str(cards)
	_update_table()
	_log("  %s 出: %s" % [SEAT_NAMES[seat], _cards_str(cards)])

	if result.get("trick_complete", false):
		_resolve_trick()
		return
	# Small delay for readability
	get_tree().create_timer(0.3).timeout.connect(_process_next_player)


func _show_play_options(seat: int) -> void:
	var turn := session_controller.get_current_turn_context()
	var hand: Array = turn["hand"]
	var is_leading: bool = turn["is_leading"]

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
	var submit := session_controller.submit_play(human_seat, cards)
	if not submit["ok"]:
		var err: String = submit["error"]
		if err == "wrong_card_count":
			var turn := session_controller.get_current_turn_context()
			_log("[color=red]需要出 %d 张牌（当前选了 %d 张）[/color]" % [turn["lead_count"], cards.size()])
		elif err == "invalid_follow":
			_log("[color=red]跟牌不合法，请重新选择[/color]")
		else:
			_log("[color=red]出牌不合法，请重新选择: %s[/color]" % err)
		return

	waiting_for_input = false
	_sync_trick_host_from_controller()
	table_cards[human_seat] = _cards_str(cards)
	_update_table()
	_log("  你出: %s" % _cards_str(cards))

	selected_indices = []
	_clear_actions()
	if submit.get("trick_complete", false):
		_resolve_trick()
		return
	_process_next_player()


func _resolve_trick() -> void:
	var result := session_controller.last_trick_result
	var winner_name := SEAT_NAMES[result["winner"]]
	var side := "攻方" if game_round.is_attack(result["winner"]) else "庄家方"
	_log("  → %s 赢墩 (%s) | 本墩: %d 分 | 攻方总分: %d" % [
		winner_name, side, result["score"], result["attack_score"]])

	_update_info()

	if result["is_last"]:
		_finish_round()
	else:
		# Continue to next trick after a short delay
		get_tree().create_timer(0.8).timeout.connect(_start_next_trick)


func _finish_round() -> void:
	var finish := session_controller.finish_round()
	var settlement: UpgradeSettlement.SettlementResult = finish["settlement"]
	_sync_host_from_controller()

	_log("\n[color=yellow]═══════ 结算 ═══════[/color]")
	_log("出牌阶段攻方得分: %d" % settlement.attack_base_score)
	if settlement.bottom_multiplier > 0:
		_log("底牌: %d × %d 倍 = %d" % [settlement.bottom_score, settlement.bottom_multiplier, settlement.bottom_bonus])
	else:
		_log("庄家方赢最后一墩，底牌不计分")
	_log("最终得分: %d" % settlement.final_score)

	var upgrading_team := finish["upgrading_team"] as int
	var team_names: Array[String] = ["南北队", "东西队"]
	var team_name: String = team_names[upgrading_team]

	if settlement.upgrade_levels > 0:
		_log("%s 升 %d 级 → 新级: %s" % [team_name, settlement.upgrade_levels, Card.rank_symbol(settlement.new_rank)])
	elif settlement.dealer_dethroned:
		_log("攻方下庄（不升级）")
	else:
		_log("庄家方守住")

	_auto_save_log()

	if settlement.game_over:
		_log("\n[color=yellow]🏆 游戏结束！%s 获胜！[/color]" % team_name)
		_save_log()
		_clear_actions()
		var restart_btn := _make_button("再来一局", func() -> void: _start_new_game())
		action_container.add_child(restart_btn)
	else:
		_log("  南北队: %s 级 | 东西队: %s 级" % [
			Card.rank_symbol(team_ranks[0]), Card.rank_symbol(team_ranks[1])])

		_clear_actions()
		var next_btn := _make_button("下一局", func() -> void: _start_round())
		action_container.add_child(next_btn)
		var save_btn := _make_button("保存日志", func() -> void: _save_log())
		action_container.add_child(save_btn)


func _sync_controller_from_host_state() -> void:
	if session_controller == null:
		return
	session_controller.state.team_ranks = team_ranks.duplicate()
	session_controller.state.current_dealer = current_dealer
	session_controller.state.current_rank = current_rank
	session_controller.state.round_num = round_num
	session_controller.state.is_first_game = is_first_game
	session_controller.state.human_seat = human_seat


func _sync_host_from_controller() -> void:
	if session_controller == null:
		return
	game_round = session_controller.game_round
	team_ranks = session_controller.state.team_ranks.duplicate()
	current_dealer = session_controller.state.current_dealer
	current_rank = session_controller.state.current_rank
	round_num = session_controller.state.round_num
	is_first_game = session_controller.state.is_first_game


func _sync_trick_host_from_controller() -> void:
	if session_controller == null:
		return
	trick_play_cards = session_controller.trick_play_cards
	trick_seat_index = session_controller.trick_seat_index
	trick_seat_order = session_controller.trick_seat_order
	trick_lead_info = session_controller.trick_lead_info


# ============================================================
# Log saving
# ============================================================

## 自动保存（静默，覆盖同一文件，不打日志）
func _auto_save_log() -> void:
	logger.save_to_file(_resolve_log_path("game_log_latest.json"), false)


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
	info_label.text = "[b]级: %s  |  主: %s  |  庄家: %s  |  攻方: %d[/b]" % [
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
	ui_log_lines.append(msg)
	while ui_log_lines.size() > UI_LOG_MAX_LINES:
		ui_log_lines.remove_at(0)
	log_label.text = "\n".join(ui_log_lines) + "\n"
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
		return _card_display_less(a, b, ts, cr, jat)
	)
	return sorted


func _sort_hand_for_display(hand: Array) -> Array:
	return _sort_hand(hand)


func _card_display_less(a: Card, b: Card, trump_suit: int, c_rank: int, jat: bool) -> bool:
	var group_a := _card_display_group(a, trump_suit, c_rank, jat)
	var group_b := _card_display_group(b, trump_suit, c_rank, jat)
	if group_a != group_b:
		return group_a < group_b
	var value_a := TrumpJudge.get_sort_value(a, trump_suit, c_rank, jat)
	var value_b := TrumpJudge.get_sort_value(b, trump_suit, c_rank, jat)
	if value_a != value_b:
		return value_a > value_b
	return _card_identity_key(a) < _card_identity_key(b)


func _card_display_group(card: Card, trump_suit: int, c_rank: int, jat: bool) -> int:
	if TrumpJudge.is_trump(card, trump_suit, c_rank, jat):
		return 0
	match card.suit:
		Card.Suit.CLUB:
			return 1
		Card.Suit.HEART:
			return 2
		Card.Suit.SPADE:
			return 3
		Card.Suit.DIAMOND:
			return 4
		_:
			return 5


func _card_identity_key(card: Card) -> String:
	if card.is_joker:
		return "joker_%d" % card.joker_type
	return "%d_%02d" % [card.suit, card.rank]


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
