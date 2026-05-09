# FT1 AI 基础决策

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 1（配合可感知）— MVP 阶段先保证规则正确，为后续配合意图打基础

## Overview

**AI 基础决策系统**为 3 个 AI 玩家提供出牌决策能力。MVP 阶段的目标是"规则正确 + 基础合理"——AI 不会犯规，不会出明显愚蠢的牌，但不要求高水平博弈或搭档配合。本系统通过 C2 的 `get_legal_plays()` 获取合法出牌列表，然后用评分策略选择最优出牌。

## Player Fantasy

AI 是玩家的对手和搭档。MVP 阶段玩家的期望底线是"AI 不犯规、不出太离谱的牌"。如果 AI 出了非法牌或明显的低级失误（如有主牌不出、明知必输还浪费大牌），玩家会立刻丧失游戏兴趣。本系统服务的情感是**合理感**——"AI 至少像个懂规则的人"。

## Detailed Design

### Core Rules

#### 1. AI 决策入口

```
ai_decide(seat_id: int, hand: Card[], game_state: GameState, rule_config: RuleConfig) → Card[]
```

AI 在以下时机被调用：
- **亮主阶段**：是否亮主、亮什么花色
- **配底阶段**（AI 为庄家时）：选哪些牌扣底
- **出牌阶段**：首出或跟牌选择

#### 2. 亮主决策

```
ai_bid_decision(hand: Card[], rule_config: RuleConfig) → BidDeclaration?
```

MVP 策略：
- 统计手中每个花色的级牌和王牌数量
- 如果有合法声明条件（满足 bid_requires_joker 等配置）：
  - 选择级牌/主牌最多的花色声明
  - 有 PairJoker 时优先声明公主
- 如果不满足声明条件 → 不声明（返回 null）

#### 3. 配底决策（AI 为庄家时）

```
ai_bury_decision(hand: Card[], bottom_size: int, trump_suit: Suit?, rule_config: RuleConfig) → Card[]
```

MVP 策略：
- 优先扣短门副牌（张数最少的副花色）
- 避免扣主牌（除非手牌主牌过多）
- 避免扣分牌（5/10/K），除非该副花色只有分牌无保护
- 目标：清掉 1-2 门副牌，增加主牌控制力

#### 4. 出牌决策

**首出决策**：

```
ai_lead_decision(hand: Card[], game_state: GameState, rule_config: RuleConfig) → Card[]
```

MVP 策略（按优先级）：
1. 如果主牌强势（主牌数量 > 平均值）→ 出主牌清主
2. 如果某副花色有绝对控制（最大牌）→ 出该花色拿分
3. 如果攻方（己方为攻方时）需要拿分 → 出含分牌的花色
4. 默认：出最短门副牌的小牌（减少被杀风险）

**跟牌决策**：

```
ai_follow_decision(hand: Card[], lead: LeadPlay, game_state: GameState, rule_config: RuleConfig) → Card[]
```

MVP 策略：
1. 获取 `get_legal_plays()` 的合法跟牌列表
2. 评估每种合法出牌的分值：
   - **搭档赢墩概率高** → 出分牌（喂分）
   - **自己能赢墩** → 出最小的能赢的牌（节约大牌）
   - **无法赢墩** → 出最小的牌（垫牌）
   - **无首出花色，考虑杀牌** → 评估杀牌收益（墩中分值 vs 消耗的主牌价值）
3. 选择评分最高的出牌

#### 5. 出牌评分函数

```
score_play(play: Card[], context: PlayContext) → float
```

评分因素（MVP 权重）：

| 因素 | 权重 | 说明 |
|------|------|------|
| 赢墩概率 | 0.3 | 基于已出牌推断，当前出牌能否赢墩 |
| 墩中分值 | 0.3 | 该墩已有多少分（值得争夺吗） |
| 牌力消耗 | 0.2 | 出大牌的代价（大牌留着后面用更好？） |
| 分牌保护 | 0.2 | 避免暴露未受保护的分牌 |

权重为 MVP 初始值，后续由 FT4（AI 难度梯度）调整。

### States and Transitions

AI 决策系统无内部持续状态。每次调用时读取当前游戏状态（game_state），执行决策，返回结果。

AI 可维护的**推断状态**（跨墩保持，局内有效）：
- 已出牌记录（公开信息）
- 各花色剩余张数估算

### Interactions with Other Systems

| 方向 | 系统 | 接口 |
|------|------|------|
| ← C2 出牌合法性校验 | `get_legal_plays()` 获取合法出牌列表 |
| ← C1 主副牌判定 | `get_suit_domain()`、`get_sort_value()` 评估牌力 |
| ← C5 分值追踪 | 当前得分，决定策略倾向（保守/激进） |
| ← C7 对局状态机 | AI 出牌轮次时被 C7 调用 |
| ← F3 规则配置系统 | 读取规则配置 |
| → C3 亮主/抢主/反主 | 返回亮主决策 |
| → C4 抠底/配底 | 返回配底决策 |
| → C7 对局状态机 | 返回出牌决策 |

## Formulas

### 赢墩概率估算（MVP 简化版）

```
estimate_win_probability(play: Card[], lead: LeadPlay?, game_state: GameState) → float
```

MVP 策略（简化，不做深度推理）：
- 首出时：该花色域中自己出的牌是否为当前已知最大 → 高概率赢
- 跟牌时：自己的牌是否大于已出的所有牌 → 确定赢/不赢
- 杀牌时：主牌结构是否匹配且大于已出的主牌杀 → 确定赢/不赢

### 牌力评估

```
hand_strength(hand: Card[], trump_suit: Suit?, current_rank: Rank) → float
```

简单统计：
- 主牌数量 / 总手牌数
- 大牌数量（A、K、Q 以及级牌、王）
- 各副花色的控制度（最大牌是否在手）

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **合法出牌只有 1 种** | 直接出，无需评分 |
| E2 | **AI 为庄家需要配底** | 调用 ai_bury_decision，策略见 Core Rules 第 3 条 |
| E3 | **AI 需要决定是否反主** | MVP 阶段简化：AI 手中有更强声明条件时，50% 概率反主 |
| E4 | **甩牌决策** | MVP 阶段 AI 不主动甩牌（逻辑复杂），只出 Single/Pair/Tractor |
| E5 | **1 副牌下无对子** | AI 决策自然适应——get_legal_plays 不会返回对子选项 |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← C2 出牌合法性校验 | 硬依赖 | get_legal_plays() |
| ← C1 主副牌判定 | 硬依赖 | 牌力评估 |
| ← C5 分值追踪 | 软依赖 | 得分参考 |
| ← C7 对局状态机 | 硬依赖 | 调用触发 |
| ← F3 规则配置系统 | 硬依赖 | 规则参数 |

## Tuning Knobs

| 参数 | 类型 | 默认值 | 影响 |
|------|------|--------|------|
| 评分权重（赢墩/分值/消耗/保护） | float[4] | [0.3, 0.3, 0.2, 0.2] | 调整 AI 出牌风格（激进/保守） |
| 反主概率 | float | 0.5 | MVP 阶段 AI 反主的随机概率 |
| 甩牌启用 | bool | false | MVP 阶段关闭 AI 甩牌 |

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | AI 出牌 100 墩 | 所有出牌均通过 C2 合法性校验（零犯规） |
| AC2 | AI 跟牌时有该花色域的牌 | 不会出其他花色域的牌 |
| AC3 | AI 跟对子时手中有该花色域对子 | 必须出对子（遵守 strict_follow_structure） |
| AC4 | AI 为庄家配底 | 选择的牌数 == bottom_size |
| AC5 | AI 亮主，bid_requires_joker=true 且无王 | 不声明 |
| AC6 | AI 首出，主牌数量占优 | 倾向出主牌清主 |
| AC7 | AI 跟牌，搭档已出最大牌（大概率赢墩） | 倾向出分牌喂分 |
| AC8 | AI 跟牌，无法赢墩 | 出最小的牌垫牌 |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | 评分函数的权重需要通过大量对局测试调优 | FT4 / 测试阶段 | 高 |
| Q2 | AI 甩牌逻辑何时启用——需要甩牌合法性校验的额外信息（其他人手牌），AI 本身有全部信息 | FT2 阶段 | 中 |
| Q3 | "搭档赢墩概率高时喂分"的判断标准需要量化——多高算"高"？ | FT3 阶段 | 中 |
