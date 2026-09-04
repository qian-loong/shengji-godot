# S5-01 / S5-02 模拟器 UI 验证报告

**日期**: 2026-09-04
**验证人**: loong (Claude Code)
**关联任务**: S5-01（渲染后端决策与文档同步）、S5-02（模拟器 UI 全量验证）
**关联提交**: 工作区未提交改动（`export_presets.cfg` / `project.godot` / `export_android_emulator.ps1` / `CLAUDE.md`）

---

## 验证环境

| 项 | 值 |
|----|-----|
| Godot | `Godot_v4.6.2-stable_win64_console.exe` |
| AVD | `Pixel_6_API_36`（emulator-5554，2400×1080 横屏）|
| 渲染器 | `gl_compatibility`（经 `Android-Emulator` 预设的 `emulator` 特性标签映射）|
| APK | `builds/android/shengji-debug-emulator.apk`，54.89 MB |

---

## 1. 单元测试（前置门禁）

```
GUT: 388/388 passed，1411 asserts，8.5s，0 失败
```

逻辑层无退化。

## 2. 导出脚本修复验证（S5-01 核心）

新 `export_android_emulator.ps1` 使用 `Android-Emulator` 预设，**不再改写 `project.godot`**：

- ✅ 导出成功，输出确认 `preset: Android-Emulator, renderer: gl_compatibility`
- ✅ 运行后 `project.godot` 无额外改动（`git diff` 仅剩 S5-01 那一行 `.mobile→.emulator`）
- ✅ 未产生新的 `.bak` 文件（旧脚本会临时改写再还原并留备份）
- ✅ 未触发旧脚本"patch 未生效则中止"的守卫（该守卫此前会连带 `verify_ui_emulator.ps1` 一起挂掉）

## 3. UI 导航全链路（S5-02）

在 AVD 上安装启动后，逐屏截图验证：

| # | 界面 | 结果 | 证据 |
|---|------|------|------|
| 1 | 主菜单 | ✅ 标题「双升对局」+ 菜单按钮正常渲染 | `s5-01-01-main-menu.png` |
| 2 | 预设选择页 | ✅ 三张卡片（经典/竞技/快速），规则要点由 `RuleConfig` 实时生成，徽章占位对齐 | `s5-01-02-preset-selector.png` |
| 3 | room_config（自定义规则）| ✅ 两栏免滚动布局，左栏牌组/必打级、右栏出牌/定主规则，✎ 标记位占位 | `s5-01-03-room-config.png` |
| 4 | 返回导航 | ✅ 完整链路 | `s5-01-04-back-to-menu.png` |

**返回链路**（`back_navigation.gd`，系统 BACK 键）：

```
主菜单 → 预设页 → room_config
              ↑ BACK（=取消，退回预设页）✅
       ↑ BACK（退回主菜单）✅
```

两级返回均按预期工作，画面字节数与去程各屏一致（room_config→预设页 220395B；预设页→主菜单 40038B），确认无残留/无卡死。

---

## 结论

**PASS** — `gl_compatibility` 渲染在 AVD 上无黑屏/无错位；导出脚本重构消除了"改写 project.godot"的隐患；预设页、room_config、返回导航三项 S4-02 遗留验收全部走通。

可提交 S5-01 改动。
