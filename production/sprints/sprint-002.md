# Sprint 2 — 对局状态机 + 终端可玩原型

> **Status**: Completed
> **Created**: 2026-04-16
> **Completed**: 2026-05（S2-03 反主于 2026-05-18 在 `feature/counter-bid` 分支补齐）
> **Sprint Goal**: 串联所有已实现的规则引擎系统，实现完整对局流程（发牌→亮主→配底→出牌→结算），通过终端文字交互完成一局双升。

---

## Sprint Info

- **周期**：2 周（弹性节奏）
- **说明**：无 UI，纯终端文字输出。玩家通过数字选择出牌，AI 自动决策。目标是验证全链路正确性。

---

## Tasks

### Must Have

| ID | Task | 对应 GDD | Est. | 依赖 | 状态 | 备注 |
|----|------|---------|------|------|------|------|
| S2-01 | 亮主流程（C3 发牌阶段亮主 + 首局抢主） | C3 trump-bidding | 1d | S1-12 | ✅ | 随 v0.4.0 |
| S2-02 | 抠底/配底逻辑（C4 庄家查看底牌 + 选牌扣下） | C4 bottom-cards | 0.5d | S2-01 | ✅ | 随 v0.4.0 |
| S2-03 | 反主流程（C3 配底后反主窗口） | C3 trump-bidding | 1d | S2-02 | ✅ | `feature/counter-bid` 分支：CounterWindow + SessionController 集成 + AI decide_counter + 50 局回归（4 次反主成功 0 错误）；TUI 短路防御（完整 UI 留待后续） |
| S2-04 | 对局状态机（C7 全流程串联） | C7 game-state-machine | 2d | S2-01,02 | ✅ | 随 v0.4.0；S2-09 重构后由 `session_controller.gd` 持有 |
| S2-05 | AI 基础决策（FT1 亮主/配底/出牌） | FT1 ai-basic | 2d | S2-04 | ✅ | 随 v0.4.0 |
| S2-06 | 终端交互层（玩家通过文字输入操作） | — | 1.5d | S2-04,05 | ✅ | 随 v0.4.0；`tui_game.gd` |
| S2-07 | 完整对局集成测试（打完一局无报错） | — | 1d | S2-06 | ✅ | 随 v0.4.0；117 个 GUT 测试通过 |

### Should Have

| ID | Task | Est. | 依赖 | 状态 | 备注 |
|----|------|------|------|------|------|
| S2-08 | 多局连续（升级 + 庄家轮转 + 游戏结束判定） | 1d | S2-07 | ✅ | `dd1e749 Merge feature/s2-08-multi-round-v2`；新增独立级数 + HTML 日志分析器 |
| S2-09 | 自动对局模式（4 AI 无人值守，验证规则） | 0.5d | S2-07 | ✅ | `game_session.gd` 自动模式保留 |

---

## Definition of Done

- [x] 可以在终端中完整打完一局双升（发牌→亮主→配底→25墩出牌→结算）
- [x] 玩家通过数字选择出牌，非法出牌被拒绝并提示
- [x] AI 3人自动出牌，不犯规
- [x] 结算显示得分、抠底倍数、升级结果
- [x] 全量单元测试仍然通过（117 个）

---

## Progress Log

| 日期 | 完成任务 | 备注 |
|------|---------|------|
| 2026-04 | S2-01, S2-02, S2-04, S2-05, S2-06, S2-07 完成 | 随 v0.4.0 (`ec67b0a`) 发布 |
| 2026-05 | S2-08 多局连续 + 日志分析器 | `dd1e749` |
| 2026-05 | S2-09 自动对局模式可用 | `game_session.gd` 自动模式保留 |
| 2026-05-18 | S2-03 反主流程 | `feature/counter-bid`：`counter-bid-plan.md` v2 + GameRound.bury_seat 重构 + counter_window 状态机 + 10 个新测试 + AIPlayer.decide_counter + game_session.gd 集成 + GDD §4 订正 |
