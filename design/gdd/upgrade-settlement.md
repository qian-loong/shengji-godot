# C6 升级结算

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 2（规则即策略）

## Overview

**升级结算系统**负责对局结束时的最终计算：合并出牌阶段得分与抠底分值，判定攻守双方的升级结果，处理不可跳过级的约束，并更新 current_rank。本系统是一局与下一局之间的桥梁——它的输出直接决定下一局的级牌和庄家归属。

## Player Fantasy

结算是整局博弈的最终揭晓——"我们赢了多少分？升几级？有没有被抠底翻盘？"抠底倍数的存在让最后一墩充满悬念。本系统服务的情感是**结果张力**——分数揭晓时的紧张与满足。

## Detailed Design

### Core Rules

#### 1. 最终得分计算

```
calculate_final_score(attack_score: int, bottom: Card[], last_trick_winner: TeamSide, last_trick_type: CardType, last_trick_pair_count: int) → int
```

流程：
1. 基础分 = C5 提供的 `attack_score`（出牌阶段攻方累计得分）
2. 如果攻方赢得最后一墩：
   - 计算底牌分值：`bottom_score = sum(card_score(c) for c in bottom)`
   - 计算抠底倍数：`multiplier = get_bottom_multiplier(last_trick_type, last_trick_pair_count)`（F3 已定义公式）
   - 最终得分 = `attack_score + bottom_score × multiplier`
3. 如果庄家方赢得最后一墩：
   - 最终得分 = `attack_score`（底牌分值不计入）

#### 2. 升级阶梯

| 攻方最终得分 | 结果 | 谁升级 | 升几级 |
|-------------|------|--------|--------|
| = 0 | 庄家大胜 | 庄家方 | 2 级 |
| 1–39 | 庄家小胜 | 庄家方 | 1 级 |
| 40–79 | 庄家守住 | 庄家方 | 不升（继续坐庄） |
| 80–119 | 攻方下庄 | 攻方 | 不升（仅换庄） |
| 120–149 | 攻方小胜 | 攻方 | 1 级 |
| 150–199 | 攻方大胜 | 攻方 | 2 级 |
| = 200 | 攻方全收 | 攻方 | 3 级 |

以上阈值（0/40/80/120/150/200）均可配置。

#### 3. 不可跳过级

某些级在升级时不可跳过（可配置，默认 5、10、K）：

```
apply_upgrade(current_rank: Rank, levels: int, no_skip_ranks: Rank[]) → Rank
```

算法：
```
rank = current_rank
for i in 1..levels:
    rank = next_rank(rank)  // 按 2,3,4,...,K,A 顺序
    if rank in no_skip_ranks and i < levels:
        return rank  // 遇到不可跳过级，停在此处
return rank
```

示例（no_skip = [5, 10, K]）：

| 当前级 | 升级数 | 目标 | 实际结果 | 原因 |
|--------|--------|------|---------|------|
| 4 | 2 | 6 | 5 | 5 不可跳过 |
| 4 | 1 | 5 | 5 | 正好到 5，无跳过 |
| 5 | 2 | 7 | 7 | 从 5 出发，6→7 无阻挡 |
| 9 | 2 | J | 10 | 10 不可跳过 |
| Q | 2 | A | K | K 不可跳过 |
| K | 1 | A | A | 正好到 A |

#### 4. 下庄判定

攻方最终得分 ≥ 80（`upgrade_threshold`）→ 下庄。下一局庄家切换到攻方。

#### 5. 游戏结束条件

当一方需要打 A 级时（current_rank = A），该局为"打 A"局。打完 A 级后（即该方在 A 级胜出并需要继续升级时），该方获胜，游戏结束。

### States and Transitions

C6 无持续状态。对局结束时执行一次计算，输出升级结果。

### Interactions with Other Systems

| 方向 | 系统 | 接口 |
|------|------|------|
| ← C5 分值追踪 | attack_score（出牌阶段攻方得分） |
| ← C4 抠底/配底 | 底牌 Card[]（用于计算底牌分值） |
| ← C7 对局状态机 | 最后一墩的赢家、牌型信息 |
| ← F3 规则配置系统 | `upgrade_threshold`、`upgrade_step`、升级阈值表、`no_skip_ranks` |
| → F3 规则配置系统 | 更新 `current_rank`（下一局的级牌） |
| → C3 亮主/抢主/反主 | 庄家归属（下一局谁坐庄） |
| → P5 结算界面 | 结算数据（得分、倍数、升级结果）供 UI 展示 |

## Formulas

### 抠底倍数（来自 F3）

| 最后一手牌型 | 倍数 |
|-------------|------|
| Single | 1 |
| Pair | 2 |
| Tractor(N对) | N × 2 |
| Dump | 取最大成分倍数 |

### 升级阈值表（可配置）

```
UPGRADE_TABLE = {
    0:   (Side.DEALER, 2),   // 庄家升 2
    40:  (Side.DEALER, 1),   // 庄家升 1
    80:  (Side.ATTACK, 0),   // 攻方换庄不升
    120: (Side.ATTACK, 1),   // 攻方升 1
    150: (Side.ATTACK, 2),   // 攻方升 2
    200: (Side.ATTACK, 3),   // 攻方升 3
}
```

查表逻辑：找到 ≤ 最终得分的最大阈值，取对应结果。

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **抠底翻盘**：出牌阶段攻方 70 分（未下庄），但赢最后一墩抠底后达 120 | 最终得分 = 120，攻方升 1 级 |
| E2 | **底牌无分牌** | bottom_score = 0，倍数无意义，最终得分 = attack_score |
| E3 | **current_rank = A 且胜方需继续升级** | 游戏结束，该方获胜 |
| E4 | **current_rank = A 且胜方不升级（40–79 分守住）** | 不结束，庄家继续打 A |
| E5 | **升级跨越多个不可跳过级**：如当前 3 级升 3 级（3→6），但 5 不可跳过 | 停在 5 |
| E6 | **no_skip_ranks 为空** | 所有级均可跳过，正常升级 |
| E7 | **攻方得分恰好 = 阈值**（如 80、120） | 按该阈值对应的结果处理（≥ 80 下庄，≥ 120 升 1） |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← C5 分值追踪 | 硬依赖 | attack_score |
| ← C4 抠底/配底 | 硬依赖 | 底牌 Card[] |
| ← C7 对局状态机 | 硬依赖 | 最后一墩信息 |
| ← F3 规则配置系统 | 硬依赖 | 升级相关配置 |
| → F3 规则配置系统 | 写入 | 更新 current_rank |
| → C3 亮主/抢主/反主 | 通知 | 下一局庄家归属 |
| → P5 结算界面 | 被硬依赖 | 结算展示数据 |

## Tuning Knobs

| 参数 | 类型 | 默认值 | 影响 |
|------|------|--------|------|
| `upgrade_thresholds` | int[] | [0, 40, 80, 120, 150, 200] | 升级阶梯的分值阈值，**需更新 F3 参数表** |
| `no_skip_ranks` | Rank[] | [5, 10, K] | 不可跳过的级，可配置开关 |
| `no_skip_enabled` | bool | true | 是否启用不可跳过级 |

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | 攻方出牌得 70 分，庄家方赢最后一墩 | 最终得分 70，庄家方不升级（40–79 区间） |
| AC2 | 攻方出牌得 70 分，攻方赢最后一墩（Pair），底牌含 ♠5♥10 = 15 分 | 最终得分 = 70 + 15×2 = 100，攻方下庄不升 |
| AC3 | 攻方出牌得 70 分，攻方赢最后一墩（Tractor 2对），底牌含 30 分 | 最终得分 = 70 + 30×4 = 190，攻方升 2 级 |
| AC4 | 攻方得 0 分 | 庄家方升 2 级 |
| AC5 | 攻方得 30 分 | 庄家方升 1 级 |
| AC6 | 攻方得 200 分 | 攻方升 3 级 |
| AC7 | 当前级 4，升 2 级，no_skip=[5,10,K] | 实际升到 5（5 不可跳过） |
| AC8 | 当前级 5，升 2 级，no_skip=[5,10,K] | 实际升到 7（从 5 出发无阻挡） |
| AC9 | 当前级 A，庄家方守住 | 继续打 A，游戏不结束 |
| AC10 | 当前级 A，攻方下庄且需升级 | 游戏结束，攻方获胜 |
| AC11 | no_skip_enabled=false，当前级 4 升 2 级 | 直接到 6（跳过 5） |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | `upgrade_thresholds` 和 `no_skip_ranks`/`no_skip_enabled` 需补充到 F3 参数表 | F3 更新 | 高 |
| Q2 | 1 副牌时升级阈值是否需要等比缩放（总分 100 vs 200）？ | 待确认 | 高 |
