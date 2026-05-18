# ADR-0002: 「王+对级」（JokerPairRank）免疫公主反主

## Status

Proposed

## Date

2026-05-18

## Context

### Problem Statement

[ADR-0001](adr-0001-bid-strength-refinement.md) 把模式 B 的定主声明拆为 `JOKER_SINGLE_RANK`(s=3) 与 `JOKER_PAIR_RANK`(s=4) 两档，并保留 `PAIR_JOKER`(s=5) 作为最高档。当前 `is_stronger` 严格按 strength 比较，因此 `PAIR_JOKER` 仍可反 `JOKER_PAIR_RANK`。

ADR-0001 上线后 50 局烟测中此路径触发了 1 次（搭档(北) 公主反 ♦ 王+对），引发了一个直觉问题：

> **庄家投入 3 张关键牌（1 王 + 2 同花色级牌）凑到「王+对级」的强亮主，反家用 2 张同种王就能把它反掉，这合理吗？**

正反观点（详见 [bid-strength worktree 会话](eb35a9d6-df84-4e0f-8ed9-351b625209e7) 的讨论）：

| 角度 | 支持现状（公主无差别压制） | 支持本 ADR（JPR 免疫公主反主） |
|---|---|---|
| 传统玩法 | 多数双升地方版本：公主作为顶级声明可压一切非公主声明 | 部分严格版本：「王+对级」是"反公主防线"（即"大亮"） |
| 牌张投入 | 公主需双小王或双大王对子，已极稀有 | 庄家用 3 张关键牌，反家仅 2 张牌就压下去，"以少胜多"违和 |
| 设计价值 | 简单一致：strength 阶梯单调即真理 | 让 JPR 拥有不可替代的设计意义——鼓励玩家在拿到「王+对级」时大胆亮主，不被"等公主"绑架 |
| 反主收益 | 公主局下双王是绝对最大牌，反主翻盘性强 | 庄家原 3 张主牌在公主局下仍全是主，"反主收益"虚高 |

用户决策（"我也倾向 B"）：让「王+对级」成为公主拦截器。

### Constraints

- 必须保留 `BidType` 5 档 strength 阶梯单调（不破坏 ADR-0001 的"严格大于"语义）
- 不引入新的配置项（保持规则简洁，与 ADR-0001 风格一致）
- 反主窗口 / 资格 / 次数等其他规则保持不变
- 所有现有测试（特别是 ADR-0001 新增的反主路径）必须继续通过

### Requirements

- 庄家亮 `JOKER_PAIR_RANK` 后，**反主窗口直接跳过**，进入出牌阶段（与 `PAIR_JOKER` 行为一致）
- AI / 人类反家在 `JOKER_PAIR_RANK` 局都无法发起反主请求（窗口根本不开）
- 防御层：即便有人在 `current_phase != counter_window` 状态下硬塞 `submit_counter_or_pass`，也能正确返回 `not_counter_window` 错误（已实现，无需改动）

## Decision

将不可被反主的档位从 1 档（`PAIR_JOKER`）扩展为 2 档（`PAIR_JOKER` + `JOKER_PAIR_RANK`）。

### Key Interfaces

#### `TrumpBidding.can_be_countered` 改动

```gdscript
## Check if a bid can be countered.
## ADR-0002: PAIR_JOKER (公主) AND JOKER_PAIR_RANK (王+对) are both immune to counter.
##   - PAIR_JOKER: highest strength tier, no stronger bid exists.
##   - JOKER_PAIR_RANK: only PAIR_JOKER would be strictly stronger by enum value;
##                     by ADR-0002 we shield it as well, making JPR a "counter-shield"
##                     for players who invest 3 key cards (joker + same-suit pair).
static func can_be_countered(bid: BidDeclaration) -> bool:
	if bid.bid_type == BidType.PAIR_JOKER:
		return false
	if bid.bid_type == BidType.JOKER_PAIR_RANK:
		return false
	return true
```

#### `SessionController._should_open_counter_window` 现状

```gdscript
func _should_open_counter_window() -> bool:
	# Already calls TrumpBidding.can_be_countered — no change needed.
	if not TrumpBidding.can_be_countered(game_round.bid_declaration):
		return false
	# ... other gates (first game, no_bid, counter_attempted)
```

`SessionController` 不需要任何改动；`can_be_countered` 是单一权威。

### State Diagram (no change)

```
非首局：Idle → Bidding → Resolved → CounterWindow → Final           （所有反家 pass）
                                  → CounterWindow → Countered → ...   （反主成功）

ADR-0002 之后：庄家亮 JPR 时 _should_open_counter_window() = false，
              直接 Resolved → Final，CounterWindow 不会被开启。
```

## Alternatives Considered

### Alternative 1：保持现状（公主可反 JPR）

- **Description**：不改任何代码，保留 ADR-0001 的实现。
- **Pros**：5 档阶梯单调最简洁，"严格大于"语义无例外。
- **Cons**：JPR 失去独立的设计价值——理性玩家发现「拿到 JPR 还会被公主反掉」后会更倾向"等公主"，回到 ADR-0001 想解决的同质化问题。
- **Rejection Reason**：用户讨论后明确倾向给 JPR 设置反主屏障。

### Alternative 2：JPR 与 PAIR_JOKER 平级（同 strength=5）

- **Description**：把 `JOKER_PAIR_RANK` 与 `PAIR_JOKER` 都设为 strength = 5（或新枚举），互相不可反，靠抢主先后顺序决定谁定主。
- **Pros**：在阶梯顶端形成"双雄"；理论上等价。
- **Cons**：破坏 ADR-0001 的单调阶梯；`is_stronger` 需要特例化（同 strength 也算"不更强"，而某些路径可能误用 `>=`）；测试与 GDD 都要重写一大块。
- **Rejection Reason**：复杂度↑、与 ADR-0001 阶梯设计冲突；用户未选此方案。

### Alternative 3：新增 `RuleConfig.joker_pair_rank_blocks_pair_joker` 配置项

- **Description**：在 `RuleConfig` 加布尔开关，玩家可选择"传统多数派（公主无差别压制）"或"严格少数派（JPR 免疫）"两套规则。
- **Pros**：灵活，兼顾两种偏好；规则学习者可对照。
- **Cons**：增加配置面；规则配置已经较多（`bid_requires_joker` / `trump_joker_color_match` / `joker_always_trump` / ...），再加一个会让 `RuleConfig` 表过载；测试矩阵×2。
- **Rejection Reason**：项目当前是单机 MVP，规则配置应保持收敛；如未来真有需要可由本 ADR 升级而来（而非从一开始引入）。

## Consequences

### Positive

- **JPR 拥有不可替代的设计价值**——拿到「王+对级」就是"压顶"，不再被任何反主翻盘
- **公主与 JPR 形成"双顶档"**：公主是严格最高强度（5 仍是最大），JPR 是顶级反主免疫（s=4 但不可反）。双方各有特权，鼓励玩家在不同手牌下做出不同决策
- **代码改动极小**：单点改 `can_be_countered`，下游 `SessionController._should_open_counter_window` 自动正确

### Negative

- **多数派双升玩家可能不习惯**——他们的直觉是"公主能反一切"。需要在 UI/教程中明示规则
- **公主局相对稀有度上升**——以前公主可以反 JPR 抢回主控权，现在 JPR 局公主即便发牌时拿到也只能"等下一局"
- **历史日志（v2 schema）的语义不变**——但实战表现会有差异，跨版本对局回放可能与新规则下决策不一致

### Risks

| 风险 | 缓解 |
|---|---|
| 反主样本急剧减少，反主特性变得"鸡肋" | 在新一轮 50 局烟测中验证：反主成功次数应仍 ≥4 次（PAIR_JOKER 反 JOKER_SINGLE_RANK 路径仍开放），否则需要重新考量 |
| 玩家在 UI 中误认为可对 JPR 发起反主、报告"按钮没反应"bug | TUI / UI 层在反主窗口未开时根本不展示反主按钮（已有逻辑），且 `submit_counter_or_pass` 在错误 phase 下返回 `not_counter_window` 明确错误 |
| 与 ADR-0001 配套的"反主类型分布多样化"目标退化 | 在新 50 局回归中明确观察分布。预期至少剩 2 种成功类型（PJ 反 JSR、JPR 不再被反但 JPR 自己仍是反主主力之一） |

## Performance Implications

- **CPU**：`can_be_countered` 多一次 enum 比较，O(1)，可忽略
- **Memory / IO / Network**：无影响

## Migration Plan

1. **代码改动**（feature/joker-pair-rank-immune 分支）：
   - `scripts/core/trump_bidding.gd`：`can_be_countered` 加 `JOKER_PAIR_RANK` 分支
2. **测试**：
   - `tests/test_trump_bidding.gd`：新增 `test_can_be_countered_joker_pair_rank_immune`
   - `tests/test_session_controller.gd`：新增 `test_counter_window_skipped_on_joker_pair_rank_bid`（与现有 `test_counter_window_skipped_on_pair_joker_bid` 对称）
3. **GDD 更新**：
   - `design/gdd/trump-bidding.md` §1 强度表："可被反主" 列：`JokerPairRank` 由 ✅ 改为 ❌（带 ADR-0002 注释）
   - §4 反主规则增第 9 条：「**「王+对级」不可反**：`JokerPairRank` 与 `PairJoker` 同样作为顶级声明的一部分免疫反主」
   - AC9（公主不可反）扩展为同时覆盖 PAIR_JOKER 与 JOKER_PAIR_RANK
   - 新增 AC19：「庄家亮 `JokerPairRank ♥` → 不开反主窗口」
4. **回归**：
   - `gut_cmdln.gd` 全过（预期 184）
   - `game_session.gd --max-rounds=50 --seed=42`：观察反主分布——预期 PJ 反 JPR 这一种类型消失（0 次），其他路径不受影响
5. **合并策略**：fast-forward 到 main，保留每步 commit；推 origin 双分支。

## Validation Criteria

| 指标 | 预期 |
|---|---|
| GUT 测试通过率 | 100%（新增 2 测试） |
| `game_session.gd` 50 局回归 | 0 错误 |
| `PAIR_JOKER 反 JOKER_PAIR_RANK` 次数（seed=42） | **0 次**（pre-ADR-0002 是 1 次） |
| `PAIR_JOKER 反 JOKER_SINGLE_RANK` 次数 | 不显著下降（应仍 ≥3 次） |
| `JOKER_PAIR_RANK 反 JOKER_SINGLE_RANK` 次数 | 不变（应仍 ≥4 次，与 ADR-0002 无关） |
| `can_be_countered(JOKER_PAIR_RANK)` 单元测试 | 返回 false |

## Related Decisions

- 前置：[ADR-0001](adr-0001-bid-strength-refinement.md) — 5 档定主强度细分（Accepted）
- GDD：[`design/gdd/trump-bidding.md`](../../design/gdd/trump-bidding.md) §4 反主规则
- 系统索引：[`design/gdd/systems-index.md`](../../design/gdd/systems-index.md)
