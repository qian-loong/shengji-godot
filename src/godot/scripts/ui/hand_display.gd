## HandDisplay — manages the player's hand card layout and selection.
## Cards are laid out in a horizontal row with adaptive overlap when space is tight.
## Selected cards rise up. Supports multi-select for plays, bury, etc.
class_name HandDisplay
extends Control

signal cards_selected(cards: Array[Card])
signal selection_changed(count: int)

const CARD_W: float = 70.0
const CARD_H: float = 100.0
const CARD_RATIO: float = 140.0 / 190.0  # matches Kenney card art aspect
const CARD_H_MIN: float = 90.0
const CARD_H_MAX: float = 172.0
const HAND_TOP_PAD: float = 6.0
const HAND_BOTTOM_PAD: float = 16.0  # keep card bottom (rank + 主 badge) off the screen edge
const SELECT_RISE_RATIO: float = 0.18
const MIN_OVERLAP: float = 0.35
const MAX_OVERLAP: float = 0.72

## Card size is computed from the control height so the hand scales with the
## available space (high-res phones no longer show tiny cards).
var _card_w: float = CARD_W
var _card_h: float = CARD_H
var _rise_px: float = 0.0

var card_views: Array = []
var _cards: Array = []
var _selected_indices: Array[int] = []
var _interactive: bool = false
var _trump_suit: int = -1
var _current_rank: int = Card.Rank.TWO
var _joker_always_trump: bool = true
var _card_view_class: GDScript = null

var _sort_callback: Callable = Callable()


func _ready() -> void:
	clip_contents = true
	_card_view_class = load("res://scripts/ui/card_view.gd")


func set_trump_context(trump_suit: int, current_rank: int, joker_always_trump: bool = true) -> void:
	_trump_suit = trump_suit
	_current_rank = current_rank
	_joker_always_trump = joker_always_trump


func set_sort_callback(cb: Callable) -> void:
	_sort_callback = cb


func show_hand(cards: Array, interactive: bool = true) -> void:
	_clear()
	_interactive = interactive
	_cards = cards.duplicate()
	_selected_indices = []

	if _sort_callback.is_valid():
		_cards = _sort_callback.call(_cards)

	for i: int in range(_cards.size()):
		var card: Card = _cards[i]
		var cv = _card_view_class.new()
		cv.setup(card, true, _is_trump(card))
		cv.disabled = not interactive
		if interactive:
			cv.clicked.connect(_on_card_clicked)
		card_views.append(cv)
		add_child(cv)

	_layout_cards()


func get_selected_cards() -> Array[Card]:
	var result: Array[Card] = []
	for idx: int in _selected_indices:
		if idx >= 0 and idx < _cards.size():
			result.append(_cards[idx])
	return result


func get_selected_count() -> int:
	return _selected_indices.size()


func clear_selection() -> void:
	_selected_indices = []
	for cv in card_views:
		cv.set_selected(false)
	_layout_cards()
	selection_changed.emit(0)


func set_interactive(value: bool) -> void:
	_interactive = value
	for cv in card_views:
		cv.disabled = not value


func _clear() -> void:
	for cv in card_views:
		cv.queue_free()
	card_views = []
	_cards = []
	_selected_indices = []


func _on_card_clicked(cv) -> void:
	if not _interactive:
		return

	var idx := card_views.find(cv)
	if idx < 0:
		return

	if idx in _selected_indices:
		_selected_indices.erase(idx)
		cv.set_selected(false)
	else:
		_selected_indices.append(idx)
		cv.set_selected(true)

	_layout_cards()
	selection_changed.emit(_selected_indices.size())


func _compute_card_size() -> void:
	var rise_budget := CARD_H_MAX * SELECT_RISE_RATIO
	var h := clampf(
		size.y - HAND_TOP_PAD - HAND_BOTTOM_PAD - rise_budget,
		CARD_H_MIN,
		CARD_H_MAX
	)
	_card_h = h
	_card_w = h * CARD_RATIO
	_rise_px = _card_h * SELECT_RISE_RATIO


func _layout_cards() -> void:
	if card_views.is_empty():
		return

	_compute_card_size()
	var rise := _rise_px
	var card_top_min := HAND_TOP_PAD
	var card_bottom := size.y - HAND_BOTTOM_PAD
	var count := card_views.size()
	var available_width := size.x

	var spacing := _card_w
	if count > 1:
		var max_total := available_width - _card_w
		var spacing_max := _card_w * (1.0 - MIN_OVERLAP)
		var spacing_min := _card_w * (1.0 - MAX_OVERLAP)
		spacing = minf(spacing_max, max_total / (count - 1))
		spacing = maxf(spacing_min, spacing)

	var total_width := _card_w + spacing * (count - 1) if count > 1 else _card_w
	var start_x := (available_width - total_width) * 0.5

	for i: int in range(count):
		var cv = card_views[i]
		cv.custom_minimum_size = Vector2(_card_w, _card_h)
		cv.size = Vector2(_card_w, _card_h)
		var x := start_x + spacing * i
		var y := card_bottom - _card_h
		if i in _selected_indices:
			y -= rise
		y = maxf(y, card_top_min)
		cv.position = Vector2(x, y)
		cv.z_index = i


func _is_trump(card: Card) -> bool:
	return TrumpJudge.is_trump(card, _trump_suit, _current_rank, _joker_always_trump)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_cards()
