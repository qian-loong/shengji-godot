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

# Tracks which ranks each team has completed as dealer (必打级 enforcement).
# dealer_played_ranks[team_index] = Array of rank ints played as 庄家.
var dealer_played_ranks: Array = [[], []]


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
	dealer_played_ranks = [[], []]


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


## Record that a team played a round as dealer at a given rank.
## Must be called before apply_settlement so the constraint check has up-to-date data.
func record_dealer_round(dealer_seat: int, rank: int) -> void:
	var team := get_team_for_seat(dealer_seat)
	if rank not in dealer_played_ranks[team]:
		dealer_played_ranks[team].append(rank)


## 应用一次结算提案到会话状态，并返回"裁决后"的 EffectiveSettlement。
##
## 提案（SettlementResult）由 UpgradeSettlement.calculate() 生成，只知道当局。
## 本方法负责叠加跨局约束：
##   - 必打级：升级方从 no_skip_rank 起步，必须打过庄才允许跨越；否则拦回起点。
##   - game_over：拦截后 game_over 必须回落，否则会误报游戏结束。
## 返回的 EffectiveSettlement 里的 new_rank / game_over / new_dealer / upgrade_levels
## 与本方法执行后的 team_ranks / game_over / current_dealer 严格一致，
## 是 UI / 日志 / 自动对局入口的唯一可信来源。
func apply_settlement(
	settlement: UpgradeSettlement.SettlementResult,
	actual_dealer: int,
	rule_config: RuleConfig = null,
) -> EffectiveSettlement:
	var upgrading_team := get_upgrading_team(settlement, actual_dealer)
	var effective_new_rank := settlement.new_rank
	var upgrade_blocked := false

	if settlement.upgrade_levels > 0:
		if rule_config != null and rule_config.no_skip_enabled:
			effective_new_rank = _apply_no_skip_dealer_constraint(
				team_ranks[upgrading_team], settlement.new_rank,
				upgrading_team, rule_config)
			upgrade_blocked = (effective_new_rank == team_ranks[upgrading_team] \
				and settlement.new_rank != team_ranks[upgrading_team])
		team_ranks[upgrading_team] = effective_new_rank

	is_first_game = false
	game_over = settlement.game_over and not upgrade_blocked
	winning_team = upgrading_team if game_over else -1

	var effective_new_dealer: int
	if game_over:
		# 游戏结束时不切庄，保留实际庄家便于展示。
		current_dealer = actual_dealer
		effective_new_dealer = actual_dealer
	else:
		if settlement.new_dealer >= 0:
			current_dealer = settlement.new_dealer
		else:
			current_dealer = actual_dealer
		effective_new_dealer = current_dealer
		sync_rank_to_dealer(current_dealer)

	return EffectiveSettlement.from_proposal(
		settlement,
		upgrading_team,
		effective_new_rank,
		game_over,
		effective_new_dealer,
		upgrade_blocked,
	)


## Enforce 必打级: a team cannot advance FROM a no_skip rank unless they have
## played as dealer at that rank. Walk from current toward target, stopping at
## the first unplayed no_skip rank.
func _apply_no_skip_dealer_constraint(
	from_rank: int, to_rank: int, team: int, rule_config: RuleConfig,
) -> int:
	if from_rank == to_rank:
		return to_rank
	var rank := from_rank
	var seq := Card.RANK_SEQUENCE
	var idx := seq.find(rank)
	if idx < 0:
		return to_rank
	var to_idx := seq.find(to_rank)
	if to_idx < 0:
		return to_rank
	while idx < to_idx:
		if seq[idx] in rule_config.no_skip_ranks:
			if seq[idx] not in dealer_played_ranks[team]:
				return seq[idx]
		idx += 1
	return to_rank
