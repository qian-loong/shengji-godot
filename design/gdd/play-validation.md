# C2 出牌合法性校验

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 2（规则即策略）

## Overview

**出牌合法性校验系统**是对局中每一次出牌的裁判。它接收玩家（或 AI）选择的牌，结合当前手牌、首出牌型、花色域归属和规则配置，判定"这手牌能不能出"。

本系统分两个场景运作：
- **首出校验**：判定出牌是否构成合法牌型（Single / Pair / Tractor / Dump）
- **跟牌校验**：判定跟牌是否满足跟牌规则（花色匹配、结构匹配、必须出最大等约束）

本系统还负责**赢墩判定**——一轮 4 人出牌后，判定谁赢得这一墩。

## Player Fantasy

C2 直接决定玩家能否执行自己的战术意图。如果合法出牌被拒绝，玩家会愤怒；如果非法出牌被允许（AI 或对手作弊），玩家会失去信任。本系统的情感目标是**公正感**——"规则对所有人一视同仁，包括 AI"。

## Detailed Design

### Core Rules

#### 1. 首出校验

```
validate_lead(cards: Card[], hand: Card[], rule_config: RuleConfig) → Result<LeadPlay, Error>
```

- 所有牌必须在手牌中存在
- 所有牌必须同属一个花色域（由 C1 判定）
- 识别牌型：Single / Pair / Tractor / Dump
- Dump 需额外校验"最大性"（见甩牌校验）

**甩牌校验**

```
validate_dump(cards: Card[], hand: Card[], other_hands: Card[3][], rule_config: RuleConfig) → Result<DumpDetail, Error>
```

1. `allow_dump` 必须为 true
2. 所有牌同属一个花色域
3. 拆解为最大牌型优先：拖拉机 > 对子 > 单张
4. 每个组成部分在其他 3 人手中该花色域内无更大的同类型牌
5. 失败时：只出选中牌中最小的一张单牌，其余收回

#### 2. 跟牌校验

```
validate_follow(cards: Card[], hand: Card[], lead: LeadPlay, rule_config: RuleConfig) → Result<FollowPlay, Error>
```

**基本规则**：出牌张数必须等于首出张数。

**跟牌优先级（strict_follow_structure = true）**：

跟牌方必须按以下优先级尽量匹配首出结构：

**场景 A：手中有首出花色域的牌**

| 首出牌型 | 跟牌要求（按优先级从高到低） |
|---------|--------------------------|
| Single | 必须出该花色域的牌（任意 1 张） |
| Pair | ① 有该花色域对子 → 必须出对子；② 无对子 → 出该花色域任意 2 张 |
| Tractor(N对) | ① 有该花色域拖拉机 → 必须出拖拉机；② 无拖拉机但有对子 → 尽量多出对子，剩余用单张补；③ 无对子 → 出该花色域任意 2N 张 |
| Dump | 按甩牌的拆解结构，对每个组成部分分别执行上述优先级匹配 |

**关键原则**：该花色域的牌必须优先出完，不足部分才可用其他花色域的牌补。

**场景 B：手中无首出花色域的牌（垫牌/杀牌）**

可以出任意花色域的牌（包括主牌），张数匹配即可。

#### 3. 赢墩判定

```
determine_winner(plays: Play[4], lead_domain: SuitDomain) → seat_id
```

一轮 4 人出牌后，按以下规则判定赢家：

**规则 1：主牌杀必须匹配首出牌型结构**

出主牌想赢墩，主牌组合必须构成与首出**相同的牌型**：
- 首出对子 → 主牌必须是对子才能赢
- 首出拖拉机(N对) → 主牌必须是拖拉机(≥N对)才能赢
- 首出单张 → 主牌单张即可赢
- 大王+小王不是对子，不能赢对子

**规则 2：同花色域内比大小**

- 同花色域的牌按 C1 排序值比大小
- 同层级同值（如非主花级牌）→ 先出者大

**规则 3：优先级**

1. 有合法主牌杀（结构匹配）→ 最大的主牌杀赢
2. 无主牌杀 → 首出花色域中最大者赢
3. 垫牌（非首出花色域、非主牌域）→ 永远不赢

**赢墩判定流程**：

```
candidates = []
for each play in plays:
    if play.domain == TrumpDomain && play.domain != lead_domain:
        // 主牌杀：检查结构是否匹配首出牌型
        if matches_structure(play, lead.card_type):
            candidates.add(play, priority=TRUMP)
    elif play.domain == lead_domain:
        // 同花色域跟牌
        candidates.add(play, priority=FOLLOW)
    else:
        // 垫牌，不参与赢墩
        skip

winner = candidates中TRUMP优先级最大者，若无TRUMP则FOLLOW优先级最大者
平局时先出者大
```

### States and Transitions

C2 无内部状态。所有校验函数（validate_lead、validate_follow、determine_winner）都是纯函数——输入当前牌局状态，输出校验结果，无副作用。

### Interactions with Other Systems

| 方向 | 系统 | 接口 |
|------|------|------|
| ← F1 牌型定义 | CardType 枚举、is_adjacent()、牌型拆解 |
| ← F3 规则配置系统 | `allow_dump`、`strict_follow_structure`、`four_same_is_tractor`、`tractor_allow_rank_card` |
| ← C1 主副牌判定 | `get_suit_domain()`、`get_sort_value()` |
| → C7 对局状态机 | C7 每次出牌时调用 C2 校验，赢墩后调用 determine_winner |
| → FT1 AI 基础决策 | AI 调用 C2 获取当前合法出牌列表 |
| → P3 出牌/动画反馈 | P3 根据校验结果决定是否播放出牌动画或拒绝动画 |

## Formulas

### 合法出牌枚举（供 AI 使用）

```
get_legal_plays(hand: Card[], lead: LeadPlay?, rule_config: RuleConfig) → Card[][]
```

- lead = null 时：枚举所有合法首出组合
- lead != null 时：枚举所有合法跟牌组合
- 返回值为二维数组，每个元素是一种合法出牌方案

此函数计算量可能较大（尤其 25 张手牌的组合空间），AI 性能优化阶段可能需要剪枝策略。暂不定义具体算法，留给实现阶段。

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **跟牌方该花色域牌不够**：首出拖拉机 4 张，跟牌方该花色域只有 3 张 | 3 张必须全出（该花色域的牌优先出完），剩余 1 张从其他花色域补 |
| E2 | **多人主牌杀**：两人都出了结构匹配的主牌 | 主牌之间按 C1 排序值比大小，大的赢 |
| E3 | **首出是主牌域**：首出方本身出的就是主牌 | 其他人跟主牌域，无主牌时垫任意牌。不存在"杀"的概念，因为首出就是主 |
| E4 | **甩牌被挑战后的出牌**：甩牌失败后被迫出最小单牌 | 该单牌视为 Single 首出，后续 3 人按 Single 跟牌规则出牌 |
| E5 | **跟甩牌时的结构匹配**：首出甩牌 = 拖拉机 + 单张（如 ♥5566♥A） | 跟牌方需分别匹配每个组成部分：优先出拖拉机 + 单张；无拖拉机则降级为对子+对子+单张，依此类推 |
| E6 | **无主局 + joker_always_trump=false 时出王** | 王牌不属于任何花色域，不能赢任何墩，只能在无首出花色牌时作为垫牌打出（C1 E1 已定义） |
| E7 | **1 副牌下无对子可跟** | 正常降级：无对子出 2 张单张。1 副牌下这是常态 |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← F1 牌型定义 | 硬依赖 | CardType、is_adjacent()、牌型拆解算法 |
| ← F3 规则配置系统 | 硬依赖 | 出牌相关配置参数 |
| ← C1 主副牌判定 | 硬依赖 | get_suit_domain()、get_sort_value() |
| → C7 对局状态机 | 被硬依赖 | validate_lead()、validate_follow()、determine_winner() |
| → FT1 AI 基础决策 | 被硬依赖 | get_legal_plays() |
| → P3 出牌/动画反馈 | 被软依赖 | 校验结果 |

## Tuning Knobs

C2 无独立可调参数。所有影响出牌规则的参数由 F3 承载（`allow_dump`、`strict_follow_structure`、`four_same_is_tractor`、`tractor_allow_rank_card`）。

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | 首出 ♠33（对子），手牌包含 ♠33 | 合法，识别为 Pair |
| AC2 | 首出 ♠35（非对子非拖拉机），allow_dump=false | 非法 |
| AC3 | 甩牌 ♥AA ♥K，其他人手中♥域无 A 对和 K 以上单张 | 合法 Dump |
| AC4 | 甩牌 ♥KK ♥Q（对子+单张），某人手中有 ♥A | 甩牌失败——♥Q 不是最大单张（♥A > ♥Q），强制出最小单张 |
| AC5 | 跟对子，手中有该花色域对子 | 必须出对子 |
| AC6 | 跟对子，手中无该花色域对子但有该花色单张 | 出该花色域任意 2 张单张 |
| AC7 | 跟拖拉机 4 张，手中该花色域只有 3 张 | 3 张必须全出，1 张从其他花色域补 |
| AC8 | 赢墩：首出 ♥22，跟牌 ♠AA（主牌对子） | ♠AA 赢（结构匹配的主牌杀） |
| AC9 | 赢墩：首出 ♥22，跟牌 大王+小王 | 大王+小王不赢（不是对子） |
| AC10 | 赢墩：首出 ♥2233，跟牌 ♠KKAA（主牌拖拉机） | ♠KKAA 赢（结构匹配） |
| AC11 | 赢墩：首出 ♥2233，跟牌 ♠99 ♠AA | 不赢（不是拖拉机） |
| AC12 | 赢墩：两人主牌杀，♠55 vs ♠KK | ♠KK 赢 |
| AC13 | 赢墩：首出 ♥5，无人出主牌，♥A 最大 | ♥A 赢 |
| AC14 | 甩牌 ♥A ♥KK（单张+对子），某人手中有另一张 ♥A | 合法——等值不算"更大"，先出者大，甩牌成功 |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | `get_legal_plays` 的算法性能优化——25 张手牌的组合爆炸问题 | FT1/实现阶段 | 高 |
| Q2 | 甩牌拆解的"最大牌型优先"策略是否存在歧义情况（多种拆解方式都合法） | 实现阶段 | 中 |
| Q3 | 跟甩牌时如果只能部分匹配结构，剩余部分的选择是否需要约束（必须出最大？还是任意？） | 待确认 | 中 |
