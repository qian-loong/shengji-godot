# C7 对局状态机

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 3（对局自足）

## Overview

**对局状态机**是整局游戏的流程控制器。它定义对局从开始到结束的所有阶段、状态转换条件、以及各阶段调用哪些子系统。本系统不包含任何游戏规则逻辑——所有规则判定由 C2/C3/C5/C6 等系统执行，C7 只负责"现在该做什么"和"下一步是什么"。

## Player Fantasy

玩家不会直接感知状态机的存在，但会感知到流程是否顺畅——发牌后自然进入亮主、亮主后自然进入配底、配底后自然进入出牌。如果流程卡顿或跳步，玩家会困惑。本系统服务的情感是**流畅感**——一切按预期自然发生。

## Detailed Design

### Core Rules

#### 1. 游戏级状态机（跨局）

```
GameState:
  Lobby → InRound → RoundEnd → [InRound | GameOver]
```

| 状态 | 说明 | 退出条件 |
|------|------|---------|
| **Lobby** | 游戏启动，规则配置（F3 Editing 状态） | 玩家确认开始 |
| **InRound** | 一局进行中（见局内状态机） | 局内状态机到达 Settlement |
| **RoundEnd** | 结算完成，展示结果 | 玩家确认继续 |
| **GameOver** | 某方打完 A 级获胜 | — |

`RoundEnd → InRound`：开始下一局，F3 更新 current_rank，庄家按 C6 结果确定。
`RoundEnd → GameOver`：C6 判定某方在 A 级胜出。

#### 2. 局内状态机（单局）

```
RoundPhase:
  Dealing → Bidding → BottomBury → CounterWindow → Playing → LastTrick → Settlement
```

| 阶段 | 负责系统 | 说明 | 退出条件 |
|------|---------|------|---------|
| **Dealing** | F2 | 生成牌组、洗牌、逐张发牌 | 发牌完成 |
| **Bidding** | C3 | 发牌过程中异步接收亮主声明，发牌结束后确定定主结果 | 定主确定（或无人定主） |
| **BottomBury** | C4 | 庄家查看底牌、配底 | 配底完成 |
| **CounterWindow** | C3 | 反主窗口（非首局） | 窗口关闭或反主成功 |
| **Playing** | C2, C5 | 出牌阶段，循环执行每一墩 | 所有手牌出完 |
| **LastTrick** | C2, C5 | 最后一墩（标记用于 C6 抠底计算） | 最后一墩结束 |
| **Settlement** | C6 | 计算最终得分、升级结果 | 结算完成 |

**说明**：
- Dealing 和 Bidding 并行运行（边发边亮）
- CounterWindow 仅在非首局且有人定主时进入；首局或无人定主时跳过
- 反主成功时回到 BottomBury（反家重新配底），然后跳过 CounterWindow 直接进 Playing
- LastTrick 与 Playing 逻辑相同，但标记最后一墩以供 C6 读取

#### 3. 出牌阶段（Playing）内部循环

```
TrickPhase:
  LeadPlay → Follow1 → Follow2 → Follow3 → TrickEnd → [LeadPlay | LastTrick]
```

| 阶段 | 说明 |
|------|------|
| **LeadPlay** | 当前先手方出牌（C2 validate_lead） |
| **Follow1/2/3** | 其余 3 人按座位顺序跟牌（C2 validate_follow） |
| **TrickEnd** | 赢墩判定（C2 determine_winner）、分值记录（C5）、先手权转移 |

出牌顺序：从先手方开始，按座位顺序（逆时针，即下标递增 0→1→2→3→0，对应 南→东→北→西）。
先手权：首局首墩由庄家先手；后续墩由上一墩赢家先手。
循环终止：当任何一人手牌为 0 时，当前墩为最后一墩。

#### 4. 座位与队伍

```
Seat: 0(南/下) | 1(东/右) | 2(北/上) | 3(西/左)
Team: [0,2] vs [1,3]  // 对面为搭档
```

庄家方 = 庄家所在队伍。攻方 = 另一队。

### States and Transitions

完整状态转换图：

```
Lobby
  → InRound
    → Dealing + Bidding（并行）
      → BottomBury
        → CounterWindow（非首局）
          ├→ Playing（无反主）
          └→ BottomBury（反主成功，反家配底）→ Playing
        → Playing（首局/无人定主，跳过 CounterWindow）
          → TrickLoop（LeadPlay → Follow×3 → TrickEnd → ...）
            → LastTrick
              → Settlement
                → RoundEnd
                  ├→ InRound（下一局）
                  └→ GameOver
```

### Interactions with Other Systems

| 方向 | 系统 | 交互 |
|------|------|------|
| → F2 牌组管理 | 触发 Dealing 阶段 |
| → F3 规则配置系统 | Lobby 时锁定配置（lock），RoundEnd 时解锁 |
| → C3 亮主/抢主/反主 | 触发 Bidding 和 CounterWindow |
| → C4 抠底/配底 | 触发 BottomBury |
| → C2 出牌合法性校验 | Playing 阶段每次出牌调用校验和赢墩判定 |
| → C5 分值追踪 | TrickEnd 时通知记分 |
| → C6 升级结算 | Settlement 阶段触发结算 |
| → P1–P5 UI | 每个阶段转换时通知 UI 切换显示 |
| → FT1 AI 基础决策 | AI 玩家的出牌轮次时触发 AI 决策 |

## Formulas

C7 无计算公式。所有计算由子系统执行。

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **Dealing + Bidding 并行时序** | F2 发牌事件驱动 C3 异步响应，C7 不阻塞。发牌结束后 C7 等待 C3 输出定主结果再推进 |
| E2 | **反主成功后重新配底** | C7 回退到 BottomBury 状态，反家配底完成后跳过 CounterWindow 直接进 Playing |
| E3 | **首局无人定主** | C3 返回公主局结果，C7 跳过 CounterWindow 直接进 Playing |
| E4 | **出牌阶段玩家超时（未来联机）** | MVP 单机无超时。联机时需定义默认出牌行为 |
| E5 | **所有手牌在最后一墩恰好出完** | 正常——这是预期行为（hand_size 能被整除的情况） |
| E6 | **甩牌失败导致的出牌变更** | C2 返回甩牌失败结果，C7 使用修正后的出牌（最小单张）继续流程 |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← F3 规则配置系统 | 硬依赖 | RuleConfig 快照 |
| → F2 牌组管理 | 硬依赖 | 触发发牌 |
| → C2 出牌合法性校验 | 硬依赖 | 出牌校验 + 赢墩判定 |
| → C3 亮主/抢主/反主 | 硬依赖 | 定主流程控制 |
| → C4 抠底/配底 | 硬依赖 | 配底流程控制 |
| → C5 分值追踪 | 硬依赖 | 记分触发 |
| → C6 升级结算 | 硬依赖 | 结算触发 |
| → FT1 AI 基础决策 | 软依赖 | AI 出牌触发 |
| → P1–P5 UI | 软依赖 | 状态变更通知 |

## Tuning Knobs

C7 无独立可调参数。流程控制完全由子系统的配置和结果驱动。

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | 完整一局流程（2副牌） | Dealing → Bidding → BottomBury → CounterWindow → Playing(25墩) → Settlement |
| AC2 | 首局无人亮主 | 跳过 CounterWindow，公主局进入 Playing |
| AC3 | 反主成功 | 回到 BottomBury，反家配底后进入 Playing |
| AC4 | 出牌阶段所有手牌打完 | 最后一墩标记为 LastTrick，进入 Settlement |
| AC5 | Settlement 判定游戏结束 | 进入 GameOver 而非 InRound |
| AC6 | Settlement 判定继续 | 进入 RoundEnd → InRound，current_rank 已更新 |
| AC7 | 每墩结束后先手权转移 | 赢墩者成为下一墩先手 |
| AC8 | 座位 0 和 2 为搭档 | 始终在同一队 |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | 2 副牌 25 张手牌能否被 4 人整除出完？25 张 = 每人出 25 张，4 人共 100 张出牌 = 25 墩（每墩 4 张）。底牌 8 张不参与出牌。校验：25×4+8=108 ✓ | 已验证 | — |
| Q2 | 1 副牌 12 张 = 12 墩（每墩 4 张 = 48 张）+ 底牌 6 张 = 54 ✓ | 已验证 | — |
