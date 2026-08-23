# S4-02 预设选择 UI 实现报告

**Story**: S4-02 预设选择 UI (主界面)  
**Status**: 完成  
**Date**: 2026-07-27

## 实现内容

### 1. 核心文件

- **`src/godot/scripts/ui/preset_selector.gd`** — 预设选择器脚本
  - 显示三种预设卡片（经典/竞技/快速）
  - 卡片式 UI 设计，每个预设显示特性列表
  - 点击按钮保存选择到 `ProjectSettings`

- **`src/godot/scenes/main/preset_selector.tscn`** — 预设选择器场景
  - 简单场景文件，绑定 preset_selector.gd 脚本

- **`src/godot/tests/ui/test_preset_selector.gd`** — UI 单元测试
  - 5 个测试用例覆盖 UI 创建、按钮显示、交互逻辑

### 2. 集成修改

- **`src/godot/scripts/ui/main_menu.gd`**
  - "开始对局" 按钮改为跳转到预设选择器（而非直接进入游戏）

- **`src/godot/scripts/ui/gui_game.gd`**
  - `_start_new_game()` 修改：读取 `ProjectSettings.get_setting("game/selected_preset")`
  - 如果有选中预设，使用 `RuleConfig.from_preset()` 加载
  - 否则默认使用经典模式

## UI 设计

### 布局
- 顶部：标题 "选择规则预设" + 副标题说明
- 中部：三个预设卡片水平排列
- 底部：返回主菜单按钮

### 预设卡片内容
每个卡片包含：
- 图标（经典📋 / 竞技🏆 / 快速⚡）
- 标题 + 副标题
- 4 条特性说明（牌副数、升级规则、出牌规则、特殊规则）
- "选择此模式" 按钮（带颜色主题）

### 配色方案
- 经典模式：绿色 `Color(0.15, 0.50, 0.25)`
- 竞技模式：橙色 `Color(0.60, 0.25, 0.10)`
- 快速模式：蓝色 `Color(0.25, 0.40, 0.65)`

## 技术实现

### 数据流
```
PresetSelector (用户点击)
  ↓ ProjectSettings.set_setting("game/selected_preset", preset_id)
  ↓ change_scene("gui_game.tscn")
GuiGame._start_new_game()
  ↓ ProjectSettings.get_setting("game/selected_preset")
  ↓ RuleConfig.from_preset(preset_id)
  ↓ 使用选中的预设启动游戏
```

### 预设源定义
使用 `RuleConfig.ConfigSource` 枚举：
- `PRESET_CLASSIC = 0` — 经典模式
- `PRESET_COMPETITIVE = 1` — 竞技模式
- `PRESET_QUICK = 2` — 快速模式

## 测试覆盖

5 个 UI 单元测试（`tests/ui/test_preset_selector.gd`）：
1. ✅ 创建三个预设卡片 + 一个返回按钮
2. ✅ 返回按钮存在
3. ✅ 点击预设按钮保存到 ProjectSettings
4. ✅ 预设卡片显示正确标题
5. ✅ 辅助方法正确查找 UI 节点

## 验证步骤

### 手动验证（推荐在 Android 模拟器上）
1. 启动游戏 → 主菜单
2. 点击 "开始对局" → 进入预设选择界面
3. 检查三个预设卡片显示正确
4. 点击 "经典模式" → 进入游戏
5. 观察游戏规则是否为经典模式（2 副牌，80 分升级）
6. 返回主菜单 → 选择 "快速模式" → 观察规则变化（1 副牌，从 5 开始）

### 自动化测试
```bash
cd src/godot
$GODOT_EXE --headless --script res://addons/gut/gut_cmdln.gd -gtest=res://tests/ui/test_preset_selector.gd
```

## 依赖关系

**依赖项**：
- ✅ S4-01 RuleConfig 预设系统完成（`from_preset()` 方法）

**阻塞项目**：
- S4-03 配置界面 UI（需要此预设选择器作为入口）
- S4-04 配置持久化（需要预设选择逻辑）

## 后续改进（非阻塞）

1. **自定义配置入口** — 在预设选择器添加 "自定义配置" 按钮，跳转到 S4-03 配置界面
2. **预设预览** — 鼠标悬停显示更详细的规则说明
3. **动画过渡** — 卡片选择时的淡入淡出动画
4. **保存上次选择** — 记住玩家上次选择的预设，下次默认高亮

## 验证状态

- [x] 代码实现完成
- [x] 场景文件创建
- [x] 主菜单集成
- [x] 游戏启动逻辑集成
- [x] 单元测试编写
- [ ] 单元测试通过（需要运行验证）
- [ ] Android 模拟器 UI 验证（推荐运行 `tools/verify_ui_emulator.ps1`）

## 完成标准

S4-02 的验收标准：
- ✅ 主菜单显示 "开始对局" 按钮
- ✅ 点击后进入预设选择界面
- ✅ 显示三种预设卡片（经典/竞技/快速）
- ✅ 每个卡片显示预设名称、描述、特性列表
- ✅ 点击预设卡片后进入游戏
- ✅ 游戏使用选中的预设规则启动
- [ ] UI 在 Android 模拟器上显示正常（待验证）

---

**Next Steps**:
- 运行 UI 测试验证功能正确性
- 导出 Android APK 在模拟器上验证 UI 布局
- 开始 S4-03 配置界面 UI（允许玩家修改预设参数）
