# Test Fixtures — AC16 黄金基准 (FT1 SMART / S5-05)

本目录存放 **AC16 逐字节可复现黄金基准**与 **AC20 墩数基线**，供 FT1 SMART 实现验收。

> ⚠️ **不可逆窗口产物。** 这批基准在 **RNG 注入完成后、SMART 上线前、代码仍默认 SIMPLE** 时抓取
> （2026-09-05，commit 见 git log）。SMART 上线后 `lead_strategy` 默认改变，同 seed 输出漂移，
> **无法重新生成**。请勿删除或覆盖，除非明确要重建基准（须先回退到 SIMPLE 默认 + RNG 注入态）。

## 三个归档文件

| 文件 | 内容 | 用于 |
|------|------|------|
| `ac16_trick_hashes.json` | 每 seed 一局 SIMPLE 对局的规范化每墩输出 SHA-256 哈希 | **AC16** 逐字节可复现 |
| `baseline_simple_stats.json` | 聚合统计：平均墩数/牌局、stddev、下庄率 | **AC20**（墩数降幅 ≤ 10%）、**AC19**（下庄率走廊 [0.45,0.60]）对照 |
| `ac16_seeds.json` | seed 列表（preset / seed_base / count / max_rounds） | 复现 + 语料库定义 |

## 生成方式

```bash
GODOT_EXE=<console build> python tools/batch/capture_ac16_baseline.py \
    --preset classic --seeds 1000 --seed-base 1000 --max-rounds 30
```

## AC16 怎么比对（SMART 实现时）

哈希输入 = 每局每墩的规范化 `(trick_num, lead_seat, [(seat, cards)...], winner)` 序列
（`tools/batch/capture_ac16_baseline.py` 的 `normalize_game` / `hash_game`）。

SMART 实现后，用**显式 `--lead-strategy=simple`** 重跑同一批 seed，对每 seed 重算哈希，
与 `ac16_trick_hashes.json` 逐一比对：

- **全部一致** → SIMPLE 路径未被 SMART 改动破坏，AC16 PASS。
- **任一不一致** → SMART 的改动泄漏到了 SIMPLE 路径（或引入了非确定源，如 Dictionary 有序遍历、
  非全序 sort_custom），必须定位修复——这正是 AC16 要守护的回归。

> 注：AC16 只保证**纯 AI + 固定 seed + SIMPLE** 逐字节可复现（GDD §可复现契约）。
> 含人类交互的对局不在契约内。SMART 自身的可复现由其单一注入 RNG 保证，另测。

## AC20 怎么比对

`baseline_simple_stats.json` 的 `mean_tricks_per_round` 是 SIMPLE 基线。
SMART 实现后同批 seed 跑 SMART，算平均墩数：

- SMART 平均墩数 ≥ SIMPLE × 0.90 → 降幅 ≤ 10%，AC20 PASS（对局未被打太短）。
- 走廊张力（AC9 结构使用率 vs AC20 墩数降幅）以 AC20 优先，见 ai-basic.md §4b 走廊表。
