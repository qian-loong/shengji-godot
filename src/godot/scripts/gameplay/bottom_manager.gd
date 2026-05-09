## Bottom card management — reveal and bury
## Implements: C4 Bottom Cards GDD (design/gdd/bottom-cards.md)
class_name BottomManager
extends RefCounted


## Merge bottom cards into dealer's hand
static func reveal_bottom(dealer_hand: Array, bottom: Array) -> Array:
	var merged := dealer_hand.duplicate()
	merged.append_array(bottom)
	return merged


## Validate and execute bury selection
## Returns: { "ok": bool, "error": String, "new_hand": Array, "buried": Array }
static func bury_bottom(hand: Array, selected_indices: Array[int], bottom_size: int) -> Dictionary:
	if selected_indices.size() != bottom_size:
		return { "ok": false, "error": "Must select exactly %d cards, got %d" % [bottom_size, selected_indices.size()] }

	# Validate indices
	for idx: int in selected_indices:
		if idx < 0 or idx >= hand.size():
			return { "ok": false, "error": "Invalid card index: %d" % idx }

	# Check for duplicate indices
	var unique := {}
	for idx: int in selected_indices:
		if unique.has(idx):
			return { "ok": false, "error": "Duplicate index: %d" % idx }
		unique[idx] = true

	# Extract buried cards and remaining hand
	var buried: Array = []
	var new_hand: Array = []
	for i: int in range(hand.size()):
		if i in selected_indices:
			buried.append(hand[i])
		else:
			new_hand.append(hand[i])

	return { "ok": true, "error": "", "new_hand": new_hand, "buried": buried }
