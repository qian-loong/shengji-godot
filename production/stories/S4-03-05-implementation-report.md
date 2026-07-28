# S4-03 / S4-04 / S4-05 实现收口报告

**日期**: 2026-07-28  
**关联 commits**（本地，未 push 时以 log 为准）:
- `feat(config): memory-first rule config and upgrade_step settlement`
- `chore(logs): write game logs under repo logs/ …`
- `docs(gdd): align dethrone wording …`
- `refactor(session): simplify settlement apply …`

## 交付摘要

| Story | 结果 |
|-------|------|
| S4-03 配置 UI | `room_config.gd` 自定义规则 → 确认进局 |
| S4-04 持久化 | `ConfigStore` + `user://custom_rule_config.json` |
| S4-05 应用到对局 | 开局读内存；结算 × `upgrade_step`；日志带配置快照 |

## 配置生命周期

1. 选预设：`ConfigStore.commit_preset`（只写内存）  
2. 自定义确认：`commit_custom`（内存 + 磁盘）  
3. 开局：`take_for_match`（有 current 不再读 JSON）  
4. 冷启动同预设再进自定义：磁盘按 `base_preset` 恢复  

## 验证

- GUT `tests/unit/game_logic`：ConfigStore / preset / upgrade_settlement 相关通过  
- 实机日志：`upgrade_step: 2`，R1 攻方 70 分 → levels=2（表1×2）  

## 非范围 / 后续

- Headless 批跑矩阵与汇总脚本  
- Polish UX（见 `production/polish-backlog.md`）  
- 根目录 `test_*.gd` 探针：已 gitignore，非正式测试  
