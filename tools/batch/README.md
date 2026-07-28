# Headless 配置批跑（集成/系统级）

对 **SessionController 全链路 + AI** 做多配置无头对局，属于 **集成测试 / 系统回归**，不是 GUT 单测。

## 这是不是集成测试？

| 类型 | 本批跑 | GUT `tests/unit/**` |
|------|--------|---------------------|
| 范围 | 规则 + 会话 + AI + 日志 | 单模块函数 |
| 有无 UI | 无（headless） | 无 |
| 断言 | 统计/对比报告 + 进程成功 | assert |
| 随机性 | 有（需多种 seed） | 尽量确定性 |

结论：**是集成级自动化**，验证「该 RuleConfig 下整盘能跑完、结算/日志字段合理」；**不能**替代 GUI 体验测试。

## 流程

```text
matrix JSON  (实验设计，可进 git)
    ↓ generate_matrix.py
configs/batch/<name>/*.json + manifest.json  (生成物，可选提交)
    ↓ run_batch.py
logs/batch/<run_id>/<case>/game_*.json
    ↓ summarize_batch.py
logs/batch/<run_id>/summary.md
```

## 命令

```bash
# 0) 环境
export GODOT_EXE="E:/DevTools/Godot/Godot_v4.6.2-stable_win64_console.exe"  # 按本机

# 1) 展开单因子矩阵（快速基底）
python tools/batch/generate_matrix.py tools/batch/matrix_single_factor_quick.json

# 2) 冒烟：每 case 1 局，最多 5 局封顶
python tools/batch/run_batch.py configs/batch/single_factor_quick_v1/manifest.json --games 1 --max-rounds 5

# 3) 汇总
python tools/batch/summarize_batch.py logs/batch/<run_id>/run_results.json
```

正式扫描可加大 `--games`（如 20）并去掉过小的 `--max-rounds`。

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
| `configs/batch/**` | 可选 | 生成的 case 配置 |
| `logs/batch/**` | 否 | 运行日志与 summary |

## 限制

1. 反映的是 **当前 AI** 在该规则下的表现，不是真人平衡  
2. 需足够 seed/局数才有统计意义  
3. 部分规则（跟牌松紧）若 AI 很少触达，差异可能不明显  
