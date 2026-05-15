# F3 规则配置系统

> **Status**: Designed
> **Author**: user + game-designer
> **Last Updated**: 2026-04-06
> **Implements Pillar**: 支柱 2（规则即策略）

## Overview

**规则配置系统**是所有可变规则参数的单一来源（Single Source of Truth）。它定义每条规则的参数名、类型、默认值和有效范围，并在对局开始前向所有消费系统（C1、C2、C3、C6 等）提供当前规则快照。

本系统不执行任何游戏逻辑——它只负责"当前这局的规则是什么"。规则如何影响出牌、亮主、结算，由各消费系统自行根据配置值执行。

本系统是支柱 2（规则即策略）的直接载体：每一条配置项都应对博弈策略产生可见影响。

## Player Fantasy

规则配置系统面向的玩家体验是**掌控感**——"这是我的牌桌，规则我说了算"。玩家在开局前调整参数时，应感受到自己在定义一个独特的博弈空间，而不是在填一张无聊的表单。

对于核心玩家，配置界面本身就是乐趣来源之一：尝试不同规则组合、观察它们如何改变对局节奏与策略——这正是"规则实验室"体验的入口。

## Detailed Design

### Core Rules

#### 1. 规则快照 (RuleConfig)

规则配置系统在对局开始前生成一份不可变的规则快照（RuleConfig），对局期间所有系统只读取该快照，不允许中途修改。

#### 2. 完整参数表

**2.1 牌组相关（消费者：F1、F2）**

| 参数名 | 类型 | 默认值 | 有效值 | 说明 |
|--------|------|--------|--------|------|
| `deck_count` | int | 2 | 1, 2 | 副牌数量 |
| `current_rank` | Rank | 2 | 2–A | 当前级牌点数 |
| `hand_size` | int | 25 | 只读，由 deck_count 派生 | 每人手牌数（2副=25，1副=12） |
| `bottom_size` | int | 8 | 只读，由 deck_count 派生 | 底牌张数（2副=8，1副=6） |

派生公式：
- 2 副：`108 = 25×4 + 8`
- 1 副：`54 = 12×4 + 6`

**2.2 主牌相关（消费者：C1、C3）**

| 参数名 | 类型 | 默认值 | 有效值 | 说明 |
|--------|------|--------|--------|------|
| `trump_mode` | enum | Bid | Bid / Grab / Counter / Fixed / NoTrump | 主牌产生方式 |
| `fixed_trump_suit` | Suit? | null | ♠♥♦♣ 或 null | 仅 `trump_mode = Fixed` 时生效 |
| `joker_always_trump` | bool | true | — | 大小王是否永远为主 |
| `trump_joker_color_match` | bool | true | — | 亮主时王的颜色须与级牌花色颜色一致才能定主 |
| `bid_requires_joker` | bool | true | — | 是否需要王才能定主。false 时级牌单独可定主 |

**2.3 出牌相关（消费者：C2）**

| 参数名 | 类型 | 默认值 | 有效值 | 说明 |
|--------|------|--------|--------|------|
| `allow_dump` | bool | true | — | 是否允许甩牌 |
| `strict_follow_structure` | bool | true | — | 跟牌是否必须严格匹配首出的牌型结构 |
| `four_same_is_tractor` | bool | false | — | 4 张相同牌是否算拖拉机 |
| `tractor_allow_rank_card` | bool | true | — | 拖拉机是否允许级牌参与 |

**2.4 结算相关（消费者：C6）**

| 参数名 | 类型 | 默认值 | 有效值 | 说明 |
|--------|------|--------|--------|------|
| `upgrade_threshold` | int | 80 | 0–200 | 攻方得分达到此值即可升级 |
| `upgrade_step` | int | 1 | 1–3 | 每次升级跳几级 |
| `upgrade_table` | Array | `[[0,0,3],[1,0,2],[40,0,1],[80,1,0],[120,1,1],[160,1,2],[200,1,3]]` | 按分值升序 | 结算阶梯：`[最低分, 升级方(0庄/1攻), 升级级数]` |
| `no_skip_ranks` | Rank[] | [5, 10, K] | 2–A | 升级过程中不可跳过的级 |
| `no_skip_enabled` | bool | true | — | 是否启用不可跳过级 |

注意：`bottom_score_multiplier` 不是静态配置，而是由最后一手牌型动态计算（见 Formulas 节）。

**2.5 庄家轮转相关（消费者：C3、C7）**

| 参数名 | 类型 | 默认值 | 有效值 | 说明 |
|--------|------|--------|--------|------|
| `initial_dealer` | int | -1 | -1 或 0–3 | 初始庄家座位，-1 表示首局由抢定决定 |

庄家轮转规则（非配置，固定逻辑）：
1. 首局：4 人抢定，最先定主者为庄家
2. 后续局：上一局庄家未被下庄 → 继续坐庄
3. 庄家无法定主（如 `trump_joker_color_match` 不匹配）→ 下手敌方尝试定主当庄，依次轮转
4. 一轮 4 人均无法定主 → 庄家回到原始玩家，默认无主局

#### 3. 参数约束与校验

系统在生成 RuleConfig 时执行校验：
- `deck_count = 1` 时，`four_same_is_tractor` 强制为 false
- `trump_mode = Fixed` 时，`fixed_trump_suit` 不得为 null
- `trump_mode != Fixed` 时，`fixed_trump_suit` 忽略
- `trump_mode = NoTrump` 时，`joker_always_trump` 决定王牌是否仍为主
- `upgrade_threshold` 不得超过 `deck_count × 100`

### States and Transitions

| 状态 | 说明 | 允许操作 |
|------|------|---------|
| **Editing** | 对局开始前，玩家可修改任意参数 | 读写所有参数 |
| **Locked** | 对局开始后，规则快照冻结 | 只读 |

状态转换：
- `Editing → Locked`：玩家确认开始对局时，执行参数校验，通过后生成不可变快照
- `Locked → Editing`：对局结束后，自动回到可编辑状态（保留上局配置作为默认值）

### Interactions with Other Systems

| 方向 | 系统 | 接口 |
|------|------|------|
| → F1 牌型定义 | F1 读取 `current_rank`、`tractor_allow_rank_card`、`four_same_is_tractor` 用于跳级序列与牌型判定 |
| → F2 牌组管理 | F2 读取 `deck_count` 决定生成几副牌 |
| → C1 主副牌判定 | C1 读取 `current_rank`、`trump_mode`、`joker_always_trump` 判定每张牌的主副属性 |
| → C2 出牌合法性校验 | C2 读取 `allow_dump`、`strict_follow_structure`、`four_same_is_tractor`、`tractor_allow_rank_card` |
| → C3 亮主/抢主/反主 | C3 读取 `trump_mode`、`trump_joker_color_match`、`fixed_trump_suit`、`initial_dealer` |
| → C6 升级结算 | C6 读取 `upgrade_threshold`、`upgrade_step`，并调用抠底倍数计算公式 |
| → FT5 规则预设模板 | FT5 提供预设参数集，写入 F3 的 Editing 状态 |
| → P6 规则配置界面 | P6 读取参数定义（名称、类型、范围、默认值）渲染配置 UI |
| → PL1 配置持久化 | PL1 将当前参数序列化为本地存档，加载时写入 F3 |

**接口契约**：
- F3 对外暴露：`RuleConfig`（不可变快照）、`get_param(name) → value`、`set_param(name, value)`（仅 Editing 状态）、`validate() → Result`、`lock() → RuleConfig`
- 所有消费系统通过 `RuleConfig` 快照读取参数，不直接访问 F3 内部状态

## Formulas

### 抠底倍数计算

```
get_bottom_multiplier(last_trick_type: CardType, pair_count: int) → int
```

| 最后一手牌型 | 倍数 | 规则 |
|-------------|------|------|
| Single（单牌） | 1 | — |
| Pair（对牌） | 2 | — |
| Tractor（拖拉机） | `pair_count × 2` | 2对=4倍，3对=6倍，4对=8倍… |
| Dump（甩牌） | 取最大成分倍数 | 拆解为单张/对子/拖拉机，取其中最高倍数 |

示例：

| 最后一手 | 拆解 | 倍数 |
|---------|------|------|
| ♠5 | Single | 1 |
| ♠5♠5 | Pair | 2 |
| ♠3♠3♠4♠4 | Tractor(2对) | 4 |
| ♠3♠3♠4♠4♠5♠5 | Tractor(3对) | 6 |
| ♠3 ♠5♠5 | Dump → max(Single=1, Pair=2) | 2 |
| ♠3 ♠5♠5♠6♠6 | Dump → max(Single=1, Tractor=4) | 4 |

### 手牌/底牌数量派生

```
hand_size = (deck_count × 54 - bottom_size) / 4
bottom_size = deck_count × 54 - hand_size × 4
```

| deck_count | 总张数 | hand_size | bottom_size |
|------------|--------|-----------|-------------|
| 1 | 54 | 12 | 6 |
| 2 | 108 | 25 | 8 |

## Edge Cases

| # | 边界情况 | 处理方式 |
|---|---------|---------|
| E1 | **trump_mode=NoTrump + joker_always_trump=false**：王牌没有归属花色域 | 王牌归入一个特殊的"无域"，不能参与任何花色的出牌。具体处理由 C1 定义 |
| E2 | **trump_mode=Fixed + fixed_trump_suit=null**：校验不通过 | `validate()` 返回错误，阻止生成快照 |
| E3 | **deck_count=1 + four_same_is_tractor=true**：矛盾 | 校验时强制覆盖为 false，UI 中灰掉该选项 |
| E4 | **upgrade_threshold=0**：攻方 0 分即可升级 | 合法配置，代表"攻方必升"的极端规则（测试/娱乐用） |
| E5 | **upgrade_threshold=200（2副牌最大分）**：攻方必须拿到所有分 | 合法配置，代表极高难度 |
| E6 | **4 人均无法定主**：庄家轮转一圈后回到原始玩家 | 原始玩家坐庄，本局为无主局 |
| E7 | **对局中途退出后重新进入**：规则快照是否保留 | 快照与对局绑定，对局存在则快照存在。对局销毁则回到 Editing |
| E8 | **current_rank 超出范围后的升级**：如升到 A 之后还能升吗 | 由 C6 定义，F3 只保证 current_rank 在 2–A 范围内 |

## Dependencies

| 依赖方向 | 系统 | 类型 | 接口描述 |
|---------|------|------|---------|
| ← FT5 规则预设模板 | 软依赖 | FT5 可向 F3 写入一组预设参数，F3 无 FT5 也能正常工作 |
| ← PL1 配置持久化 | 软依赖 | PL1 可从存档加载参数写入 F3，F3 无 PL1 也能正常工作（使用默认值） |
| → C1 主副牌判定 | 硬依赖（C1 依赖 F3） | C1 读取主牌相关参数 |
| → C2 出牌合法性校验 | 硬依赖（C2 依赖 F3） | C2 读取出牌相关参数 |
| → C3 亮主/抢主/反主 | 硬依赖（C3 依赖 F3） | C3 读取主牌模式与庄家轮转参数 |
| → C6 升级结算 | 硬依赖（C6 依赖 F3） | C6 读取结算相关参数 |
| → F1 牌型定义 | 软依赖（F1 依赖 F3 的运行时参数） | F1 的跳级序列需要 `current_rank` |
| → F2 牌组管理 | 硬依赖（F2 依赖 F3） | F2 读取 `deck_count` |
| → P6 规则配置界面 | 硬依赖（P6 依赖 F3） | P6 读取参数元数据渲染 UI |

F3 自身无硬依赖，可独立设计和实现。

## Tuning Knobs

| 参数 | 类型 | 默认值 | 影响 |
|------|------|--------|------|
| 参数表结构（新增/移除规则项） | 代码变更 | 见 Core Rules 参数表 | 新增规则项需同步更新：校验逻辑、消费系统、P6 界面、PL1 序列化 |

**说明**：F3 的可调性体现在它承载的游戏规则参数（已在 Core Rules 2.1–2.5 详细定义）。F3 系统自身没有独立的运行时可调参数——它的"调参"就是增删游戏规则项，这是代码级变更而非数据驱动。

## Acceptance Criteria

| # | 测试条件 | 预期结果 |
|---|---------|---------|
| AC1 | 使用默认值创建 RuleConfig | 所有参数等于默认值表中定义的值 |
| AC2 | 修改 `deck_count = 1` | `hand_size` 自动派生为 12，`bottom_size` 为 6 |
| AC3 | 修改 `deck_count = 2` | `hand_size` 自动派生为 25，`bottom_size` 为 8 |
| AC4 | 设置 `deck_count=1, four_same_is_tractor=true`，调用 `validate()` | 校验通过但 `four_same_is_tractor` 强制为 false |
| AC5 | 设置 `trump_mode=Fixed, fixed_trump_suit=null`，调用 `validate()` | 校验失败，返回错误信息 |
| AC6 | 设置 `upgrade_threshold=250`（超过 2副×100），调用 `validate()` | 校验失败 |
| AC7 | Editing 状态下调用 `set_param` | 成功修改参数 |
| AC8 | Locked 状态下调用 `set_param` | 拒绝修改，返回错误 |
| AC9 | 调用 `lock()` | 返回不可变 RuleConfig 快照，状态变为 Locked |
| AC10 | 对局结束后 | 状态回到 Editing，参数保留上局配置 |
| AC11 | 抠底倍数：最后一手为 Tractor(3对) | `get_bottom_multiplier` 返回 6 |
| AC12 | 抠底倍数：最后一手为 Dump(单张+拖拉机2对) | `get_bottom_multiplier` 返回 4（取最大成分） |
| AC13 | 庄家轮转：4 人均无法定主 | 庄家回到原始玩家，本局无主 |

## Open Questions

| # | 问题 | 归属 | 优先级 |
|---|------|------|--------|
| Q1 | 无主局时王牌无花色域的具体处理（不能出？归入某个特殊域？） | C1 设计时解决 | 高 |
| Q2 | 庄家轮转中"下庄"的具体判定条件（攻方得分 ≥ threshold？还是其他条件？） | C6 已定义：≥ upgrade_threshold 即下庄，新庄 = (dealer+1)%4 | 已解决 |
| Q3 | 是否需要支持"自定义手牌/底牌数量"作为高级配置（当前为 deck_count 派生，固定） | 未来评估 | 低 |
