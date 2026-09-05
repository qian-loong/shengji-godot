# Review Log — FT1 AI 基础决策 (`ai-basic.md`)

## Review — 2026-09-05 — Verdict: NEEDS REVISION → 已修订
Scope signal: M
Specialists: game-designer, systems-designer, qa-lead, ai-programmer, creative-director（资深综合）
Blocking items: 5 | Recommended: 10
Summary: 首次正式复评，针对 S5-04 补章（§4b SMART 模式）。现有已实现部分（三个测试开关 + 亮主/配底/基础跟牌）稳固；争议全部集中在**尚未实现的 SMART 设计契约完整性**。creative-director 裁定 CONCERNS：SMART 有 5 个阻塞缺口（score_play 公式量纲错、两副牌"铁最大"计数未定义、estimate_win_probability 无数值、hand_strength 无合成公式、喂分阈值依赖未解的 Q3），会迫使 S5-05 实现者做本属 GDD 的设计决策。GDD/代码默认值分歧（GDD=SMART，代码=SIMPLE 且 SMART 枚举不存在）经核实为前瞻契约，非缺陷。
Prior verdict resolved: First review

### 同会话修订（2026-09-05，共 15 项 blocker→fix）
用户决策：B2=按可组成结构计数；B5=位置性确定判据；范围=全量（5 阻塞 + 全 10 Recommended）。

- **B1** score_play 全因素归一化到 [0,1]、权重和=1.0、补量纲陷阱示例 + MAX_TRICK_POINTS=40
- **B2** §4b "铁最大"改按可组成结构计数（副本 ≥2 份门槛）+ Q 对反例
- **B3-win** estimate_win_probability 补三分支七行定值表
- **B4-hand** hand_strength 补合成公式 + TRUMP_STRONG_THRESHOLD=0.45 替换"平均值"
- **B5** §4b 喂分改位置性确定判据（搭档赢墩且后续无对手），避开 Q3
- **B-dump** §4b 补 C2 合法牌型自校验门；纠正 challenge_dump 降级语义（降被击败分量，归 C2）
- **B-arch** States：已出记录=引擎侧共享公开、剩余张数=派生不存储、ADR-0004 前置
- **R1/R2/R3/R8** AC 全重写：证据类型分类 + 统计协议(1000局) + seed 黄金基准 + AC1≥1000墩；新增 AC17/18
- **R4** E3 改确定性 trump_strength≥4；Tuning Knobs 删"反主概率"换 COUNTER_BID_THRESHOLD
- **R5** §4b 庄家方留后手显式归 FT3/FT4
- **R6** Interactions + Dependencies 补 C6 软依赖 + score_gap
- **R7** §4 首出/跟牌清单标注"非 SMART 路径"，权威定义归 §4b
- **R9** Tuning Knobs 补安全区间列
- **GD-B1** §4b 补 SMART 体验走廊（下庄率 [0.45,0.60]、墩数降幅≤10%）作为验收门槛
- **GD-B2/Fantasy** 顶部加 v1.x/v2.0 版本门控；Player Fantasy 澄清喂分为 MVP 合理感、深度配合归 FT3

**待新会话二次复评验证**（`/clear` 后 `/design-review design/gdd/ai-basic.md`）。

## Review — 2026-09-05（二次） — Verdict: NEEDS REVISION → 已修订
Scope signal: M
Specialists: game-designer, qa-lead, ai-programmer, godot-gdscript-specialist, creative-director（资深综合）；公式边界层主评审亲验（systems-designer 子代理两次环境超时）
Blocking items: 5 | Recommended: 5（+若干 nice-to-have）
Summary: 对上一轮 15 项修订做验证性复评。上轮修订大体健全（score_play 归一化算术亲验全对、win_probability 无排序矛盾、版本门控清晰），但**新引入 2 缺陷 + 漏抓 2 既有缺口 + 1 文书错**：A1 ADR-0004 与已存在的 counter-bid ADR 编号冲突（应 ADR-0005）；A2 `get_legal_plays()` 全代码库无实现（工程双专家读码独立确认），且甩牌 shape 校验误绑该未实现接口（正确 API=validate_lead）；A3 hand_strength 全主牌 total_side_suits=0 除零；A4 归一化常数 8/6 在两副牌下被突破（拖拉机26/分牌24）；A5 配底扣的 8 张底牌打破"共享公开记录"模型（庄家有非对称私有知识）。多专家跨领域收敛：喂分位置性判据触发率仅~10%（game-designer 座位数学 + qa-lead 统计样本量双路指向同一稀疏性）；性能担忧被 godot-specialist 实算证伪（非阻塞）。
修订：5 阻塞全部手术式修入（约 40 行）+ 记牌座位归属/墩内可见性/更新时机、RNG 可复现契约、N_min=100、AC0、AC19/20、喂分低频注记、kill_value 兑换率、AC16 基准时点。用户决策：喂分保留保守判据+补注记（不加次级启发式，概率化留 FT3）；get_legal_plays 保留枚举架构、列 S5-05 前置；归一化常数取理论上界 26/24。memory `ft1-smart-s5-05` 同步 ADR 改号 + 本轮发现。
Prior verdict resolved: 上轮 15 项 Yes；本轮 5 阻塞已修，待新会话二次复评验证。

## Review — 2026-09-05（三次） — Verdict: NEEDS REVISION → 已修订
Scope signal: L（升级：多前置交付物 get_legal_plays + ADR-0005 + RNG 注入 + game_state 扩展）
Specialists: godot-gdscript-specialist, ai-programmer, systems-designer, qa-lead, game-designer（Senior Verdict 由主评审代行——creative-director 三次环境超时未产出）
Blocking items: 6 | Recommended: 7（+2 nice-to-have）
Summary: 对二次修订做验证性复评。**前两轮 20 项修订全部验证站得住**（score_play 归一化、win_probability、版本门控、除零、26/24 上界）。本轮价值在于**双工程专家读码暴露 6 组前两轮纯设计视角不可能发现的"实现前接缝"**（非推翻性缺陷）：C1 `make_game_state()` 缺墩内进行中出牌、SMART 跟牌流水线无数据源（ai-programmer + godot **独立收敛**同一处）；C2 `MAX_TRICK_POINTS=40` 只对单张墩成立、对子墩80/拖拉机墩160 溢出使 v_pts>1 破坏 score∈[0,1]、kill_value 判据失判别力（systems-designer 验算，前两轮 B1 仅验单张墩场景漏此）；C3 `decide_bid` 全局 randf() 使 AC16 黄金基准在 RNG 迁移前无法抓取（时序死锁，ai-programmer+qa-lead 收敛）；C4 AC16 逐字节可复现在 GDScript 层物理不可达（Dictionary 遍历序+sort_custom 不稳定+get_sort_value 缺全序，现有 ai_player.gd 已违反，godot 专家新发现）；C5 AC0 级联阻塞 11/21 条 AC 标注不足 + AC20 基线来源未定义（qa-lead）；C6 AC7 频率型单测可能永判 INCONCLUSIVE、核心配合 AC 实际不可验证（qa-lead+game-designer）。game-designer 博弈层独立给 APPROVED（0 阻塞）：喂分低频不破坏支柱1（措辞是"可感知"非"频繁可见"、真人搭档亦不墩墩喂分、垫牌不送分是隐性配合），庄家方贪婪即出铁最大=中等玩家标准打法恰当。
修订：6 阻塞全部手术式修入 + 7 建议（§R10 收敛实例方法/缩小 ADR-0005 范围、AC13 spy AST化、反主 private_known_cards 快照时序、AC9/AC20 优先级、s_prot 二值局限、AC19 三级判定、AC11 措辞量化、Player Fantasy 隐性配合 framing、get_legal_plays 跟牌枚举语义）。用户决策（4 项）：MAX_TRICK_POINTS 按结构动态 cards_per_play×4×10；AC7 拆三条（deterministic/frequency/AC7b）；§R10 GDD 直接推荐实例方法；AC9/AC20 张力以 AC20 优先、AC9 可降 20%。
Prior verdict resolved: 前两轮 20 项 Yes；本轮 6 阻塞已修，待新会话三次复评验证。

## Review — 2026-09-05（四次） — Verdict: APPROVED（有条件→修订后即批准）
Scope signal: L（多前置交付物 get_legal_plays + ADR-0005 + RNG 注入 + game_state 扩展）
Specialists: ai-programmer, systems-designer, game-designer, qa-lead, godot-gdscript-specialist（读码核对，主评审亲验）, creative-director（资深综合）
Blocking items: 3（去重后）| Recommended: 7（+若干 nice-to-have）
Summary: 对三次修订做验证性复评。**前三轮 26 项修订全部验证站得住**（kill_value 外的归一化、win_probability、版本门控、除零、26/24 上界、AC0/AC19/AC20、C1-C6）。creative-director 裁决**有条件 APPROVE**：3 阻塞均为手术式文档修订（≤15 行、零机制变更），修订后即满足"前瞻契约不迫使实现者做设计决策"标准。3 阻塞去重后：(A1) `kill_value` 求和多张杀溢出 [0,1]（大小王杀对子墩 1.93、拖拉机墩 2.93）使对子/拖拉机墩杀牌判据永假——**ai-programmer 与 systems-designer 从溢出/比较语义两视角独立收敛到同一行**，本轮最强信号；是 C2 `MAX_TRICK_POINTS` 修正的遗漏镜像（分母放大分子未归一）→改取 max 单张与 `play_strength` 对齐。(A2) §5 通用骨架（枚举→score_play→取最高）与 §4b 优先级短路**双权威冲突**，实现者不知 SMART follow 用不用 score_play→明确 §4b 短路为 SMART 权威、通用骨架为非 SMART 路径、score_play 仅 §4b 分支内当局部工具。(A3) AC6 遗漏 AC0 级联清单（AC6 测 SMART 首出依赖 SMART 实现）→11 补 12 条。专家分歧诊断：game-designer 给 APPROVED（体验层健全）vs 工程三专家给多阻塞（实现层有接缝）经 CD 判为"非冲突、健康的分层复评"——愿景对、蓝图三处须临场发挥。godot 读码亲验 5 项技术声明（make_game_state 4 字段/get_sort_value 两副同名/deck_id tie-break/ai_player.gd 违反 Dictionary 禁令/decide_bid 全局 randf）全属实，C4 论证成立、文档无误导实现的技术错误。
修订：3 阻塞手术式修入 + 7 建议（A4 estimate_win_probability 分支判定顺序 + 等值归压不过、A5 seat_id 可得性注、A6 主牌域拓扑归 C1/F1、A7 AC7-frequency 禁构造牌局注水 <100 降 ADVISORY、A8 AC13「AST 级」降 grep+debug spy、A9 RNG/基准/SMART 三步不可压缩、Q4 kill_value 兑换系数入 Open Questions）。修订均文档措辞级、零机制变更，同会话完成，未再跑代理复评。
Prior verdict resolved: 前三轮 26 项 Yes；本轮 3 阻塞 + 7 建议已修，设计层 Approved。剩余全部为 S5-05 实现期工作（get_legal_plays 实现、ADR-0005、RNG 注入、game_state 扩展、SMART 决策 + 测试）。
