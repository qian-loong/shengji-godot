# ADR-0003: 「对级」（PairRank）对称免疫反主

## Status

Accepted (2026-06-09)

## Date

2026-06-09

## Implementation

- `trump_bidding.can_be_countered()` **整体重写**：由"逐档加免疫的黑名单"反转为"只有单张档可反的白名单"——
  `return bid.bid_type == SINGLE_RANK or bid.bid_type == JOKER_SINGLE_RANK`。
  这一改同时表达了 ADR-0002（JPR 免疫）与本 ADR（PairRank 免疫），不再是补丁式追加分支。
- 测试：
  - `test_trump_bidding.gd` 修正 `test_joker_pair_rank_immune_to_counter`（移除"PAIR_RANK 仍可反"的过时断言）；新增 `test_pair_rank_immune_to_counter`
  - `test_session_controller.gd` 新增 `test_counter_window_skipped_on_pair_rank_bid`（与 `test_counter_window_skipped_on_joker_pair_rank_bid` 对称，含防御性 submit）
- GDD `trump-bidding.md`：§1 强度表 `PairRank` "可被反主" 改 ❌ + 新增"反主免疫总则"；§4 第 9 条推广为"对级及以上免疫"；AC8 改为对称免疫；新增 AC20；新增边界 E11；Status 加 ADR-0003 标记。

## Context

### Problem Statement

[ADR-0002](adr-0002-joker-pair-rank-counter-immunity.md) 让模式 B 的 `JOKER_PAIR_RANK`(s=4) 免疫反主，
理由是"庄家投入对子（1 王 + 2 同花色级牌）的强亮主，不应被反家 2 张同种王的公主轻易翻盘"。

但 ADR-0002 只处理了模式 B。模式 A（`bid_requires_joker = false`）下的对称档 `PAIR_RANK`(s=2)——
即"2 张同花色级牌"的对亮——当时仍标记为可被反主，会被 `PAIR_JOKER`(公主) 反掉。

这造成**两种模式的免疫规则不对称**：

| 模式 | 单张档（可反） | 对级档 | 顶档 |
|---|---|---|---|
| A（无王） | `SingleRank`(1) ✅ | `PairRank`(2) ❌→**应免疫** | `PairJoker`(5) 免疫 |
| B（带王） | `JokerSingleRank`(3) ✅ | `JokerPairRank`(4) 免疫 | `PairJoker`(5) 免疫 |

用户指出：模式 A 下的 `PairRank` 与模式 B 下的 `JokerPairRank` 是同构的"对子投入"，
ADR-0002 的逻辑应当**对称地**适用于 `PairRank`。

### Constraints

- 保持 `BidType` 5 档 strength 阶梯单调（不破坏 ADR-0001 / ADR-0002 的"严格大于"语义）
- 不引入新配置项（与 ADR-0001/0002 风格一致）
- 反主窗口 / 资格 / 次数 / 庄家不变等其他规则保持不变
- 现有反主路径测试（特别是模式 B 的 JSR/JPR 路径）必须继续通过
- 本次要求"完整重写而非补丁"——`can_be_countered` 应以一条清晰规则表达，而不是不断追加免疫分支

### Requirements

- 庄家亮 `PairRank` 后，**反主窗口直接跳过**，进入出牌阶段（与 `JokerPairRank` / `PairJoker` 行为一致）
- AI / 人类反家在 `PairRank` 局都无法发起反主请求（窗口根本不开）
- 防御层：硬塞 `submit_counter_or_pass` 在非 `counter_window` 状态下返回 `not_counter_window`（已实现，无需改动）

## Decision

将"反主免疫"规则归纳为单一总则：**只有"单张"档（`SingleRank` / `JokerSingleRank`）可被反主；
"对级"及以上（`PairRank` / `JokerPairRank` / `PairJoker`）一律免疫**，两种模式对称。

### Key Interfaces

#### `TrumpBidding.can_be_countered` 重写（白名单）

```gdscript
## Whether a winning bid can still be overturned in the counter window.
##
## Rule (ADR-0002 + ADR-0003): only the *single* entry tier of each ladder is
## counterable. The "pair" tier and everything above it is counter-immune,
## symmetrically across both bid modes:
##
##   mode A (no joker): SINGLE_RANK ✅ | PAIR_RANK ❌ | PAIR_JOKER ❌
##   mode B (joker):    JOKER_SINGLE_RANK ✅ | JOKER_PAIR_RANK ❌ | PAIR_JOKER ❌
static func can_be_countered(bid: BidDeclaration) -> bool:
	return bid.bid_type == BidType.SINGLE_RANK or bid.bid_type == BidType.JOKER_SINGLE_RANK
```

对比 ADR-0002 的实现（三个 `if ... return false` 黑名单），本 ADR 反转为白名单，
**一行即表达全部免疫规则**，且 `NONE` / 未知类型自然落入"不可反"（语义更安全）。

#### `SessionController._should_open_counter_window` 现状

`_should_open_counter_window` 已调用 `can_be_countered`，`can_be_countered` 是单一权威，
下游无需任何改动。

## Alternatives Considered

### Alternative 1：保持现状（PairRank 可被公主反）

- **Description**：只让模式 B 的 JPR 免疫（ADR-0002），模式 A 的 PairRank 仍可反。
- **Pros**：改动为零。
- **Cons**：两种模式免疫规则不对称，违反用户对"对子投入即免疫"的直觉；模式 A 玩家拿到对亮仍会被公主翻盘。
- **Rejection Reason**：用户明确要求对称。

### Alternative 2：补丁式追加 `if bid_type == PAIR_RANK: return false`

- **Description**：在 ADR-0002 的黑名单后再加一个分支。
- **Pros**：改动最小。
- **Cons**：`can_be_countered` 沦为不断增长的免疫清单，意图不清晰；用户明确要求"完整重写而非补丁"。
- **Rejection Reason**：被白名单写法取代——后者更短、更能表达"只有单张可反"的设计意图。

### Alternative 3：新增 `RuleConfig` 开关控制对称性

- **Description**：加布尔项让玩家选"对称免疫 / 仅 JPR 免疫"。
- **Pros**：灵活。
- **Cons**：配置面过载；当前为单机 MVP，规则应收敛。
- **Rejection Reason**：与 ADR-0002 Alternative 3 同理，暂不引入。

## Consequences

### Positive

- **两种模式免疫规则完全对称**："对子投入即免疫"，玩家心智模型统一
- **`can_be_countered` 表达力更强**：一行白名单胜过逐档黑名单，后续新增档位也不会默认变成可反
- **代码改动极小**：单点重写，下游自动正确

### Negative

- **模式 A 反主样本进一步减少**：`PairRank` 局不再开反主窗口（但项目默认模式 B，影响有限）
- **多数派双升玩家可能不习惯**：他们的直觉是"公主能反一切"，需在 UI/教程明示

### Risks

| 风险 | 缓解 |
|---|---|
| 反主样本减少使该特性"鸡肋" | 项目默认 `bid_requires_joker=true`（模式 B），主路径是 JSR 可反，反主仍活跃；50 局烟测验证反主成功次数无显著变化 |
| 玩家误以为可反 PairRank、报告"按钮没反应" | 窗口未开时不展示反主按钮；`submit_counter_or_pass` 返回 `not_counter_window` 明确错误 |

## Performance Implications

- **CPU**：`can_be_countered` 由最多 3 次 enum 比较降为最多 2 次，O(1)，可忽略
- **Memory / IO / Network**：无影响

## Migration Plan

1. **代码**：`scripts/core/trump_bidding.gd` — `can_be_countered` 重写为白名单
2. **测试**：
   - `test_trump_bidding.gd`：修正 `test_joker_pair_rank_immune_to_counter`；新增 `test_pair_rank_immune_to_counter`
   - `test_session_controller.gd`：新增 `test_counter_window_skipped_on_pair_rank_bid`
3. **GDD**：§1 表 + 反主免疫总则；§4 第 9 条推广；AC8 改写 + 新增 AC20 + 新增 E11；Status 加标记
4. **回归**：GUT 全过（预期 186）；`game_session.gd --max-rounds=50 --seed=42` 0 错误
5. **合并**：fast-forward 到 main，推 origin

## Validation Criteria

| 指标 | 预期 |
|---|---|
| GUT 测试通过率 | 100%（净 +2 测试，预期 186） |
| `game_session.gd` 50 局回归 | 0 错误 |
| `can_be_countered(PAIR_RANK)` | 返回 false |
| `can_be_countered(SINGLE_RANK)` | 返回 true |
| 模式 B 反主分布（seed=42） | 与 ADR-0002 后一致（本 ADR 只影响模式 A，默认配置下不触发） |

## Related Decisions

- 前置：[ADR-0001](adr-0001-bid-strength-refinement.md) — 5 档定主强度细分（Accepted）
- 前置：[ADR-0002](adr-0002-joker-pair-rank-counter-immunity.md) — JokerPairRank 免疫反主（Accepted），本 ADR 将其推广为对称规则
- GDD：[`design/gdd/trump-bidding.md`](../../design/gdd/trump-bidding.md) §1 / §4 反主规则
- 系统索引：[`design/gdd/systems-index.md`](../../design/gdd/systems-index.md)
