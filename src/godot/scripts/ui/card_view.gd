## CardView — programmatic card rendering component.
## Draws a playing card using Godot's _draw() API.
## Supports: face-up, face-down (back), selected state, hover highlight, trump glow.
class_name CardView
extends Control

signal clicked(card_view: Control)

const CARD_WIDTH: float = 70.0
const CARD_HEIGHT: float = 100.0
const CARD_TEX_RATIO: float = 140.0 / 190.0  # Kenney card art aspect
const CORNER_RADIUS: float = 6.0
const BORDER_WIDTH: float = 1.5
const SUIT_FONT_SIZE: int = 28
const RANK_FONT_SIZE: int = 22
const JOKER_FONT_SIZE: int = 14

## Art assets (Kenney Boardgame Pack, CC0). When a matching texture exists it is
## used; otherwise CardView falls back to procedural drawing (e.g. jokers).
const CARD_ASSET_DIR := "res://assets/cards/"
const CARD_BACK_FILE := "cardBack_red2.png"

## Cached textures shared across all CardView instances (null = confirmed missing).
static var _tex_cache: Dictionary = {}

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
	texture_filter = TEXTURE_FILTER_LINEAR


## Fit a texture into `size` without stretching (keeps Kenney 140:190 aspect).
func _draw_texture_fit(tex: Texture2D) -> void:
	var tex_size := tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var tex_ratio := tex_size.x / tex_size.y
	var draw_size := size
	if size.x / size.y > tex_ratio:
		draw_size.x = size.y * tex_ratio
	else:
		draw_size.y = size.x / tex_ratio
	var origin := (size - draw_size) * 0.5
	draw_texture_rect(tex, Rect2(origin, draw_size), false)


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


## Render scale relative to the base card size, so a larger `size` scales
## fonts and offsets proportionally instead of leaving tiny text top-left.
func _scale_factor() -> float:
	return maxf(size.y / CARD_HEIGHT, 0.1)


static func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[path] = tex
	return tex


func _face_texture() -> Texture2D:
	if card == null or card.is_joker:
		return null  # jokers fall back to procedural drawing
	var suit_token := ""
	match card.suit:
		Card.Suit.SPADE:   suit_token = "Spades"
		Card.Suit.HEART:   suit_token = "Hearts"
		Card.Suit.DIAMOND: suit_token = "Diamonds"
		Card.Suit.CLUB:    suit_token = "Clubs"
		_:                 return null
	var rank_token := Card.rank_symbol(card.rank)
	return _load_tex(CARD_ASSET_DIR + "card%s%s.png" % [suit_token, rank_token])


func _back_texture() -> Texture2D:
	return _load_tex(CARD_ASSET_DIR + CARD_BACK_FILE)


func _draw() -> void:
	if face_up and card != null:
		var face_tex := _face_texture()
		if face_tex != null:
			_draw_texture_fit(face_tex)
		else:
			_draw_face()
	else:
		var back_tex := _back_texture()
		if back_tex != null:
			_draw_texture_fit(back_tex)
		else:
			_draw_back()

	if selected:
		_draw_selection_border()
	if is_trump and face_up and card != null:
		_draw_trump_badge()


func _draw_face() -> void:
	var s := _scale_factor()
	var rect := Rect2(Vector2.ZERO, size)
	# White card background
	draw_rect(rect, Color(0.98, 0.96, 0.93), true)
	# Border
	draw_rect(rect, Color(0.5, 0.5, 0.5, 0.6), false, BORDER_WIDTH * s)

	if card.is_joker:
		_draw_joker_face()
	else:
		_draw_normal_face()


func _draw_normal_face() -> void:
	var s := _scale_factor()
	var col := _get_suit_color()
	var suit_str := Card.suit_symbol(card.suit)
	var rank_str := Card.rank_symbol(card.rank)

	# Top-left rank
	draw_string(
		ThemeDB.fallback_font,
		Vector2(6 * s, 20 * s),
		rank_str,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		int(RANK_FONT_SIZE * s),
		col,
	)
	# Top-left suit (below rank)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(6 * s, 42 * s),
		suit_str,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		int((SUIT_FONT_SIZE - 6) * s),
		col,
	)

	# Center suit (large)
	var center_w := 40.0 * s
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x * 0.5 - center_w * 0.5, size.y * 0.5 + 10 * s),
		suit_str,
		HORIZONTAL_ALIGNMENT_CENTER,
		center_w,
		int((SUIT_FONT_SIZE + 4) * s),
		col,
	)

	# Bottom-right rank+suit
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 24 * s, size.y - 8 * s),
		rank_str,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		int(RANK_FONT_SIZE * s),
		col,
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 24 * s, size.y - 28 * s),
		suit_str,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		int((SUIT_FONT_SIZE - 6) * s),
		col,
	)


func _draw_joker_face() -> void:
	var s := _scale_factor()
	var is_big := card.joker_type == Card.JokerType.BIG
	var col := Color(0.85, 0.1, 0.1) if is_big else Color(0.15, 0.15, 0.15)
	var label := "大" if is_big else "小"
	var star := "★" if is_big else "☆"
	var center_w := 40.0 * s

	# Top label
	draw_string(
		ThemeDB.fallback_font,
		Vector2(6 * s, 22 * s),
		star,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		int(RANK_FONT_SIZE * s),
		col,
	)

	# Center "王"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x * 0.5 - center_w * 0.5, size.y * 0.38),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		center_w,
		int((SUIT_FONT_SIZE + 2) * s),
		col,
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x * 0.5 - center_w * 0.5, size.y * 0.62),
		"王",
		HORIZONTAL_ALIGNMENT_CENTER,
		center_w,
		int((SUIT_FONT_SIZE + 2) * s),
		col,
	)

	# Bottom
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 24 * s, size.y - 10 * s),
		star,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		int(RANK_FONT_SIZE * s),
		col,
	)


func _draw_back() -> void:
	var s := _scale_factor()
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.15, 0.25, 0.55), true)
	draw_rect(rect, Color(0.1, 0.15, 0.35), false, BORDER_WIDTH * s)

	# Diamond pattern
	var inner := Rect2(Vector2(5 * s, 5 * s), size - Vector2(10 * s, 10 * s))
	draw_rect(inner, Color(0.2, 0.35, 0.65), false, maxf(1.0, s))
	var inner2 := Rect2(Vector2(8 * s, 8 * s), size - Vector2(16 * s, 16 * s))
	draw_rect(inner2, Color(0.25, 0.4, 0.7), false, maxf(0.5, 0.5 * s))


func _draw_selection_border() -> void:
	var s := _scale_factor()
	var rect := Rect2(Vector2(-1, -1), size + Vector2(2, 2))
	draw_rect(rect, Color(0.2, 0.9, 0.3, 0.9), false, 3.0 * s)


## Green "主" badge on the bottom-left corner of trump cards, matching the
## common 升级 client convention so trump cards stand out at a glance.
func _draw_trump_badge() -> void:
	var s := _scale_factor()
	var r := 11.0 * s
	var pad := 4.0 * s
	var center := Vector2(r + pad, size.y - r - pad)
	draw_circle(center, r, Color(0.13, 0.60, 0.26))
	draw_circle(center, r, Color(1, 1, 1, 0.9), false, maxf(1.0, 1.4 * s))
	var fs := int(15 * s)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center.x - r, center.y + fs * 0.36),
		"主",
		HORIZONTAL_ALIGNMENT_CENTER,
		r * 2.0,
		fs,
		Color(1, 1, 1),
	)


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
