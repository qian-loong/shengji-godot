# ADR-0001: 定主声明强度 5 档细分（拆 JOKER_RANK → JOKER_SINGLE_RANK / JOKER_PAIR_RANK）

## Status

Proposed

## Date

2026-05-18

## Context

### Problem Statement

当前 `TrumpBidding.BidType` 把 `bid_requires_joker = true` 模式下「王 + 1 张级牌」与「王 + 2 张同花色级牌」都归入同一档 `JOKER_RANK`（strength = 3），导致：

1. **不符合真实双升玩法**。线下双升将「王+对级」公认为比「王+单级」更强的亮主——它需要更稀有的对级牌，理应在反主与定主竞争中更具压制力。
2. **退化的反主样本**。`feature/counter-bid` 的 50 局烟测中，4 次反主成功 **全部** 是 `PAIR_JOKER` 反 `JOKER_RANK`——因为模式 B（项目默认）只剩 strength 3 ↔ 4 一条反主路径，「王+对级」无法体现优势。这削弱了反主特性的博弈空间与 AI 行为多样性。
3. **两模式不对称**。模式 A（`bid_requires_joker = false`）天然有「单 < 对 < 公主」三档结构，而模式 B 仅有两档。应让两模式具备对称的"弱 < 强 < 公主"三档阶梯。

### Constraints

- **必须保持 `is_stronger` 严格大于语义**——同档不同花色仍不可互反（与 ADR 之外的 GDD trump-bidding §4 第 3 条保持一致）。
- **必须保持向后兼容**——原 `JOKER_RANK` 测试要么显式迁移为 `JOKER_SINGLE_RANK`、要么有路径覆盖；不允许悄悄改变历史日志的可重放语义。
- **必须保持下游隔离**——结算（C6）、出牌（C7）、扣底（C4）不读 `bid_type` 强度，仅读 `trump_suit`，因此核心规则引擎不受影响。
- **零网络/零 IO 影响**——纯枚举/比较函数变更。

### Requirements

- 扩充 `BidType` 枚举为 5 档（含 `NONE`），enum 数值即 strength 排序。
- `get_available_bids` 在 `bid_requires_joker = true` 模式下同时枚举 `JOKER_SINGLE_RANK` 和 `JOKER_PAIR_RANK`，不再仅生成"王+任一级牌"。
- 「王+对级」必须严格同花色（与 `PAIR_RANK` 同口径），由用户在 [反主-Q1](../../production/sprints/counter-bid-plan.md) 后续会话中明确决定。
- 颜色匹配（`trump_joker_color_match`）仍只是合法性约束，不参与强度比较。
- AI 决策启发式同步更新：`decide_bid` 在模式 B 下优先选 `JOKER_PAIR_RANK`（若手牌成立），但权重不能极端到压抑常见的 `JOKER_SINGLE_RANK` 亮主。

## Decision

### 新枚举

```gdscript
enum BidType {
    NONE = 0,
    SINGLE_RANK = 1,           # 1 张级牌（不需要王模式）
    PAIR_RANK = 2,             # 2 张同花色级牌（不需要王模式）
    JOKER_SINGLE_RANK = 3,     # 王 + 1 张级牌（需要王模式）
    JOKER_PAIR_RANK = 4,       # 王 + 2 张同花色级牌（需要王模式，新增）
    PAIR_JOKER = 5,            # 2 张同种王（公主，最高，不可反）
}
```

### 两条阶梯（互斥）

```
模式 A（bid_requires_joker = false）：
    SINGLE_RANK(1)        <  PAIR_RANK(2)        <  PAIR_JOKER(5)

模式 B（bid_requires_joker = true，项目默认）：
    JOKER_SINGLE_RANK(3)  <  JOKER_PAIR_RANK(4)  <  PAIR_JOKER(5)
```

> 跨模式比较只在理论层面有意义；模式由 `RuleConfig.bid_requires_joker` 切换，运行时不会同时存在两种来源的 bid。

### Key Interfaces

#### `TrumpBidding.get_available_bids` 改动

```gdscript
# bid_requires_joker = true 分支增量伪码
for suit in rank_per_suit:
    var rank_count := rank_per_suit[suit]
    var has_matching_joker := _find_matching_joker(suit, joker_counts, rule_config)
    if not has_matching_joker:
        continue
    bids.append(BidDeclaration.new(seat_id, BidType.JOKER_SINGLE_RANK, suit))
    if rank_count >= 2:
        bids.append(BidDeclaration.new(seat_id, BidType.JOKER_PAIR_RANK, suit))
```

#### `is_stronger` / `_bid_strength` 不变

继续使用 enum 数值即 strength，不修改函数签名。

#### `can_be_countered` 不变

仍然 `bid.bid_type != BidType.PAIR_JOKER`。

#### 「王+对级」合法性

- 王和级牌对子的颜色匹配规则同 `JOKER_SINGLE_RANK`（受 `trump_joker_color_match` 约束）。
- 对子必须是 **同花色**（如 ♥5 + ♥5），跨花色（♥5 + ♦5）不算合法 `JOKER_PAIR_RANK`。

## Alternatives Considered

### Alternative 1：保留现状，仅在 GDD 明文写"严格大于"

- **Description**：不动代码，把"同档不同花色不可互反"写进 GDD §4 / E3（已在 counter-bid §7 完成）。
- **Pros**：零代码变更、零回归风险。
- **Cons**：无法解决"王+对级"压制不到"王+单级"的根本问题；模式 B 反主样本仍单一；与真实双升偏离。
- **Rejection Reason**：仅治标，未触及核心规则缺陷。

### Alternative 2：允许"同强度反花色"（红黑切换）

- **Description**：扩充 `is_stronger` 让同档但不同花色在某些条件下成立（典型："黑色 5 + 大王" 反 "红色 5 + 大王"）。
- **Pros**：保留 4 档枚举不变；样本丰富度也能提升。
- **Cons**：破坏"严格大于"的简单语义；引入额外配置项；AI 难以平衡（同强度互反容易陷入收益不明的反复反主）；与 GDD 已落定的 E3 条文相悖。
- **Rejection Reason**：规则复杂度↑、确定性↓，与项目"小步、清晰、可测试"原则冲突。

### Alternative 3：「王+对级」算独立强度但不要求同花色

- **Description**：王 + 任意 2 张同 rank 级牌（含 ♥5 + ♦5）都算 `JOKER_PAIR_RANK`。
- **Pros**：触发样本更多、AI 决策更频繁。
- **Cons**：与 `PAIR_RANK`（仅同花色）口径不一致；牌型语义混乱（双 deck 下 ♥5 + ♦5 不应被当作"对"）。
- **Rejection Reason**：违反 `PAIR_RANK` 一致性，已被用户在会话中明确否决，选择 Alternative 当前 Decision 的「严格同花色」。

## Consequences

### Positive

- 模式 B 下反主路径从 1 条（`PAIR_JOKER` 反 `JOKER_RANK`）扩展为 3 条（`JOKER_PAIR_RANK` / `PAIR_JOKER` 反 `JOKER_SINGLE_RANK`，`PAIR_JOKER` 反 `JOKER_PAIR_RANK`），博弈空间显著提升。
- 两模式形成对称三档结构，UI 教学/AI 启发式可用同一套抽象描述（"弱亮 < 强亮 < 公主"）。
- 与真实双升玩法对齐，玩家直觉一致。

### Negative

- `BidType` 枚举数值整体上移（旧 `PAIR_JOKER = 4` → `5`）——若有未走标准路径的硬编码数字，可能漏改。需要在迁移期 grep 全仓硬编码数字（应当只在测试 `assert_eq` 中出现）。
- 历史游戏日志（`game_log_*.json`）若以 `bid_type` 数字反序列化，加载后强度比较将错乱。需迁移逻辑或丢弃历史日志。

### Risks

| 风险 | 缓解 |
|---|---|
| 历史日志 replay 失效 | 在 `game_logger.gd` 加 schema_version 字段；旧日志检测到 v1 时按旧映射读取（短期），后续清理 |
| AI 在模式 B 下"憋"`JOKER_PAIR_RANK` 错过亮主时机 | `decide_bid` 启发式：若手牌已有 `JOKER_PAIR_RANK` 条件 → 直接亮；若仅有 `JOKER_SINGLE_RANK` → 按现有阈值亮；不再延迟亮主 |
| 测试 `assert_eq(bid_type, 4)` 等魔法数失效 | 全仓 grep `BidType\.|bid_type *== *[0-9]`，强制改用枚举名 |
| 与 `feature/counter-bid` 已经合并的代码产生 merge 冲突（短期内若多人协作） | 单线开发，本分支基于刚合并的 main，无并行写入风险 |

## Performance Implications

- **CPU**：`get_available_bids` 在模式 B 下每次多遍历一次 rank_per_suit 计算对级，复杂度 O(suits) ≈ O(4)，可忽略。
- **Memory**：每个 hand 多生成最多 4 个 `BidDeclaration` 候选，可忽略。
- **Load Time**：无影响。
- **Network**：项目目前单机，无影响。

## Migration Plan

1. **代码改动**（feature/bid-strength-refinement 分支）：
   - `scripts/core/trump_bidding.gd`：枚举 + `get_available_bids` 新增对级分支
   - `scripts/core/game_logger.gd`：bid_type → 字符串映射加 `JOKER_PAIR_RANK`，schema_version = 2
   - `scripts/ui/tui_game.gd`：亮主按钮文案加「王+对 ♥/♠」展示
   - `scripts/ai/ai_player.gd`：`decide_bid` 模式 B 下优先 `JOKER_PAIR_RANK`（若可），保持 `decide_counter` 取最强
2. **测试**：
   - `tests/test_trump_bidding.gd`：strength 阶梯断言、王+对级生成测试（同花色）、王+异花色对级**不**生成测试
   - `tests/test_session_controller.gd`：原 `JOKER_RANK` 用例显式重命名为 `JOKER_SINGLE_RANK`；新增「`JOKER_PAIR_RANK` 反 `JOKER_SINGLE_RANK`」反主路径
   - `tests/test_rule_config.gd`：默认值检查微调
3. **GDD 文档**：
   - `design/gdd/trump-bidding.md` §1 强度表：分别列出模式 A（3 档）/ 模式 B（3 档）/ 全 5 档对照
   - AC 增补：「`JOKER_PAIR_RANK` 反 `JOKER_SINGLE_RANK` 同花色 → 反主成功」「跨花色级牌对 → 不生成 `JOKER_PAIR_RANK`」
4. **回归**：
   - `gut_cmdln.gd` 全过（预期 ~180 条）
   - `game_session.gd --max-rounds=50 --seed=42`：观察反主分布是否多样化（预期出现 `JOKER_PAIR_RANK` 与 `PAIR_JOKER` 两种成功反主）
5. **合并策略**：fast-forward 到 main，保留每步 commit；推 origin 双分支。

## Validation Criteria

| 指标 | 预期 |
|---|---|
| GUT 测试通过率 | 100%（全部新增 + 原有迁移） |
| `game_session.gd` 50 局回归 | 0 错误 |
| 反主成功类型分布（50 局，seed=42） | 至少出现 2 种类型（`JOKER_PAIR_RANK` 反 `JOKER_SINGLE_RANK` ≥ 1 次，`PAIR_JOKER` 反任意 ≥ 1 次） |
| `BidType` 枚举里 `_bid_strength` 顺序单调 | 单元测试断言每一档 strength 严格递增 |
| `is_stronger` 同档不同花色 | 单元测试断言返回 false |

## Related Decisions

- 反主特性原始实施：[`production/sprints/counter-bid-plan.md`](../../production/sprints/counter-bid-plan.md)（v2，2026-05-18 已合并到 main）
- GDD §4 反主规则：[`design/gdd/trump-bidding.md`](../../design/gdd/trump-bidding.md)（counter-bid §5 step 7 已订正"严格大于"）
- 系统索引：[`design/gdd/systems-index.md`](../../design/gdd/systems-index.md)（C3 已标记 ✅，本 ADR 实施后会再触动 §1 强度表）
