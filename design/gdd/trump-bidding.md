# C3 亮主/抢主/反主

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 1（配合可感知）

## Overview

**亮主/抢主/反主系统**负责对局开始阶段确定主花色（trump_suit）和庄家（dealer）。它在发牌过程中异步接收玩家的亮主声明，根据声明强度决定主花色归属，并在配底阶段后处理反主挑战。

本系统根据 F3 的 `trump_mode` 配置运行不同模式：Bid（亮主）、Grab（抢主）、Counter（反主）、Fixed（固定主）、NoTrump（无主）。其中 Bid/Grab/Counter 是核心交互模式，Fixed 和 NoTrump 是简化模式。

本系统的输出是 `trump_suit`（主花色）和 `dealer`（庄家座位），这两个值确定后 C1 才能完整工作，C4 才能开始配底。

## Player Fantasy

亮主是对局中第一个策略决策点——亮什么花色、什么时机亮、是否抢主，都在传递信息。对搭档而言，亮主是一次隐含的沟通："我这个花色强"。本系统服务的情感是**博弈张力**——亮主时的紧张感和反主时的翻盘快感。

## Detailed Design

### Core Rules

#### 1. 亮主声明 (BidDeclaration)

```
BidDeclaration:
  seat_id: int           // 声明者座位
  bid_type: BidType      // 声明类型
  suit: Suit?            // 声明的主花色（公主时为 null）
  timestamp: int         // 发牌进度（第几张牌时声明）
```

**声明类型与强度——当 `bid_requires_joker = false` 时：**

| BidType | 强度 | 条件 | 结果 |
|---------|------|------|------|
| SingleRank | 1 | 手中有 1 张该花色级牌 | trump_suit = 该花色 |
| PairRank | 2 | 手中有 2 张该花色级牌 | trump_suit = 该花色 |
| PairJoker（公主） | 3 | 手中有 2 张同类型王 | trump_suit = null，joker_always_trump 强制 true |

**声明类型与强度——当 `bid_requires_joker = true` 时：**

| BidType | 强度 | 条件 | 结果 |
|---------|------|------|------|
| JokerRank | 1 | 手中有 1 张王 + 该花色级牌（王颜色匹配，如 `trump_joker_color_match = true`） | trump_suit = 该花色 |
| PairJoker（公主） | 2 | 手中有 2 张同类型王 | trump_suit = null，joker_always_trump 强制 true |

**说明**：
- 单王不可声明，无论任何配置
- `bid_requires_joker = true` 时，无王则无法定主（UI 中不提供选择机会）
- `bid_requires_joker = true` 时，PairRank（2 张级牌但无王）无效
- 公主局下 `joker_always_trump` 强制为 true（用王定主则王必须算主）
- `trump_joker_color_match` 仅在 JokerRank 声明时生效，约束王的颜色须与声明花色颜色一致

#### 2. 抢主规则（仅首局，级 = 2）

首局时所有玩家对等，通过抢主确定庄家和主花色：

1. 发牌过程中，任何玩家可随时发起亮主声明
2. **先到先得**：首个合法声明即生效，后续声明无论强度高低均不可覆盖
3. 发牌结束后，声明者成为庄家，声明花色为 trump_suit
4. **无人声明**：默认人类玩家为庄家，公主局（trump_suit = null），级 = 2

> **MVP 简化**：TUI 原型一次性发完所有牌（非逐张发牌），无法实现"边发边抢"的实时竞争。
> 当前实现为：发牌完成后先询问人类玩家是否亮主，然后按座位顺序轮询 AI。
> 待正式 UI 实现逐张发牌后，应改为 4 人实时抢定（先到先得）。

#### 3. 非首局定主流程

非首局中，庄家由轮转规则确定（见第 5 条），定主流程如下：

1. 按座位顺序从庄家开始轮询（`(current_dealer + i) % 4`）
2. 庄家有优先定主权：庄家能定则定，不能定则轮到下家
3. 轮到某人时：能定主 → 定主成功，该人成为庄家；不能定主 → 跳过，轮到下一人
4. 一轮 4 人均无法定主 → 庄家回到原始庄家，公主局
5. 定主完成后进入配底阶段（C4），配底完成后开启反主窗口

#### 4. 反主规则（非首局）

反主是独立于定主的机制，发生在庄家配底完成后：

1. **窗口**：庄家配底完成后开启，单机模式下无时间限制
2. **资格**：只有对手方（非庄家搭档）可以反主
3. **条件**：反主声明的强度必须**严格大于**庄家当前的定主声明强度
4. **次数**：每局只能反主一次
5. **级牌不变**：反主只改变 trump_suit，不改变 current_rank
6. **重新配底**：反主成功后，反家获得底牌重新配底（C4）
7. **先手不变**：配底完成后，先手权仍归原庄家
8. **公主不可反**：PairJoker 声明不可被反主

#### 5. 庄家轮转（跨局）

1. 首局：抢主决定庄家；无人抢主则默认人类玩家
2. 后续局：上局庄家未被下庄 → 继续坐庄
3. 庄家无法定主（如手中无级牌、无匹配王等）→ 下手敌方尝试定主当庄，依次轮转
4. 一轮 4 人均无法定主 → 庄家回到原始玩家，公主局（无主）

#### 6. 简化模式

| trump_mode | 行为 |
|------------|------|
| Fixed | 直接使用 `fixed_trump_suit`，不进行亮主流程。庄家按轮转规则确定 |
| NoTrump | `trump_suit = null`，不进行亮主流程。庄家按轮转规则确定 |

### States and Transitions

| 状态 | 说明 |
|------|------|
| **Idle** | 等待新局开始 |
| **Bidding** | 发牌进行中，接收亮主声明 |
| **Resolved** | 发牌结束，定主确定（或无人定主） |
| **CounterWindow** | 庄家配底完成后，等待反主（非首局） |
| **Countered** | 反主成功，反家重新配底中 |
| **Final** | 主花色和庄家最终确定，C3 职责完成 |

转换：
```
首局：  Idle → Bidding → Resolved → Final（无反主窗口）
非首局：Idle → Bidding → Resolved → CounterWindow → Final
                                   → CounterWindow → Countered → Final
无人定主：Idle → Bidding → Resolved(无人) → Final(公主局)
```

### Interactions with Other Systems

| 方向 | 系统 | 接口 |
|------|------|------|
| ← F2 牌组管理 | 接收发牌事件流（每发 1 张通知 C3） |
| ← F3 规则配置系统 | `trump_mode`、`trump_joker_color_match`、`bid_requires_joker`、`fixed_trump_suit`、`initial_dealer` |
| ← C1 主副牌判定 | 声明时校验牌是否为级牌/王牌 |
| → C1 主副牌判定 | 输出 `trump_suit`，C1 据此完成主副判定 |
| → C4 抠底/配底 | 庄家确定后通知 C4 开始配底；反主成功后再次通知 C4 |
| → C7 对局状态机 | 通知 C7 定主阶段完成 |
| → P4 亮主/抢主 UI | 提供声明事件供 UI 展示（亮牌动画、反主提示等） |

## Formulas

C3 无复杂计算公式。核心逻辑是声明强度的比较（枚举值比较，非数值计算）。

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **首局无人声明** | 默认人类玩家为庄家，公主局（trump_suit = null，joker_always_trump = true） |
| E2 | **非首局庄家无法定主** | 按轮转规则：下手敌方尝试，依次循环。4 人均无法定主则原庄家坐庄 + 公主局 |
| E3 | **反主声明强度等于庄家** | 不可反（必须严格大于） |
| E4 | **庄家搭档试图反主** | 拒绝（只有对手方可反） |
| E5 | **公主局被反主** | 不可能（PairJoker 是最高强度，无法被超越） |
| E6 | **反主成功后的底牌处理** | 原庄家配的底牌全部回收，底牌交给反家重新配底 |
| E7 | **bid_requires_joker=true 且无人有王** | 无人可定主，进入轮转逻辑，最终公主局 |
| E8 | **1 副牌下无 PairJoker** | 每种王仅 1 张，公主声明不可能出现。强度上限为 SingleRank/JokerRank |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← F2 牌组管理 | 硬依赖 | 发牌事件流 |
| ← F3 规则配置系统 | 硬依赖 | 定主相关配置 |
| ← C1 主副牌判定 | 软依赖 | 校验级牌/王牌身份（也可在 C3 内部直接判断） |
| → C1 主副牌判定 | 被硬依赖 | trump_suit 输出 |
| → C4 抠底/配底 | 被硬依赖 | 庄家确定 + 反主通知 |
| → C7 对局状态机 | 被硬依赖 | 定主完成信号 |
| → P4 亮主/抢主 UI | 被硬依赖 | 声明事件 |

## Tuning Knobs

| 参数 | 类型 | 默认值 | 影响 |
|------|------|--------|------|
| `bid_requires_joker` | bool | true | 是否需要王才能定主。false 时级牌单独可定。由 F3 承载 |

其余参数由 F3 承载（`trump_mode`、`trump_joker_color_match`、`fixed_trump_suit`）。

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | 首局，玩家A亮 ♠级牌（SingleRank），bid_requires_joker=false | 合法，A 为庄家，trump_suit=♠ |
| AC2 | 首局 AC1 之后，玩家B亮 ♥级牌对（PairRank） | 拒绝——首局先到先得，不可覆盖 |
| AC3 | 首局无人声明 | 人类玩家为庄家，公主局，joker_always_trump 强制 true |
| AC4 | bid_requires_joker=true，手中有王+级牌 | 可定主（JokerRank） |
| AC5 | bid_requires_joker=true，手中只有级牌无王 | 不可定主 |
| AC6 | bid_requires_joker=true，手中只有单王无级牌 | 不可定主 |
| AC7 | 非首局，庄家亮 SingleRank，对手方亮 PairRank 在反主窗口 | 反主成功，反家重新配底 |
| AC8 | 非首局，庄家亮 PairRank，对手方亮 SingleRank 在反主窗口 | 拒绝——强度不够 |
| AC9 | 非首局，庄家亮 PairJoker（公主） | 不可反主 |
| AC10 | 非首局，庄家搭档试图反主 | 拒绝——只有对手方可反 |
| AC11 | 反主成功后 | 反家获得底牌，先手仍归原庄家 |
| AC12 | trump_joker_color_match=true，红王声明 ♠（黑色花色） | 拒绝——颜色不匹配 |
| AC13 | trump_joker_color_match=true，红王声明 ♥（红色花色） | 合法 |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | `bid_requires_joker` 已补充到 F3 规则配置系统的参数表中 | 已解决 | — |
| Q2 | 非首局发牌阶段，非庄家玩家是否也可以亮主（抢庄）？还是只有庄家可以？ | 待确认 | 高 |
