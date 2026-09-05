# Sprint 005 — 2026-08-23 to 2026-09-06

> **Status**: Active
> **Created**: 2026-08-23
> **Sprint Goal**: 闭合 Sprint 004 的验收缺口，让甩牌规则从「引擎已实现」走到「玩家可见」，
> 并把 AI 首出策略从占位设计推进到可实现规格。
> **上游输入**: `production/retrospectives/retro-sprint-004-2026-08-23.md`

---

## Capacity

- Total days: 14（日历 2 周，约 10 个工作日）
- Buffer (30%): 3 天
- Available: **7 天**

> 缓冲取 30% 而非模板默认的 20%，依据是 Sprint 004 回顾：计划外工作占实际工作量约 70%。
> 按 20% 排会重演「计划描述不了真实工作」的问题。

---

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|--------------|---------------------|
| S5-01 | 渲染后端决策：确认 `gl_compatibility` 是否为最终方案，同步 CLAUDE.md 与 `export_android_emulator.ps1` | loong | 0.5 | — | project.godot / CLAUDE.md / 导出脚本三者描述一致；导出脚本不再做无效的临时切换 |
| S5-02 | 重导模拟器 APK 并跑 `verify_ui_emulator.ps1`，闭合 S4-02 遗留验收 | loong | 0.5 | S5-01 | 预设选择页、room_config、返回导航在 AVD 上走通；截图存 `production/qa/evidence/` |
| S5-03 | 甩牌失败的 UI 表现（`play-animation.md:27` 规定的失败动画 + 最小单牌飞出） | ui-programmer | 2.0 | S5-02 | 构造牌局 `spec_dump_not_biggest` 下能看到失败反馈；玩家能理解「为什么只出了一张」 |
| S5-04 | AI 出牌策略设计补章（`ai-basic.md`）：含「靠记牌推断该不该甩牌」与 `lead_strategy` 默认值决策，关闭 GDD Q2 | game-designer | 2.0 | — | 8 个必需章节齐备；`DUMP_HAPPY`/`MAX_STRUCTURE`/`SIMPLE` 三态定位明确；防作弊边界写清（AI 不得借 `challenge_dump` 偷看手牌） |

**Must Have 小计：5.0 天**

### Should Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|--------------|---------------------|
| S5-05 | AI 首出策略实现，按 S5-04 决定是否切换 `lead_strategy` 默认值 | ai-programmer | 2.0 | S5-04 | 批跑首出牌型不再 100% 单张；三预设矩阵全通过校验器 |
| S5-06 | CI 断言：GUT 测试总数不得低于上次记录值 | devops-engineer | 0.5 | — | 人为制造 Parse Error 时 CI 报错而非静默少跑 |

**Should Have 小计：2.5 天**

### Nice to Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|--------------|---------------------|
| S5-07 | UX-P02 墩内实时比大并标注当前最大 | ui-programmer | 1.5 | S5-02 | 第 2/3/4 家落牌后当前最大方有标记 |
| S5-08 | UX-P03 出牌瞬间界面跳动 | ui-programmer | 1.5 | S5-02 | 出牌无视觉跳变；先 tween 再清选中 |

---

## Carryover from Previous Sprint

| Task | Reason | New Estimate |
|------|--------|--------------|
| Android 模拟器 UI 全量验证 | 标注「可后置」后无人跟进；模拟器 APK 落后源码 13 小时 | 0.5 d (S5-02) |
| 甩牌失败 UI 表现 | 逻辑层已实现，GUI 未接 | 2.0 d (S5-03) |
| AI 出牌策略设计 | 依赖规则引擎先稳定，现已稳定 | 2.0 d (S5-04) |
| 切换预设确认框 / 字段 `*` 标记 | — | **Descope** → `production/polish-backlog.md` |

---

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| S5-04 触及 GDD Q2（AI 甩牌需要他人手牌信息）——设计上是真难题，可能远超 2 天 | High | High | 时间盒 2 天；超时则只交付「记牌推断」框架，甩牌决策降级为「默认不甩」并明确记为后续议题 |
| 项目中断 3 周，上下文已流失（session-state 停在 07-28） | High | Med | S5-01/S5-02 是低风险热身任务，借此重建环境与上下文 |
| Must + Should = 7.5 天，略超 available 7 天 | Med | Low | S5-06 可移至下个 Sprint；Nice to Have 不承诺 |
| 无 milestone / risk-register / qa 目录，Sprint 与里程碑无正式对齐 | Med | Med | 本 Sprint 内不补建（会挤占容量）；记入下次回顾 |

---

## Dependencies on External Factors

- Android AVD（如 `Pixel_6_API_36`）与 `$env:GODOT_EXE`、`adb` 可用 —— S5-01/S5-02 的硬前提
- 无第三方 / 外部团队依赖

---

## Definition of Done for this Sprint

- [ ] All Must Have tasks completed
- [ ] All tasks pass acceptance criteria
- [ ] QA plan exists (`production/qa/qa-plan-sprint-005.md`)
- [ ] All Logic/Integration stories have passing unit/integration tests
- [ ] Smoke check passed (`/smoke-check sprint`)
- [ ] QA sign-off report: APPROVED or APPROVED WITH CONDITIONS
- [ ] No S1 or S2 bugs in delivered features
- [ ] Design documents updated for any deviations
- [ ] Code reviewed and merged
- [ ] **每日收工前提交**（回顾行动项 3）
- [ ] **计划外工作超过半天补入 `sprint-status.yaml`，标 `unplanned: true`**（回顾行动项 4）

> 回顾行动项 3、4 是工作习惯而非任务，故列入 DoD 而不占容量。

---

## 承接自 Sprint 004 回顾的流程改进

1. **计划外工作要留痕** —— Sprint 004 最有价值的产出（校验工具链）不在任何计划文件里，
   只能靠 git log 考古。不要求提前预测，但要求事后补记。
2. **新规则必须配构造牌局** —— 已证明随机对局对结构化牌型的覆盖率是 0，
   这不是「测试写得少」，是「这类测试原理上撞不到」。
3. **返回值必须检查** —— GUI 忽略 `submit_play` 返回值导致整局卡死。
   引擎裁决类接口的返回值不得丢弃。

---

## 备注

- 本 Sprint 的 story 仍未拆出独立文件（`sprint-status.yaml` 中 `file: ""`）。
  Sprint 004 回顾已指出这是追溯性缺口；如需补齐可对 S5-03 / S5-05 跑 `/create-stories`。
- `production/milestones/`、`production/risk-register/`、`production/qa/` 三个目录
  在本 Sprint 开始时均不存在，上文的里程碑对齐与风险登记为推导所得，非读取所得。
