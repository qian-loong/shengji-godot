# 系统索引 — 双升对局

> 版本：v0.2 | 最后更新：2026-05-17

---

## 概览

| 统计 | 数量 |
|------|------|
| 系统总数 | 23 |
| 已完成设计 | 16 |
| 已实现（代码） | 10 完整 + 1 部分（C3 缺反主） |
| TUI 替代（M1 表现层） | 5（P1–P5；图形 UI 待实现） |
| 未开始（设计） | 7 |

---

## 设计顺序（依赖 + 优先级排序）

| 顺序 | ID | 系统名 | 层级 | 里程碑 | 优先级 | 设计 | 实现 | GDD 文件 |
|------|----|--------|------|--------|--------|------|------|----------|
| 1 | F1 | 牌型定义 | Foundation | M0 | MVP | ✅ | ✅ 已实现 | `design/gdd/card-types.md` |
| 2 | F3 | 规则配置系统 | Foundation | M0 | MVP | ✅ | ✅ 已实现 | `design/gdd/rule-config.md` |
| 3 | F2 | 牌组管理 | Foundation | M0 | MVP | ✅ | ✅ 已实现 | `design/gdd/deck-management.md` |
| 4 | C1 | 主副牌判定 | Core | M0 | MVP | ✅ | ✅ 已实现 | `design/gdd/trump-determination.md` |
| 5 | C2 | 出牌合法性校验 | Core | M0 | MVP | ✅ | ✅ 已实现 | `design/gdd/play-validation.md` |
| 6 | C3 | 亮主/抢主/反主 | Core | M1 | MVP | ✅ | 🚧 部分（反主未完成） | `design/gdd/trump-bidding.md` |
| 7 | C4 | 抠底/配底 | Core | M1 | MVP | ✅ | ✅ 已实现 | `design/gdd/bottom-cards.md` |
| 8 | C5 | 分值追踪 | Core | M1 | MVP | ✅ | ✅ 已实现 | `design/gdd/score-tracking.md` |
| 9 | C6 | 升级结算 | Core | M1 | MVP | ✅ | ✅ 已实现 | `design/gdd/upgrade-settlement.md` |
| 10 | C7 | 对局状态机 | Core | M1 | MVP | ✅ | ✅ 已实现 | `design/gdd/game-state-machine.md` |
| 11 | FT1 | AI 基础决策 | Feature | M1 | MVP | ✅ | ✅ 已实现 | `design/gdd/ai-basic.md` |
| 12 | P2 | 手牌渲染 | Presentation | M1 | MVP | ✅ | ⏳ TUI 替代 | `design/gdd/hand-rendering.md` |
| 13 | P1 | 桌面布局 UI | Presentation | M1 | MVP | ✅ | ⏳ TUI 替代 | `design/gdd/table-layout.md` |
| 14 | P4 | 亮主/抢主 UI | Presentation | M1 | MVP | ✅ | ⏳ TUI 替代 | `design/gdd/bid-ui.md` |
| 15 | P3 | 出牌/动画反馈 | Presentation | M1 | MVP | ✅ | ⏳ TUI 替代 | `design/gdd/play-animation.md` |
| 16 | P5 | 结算界面 | Presentation | M1 | MVP | ✅ | ⏳ TUI 替代 | `design/gdd/settlement-ui.md` |
| 17 | FT5 | 规则预设模板 | Feature | M2 | Vertical Slice | ⬜ | ⬜ 未开始 | — |
| 18 | P6 | 规则配置界面 | Presentation | M2 | Vertical Slice | ⬜ | ⬜ 未开始 | — |
| 19 | PL1 | 配置持久化 | Polish | M2 | Vertical Slice | ⬜ | ⬜ 未开始 | — |
| 20 | FT2 | AI 手牌推理 | Feature | M3 | Alpha | ⬜ | ⬜ 未开始 | — |
| 21 | FT3 | AI 配合意图 | Feature | M3 | Alpha | ⬜ | ⬜ 未开始 | — |
| 22 | FT4 | AI 难度梯度 | Feature | M3 | Alpha | ⬜ | ⬜ 未开始 | — |
| 23 | PL2 | 联机预留接口 | Polish | M5 | Full Vision | ⬜ | ⬜ 未开始 | — |

---

## 依赖关系

| 系统 | 依赖 |
|------|------|
| F1 牌型定义 | — |
| F2 牌组管理 | — |
| F3 规则配置系统 | — |
| C1 主副牌判定 | F1, F3 |
| C2 出牌合法性校验 | F1, C1, F3 |
| C3 亮主/抢主/反主 | F2, C1, F3 |
| C4 抠底/配底 | F2, C1 |
| C5 分值追踪 | F1 |
| C6 升级结算 | C5, F3 |
| C7 对局状态机 | C3, C4, C2, C5, C6 |
| FT1 AI 基础决策 | C2, C7, C1 |
| FT2 AI 手牌推理 | FT1, C5 |
| FT3 AI 配合意图 | FT2 |
| FT4 AI 难度梯度 | FT1 |
| FT5 规则预设模板 | F3 |
| P1 桌面布局 UI | C7 |
| P2 手牌渲染 | F1, C1 |
| P3 出牌/动画反馈 | C2, P2 |
| P4 亮主/抢主 UI | C3 |
| P5 结算界面 | C6 |
| P6 规则配置界面 | F3, FT5 |
| PL1 配置持久化 | F3 |
| PL2 联机预留接口 | C7 |

---

## 瓶颈系统（被依赖最多）

| 系统 | 被依赖次数 | 被哪些系统依赖 |
|------|-----------|----------------|
| F1 牌型定义 | 6 | C1, C2, C5, P2, P3, FT1（间接） |
| F3 规则配置系统 | 6 | C1, C2, C3, C6, P6, PL1 |
| C1 主副牌判定 | 5 | C2, C3, FT1, P2, P3（间接） |
| C2 出牌合法性校验 | 3 | C7, FT1, P3 |
| C7 对局状态机 | 3 | FT1, P1, PL2 |

---

## 下一步

按当前代码状态（Sprint 1/2 已完成，v0.4.0 发布），下一步聚焦：

1. **C3 反主流程（CounterWindow）实现** — 收掉 sprint-002 S2-03 与 `session-controller-refactor-plan.md` 中的 TODO
2. **M1 表现层 P1 → P2 → P3 → P4 → P5** — 把 TUI 替换为正式图形 UI

运行 `/sprint-plan` 起 Sprint 3。
