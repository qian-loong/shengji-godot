## GUI Game — graphical card table interface.
## Replaces TUI with proper Godot 2D visuals.
## Uses SessionController for all game logic (same as tui_game.gd).
extends Control

const SEAT_NAMES: Array[String] = ["你(南)", "AI-东", "搭档(北)", "AI-西"]
const TABLE_BG_COLOR := Color(0.08, 0.30, 0.15)
const TABLE_FELT_COLOR := Color(0.10, 0.38, 0.18)

var _CardViewClass: GDScript
var _HandDisplayClass: GDScript

# ============================================================
# UI node references (built in _ready)
# ============================================================
var info_bar: HBoxContainer
var info_labels: Dictionary = {}
var table_center: Control
var center_card_slots: Dictionary = {}  # seat -> Control
var seat_panels: Dictionary = {}        # seat -> Control
var seat_name_labels: Dictionary = {}   # seat -> Label
var seat_count_labels: Dictionary = {}  # seat -> Label
var hand_display = null
var action_bar: HBoxContainer
var bid_panel: PanelContainer
var message_label: Label
var log_panel: RichTextLabel

# ============================================================
# Game state
# ============================================================
var rule_config: RuleConfig
var game_round: GameRound
var logger: GameLogger
var session_controller: SessionController

var human_seat: int = 0
var current_dealer: int = 0
var team_ranks: Array[int] = [Card.Rank.TWO, Card.Rank.TWO]
var current_rank: int = Card.Rank.TWO
var is_first_game: bool = true
var round_num: int = 0
var base_seed: int = -1

var current_phase: String = "idle"
var waiting_for_input: bool = false
var _bid_seat_index: int = 0

# Trick state
var trick_play_cards: Array = []
var trick_seat_index: int = 0
var trick_seat_order: Array[int] = []
var trick_lead_info: Dictionary = {}
var trick_num: int = 0
var table_cards: Dictionary = {}

const UI_LOG_MAX_LINES: int = 200
var ui_log_lines: Array[String] = []


func _ready() -> void:
	_CardViewClass = load("res://scripts/ui/card_view.gd")
	_HandDisplayClass = load("res://scripts/ui/hand_display.gd")
	_parse_cli_args()
	_build_ui()
	_start_new_game()


func _parse_cli_args() -> void:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--seed="):
			base_seed = arg.split("=")[1].to_int()


# ============================================================
# UI Construction
# ============================================================

func _build_ui() -> void:
	# Full-screen dark felt background
	var bg := ColorRect.new()
	bg.color = TABLE_BG_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Felt oval (decorative center)
	var felt := _create_table_felt()
	add_child(felt)

	# Root layout
	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.set_anchor_and_offset(SIDE_LEFT, 0, 0)
	root.set_anchor_and_offset(SIDE_TOP, 0, 0)
	root.set_anchor_and_offset(SIDE_RIGHT, 1, 0)
	root.set_anchor_and_offset(SIDE_BOTTOM, 1, 0)
	add_child(root)

	# === Top: Info bar ===
	info_bar = _build_info_bar()
	root.add_child(info_bar)

	# === Middle: table area (expandable) ===
	var mid_section := HBoxContainer.new()
	mid_section.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(mid_section)

	# Left seat (West/seat 3)
	var west_panel := _build_seat_panel(3)
	west_panel.custom_minimum_size = Vector2(90, 0)
	west_panel.size_flags_vertical = SIZE_SHRINK_CENTER
	mid_section.add_child(west_panel)

	# Center column
	var center_col := VBoxContainer.new()
	center_col.size_flags_horizontal = SIZE_EXPAND_FILL
	center_col.size_flags_vertical = SIZE_EXPAND_FILL
	center_col.add_theme_constant_override("separation", 2)
	mid_section.add_child(center_col)

	# North seat (seat 2) — centered small panel, not full width
	var north_wrap := HBoxContainer.new()
	north_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	center_col.add_child(north_wrap)
	var north_panel := _build_seat_panel(2)
	north_panel.custom_minimum_size = Vector2(90, 0)
	north_wrap.add_child(north_panel)

	# Table center (play area)
	table_center = _build_table_center()
	table_center.size_flags_vertical = SIZE_EXPAND_FILL
	center_col.add_child(table_center)

	# Message area (below table center)
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 16)
	message_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	message_label.custom_minimum_size = Vector2(0, 26)
	center_col.add_child(message_label)

	# Right seat (East/seat 1)
	var east_panel := _build_seat_panel(1)
	east_panel.custom_minimum_size = Vector2(90, 0)
	east_panel.size_flags_vertical = SIZE_SHRINK_CENTER
	mid_section.add_child(east_panel)

	# === Bid panel (overlay, initially hidden) ===
	bid_panel = _build_bid_panel()
	bid_panel.visible = false
	add_child(bid_panel)

	# === Action bar ===
	action_bar = HBoxContainer.new()
	action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	action_bar.add_theme_constant_override("separation", 16)
	action_bar.custom_minimum_size = Vector2(0, 44)
	root.add_child(action_bar)

	# === Hand area ===
	hand_display = _HandDisplayClass.new()
	hand_display.custom_minimum_size = Vector2(0, 130)
	hand_display.size_flags_horizontal = SIZE_EXPAND_FILL
	hand_display.selection_changed.connect(_on_hand_selection_changed)
	root.add_child(hand_display)

	# === Log panel (compact, at very bottom) ===
	log_panel = RichTextLabel.new()
	log_panel.bbcode_enabled = true
	log_panel.scroll_following = true
	log_panel.custom_minimum_size = Vector2(0, 80)
	log_panel.add_theme_font_size_override("normal_font_size", 12)
	log_panel.add_theme_color_override("default_color", Color(0.7, 0.7, 0.7))
	root.add_child(log_panel)


func _build_info_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 24)
	bar.custom_minimum_size = Vector2(0, 36)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.18, 0.10, 0.9)
	bg.content_margin_left = 16
	bg.content_margin_right = 16
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", bg)

	for key: String in ["rank", "trump", "dealer", "score", "round"]:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
		bar.add_child(lbl)
		info_labels[key] = lbl

	return bar


func _build_seat_panel(seat: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.22, 0.12, 0.7)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = SEAT_NAMES[seat]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(name_lbl)
	seat_name_labels[seat] = name_lbl

	var count_lbl := Label.new()
	count_lbl.text = "25 张"
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.add_theme_font_size_override("font_size", 13)
	count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(count_lbl)
	seat_count_labels[seat] = count_lbl

	# Card back (mini) for AI
	var card_back = _CardViewClass.new()
	card_back.custom_minimum_size = Vector2(40, 56)
	card_back.size = Vector2(40, 56)
	card_back.face_up = false
	card_back.disabled = true
	vbox.add_child(card_back)

	seat_panels[seat] = panel
	return panel


func _build_table_center() -> Control:
	var center := Control.new()
	center.custom_minimum_size = Vector2(400, 200)

	# 4 slots for played cards, positioned relative to center
	for seat: int in [0, 1, 2, 3]:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(90, 110)
		slot.size = slot.custom_minimum_size
		center.add_child(slot)
		center_card_slots[seat] = slot

	center.resized.connect(_position_center_slots)
	return center


func _position_center_slots() -> void:
	var cx := table_center.size.x * 0.5
	var cy := table_center.size.y * 0.5
	var slot_w: float = 90.0
	var slot_h: float = 110.0
	var hoff := 80.0
	var voff := 55.0

	# South (seat 0) — bottom center
	center_card_slots[0].position = Vector2(cx - slot_w * 0.5, cy + voff - slot_h * 0.5)
	# North (seat 2) — top center
	center_card_slots[2].position = Vector2(cx - slot_w * 0.5, cy - voff - slot_h * 0.5)
	# East (seat 1) — right
	center_card_slots[1].position = Vector2(cx + hoff - slot_w * 0.5, cy - slot_h * 0.5)
	# West (seat 3) — left
	center_card_slots[3].position = Vector2(cx - hoff - slot_w * 0.5, cy - slot_h * 0.5)


func _build_bid_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(PRESET_CENTER)
	panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -150)
	panel.set_anchor_and_offset(SIDE_RIGHT, 0.5, 150)
	panel.set_anchor_and_offset(SIDE_TOP, 0.4, -60)
	panel.set_anchor_and_offset(SIDE_BOTTOM, 0.4, 60)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_color = Color(0.8, 0.7, 0.4, 0.6)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	vbox.name = "BidContent"
	panel.add_child(vbox)

	return panel


func _create_table_felt() -> ColorRect:
	var felt := ColorRect.new()
	felt.color = TABLE_FELT_COLOR
	felt.set_anchors_preset(PRESET_CENTER)
	felt.set_anchor_and_offset(SIDE_LEFT, 0.1, 0)
	felt.set_anchor_and_offset(SIDE_RIGHT, 0.9, 0)
	felt.set_anchor_and_offset(SIDE_TOP, 0.08, 0)
	felt.set_anchor_and_offset(SIDE_BOTTOM, 0.6, 0)
	return felt


# ============================================================
# Game flow (mirrors tui_game.gd structure)
# ============================================================

func _start_new_game() -> void:
	ui_log_lines = []
	if log_panel:
		log_panel.clear()

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

	team_ranks = [Card.Rank.TWO, Card.Rank.TWO]
	current_dealer = 0
	round_num = 0
	is_first_game = true
	_sync_controller_from_host_state()

	_log("[color=gold]═══ 双升对局 — 图形版 ═══[/color]")
	_start_round()


func _start_round() -> void:
	round_num += 1
	current_rank = team_ranks[current_dealer % 2]
	rule_config.current_rank = current_rank
	var round_seed := (base_seed + round_num - 1) if base_seed >= 0 else randi()

	round_num -= 1
	_sync_controller_from_host_state()
	session_controller.start_round(round_seed)
	_sync_host_from_controller()

	hand_display.set_trump_context(game_round.trump_suit, current_rank, rule_config.joker_always_trump)
	hand_display.set_sort_callback(_sort_hand_callback)

	var trump_str := Card.rank_symbol(current_rank)
	var dealer_team_name: String = ["南北队", "东西队"][current_dealer % 2] as String
	_log("[color=cyan]══ 第 %d 局 | %s 打 %s 级 | 庄家: %s ══[/color]" % [
		round_num, dealer_team_name, trump_str, SEAT_NAMES[current_dealer]])

	_update_info()
	_update_seat_counts()
	_clear_table_cards()
	_start_bidding()


# ============================================================
# Bidding
# ============================================================

func _start_bidding() -> void:
	current_phase = "bidding"
	session_controller.current_phase = "bidding"

	if is_first_game:
		_log("[color=green]— 亮主阶段（首局·先到先得）—[/color]")
		var context := session_controller.get_bidding_context(human_seat)
		var human_bids: Array = context["available_bids"]
		if not human_bids.is_empty():
			_show_bid_options(human_bids)
		else:
			_set_message("你没有可亮的牌")
			_log("你 无可亮牌（跳过）")
			session_controller.submit_bid_or_pass(human_seat, null, "no_valid_cards")
			_finish_bidding_round()
	else:
		_log("[color=green]— 亮主阶段（从庄家开始轮询）—[/color]")
		_bid_seat_index = 0
		_process_next_bidder()


func _process_next_bidder() -> void:
	if game_round.bid_declaration != null:
		_finish_bidding()
		return
	if _bid_seat_index >= 4:
		session_controller.resolve_no_bid_default()
		_log("无人亮主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])
		_finish_bidding()
		return

	var seat := (current_dealer + _bid_seat_index) % 4
	var context := session_controller.get_bidding_context(seat)

	if seat == human_seat:
		var human_bids: Array = context["available_bids"]
		if not human_bids.is_empty():
			_show_bid_options(human_bids)
			return
		else:
			_set_message("你没有可亮的牌（跳过）")
			session_controller.submit_bid_or_pass(seat, null, "no_valid_cards")
	else:
		var hand: Array = context["hand"]
		var bid_rank: int = context["bid_rank"]
		var available_bids: Array = context["available_bids"]
		var decl := AIPlayer.decide_bid(seat, hand, bid_rank, rule_config)
		var bid_result := session_controller.submit_bid_or_pass(seat, decl) if decl != null else session_controller.submit_bid_or_pass(seat, null, "no_valid_cards" if available_bids.is_empty() else "ai_pass")
		if decl != null and bid_result["ok"] and session_controller.current_phase == "burying":
			_log("%s 亮主: %s" % [SEAT_NAMES[seat], TrumpBidding.bid_label(decl)])
			_sync_host_from_controller()
			_finish_bidding()
			return
		else:
			_log("%s 跳过" % SEAT_NAMES[seat])

	_bid_seat_index += 1
	_process_next_bidder()


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
				_log("%s 亮主: %s" % [SEAT_NAMES[seat], TrumpBidding.bid_label(decl)])
				break

	if not bid_made:
		session_controller.resolve_no_bid_default()
		_log("无人亮主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])

	_finish_bidding()


func _finish_bidding() -> void:
	if session_controller.current_phase == "bidding":
		session_controller.finish_bidding_if_ready()
	_sync_host_from_controller()

	hand_display.set_trump_context(game_round.trump_suit, current_rank, rule_config.joker_always_trump)

	_log("主花色: %s | 庄家: %s" % [_trump_str(), SEAT_NAMES[game_round.dealer_seat]])
	_update_info()
	_hide_bid_panel()
	_start_bury()


func _show_bid_options(bids: Array) -> void:
	waiting_for_input = true
	_refresh_hand_display(false)

	var content := bid_panel.get_node("BidContent")
	for child: Node in content.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "选择亮主"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	content.add_child(title)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	content.add_child(btn_row)

	for i: int in range(bids.size()):
		var b: TrumpBidding.BidDeclaration = bids[i]
		var btn := _make_styled_button(TrumpBidding.bid_label(b), _get_suit_button_color(b))
		var idx := i
		btn.pressed.connect(func() -> void: _on_bid_selected(bids, idx))
		btn_row.add_child(btn)

	var skip_btn := _make_styled_button("不亮", Color(0.4, 0.4, 0.4))
	skip_btn.pressed.connect(_on_bid_skip)
	btn_row.add_child(skip_btn)

	bid_panel.visible = true


func _on_bid_selected(bids: Array, index: int) -> void:
	if not waiting_for_input:
		return
	waiting_for_input = false
	var decl: TrumpBidding.BidDeclaration = bids[index]
	session_controller.submit_bid_or_pass(human_seat, decl)
	_sync_host_from_controller()
	_log("你亮主: %s" % TrumpBidding.bid_label(decl))
	_hide_bid_panel()
	if is_first_game:
		_finish_bidding_round()
	else:
		_finish_bidding()


func _on_bid_skip() -> void:
	if not waiting_for_input:
		return
	waiting_for_input = false
	_log("你选择不亮")
	session_controller.submit_bid_or_pass(human_seat, null, "player_choice")
	_hide_bid_panel()
	if is_first_game:
		_finish_bidding_round()
	else:
		_bid_seat_index += 1
		_process_next_bidder()


func _hide_bid_panel() -> void:
	bid_panel.visible = false


# ============================================================
# Bury phase
# ============================================================

func _start_bury() -> void:
	current_phase = "burying"
	var context := session_controller.get_bury_context()
	# 反主后 bury_seat = 反家（≠ dealer）。必须用 bury_seat 判断是否人类扣底，
	# 否则反主人是人类时会被误判成"AI 扣底"，UI 不弹配底面板直接跳到出牌。
	var bury_seat: int = context.get("bury_seat", context["dealer"])
	var is_counter_re_bury: bool = context.get("is_counter_re_bury", false)
	var label := "反家" if is_counter_re_bury else "庄家"

	if bury_seat != human_seat:
		var merged: Array = context["merged_hand"]
		var indices := AIPlayer.decide_bury(merged, rule_config.bottom_size,
			game_round.trump_suit, current_rank, rule_config)
		session_controller.submit_bury(indices)
		_log("%s（%s）完成配底" % [SEAT_NAMES[bury_seat], label])
		_auto_save_log()
		_after_bury_done()
	else:
		var merged: Array = context["merged_hand"]
		_set_message("配底阶段（%s）— 选 %d 张扣底" % [label, rule_config.bottom_size])
		hand_display.show_hand(merged, true)
		_show_bury_actions()


func _show_bury_actions() -> void:
	_clear_actions()
	var confirm_btn := _make_styled_button("确认扣底 (0/%d)" % rule_config.bottom_size, Color(0.2, 0.7, 0.3))
	confirm_btn.name = "ConfirmBury"
	confirm_btn.pressed.connect(_on_bury_confirm)
	action_bar.add_child(confirm_btn)


func _on_hand_selection_changed(count: int) -> void:
	if current_phase == "burying":
		var confirm := action_bar.get_node_or_null("ConfirmBury")
		if confirm is Button:
			(confirm as Button).text = "确认扣底 (%d/%d)" % [count, rule_config.bottom_size]


func _on_bury_confirm() -> void:
	var selected = hand_display.get_selected_cards()
	if selected.size() != rule_config.bottom_size:
		_set_message("请选择 %d 张牌扣底（当前选了 %d 张）" % [rule_config.bottom_size, selected.size()])
		return

	var merged := game_round.get_dealer_hand_with_bottom()
	var actual_indices: Array[int] = []
	var used: Dictionary = {}
	for sel_card: Card in selected:
		for i: int in range(merged.size()):
			if used.has(i):
				continue
			if (merged[i] as Card).equals(sel_card):
				actual_indices.append(i)
				used[i] = true
				break

	var result := session_controller.submit_bury(actual_indices)
	if result["ok"]:
		_log("配底完成")
		_auto_save_log()
		_after_bury_done()
	else:
		_set_message("配底失败: %s" % result["error"])


func _after_bury_done() -> void:
	_sync_host_from_controller()
	if session_controller.current_phase == "counter_window":
		_handle_counter_window()
	else:
		_start_play_phase()


# ============================================================
# Counter-bid window
# ============================================================

func _handle_counter_window() -> void:
	var seat := session_controller.get_current_counter_seat()
	if seat < 0:
		_finish_counter_no_change()
		return

	if seat == human_seat:
		var ctx := session_controller.get_counter_context(seat)
		if ctx.get("has_any", false):
			_show_counter_options(ctx)
			return

	# AI or no valid counter — auto pass loop
	_auto_counter_pass_loop()


func _auto_counter_pass_loop() -> void:
	var safety: int = 8
	while session_controller.current_phase == "counter_window" and safety > 0:
		var seat := session_controller.get_current_counter_seat()
		if seat < 0:
			break

		if seat == human_seat:
			var ctx := session_controller.get_counter_context(seat)
			if ctx.get("has_any", false):
				_show_counter_options(ctx)
				return
			else:
				session_controller.submit_counter_or_pass(seat, null, "no_valid_counter")
				_log("你没有可反的牌（跳过）")
		else:
			var ctx := session_controller.get_counter_context(seat)
			var counter_bids: Array = ctx.get("available_counter_bids", [])
			var decl: TrumpBidding.BidDeclaration = null
			if not counter_bids.is_empty():
				decl = AIPlayer.decide_counter(seat, game_round.get_hand(seat), current_rank, game_round.bid_declaration, rule_config)

			if decl != null:
				var res := session_controller.submit_counter_or_pass(seat, decl)
				if res.get("counter_made", false):
					_log("%s 反主: %s" % [SEAT_NAMES[seat], TrumpBidding.bid_label(decl)])
					_sync_host_from_controller()
					hand_display.set_trump_context(game_round.trump_suit, current_rank, rule_config.joker_always_trump)
					_update_info()
					_start_bury()
					return
			else:
				session_controller.submit_counter_or_pass(seat, null, "ai_pass")
				_log("%s 放弃反主" % SEAT_NAMES[seat])

		safety -= 1

	_finish_counter_no_change()


func _show_counter_options(ctx: Dictionary) -> void:
	waiting_for_input = true
	var counter_bids: Array = ctx["available_counter_bids"]

	_refresh_hand_display(false)

	var content := bid_panel.get_node("BidContent")
	for child: Node in content.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "反主"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	content.add_child(title)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	content.add_child(btn_row)

	for i: int in range(counter_bids.size()):
		var b: TrumpBidding.BidDeclaration = counter_bids[i]
		var btn := _make_styled_button(TrumpBidding.bid_label(b), Color(1, 0.5, 0.2))
		var idx := i
		btn.pressed.connect(func() -> void: _on_counter_selected(counter_bids, idx))
		btn_row.add_child(btn)

	var pass_btn := _make_styled_button("放弃", Color(0.4, 0.4, 0.4))
	pass_btn.pressed.connect(_on_counter_pass)
	btn_row.add_child(pass_btn)

	bid_panel.visible = true


func _on_counter_selected(bids: Array, index: int) -> void:
	if not waiting_for_input:
		return
	waiting_for_input = false
	var decl: TrumpBidding.BidDeclaration = bids[index]
	var res := session_controller.submit_counter_or_pass(human_seat, decl)
	_hide_bid_panel()

	if res.get("counter_made", false):
		_log("你反主: %s" % TrumpBidding.bid_label(decl))
		_sync_host_from_controller()
		hand_display.set_trump_context(game_round.trump_suit, current_rank, rule_config.joker_always_trump)
		_update_info()
		_start_bury()
	else:
		_set_message("反主失败")
		_auto_counter_pass_loop()


func _on_counter_pass() -> void:
	if not waiting_for_input:
		return
	waiting_for_input = false
	_log("你放弃反主")
	session_controller.submit_counter_or_pass(human_seat, null, "player_choice")
	_hide_bid_panel()
	_auto_counter_pass_loop()


func _finish_counter_no_change() -> void:
	_sync_host_from_controller()
	_start_play_phase()


# ============================================================
# Play phase
# ============================================================

func _start_play_phase() -> void:
	_log("[color=green]— 出牌阶段 —[/color]")
	trick_num = 0
	session_controller.current_phase = "playing"
	_clear_actions()
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

	_log("--- 第 %d 墩 | 先手: %s | 攻方: %d 分 ---" % [
		trick_num, SEAT_NAMES[game_round.current_lead_seat],
		game_round.score_tracker.get_attack_score()])

	_update_info()
	_update_seat_counts()
	_clear_table_cards()
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
	_show_played_cards(seat, cards)
	_update_seat_counts()
	_log("  %s 出: %s" % [SEAT_NAMES[seat], _cards_str(cards)])

	if result.get("trick_complete", false):
		get_tree().create_timer(0.6).timeout.connect(_resolve_trick)
		return
	get_tree().create_timer(0.3).timeout.connect(_process_next_player)


func _show_play_options(seat: int) -> void:
	var turn := session_controller.get_current_turn_context()
	var hand: Array = turn["hand"]
	var is_leading: bool = turn["is_leading"]

	current_phase = "leading" if is_leading else "following"
	waiting_for_input = true

	_refresh_hand_display(true)

	_clear_actions()
	var play_btn := _make_styled_button("出牌", Color(0.2, 0.7, 0.3))
	play_btn.name = "PlayConfirm"
	play_btn.pressed.connect(_on_play_confirm)
	action_bar.add_child(play_btn)

	var hint := "请出牌（首出）" if is_leading else "请跟牌（%d 张）" % (0 if trick_play_cards.is_empty() else trick_play_cards[0].size())
	_set_message(hint)


func _on_play_confirm() -> void:
	if not waiting_for_input:
		return
	var selected = hand_display.get_selected_cards()
	if selected.is_empty():
		_set_message("请先选牌")
		return

	var cards: Array = []
	for c: Card in selected:
		cards.append(c)

	var submit := session_controller.submit_play(human_seat, cards)
	if not submit["ok"]:
		var err: String = submit["error"]
		if err == "wrong_card_count":
			var turn := session_controller.get_current_turn_context()
			_set_message("需要出 %d 张牌（当前选了 %d 张）" % [turn["lead_count"], cards.size()])
		elif err == "invalid_follow":
			_set_message("跟牌不合法，请重新选择")
		else:
			_set_message("出牌不合法: %s" % err)
		return

	waiting_for_input = false
	_sync_trick_host_from_controller()
	_show_played_cards(human_seat, cards)
	_update_seat_counts()
	_log("  你出: %s" % _cards_str(cards))

	_clear_actions()
	if submit.get("trick_complete", false):
		get_tree().create_timer(0.6).timeout.connect(_resolve_trick)
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
		get_tree().create_timer(1.0).timeout.connect(_finish_round)
	else:
		get_tree().create_timer(0.8).timeout.connect(_start_next_trick)


func _finish_round() -> void:
	var finish := session_controller.finish_round()
	var settlement: EffectiveSettlement = finish["settlement"]
	_sync_host_from_controller()

	_clear_table_cards()
	_clear_actions()
	_show_settlement(settlement, finish)


func _show_settlement(settlement: EffectiveSettlement, finish: Dictionary) -> void:
	_log("\n[color=gold]═══════ 结算 ═══════[/color]")
	_log("出牌阶段攻方得分: %d" % settlement.attack_base_score)
	if settlement.bottom_multiplier > 0:
		_log("底牌: %d × %d 倍 = %d" % [settlement.bottom_score, settlement.bottom_multiplier, settlement.bottom_bonus])
	else:
		_log("庄家方赢最后一墩，底牌不计分")
	_log("最终得分: %d" % settlement.final_score)

	var upgrading_team := finish["upgrading_team"] as int
	var team_names: Array[String] = ["南北队", "东西队"]
	var team_name: String = team_names[upgrading_team]

	if settlement.upgrade_blocked:
		_log("[color=orange]%s 提案升 %d 级 → %s，但必打级拦截，实际留在 %s[/color]" % [
			team_name, settlement.proposal.upgrade_levels,
			Card.rank_symbol(settlement.proposal.new_rank),
			Card.rank_symbol(settlement.new_rank)])
	elif settlement.upgrade_levels > 0:
		_log("%s 升 %d 级 → 新级: %s" % [team_name, settlement.upgrade_levels, Card.rank_symbol(settlement.new_rank)])
	elif settlement.dealer_dethroned:
		_log("攻方下庄（不升级）")
	else:
		_log("庄家方守住")

	var summary_text: String
	if settlement.upgrade_blocked:
		summary_text = "%s 升级被必打级拦截" % team_name
	elif settlement.upgrade_levels > 0:
		summary_text = "%s 升 %d 级" % [team_name, settlement.upgrade_levels]
	elif settlement.dealer_dethroned:
		summary_text = "攻方下庄"
	else:
		summary_text = "庄家方守住"
	_set_message("得分: %d | %s" % [settlement.final_score, summary_text])

	_auto_save_log()

	if settlement.game_over:
		_log("\n[color=gold]游戏结束！%s 获胜！[/color]" % team_name)
		_save_log()
		var restart_btn := _make_styled_button("再来一局", Color(0.3, 0.7, 0.9))
		restart_btn.pressed.connect(_start_new_game)
		action_bar.add_child(restart_btn)
	else:
		_log("  南北队: %s 级 | 东西队: %s 级" % [
			Card.rank_symbol(team_ranks[0]), Card.rank_symbol(team_ranks[1])])

		var next_btn := _make_styled_button("下一局", Color(0.3, 0.7, 0.9))
		next_btn.pressed.connect(_start_round)
		action_bar.add_child(next_btn)

		var save_btn := _make_styled_button("保存日志", Color(0.5, 0.7, 0.5))
		save_btn.pressed.connect(_save_log)
		action_bar.add_child(save_btn)


# ============================================================
# Display helpers
# ============================================================

func _refresh_hand_display(interactive: bool) -> void:
	var hand := game_round.get_hand(human_seat)
	hand_display.show_hand(hand, interactive)


func _show_played_cards(seat: int, cards: Array) -> void:
	table_cards[seat] = cards
	var slot: Control = center_card_slots[seat]
	# Clear old
	for child: Node in slot.get_children():
		child.queue_free()

	var offset := 0.0
	for card: Card in cards:
		var cv = _CardViewClass.new()
		cv.setup(card, true, _is_trump(card))
		cv.disabled = true
		cv.position = Vector2(offset, 0)
		slot.add_child(cv)
		offset += 22.0


func _clear_table_cards() -> void:
	table_cards = {}
	for seat: int in center_card_slots:
		var slot: Control = center_card_slots[seat]
		for child: Node in slot.get_children():
			child.queue_free()


func _update_info() -> void:
	var trump := _trump_str()
	var score := 0
	if game_round and game_round.score_tracker:
		score = game_round.score_tracker.get_attack_score()
	var dealer_name := SEAT_NAMES[game_round.dealer_seat] if game_round else "—"

	if info_labels.has("rank"):
		info_labels["rank"].text = "级: %s" % Card.rank_symbol(current_rank)
	if info_labels.has("trump"):
		info_labels["trump"].text = "主: %s" % trump
	if info_labels.has("dealer"):
		info_labels["dealer"].text = "庄家: %s" % dealer_name
	if info_labels.has("score"):
		info_labels["score"].text = "攻方: %d 分" % score
	if info_labels.has("round"):
		info_labels["round"].text = "第 %d 局" % round_num


func _update_seat_counts() -> void:
	if game_round == null:
		return
	for seat: int in [1, 2, 3]:
		if seat_count_labels.has(seat):
			var count := game_round.get_hand_size(seat)
			seat_count_labels[seat].text = "%d 张" % count
	# Update dealer markers
	for seat: int in [1, 2, 3]:
		if seat_name_labels.has(seat):
			var base := SEAT_NAMES[seat]
			if seat == game_round.dealer_seat:
				seat_name_labels[seat].text = base + " [庄]"
				seat_name_labels[seat].add_theme_color_override("font_color", Color(1, 0.85, 0.3))
			else:
				seat_name_labels[seat].text = base
				seat_name_labels[seat].add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))


func _set_message(msg: String) -> void:
	message_label.text = msg


# ============================================================
# State sync (same as tui_game.gd)
# ============================================================

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
# Logging
# ============================================================

func _log(msg: String) -> void:
	ui_log_lines.append(msg)
	while ui_log_lines.size() > UI_LOG_MAX_LINES:
		ui_log_lines.remove_at(0)
	if log_panel:
		log_panel.clear()
		log_panel.append_text("\n".join(ui_log_lines) + "\n")


func _auto_save_log() -> void:
	if logger:
		logger.save_to_file(_resolve_log_path("game_log_latest.json"), false)


func _save_log() -> void:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var log_path := _resolve_log_path("game_log_%s.json" % timestamp)
	var err := logger.save_to_file(log_path)
	if err == OK:
		_log("[color=green]日志已保存: %s[/color]" % log_path)
	else:
		_log("[color=red]日志保存失败: %s[/color]" % error_string(err))


func _resolve_log_path(filename: String) -> String:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repo_root := project_root.get_base_dir().get_base_dir()
	return "%s/docs/game-logs/%s" % [repo_root, filename]


# ============================================================
# UI factory helpers
# ============================================================

func _make_styled_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = color.darkened(0.3)
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := style_normal.duplicate()
	style_hover.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = color
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	return btn


func _clear_actions() -> void:
	for child: Node in action_bar.get_children():
		child.queue_free()


func _get_suit_button_color(decl: TrumpBidding.BidDeclaration) -> Color:
	match decl.suit:
		Card.Suit.HEART, Card.Suit.DIAMOND:
			return Color(0.8, 0.2, 0.2)
		Card.Suit.SPADE, Card.Suit.CLUB:
			return Color(0.25, 0.35, 0.55)
		_:
			return Color(0.6, 0.4, 0.1)


# ============================================================
# Utility
# ============================================================

func _trump_str() -> String:
	if game_round == null:
		return "—"
	return "公主" if game_round.trump_suit < 0 else Card.suit_symbol(game_round.trump_suit)


func _cards_str(cards: Array) -> String:
	var parts: Array[String] = []
	for c: Card in cards:
		parts.append(c.to_string_repr())
	return " ".join(parts)


func _is_trump(card: Card) -> bool:
	if game_round == null:
		return false
	return TrumpJudge.is_trump(card, game_round.trump_suit, current_rank, rule_config.joker_always_trump)


func _sort_hand_callback(hand: Array) -> Array:
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
		Card.Suit.CLUB:    return 1
		Card.Suit.HEART:   return 2
		Card.Suit.SPADE:   return 3
		Card.Suit.DIAMOND: return 4
		_:                 return 5


func _card_identity_key(card: Card) -> String:
	if card.is_joker:
		return "joker_%d" % card.joker_type
	return "%d_%02d" % [card.suit, card.rank]
