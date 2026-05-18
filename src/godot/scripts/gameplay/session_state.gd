## Multi-round session state shared by automatic and TUI hosts.
class_name SessionState
extends RefCounted


var team_ranks: Array[int] = [Card.Rank.TWO, Card.Rank.TWO]
var current_dealer: int = 0
var current_rank: int = Card.Rank.TWO
var round_num: int = 0
var is_first_game: bool = true
var human_seat: int = 0
var game_over: bool = false
var winning_team: int = -1

# Per-round flag: whether the counter-bid window has already been opened/resolved
# (success OR all attackers passed). Reset every round.
var counter_attempted: bool = false


func reset(p_human_seat: int = 0) -> void:
	team_ranks = [Card.Rank.TWO, Card.Rank.TWO]
	current_dealer = 0
	current_rank = Card.Rank.TWO
	round_num = 0
	is_first_game = true
	human_seat = p_human_seat
	game_over = false
	winning_team = -1
	counter_attempted = false


func begin_round_for_current_dealer() -> int:
	round_num += 1
	counter_attempted = false
	return sync_rank_to_dealer(current_dealer)


func sync_rank_to_dealer(dealer: int) -> int:
	current_rank = get_team_rank_for_seat(dealer)
	return current_rank


func get_team_rank_for_seat(seat: int) -> int:
	return team_ranks[get_team_for_seat(seat)]


static func get_team_for_seat(seat: int) -> int:
	return seat % 2


static func get_attack_team(dealer: int) -> int:
	return (dealer + 1) % 2


static func get_upgrading_team(
	settlement: UpgradeSettlement.SettlementResult,
	dealer: int,
) -> int:
	if settlement.upgrading_side == 0:
		return get_team_for_seat(dealer)
	return get_attack_team(dealer)


func apply_settlement(
	settlement: UpgradeSettlement.SettlementResult,
	actual_dealer: int,
) -> Dictionary:
	var upgrading_team := get_upgrading_team(settlement, actual_dealer)
	if settlement.upgrade_levels > 0:
		team_ranks[upgrading_team] = settlement.new_rank

	is_first_game = false
	game_over = settlement.game_over
	winning_team = upgrading_team if game_over else -1

	if not game_over:
		if settlement.new_dealer >= 0:
			current_dealer = settlement.new_dealer
		else:
			current_dealer = actual_dealer
		sync_rank_to_dealer(current_dealer)

	return {
		"upgrading_team": upgrading_team,
		"game_over": game_over,
		"current_dealer": current_dealer,
		"current_rank": current_rank,
		"team_ranks": team_ranks.duplicate(),
		"is_first_game": is_first_game,
	}
