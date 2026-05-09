# C1 主副牌判定

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 2（规则即策略）

## Overview

**主副牌判定系统**是 F1 中定义的 `SuitDomain` 接口的运行时实现。给定一张 Card、当前规则配置（current_rank、trump_suit、joker_always_trump）和已确定的主花色，它输出这张牌属于 `TrumpDomain`（主牌域）还是 `SideDomain(suit)`（副牌域）。

本系统同时定义**主牌域内部的大小排序**——主花色普通牌、非主花级牌、主花级牌、小王、大王之间的完整排序关系。这个排序被 C2（出牌合法性）和 FT1（AI 决策）直接消费。

## Player Fantasy

玩家在每一手出牌时，需要瞬间判断"这张牌是主还是副、大还是小"。C1 的正确性直接决定手牌排列是否符合玩家直觉、出牌判定是否令人信服。本系统服务的情感仍然是**信任感**——主副判定出错一次，玩家就会觉得"这游戏规则不对"。

## Detailed Design

### Core Rules

#### 1. 主牌判定函数

```
get_suit_domain(card: Card, trump_suit: Suit?, current_rank: Rank, joker_always_trump: bool) → SuitDomain
```

判定逻辑（按优先级从高到低）：

| 优先级 | 条件 | 结果 |
|--------|------|------|
| 1 | card 是 JokerCard 且 `joker_always_trump = true` | TrumpDomain |
| 2 | card 是 JokerCard 且 `joker_always_trump = false` 且 `trump_suit = null`（无主局） | 不属于任何域（特殊处理，见 Edge Cases） |
| 3 | card 是 JokerCard 且 `joker_always_trump = false` 且 `trump_suit != null` | TrumpDomain |
| 4 | card.rank == current_rank（级牌，任意花色） | TrumpDomain |
| 5 | card.suit == trump_suit | TrumpDomain |
| 6 | 其余 | SideDomain(card.suit) |

**说明**：
- 级牌永远算主（F3 已确认"级牌不算主"暂不支持）
- `trump_suit = null` 代表无主局，此时只有级牌和王牌（如果 joker_always_trump）是主

#### 2. 主牌域内大小排序

当 `trump_suit` 已确定时（假设 trump_suit = ♠，current_rank = 4）：

```
主牌域排序（从小到大）：

♠2 < ♠3 < ♠5 < ♠6 < ... < ♠K < ♠A     ← 主花色普通牌（跳过级牌4）
< ♥4 = ♦4 = ♣4                           ← 非主花级牌（同级，先出者大）
< ♠4                                       ← 主花级牌
< SmallJoker                               ← 小王
< BigJoker                                 ← 大王
```

**排序层级表**：

| 层级 | 类别 | 排序规则 |
|------|------|---------|
| L1 | 主花色普通牌（非级牌） | 按跳级序列中的点数排序 |
| L2 | 非主花级牌 | 同层级内无固定大小，先出者大 |
| L3 | 主花级牌 | 唯一（2副牌时最多2张） |
| L4 | 小王 | — |
| L5 | 大王 | — |

#### 3. 副牌域内大小排序

副牌域内按跳级序列排：

```
副牌（如 ♥，级 = 4）：♥2 < ♥3 < ♥5 < ♥6 < ... < ♥K < ♥A
```

级牌（♥4）不在副牌域中，因为它被归入了主牌域。

#### 4. 无主局排序

`trump_suit = null` 时：
- 级牌（所有花色）→ TrumpDomain
- 王牌（如果 joker_always_trump）→ TrumpDomain
- 其余牌 → SideDomain(card.suit)

主牌域排序：
```
所有级牌同级（先出者大）< SmallJoker < BigJoker
```

### States and Transitions

C1 无内部状态。`get_suit_domain` 和排序函数都是纯函数——输入 Card + 规则参数，输出 SuitDomain 或排序值，无副作用。主花色（trump_suit）的确定由 C3 负责，C1 只消费它。

### Interactions with Other Systems

| 方向 | 系统 | 接口 |
|------|------|------|
| ← F1 牌型定义 | Card、Suit、Rank、Joker、SuitDomain 定义 |
| ← F3 规则配置系统 | `current_rank`、`trump_mode`、`joker_always_trump` |
| ← C3 亮主/抢主/反主 | `trump_suit`（已确定的主花色） |
| → C2 出牌合法性校验 | C2 调用 `get_suit_domain` 判断出牌花色域归属 |
| → FT1 AI 基础决策 | AI 调用排序函数评估手牌与出牌 |
| → P2 手牌渲染 | P2 调用排序函数决定手牌排列顺序（主牌在前/后） |

## Formulas

### 排序值计算函数

```
get_sort_value(card: Card, trump_suit: Suit?, current_rank: Rank) → int
```

| 层级 | 基础值范围 | 内部排序 |
|------|-----------|---------|
| 副牌 | 0–99 | 按花色分段（每花色 0–12），每段内按跳级序列排 |
| L1 主花色普通牌 | 100–112 | 按跳级序列排 |
| L2 非主花级牌 | 120 | 同值（先出者大由 C2 在比较时处理） |
| L3 主花级牌 | 130 | — |
| L4 小王 | 140 | — |
| L5 大王 | 150 | — |

具体数值为示意，实现时可用任意保序映射。

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **无主局 + joker_always_trump=false**：王牌无花色域 | 王牌不属于任何 SuitDomain，不能在任何花色域中出牌。具体行为：王牌只能在所有人都无该首出花色时作为垫牌打出，不能赢墩（由 C2 裁定） |
| E2 | **无主局 + joker_always_trump=true**：王牌属于主牌域 | 正常，王牌是主牌域中最大的牌 |
| E3 | **trump_suit 未确定（发牌阶段）** | C1 暂时无法输出完整判定。发牌阶段只有 current_rank 可用——级牌可判为"潜在主牌"，其余暂不判定。C3 确定 trump_suit 后 C1 才能完整工作 |
| E4 | **2 副牌下同层级牌的比较**：如两张 ♠4（主花级牌） | 同层级同花色同点数 = 先出者大 |
| E5 | **反主后 trump_suit 变化** | C1 重新计算所有牌的 SuitDomain。已出的牌不受影响（历史牌的判定以出牌时为准），手牌和底牌重新归属 |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← F1 牌型定义 | 硬依赖 | Card 数据结构、SuitDomain 接口 |
| ← F3 规则配置系统 | 硬依赖 | `current_rank`、`joker_always_trump` |
| ← C3 亮主/抢主/反主 | 硬依赖 | `trump_suit`（运行时确定） |
| → C2 出牌合法性校验 | 被硬依赖 | `get_suit_domain()`、排序函数 |
| → FT1 AI 基础决策 | 被硬依赖 | `get_sort_value()` |
| → P2 手牌渲染 | 被硬依赖 | `get_sort_value()` |

## Tuning Knobs

C1 无独立可调参数。所有影响主副判定的参数由 F3 承载（`current_rank`、`joker_always_trump`、`trump_mode`）。

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | trump_suit=♠, rank=4, 输入 ♠7 | TrumpDomain |
| AC2 | trump_suit=♠, rank=4, 输入 ♥7 | SideDomain(♥) |
| AC3 | trump_suit=♠, rank=4, 输入 ♥4 | TrumpDomain（级牌） |
| AC4 | trump_suit=♠, rank=4, 输入 ♠4 | TrumpDomain（主花级牌） |
| AC5 | trump_suit=♠, rank=4, 输入 BigJoker | TrumpDomain |
| AC6 | trump_suit=null, rank=4, joker_always_trump=true, 输入 BigJoker | TrumpDomain |
| AC7 | trump_suit=null, rank=4, joker_always_trump=false, 输入 BigJoker | 无域（特殊处理） |
| AC8 | 排序：♠3 < ♠5（级=4，跳过4） | get_sort_value(♠3) < get_sort_value(♠5) |
| AC9 | 排序：♠A < ♥4 < ♠4 < SmallJoker < BigJoker（trump=♠, rank=4） | 排序值递增 |
| AC10 | 排序：♥4 == ♦4 == ♣4（非主花级牌同层级） | get_sort_value 相同 |
| AC11 | 反主后 trump_suit 从 ♠ 变为 ♥ | 所有手牌的 SuitDomain 重新计算正确 |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | E1（无主+王不为主）的详细出牌规则需在 C2 设计时明确 | C2 | 高 |
| Q2 | 发牌阶段 trump_suit 未确定时，手牌排序如何显示（按花色分组？级牌标记为"待定主"？） | P2 | 中 |
