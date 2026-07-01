# ADR-0004: 反主时反家必须用「当前局 rank」的级牌

## Status

Accepted (2026-07-01)

## Date

2026-07-01

## Context

### Problem Statement

在两队级牌不同的场景（例如南北队打 3、东西队打 2），反主流程存在一个易被忽视的行为分歧：

- **意图**：反主是反家用"更强的手牌"接管定主，其"级牌部分"应当锚定在**当前局的级**（也即庄家所在队的级 = `state.current_rank`）
- **现状**：`session_controller.get_counter_context` 用 `state.get_team_rank_for_seat(seat)`（反家自己队级）派生 `bid_rank`，交给 `TrumpBidding.get_available_bids` 生成候选

这导致：**反家能用"自己队级"的对子反庄家"当前局级"的单张**。例如：

- 北队打 3，东西队打 2，庄家=北，庄家亮 ♦2 单（SINGLE_RANK, s=1）
- 南（反家，自己队级=3）看到候选里包含"梅花对3"（PAIR_RANK ♣, s=2）
- `is_stronger` 只比 strength（2 > 1），rank 不参与比较
- 反主成功——但用的是"3"这张对**当局无级牌意义**（当局级 = 2）的牌

在传统双升规则中，反主的合法牌型应当基于**当局级**（因为反主替代的是"定主"，定主必须用当局级）。用"自己队级"反主削弱了"级牌 = 主"的语义。

同时，`AIPlayer.decide_counter` 在 `game_session.gd` / `gui_game.gd` 调用点已经在传 `state.current_rank`——AI 侧行为与 `get_counter_context` 侧行为不一致，前者遵守传统规则，后者放宽。

### Constraints

- 不破坏 ADR-0001 的 strength 单调阶梯（`is_stronger` 仍严格按 `bid_type` 数值比较）
- 不破坏 ADR-0002 / ADR-0003 的"对级及以上免疫反主"规则
- 不影响定主流程（首局抢主、非首局定主轮询）——只作用于反主窗口
- `PAIR_JOKER`（公主）继续豁免——公主用两张同种王，本就不消耗任何 rank 牌，最高强度地位不变
- 现有游戏日志格式需向后兼容（新增字段可，破坏字段不可）

### Requirements

- 反家可用于反主的 bid 候选，其"级牌部分"的 rank 必须严格等于 `state.current_rank`
- 例外：`PAIR_JOKER` 不受此约束
- 门 1（候选生成）过滤掉不合规的候选，避免 UI 上暴露误导选项
- 门 2（提交时防御）拦截绕过 UI 手工构造的非法 declaration
- `BidDeclaration` 数据模型需显式携带 rank 信息，供门 2 校验

## Decision

### 1. `BidDeclaration` 加 rank 字段

```gdscript
class BidDeclaration:
    var seat_id: int
    var bid_type: int  # BidType
    var suit: int      # Card.Suit or -1 for 公主
    var rank: int      # Card.Rank; -1 for PAIR_JOKER (rank 无关)

    func _init(p_seat: int, p_type: int, p_suit: int, p_rank: int = -1) -> void:
        seat_id = p_seat
        bid_type = p_type
        suit = p_suit
        rank = p_rank
```

新字段默认值 `-1`，语义上表达"无 rank 概念"，专供 `PAIR_JOKER`。其他 4 档 bid 必须显式传入 `current_rank`。

### 2. `get_available_bids` 生成时写入 rank

生成 `SINGLE_RANK / PAIR_RANK / JOKER_SINGLE_RANK / JOKER_PAIR_RANK` 候选时，把入参 `current_rank` 写入 `declaration.rank`。生成 `PAIR_JOKER` 时保持 `rank = -1`。

### 3. `TrumpBidding.matches_rank` 新增

```gdscript
## 反主时用于校验：候选级牌部分是否是当前局 rank
static func matches_rank(bid: BidDeclaration, current_rank: int) -> bool:
    return bid.bid_type == BidType.PAIR_JOKER or bid.rank == current_rank
```

`is_stronger` **不变**——仍纯 strength 比较。rank 匹配是**独立**校验维度。

### 4. `SessionController.get_counter_context` 改用 `state.current_rank`

```gdscript
# 改前：反家自己队级
var bid_rank := state.get_team_rank_for_seat(seat)
# 改后：当前局 rank（庄家队级）
var bid_rank := state.current_rank
```

反家看到的候选自然过滤掉了"自己队级"的对/王+对，只保留"当前局 rank"的级牌 bid 与 `PAIR_JOKER`。

### 5. `SessionController.submit_counter_or_pass` 追加防御性 rank 校验

```gdscript
if not TrumpBidding.is_stronger(declaration, game_round.bid_declaration):
    ...
    return _error("counter_not_stronger")

# NEW: rank 匹配防御
if not TrumpBidding.matches_rank(declaration, state.current_rank):
    if logger:
        logger.log_bid_attempt(seat, "counter_rejected", "rank_mismatch")
    return _error("counter_rank_mismatch")
```

拦截"绕过 UI 直接构造 declaration"路径。

### 6. `GameLogger` 补 rank 字段

`log_bid` / `log_counter_bid` 输出中新增 `rank` + `rank_symbol` 字段。旧日志字段完全保留，仅新增字段。

### 7. `AIPlayer.decide_counter` 不改

调用方（`game_session.gd`, `gui_game.gd`）**已经在传 `state.current_rank`**，AI 一直遵守传统规则。ADR-0004 只是让 `get_counter_context` 与 AI 侧行为对齐。

### 8. 定主流程不变

`get_bidding_context.bid_rank` 保持 `state.get_team_rank_for_seat(seat)`——非首局定主时每个轮询到的玩家都用**自己队级**判定"能否定主"，这与"当局 rank 尚未确定（定主完成后才 sync）"的时序保持一致。

## Alternatives Considered

### Alternative 1：保留现状

- 现状是"反家可用自己队级反庄家当局级"，与 ADR-0001 的 strength 单调阶梯不矛盾
- **Rejection**：与传统双升"级牌 = 主"语义不符；导致反家有系统性优势（自己队级通常更高，对/王+对更容易凑）

### Alternative 2：只改门 1，不加防御性校验

- 只改 `get_counter_context.bid_rank`
- **Rejection**：任何绕过 UI 构造 declaration 的路径（AI、脚本、测试、未来 REST 接口）都能穿透。架构不完整

### Alternative 3：`is_stronger` 内联 rank 校验

- 让 `is_stronger(challenger, current, current_rank)` 同时判 strength + rank
- **Rejection**：破坏 `is_stronger` 的单一职责（"strength 严格大于"），也让签名膨胀。分成 `is_stronger` + `matches_rank` 两个独立断言更符合"每次比较只关心一件事"

### Alternative 4：定主也施加 rank 约束

- 让非首局定主的轮询玩家也只能用"当局 rank"（虽然此时 rank 尚未确定）
- **Rejection**：非首局定主时 `state.current_rank` 还没 `sync_rank_to_actual_dealer`，规则模糊；且传统玩法本就允许"用自己队级"定主

## Consequences

### Positive

- 反主行为符合传统双升"级牌 = 主"语义
- `get_counter_context` 与 `AIPlayer.decide_counter` 行为对齐（此前分歧）
- `BidDeclaration.rank` 显式化后，日志/审计/未来功能都能读到 rank 信息，不再靠"隐式"约定
- 门 1 + 门 2 双重防御，架构完整

### Negative

- `BidDeclaration` 构造点全数需增补 `rank` 参数（生产代码 5 处、测试代码 ~22 处）
- 反主频率会**显著下降**——反家很少积攒庄家队级牌，尤其两队级差距大时。这本身是规则收紧的自然结果，不是 bug
- 若人机对战中人类反家没有当局 rank 的对/王+对，只能靠公主反主

### Risks

| 风险 | 缓解 |
|---|---|
| 测试构造点漏改 rank，默认 -1 导致门 2 拒绝 → 测试红 | 全数显式传 rank；GUT 跑完全量确认 |
| 现有测试依赖"反家用自己队级反主"→ 语义变形 | 逐个审计现有反主测试，team_ranks 对齐或改用 `PAIR_JOKER` 反主 |
| 反主频率下降可能影响 50 局回归的样本多样性 | 观察 headless 烟测反主分布；若极端稀疏可考虑给 AI 增补公主偏好 |
| 日志 schema 升级：`rank` 字段旧日志不存在 | GameLogger 现无 schema_version 差异化解析器；HTML 分析器缺 rank 时应静默；老日志读取时字段可选 |

## Performance Implications

- `matches_rank` 是常数比较，O(1)
- `get_available_bids` 生成 declaration 时多一个字段赋值，可忽略
- `submit_counter_or_pass` 多一次 O(1) 校验
- 无 IO / 网络 / 内存开销

## Migration Plan

1. **数据模型**：`BidDeclaration` 加 `rank` 字段（默认 -1）
2. **生成层**：`get_available_bids` 5 处 append 全部补 rank
3. **判定层**：新增 `matches_rank` 静态方法
4. **控制器**：`get_counter_context.bid_rank` 改用 `state.current_rank`；`submit_counter_or_pass` 追加 rank 校验
5. **日志层**：`log_bid` / `log_counter_bid` dump rank + rank_symbol
6. **测试改动**：
   - `test_trump_bidding.gd`：所有构造点补 `R.FOUR`（该文件默认 current_rank=4）
   - `test_session_controller.gd`：所有反主构造点补 `R.TWO`（默认 team_ranks=[2,2]）；跨 rank 场景（如 `test_counter_preserves_dealer_lead_rank` team_ranks=[8,5]）显式补 current_rank
7. **新增测试**（4 条）：
   - `test_counter_rejected_when_rank_differs_from_current_round`（跨 rank 场景，反家用自己队级 → 拒）
   - `test_counter_accepted_when_rank_matches_current_round`（跨 rank 场景，反家用当前局 rank → 成）
   - `test_counter_pair_joker_exempt_from_rank_constraint`（跨 rank 场景，公主豁免）
   - `test_matches_rank_helper`（`TrumpBidding.matches_rank` 单元测试）
8. **GDD 文档**：`design/gdd/trump-bidding.md` §4 第 3 条加 rank 约束条文；AC7 补充；新增 AC21 / AC22 / AC23
9. **回归**：GUT 全量 + headless 50 局烟测 + 反主分布抽样

## Validation Criteria

| 指标 | 预期 |
|---|---|
| GUT 测试通过率 | 100% |
| 现有反主测试 | 全部保持通过（可能需要改 team_ranks 使 current_rank 匹配 declaration.rank） |
| 新增 4 条测试 | 全部通过 |
| headless 50 局回归 | 0 error / 0 assert；反主发生率允许下降 |
| 反主分布 | 至少 1 次 `PAIR_JOKER` 反 `SINGLE_RANK` / `JOKER_SINGLE_RANK`（公主豁免路径仍活跃） |
| 日志字段 | `bid.rank` / `bid.rank_symbol` / `counter_bid_history[*].rank` 全部有值（PAIR_JOKER 除外） |

## Related Decisions

- [ADR-0001](adr-0001-bid-strength-refinement.md)：5 档 strength 阶梯（本 ADR 保留其 `is_stronger` 语义）
- [ADR-0002](adr-0002-joker-pair-rank-counter-immunity.md)：JOKER_PAIR_RANK 免疫反主（本 ADR 不改变）
- [ADR-0003](adr-0003-pair-rank-counter-immunity.md)：PAIR_RANK 对称免疫反主（本 ADR 不改变）
- GDD [`design/gdd/trump-bidding.md`](../../design/gdd/trump-bidding.md) §4 反主规则（本 ADR 落地时更新第 3 条 + AC）
