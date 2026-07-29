# Headless 配置批跑（集成/系统级）

对 **SessionController 全链路 + AI** 做多配置无头对局，属于 **集成测试 / 系统回归**，不是 GUT 单测。

## 这是不是集成测试？

| 类型 | 本批跑 | GUT `tests/unit/**` |
|------|--------|---------------------|
| 范围 | 规则 + 会话 + AI + 日志 | 单模块函数 |
| 有无 UI | 无（headless） | 无 |
| 断言 | **每局规则复算校验** + 统计报告 + 进程成功 | assert |
| 随机性 | 有（需多种 seed） | 尽量确定性 |

结论：**是集成级自动化**，验证「该 RuleConfig 下整盘能跑完、且每一墩/每一局的逻辑经得起独立复算」；**不能**替代 GUI 体验测试。

## 正确性校验

跑得完 ≠ 跑得对。`run_batch.py` 每局结束后调用 `tools/validate_game_log.py`，
从日志的 `rule_config` 读规则并独立复算：牌型、赢墩、跟牌合法性、牌张归属、
墩分与累计分、结算全字段、跨局庄家轮转与队伍等级连续性、牌张与总分守恒。

```bash
# 单独校验一个日志或一整个批跑目录
python tools/validate_game_log.py logs/batch/<run_id>/ -v
python tools/validate_game_log.py <game_log.json> --json

# 跳过校验（只看进程退出码 —— 此时结果不能证明逻辑正确）
python tools/batch/run_batch.py <manifest> --no-validate
```

校验器零硬编码规则常量，全部规则从日志读取；日志缺必需字段时直接 FATAL，
不套用默认值假装通过。2026-07-28 之前生成的日志没有 `upgrade_table`，会被拒绝，
需用当前版本重新生成。

回归测试（含变异检出，确保校验器不是"沉默通过"）：

```bash
python tools/tests/test_validate_game_log.py
```

## HTML 复盘页

```bash
python tools/export_game_log_html.py <game_log.json> [-o out.html]
```

单文件 HTML，含每局概览、每墩四家出牌、手牌前后对照、问题清单与人工订正框。
**规则判定全部委托 `validate_game_log.py`**，导出器只负责渲染 —— 它自己不再持有
任何规则实现，因此不会像旧版那样随配置系统演进而失效。

> 旧的 `analyze_game_log.py` 已删除：5 项检查全部被校验器覆盖且更强，
> 且它的拖拉机判定不处理跨级牌跳接（打 7 时 `66+88` 会被误判），
> 结果还写在废弃路径 `docs/game-logs/`。

## 流程

```text
matrix JSON  (实验设计，可进 git)
    ↓ generate_matrix.py
configs/batch/<name>/*.json + manifest.json  (生成物，可选提交)
    ↓ run_batch.py   ← 每局跑完即校验
logs/batch/<run_id>/<case>/game_*.json
    ↓ summarize_batch.py
logs/batch/<run_id>/summary.md
```

## 命令

```bash
# 0) 环境
export GODOT_EXE="E:/DevTools/Godot/Godot_v4.6.2-stable_win64_console.exe"  # 按本机

# 1) 展开单因子矩阵（三预设各有一份）
python tools/batch/generate_matrix.py tools/batch/matrix_single_factor_quick.json
python tools/batch/generate_matrix.py tools/batch/matrix_single_factor_classic.json
python tools/batch/generate_matrix.py tools/batch/matrix_single_factor_competitive.json

# 2) 冒烟：每 case 1 局，最多 5 局封顶
python tools/batch/run_batch.py configs/batch/single_factor_quick_v1/manifest.json --games 1 --max-rounds 5

# 3) 汇总
python tools/batch/summarize_batch.py logs/batch/<run_id>/run_results.json
```

正式扫描可加大 `--games`（如 20）并去掉过小的 `--max-rounds`。

退出码：进程失败**或**规则违规都返回 1，可直接用于 CI 门禁。

## Headless CLI（game_session.gd）

```text
godot --headless --path src/godot --script res://scripts/gameplay/game_session.gd \
  --preset=quick \
  --config=D:/path/to/case.json \
  --seed=42 \
  --max-rounds=20 \
  --log-path=D:/path/to/out.json \
  --case-id=baseline
```

优先级：`--config` > `--preset` > 默认经典预设。

配置文件格式 = `RuleConfig.to_dict()` JSON（由 `generate_matrix.py` 生成）。

## 目录约定

| 路径 | 是否进 git | 说明 |
|------|------------|------|
| `tools/batch/matrix_*.json` | 是 | 实验设计 |
| `tools/batch/*.py` | 是 | 工具 |
| `tools/validate_game_log.py` | 是 | 规则校验器 |
| `tools/tests/**` | 是 | 校验器回归测试与 fixture |
| `configs/batch/**` | 可选 | 生成的 case 配置 |
| `logs/batch/**` | 否 | 运行日志与 summary |

## 限制

1. 反映的是 **当前 AI** 在该规则下的表现，不是真人平衡  
2. 需足够 seed/局数才有统计意义  
3. 部分规则（跟牌松紧）若 AI 很少触达，差异可能不明显  
4. 跟牌合法性依赖 `debug.hands_at_play_start` 快照；关掉 debug 日志后
   该项会被跳过并在报告中列出（不会静默略过）
