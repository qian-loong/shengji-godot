## GUI Game — graphical card table interface.
## Replaces TUI with proper Godot 2D visuals.
## Uses SessionController for all game logic (same as tui_game.gd).
extends Control

const SEAT_NAMES: Array[String] = ["你(南)", "AI-东", "搭档(北)", "AI-西"]
const TABLE_BG_COLOR := Color(0.05, 0.13, 0.09)
const TABLE_FELT_COLOR := Color(0.11, 0.42, 0.22)
const TABLE_FELT_EDGE := Color(0.62, 0.46, 0.20)

## Played cards in the center trick area — larger than the base card so the
## current trick is clearly readable.
const PLAYED_CARD_W := 104.0
const PLAYED_CARD_H := 141.0
const PLAYED_CARD_STEP := 30.0
const SEAT_CARD_H := 72.0
const SEAT_CARD_W := SEAT_CARD_H * (140.0 / 190.0)

var _CardViewClass: GDScript
var _HandDisplayClass: GDScript

const SUIT_ICON_PATHS := {
	Card.Suit.SPADE:   "res://assets/ui/suits/suit_spade_%s.svg",
	Card.Suit.HEART:   "res://assets/ui/suits/suit_heart_%s.svg",
	Card.Suit.CLUB:    "res://assets/ui/suits/suit_club_%s.svg",
	Card.Suit.DIAMOND: "res://assets/ui/suits/suit_diamond_%s.svg",
}

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
var seat_dealer_badges: Dictionary = {} # seat -> Control (庄)
var seat_bid_badges: Dictionary = {}    # seat -> Control (亮)
var seat_card_backs: Dictionary = {}    # seat -> CardView (mini back)
var hand_display = null
var action_bar: HBoxContainer
var first_deal_bid_panel: PanelContainer
var first_deal_bid_buttons: HBoxContainer
var bid_panel: PanelContainer
var previous_trick_btn: Button
var bottom_btn: Button
var preview_panel: PanelContainer
var preview_content: VBoxContainer
var settlement_panel: PanelContainer
var settlement_content: VBoxContainer
var hand_area_panel: PanelContainer
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
var debug_ui_enabled: bool = false

var current_phase: String = "idle"
var waiting_for_input: bool = false
var _bid_seat_index: int = 0
var first_game_dealing: bool = false
var deal_round_index: int = 0
var deal_seat_index: int = 0
var visible_deal_hands: Array = [[], [], [], []]
var pending_first_bid: TrumpBidding.BidDeclaration = null
var visible_first_bid_choices: Array = []
const DEAL_STEP_SECONDS: float = 0.08

# Trick state
var trick_play_cards: Array = []
var trick_seat_index: int = 0
var trick_seat_order: Array[int] = []
var trick_lead_info: Dictionary = {}
var trick_num: int = 0
var table_cards: Dictionary = {}
var last_trick_plays_snapshot: Dictionary = {}
var human_bottom_received_snapshot: Array = []
var human_buried_bottom_snapshot: Array = []
var preview_token: int = 0
var active_turn_seat: int = -1
var seat_panel_base_styles: Dictionary = {}
var hand_area_base_style: StyleBoxFlat

const HAND_ACTION_BAR_H := 48.0
const SEAT_ACTIVE_BORDER := Color(1.0, 0.88, 0.35, 0.95)
const SEAT_WINNER_BORDER := Color(1.0, 0.72, 0.12, 1.0)

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
		elif arg == "--debug-ui" or arg == "--dev-ui":
			debug_ui_enabled = true
		elif arg == "--hide-debug-ui":
			debug_ui_enabled = false


var _back_request_in_flight: bool = false
# Android delivers a single back press as both NOTIFICATION_WM_GO_BACK_REQUEST
# and a KEY_BACK / ui_cancel input event in the same frame. Without this guard
# the first path would dismiss an overlay and the second would immediately
# proceed to the main menu, so a single press would skip two steps.
var _back_consumed_frame: int = -1


func _unhandled_input(event: InputEvent) -> void:
	if not _is_back_input(event):
		return
	# Consume BEFORE handling: change_scene_to_file() removes this Control
	# from the tree, after which get_viewport() would be null.
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()
	_handle_back_request()


func _is_back_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACK


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()


func _handle_back_request() -> void:
	if _back_request_in_flight:
		return
	var frame := Engine.get_process_frames()
	if _back_consumed_frame == frame:
		return
	_back_consumed_frame = frame

	if preview_panel and preview_panel.visible:
		_hide_preview_panel()
		return
	if bid_panel and bid_panel.visible:
		# Hiding the panel alone leaves waiting_for_input=true and never
		# notifies the SessionController, softlocking the bidding phase.
		# Treat back as a deliberate skip so the round can advance.
		if waiting_for_input:
			_on_bid_skip()
		else:
			_hide_bid_panel()
		return
	if first_deal_bid_panel and first_deal_bid_panel.visible:
		_hide_first_deal_bid_panel()
		return
	_back_request_in_flight = true
	_return_to_main_menu()


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


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

	# === First-deal bid bar (above hand) ===
	first_deal_bid_panel = _build_first_deal_bid_panel()
	first_deal_bid_panel.visible = false
	root.add_child(first_deal_bid_panel)

	# === Hand action strip (fixed row above hand — does not steal hand width) ===
	action_bar = HBoxContainer.new()
	action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	action_bar.add_theme_constant_override("separation", 16)
	action_bar.custom_minimum_size = Vector2(0, HAND_ACTION_BAR_H)
	action_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	action_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(action_bar)

	# === Hand area (full width; selected-card rise stays inside via clip + rise budget) ===
	hand_display = _HandDisplayClass.new()
	hand_display.custom_minimum_size = Vector2(0, _hand_area_min_height())
	hand_display.size_flags_horizontal = SIZE_EXPAND_FILL
	hand_display.selection_changed.connect(_on_hand_selection_changed)
	hand_area_panel = PanelContainer.new()
	hand_area_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	hand_area_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	hand_area_base_style = StyleBoxFlat.new()
	hand_area_base_style.bg_color = Color(0, 0, 0, 0)
	hand_area_base_style.set_corner_radius_all(10)
	hand_area_base_style.set_border_width_all(0)
	hand_area_panel.add_theme_stylebox_override("panel", hand_area_base_style)
	hand_area_panel.add_child(hand_display)
	root.add_child(hand_area_panel)

	# === Log panel (compact, at very bottom) ===
	log_panel = RichTextLabel.new()
	log_panel.bbcode_enabled = true
	log_panel.scroll_following = true
	log_panel.visible = debug_ui_enabled
	log_panel.custom_minimum_size = Vector2(0, 80) if debug_ui_enabled else Vector2.ZERO
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

	# Key info (级/主) is emphasized with larger, brighter text so players can
	# read the current rank and trump at a glance; secondary info stays muted.
	for key: String in ["rank", "trump", "dealer", "score", "round"]:
		var lbl := Label.new()
		if key == "rank" or key == "trump":
			lbl.add_theme_font_size_override("font_size", 24)
			lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
			lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
			lbl.add_theme_constant_override("outline_size", 4)
		else:
			lbl.add_theme_font_size_override("font_size", 15)
			lbl.add_theme_color_override("font_color", Color(0.82, 0.80, 0.68))
		bar.add_child(lbl)
		info_labels[key] = lbl

	previous_trick_btn = _make_styled_button("上一轮", Color(0.25, 0.45, 0.65))
	previous_trick_btn.disabled = true
	previous_trick_btn.pressed.connect(_show_previous_trick_preview)
	bar.add_child(previous_trick_btn)

	bottom_btn = _make_styled_button("底牌", Color(0.55, 0.40, 0.20))
	bottom_btn.visible = false
	bottom_btn.pressed.connect(_show_bottom_preview)
	bar.add_child(bottom_btn)

	return bar


func _build_first_deal_bid_panel() -> PanelContainer:
	# Shrinks to hug the suit buttons (no full-width background / side whitespace).
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.14, 0.08, 0.92)
	sb.border_color = Color(0.62, 0.46, 0.20, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)

	first_deal_bid_buttons = HBoxContainer.new()
	first_deal_bid_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	first_deal_bid_buttons.add_theme_constant_override("separation", 8)
	panel.add_child(first_deal_bid_buttons)

	return panel


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
	seat_panel_base_styles[seat] = style.duplicate()

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Badge row (庄 = dealer, 亮 = trump declarer), toggled at runtime.
	var badge_row := HBoxContainer.new()
	badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_row.add_theme_constant_override("separation", 4)
	vbox.add_child(badge_row)

	var dealer_badge := _make_seat_badge("庄", Color(0.85, 0.62, 0.15))
	badge_row.add_child(dealer_badge)
	seat_dealer_badges[seat] = dealer_badge

	var bid_badge := _make_seat_badge("亮", Color(0.20, 0.55, 0.85))
	badge_row.add_child(bid_badge)
	seat_bid_badges[seat] = bid_badge

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

	# Kenney card back at seat — keep 140:190 aspect; don't let the panel stretch it.
	var card_back = _CardViewClass.new()
	card_back.custom_minimum_size = Vector2(SEAT_CARD_W, SEAT_CARD_H)
	card_back.size = Vector2(SEAT_CARD_W, SEAT_CARD_H)
	card_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_back.face_up = false
	card_back.disabled = true
	vbox.add_child(card_back)
	seat_card_backs[seat] = card_back

	seat_panels[seat] = panel
	return panel


## Small rounded pill badge (e.g. 庄/亮) shown on a seat panel header.
func _make_seat_badge(text: String, color: Color) -> Control:
	var badge := PanelContainer.new()
	badge.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	badge.add_child(lbl)
	return badge


func _build_table_center() -> Control:
	var center := Control.new()
	# Keep the vertical minimum modest; the center expands to fill spare space and
	# played cards may overflow the slot. A large min here can push the hand row
	# off the bottom of the screen on shorter effective heights.
	center.custom_minimum_size = Vector2(480, 200)

	# 4 slots for played cards, positioned relative to center
	for seat: int in [0, 1, 2, 3]:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(90, 110)
		slot.size = slot.custom_minimum_size
		center.add_child(slot)
		center_card_slots[seat] = slot

	preview_panel = _build_preview_panel()
	center.add_child(preview_panel)

	settlement_panel = _build_settlement_panel()
	add_child(settlement_panel)

	center.resized.connect(_position_center_slots)
	return center


func _position_center_slots() -> void:
	var cx := table_center.size.x * 0.5
	var cy := table_center.size.y * 0.5
	var slot_w: float = PLAYED_CARD_W
	var slot_h: float = PLAYED_CARD_H
	# Spread played cards toward each seat, scaling with the available area.
	var hoff := maxf(130.0, table_center.size.x * 0.24)
	var voff := maxf(95.0, table_center.size.y * 0.30)

	# South (seat 0) — bottom center
	center_card_slots[0].position = Vector2(cx - slot_w * 0.5, cy + voff - slot_h * 0.5)
	# North (seat 2) — top center
	center_card_slots[2].position = Vector2(cx - slot_w * 0.5, cy - voff - slot_h * 0.5)
	# East (seat 1) — right
	center_card_slots[1].position = Vector2(cx + hoff - slot_w * 0.5, cy - slot_h * 0.5)
	# West (seat 3) — left
	center_card_slots[3].position = Vector2(cx - hoff - slot_w * 0.5, cy - slot_h * 0.5)
	if preview_panel:
		preview_panel.position = Vector2(cx - 310.0, cy - 150.0)


func _build_preview_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(620, 240)
	panel.size = panel.custom_minimum_size

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.06, 0.88)
	style.border_color = Color(0.95, 0.82, 0.45, 0.6)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	preview_content = VBoxContainer.new()
	preview_content.mouse_filter = MOUSE_FILTER_IGNORE
	preview_content.add_theme_constant_override("separation", 8)
	panel.add_child(preview_content)
	return panel


func _build_settlement_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.set_anchors_preset(PRESET_CENTER)
	panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -240)
	panel.set_anchor_and_offset(SIDE_RIGHT, 0.5, 240)
	panel.set_anchor_and_offset(SIDE_TOP, 0.5, -150)
	panel.set_anchor_and_offset(SIDE_BOTTOM, 0.5, 130)
	panel.z_index = 20

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.08, 0.96)
	style.border_color = Color(0.95, 0.82, 0.45, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)

	settlement_content = VBoxContainer.new()
	settlement_content.add_theme_constant_override("separation", 10)
	settlement_content.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(settlement_content)
	return panel


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


func _create_table_felt() -> Control:
	# Rounded felt "table" panel spanning most of the play region, with a soft
	# wood-tone border so it reads as a real card table instead of a flat block.
	var felt := Panel.new()
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	felt.set_anchors_preset(PRESET_FULL_RECT)
	felt.set_anchor_and_offset(SIDE_LEFT, 0.03, 0)
	felt.set_anchor_and_offset(SIDE_RIGHT, 0.97, 0)
	felt.set_anchor_and_offset(SIDE_TOP, 0.11, 0)
	felt.set_anchor_and_offset(SIDE_BOTTOM, 0.72, 0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = TABLE_FELT_COLOR
	sb.border_color = TABLE_FELT_EDGE
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(48)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	sb.anti_aliasing = true
	felt.add_theme_stylebox_override("panel", sb)
	return felt


# ============================================================
# Game flow (mirrors tui_game.gd structure)
# ============================================================

func _start_new_game() -> void:
	ui_log_lines = []
	if log_panel:
		log_panel.clear()
	_hide_settlement_panel()
	_clear_turn_highlights()

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
	last_trick_plays_snapshot = {}
	human_bottom_received_snapshot = []
	human_buried_bottom_snapshot = []
	first_game_dealing = false
	deal_round_index = 0
	deal_seat_index = 0
	visible_deal_hands = [[], [], [], []]
	pending_first_bid = null
	visible_first_bid_choices = []
	_hide_preview_panel()
	_sync_controller_from_host_state()
	_update_aux_buttons()

	_log("[color=gold]═══ 双升对局 — 图形版 ═══[/color]")
	_start_round()


func _start_round() -> void:
	_hide_settlement_panel()
	_clear_turn_highlights()
	round_num += 1
	current_rank = team_ranks[current_dealer % 2]
	rule_config.current_rank = current_rank
	var round_seed := (base_seed + round_num - 1) if base_seed >= 0 else randi()

	round_num -= 1
	_sync_controller_from_host_state()
	session_controller.start_round(round_seed)
	_sync_host_from_controller()
	last_trick_plays_snapshot = {}
	human_bottom_received_snapshot = []
	human_buried_bottom_snapshot = []
	_hide_preview_panel()

	hand_display.set_trump_context(game_round.trump_suit, current_rank, rule_config.joker_always_trump)
	hand_display.set_sort_callback(_sort_hand_callback)

	var trump_str := Card.rank_symbol(current_rank)
	var dealer_team_name: String = ["南北队", "东西队"][current_dealer % 2] as String
	_log("[color=cyan]══ 第 %d 局 | %s 打 %s 级 | 庄家: %s ══[/color]" % [
		round_num, dealer_team_name, trump_str, SEAT_NAMES[current_dealer]])

	_update_info()
	_update_seat_counts()
	_update_aux_buttons()
	_clear_table_cards()
	if is_first_game:
		_start_first_game_deal()
	else:
		_start_bidding()


# ============================================================
# Bidding
# ============================================================

func _start_first_game_deal() -> void:
	first_game_dealing = true
	deal_round_index = 0
	deal_seat_index = 0
	visible_deal_hands = [[], [], [], []]
	pending_first_bid = null
	visible_first_bid_choices = []
	current_phase = "dealing"
	session_controller.current_phase = "bidding"
	_clear_actions()
	_hide_bid_panel()
	_hide_first_deal_bid_panel()
	_refresh_first_deal_bid_bar()
	_update_visible_deal_counts()
	hand_display.show_hand([], false)
	_set_message("")
	_log("[color=green]— 首局发牌中抢主 —[/color]")
	_deal_next_visible_card()


func _deal_next_visible_card() -> void:
	if not first_game_dealing:
		return
	if deal_round_index >= rule_config.hand_size:
		_finish_first_game_deal()
		return

	var seat := deal_seat_index
	var card: Card = game_round.hands[seat][deal_round_index]
	(visible_deal_hands[seat] as Array).append(card)
	deal_seat_index += 1
	if deal_seat_index >= 4:
		deal_seat_index = 0
		deal_round_index += 1

	_update_visible_deal_counts()
	if seat == human_seat:
		hand_display.show_hand(visible_deal_hands[human_seat], false)
		_refresh_first_deal_bid_bar()
	if pending_first_bid == null:
		if seat == human_seat:
			pass
		else:
			var decl := AIPlayer.decide_bid(seat, visible_deal_hands[seat], current_rank, rule_config)
			if decl != null:
				pending_first_bid = decl
				_clear_actions()
				_hide_first_deal_bid_panel()
				_set_message("%s 已抢主: %s" % [SEAT_NAMES[seat], TrumpBidding.bid_label(decl)])
				_log("%s 抢主: %s" % [SEAT_NAMES[seat], TrumpBidding.bid_label(decl)])

	get_tree().create_timer(DEAL_STEP_SECONDS).timeout.connect(_deal_next_visible_card)


func _finish_first_game_deal() -> void:
	first_game_dealing = false
	current_phase = "bidding"
	waiting_for_input = false
	visible_first_bid_choices = []
	_clear_actions()
	_hide_first_deal_bid_panel()
	hand_display.show_hand(game_round.get_hand(human_seat), false)
	_update_seat_counts()

	if pending_first_bid != null:
		var result := session_controller.submit_bid_or_pass(pending_first_bid.seat_id, pending_first_bid)
		if result.get("ok", false):
			_log("抢主完成: %s | 庄家: %s" % [
				TrumpBidding.bid_label(pending_first_bid),
				SEAT_NAMES[pending_first_bid.seat_id],
			])
	else:
		session_controller.resolve_no_bid_default()
		_log("无人抢主，默认 %s 为庄家，公主局" % SEAT_NAMES[current_dealer])

	_finish_bidding()


func _update_visible_deal_counts() -> void:
	for seat: int in [1, 2, 3]:
		if seat_count_labels.has(seat):
			var count := (visible_deal_hands[seat] as Array).size()
			seat_count_labels[seat].text = "%d 张" % count


func _refresh_first_deal_bid_bar() -> void:
	if not first_game_dealing or pending_first_bid != null:
		return

	var bids := _strongest_bids_by_trump_choice(TrumpBidding.get_available_bids(
		human_seat,
		visible_deal_hands[human_seat],
		current_rank,
		rule_config
	))
	if _first_deal_choices_match(bids):
		return

	waiting_for_input = true
	visible_first_bid_choices = bids.duplicate()
	_clear_first_deal_bid_buttons()
	first_deal_bid_panel.visible = true

	for suit: int in [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]:
		_add_first_deal_bid_button(_bid_for_suit(bids, suit), suit)
	_add_first_deal_bid_button(_bid_for_suit(bids, -1), -1)


func _add_first_deal_bid_button(bid: TrumpBidding.BidDeclaration, choice: int) -> void:
	var available := bid != null
	var bg := Color(0.93, 0.92, 0.88) if available else Color(0.16, 0.18, 0.22)
	var is_no_trump := choice == -1

	var btn: Button
	if is_no_trump:
		btn = _make_styled_button("NT", bg)
		var glyph_color := Color(0.95, 0.82, 0.35) if available else Color(0.44, 0.46, 0.50)
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_theme_color_override("font_color", glyph_color)
		btn.add_theme_color_override("font_hover_color", glyph_color)
		btn.add_theme_color_override("font_pressed_color", glyph_color)
		btn.add_theme_color_override("font_disabled_color", glyph_color)
	else:
		btn = Button.new()
		btn.text = ""
		btn.icon = _load_suit_icon(choice, available)
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.add_theme_constant_override("icon_max_width", 40)
		_apply_bid_button_style(btn, bg)
	btn.custom_minimum_size = Vector2(56, 56)

	if not available:
		btn.disabled = true
	else:
		var chosen := bid
		btn.pressed.connect(func() -> void:
			_on_first_deal_bid_chosen(chosen)
		)
	first_deal_bid_buttons.add_child(btn)


func _load_suit_icon(suit: int, available: bool) -> Texture2D:
	if not SUIT_ICON_PATHS.has(suit):
		return null
	var variant := "colored" if available else "gray"
	var path: String = (SUIT_ICON_PATHS[suit] as String) % variant
	var tex: Texture2D = load(path)
	return tex


func _apply_bid_button_style(btn: Button, bg: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = bg.lightened(0.06)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = bg.darkened(0.10)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate()
	disabled.bg_color = bg
	btn.add_theme_stylebox_override("disabled", disabled)


func _on_first_deal_bid_chosen(decl: TrumpBidding.BidDeclaration) -> void:
	if not first_game_dealing or pending_first_bid != null or decl == null:
		return
	waiting_for_input = false
	visible_first_bid_choices = []
	pending_first_bid = decl
	_hide_first_deal_bid_panel()
	_log("你抢主: %s" % TrumpBidding.bid_label(decl))


func _bid_choice_key(bid: TrumpBidding.BidDeclaration) -> String:
	return "%d:%d:%d" % [bid.bid_type, bid.suit, bid.rank]


func _strongest_bids_by_trump_choice(bids: Array) -> Array:
	var by_choice: Dictionary = {}
	for bid: TrumpBidding.BidDeclaration in bids:
		var key := str(bid.suit)
		if not by_choice.has(key):
			by_choice[key] = bid
			continue
		var existing: TrumpBidding.BidDeclaration = by_choice[key]
		if bid.bid_type > existing.bid_type:
			by_choice[key] = bid

	var result: Array = []
	for suit: int in [Card.Suit.SPADE, Card.Suit.HEART, Card.Suit.CLUB, Card.Suit.DIAMOND]:
		var key := str(suit)
		if by_choice.has(key):
			result.append(by_choice[key])
	if by_choice.has("-1"):
		result.append(by_choice["-1"])
	return result


func _bid_for_suit(bids: Array, suit: int) -> TrumpBidding.BidDeclaration:
	for bid: TrumpBidding.BidDeclaration in bids:
		if bid.suit == suit:
			return bid
	return null


func _base_suit_button_color(suit: int) -> Color:
	# Glyph (font) color for an available choice — true card colors on a light face.
	match suit:
		Card.Suit.HEART, Card.Suit.DIAMOND:
			return Color(0.82, 0.12, 0.12)
		Card.Suit.SPADE, Card.Suit.CLUB:
			return Color(0.10, 0.10, 0.12)
		_:
			return Color(0.6, 0.45, 0.05)


func _first_deal_choices_match(bids: Array) -> bool:
	if not waiting_for_input or bids.size() != visible_first_bid_choices.size():
		return false
	var current_keys := {}
	for bid: TrumpBidding.BidDeclaration in visible_first_bid_choices:
		current_keys[_bid_choice_key(bid)] = true
	for bid: TrumpBidding.BidDeclaration in bids:
		if not current_keys.has(_bid_choice_key(bid)):
			return false
	return true


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
	if first_game_dealing:
		hand_display.show_hand(visible_deal_hands[human_seat], false)
	else:
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
	_log("你亮主: %s" % TrumpBidding.bid_label(decl))
	_hide_bid_panel()
	if first_game_dealing:
		pending_first_bid = decl
		_set_message("你已抢主: %s" % TrumpBidding.bid_label(decl))
	elif is_first_game:
		session_controller.submit_bid_or_pass(human_seat, decl)
		_sync_host_from_controller()
		_finish_bidding_round()
	else:
		session_controller.submit_bid_or_pass(human_seat, decl)
		_sync_host_from_controller()
		_finish_bidding()


func _on_bid_skip() -> void:
	if not waiting_for_input:
		return
	waiting_for_input = false
	_log("你选择不亮")
	_hide_bid_panel()
	if first_game_dealing:
		_set_message("继续发牌")
	elif is_first_game:
		session_controller.submit_bid_or_pass(human_seat, null, "player_choice")
		_finish_bidding_round()
	else:
		session_controller.submit_bid_or_pass(human_seat, null, "player_choice")
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
		human_bottom_received_snapshot = _last_cards(merged, rule_config.bottom_size)
		human_buried_bottom_snapshot = []
		_update_aux_buttons()
		_set_message("配底阶段（%s）— 选 %d 张扣底" % [label, rule_config.bottom_size])
		hand_display.show_hand(merged, true)
		_show_bury_actions()


func _show_bury_actions() -> void:
	_clear_actions()
	var confirm_btn := _make_hand_action_button("扣底 0/%d" % rule_config.bottom_size, Color(0.2, 0.7, 0.3))
	confirm_btn.name = "ConfirmBury"
	confirm_btn.pressed.connect(_on_bury_confirm)
	action_bar.add_child(confirm_btn)


func _on_hand_selection_changed(count: int) -> void:
	if current_phase == "burying":
		var confirm := action_bar.get_node_or_null("ConfirmBury")
		if confirm is Button:
			(confirm as Button).text = "扣底 %d/%d" % [count, rule_config.bottom_size]


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
		human_buried_bottom_snapshot = (result.get("buried", []) as Array).duplicate()
		_update_aux_buttons()
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
	_hide_preview_panel()
	_clear_turn_highlights()
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
	_set_turn_highlight(seat)
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
	var play_btn := _make_hand_action_button("出牌", Color(0.2, 0.7, 0.3))
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
	_preview_human_hand_after_play(cards)
	_update_seat_counts()
	_log("  你出: %s" % _cards_str(cards))

	_clear_actions()
	if submit.get("trick_complete", false):
		get_tree().create_timer(0.6).timeout.connect(_resolve_trick)
		return
	_process_next_player()


func _resolve_trick() -> void:
	var result := session_controller.last_trick_result
	_capture_last_trick_plays(result)
	var winner_name := SEAT_NAMES[result["winner"]]
	var side := "攻方" if game_round.is_attack(result["winner"]) else "庄家方"
	_log("  → %s 赢墩 (%s) | 本墩: %d 分 | 攻方总分: %d" % [
		winner_name, side, result["score"], result["attack_score"]])

	_highlight_trick_winner(result["winner"])
	_set_message("%s 赢墩 | +%d 分 | 攻方 %d 分" % [
		winner_name, result["score"], result["attack_score"]])

	_update_info()
	_update_aux_buttons()

	if result["is_last"]:
		get_tree().create_timer(1.4).timeout.connect(_finish_round)
	else:
		get_tree().create_timer(1.4).timeout.connect(func() -> void:
			_clear_turn_highlights()
			_start_next_trick()
		)


func _finish_round() -> void:
	_clear_turn_highlights()
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

	_populate_settlement_panel(settlement, finish, summary_text, team_name)
	_add_settlement_action_buttons(settlement.game_over)
	_set_message("")

	_auto_save_log()

	if settlement.game_over:
		_log("\n[color=gold]游戏结束！%s 获胜！[/color]" % team_name)
		_save_log()
	else:
		_log("  南北队: %s 级 | 东西队: %s 级" % [
			Card.rank_symbol(team_ranks[0]), Card.rank_symbol(team_ranks[1])])


# ============================================================
# Display helpers
# ============================================================

func _refresh_hand_display(interactive: bool) -> void:
	var hand := game_round.get_hand(human_seat)
	hand_display.show_hand(hand, interactive)


func _preview_human_hand_after_play(played_cards: Array) -> void:
	var hand := game_round.get_hand(human_seat)
	hand_display.show_hand(_cards_without(hand, played_cards), false)


func _cards_without(source_cards: Array, removed_cards: Array) -> Array:
	var result := source_cards.duplicate()
	for removed: Card in removed_cards:
		for i: int in range(result.size()):
			var card: Card = result[i]
			if card.equals(removed):
				result.remove_at(i)
				break
	return result


func _show_played_cards(seat: int, cards: Array) -> void:
	table_cards[seat] = cards
	_render_cards_in_slot(seat, cards)


func _render_table_cards(cards_by_seat: Dictionary) -> void:
	for seat: int in center_card_slots:
		_render_cards_in_slot(seat, cards_by_seat.get(seat, []))


func _restore_current_table_cards() -> void:
	_render_table_cards(table_cards)
	_update_info()


func _render_cards_in_slot(seat: int, cards: Array) -> void:
	var slot: Control = center_card_slots[seat]
	# Clear old
	for child: Node in slot.get_children():
		child.queue_free()

	var offset := 0.0
	for card: Card in cards:
		var cv = _CardViewClass.new()
		cv.custom_minimum_size = Vector2(PLAYED_CARD_W, PLAYED_CARD_H)
		cv.size = Vector2(PLAYED_CARD_W, PLAYED_CARD_H)
		cv.setup(card, true, _is_trump(card))
		cv.disabled = true
		cv.position = Vector2(offset, 0)
		slot.add_child(cv)
		offset += PLAYED_CARD_STEP


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
		var trump_color := Color(1.0, 0.92, 0.45)
		if game_round:
			match game_round.trump_suit:
				Card.Suit.HEART, Card.Suit.DIAMOND:
					trump_color = Color(1.0, 0.5, 0.45)
				Card.Suit.SPADE, Card.Suit.CLUB:
					trump_color = Color(0.7, 0.88, 1.0)
		info_labels["trump"].add_theme_color_override("font_color", trump_color)
	if info_labels.has("dealer"):
		info_labels["dealer"].text = "庄家: %s" % dealer_name
	if info_labels.has("score"):
		info_labels["score"].text = "攻方: %d 分" % score
	if info_labels.has("round"):
		info_labels["round"].text = "第 %d 局" % round_num
	_update_aux_buttons()


func _update_seat_counts() -> void:
	if game_round == null:
		return
	var declarer := -1
	if game_round.bid_declaration != null:
		declarer = game_round.bid_declaration.seat_id
	for seat: int in [1, 2, 3]:
		var count := game_round.get_hand_size(seat)
		if seat_count_labels.has(seat):
			seat_count_labels[seat].text = "%d 张" % count
		# Hide the card-back stack once a seat has emptied its hand.
		if seat_card_backs.has(seat):
			seat_card_backs[seat].visible = count > 0
		var is_dealer := seat == game_round.dealer_seat
		if seat_name_labels.has(seat):
			seat_name_labels[seat].text = SEAT_NAMES[seat]
			var name_color := Color(1, 0.85, 0.3) if is_dealer else Color(0.85, 0.85, 0.85)
			seat_name_labels[seat].add_theme_color_override("font_color", name_color)
		if seat_dealer_badges.has(seat):
			seat_dealer_badges[seat].visible = is_dealer
		if seat_bid_badges.has(seat):
			seat_bid_badges[seat].visible = declarer == seat


func _set_message(msg: String) -> void:
	message_label.text = msg


func _clear_turn_highlights() -> void:
	active_turn_seat = -1
	for seat: int in seat_panels:
		_apply_seat_panel_style(seat, "normal")
	_apply_hand_area_style("normal")
	for seat: int in center_card_slots:
		center_card_slots[seat].modulate = Color.WHITE


func _set_turn_highlight(seat: int) -> void:
	_clear_turn_highlights()
	active_turn_seat = seat
	if seat == human_seat:
		_apply_hand_area_style("active")
	elif seat_panels.has(seat):
		_apply_seat_panel_style(seat, "active")


func _highlight_trick_winner(winner_seat: int) -> void:
	_clear_turn_highlights()
	if winner_seat == human_seat:
		_apply_hand_area_style("winner")
	elif seat_panels.has(winner_seat):
		_apply_seat_panel_style(winner_seat, "winner")
	if center_card_slots.has(winner_seat):
		center_card_slots[winner_seat].modulate = Color(1.15, 1.1, 0.82)


func _apply_seat_panel_style(seat: int, mode: String) -> void:
	if not seat_panels.has(seat) or not seat_panel_base_styles.has(seat):
		return
	var panel: PanelContainer = seat_panels[seat]
	var style: StyleBoxFlat = (seat_panel_base_styles[seat] as StyleBoxFlat).duplicate()
	match mode:
		"active":
			style.border_color = SEAT_ACTIVE_BORDER
			style.set_border_width_all(2)
			style.bg_color = Color(0.10, 0.32, 0.18, 0.88)
		"winner":
			style.border_color = SEAT_WINNER_BORDER
			style.set_border_width_all(3)
			style.bg_color = Color(0.16, 0.40, 0.24, 0.94)
	panel.add_theme_stylebox_override("panel", style)


func _apply_hand_area_style(mode: String) -> void:
	if hand_area_panel == null or hand_area_base_style == null:
		return
	var style: StyleBoxFlat = hand_area_base_style.duplicate()
	match mode:
		"active":
			style.border_color = SEAT_ACTIVE_BORDER
			style.set_border_width_all(2)
			style.bg_color = Color(0.08, 0.22, 0.14, 0.35)
		"winner":
			style.border_color = SEAT_WINNER_BORDER
			style.set_border_width_all(3)
			style.bg_color = Color(0.12, 0.30, 0.18, 0.45)
	hand_area_panel.add_theme_stylebox_override("panel", style)


func _hide_settlement_panel() -> void:
	if settlement_panel:
		settlement_panel.visible = false
	if settlement_content:
		for child: Node in settlement_content.get_children():
			child.queue_free()


func _populate_settlement_panel(
		settlement: EffectiveSettlement,
		finish: Dictionary,
		summary_text: String,
		team_name: String,
	) -> void:
	_hide_settlement_panel()

	var title := Label.new()
	title.text = "本局结算"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	settlement_content.add_child(title)

	_add_settlement_line("出牌阶段攻方得分: %d" % settlement.attack_base_score)
	if settlement.bottom_multiplier > 0:
		_add_settlement_line("底牌: %d × %d 倍 = %d" % [
			settlement.bottom_score, settlement.bottom_multiplier, settlement.bottom_bonus])
	else:
		_add_settlement_line("底牌不计分（庄方收墩）")
	_add_settlement_line("最终得分: %d" % settlement.final_score, true)
	_add_settlement_line(summary_text, true)

	if settlement.game_over:
		_add_settlement_line("%s 获胜！" % team_name, true)
	else:
		_add_settlement_line("南北队 %s 级 | 东西队 %s 级" % [
			Card.rank_symbol(team_ranks[0]), Card.rank_symbol(team_ranks[1])])

	settlement_panel.visible = true


func _add_settlement_action_buttons(game_over: bool) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	settlement_content.add_child(spacer)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	settlement_content.add_child(row)

	if game_over:
		var restart_btn := _make_styled_button("再来一局", Color(0.3, 0.7, 0.9))
		restart_btn.pressed.connect(func() -> void:
			_hide_settlement_panel()
			_clear_actions()
			_start_new_game()
		)
		row.add_child(restart_btn)
	else:
		var next_btn := _make_styled_button("下一局", Color(0.3, 0.7, 0.9))
		next_btn.pressed.connect(func() -> void:
			_hide_settlement_panel()
			_clear_actions()
			_start_round()
		)
		row.add_child(next_btn)

		var save_btn := _make_styled_button("保存日志", Color(0.5, 0.7, 0.5))
		save_btn.pressed.connect(_save_log)
		row.add_child(save_btn)


func _add_settlement_line(text: String, emphasized: bool = false) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 22 if emphasized else 17)
	lbl.add_theme_color_override(
		"font_color",
		Color(1.0, 0.92, 0.55) if emphasized else Color(0.88, 0.88, 0.82)
	)
	settlement_content.add_child(lbl)


func _update_aux_buttons() -> void:
	var can_preview := _can_show_preview_overlay()
	var has_human_bottom := not human_bottom_received_snapshot.is_empty() \
		or not human_buried_bottom_snapshot.is_empty()
	if previous_trick_btn:
		previous_trick_btn.disabled = last_trick_plays_snapshot.is_empty() or not can_preview
	if bottom_btn:
		bottom_btn.visible = can_preview and has_human_bottom


func _can_show_preview_overlay() -> bool:
	if session_controller == null:
		return false
	return session_controller.current_phase in ["playing", "round_end", "game_over"]


func _capture_last_trick_plays(result: Dictionary) -> void:
	last_trick_plays_snapshot = {}
	for play: Dictionary in result.get("plays", []):
		var seat: int = play.get("seat", -1)
		if seat >= 0:
			last_trick_plays_snapshot[seat] = (play.get("cards", []) as Array).duplicate()


func _show_previous_trick_preview() -> void:
	if last_trick_plays_snapshot.is_empty() or not _can_show_preview_overlay():
		return
	_show_previous_trick_overlay()


func _show_bottom_preview() -> void:
	if not _can_show_preview_overlay():
		return
	if human_bottom_received_snapshot.is_empty() and human_buried_bottom_snapshot.is_empty():
		return
	var rows: Array[Dictionary] = []
	if not human_bottom_received_snapshot.is_empty():
		rows.append({
			"label": "拿到底牌",
			"cards": human_bottom_received_snapshot,
		})
	if not human_buried_bottom_snapshot.is_empty():
		rows.append({
			"label": "已扣底",
			"cards": human_buried_bottom_snapshot,
		})
	_show_preview_overlay("底牌", rows)


func _show_preview_overlay(title: String, rows: Array[Dictionary]) -> void:
	if preview_panel == null or preview_content == null:
		return
	preview_token += 1
	var token := preview_token
	_clear_preview_content()

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.65))
	preview_content.add_child(title_label)

	for row: Dictionary in rows:
		var cards: Array = row.get("cards", []) as Array
		_add_preview_row(str(row.get("label", "")), cards)

	preview_panel.visible = true
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if token == preview_token:
			_hide_preview_panel()
	)


func _show_previous_trick_overlay() -> void:
	if preview_panel == null or preview_content == null:
		return
	preview_token += 1
	var token := preview_token
	_clear_preview_content()

	var title_label := Label.new()
	title_label.text = "上一轮出牌"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.65))
	preview_content.add_child(title_label)

	var north := HBoxContainer.new()
	north.alignment = BoxContainer.ALIGNMENT_CENTER
	north.mouse_filter = MOUSE_FILTER_IGNORE
	preview_content.add_child(north)
	_add_preview_hand(north, "上", last_trick_plays_snapshot.get(2, []) as Array)

	var middle := HBoxContainer.new()
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.mouse_filter = MOUSE_FILTER_IGNORE
	middle.add_theme_constant_override("separation", 48)
	preview_content.add_child(middle)
	_add_preview_hand(middle, "左", last_trick_plays_snapshot.get(3, []) as Array)
	_add_preview_hand(middle, "右", last_trick_plays_snapshot.get(1, []) as Array)

	var south := HBoxContainer.new()
	south.alignment = BoxContainer.ALIGNMENT_CENTER
	south.mouse_filter = MOUSE_FILTER_IGNORE
	preview_content.add_child(south)
	_add_preview_hand(south, "下", last_trick_plays_snapshot.get(0, []) as Array)

	preview_panel.visible = true
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if token == preview_token:
			_hide_preview_panel()
	)


func _add_preview_row(label_text: String, cards: Array) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	preview_content.add_child(row)

	var label := Label.new()
	label.text = "%s:" % label_text
	label.custom_minimum_size = Vector2(76, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.90, 0.90, 0.82))
	row.add_child(label)

	if cards.is_empty():
		var empty := Label.new()
		empty.text = "无"
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		row.add_child(empty)
		return

	for card: Card in cards:
		var cv = _CardViewClass.new()
		cv.setup(card, true, _is_trump(card))
		cv.disabled = true
		cv.mouse_filter = MOUSE_FILTER_IGNORE
		cv.custom_minimum_size = Vector2(42, 60)
		cv.size = Vector2(42, 60)
		row.add_child(cv)


func _add_preview_hand(parent: Control, label_text: String, cards: Array) -> void:
	var hand := HBoxContainer.new()
	hand.mouse_filter = MOUSE_FILTER_IGNORE
	hand.add_theme_constant_override("separation", 4)
	parent.add_child(hand)

	var label := Label.new()
	label.text = "%s:" % label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.90, 0.90, 0.82))
	hand.add_child(label)

	if cards.is_empty():
		var empty := Label.new()
		empty.text = "无"
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		hand.add_child(empty)
		return

	for card: Card in cards:
		var cv = _CardViewClass.new()
		cv.setup(card, true, _is_trump(card))
		cv.disabled = true
		cv.mouse_filter = MOUSE_FILTER_IGNORE
		cv.custom_minimum_size = Vector2(36, 52)
		cv.size = Vector2(36, 52)
		hand.add_child(cv)


func _hide_preview_panel() -> void:
	preview_token += 1
	if preview_panel:
		preview_panel.visible = false
	_clear_preview_content()


func _clear_preview_content() -> void:
	if preview_content == null:
		return
	for child: Node in preview_content.get_children():
		preview_content.remove_child(child)
		child.queue_free()


func _last_cards(cards: Array, count: int) -> Array:
	var result: Array = []
	var start: int = max(0, cards.size() - count)
	for i: int in range(start, cards.size()):
		result.append(cards[i])
	return result


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
	if log_panel and debug_ui_enabled:
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
	btn.add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.72))

	var style_disabled := style_normal.duplicate()
	style_disabled.bg_color = Color(0.18, 0.18, 0.2, 0.85)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	return btn


func _hand_area_min_height() -> float:
	return HandDisplay.HAND_TOP_PAD + HandDisplay.HAND_BOTTOM_PAD \
		+ HandDisplay.CARD_H_MAX * (1.0 + HandDisplay.SELECT_RISE_RATIO)


func _make_hand_action_button(text: String, color: Color) -> Button:
	var btn := _make_styled_button(text, color)
	btn.custom_minimum_size = Vector2(120, 40)
	btn.add_theme_font_size_override("font_size", 16)
	return btn


func _clear_first_deal_bid_buttons() -> void:
	if first_deal_bid_buttons == null:
		return
	for child: Node in first_deal_bid_buttons.get_children():
		child.queue_free()


func _hide_first_deal_bid_panel() -> void:
	if first_deal_bid_panel:
		first_deal_bid_panel.visible = false
	_clear_first_deal_bid_buttons()
	waiting_for_input = false
	visible_first_bid_choices = []


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
