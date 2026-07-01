## HandDisplay — manages the player's hand card layout and selection.
## Cards are laid out in a horizontal row with adaptive overlap when space is tight.
## Selected cards rise up. Supports multi-select for plays, bury, etc.
class_name HandDisplay
extends Control

signal cards_selected(cards: Array[Card])
signal selection_changed(count: int)

const CARD_W: float = 70.0
const CARD_H: float = 100.0
const SELECT_RISE: float = 18.0
const MIN_OVERLAP: float = 0.35
const MAX_OVERLAP: float = 0.7
const CARD_SPACING_MIN: float = CARD_W * (1.0 - MAX_OVERLAP)
const CARD_SPACING_MAX: float = CARD_W * (1.0 - MIN_OVERLAP)

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
	clip_contents = false
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


func _layout_cards() -> void:
	if card_views.is_empty():
		return

	var count := card_views.size()
	var available_width := size.x

	var spacing := CARD_W
	if count > 1:
		var max_total := available_width - CARD_W
		spacing = minf(CARD_SPACING_MAX, max_total / (count - 1))
		spacing = maxf(CARD_SPACING_MIN, spacing)

	var total_width := CARD_W + spacing * (count - 1) if count > 1 else CARD_W
	var start_x := (available_width - total_width) * 0.5

	for i: int in range(count):
		var cv = card_views[i]
		var x := start_x + spacing * i
		var y := size.y - CARD_H
		if i in _selected_indices:
			y -= SELECT_RISE
		cv.position = Vector2(x, y)
		cv.z_index = i


func _is_trump(card: Card) -> bool:
	return TrumpJudge.is_trump(card, _trump_suit, _current_rank, _joker_always_trump)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_cards()
