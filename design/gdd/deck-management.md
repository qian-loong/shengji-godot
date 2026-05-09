# F2 牌组管理

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 3（对局自足）

## Overview

**牌组管理系统**负责对局开始时的牌组生成、洗牌、发牌与留底。它使用 F1 定义的 Card 数据结构，根据 F3 提供的 `deck_count` 生成完整牌组，随机打乱后按 `hand_size` 和 `bottom_size` 分配给 4 名玩家和底牌区。

本系统是一次性流程——每局开始时执行一次，之后不再参与对局逻辑。

## Player Fantasy

牌组管理是不可见的后台流程。玩家感受到的是"牌发到手上了，随机且公平"。如果洗牌不够随机（出现明显的牌序规律），玩家会立刻察觉并丧失信任。本系统服务的情感与 F1 相同——**信任感**。

## Detailed Design

### Core Rules

#### 1. 牌组生成

```
generate_deck(deck_count: int) → Card[]
```

- `deck_count = 1`：生成 54 张（4花色 × 13点数 + 大小王各1），每张 `deck_id = 0`
- `deck_count = 2`：生成 108 张（第1副 deck_id=0，第2副 deck_id=1）
- 生成顺序固定（先 ♠2–♠A，再 ♥2–♥A，…最后大小王），洗牌在下一步

#### 2. 洗牌

```
shuffle(cards: Card[], seed?: int) → Card[]
```

- 使用 Fisher-Yates 算法（O(n)，均匀随机）
- 随机源：引擎提供的 PRNG，可设定 seed 用于测试与复盘

#### 3. 发牌（非阻塞，与 C3 异步交互）

```
deal(shuffled_cards: Card[], hand_size: int, bottom_size: int)
  → (hands: Card[4][], bottom: Card[])
```

流程：
1. 从牌堆顶部依次发牌，按座位轮流（0→1→2→3→0→…）
2. 每发 1 张，通知对应玩家（玩家可异步选择亮主，不阻塞发牌）
3. 每人发到 `hand_size` 张后停止
4. 剩余 `bottom_size` 张为底牌，暂不分配
5. 发牌结束后：
   - 有人亮主 → 庄家确定，底牌交给庄家进入配底阶段（C4）
   - 无人亮主 → 进入庄家轮转逻辑（F3 已定义规则）

#### 4. 底牌分配

底牌在发牌完成且庄家确定后，才交给庄家。庄家查看底牌后进入配底阶段（C4 负责）。

### States and Transitions

| 状态 | 说明 |
|------|------|
| **Idle** | 等待新局开始 |
| **Generating** | 生成牌组 + 洗牌 |
| **Dealing** | 逐张发牌中，C3 可异步接收亮主事件 |
| **Dealt** | 发牌完成，底牌待分配 |
| **Done** | 底牌已交给庄家，F2 职责完成 |

转换：`Idle → Generating → Dealing → Dealt → Done → Idle（下一局）`

### Interactions with Other Systems

| 方向 | 系统 | 接口 |
|------|------|------|
| ← F1 牌型定义 | F2 使用 `Card` 构造函数生成牌组 |
| ← F3 规则配置系统 | F2 读取 `deck_count`、`hand_size`、`bottom_size` |
| → C3 亮主/抢主/反主 | 发牌过程中每发 1 张牌，发出事件通知 C3；C3 异步返回亮主决策 |
| → C4 抠底/配底 | 发牌完成且庄家确定后，将底牌交给 C4 |
| → C7 对局状态机 | 发牌完成时通知 C7 状态流转 |

## Formulas

牌组张数：`total = deck_count × 54`

校验：`total == hand_size × 4 + bottom_size`

| deck_count | total | hand_size | bottom_size |
|------------|-------|-----------|-------------|
| 1 | 54 | 12 | 6 |
| 2 | 108 | 25 | 8 |

无其他计算公式。洗牌算法（Fisher-Yates）复杂度 O(n)，空间 O(1) 原地操作。

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **seed 相同时牌序相同** | 预期行为，用于测试与复盘回放 |
| E2 | **1 副牌发完后手牌无对子** | 正常现象，不做特殊处理（F1 E3 已说明） |
| E3 | **发牌过程中多人同时亮主** | F2 不处理冲突，由 C3 裁定优先级 |
| E4 | **发牌速度与 UI 动画不同步** | F2 只管数据分配，UI 动画节奏由 P2 控制。F2 可提供发牌事件序列供 UI 回放 |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← F1 牌型定义 | 硬依赖 | Card 构造函数 |
| ← F3 规则配置系统 | 硬依赖 | `deck_count`、`hand_size`、`bottom_size` |
| → C3 亮主/抢主/反主 | 事件通知 | 发牌事件流 |
| → C4 抠底/配底 | 数据传递 | 底牌 Card[] |
| → C7 对局状态机 | 事件通知 | 发牌完成信号 |

## Tuning Knobs

| 参数 | 类型 | 默认值 | 影响 |
|------|------|--------|------|
| `shuffle_seed` | int? | null（随机） | 设定后牌序可复现，用于测试和复盘。null 时使用系统随机 |
| `deal_speed` | float | 1.0 | 发牌动画速度倍率（F2 提供数据节奏，P2 消费用于动画） |

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | `generate_deck(1)` | 返回 54 张，无重复（忽略 deck_id） |
| AC2 | `generate_deck(2)` | 返回 108 张，每种牌恰好 2 张 |
| AC3 | `shuffle` 同 seed 两次 | 两次结果完全相同 |
| AC4 | `shuffle` 不同 seed | 两次结果不同（统计意义上） |
| AC5 | `deal` 2 副牌 | 4人各 25 张 + 底牌 8 张，总计 108 |
| AC6 | `deal` 1 副牌 | 4人各 12 张 + 底牌 6 张，总计 54 |
| AC7 | 发牌过程中有人亮主 | 发牌不中断，C3 收到亮主事件 |
| AC8 | 发牌结束无人亮主 | 进入庄家轮转逻辑 |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | 发牌事件的具体信号格式（每张牌一个事件？还是批量？）需结合 Godot 信号机制确定 | 实现阶段 | 中 |
