# Testing Standards

## Test Framework

- **Framework**: GUT (Godot Unit Test) 9.6.0
- **Location**: `src/godot/tests/` — 所有测试文件必须放在此目录
- **Naming**: `test_*.gd` — 所有测试文件必须以 `test_` 前缀命名
- **Current Coverage**: 210 tests, 913 assertions across 12 test files

## Running Tests

### Headless Mode (CI/Automated)

```bash
cd src/godot
$GODOT_EXE --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

**Environment Variable**:
- Windows PowerShell: `$env:GODOT_EXE = "path\to\Godot_v4.6.2-stable_win64_console.exe"`
- Bash/WSL: `export GODOT_EXE="/path/to/Godot_v4.6.2-stable_win64_console.exe"`

### Editor Mode (Interactive)

1. 在 Godot Editor 中打开项目 (`src/godot/`)
2. 底部面板切换到 "GUT" 标签页
3. 点击 "Run All" 运行全部测试
4. 或选择单个测试文件运行

## Test File Structure

每个测试文件应遵循以下结构：

```gdscript
extends GutTest

# 测试固件 - 每个测试前运行
func before_each():
    pass

# 测试固件 - 每个测试后运行
func after_each():
    pass

# 测试函数 - 必须以 test_ 开头
func test_feature_name():
    var result = feature_under_test()
    assert_eq(result, expected_value, "描述性错误信息")
```

## Test Coverage by System

| System | Test File | Tests | Status |
|--------|-----------|-------|--------|
| 卡牌定义 | test_card.gd | 14 | ✅ |
| 牌型判定 | test_card_pattern.gd | 17 | ✅ |
| 牌组管理 | test_deck_manager.gd | 6 | ✅ |
| 出牌校验 | test_play_validator.gd | 30 | ✅ |
| 规则配置 | test_rule_config.gd | 9 | ✅ |
| 对局控制器 | test_session_controller.gd | 35 | ✅ |
| 对局状态 | test_session_state.gd | 21 | ✅ |
| 结算系统 | test_settlement.gd | 19 | ✅ |
| 跳级序列 | test_skip_sequence.gd | 11 | ✅ |
| 队伍等级 | test_team_ranks.gd | 13 | ✅ |
| 亮主系统 | test_trump_bidding.gd | 24 | ✅ |
| 主牌判定 | test_trump_judge.gd | 11 | ✅ |
| **总计** | **12 files** | **210** | **✅** |

## Test Evidence by Story Type

根据 `.claude/docs/coding-standards.md` 定义的测试标准：

| Story Type | Required Evidence | Location | Gate Level |
|---|---|---|---|
| **Logic** (formulas, AI, state machines) | Automated unit test — must pass | `src/godot/tests/` | BLOCKING |
| **Integration** (multi-system) | Integration test OR documented playtest | `src/godot/tests/` | BLOCKING |
| **Visual/Feel** (animation, VFX, feel) | Screenshot + lead sign-off | `production/qa/evidence/` | ADVISORY |
| **UI** (menus, HUD, screens) | Manual walkthrough doc OR interaction test | `production/qa/evidence/` | ADVISORY |
| **Config/Data** (balance tuning) | Smoke check pass | `production/qa/smoke-[date].md` | ADVISORY |

## CI/CD Integration

**预期行为**（待配置）：
- 每次 push 到 main 自动运行测试
- PR 合并前必须测试通过
- 失败的测试会阻止合并

**当前状态**：CI/CD 管道尚未配置，测试需手动运行

**TODO**: 运行 `/test-setup` 创建 GitHub Actions workflow

## Assertion Guidelines

GUT 提供的常用断言：

```gdscript
assert_eq(got, expected, "msg")      # 相等
assert_ne(got, expected, "msg")      # 不相等
assert_true(condition, "msg")        # 真值
assert_false(condition, "msg")       # 假值
assert_null(value, "msg")            # null
assert_not_null(value, "msg")        # 非 null
assert_gt(got, expected, "msg")      # 大于
assert_lt(got, expected, "msg")      # 小于
assert_has(container, item, "msg")   # 包含
```

## Test Naming Conventions

- **文件名**: `test_[system].gd` (snake_case)
- **测试函数**: `test_[scenario]_[expected]` (snake_case)
- **示例**:
  - `test_normal_card_creation`
  - `test_trump_pair_beats_side_pair`
  - `test_attack_team_upgrades_when_attack_wins`

## Test Data Fixtures

- 测试数据应使用常量或工厂函数，不要硬编码魔法数字
- 边界值测试除外（边界值本身就是测试重点）
- 每个测试应独立设置和清理自己的状态

## What NOT to Test

- 视觉保真度（shader 输出、VFX 外观、动画曲线）
- "手感"质量（输入响应度、感知重量、时机）
- 平台特定渲染（在目标硬件上测试，不要无头测试）
- 完整游戏会话（由 playtest 覆盖，不要自动化）

## Common Test Patterns

### Pattern 1: 状态机测试

```gdscript
func test_state_transition():
    var sm = StateMachine.new()
    sm.enter_state(State.IDLE)
    assert_eq(sm.current_state, State.IDLE)
    
    sm.process_event(Event.START)
    assert_eq(sm.current_state, State.RUNNING)
```

### Pattern 2: 数据驱动测试

```gdscript
func test_point_values():
    var cases = [
        {"rank": Rank.FIVE, "points": 5},
        {"rank": Rank.TEN, "points": 10},
        {"rank": Rank.KING, "points": 10},
    ]
    for case in cases:
        var result = Card.get_points(case.rank)
        assert_eq(result, case.points, "Rank %s" % case.rank)
```

### Pattern 3: 异常路径测试

```gdscript
func test_invalid_input_rejected():
    var validator = PlayValidator.new()
    var result = validator.validate([])  # 空手牌
    assert_false(result.is_valid)
    assert_true(result.error_msg.length() > 0)
```

## Sprint 3 Test Verification

**验证日期**: 2026-07-26  
**命令**:
```bash
cd src/godot
$GODOT_EXE --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

**结果**:
```
Scripts              12
Tests               210
Passing Tests       210
Asserts             913
Time              0.628s

---- All tests passed! ----
```

**覆盖的系统**: 所有核心游戏逻辑系统（F1-F3, C1-C7）  
**未覆盖**: UI 层（P1-P5）和 AI 系统（FT1）— 这些系统需要手动测试或集成测试

## Future Improvements

1. **UI 测试**: 考虑使用 Godot 的 `InputEventAction` 模拟 UI 交互测试
2. **集成测试**: 添加端到端测试覆盖完整游戏流程
3. **性能基准**: 添加性能回归测试（帧时间、内存使用）
4. **CI/CD**: 配置 GitHub Actions 自动运行测试
5. **覆盖率报告**: 集成代码覆盖率工具（如果 GUT 支持）
