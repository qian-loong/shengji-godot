# Changelog

所有重要变更按时间倒序记录。

---

## [Unreleased]

### 新增
- 共享 `SessionState` / `SessionController`：自动宿主与 TUI 宿主共用同一套开局、亮主、配底、出牌、结算和跨局状态推进路径。
- 两队独立级：南北队/东西队分别维护等级，每局按实际庄家队伍等级开局，攻方升级按攻方自身等级结算。
- 日志复盘 HTML 导出器：支持每局切换、每墩围桌展示、初始手牌、出牌前后手牌、出牌高亮、庄家顺延原因和人工订正导出。
- 日志复盘标准样例：新增 `docs/game-logs/standard_log.json` 作为分析器回归样例。

### 修复
- 修复定主顺延后本局等级未同步到实际庄家队伍的问题。
- 修复未下庄时下一局仍从旧 `current_dealer` 轮询定主的问题，改为沿用本局实际庄家。
- 修复攻方升级时错误使用庄家方等级作为升级基准的问题。

### 变更
- `game_session.gd` 降级为自动宿主，`tui_game.gd` 降级为 UI 宿主；二者通过 controller 阶段 API 提交亮主、配底、出牌和结算。
- 日志新增 `team_ranks`、`team_ranks_symbols`、每墩 `hands_after`，并将 `hands_before/hands_after` 统一为 TUI 展示顺序。
- AI 定主跳过原因细分为 `no_valid_cards` 与 `ai_pass`，HTML 报告中明确展示庄家顺延原因。

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
