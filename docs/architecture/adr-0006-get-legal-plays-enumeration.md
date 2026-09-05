# ADR-0006: `get_legal_plays()` 合法出牌枚举器（C2 生成器）

## Status

Accepted (2026-09-05)

## Date

2026-09-05

## Last Verified

2026-09-05

## Decision Makers

user + technical-director + game-designer（架构审查 2026-09-05 识别缺口）

## Summary

C2 出牌合法性只实现了**校验器**（`validate_lead`/`validate_follow`：给一手判合不合法），
没有**生成器**（枚举所有合法出牌）；而 FT1 SMART 的评分流水线（遍历合法候选 → `score_play` → 取最高）
硬依赖枚举接口 `get_legal_plays()`。本 ADR 决定把枚举能力沉到 C2、复用现有牌型识别与校验器做穷尽性复核，
并用"域内优先 + 结构约束"剪枝控制 25 张手牌的跟牌组合爆炸——它是 S5-05 的 AC0 级联门。

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | LOW — 纯 GDScript 组合枚举，不触任何 post-cutoff API；语言层数组/字典操作在 4.4–4.6 无破坏性变化 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`（无 Core/Scripting 专门参考；枚举逻辑不依赖引擎特性）；现有 `src/godot/scripts/core/play_validator.gd` / `card_pattern.gd` 读码 |
| **Post-Cutoff APIs Used** | 无 |
| **Verification Required** | (1) 枚举返回集穷尽性——对构造手牌，枚举结果 ⊇ 人工列举的全部合法牌型；(2) 每个枚举元素经 `validate_lead`/`validate_follow` 复核为合法（生成器与校验器同源、无分歧）；(3) 决策路径遍历顺序确定性——枚举结果排序须全序（tie-break 到 `deck_id`，对齐 ADR-0005 §可复现契约） |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None（消费 F1 牌型识别 / C1 排序 / C2 校验器，三者均已实现；无需先立其它 ADR） |
| **Enables** | ADR-0005（SMART 记牌决策）——SMART 评分流水线消费本枚举器；两者共同构成 S5-05 第 0 号交付物 |
| **Blocks** | S5-05（FT1 SMART 模式实现）——本 ADR Accepted 且 `get_legal_plays()` 实现前，SMART 跟牌评分无候选来源 |
| **Ordering Note** | 与 ADR-0005 并列前置，但**逻辑上先于** SMART 决策代码：枚举器是 SMART 的输入。S5-05 Day-0 交付序列中，`get_legal_plays()` 实现与 RNG 注入可并行，SMART 实现排在两者之后 |

## Context

### Problem Statement

FT1 SMART 出牌模式（GDD `ai-basic.md` §5 跟牌骨架 + §4b）的评分流水线是"**枚举合法候选 →
逐候选 `score_play` 评分 → 取最高**"。这条流水线的第一步就是 `get_legal_plays()`——但该函数
**当前全代码库无实现**。C2 GDD（`play-validation.md` Formulas）把它列出并标为 Open Q1
（"25 张手牌的组合爆炸问题"），算法留给实现阶段；FT1 GDD 二次复评把它提为 AC0 级联前置门。

不决策的代价是明确且已量化的：**AC0 FAIL → 12 条 SMART AC 全部 BLOCKED 不可测**
（AC1/6/7/8/9/10/11/12/14/15/19/20），即整个 S5-05 无法验收。且枚举算法不是琐碎实现——
25 张手牌的跟牌组合空间需要剪枝策略，属**架构选择**（枚举位置、剪枝依据、与校验器的一致性契约），
够格独立立 ADR，不应塞进 ADR-0005 的 "Enables" 一笔带过。

### Current State

C2（`src/godot/scripts/core/play_validator.gd`）实现了三个 static 校验/裁决函数：
- `validate_lead(cards, hand, trump_suit, current_rank, rule_config) → PatternResult?`——判一手首出合不合法
- `validate_follow(cards, hand, lead_count, lead_domain, …, lead_pattern) → bool`——判一手跟牌合不合法
- `determine_winner(plays, …) → seat_id`——赢墩裁决

**全是校验器（判定给定的一手），没有生成器（枚举所有可能的一手）。** 现有可复用积木：
- `CardPattern.identify(cards, current_rank, …) → PatternResult`——牌型识别（Single/Pair/Tractor/Dump）
- `PlayValidator._group_by_identity(cards)`——按 identity（同花同点/同类型王）分组
- `PlayValidator.required_pair_count(lead_pattern)`——首出结构里"必须被对上"的对子数（**已公开给 AI**）
- `TrumpJudge.get_suit_domain()` / `get_sort_value()`——域归属与排序

现存一个**危险的临时替代物**：`gui_game.gd` 的 `_find_legal_play` 是不保证穷尽的粗糙跟牌枚举。
更关键的**历史教训**（`play_validator.gd:343-345` 注释记载）：曾经 AI 自己造跟牌候选、走"取最小的 N 张"
分支、与引擎 `validate_follow` 判定**不同源**——把该跟的对子留在手里被引擎判非法，而 GUI 又不检查返回值，
**整局就此卡死数月**。这是本 ADR "枚举必须与校验器同源、不许 AI 自造候选" 的直接依据。

### Constraints

- **不新增 F3 配置项**——枚举行为完全由现有规则参数（`allow_dump`/`strict_follow_structure`/
  `four_same_is_tractor`/`tractor_allow_rank_card`）派生，与 ADR-0001~0005 的"规则收敛"风格一致。
- **不改校验器语义**——`get_legal_plays()` 是新增生成器，`validate_lead`/`validate_follow` 保持不变；
  生成器产出的每个候选**必须**能通过对应校验器（同源不分歧）。
- **性能：分层约束（实测校准，2026-09-05）**——AI 决策**不在帧循环内**（双升回合制，每回合才调一次），
  故 16.6ms 帧预算不适用；真正要防的失败是"整局卡死秒级"（历史 bug）。分层现实目标：
  - **常见手牌**（各域 ≤ 8 张）：单次枚举 **< 5ms**。
  - **极端尾部**（一门副花色占近半手牌、如域内 12 张 + n=4 拖拉机跟牌）：**< 100ms**，玩家等 AI 出牌无感知。
  - **红线**：任何单次枚举 **< 1s**。
  必须靠"域内优先 + 结构约束"剪枝避免 C(25,k) 暴力爆炸（暴力实测 649ms、域内分治后极端 case 61ms）。
- **确定性**——枚举返回集的顺序必须全序（对齐 ADR-0005 §可复现契约：AC16 逐字节可复现要求决策路径
  无非确定遍历序）。枚举内部若用 `Dictionary` 分组，**输出前须显式按规范键排序**。
- **甩牌枚举的最大性由谁负责**——`get_legal_plays(lead=null)` 枚举甩牌候选时**不做最大性校验**
  （最大性需 `other_hands` = 开天眼，AI 不得触碰，见 ADR-0005 / C2 `challenge_dump` 注）。
  枚举只保证**牌型形态（shape）合法**；最大性由 AI 的记牌推断（保守）+ 引擎 `submit_play` 兜底裁决。

### Requirements

- **首出枚举（`lead == null`）**：枚举手牌中所有合法首出牌型——按花色域分组，每域内枚举
  Single / Pair / Tractor / Dump（Dump 仅 `allow_dump=true` 时，且只保证 shape 合法不校验最大性）。
- **跟牌枚举（`lead != null`）**：枚举所有满足跟牌规则（张数匹配、域内优先出完、`strict_follow_structure`
  下的结构匹配）的候选。**须利用"域内牌优先/结构约束"剪枝，不得暴力组合。**
- **穷尽性**：返回集不漏任何合法牌型；每个元素经 `validate_lead`/`validate_follow` 复核为合法。
- **确定性**：返回集有全序（tie-break 到 `deck_id`）。
- **性能**：见 Constraints 分层约束——常见手牌 < 5ms、极端尾部 < 100ms、红线 < 1s（AI 决策非帧循环）。

## Decision

在 C2（`PlayValidator`）新增 static 生成器 `get_legal_plays()`，**按花色域分治枚举**，
复用 `CardPattern.identify` 做牌型识别、`validate_lead`/`validate_follow` 做穷尽性自复核，
用"域内优先 + 结构约束"剪枝。**首出与跟牌两条语义分开实现**，共用底层"域内牌型枚举"子例程。

### Architecture

```
PlayValidator（C2, static）
 ├── validate_lead / validate_follow / determine_winner（既有校验器，不变）
 └── get_legal_plays(hand, lead, trump_suit, current_rank, rule_config) → Array[Array[Card]]   ← 新增
      │
      ├── lead == null（首出枚举）
      │     for each 花色域 D in 按域分组(hand):        # 域内分治，避免跨域组合
      │         enumerate_singles(D)                    # 每张单牌
      │         enumerate_pairs(D)                       # _group_by_identity → size≥2 的组
      │         enumerate_tractors(D)                    # 相邻对子序列（is_adjacent），含 four_same
      │         if allow_dump: enumerate_dumps(D)        # 域内多分量组合，仅 shape，不校验最大性
      │
      └── lead != null（跟牌枚举）
            lead_pattern = lead.pattern; lead_domain = domain(lead)
            domain_cards = 手中 lead_domain 的牌
            required = required_pair_count(lead_pattern)  # 复用既有公开函数
            ├── 域内够牌 → 枚举"满足结构约束(对上 min(手中对子,required))+张数匹配"的域内组合
            └── 域内不够 → 域内牌全出 + 从其它域补齐张数（垫牌/杀牌，枚举补牌组合）
      │
      └── 输出前：对候选集按规范序排序（sort_value→rank→suit→deck_id 全序）
      └── DEBUG 构建：对每个候选 assert validate_lead/validate_follow == 合法（同源自检）
```

### Key Interfaces

```gdscript
## 枚举所有合法出牌方案（供 AI SMART 评分流水线遍历）。
## lead == null → 枚举合法首出；lead != null → 枚举合法跟牌。
## 返回 Array[Array[Card]]，每个元素是一种合法出牌；已按规范全序排序（确定性）。
##
## 甩牌候选只保证 shape 合法，**不校验最大性**（最大性需 other_hands = 开天眼）。
## AI 绝不经此获得 challenge_dump 视野；最大性由 AI 记牌推断 + 引擎 submit_play 兜底。
static func get_legal_plays(
    hand: Array,
    lead: CardPattern.PatternResult,   # null = 首出枚举
    trump_suit: int,
    current_rank: int,
    rule_config: RuleConfig,
) -> Array:
    ...

# 内部子例程（private，域内分治）：
static func _enumerate_lead_in_domain(domain_cards: Array, current_rank: int, rc: RuleConfig) -> Array
static func _enumerate_follow(hand: Array, lead: CardPattern.PatternResult, lead_domain: Dictionary, …) -> Array
static func _sort_candidates_canonical(candidates: Array, trump_suit: int, current_rank: int, jat: bool) -> Array
```

### Implementation Guidelines

1. **域内分治是主剪枝**：合法牌型的所有牌必属同一花色域（F1/C2 硬约束），故先 `_group_by_identity`
   / 按域分组，只在**单个域内**枚举，天然砍掉所有跨域组合。这把首出枚举从 C(25,k) 降到各域独立的小空间。
2. **跟牌枚举的结构约束优先剪枝**：`strict_follow_structure=true` 时，先算 `required_pair_count`，
   只枚举"能对上 `min(手中对子, required)` 个对子"的组合——不满足结构的组合根本不生成，而非生成后过滤。
3. **甩牌枚举只做 shape**：`enumerate_dumps` 用与 `CardPattern._try_dump` 相同的贪心拆解（拖拉机→对子→单张）
   验证候选是合法甩牌形态即可，**绝不调用 `challenge_dump`**。这与 ADR-0005 的 SMART 甩牌自校验走
   `validate_lead` 同源。
4. **确定性输出**：任何内部 `Dictionary` 分组（如 `_group_by_identity`）的遍历结果，**输出前必须显式排序**
   （`sort_value→rank→suit→deck_id` 全序），不得直接把字典遍历序当作候选顺序——对齐 ADR-0005 的
   `ai_decision_dictionary_ordered_traversal` 禁令。
5. **同源自检（DEBUG）**：生成器每产出一个候选，DEBUG 构建下 `assert` 它能通过对应校验器
   （`validate_lead`/`validate_follow`）。这把"生成器与校验器分歧"这一历史 bug 类别在开发期挡死。
   release 构建跳过 assert（性能）。
6. **穷尽性测试用构造牌局**：AC0 的穷尽性验收对构造手牌人工列举全部合法牌型，比对枚举返回集 ⊇ 该集合。

## Alternatives Considered

### Alternative 1: AI 自行从手牌分析生成候选（不沉到 C2）

- **Description**: SMART 决策器自己扫手牌造出候选牌型，仅用 `validate_lead` 做 shape 校验，不实现通用枚举器。
- **Pros**: 不动 C2；AI 只造它评分时真正需要的候选，可能更省。
- **Cons**: 生成逻辑与引擎校验器**不同源**——这正是 `play_validator.gd:343-345` 记载的"整局卡死数月"
  bug 的根因（AI 造的牌被引擎判非法、GUI 不检查返回值）。每个消费方各造一套枚举 = 分歧面 ×N。
- **Estimated Effort**: 表面更小，实则把正确性风险推给每个消费方。
- **Rejection Reason**: FT1 GDD 二次复评已明确"替代路线（SMART 自造候选）**不采用**，保留枚举式架构、
  把枚举能力沉到 C2 复用"。本 ADR 遵此裁决。

### Alternative 2: 暴力枚举 C(n,k) 后用 validate_* 全过滤

- **Description**: 对手牌所有 k-子集暴力组合，逐个丢给 `validate_lead`/`validate_follow` 过滤留下合法的。
- **Pros**: 实现最简单、穷尽性天然成立（只要校验器对）。
- **Cons**: 25 张手牌 C(25,k) 组合爆炸——k=4 时 C(25,4)=12650，跟牌枚举每墩多次调用会拖垮决策；
  且大量组合跨域，绝大多数一开始就非法，纯浪费。
- **Estimated Effort**: 实现最省但运行时最贵。
- **Rejection Reason**: C2 GDD Open Q1 与本 ADR Constraints 都要求剪枝；暴力枚举违反性能约束。
  域内分治能拿到相同穷尽性且避免组合爆炸。

### Alternative 3: 枚举器内联最大性校验（甩牌枚举即调 challenge_dump）

- **Description**: `get_legal_plays` 枚举甩牌时顺便调 `challenge_dump` 剔除非最大甩牌，只吐"保证能成"的甩牌。
- **Pros**: AI 拿到的甩牌候选都是"真最大"，不会被引擎降级。
- **Cons**: `challenge_dump` 需 `other_hands`（其他三家手牌）= **开天眼**。AI 决策路径调它等同作弊，
  违反 C2 契约与 ADR-0005 的 SMART 反作弊设计。
- **Rejection Reason**: 硬违反"AI 不得触碰 other_hands"。最大性由 AI 记牌推断（保守）+ 引擎兜底，
  枚举器只管 shape。

## Consequences

### Positive

- **单一权威枚举**：生成器与校验器同源，杜绝"AI 造的牌被引擎判非法"这一 bug 类别（历史已复发过）。
- **SMART 评分流水线有确定数据源**，AC0 级联门可满足，解锁 12 条被 BLOCK 的 SMART AC。
- **域内分治**把组合空间控制在可接受量级，满足性能约束。
- **确定性排序** + DEBUG 同源自检，天然对齐 ADR-0005 的逐字节可复现契约。

### Negative

- C2 新增一块非平凡代码（枚举 + 剪枝 + 排序 + 自检），实现与测试有成本（估 1.5–2 天）。
- 跟牌枚举的"域内不够 → 补牌组合"分支仍有组合展开，极端手牌（域内 0 张、需从多域补齐长甩牌张数）
  下候选数可能偏大——需实测确认在 5ms 内；若超标，加"补牌只保留每域最小若干张"的启发式剪枝（记为后续 Tuning）。

### Neutral

- `gui_game.gd._find_legal_play` 这个不穷尽的临时替代物在本 ADR 落地后可删除或改调 `get_legal_plays`
  （不强制，属清理项）。

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| 枚举遗漏某类合法牌型（穷尽性破洞） | 中 | 高（AI 错过合法出牌 / AC0 FAIL） | AC0 构造牌局人工列举比对；DEBUG 同源 assert；跨 {1副,2副}×{strict}×{allow_dump} 配置覆盖 |
| 跟牌补牌分支组合展开超 5ms | 低 | 中 | 实测最坏手牌；超标则加"每域最小 N 张"剪枝启发式 |
| 枚举内部 Dictionary 遍历序泄漏到输出 → 破坏可复现 | 中 | 中（AC16 逐字节比对失败） | 输出前强制 `_sort_candidates_canonical` 全序；code review 查 `for k in dict` |
| 生成器/校验器分歧（历史 bug 复发） | 低 | 高（整局卡死） | DEBUG 每候选 assert 过校验器；两者共用 `identify`/`required_pair_count` 底层 |

## Performance Implications

| Metric | 暴力(否决) | 实测(域内分治) | 分层约束 |
|--------|-----------|---------------|---------|
| 首出枚举 (25 张) | — | **1.9ms** / 27 候选 | < 5ms ✅ |
| 跟牌 n=4, 域内 ≤ 8 张 (常见) | — | **~3ms** / 28 候选 | < 5ms ✅ |
| 跟牌 n=4, 域内 12 张 (极端尾部) | 649ms | **61ms** / 495 候选 | < 100ms ✅ |
| Memory | — | ≤ 数百候选 × Array 引用，KB 量级瞬时 | 256MB 移动端 |
| Network | — | 不适用（本地单机） | — |

> **实测校准（2026-09-05）：** 暴力 `_combinations(hand, n)` 在域内 12 张 + n=4 拖拉机跟牌下达
> **649ms**——改为域内分治（域内够牌只枚举 C(域内, n)、域内不够则域内全出 + 域外补）后降到 **61ms**。
> `validate_follow` 的 `domain_cards` 预算缓存再降至此（瓶颈已是候选基数 495 本身，非重算）。
>
> **为何 61ms 可接受、不再强凑 5ms：** AI 决策**不在帧循环内**（回合制，每回合调一次），玩家等 AI
> 出牌 61ms 无感知；ADR 真正防的是"整局卡死秒级"（历史 bug），61ms 离红线（< 1s）极远。原 5ms 是
> 首版拍定的宽松上界、对"一门花色占近半手牌"这一 2σ 尾部定得过严。**域内 12 张同花色是罕见尾部**——
> 发牌均分下一门副花色期望 ~6 张，常见 case（域内 6-8 张）为 15-70 候选、几 ms。故约束改为分层现实值。
> 若 FT4 实测极端手牌频率偏高影响体验，再引入候选数软上限（结构代表候选），届时须在测试标注穷尽性窄化。

## Migration Plan

1. **新增 `PlayValidator.get_legal_plays()`** + 私有子例程（`_enumerate_lead_in_domain` /
   `_enumerate_follow` / `_sort_candidates_canonical`），复用 `CardPattern.identify` /
   `_group_by_identity` / `required_pair_count`。
2. **首出枚举先行**（`lead=null`）：域内 Single/Pair/Tractor/Dump 枚举 + 全序排序 + DEBUG 自检。
3. **跟牌枚举**（`lead!=null`）：结构约束剪枝的域内组合 + 域内不够时的补牌分支。
4. **测试**（`src/godot/tests/test_play_validator.gd` 或新 `test_get_legal_plays.gd`）：
   - AC0 穷尽性：构造手牌人工列举 vs 枚举返回集
   - 每候选过 `validate_lead`/`validate_follow`（同源）
   - 跨 {1副,2副}×{strict on/off}×{allow_dump on/off} 配置
   - 输出顺序确定性（同输入两次调用逐元素一致）
5. **可选清理**：`gui_game.gd._find_legal_play` 改调 `get_legal_plays` 或删除。
6. **交付时序**：本 ADR Accepted → 实现 `get_legal_plays` → （与 RNG 注入并行）→ 抓 AC16 基准 → SMART 实现。

**Rollback plan**: 枚举器是纯新增 static 函数、不改校验器；若实现有问题，SMART 未上线前直接回退该函数、
不影响任何已发布路径（v1.x SIMPLE/测试开关不消费枚举器）。

## Validation Criteria

- [ ] `get_legal_plays(lead=null)` 对构造手牌枚举全部合法首出，返回集 ⊇ 人工列举集（穷尽）
- [ ] `get_legal_plays(lead≠null)` 对构造手牌枚举全部合法跟牌，覆盖"域内够牌/不够补牌"两分支
- [ ] 每个返回元素经 `validate_lead`/`validate_follow` 复核为合法（零分歧）
- [ ] 跨 {1副,2副}×{strict on/off}×{allow_dump on/off} 配置，返回集均合法且穷尽
- [ ] 同输入两次调用返回逐元素一致（确定性 / 全序）
- [ ] 25 张手牌最坏情形单次枚举 < 5ms
- [ ] 甩牌枚举不引用 `challenge_dump`（grep 源码 + DEBUG 调用栈 spy，同 FT1 AC13 手法）

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/ai-basic.md` | FT1 | AC0：C2 `get_legal_plays()` 已实现，枚举合法出牌（首出+跟牌两语义，跟牌须剪枝、穷尽） | 域内分治枚举 + 校验器同源自检，覆盖 `lead=null/≠null` |
| `design/gdd/ai-basic.md` | FT1 | §5 跟牌骨架 / §可复现契约：枚举流水线 + 决策路径确定性 | 枚举返回集全序排序（tie-break deck_id），对齐 ADR-0005 |
| `design/gdd/play-validation.md` | C2 | Formulas `get_legal_plays()`（Open Q1：组合爆炸需剪枝，留实现期） | 本 ADR 定枚举架构与剪枝策略，关闭 Open Q1 |
| `design/gdd/card-types.md` | F1 | §2.3 甩牌 shape 判定（贪心拆解拖拉机→对子→单张） | 甩牌枚举复用同一贪心，仅校验 shape 不校验最大性 |

## Related

- **Enables / 并列前置**: [ADR-0005](adr-0005-card-memory-state-management.md)（SMART 记牌决策消费本枚举器；
  两者共同构成 S5-05 第 0 号交付物，本 ADR 逻辑上先于 SMART 决策代码）
- **消费的既有实现**: `src/godot/scripts/core/play_validator.gd`（校验器 + `required_pair_count` +
  `_group_by_identity`）、`src/godot/scripts/core/card_pattern.gd`（`identify` / `_try_dump` 贪心拆解）
- **GDD**: [`design/gdd/play-validation.md`](../../design/gdd/play-validation.md) Open Q1、
  [`design/gdd/ai-basic.md`](../../design/gdd/ai-basic.md) AC0 / Dependencies A2
- **历史依据**: `play_validator.gd:343-345` 注释记载的"AI 自造候选与校验器不同源导致整局卡死"教训
