## Upgrade settlement — end-of-round scoring and rank progression
## Implements: C6 Upgrade Settlement GDD (design/gdd/upgrade-settlement.md)
class_name UpgradeSettlement
extends RefCounted


## Settlement result
class SettlementResult:
	var attack_base_score: int       # Score from play phase
	var bottom_score: int            # Bottom card points
	var bottom_multiplier: int       # Multiplier from last trick type
	var bottom_bonus: int            # bottom_score * bottom_multiplier
	var final_score: int             # Total attack score
	var upgrading_side: int          # 0=dealer, 1=attack
	var upgrade_levels: int          # How many levels to upgrade
	var new_rank: int                # New rank after upgrade
	var game_over: bool              # Whether the game ends
	var dealer_dethroned: bool       # Whether dealer was dethroned
	var new_dealer: int              # New dealer seat (-1 if dealer not changed)


## Calculate settlement
## current_rank: the rank being played this round (dealer's team rank)
## attack_rank: the attack team's own rank (for independent rank upgrade; -1 = same as current_rank)
static func calculate(
	attack_score: int,
	bottom_cards: Array,
	dealer_seat: int,
	last_trick_winner_is_attack: bool,
	last_trick_pattern: CardPattern.PatternResult,
	current_rank: int,
	rule_config: RuleConfig,
	attack_rank: int = -1,
) -> SettlementResult:
	var result := SettlementResult.new()
	result.attack_base_score = attack_score

	# Bottom score calculation
	if last_trick_winner_is_attack:
		result.bottom_score = ScoreTracker.calc_cards_score(bottom_cards)
		result.bottom_multiplier = CardPattern.get_bottom_multiplier(last_trick_pattern)
		result.bottom_bonus = result.bottom_score * result.bottom_multiplier
		result.final_score = attack_score + result.bottom_bonus
	else:
		result.bottom_score = 0
		result.bottom_multiplier = 0
		result.bottom_bonus = 0
		result.final_score = attack_score

	# Look up upgrade table
	var side: int = 0
	var levels: int = 0
	for row: Array in rule_config.upgrade_table:
		if result.final_score >= row[0]:
			side = row[1]
			levels = row[2]

	result.upgrading_side = side
	result.upgrade_levels = levels
	result.dealer_dethroned = (result.final_score >= rule_config.upgrade_threshold)

	# New dealer: if dethroned, next seat (counter-clockwise) becomes dealer
	if result.dealer_dethroned:
		result.new_dealer = (dealer_seat + 1) % 4
	else:
		result.new_dealer = -1  # Dealer unchanged

	# Calculate new rank (use upgrading side's own rank as base)
	if levels > 0:
		var base_rank: int
		if side == 0:
			base_rank = current_rank  # Dealer's team rank
		elif attack_rank >= 0:
			base_rank = attack_rank  # Attack team's own rank
		else:
			base_rank = current_rank  # Fallback: shared rank mode
		result.new_rank = apply_upgrade(base_rank, levels, rule_config)
	else:
		result.new_rank = current_rank

	# Game over check: if upgrading past A
	var rank_for_game_over: int
	if side == 0:
		rank_for_game_over = current_rank
	elif attack_rank >= 0:
		rank_for_game_over = attack_rank
	else:
		rank_for_game_over = current_rank
	result.game_over = (rank_for_game_over == Card.Rank.ACE and levels > 0)

	return result


## Apply upgrade with no-skip-rank constraint
static func apply_upgrade(current_rank: int, levels: int, rule_config: RuleConfig) -> int:
	var rank: int = current_rank
	for i: int in range(levels):
		var next := _next_rank(rank)
		if next < 0:
			# Past ACE = game over, return ACE
			return Card.Rank.ACE
		rank = next
		# Check no-skip constraint (only if we have more levels to go)
		if rule_config.no_skip_enabled and i < levels - 1:
			if rank in rule_config.no_skip_ranks:
				return rank  # Stop at non-skippable rank
	return rank


## Get next rank in sequence, returns -1 if past ACE
static func _next_rank(rank: int) -> int:
	var idx := Card.RANK_SEQUENCE.find(rank)
	if idx < 0 or idx >= Card.RANK_SEQUENCE.size() - 1:
		return -1
	return Card.RANK_SEQUENCE[idx + 1]
