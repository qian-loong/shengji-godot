# Sprint 1 — M0 规则引擎

> **Status**: Active
> **Created**: 2026-04-16
> **Sprint Goal**: 实现双升的核心数据层和规则逻辑，可通过单元测试验证所有牌型定义、主副牌判定和出牌合法性校验。

---

## Sprint Info

- **周期**：2 周（弹性节奏，无硬性截止日）
- **说明**：第一次接触 Godot/GDScript，Sprint 1 不做 UI，纯逻辑层熟悉语言和工具链。所有成果通过 GUT 单元测试验证。

---

## Tasks

### Must Have（关键路径）

| ID | Task | 对应 GDD | Est. | 依赖 | 验收标准 | 状态 |
|----|------|---------|------|------|---------|------|
| S1-01 | Card 数据结构（Suit、Rank、Joker、Card） | F1 card-types | 1d | — | F1 AC1-AC4 | ⬜ |
| S1-02 | 跳级序列与相邻性判定 | F1 card-types | 1d | S1-01 | F1 AC5-AC8 | ⬜ |
| S1-03 | 牌型识别（Single/Pair/Tractor/Dump 枚举与识别） | F1 card-types | 2d | S1-02 | F1 AC9-AC14 | ⬜ |
| S1-04 | RuleConfig 数据结构与校验 | F3 rule-config | 1d | S1-01 | F3 AC1-AC6 | ⬜ |
| S1-05 | 牌组生成与洗牌 | F2 deck-management | 0.5d | S1-01, S1-04 | F2 AC1-AC4 | ⬜ |
| S1-06 | 主副牌判定（get_suit_domain、get_sort_value） | C1 trump-determination | 1d | S1-01, S1-04 | C1 AC1-AC11 | ⬜ |
| S1-07 | 出牌合法性校验（首出 + 跟牌） | C2 play-validation | 3d | S1-03, S1-06 | C2 AC1-AC8 | ⬜ |
| S1-08 | 赢墩判定（含主牌杀结构匹配） | C2 play-validation | 1d | S1-07 | C2 AC8-AC14 | ⬜ |

### Should Have

| ID | Task | 对应 GDD | Est. | 依赖 | 验收标准 | 状态 |
|----|------|---------|------|------|---------|------|
| S1-09 | 分值追踪 | C5 score-tracking | 0.5d | S1-01 | C5 AC1-AC6 | ⬜ |
| S1-10 | 升级结算（含抠底倍数、不可跳过级） | C6 upgrade-settlement | 1d | S1-09, S1-04 | C6 AC1-AC11 | ⬜ |
| S1-11 | GUT 测试框架搭建 + 测试入口 | — | 0.5d | — | gut 命令可运行所有测试 | ⬜ |

### Nice to Have

| ID | Task | 对应 GDD | Est. | 依赖 | 验收标准 | 状态 |
|----|------|---------|------|------|---------|------|
| S1-12 | 亮主声明逻辑（BidDeclaration 强度比较） | C3 trump-bidding | 1d | S1-04, S1-06 | C3 AC1-AC13 | ⬜ |

---

## Risks

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| GDScript 学习曲线 | 中 | 降低编码速度 | GDScript 语法接近 Python，对 C++ 开发者友好。遇到语法问题随时问 |
| 拖拉机/跟牌规则实现复杂度超预期 | 中 | S1-07 延期 | 先做 Single/Pair 的校验，Tractor/Dump 分步实现 |
| GUT 测试框架与 Godot 4.6 兼容性 | 低 | 测试无法运行 | 可退回到内置 assert + 自定义测试脚本 |

---

## Definition of Done

- [ ] S1-01 至 S1-08（Must Have）全部完成
- [ ] 所有 GDD 中的 Acceptance Criteria 有对应单元测试
- [ ] 测试全部通过
- [ ] 代码遵循 Technical Preferences 中的命名规范
- [ ] 无需 UI——全部通过测试验证

---

## Progress Log

| 日期 | 完成任务 | 备注 |
|------|---------|------|
| — | — | Sprint 尚未开始 |
