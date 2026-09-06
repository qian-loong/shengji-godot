## CardMemory — 局内公开记牌状态（FT1 SMART / ADR-0005）
##
## GameRound 持有的**一份共享公开记录**：本局所有已公开打出的牌，逐墩累加。
## 已出牌是公开信息（所有玩家看到同一份），故非 per-AI 私有拷贝。SMART 决策
## （ai-basic.md §4b B2「铁最大判定」）据此按 identity 做副本计数。
##
## 坐标系说明（ADR-0005 实现注记，2026-09-06 用户拍板）：
## ADR-0005 §2 字面写 played_count[domain_key][rank_index]（域+域内 rank 序）。
## 实现改用 **identity 坐标**（[suit][rank] + 独立王计数），理由：
##   1. 副本计数本质按物理 identity（suit+rank / joker_type）——对子/拖拉机同型
##      判定要求 identity 相同（见 card_pattern.gd Bug A 修复），非按 sort_value 聚合。
##   2. 主牌域是异构混合体（副牌级牌×3花色 + 主花色普通 + 主花色级牌 + 大小王），
##      用"域内 rank 序"编码这堆异构 identity 既不直观又易错。
##   3. identity 坐标与「域」解耦，CardMemory 不碰主牌域内部拓扑——正合 ADR-0005 +
##      GDD §记牌推断「CardMemory 只消费 C1 全序、不自定义主牌域拓扑」原则。
## 满足 ADR 全部硬约束（O(1) 查询/更新、定长数组、无 Dictionary 遍历、按物理副本计数）；
## 「域」的复杂性下沉到步骤 E 的查询逻辑（用现成 get_suit_domain/get_sort_value 动态遍历）。
class_name CardMemory
extends RefCounted


const _SUIT_COUNT: int = 4                          # ♠♥♦♣
const _RANK_COUNT: int = 13                         # RANK_SEQUENCE 长度（2..A）
const _JOKER_COUNT: int = 2                         # SMALL / BIG


## 每副牌数（1 或 2）。每个 identity 的物理副本上界 = deck_count（普通牌）
## 或 deck_count（王，每副各一张小王一张大王）。
var deck_count: int = 2

## 普通牌副本计数：played_count[suit][rank_index] = 该 (suit, rank) 已公开打出的副本数。
## suit ∈ [0,3]（Card.Suit 枚举值）；rank_index = RANK_SEQUENCE.find(rank) ∈ [0,12]。
## 定长二维 int 数组，预分配，O(1) 查询/更新，无 Dictionary。
var played_count: Array = []                        # Array[Array[int]]，[4][13]

## 王副本计数：joker_played[joker_type] = 该王已公开打出的副本数。joker_type ∈ {0,1}。
var joker_played: Array[int] = [0, 0]

## 当前墩的座位/顺序记录（供「本墩谁在赢 / 后续座位有无对手」）。
## 每墩结算后由 record_trick 累加，begin_trick 时由 begin_trick 清空。
## 元素: { seat_id:int, cards:Array, pattern, play_order:int }
## 仅当前墩需要精细顺序；跨墩累积只喂 played_count / joker_played。
var current_trick: Array = []                        # Array[Dictionary]


func _init(p_deck_count: int = 2) -> void:
	deck_count = p_deck_count
	_reset_played_count()


## 预分配并清零 played_count（[4][13] 定长）。
func _reset_played_count() -> void:
	played_count = []
	for _s: int in range(_SUIT_COUNT):
		var row: Array[int] = []
		for _r: int in range(_RANK_COUNT):
			row.append(0)
		played_count.append(row)
	joker_played = [0, 0]


# ============================================================
# 更新：每墩结算后由 GameRound 调用（ADR-0005 §更新时机）
# ============================================================

## 记录一墩已公开的所有出牌（每墩结算完成时、begin_trick 之前调用）。
## plays: Array[Dictionary]，每条至少含 { seat_id:int, cards:Array }。
## 逐张按 identity 累加进 played_count / joker_played。
func record_trick(plays: Array) -> void:
	for entry: Dictionary in plays:
		var cards: Array = entry.get("cards", [])
		for c: Card in cards:
			_tally_card(c)


## 累加单张牌到副本计数（按 identity）。
func _tally_card(card: Card) -> void:
	if card.is_joker:
		joker_played[card.joker_type] += 1
	else:
		var ri := Card.RANK_SEQUENCE.find(card.rank)
		if ri >= 0:
			played_count[card.suit][ri] += 1


# ============================================================
# 当前墩座位/顺序（供 SMART 跟牌分支① 判定）
# ============================================================

## 开新墩：清空当前墩记录。由 GameRound/SessionController 在墩开始时调用。
func begin_trick() -> void:
	current_trick = []


## 记录当前墩的一次出牌（每家提交后调用，尚未结算）。
## entry 至少含 { seat_id:int, cards:Array, pattern, play_order:int }。
func record_play(entry: Dictionary) -> void:
	current_trick.append(entry)


# ============================================================
# 查询：AI 只读（ADR-0005 §Key Interfaces）
# ============================================================

## 某普通牌 identity (suit, rank) 未出、且不在己方已知的副本数。
## own_known = 自己手牌中该 (suit,rank) 张数 + private_known_cards 中该项张数。
## 返回值 = 物理副本上界(deck_count) − 已公开打出 − 己方已知，clamp 到 [0, ∞)。
## 铁最大判定（GDD §4b B2）："不存在更大 rank 其 remaining ≥ 2" 遍历时消费本函数。
func remaining_copies(suit: int, rank: int, own_known: int) -> int:
	var ri := Card.RANK_SEQUENCE.find(rank)
	if ri < 0:
		return 0
	var played: int = played_count[suit][ri]
	var remaining := deck_count - played - own_known
	return maxi(remaining, 0)


## 某王 identity 未出、且不在己方已知的副本数。
## own_known = 自己手牌 + private_known_cards 中该 joker_type 张数。
## 每副牌各一张小王一张大王 → 上界 = deck_count。
func remaining_joker_copies(joker_type: int, own_known: int) -> int:
	var remaining := deck_count - joker_played[joker_type] - own_known
	return maxi(remaining, 0)


## 累计某普通牌 identity 已公开打出的副本数（调试 / 派生查询用）。
func played_copies(suit: int, rank: int) -> int:
	var ri := Card.RANK_SEQUENCE.find(rank)
	if ri < 0:
		return 0
	var played: int = played_count[suit][ri]
	return played
