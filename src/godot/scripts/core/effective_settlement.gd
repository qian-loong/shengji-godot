## 会话层裁决产物 —— 由 SessionState.apply_settlement() 生成。
##
## 与 UpgradeSettlement.SettlementResult 的关系：
##   - SettlementResult 是"得分层的提案"，只依赖当局发牌/出牌/底分/加倍，
##     不知道跨局约束（必打级、game_over 修正等）。视作只读值对象。
##   - EffectiveSettlement 是"会话层的最终裁决"，在提案基础上叠加
##     跨局规则（必打级拦截、game_over 修正），字段与 state.team_ranks
##     等真实状态严格一致。
##
## UI / 日志 / 自动对局入口都应该消费 EffectiveSettlement 而非提案对象，
## 否则会出现"界面显示已升级到 J，但真实状态仍在 10"的错位。
class_name EffectiveSettlement
extends RefCounted


# ---- 提案原样透传（用于展示 / 复盘）----
var attack_base_score: int
var bottom_score: int
var bottom_multiplier: int
var bottom_bonus: int
var final_score: int
var upgrading_side: int          # 0 = dealer side, 1 = attack side
var dealer_dethroned: bool

# ---- 裁决后的最终值（与 state.team_ranks / state.game_over 严格一致）----
var upgrading_team: int          # 0 = seats {0,2}, 1 = seats {1,3}
var upgrade_levels: int          # 生效等级数（被拦截时为 0）
var new_rank: int                # 生效后的升级结果（被拦截时 == 旧 rank）
var new_dealer: int              # 生效后的下庄（game_over 时 == actual_dealer）
var game_over: bool              # 生效后的游戏结束标志

# ---- 裁决元信息 ----
var upgrade_blocked: bool        # 必打级是否拦截了本次升级
var proposal: UpgradeSettlement.SettlementResult  # 原始提案（只读引用）


static func from_proposal(
	proposal: UpgradeSettlement.SettlementResult,
	upgrading_team: int,
	effective_new_rank: int,
	effective_game_over: bool,
	effective_new_dealer: int,
	upgrade_blocked: bool,
) -> EffectiveSettlement:
	var e := EffectiveSettlement.new()
	e.attack_base_score = proposal.attack_base_score
	e.bottom_score = proposal.bottom_score
	e.bottom_multiplier = proposal.bottom_multiplier
	e.bottom_bonus = proposal.bottom_bonus
	e.final_score = proposal.final_score
	e.upgrading_side = proposal.upgrading_side
	e.dealer_dethroned = proposal.dealer_dethroned

	e.upgrading_team = upgrading_team
	# 拦截时 upgrade_levels 归零，与 new_rank == 旧 rank 保持语义一致。
	e.upgrade_levels = 0 if upgrade_blocked else proposal.upgrade_levels
	e.new_rank = effective_new_rank
	e.new_dealer = effective_new_dealer
	e.game_over = effective_game_over

	e.upgrade_blocked = upgrade_blocked
	e.proposal = proposal
	return e
