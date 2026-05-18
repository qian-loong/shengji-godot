# 反主流程实施方案 — Counter-Bid Plan

> **Status**: Draft (v2)
> **Branch**: `feature/counter-bid`
> **Worktree**: `D:/WorkDir/counter-bid`
> **Scope**: 实现 C3 反主流程，收掉 sprint-002 S2-03 与 `session-controller-refactor-plan.md` 中的 TODO
> **Created**: 2026-05-17
> **Revised**: 2026-05-18（D3 重写：庄家手牌不动，buried_bottom 直接转给反家）
> **Implements**: GDD `design/gdd/trump-bidding.md` §4 反主规则
> **Out of Scope**: TUI 集成（留下个 PR 再做）

---

## 1. 设计决策

### D1. 反主成功不更换庄家

按规则，庄家位置由"上局结果"或"无法定主轮转"确定，反主只是改变了主花色与底牌内容，**不应让庄家因反主而下台**。

因此反主成功后：

- `dealer_seat` **保持不变**
- `dealer_team` / `attack_team` **保持不变**
- `current_lead_seat` **保持不变**（自然，因为 dealer 没动）
- `state.current_rank` **保持不变**（GDD §4.5 已规定）
- 仅 `bid_declaration`、`trump_suit` 被替换；底牌由反家重选

### D2. GDD 文字需同步修改

`design/gdd/trump-bidding.md` §4 中两处描述与新行为不一致，**实施时一并订正**：

- §4.6 「反主成功后，反家获得底牌重新配底（C4）」 → 补充：「**庄家不变**；庄家原扣下的 8 张底牌直接转给反家作为新底，反家从'自己手牌 + 这 8 张'共 33 张中选 8 张埋。反家所埋的牌进入 `buried_bottom`，结算扣底逻辑不变」
- §4.7 「先手不变：配底完成后，先手权仍归**原**庄家」 → 改为：「**庄家与先手权均保持**；反主只改变 `trump_suit` 与底牌内容」（删去暗示有"新庄家"的"原"字）

GDD 状态机表格同步：删除 `Countered` 状态中"反家重新配底中"的"反家"措辞，改为"反家完成 re-bury 中"——避免误读为反家临时坐庄。

### D3. 反家 re-bury：庄家手牌不动，复用现有 bury 流程

反主成功瞬间的牌堆变化：

| 角色 | 手牌 | 备注 |
|---|---|---|
| 庄家 | **25 张不动** | 庄家已经做出过弃 8 决策，反主不应让庄家"反悔" |
| 反家 | **25 张**（自己原有） | 不动 |
| `bottom`（GameRound） | 原 `buried_bottom`（庄家弃的 8 张） | **由 buried_bottom 直接转过来** |
| `buried_bottom` | `[]` | 清空，等反家选 8 张埋 |

反家 re-bury 流程**与庄家原 bury 完全同形**：

- 反家可见手牌 = `BottomManager.reveal_bottom(hands[counter_seat], bottom)`（25 + 8 = 33）
- 反家选 8 张 → `BottomManager.bury_bottom(merged, indices, 8)` → `buried_bottom`、新 25 张手牌

**实现上引入 `bury_seat` 字段**（默认 `= dealer_seat`），让 `GameRound.execute_bury()` 与 `get_dealer_hand_with_bottom()` 都通过 `bury_seat` 取手牌。反主时只把 `bury_seat = counter_seat`，**`execute_bury` 一行不改，TUI 33 选 8 交互一字不改**。

### D4. 一局至多一次反主

由 `state.counter_attempted: bool` 守门：

- counter_window 进入前检查；若已 attempted（理论上不会，因为成功后立即设 true）则跳过
- counter_window 结束（pass 完所有反家 / 反主成功）一律置 true
- 反家 bury 完成后回到 playing；不再开第二次 counter_window
- 每局 `state.begin_round_for_current_dealer()` 时 reset

### D5. 范围控制

- 控制器逻辑、`GameRound` 支持、AI 决策、测试、`game_session.gd` 自动跑局集成 → **本次包含**
- `tui_game.gd` UI 集成 → **本次不做**，留 short-circuit；TUI 在 counter_window 阶段自动 pass，sprint-002 S2-09 自动模式不受影响

---

## 2. 状态机

```
旧：bidding -> burying -> playing
新：bidding -> burying -> counter_window -> playing
                                          ↓ (反主成功)
                                          burying(again, by counter_seat) -> playing

跳过 counter_window 的条件（任一成立即跳过）：
  - state.is_first_game = true
  - game_round.bid_declaration = null（公主局／无人定主）
  - not TrumpBidding.can_be_countered(bid_declaration)（PairJoker）
  - state.counter_attempted = true
```

注意：**`current_phase` 不引入 `re_burying`**——反家 re-bury 复用 `burying` 阶段，区分由 `state.counter_attempted` 担任：

- `submit_bury` 完成时：若 `counter_attempted == false` → 进 `counter_window`（或 playing）；若 `== true` → 直接 `playing`（反家已 bury 完）

---

## 3. 文件改动清单

### 3.1 `src/godot/scripts/gameplay/session_state.gd`

新增字段：

```gdscript
var counter_attempted: bool = false
```

`begin_round_for_current_dealer()` 内置零：`counter_attempted = false`

### 3.2 `src/godot/scripts/gameplay/session_controller.gd`

**新增成员**：

```gdscript
var counter_seat_index: int = 0
var counter_seat_order: Array[int] = []
```

**修改 `submit_bury(indices)`**：成功后根据 `state.counter_attempted` 分流：

```gdscript
if not state.counter_attempted:
    return _open_counter_window_or_play()
else:
    current_phase = "playing"
    return _ok({...})
```

**修改 `get_bury_context()`**：返回字段中 `dealer` 改为 `bury_seat`（或并存）——让 host 知道现在是谁要 bury。

**新增方法**：

- `_open_counter_window_or_play() -> Dictionary`
- `_should_open_counter_window() -> bool`：见 §2 跳过条件
- `get_current_counter_seat() -> int`
- `get_counter_context(seat) -> Dictionary`：返回 hand、当前 bid、available_counter_bids（强度严格大于）
- `submit_counter_or_pass(seat, declaration, pass_reason) -> Dictionary`
  - 校验 seat 属于 attack team 且等于 `get_current_counter_seat()`
  - declaration != null：校验 `TrumpBidding.is_stronger(declaration, current_bid)` → 调 `_apply_counter()`
  - declaration == null（pass）：`counter_seat_index += 1`，超界则 `_finish_counter_window_no_change()`
- `_apply_counter(declaration)`：
  - 调 `game_round.apply_counter_bid(declaration)`
  - `state.counter_attempted = true`
  - `current_phase = "burying"`（让反家走和庄家相同的 bury 路径）
- `_finish_counter_window_no_change()`：
  - `state.counter_attempted = true`
  - `current_phase = "playing"`

### 3.3 `src/godot/scripts/gameplay/game_round.gd`

**新增字段**：

```gdscript
var bury_seat: int = 0
var counter_seat: int = -1
```

**`setup()` 末尾**：`bury_seat = dealer_seat`

**`process_bid(declaration)`**：现有逻辑会在首局 bid 时把 `dealer_seat = declaration.seat_id`；同步加一行 `bury_seat = dealer_seat` 保持一致。`set_no_bid_default(human_seat)` 同样补一行。

**改造现有方法用 `bury_seat`**（语义上更准确，行为不变）：

```gdscript
func get_dealer_hand_with_bottom() -> Array:
    return BottomManager.reveal_bottom(hands[bury_seat], bottom)

func execute_bury(selected_indices: Array[int]) -> Dictionary:
    var merged := get_dealer_hand_with_bottom()
    var result := BottomManager.bury_bottom(merged, selected_indices, rule_config.bottom_size)
    if result["ok"]:
        hands[bury_seat] = result["new_hand"]
        buried_bottom = result["buried"]
        if logger:
            logger.log_bury(merged, selected_indices, buried_bottom, hands[bury_seat])
    return result
```

> 注：`get_dealer_hand_with_bottom` 名字保留以减少调用方改动；语义上变成"当前 bury 者的手 + 当前 bottom"。

**新增 `apply_counter_bid(declaration)`**（核心，仅 ~10 行）：

```gdscript
func apply_counter_bid(declaration: TrumpBidding.BidDeclaration) -> void:
    var prev_trump := trump_suit
    bottom = buried_bottom.duplicate()
    buried_bottom = []
    bid_declaration = declaration
    trump_suit = declaration.suit
    counter_seat = declaration.seat_id
    bury_seat = declaration.seat_id
    if logger:
        logger.log_counter_bid(declaration, prev_trump)
```

**结算路径不变**：`calculate_settlement` 仍用 `dealer_seat` 判定 attack/dealer team。

### 3.4 `src/godot/scripts/core/game_logger.gd`

仅新增 1 个事件方法（`log_bury` 复用反家 re-bury，**不需要新方法**）：

- `log_counter_bid(declaration, original_trump_suit)`：日志一行 `"counter_bid"` 事件。HTML 日志分析器若不识别该事件应静默跳过，不需要立即更新分析器。

### 3.5 `src/godot/scripts/ai/ai_player.gd`

新增方法：

```gdscript
static func decide_counter(
    seat_id: int,
    hand: Array,
    current_rank: int,
    current_bid: TrumpBidding.BidDeclaration,
    rule_config: RuleConfig
) -> TrumpBidding.BidDeclaration:
    # 取所有可用 bid
    # 过滤出 is_stronger(b, current_bid) 严格成立的
    # 选最强者
    # 复用 trump_strength >= 4 启发式（与 decide_bid 一致）
    # 否则返回 null（pass）
```

`decide_bury()` 已是无关 seat 的纯函数，**反家 re-bury 直接复用**。

### 3.6 `src/godot/scripts/gameplay/game_session.gd`

在调 `submit_bury` 后追加 counter_window 处理段：

```gdscript
while session_controller.current_phase == "counter_window":
    var seat := session_controller.get_current_counter_seat()
    var ctx := session_controller.get_counter_context(seat)
    var decl := AIPlayer.decide_counter(
        seat, ctx["hand"], state.current_rank, ctx["current_bid"], rule_config
    )
    session_controller.submit_counter_or_pass(seat, decl)

if session_controller.current_phase == "burying" and state.counter_attempted:
    var rb_ctx := session_controller.get_bury_context()
    var indices := AIPlayer.decide_bury(
        rb_ctx["merged_hand"], rule_config.bottom_size,
        game_round.trump_suit, state.current_rank, rule_config
    )
    session_controller.submit_bury(indices)
```

### 3.7 `src/godot/scripts/ui/tui_game.gd`

**本次仅加防御**：在阶段 `counter_window` 出现时，记录一条日志「Counter window TODO — TUI 未实现，本局自动 pass 反主」，循环对每个反家调 `submit_counter_or_pass(seat, null)` 直到 phase 退出为 `playing`。

### 3.8 `src/godot/tests/test_session_controller.gd`

新增 9 个测试用例，对应 GDD AC7-AC11：

| 测试 | 验证 GDD AC | 概述 |
|---|---|---|
| `test_counter_window_skipped_on_first_game` | — | 首局 `is_first_game=true`，bury 后直接 playing |
| `test_counter_window_skipped_on_pair_joker_bid` | AC9 | 公主 bid 不可被反 |
| `test_counter_window_skipped_on_no_bid` | — | 无人定主局，无反主 |
| `test_counter_succeeds_with_stronger_bid` | AC7 | SingleRank -> PairRank 反主成功 |
| `test_counter_rejected_with_equal_strength` | AC3（边界） | 强度相等不可反 |
| `test_counter_rejected_with_weaker_bid` | AC8 | 强度更弱不可反 |
| `test_counter_rejected_from_dealer_team` | AC10 | dealer 搭档不能反 |
| `test_counter_at_most_once_per_round` | — | 反主成功后再走一遍流程：counter_window 不再开 |
| `test_counter_preserves_dealer_lead_rank` | AC11（修订） | dealer_seat、current_lead_seat、current_rank 都不变 |

可选追加：
- `test_counter_re_bury_uses_dealer_buried_as_new_bottom`：反家可见 33 张 = 自己 25 + 庄家弃的 8。

---

## 4. 改动规模

| 文件 | 性质 | 估算 LOC |
|---|---|---:|
| `session_state.gd` | 新增字段 + 重置 | ~5 |
| `session_controller.gd` | 修改 + 新方法 | ~85 |
| `game_round.gd` | 引入 `bury_seat` + `apply_counter_bid` | ~25 |
| `game_logger.gd` | 新增 `log_counter_bid` | ~10 |
| `ai_player.gd` | 新增 `decide_counter` | ~25 |
| `game_session.gd` | 修改集成 | ~25 |
| `tui_game.gd` | 防御性 short-circuit | ~10 |
| `test_session_controller.gd` | 新测试 | ~180 |
| `design/gdd/trump-bidding.md` | 文字订正 §4.6/4.7 + 状态机表格 | ~8 |
| **合计** | | **~373 LOC** |

---

## 5. 实施顺序（推荐 commit 分块）

1. **GameRound 重构**：引入 `bury_seat` 字段，`execute_bury`/`get_dealer_hand_with_bottom` 改用之；`apply_counter_bid` 新增；`game_logger.log_counter_bid` 新增。
   验收：现有 117 个测试全 pass（重构前后行为等价）。
2. **SessionState.counter_attempted** + **SessionController** counter_window 方法骨架（不接 host）。
3. **9 个 `test_session_controller.gd` 测试**（先红后绿）。
4. **`AIPlayer.decide_counter`**。
5. **`game_session.gd` 自动模式集成**：跑 100 局自动对局，验证无 assert/异常、无重复牌/丢牌。
6. **`tui_game.gd` short-circuit 防御**。
7. **GDD 文字订正** §4.6/§4.7 + 状态机表格。
8. **状态收尾**：sprint-002 中 S2-03 状态 ⏳ -> ✅；systems-index 中 C3 状态 🚧 -> ✅。

每步独立 commit，方便 review/回滚。

---

## 6. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| `bury_seat` 重构遗漏调用点（如 host 直接读 `dealer_seat` 用于 bury UI 标题） | 中 | TUI 显示错座位 | 第 1 步重构时 grep 全部 `dealer_seat` 引用，明确"当前 bury 者"和"庄家身份"两种语义 |
| `apply_counter_bid` 后牌堆校验失败（重复牌/丢牌） | 低 | 后续 bury 异常 | 方法末尾加 invariant：`assert(bottom.size() == rule_config.bottom_size && buried_bottom.is_empty())` |
| 日志格式变化导致 HTML 日志分析器（S2-08 引入）失效 | 低 | 复盘工具坏 | 仅追加 `counter_bid` 事件类型，不改既有事件；分析器若不识别应静默跳过 |
| `decide_counter` 启发式过于激进，AI 频繁反主导致测试不稳定 | 低 | 测试随机失败 | `trump_strength >= 4` 同 `decide_bid`；测试中固定 seed |
| TUI short-circuit 让人类玩家以为反主已实现 | 低 | 用户体验误解 | TUI 日志面板明确显示「反主功能 TUI 集成待 sprint-3」 |

---

## 7. 验收

- 117 个原有测试 + 9 个新增测试 全部通过
- `game_session.gd` 自动模式跑 100 局无 assert/异常
- 反主成功局：手牌总数恒定（4 × 25 = 100）+ buried_bottom 8 + bottom 0
- HTML 日志分析器仍可解析新对局日志（即使不识别 counter_bid 事件）
- GDD §4 文字与代码行为一致
