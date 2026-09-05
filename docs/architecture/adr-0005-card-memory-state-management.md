# ADR-0005: 记牌状态管理（CardMemory）

## Status

Accepted (2026-09-05)

## Date

2026-09-05

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | MEDIUM — 语言层确定性（`Dictionary` 遍历序、`Array.sort_custom` 稳定性、`RandomNumberGenerator`）在 4.4–4.6 无破坏性变化，但 LLM 训练数据（~4.3）对"逐字节可复现"的隐性陷阱覆盖不足 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`（无 Core/Scripting 模块参考文档，语言层确定性已由 FT1 四次复评 C4 读码验证） |
| **Post-Cutoff APIs Used** | 无（`RandomNumberGenerator`、`Array` 均为稳定 API） |
| **Verification Required** | (1) `RandomNumberGenerator` 固定 seed 逐字节可复现；(2) 决策路径无 `Dictionary` 有序遍历；(3) 所有 `sort_custom` 比较函数为全序（tie-break 到 `Card.deck_id`） |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None（架构注册表全空，本 ADR 为首个注册状态所有权者） |
| **Enables** | RNG 注入、`make_game_state()` 扩展——与 [ADR-0006](adr-0006-get-legal-plays-enumeration.md)（`get_legal_plays()` 枚举器）并列构成 S5-05 第 0 号交付物。ADR-0006 是并列前置（SMART 消费其枚举器），二者互 enable、不构成循环（都不 block 对方 Accepted） |
| **Blocks** | S5-05（FT1 SMART 模式实现）——本 ADR Accepted 前 SMART 不得动工 |
| **Ordering Note** | S5-05 Day-0 交付序列：`(1) RNG 注入 PR → (2) 抓取 AC16 黄金基准 → (3) SMART 实现 PR`。本 ADR 定义 (1)(3) 的架构，且 (1)(3) 必须独立提交（见 GDD AC16 A9 注） |

## Context

### Problem Statement

FT1 的 SMART 出牌模式（GDD `design/gdd/ai-basic.md` §4b）需要**跨墩保持的局内记牌状态**来做"铁最大"判定与喂分决策，但现有 `AIPlayer.decide_play` 是 **static 纯函数、无处存储状态**。同时，GDD 四次复评的 C1/C3/C4/R10 暴露了四个相互关联的实现前接缝：

1. **C1**：`make_game_state()`（`session_controller.gd:648`）只返回 4 字段、不含墩内进行中出牌，SMART 跟牌流水线无数据源。
2. **C3**：`decide_bid`（`ai_player.gd:55`）用全局 `randf()`，使 AC16 黄金基准在 RNG 迁移前无法逐字节复现（时序死锁）。
3. **C4**：逐字节可复现在 GDScript 层受 `Dictionary` 遍历序、`sort_custom` 不稳定、`get_sort_value` 缺全序三重威胁；现有 `ai_player.gd` 已违反（`:206/:222/:417` 遍历依赖）。
4. **R10**：`static decide_play` → 读取记牌上下文的迁移是 SMART 最重的架构选择。

GDD 已明确定义**需要什么状态与语义**（记录带 `seat_id`、按域可查询、按 `(domain,rank)` 常数时间副本计数、每墩结算后更新、`private_known_cards` 私有底牌）。**本 ADR 聚焦"如何存"的实现设计**——持有方、容器、注入方式、RNG 归属。

### Constraints

- 不做 AutoLoad——记牌是**每局状态**而非全局状态；AutoLoad 会诱导全局可变状态、破坏可测性（对齐项目"依赖注入优于单例"标准）。
- 逐字节可复现契约仅覆盖**纯 AI 对局 + 固定 seed**；含人类交互的对局不在契约内。
- 不改动 C1/F1 的牌型/牌力契约——CardMemory 只消费 C1 `get_sort_value()` 全序，不自定义主牌域拓扑。
- 现有三个测试开关（SIMPLE/MAX_STRUCTURE/DUMP_HAPPY）行为不变——迁移到实例方法后 static 基线复现仍须可用。

### Requirements

- 记牌记录须带 `seat_id` 归属与出牌顺序，支持"本墩谁在赢 / 后续座位有无对手"判定。
- 副本计数须支持按 `(domain, rank)` **常数时间**查询"未出且不在自己手里的副本数 ≥2"（铁最大判定），避免每次决策 O(已出牌数) 线性扫描。
- SMART 一切随机性只由**单一确定性注入的 RNG** 驱动，`decide_bid` 去全局 `randf()`。
- 决策路径禁止 `Dictionary` 有序遍历；所有 `sort_custom` 比较函数为全序。

## Decision

### 1. CardMemory 由 GameRound 持有（引擎侧共享公开记录）

新增 `CardMemory` 类（`RefCounted`），作为 `GameRound` 的成员。`GameRound` 是自然持有者——它已握有 `hands`、`buried_bottom`、`tricks_played`、`dealer_team`/`attack_team`、`counter_seat`（见 `game_round.gd:17-41`），CardMemory 与这些同域同生命周期（局初建、局末随 GameRound 释放）。

**已出牌记录是公开信息**——所有玩家看到同一份，故语义上是 GameRound 侧**一份共享的公开记录**，不是 3 个 AI 各持一份的私有拷贝。

### 2. 副本计数用二维计数数组（O(1) 查询/更新，避 Dictionary 不确定性）

```gdscript
class CardMemory:
    extends RefCounted

    # played_count[domain_key][rank_index] = 该 (域, rank) 已公开打出的副本数
    # domain_key: 主牌域 + 各副花色域（定长枚举）；rank_index: 定长 rank 序
    # 定长 int 数组 —— O(1) 查询/更新，无 Dictionary 遍历（避 C4 不确定性），可预分配
    var played_count: Array          # Array[Array[int]]，二维定长

    # 每条已出记录的座位归属与顺序（供"本墩谁在赢/后续有无对手"）
    # 仅当前墩需要精细顺序；跨墩累积只喂 played_count
    # 元素: { seat_id:int, cards:Array[Card], pattern, play_order:int }
    var trick_history: Array         # Array[Dictionary]，按插入序（不做有序遍历）

    ## 铁最大副本计数查询：某 (domain, rank) 未出且不在 own_hand 的副本数
    ## own_known = own_hand 中该 (domain,rank) 张数 + private_known_cards 中该项
    func remaining_copies(domain_key: int, rank_index: int, own_known: int) -> int:
        var total := 2 * deck_count            # 每 (域,rank) 物理副本上界
        return total - played_count[domain_key][rank_index] - own_known
```

铁最大判定（GDD §4b B2）："不存在更大 rank 其 `remaining_copies ≥ 2`"——纯 O(该域 rank 数) 遍历定长数组，无 Dictionary。

### 3. AIPlayer 迁移为实例方法（收纳 static var lead_strategy）

`AIPlayer` 从 static 纯函数迁移为**实例方法**。理由（GDD §R10）：`decide_play` 已 5 参，SMART 再加 `card_memory/private_known_cards/rng/team_info` → 参数爆炸；`static var lead_strategy` 已证明 static 诱导全局可变状态；有状态的 `RandomNumberGenerator` 挂 static 别扭；static 函数无法 mock/override（违反"依赖注入优于单例"）。

**迁移范围 = 全部 6 个 public static 方法**（godot 专家验证补全，非仅 `decide_play`/`decide_bid`）：`decide_bid`、`decide_counter`、`decide_bury`、`decide_play` 及其私有下游（`_decide_lead*`/`_decide_follow*`）。`decide_bury` 当前无 RNG，`decide_counter` 未来可能需要——一并迁实例以统一注入面。

```gdscript
class_name AIPlayer
extends RefCounted

var seat_id: int
var lead_strategy: LeadStrategy = LeadStrategy.SIMPLE   # 原 static var 收纳为实例成员
var card_memory: CardMemory                              # 构造注入（GameRound 共享的那一份）
var rng: RandomNumberGenerator                           # 构造注入（单局单 RNG）
var private_known_cards: Array = []                      # 配底后注入的不可变成员（见 4）

func _init(p_seat: int, p_memory: CardMemory, p_rng: RandomNumberGenerator) -> void:
    seat_id = p_seat
    card_memory = p_memory
    rng = p_rng

func decide_play(hand: Array, lead_info: Dictionary, game_state: Dictionary, rule_config: RuleConfig) -> Array:
    ...   # 读 card_memory / private_known_cards / rng，不再是 static
```

### 4. private_known_cards：配底后注入的不可变成员

`private_known_cards` 语义 = **"该 AI 确定不在任何对手手里的离场牌集合"**（GDD §States 三次复评精化）：

- **庄家**：= 自己扣入的 `buried_bottom`（8 张），配底完成时注入。
- **反主赢家**：= `apply_counter_bid` 后自己重新扣入的新 `buried_bottom`。
- **原庄家（反主成功后）**：= 空（曾扣的 8 张已被反主赢家收回，状态不再确定）。

注入时机：**配底/反主完成时**将 8 张快照注入为该 AI 的**不可变成员**（注入后不再变更），并计入 `remaining_copies` 的 `own_known`，防止庄家把自己扣的底牌误当"可能在对手手里"（否则剩余量多算最多 8 张、铁最大判定偏错）。

> **不可变性由约定+防御强制（godot 专家验证）：** GDScript 无语言级 `const` 实例成员，`var private_known_cards` 恒可变。故须 **注入时 `cards.duplicate()`**（切断外部引用）+ **注入后不暴露 setter** + **assert 只注入一次**，以约定与防御模拟不可变，而非依赖语言保证。

### 5. RNG：单局单确定性 RNG，去全局 randf()

每局一个 `RandomNumberGenerator`，seed 从局种子派生，四家 AI 共用同一实例（构造注入）。`decide_bid` 现有全局 `randf()`（`ai_player.gd:55`）迁移到 `rng.randf()`。

**tie-break 优先确定性排序**：评分平分时先按 `get_sort_value` 之和取最小（确定性），仍并列再按规范序 `sort_value → rank → suit → deck_id` 取首个——能不用 RNG 就不用。

> **共享 RNG 不变量（godot 专家验证）：** 单 RNG 跨四家共享，其逐字节可复现**仅在座位对 RNG 的调用序完全确定时成立**——即座位必须按固定顺序顺序调用（现有游戏循环顺序遍历座位，满足）。**任何未来引入并行/事件驱动 AI 调用的改动都会破坏共享 RNG 可复现**，届时须改 per-seat RNG。此不变量须在实现中保持。

### 6. game_state 扩展（C7 侧提供，本 ADR 定字段语义）

`make_game_state()` 须至少补：`current_trick_plays`（本墩已出未结算，每条 `{seat_id, cards, pattern, play_order}`）、`attack_team`/`defend_team`、累积已出牌查询入口（即 CardMemory 读取口）。字段名/容器由本 ADR 定，由 C7 侧扩展 `make_game_state()` 提供。

### Architecture Diagram

```
GameRound（每局，RefCounted）
 ├── hands / buried_bottom / tricks_played / attack_team ...（既有）
 ├── CardMemory（新增，共享公开记录）
 │    ├── played_count[domain][rank]  ← 每墩结算后推入（O(1)）
 │    └── trick_history[]             ← 当前墩座位/顺序
 ├── rng: RandomNumberGenerator（新增，单局单 seed）
 └── ai_players[4]: AIPlayer（实例方法）
      ├── card_memory ─────┐（注入 GameRound 那一份）
      ├── rng ─────────────┤（注入同一实例）
      └── private_known_cards（配底后注入的不可变快照，per-AI 非对称）

更新时机：C7 play_trick 完成 → begin_trick 之前，推入 played_count
```

### Key Interfaces

```gdscript
# CardMemory（GameRound 持有，AI 只读）
func remaining_copies(domain_key: int, rank_index: int, own_known: int) -> int   # O(1) 副本计数
func record_trick(plays: Array) -> void                                          # 每墩结算后 GameRound 调
func current_trick_winner_seat() -> int                                          # 本墩当前赢家座位

# AIPlayer（实例方法）
func _init(seat_id: int, memory: CardMemory, rng: RandomNumberGenerator) -> void
func set_private_known(cards: Array) -> void          # 配底/反主后注入，注入后不可变
func decide_play(hand, lead_info, game_state, rule_config) -> Array
```

## Alternatives Considered

### Alternative 1: AutoLoad 单例持有记牌状态
- **Description**: 记牌记录挂全局 AutoLoad，AI 直接读单例。
- **Pros**: AI 无需注入，任意处可读。
- **Cons**: 记牌是每局状态、AutoLoad 是全局单例——生命周期不匹配；诱导全局可变状态；无法在测试中隔离 mock。
- **Rejection Reason**: 违反项目"依赖注入优于单例"标准；GDD §R10 已明确否决。

### Alternative 2: static decide_play 增参 CardMemory
- **Description**: 保留 static，把 `card_memory/rng/private_known_cards/team_info` 全加为函数参数。
- **Pros**: 改动面小，不引入实例。
- **Cons**: `decide_play` 已 5 参 → 参数爆炸；有状态 RNG 挂 static 别扭；static 无法 mock/override；`static var lead_strategy` 已证明 static 诱导全局可变状态。
- **Rejection Reason**: GDD §R10 三次复评已收敛为"推荐实例方法"，static 有结构性缺陷。

### Alternative 3: Dictionary[(domain,rank)] 做副本计数
- **Description**: 键为 `(domain,rank)` 元组、值为计数。
- **Pros**: 稀疏、写法灵活。
- **Cons**: 遍历需显式排序（C4 禁令）；键哈希有开销；有序决策易踩不确定遍历序。
- **Rejection Reason**: 定长二维数组 O(1) 且天然无遍历序问题，更契合逐字节可复现契约。

## Consequences

### Positive

- SMART 记牌流水线有确定的数据源与持有方；铁最大判定 O(1)。
- 逐字节可复现契约在 GDScript 层可达（单 RNG + 无 Dictionary 有序遍历 + 全序 tie-break）。
- AI 可 mock/override，满足项目可测性标准。
- CardMemory 与 GameRound 同生命周期，无缓存失效/漂移风险（剩余量派生查询、不独立存储）。

### Negative

- `AIPlayer` 全部调用点（`game_session.gd`、`gui_game.gd`、`session_controller.gd`、测试）须从 static 调用改为实例调用——迁移面较大。
- `decide_bid` 去 `randf()` 会改变亮主序列——即使 SIMPLE 默认，同 seed 输出也会变，故 AC16 黄金基准须在 RNG 注入后重抓。
- CardMemory 增加每墩结算后一次 O(1) 推入开销（可忽略）。

### Risks

| 风险 | 缓解 |
|---|---|
| static→实例迁移漏改调用点 → 运行时错误 | grep 全部 `AIPlayer.` 调用点逐一迁移；GUT 全量回归 |
| RNG 注入改变 SIMPLE 输出 → 旧基线失效 | 三步时序：RNG 注入 PR 先合并 → 重抓黄金基准 → SMART 实现，三步独立提交 |
| private_known_cards 注入时机错（配底前/反主后未快照）→ 铁最大偏错 | 注入点严格绑定配底完成 / `apply_counter_bid` 之前快照；单测覆盖庄家/反主赢家/原庄家三场景 |
| 决策路径残留 Dictionary 有序遍历 → 非确定 | AC16 逐字节比对兜底；code review 检查 `for k in dict` 模式 |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| ai-basic.md §States | 已出记录带 seat_id、按域可查询、每墩结算后更新 | CardMemory `played_count` + `trick_history`，GameRound 持有，C7 每墩推入 |
| ai-basic.md §4b B2 | 按 `(domain,rank)` 常数时间副本计数（铁最大） | 二维计数数组 `remaining_copies()` O(1) |
| ai-basic.md §可复现契约 | 同 seed 逐字节一致、去全局 randf | 单局单注入 RNG；`decide_bid` 迁移到 `rng.randf()`；全序 tie-break |
| ai-basic.md §States A5 | 庄家/反主赢家私有底牌 private_known_cards | 配底后注入的 per-AI 不可变成员，计入 own_known |
| ai-basic.md §R10 | static→实例方法迁移 | AIPlayer 实例方法，lead_strategy 收纳为实例成员 |
| ai-basic.md §States C1 | game_state 补墩内进行中出牌 | 定义 `current_trick_plays` 等最小字段，C7 侧提供 |

## Performance Implications

- **CPU**: 铁最大 `remaining_copies` O(1)；每墩结算后一次 O(1) 推入。整体远低于 16.6ms 帧预算（2D 卡牌）。
- **Memory**: `played_count` 定长二维数组（域数 × rank 数 × int），几百字节量级；`trick_history` 每局 ≤ 墩数条。可忽略。
- **Load Time**: 无影响。
- **Network**: 不适用（本地单机）。

## Migration Plan

1. 新增 `CardMemory` 类（`src/godot/scripts/gameplay/` 或 `core/`，容器 = 二维计数数组）。
2. `GameRound` 加 `card_memory` + `rng` 成员，`setup()`/`deal()` 初始化（seed 从局种子派生）。
3. `AIPlayer` static → 实例方法：`_init(seat, memory, rng)`，`static var lead_strategy` → 实例成员，`decide_bid` 的 `randf()` → `rng.randf()`。**全部 6 个 public static 方法**（`decide_bid`/`decide_counter`/`decide_bury`/`decide_play` + 私有下游）一并迁移。
4. 全部 `AIPlayer.` 调用点（`game_session.gd`/`gui_game.gd`/`session_controller.gd` + 测试）改实例调用。**注意时序缺口**：`_apply_lead_strategy`（`game_session.gd`）在 CLI 解析时设策略、但 AIPlayer 实例每局才建——须**存储期望策略、在 `_init` 时注入**（策略先于实例存在）。
5. 配底/反主完成处注入 `private_known_cards` 快照。
6. `make_game_state()` 扩展 `current_trick_plays`/`attack_team`/CardMemory 读取口。
7. C7 `play_trick` 完成处调 `card_memory.record_trick()`。
8. 决策路径审计：消除 Dictionary 有序遍历（现有 `ai_player.gd` 至少 5 处 `for key in dict`：`:206/:210/:222/:278/:330`）、`sort_custom` 全序 tie-break 到 `deck_id`（现有 `ai_player.gd` **约 10 处** `sort_custom` lambda 全按 `get_sort_value` 单键比较、均须改全序——范围大于字面）。
9. **RNG 注入 PR 独立合并 → 抓 AC16 黄金基准 → 再做 SMART 实现**（三步独立提交）。

## Validation Criteria

| 指标 | 预期 |
|---|---|
| GUT 全量 | 100% 通过（含迁移后既有测试） |
| 三测试开关基线 | SIMPLE/MAX_STRUCTURE/DUMP_HAPPY 迁移后行为不变 |
| AC16 逐字节可复现 | RNG 注入后、固定 seed 纯 AI 对局，每墩输出哈希稳定 |
| 铁最大副本计数 | Q 对反例（GDD §4b B2）判定正确 |
| private_known_cards | 庄家/反主赢家/原庄家三场景 own_known 正确 |
| 决策路径确定性 | 无 Dictionary 有序遍历；sort_custom 全序（AST/grep 审计） |

## Related Decisions

- [ADR-0004](adr-0004-counter-bid-uses-current-round-rank.md)：反主用当前局 rank（本 ADR 的 `private_known_cards` 反主赢家场景与其 `apply_counter_bid` 时序对齐）
- GDD [`design/gdd/ai-basic.md`](../../design/gdd/ai-basic.md) §States and Transitions / §4b / §可复现契约（本 ADR 落地其状态语义）
- GDD [`design/gdd/game-state-machine.md`](../../design/gdd/game-state-machine.md) C7（`make_game_state` 扩展、`play_trick` 每墩推入的提供方）
