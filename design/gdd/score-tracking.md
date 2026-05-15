# C5 分值追踪

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 3（对局自足）

## Overview

**分值追踪系统**负责对局过程中实时统计攻方得分。每墩结束后，根据赢墩方和墩中的分牌（5/10/K），将分值累加到攻方或庄家方的得分池中。本系统为 C6（升级结算）提供最终得分数据。

## Player Fantasy

分值追踪是玩家时刻关注的信息——"攻方现在拿了多少分？离升级还差多少？"实时可见的分值驱动着每一手出牌的策略决策。本系统服务的情感是**局势感知**——玩家需要随时知道自己是领先还是落后。

## Detailed Design

### Core Rules

#### 1. 分牌定义（来自 F1）

| Rank | 分值 |
|------|------|
| 5 | 5 分 |
| 10 | 10 分 |
| K | 10 分 |
| 其余 | 0 分 |

#### 2. 得分累加

```
record_trick(trick_cards: Card[4][], winner_seat: int, teams: TeamConfig) → void
```

每墩结束后：
1. 统计该墩所有牌中的分牌总分值
2. 判断赢墩者属于攻方还是庄家方
3. 将分值累加到对应方的得分池

**攻守方定义**：
- 庄家方：庄家 + 庄家搭档（对面座位）
- 攻方：另外两人

#### 3. 实时查询

```
get_attack_score() → int       // 攻方当前得分
get_defend_score() → int       // 庄家方当前得分（通常不显示，可由总分推算）
get_remaining_score() → int    // 剩余未获取分值
```

总分恒等式：`attack_score + defend_score + remaining_score = total_score`

| deck_count | total_score |
|------------|-------------|
| 1 | 100 |
| 2 | 200 |

### States and Transitions

C5 无复杂状态。每局开始时清零，每墩结束时累加，对局结束时输出最终得分。

### Interactions with Other Systems

| 方向 | 系统 | 接口 |
|------|------|------|
| ← F1 牌型定义 | 分牌判定（Card.rank） |
| ← C7 对局状态机 | 每墩结束时通知 C5 记录 |
| ← C2 出牌合法性校验 | 赢墩者座位（determine_winner 的结果） |
| → C6 升级结算 | 对局结束时提供 attack_score |
| → P1/P5 UI | 实时分值供 UI 展示 |
| → FT1 AI 基础决策 | AI 参考当前得分决定策略（保守/激进） |
| → FT2 AI 手牌推理 | AI 参考已出分牌推断剩余分牌分布 |

## Formulas

**每墩分值计算**：

```
trick_score(cards: Card[]) → int
  return sum(card_score(c) for c in cards)

card_score(card: Card) → int
  if card.rank == 5:  return 5
  if card.rank == 10: return 10
  if card.rank == K:  return 10
  return 0
```

**每副牌分值分布**：

| Rank | 每花色张数 | 每张分值 | 每副小计 |
|------|-----------|---------|---------|
| 5 | 4 | 5 | 20 |
| 10 | 4 | 10 | 40 |
| K | 4 | 10 | 40 |
| **合计** | — | — | **100** |

2 副牌总分 = 200。

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **一墩中无分牌** | 记录 0 分，正常 |
| E2 | **攻方得分 = 0（全局无分）** | 极端但合法，C6 据此判定升级结果 |
| E3 | **底牌中的分牌** | 底牌分值不在 C5 追踪范围内（C5 只追踪出牌阶段的墩），底牌分值由 C6 在结算时单独处理 |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← F1 牌型定义 | 硬依赖 | Card.rank 分值判定 |
| ← C7 对局状态机 | 硬依赖 | 墩结束事件 |
| → C6 升级结算 | 被硬依赖 | 最终 attack_score |
| → FT1/FT2 AI | 被软依赖 | 实时得分查询 |

## Tuning Knobs

C5 无独立可调参数。分牌定义和分值由 F1 硬编码（5→5分，10→10分，K→10分），不可配置。

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | 一墩包含 ♠5 ♥10 ♦K ♣3 | trick_score = 5+10+10+0 = 25 |
| AC2 | 一墩全无分牌 | trick_score = 0 |
| AC3 | 攻方赢得 AC1 的墩 | attack_score += 25 |
| AC4 | 庄家方赢得 AC1 的墩 | attack_score 不变 |
| AC5 | 对局结束，attack_score + defend_score + bottom_score = total_score | 恒等式成立 |
| AC6 | 2 副牌全局所有分牌出完 | 出牌阶段总分 ≤ 200（差值在底牌中） |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | 已记录每墩 `trick_score` / `trick_points`、`attack_score_before/after` 与 `attack_gain`，供日志复盘使用；运行时计分仍只维护累计攻方分 | 已解决 | — |
