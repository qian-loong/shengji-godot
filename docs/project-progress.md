# 升级 (Shengji) 项目进度总结

**更新时间**: 2026-07-29  
**当前阶段**: 制作阶段 (Production)  
**活跃 Sprint**: Sprint 004（收口 + 测试基础设施）

---

## 📊 项目概览

### 游戏核心信息
- **类型**: 4人组队扑克牌游戏（双升/升级/拖拉机）
- **引擎**: Godot 4.6
- **语言**: GDScript
- **平台**: Android（主要）+ PC
- **渲染**: Vulkan Mobile（设备）/ OpenGL ES 3.0（模拟器）

### 开发状态
- ✅ **Sprint 001**: 核心游戏逻辑（发牌、出牌、结算）
- ✅ **Sprint 002**: 定主系统（抢注、反注、定主、底牌）
- ✅ **Sprint 003**: UI 重构（Bootstrap Icons SVG、模态层统一、Android 导航）
- ✅ **Sprint 004**: 规则配置系统（预设模板、自定义配置）+ 批跑校验工具链

---

## 🎯 当前 Sprint 状态

### Sprint 003 总结（已完成）
**目标**: GUI 系统现代化改造

**已交付**:
1. ✅ 使用 Bootstrap Icons 替换旧图标系统
2. ✅ 统一所有模态覆盖层（抢注、定主、弃牌、结算）
3. ✅ 定主面板复用抢注阶段的图标栏
4. ✅ Android 返回键导航支持
5. ✅ Kenney 卡牌素材集成

**成果**:
- 视觉一致性大幅提升
- Android 用户体验改善
- 代码可维护性增强

---

### Sprint 004 规划（当前）
**目标**: 实现完整的规则配置系统

**核心交付物**:
1. 🎯 RuleConfig 数据模型（8个规则字段）
2. 🎯 三种预设模板：
   - **经典模式**: 2副牌, 80分, 完整策略（15-20分钟）
   - **竞技模式**: 2副牌, 100分, 高门槛（20-25分钟）
   - **快速模式**: 1副牌, 80分, 升2级, 简化规则（5-8分钟）
3. 🎯 配置界面 UI（预设选择 + 自定义配置）
4. 🎯 配置持久化（保存到 user://）
5. 🎯 配置应用到游戏流程

**Story 列表**:
- S4-01: RuleConfig 数据模型（2天）
- S4-02: 预设选择 UI（1天）
- S4-03: 配置界面 UI（3天）
- S4-04: 配置持久化（1天）
- S4-05: 配置应用到游戏流程（2天）

**时间线**: 2026-07-26 → 2026-08-09 (2周)

---

## 📋 设计文档状态

### 已完成的 GDD
1. ✅ `game-concept.md` — 游戏概念与核心玩法
2. ✅ `card-system.md` — 牌组系统（FT1）
3. ✅ `trump-system.md` — 主牌系统（FT2）
4. ✅ `play-phase.md` — 出牌阶段（FT3）
5. ✅ `score-system.md` — 计分升级（FT4）
6. ✅ `rule-config.md` — 规则配置（FT5/FT6，框架已定义）

### 待补充
- `rule-config.md` 需要补充三种预设的详细说明（Sprint 004 完成后）

---

## 🏗️ 技术架构

### 核心模块
```
GameController (总控)
├── BidPhaseController (定主阶段)
│   ├── Counter-bid 系统（反注）
│   └── Trump declaration (定主)
├── PlayPhaseController (出牌阶段)
│   ├── 合法性校验
│   ├── 甩牌检测
│   └── 打出检测
├── ScoreSystem (计分升级)
│   └── 80分升级逻辑
└── [NEW] RuleConfig (规则配置)
    ├── 三种预设模板
    └── 自定义配置
```

### UI 架构
```
GUI_Game (主界面)
├── HandDisplay (手牌显示)
├── PlayArea (出牌区)
├── BidBar (抢注图标栏) — 复用于定主阶段
├── Modals (模态层)
│   ├── CounterBidPanel (抢注/反注)
│   ├── TrumpDeclarePanel (定主)
│   ├── KittyDiscardPanel (弃牌)
│   └── SettlementPanel (结算)
└── [NEW] RuleConfigDialog (规则配置)
```

---

## 🎨 视觉风格

### 卡牌素材
- **主素材**: Kenney Card Pack
- **备用**: 可替换为中国传统花色设计

### UI 图标
- **花色图标**: Bootstrap Icons (`suit-*`)
- **功能图标**: Bootstrap Icons 通用图标集
- **渲染**: SVG → Texture2D（实时转换）

---

## 🧪 测试覆盖

### 已有测试
- ✅ 核心游戏逻辑单元测试
- ✅ 定主系统集成测试
- ✅ Android 模拟器 UI 测试

### Sprint 004 测试计划
- 🎯 RuleConfig 单元测试（所有方法）
- 🎯 ConfigManager 持久化测试
- 🎯 三种预设的集成测试
- 🎯 Android UI 配置界面测试

---

## 🚀 后续里程碑

### Sprint 005（预计）
**主题**: 多人联机基础架构
- WebSocket 或 Godot Multiplayer
- 房间系统（创建/加入/观战）
- 网络同步（出牌、定主、结算）

### Sprint 006（预计）
**主题**: 玩家系统与账号
- 本地玩家数据
- 头像/昵称
- 战绩统计

### Sprint 007+（待规划）
- 排行榜/天梯系统
- 复盘功能
- AI 对手（单机模式）

---

## 📈 代码健康度

### 当前指标
- **TODO**: 10 个（分布在 src/）
- **FIXME**: 0 个
- **单元测试覆盖率**: 预估 60-70%（需补充）

### 技术债务
- [ ] 部分早期代码需要重构以支持 RuleConfig 注入
- [ ] UI 自适应需要更多测试（不同屏幕尺寸）
- [ ] 性能分析待进行（Android 真机）

---

## 🔧 开发环境

### 工具链
- **Godot**: 4.6 stable
- **版本控制**: Git (trunk-based)
- **Android 导出**: Godot Export Templates 4.6
- **模拟器**: Android Studio AVD (Pixel 6 API 36)

### 构建脚本
- `tools/export_android_emulator.ps1` — 生成模拟器 APK
- `tools/verify_ui_emulator.ps1` — UI 自动验证 + 截图

---

## 🎯 下一步行动

### 立即开始（Sprint 004）
1. **创建 RuleConfig 类** (`src/godot/scripts/game_logic/rule_config.gd`)
2. **定义三种预设的默认值**
3. **设计预设选择 UI**（主界面或房间设置面板）
4. **实现配置界面**（8个字段的可视化编辑）

### 等待用户确认
- Sprint 004 的 Story 拆分是否合理？
- 是否需要调整优先级？
- 是否需要添加其他功能？

---

## 📝 备注

### 三种预设的设计哲学

| 预设 | 牌数 | 门槛 | 升级 | 特色规则 | 目标玩家 |
|------|------|------|------|---------|---------|
| **经典** | 2副 | 80分 | 升1级 | 完整策略 | 传统玩家 |
| **竞技** | 2副 | 100分 | 升1级 | 高门槛+宽松定主 | 高手/天梯 |
| **快速** | 1副 | 80分 | 升2级 | 简化规则 | 休闲/碎片时间 |

### 配置行为设计
- 用户选择预设 → 加载预设默认值
- 用户修改配置 → 标记为 CUSTOM，显示 * 号
- 切换预设 → 弹确认框，确认后丢弃修改
- 恢复预设 → 重置到原始预设值
- 保存配置 → 持久化到 `user://game_config.tres`

---

**文档维护**: 本文档在每个 Sprint 开始/结束时更新
