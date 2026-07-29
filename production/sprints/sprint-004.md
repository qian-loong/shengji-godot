# Sprint 004 — 规则配置系统与预设模板

**目标**: 实现完整的规则配置系统，支持三种预设模式（经典/竞技/快速）和自定义配置

**Sprint 周期**: 2026-07-26 → 2026-08-09 (2周)

**状态（2026-07-29 更新）**: S4-01～S4-05 代码主路径已完成；sprint-status 已同步为 done。  
headless 批跑配置矩阵**已完成**（三预设单因子矩阵 + 配置驱动校验器 + 构造牌局注入），
详见下方「批跑与校验工具链」。后续体验项见 `production/polish-backlog.md`。

---

## Sprint 目标

### 核心交付物

1. ✅ **RuleConfig 数据模型** — 规则字段、三预设、`to_dict`/`from_dict`
2. ✅ **三种预设模板** — 经典 / 竞技 / 快速（含 `upgrade_step`、upgrade_table）
3. ✅ **配置界面 UI** — `room_config` + 预设卡「自定义规则」
4. ✅ **预设选择 UI** — `preset_selector`，主菜单「开始对局」进入
5. ✅ **配置持久化 + 开局应用** — `ConfigStore` 内存优先，磁盘 `user://custom_rule_config.json`

### 与早期草案的差异（实现为准）

| 草案 | 实际实现 |
|------|----------|
| `RuleConfig extends Resource` + `.tres` | `RuleConfig extends RefCounted` + JSON（`to_dict`/`from_dict`） |
| `user://game_config.tres` | `user://custom_rule_config.json` + 进程内 `ConfigStore.current` |
| 开局再读盘传配置 | 确认时写内存+盘；开局只读内存 |
| 快速表「60 分仅换庄」等旧档 | 与代码一致：60/90/120 档，级数 × `upgrade_step` |
| 文案「攻方下庄」 | UI/GDD：「庄家下庄 / 庄家守庄」 |
| 日志 `docs/game-logs/` | 仓库根 `logs/` |

### 验收对照（实现后）

- [x] 主界面 → 开始对局 → 三预设可选
- [x] 预设卡 / 主菜单可进自定义规则页
- [x] 可改副牌数、升级分、升级步数、甩牌、跟牌、必打等级等
- [x] 确认后配置进局生效（含 `upgrade_step` 乘数）
- [x] 同预设再次打开自定义可恢复上次改动（磁盘 + 内存）
- [x] 对局日志写入 `logs/`，含 `rule_config.upgrade_step`
- [ ] Android 模拟器 UI 全量验证（S4-02 备注，可后置）
- [ ] 切换预设确认框 / 字段 `*` 标记等体验细节（见 polish backlog 或后续小改）

---

## Story 列表与结论

### S4-01: RuleConfig 数据模型 — **done**

- 路径：`src/godot/scripts/core/rule_config.gd`
- 要点：`from_preset`、`set_custom_value`、`to_dict`/`from_dict`、三预设工厂
- 测试：`tests/unit/game_logic/test_rule_config_preset.gd` 等

### S4-02: 预设选择 UI — **done**

- 路径：`src/godot/scripts/ui/preset_selector.gd`、`scenes/main/preset_selector.tscn`
- 主菜单「开始对局」→ 预设页；卡内「自定义规则」→ room_config
- 报告：`production/stories/S4-02-implementation-report.md`

### S4-03: 配置界面 UI — **done**

- 路径：`src/godot/scripts/ui/room_config.gd`
- 确认：`ConfigStore.commit_custom` → 内存 + 磁盘 → 进 `gui_game`
- 按钮文案：「自定义规则」（非临时「调整规则」）

### S4-04: 配置持久化 — **done**

- 路径：`src/godot/scripts/core/config_store.gd`
- 磁盘：`user://custom_rule_config.json`（完整字段含 `upgrade_table`/`upgrade_step`）
- 匹配：仅 `base_preset` 一致时叠自定义

### S4-05: 配置应用到游戏流程 — **done**

- 开局：`gui_game` → `ConfigStore.take_for_match`
- 结算：`upgrade_levels = 表级数 × upgrade_step`（`upgrade_settlement.gd`）
- 日志：`game_logger.set_rule_config` 含 `upgrade_step`
- 测试：`test_config_store.gd`、`test_upgrade_settlement.gd`

---

## 关键实现路径（速查）

| 能力 | 路径 |
|------|------|
| 配置模型 | `src/godot/scripts/core/rule_config.gd` |
| 配置仓库 | `src/godot/scripts/core/config_store.gd` |
| 升级结算 | `src/godot/scripts/core/upgrade_settlement.gd` |
| 预设 UI | `src/godot/scripts/ui/preset_selector.gd` |
| 自定义 UI | `src/godot/scripts/ui/room_config.gd` |
| GUI 开局 | `src/godot/scripts/ui/gui_game.gd` |
| 对局日志目录 | 仓库根 `logs/` |
| 本地说明 | `CLAUDE.local.md`（不进 git） |
| 体验待办 | `production/polish-backlog.md` |

---

## 关于 `src/godot/test_*.gd` / `debug_*.gd`

这些是调试期 **一次性 headless 探针**（`extends SceneTree`，`godot --headless --script …` 打印期望值），**不是** GUT 正式测试。

- 正式测试：`src/godot/tests/**`
- 探针用途：当时排查必打级、下庄、upgrade_table 等
- 处理：已加入 `.gitignore`，不提交；可随时本地删除

---

## 后续（非本 sprint 阻塞）

1. ~~Headless 批跑：`--preset` / `--config` + 配置矩阵 + 汇总脚本~~ **已完成**
2. Polish：墩内实时比大、拖选、出牌跳动、主菜单信息架构（见 polish-backlog）
3. Android 模拟器验证预设/配置 UI
4. AI 出牌策略设计（见 `design/gdd/ai-basic.md` 的首出策略开关一节）
5. 甩牌失败的 UI 表现（`play-animation.md` 已规定动画，目前只有逻辑层）

---

## 批跑与校验工具链（2026-07-29 完成）

| 工具 | 职责 |
|------|------|
| `tools/validate_game_log.py` | **唯一规则源**。配置驱动复算：牌型/赢墩/跟牌合法性/牌张归属/结算全字段/跨局连续性/守恒。缺字段 FATAL 而非静默默认 |
| `tools/export_game_log_html.py` | HTML 复盘页，纯渲染。规则判定全部委托校验器（原自带的 340 行规则实现已删除） |
| `tools/batch/run_batch.py` | 批跑，每局跑完即校验；`--lead-strategy` 切首出策略；退出码可做 CI 门禁 |
| `tools/batch/summarize_batch.py` | 汇总，含首出牌型覆盖率与违规类型统计 |
| `tools/batch/generate_matrix.py` | 展开配置矩阵，写盘前拦截门槛/升级表失配 |
| `tools/scenarios/make_scenario.py` | 构造牌局生成器，含牌张守恒自检 |
| `tools/tests/test_validate_game_log.py` | 校验器回归测试（64 项，含变异检出与预设镜像一致性） |

**矩阵**：三预设各一份单因子扫描（`matrix_single_factor_{classic,competitive,quick}.json`）。

**构造牌局**（`--scenario`）：随机对局里 AI 只首出单张，对子/拖拉机/甩牌路径永不触发，
需靠构造牌局命中。已覆盖四张级牌拖拉机、四张王、严格跟牌、级牌参与拖拉机、甩牌最大性。

### 本阶段修掉的规则 Bug

| Bug | 说明 |
|-----|------|
| 对子按 rank 统计 | `_extract_pair_ranks` 与 `_is_pair`（equals）语义冲突，`♠5♥5♠6♥6` 四张散牌被判为拖拉机 |
| `four_same_is_tractor` 死配置 | 原用"4 张完全相同"需 4 副牌，任何合法配置下都触发不了。已改为"同点数 4 张" |
| 甩牌最大性未校验 | GDD 在四个文档里定义了规则链，实现完全缺失。已补 `PlayValidator.challenge_dump` |
| `upgrade_threshold` 与表失配 | 两字段可独立修改，产生矛盾配置。已加 `validate()` 校验 + `build_upgrade_table()` |
| 测试文件静默失效 | `test_session_state.gd` 的 Parse Error 让整个文件 18 个测试未被 GUT 加载 |
| headless 每局崩溃 | `game_session.gd` 引用已删除的 `upgrade_blocked` 字段 |
