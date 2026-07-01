## CardView — programmatic card rendering component.
## Draws a playing card using Godot's _draw() API.
## Supports: face-up, face-down (back), selected state, hover highlight, trump glow.
class_name CardView
extends Control

signal clicked(card_view: Control)

const CARD_WIDTH: float = 70.0
const CARD_HEIGHT: float = 100.0
const CORNER_RADIUS: float = 6.0
const BORDER_WIDTH: float = 1.5
const SUIT_FONT_SIZE: int = 28
const RANK_FONT_SIZE: int = 22
const JOKER_FONT_SIZE: int = 14

var card: Card = null
var face_up: bool = true
var selected: bool = false
var is_trump: bool = false
var hover: bool = false
var disabled: bool = false

var _base_position: Vector2 = Vector2.ZERO
var _select_offset: float = -16.0


func _init() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND


func setup(p_card: Card, p_face_up: bool = true, p_is_trump: bool = false) -> void:
	card = p_card
	face_up = p_face_up
	is_trump = p_is_trump
	selected = false
	queue_redraw()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func _draw() -> void:
	if face_up and card != null:
		_draw_face()
	else:
		_draw_back()

	if selected:
		_draw_selection_border()
	elif is_trump and face_up:
		_draw_trump_glow()


func _draw_face() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	# White card background
	draw_rect(rect, Color(0.98, 0.96, 0.93), true)
	# Border
	draw_rect(rect, Color(0.5, 0.5, 0.5, 0.6), false, BORDER_WIDTH)

	if card.is_joker:
		_draw_joker_face()
	else:
		_draw_normal_face()


func _draw_normal_face() -> void:
	var col := _get_suit_color()
	var suit_str := Card.suit_symbol(card.suit)
	var rank_str := Card.rank_symbol(card.rank)

	# Top-left rank
	draw_string(
		ThemeDB.fallback_font,
		Vector2(6, 20),
		rank_str,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		RANK_FONT_SIZE,
		col,
	)
	# Top-left suit (below rank)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(6, 42),
		suit_str,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		SUIT_FONT_SIZE - 6,
		col,
	)

	# Center suit (large)
	var center_x := size.x * 0.5
	var center_y := size.y * 0.5
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center_x - 14, center_y + 10),
		suit_str,
		HORIZONTAL_ALIGNMENT_CENTER,
		40,
		SUIT_FONT_SIZE + 4,
		col,
	)

	# Bottom-right rank+suit (rotated by drawing upside-down text)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 24, size.y - 8),
		rank_str,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		RANK_FONT_SIZE,
		col,
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 24, size.y - 28),
		suit_str,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		SUIT_FONT_SIZE - 6,
		col,
	)


func _draw_joker_face() -> void:
	var is_big := card.joker_type == Card.JokerType.BIG
	var col := Color(0.85, 0.1, 0.1) if is_big else Color(0.15, 0.15, 0.15)
	var label := "大" if is_big else "小"
	var star := "★" if is_big else "☆"

	# Top label
	draw_string(
		ThemeDB.fallback_font,
		Vector2(6, 22),
		star,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		RANK_FONT_SIZE,
		col,
	)

	# Center "王"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x * 0.5 - 14, size.y * 0.38),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		40,
		SUIT_FONT_SIZE + 2,
		col,
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x * 0.5 - 14, size.y * 0.62),
		"王",
		HORIZONTAL_ALIGNMENT_CENTER,
		40,
		SUIT_FONT_SIZE + 2,
		col,
	)

	# Bottom
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 24, size.y - 10),
		star,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		RANK_FONT_SIZE,
		col,
	)


func _draw_back() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.15, 0.25, 0.55), true)
	draw_rect(rect, Color(0.1, 0.15, 0.35), false, BORDER_WIDTH)

	# Diamond pattern
	var inner := Rect2(Vector2(5, 5), size - Vector2(10, 10))
	draw_rect(inner, Color(0.2, 0.35, 0.65), false, 1.0)
	var inner2 := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	draw_rect(inner2, Color(0.25, 0.4, 0.7), false, 0.5)


func _draw_selection_border() -> void:
	var rect := Rect2(Vector2(-1, -1), size + Vector2(2, 2))
	draw_rect(rect, Color(0.2, 0.9, 0.3, 0.9), false, 3.0)


func _draw_trump_glow() -> void:
	var rect := Rect2(Vector2(-1, -1), size + Vector2(2, 2))
	draw_rect(rect, Color(1.0, 0.85, 0.3, 0.4), false, 2.0)


func _get_suit_color() -> Color:
	if card == null:
		return Color.WHITE
	if card.is_joker:
		return Color(0.85, 0.1, 0.1) if card.joker_type == Card.JokerType.BIG else Color(0.15, 0.15, 0.15)
	match card.suit:
		Card.Suit.HEART, Card.Suit.DIAMOND:
			return Color(0.85, 0.1, 0.1)
		_:
			return Color(0.1, 0.1, 0.1)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clicked.emit(self)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER and not disabled:
		hover = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		hover = false
		queue_redraw()
