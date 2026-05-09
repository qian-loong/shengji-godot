## Score tracking — real-time score accumulation during play
## Implements: C5 Score Tracking GDD (design/gdd/score-tracking.md)
class_name ScoreTracker
extends RefCounted


var _attack_score: int = 0
var _defend_score: int = 0
var _total_score: int


func _init(total: int = 200) -> void:
	_total_score = total


func reset(total: int = 200) -> void:
	_attack_score = 0
	_defend_score = 0
	_total_score = total


## Record a trick result
## trick_cards: all cards played in this trick (flat array)
## winner_is_attack: true if the winning team is the attack side
func record_trick(trick_cards: Array, winner_is_attack: bool) -> int:
	var score := _calc_trick_score(trick_cards)
	if winner_is_attack:
		_attack_score += score
	else:
		_defend_score += score
	return score


func get_attack_score() -> int:
	return _attack_score


func get_defend_score() -> int:
	return _defend_score


func get_remaining_score() -> int:
	return _total_score - _attack_score - _defend_score


static func _calc_trick_score(cards: Array) -> int:
	var total := 0
	for c: Card in cards:
		total += c.get_point_value()
	return total


## Calculate score of a set of cards (used for bottom cards)
static func calc_cards_score(cards: Array) -> int:
	return _calc_trick_score(cards)
