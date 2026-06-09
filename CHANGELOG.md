# Changelog

所有重要变更按时间倒序记录。

---

## [Unreleased]

（暂无）

---

## 2026-06-09 — v0.5.0 Release

**commits**: `306918c` … `e98c9cc` on `main`

Sprint 2 收尾：SessionController 架构重构、反主窗口、定主强度 5 档细分与反主免疫规则（ADR-0001/0002/0003）。186 个 GUT 单元测试全部通过。

### 新增

- 共享 `SessionState` / `SessionController`：自动宿主与 TUI 宿主共用同一套开局、亮主、配底、出牌、结算和跨局状态推进路径。
- 两队独立级：南北队/东西队分别维护等级，每局按实际庄家队伍等级开局，攻方升级按攻方自身等级结算。
- 日志复盘 HTML 导出器：支持每局切换、每墩围桌展示、初始手牌、出牌前后手牌、出牌高亮、庄家顺延原因和人工订正导出。
- 日志复盘标准样例：新增 `docs/game-logs/standard_log.json` 作为分析器回归样例。
- 反主窗口（`counter_window` 阶段）：`SessionController` 集成配底后反主流程；`AIPlayer.decide_counter` 支持 AI 反主决策；10 个反主专项测试。
- 定主声明强度 5 档细分（ADR-0001）：`JOKER_RANK` 拆分为 `JOKER_SINGLE_RANK`(s=3) 与 `JOKER_PAIR_RANK`(s=4)；日志 schema v2 新增 `type_name` 可读标签。
- 反主免疫规则（ADR-0002/0003）：`JokerPairRank` 与 `PairRank` 免疫反主；`can_be_countered()` 改为白名单（仅 `SingleRank` / `JokerSingleRank` 可被反）。
- 自动宿主新增 `--max-rounds`、`--log-path` 与 `--seed` 参数，便于生成可复现的验证日志。

### 修复

- 修复定主顺延后本局等级未同步到实际庄家队伍的问题。
- 修复未下庄时下一局仍从旧 `current_dealer` 轮询定主的问题，改为沿用本局实际庄家。
- 修复攻方升级时错误使用庄家方等级作为升级基准的问题。
- 修复 TUI 长局运行时界面日志无限增长导致的出牌卡顿，UI 日志改为固定行数缓冲。

### 变更

- `game_session.gd` 降级为自动宿主，`tui_game.gd` 降级为 UI 宿主；二者通过 controller 阶段 API 提交亮主、配底、出牌和结算。
- `GameRound` 引入 `bury_seat` 以支持反主后底牌转交。
- 日志新增 `team_ranks`、`team_ranks_symbols`，并移除每墩 `hands_before/hands_after` 冗余快照；HTML 导出器在生成报告时从初始手牌、埋牌和出牌记录重建每墩前后手牌。
- AI 定主跳过原因细分为 `no_valid_cards` 与 `ai_pass`，HTML 报告中明确展示庄家顺延原因。
- TUI 自动保存改为 compact JSON，并取消每墩结束后的完整日志写盘，只在配底、结算、游戏结束和手动保存时写盘。
- TUI 反主窗口暂短路为自动 pass（完整反主 UI 留待 Sprint 3 P4）。

### 文档

- ADR-0001：定主声明强度 5 档细分（Accepted 2026-05-18）
- ADR-0002：「王+对级」免疫公主反主（Accepted 2026-05-18）
- ADR-0003：「对级」对称免疫反主（Accepted 2026-06-09）
- `trump-bidding.md`：§1 强度表、反主免疫总则、AC8/AC16–AC20 同步
- `counter-bid-plan.md` v2、`sprint-002.md`、`systems-index.md` 与实现对齐

---

## 2026-05-14 — S2-08 规则修复、日志完善与跟牌约束

**commit**: `e8b33c4` on `feature/s2-08-multi-round-v2`

### 新增

- 跟牌结构约束 `strict_follow_structure`：有对必出对，跟拖拉机时尽量出对子
- 日志 `bid_history`：记录每个 seat 的亮主决策（bid/skip + reason）
- 日志 `settlement.new_dealer`：记录庄家轮转结果
- 非首局亮主从庄家开始按座位轮询，UI 显示"XX 跳过"
- 升级阶梯 no_skip 组合测试（5 个）、跟牌结构测试（7 个）、亮主放弃测试（2 个）
- 130 个单元测试全部通过（较 v0.4.0 的 117 个新增 13 个）

### 修复

- 座位编号统一为逆时针递增（0南/下 → 1东/右 → 2北/上 → 3西/左）
- 出牌公式从 `(seat-i+4)%4` 改为 `(seat+i)%4`
- 庄家轮转：下庄后新庄家 = `(dealer+1)%4`（修复原 `last_trick_winner` 可能选到庄家方的 Bug）
- 非首局亮主顺序：从庄家开始轮询（修复原"无条件先问人类"的 Bug）
- 对子判定：按牌面身份 (suit+rank) 分组（修复非同花色级牌误判为对子的 Bug）
- 桌面视图 `_update_table` 左右位置互换
- 无人定主 fallback 改为 `current_dealer`（修复原硬编码 `human_seat` 的 Bug）

### 变更

- 升级阶梯修正为 40 分间隔：0→庄3级, 1-39→庄2级, 40-79→庄1级, 80-119→换庄, 120-159→攻1级, 160-199→攻2级, ≥200→攻3级
- 亮主规则启用 `bid_requires_joker=true` + `trump_joker_color_match=true`
- AI 跟牌重构为 `_pick_domain_follow`，规则保障与策略选择分离

### 文档

- `trump-bidding.md` §2：增加首局 MVP 简化说明（一次发完牌→先问人类，待正式 UI 改为实时抢定）
- `trump-bidding.md` §3：重写非首局定主流程（从庄家开始轮询）
- `upgrade-settlement.md`：升级阶梯表 + 下庄判定公式更新
- `game-state-machine.md`：座位编号 + 出牌方向更新
- `table-layout.md`：座位布局图更新
- `rule-config.md`：Q2（下庄判定）标记为已解决

---

## 2026-04-16 — v0.4.0 Release

**commit**: `ec67b0a` on `main`

- 规则引擎完整实现（F1 牌型、F2 牌组、F3 规则配置、C1 主副判定、C2 出牌校验、C3 亮主、C5 计分、C6 结算）
- 终端可玩原型（TUI + headless 两种模式）
- AI 基础决策（亮主/配底/出牌）
- 游戏日志系统（replay + debug 双层）
- 117 个单元测试
