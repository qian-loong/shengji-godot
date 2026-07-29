#!/usr/bin/env python3
"""把对局日志导出成单文件的交互式 HTML 复盘页。

**规则判定全部委托 tools/validate_game_log.py**，本文件只负责可视化。

历史上这个导出器自带一整套规则实现（域判定 / 牌型 / 赢墩 / 结算复算约 340 行），
目的是"独立复算以暴露分歧"。但它随配置系统演进而失效——不认 upgrade_step、
按 rank 而非 identity 统计对子、four_same 用旧语义——对 quick 预设会报出 20 条
全假的错误，噪声把真问题淹没。现在统一由校验器提供判定，本文件不再持有第二套规则。

用法:
  python tools/export_game_log_html.py <game_log.json> [-o out.html]
"""

from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from validate_game_log import (  # noqa: E402
    Card,
    LogFormatError,
    LogValidator,
    RuleConfig,
    Rules,
    force_utf8_stdout,
    parse_cards,
    rank_symbol,
)

SUIT_ID_TO_SYMBOL = {0: "♠", 1: "♥", 2: "♦", 3: "♣"}
SEAT_NAMES = ["南 / 你", "东", "北 / 搭档", "西"]
TEAM_NAMES = ["南北队", "东西队"]

DOMAIN_TRUMP = 0
DOMAIN_SIDE = 1


# ============================================================
# 分析适配层：校验器的扁平 issue 列表 → 渲染层需要的分组结构
# ============================================================


def build_analysis(log: Dict[str, Any]) -> Dict[str, Any]:
    """跑校验并整理成渲染层期望的结构。

    校验器返回的是扁平的 Issue 列表（每条带 round_num / trick_num），
    这里按局、按墩归位，并附上每局的复算结算值用于"日志 vs 复算"对照。
    """
    validator = LogValidator(log)
    issues = validator.validate()

    by_round: Dict[Any, List[Dict[str, Any]]] = {}
    by_trick: Dict[Any, Dict[Any, List[Dict[str, Any]]]] = {}
    for issue in issues:
        entry = issue.to_dict()
        if issue.trick_num is not None:
            by_trick.setdefault(issue.round_num, {}).setdefault(
                issue.trick_num, []).append(entry)
        else:
            by_round.setdefault(issue.round_num, []).append(entry)

    round_reports: List[Dict[str, Any]] = []
    prev_expected_dealer: Optional[int] = None

    for idx, round_data in enumerate(log.get("rounds", [])):
        round_num = round_data.get("round_num", idx + 1)
        trick_issue_map = by_trick.get(round_num, {})

        trick_reports = []
        for t_idx, trick in enumerate(round_data.get("tricks", [])):
            trick_num = trick.get("trick_num", t_idx + 1)
            trick_reports.append({
                "trick": trick,
                "issues": trick_issue_map.get(trick_num, []),
            })

        # 该局的问题 = 局级问题 + 所有墩级问题（供概览徽章计数）
        own_issues = list(by_round.get(round_num, []))
        all_round_issues = own_issues + [
            i for lst in trick_issue_map.values() for i in lst
        ]

        recomputed = validator.round_reports.get(round_num, {})
        expected = recomputed.get("effective", {})

        settlement = round_data.get("settlement") or {}
        dealer = int(round_data.get("dealer", 0))
        next_dealer = settlement.get("new_dealer")
        if not isinstance(next_dealer, int) or next_dealer < 0:
            next_dealer = dealer

        round_reports.append({
            "round": round_data,
            "issues": all_round_issues,
            "round_issues": own_issues,
            "tricks": trick_reports,
            "expected_settlement": expected,
            "expected_next_dealer": None if settlement.get("game_over") else next_dealer,
            "dealer_reason": describe_dealer_rotation(
                prev_expected_dealer, dealer, round_data.get("bid_history", [])),
        })
        prev_expected_dealer = None if settlement.get("game_over") else next_dealer

    return {
        "rounds": round_reports,
        "issues": [i.to_dict() for i in issues],
        "skipped": validator.skipped_checks,
        "config": validator.config,
        "rules": validator.rules,
    }


# ============================================================
# 展示用的牌面排序（非规则判定，只影响手牌的显示顺序）
# ============================================================


def sort_raw_cards_for_display(
    raw_cards: List[str], rules: Rules, trump_suit: int, current_rank: int
) -> List[str]:
    try:
        parsed = parse_cards(raw_cards)
    except LogFormatError:
        return list(raw_cards)
    parsed.sort(key=lambda c: (
        card_display_group(c, rules, trump_suit, current_rank),
        -rules.sort_value(c, trump_suit, current_rank),
        card_identity_key(c),
    ))
    return [c.raw for c in parsed]


def card_display_group(
    card: Card, rules: Rules, trump_suit: int, current_rank: int
) -> int:
    """主牌排最前，副牌按 ♣♥♠♦ 分组——纯展示分组，与规则无关。"""
    if rules.suit_domain(card, trump_suit, current_rank)[0] == DOMAIN_TRUMP:
        return 0
    return {3: 1, 1: 2, 0: 3, 2: 4}.get(card.suit, 5)


def card_identity_key(card: Card) -> str:
    if card.is_joker:
        return f"joker:{card.joker_type}"
    return f"{card.suit}:{card.rank:02d}"


# ============================================================
# 手牌快照重建
# ============================================================


def remove_cards(source: List[str], removed: Iterable[str]) -> List[str]:
    result = list(source)
    for card in removed:
        try:
            result.remove(card)
        except ValueError:
            pass
    return result


def hand_snapshots(hands: List[List[str]]) -> List[Dict[str, Any]]:
    return [
        {"seat": seat, "cards": list(hand), "count": len(hand)}
        for seat, hand in enumerate(hands)
    ]


def reconstruct_hand_snapshots(log: Dict[str, Any]) -> None:
    """给每墩补上 _hands_before / _hands_after，供页面展示手牌变化。

    优先用 debug.hands_at_play_start（引擎在进入出牌阶段时直接快照）。
    退化路径 initial_hands - 埋底在**反抢局下不可靠**：庄家先埋一次、
    反家再埋一次，log_bury 第二次会覆盖第一次，原庄家埋了什么无从得知。
    数据不足时跳过该局而不是抛异常——可视化不该因为缺可选字段就整个失败。
    """
    for round_data in log.get("rounds", []):
        tricks = round_data.get("tricks", [])
        if not tricks:
            continue

        debug = round_data.get("debug") or {}
        snapshot = debug.get("hands_at_play_start")
        if isinstance(snapshot, list) and len(snapshot) == 4 and all(snapshot):
            hands = [list(h) for h in snapshot]
        else:
            initial = debug.get("initial_hands")
            if not isinstance(initial, list) or len(initial) != 4:
                continue
            hands = [list(h) for h in initial]
            merged = debug.get("hand_with_bottom")
            buried = round_data.get("buried_cards") or debug.get("buried_cards")
            bid = round_data.get("bid")
            bury_seat = int(bid["seat"]) if isinstance(bid, dict) and "seat" in bid \
                else int(round_data.get("dealer", 0))
            if isinstance(merged, list) and merged and isinstance(buried, list):
                hands[bury_seat] = remove_cards(list(merged), buried)

        for trick in tricks:
            trick["_hands_before"] = hand_snapshots(hands)
            for play in trick.get("plays", []):
                seat = int(play.get("seat", 0))
                hands[seat] = remove_cards(hands[seat], play.get("cards", []))
            trick["_hands_after"] = hand_snapshots(hands)


def find_hand_before(trick: Dict[str, Any], seat: int) -> List[str]:
    for hand in trick.get("_hands_before", []):
        if hand.get("seat") == seat:
            return hand.get("cards", [])
    return []


def find_hand_after(trick: Dict[str, Any], seat: int) -> List[str]:
    for hand in trick.get("_hands_after", []):
        if hand.get("seat") == seat:
            return hand.get("cards", [])
    return []


def normalize_html_output(content: str) -> str:
    return "\n".join(line.rstrip() for line in content.splitlines()) + "\n"


def normalize_bid_history(raw_history: Any) -> List[Dict[str, Any]]:
    if isinstance(raw_history, list):
        return [h for h in raw_history if isinstance(h, dict)]
    if isinstance(raw_history, dict):
        return [raw_history]
    return []


def format_skip_reason(reason: Any) -> str:
    if reason == "no_valid_cards":
        return "无可定主牌"
    if reason == "player_choice":
        return "玩家选择不定主"
    if reason == "ai_pass":
        return "AI 放弃定主"
    if reason == "already_bid":
        return "已有他人定主"
    if reason == "bid_rejected":
        return "定主被拒"
    return str(reason or "unknown")


def describe_dealer_rotation(expected_dealer: Optional[int], actual_dealer: int, raw_bid_history: Any) -> str:
    bid_history = normalize_bid_history(raw_bid_history)
    first_bid = next((b for b in bid_history if b.get("action") == "bid"), None)
    if expected_dealer is None:
        if first_bid:
            return "首局由 S%d 亮 %s，成为庄家。" % (first_bid.get("seat"), first_bid.get("suit_symbol", "主"))
        return "首局未记录亮主成功者。"

    if actual_dealer == expected_dealer:
        if first_bid and first_bid.get("seat") == actual_dealer:
            return "上局结算期望庄家 S%d，本局由其成功亮 %s，庄家不变。" % (
                expected_dealer,
                first_bid.get("suit_symbol", "主"),
            )
        return "上局结算期望庄家 S%d，本局庄家不变。" % expected_dealer

    parts = ["上局结算期望庄家 S%d 先定主" % expected_dealer]
    seat = expected_dealer
    while seat != actual_dealer:
        skip = next((b for b in bid_history if b.get("seat") == seat and b.get("action") == "skip"), None)
        if skip:
            parts.append("S%d 跳过（%s）" % (seat, format_skip_reason(skip.get("reason"))))
        else:
            parts.append("S%d 未见跳过记录" % seat)
        seat = (seat + 1) % 4
        if len(parts) > 6:
            break
    if first_bid:
        parts.append("S%d 亮 %s，庄家顺延为 S%d" % (
            first_bid.get("seat"),
            first_bid.get("suit_symbol", "主"),
            actual_dealer,
        ))
    else:
        parts.append("最终庄家为 S%d，但未见亮主成功记录" % actual_dealer)
    return "；".join(parts) + "。"


def render_html(log: Dict[str, Any], analysis: Dict[str, Any], source_path: Path) -> str:
    title = f"双升日志复盘 - {source_path.name}"
    nav = []
    sections = []
    for idx, report in enumerate(analysis["rounds"]):
        r = report["round"]
        errors = sum(1 for i in report["issues"] if i["level"] == "error")
        warnings = sum(1 for i in report["issues"] if i["level"] == "warning")
        badge = f"{errors} 错 / {warnings} 警"
        nav.append(f'<button class="round-tab" data-target="round-{idx}">第 {esc(r.get("round_num", idx + 1))} 局 <span>{esc(badge)}</span></button>')
        sections.append(render_round(report, idx, analysis["rules"]))

    corrections_seed = {"source": str(source_path), "created_from": log.get("created_at"), "corrections": {}}
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{esc(title)}</title>
  <style>{CSS}</style>
</head>
<body>
  <header class="app-header">
    <div>
      <h1>{esc(title)}</h1>
      <p>日志时间：{esc(log.get("created_at", "未知"))} · 总局数：{len(analysis["rounds"])} · 自动分析：{len(analysis["issues"])} 项问题/提示</p>
    </div>
    <div class="header-actions">
      <button id="expand-all">展开全部墩</button>
      <button id="collapse-all">收起全部墩</button>
      <button id="export-corrections">导出订正 JSON</button>
    </div>
  </header>
  <nav class="round-nav">{''.join(nav)}</nav>
  <main>{''.join(sections)}</main>
  <script>
    window.REPLAY_CORRECTIONS_SEED = {json.dumps(corrections_seed, ensure_ascii=False)};
{JS}
  </script>
</body>
</html>
"""


def render_round(report: Dict[str, Any], idx: int, rules: Rules) -> str:
    r = report["round"]
    settlement = r.get("settlement", {})
    expected = report["expected_settlement"]
    issues_html = render_issues(report["issues"])
    tricks = "".join(render_trick(t_report, r, idx, rules) for t_report in report["tricks"])
    team_ranks = r.get("team_ranks_symbols") or [rank_symbol(v) for v in r.get("team_ranks", [])]
    bid_history = ", ".join(render_bid(b) for b in r.get("bid_history", [])) or "无"
    bottom = " ".join(r.get("debug", {}).get("bottom_cards", [])) or "无"
    buried = " ".join(r.get("debug", {}).get("buried_cards", [])) or "无"
    initial_hands = render_initial_hands(r, rules)
    correction_key = f"round-{r.get('round_num', idx + 1)}"
    return f"""
<section id="round-{idx}" class="round-section">
  <div class="round-grid">
    <article class="card summary">
      <h2>第 {esc(r.get("round_num", idx + 1))} 局概览</h2>
      <div class="kv">
        <span>庄家</span><b>S{esc(r.get("dealer"))} {esc(seat_name(r.get("dealer", 0)))}</b>
        <span>庄家队</span><b>{esc(team_label(r.get("dealer", 0) % 2))}</b>
        <span>攻方队</span><b>{esc(team_label((r.get("dealer", 0) + 1) % 2))}</b>
        <span>本局级</span><b>{esc(r.get("rank_symbol", rank_symbol(r.get("rank", 2))))}</b>
        <span>队伍级</span><b>{esc(" / ".join(team_ranks))}</b>
        <span>主花色</span><b>{esc(r.get("trump_suit_symbol") or r.get("bid", {}).get("suit_symbol", "未知"))}</b>
        <span>亮主</span><b>{esc(bid_history)}</b>
        <span>庄家原因</span><b>{esc(report.get("dealer_reason", ""))}</b>
      </div>
    </article>
    <article class="card summary">
      <h2>结算与轮庄</h2>
      <div class="kv">
        <span>攻方出牌分</span><b>{esc(settlement.get("attack_base_score"))}</b>
        <span>底牌奖励</span><b>{esc(settlement.get("bottom_score"))} × {esc(settlement.get("bottom_multiplier"))} = {esc(settlement.get("bottom_bonus"))}</b>
        <span>最终分</span><b>{esc(settlement.get("final_score"))}</b>
        <span>升级方</span><b>{esc("攻方" if settlement.get("upgrading_side") == 1 else "庄家方")}</b>
        <span>新级</span><b>{esc(settlement.get("new_rank_symbol", rank_symbol(settlement.get("new_rank", r.get("rank", 2)))))}</b>
        <span>新庄家</span><b>{esc(format_dealer(settlement.get("new_dealer")))}</b>
        <span>复算新庄家</span><b>{esc(format_dealer(expected.get("new_dealer")))}</b>
        <span>下局期望庄家</span><b>{esc(format_dealer(report.get("expected_next_dealer")))}</b>
      </div>
    </article>
    <article class="card summary wide">
      <h2>底牌与埋牌</h2>
      <p><b>底牌：</b>{render_cards(bottom.split())}</p>
      <p><b>埋牌：</b>{render_cards(buried.split())}</p>
    </article>
    {initial_hands}
  </div>
  {issues_html}
  <article class="card correction">
    <h2>本局人工订正</h2>
    <textarea data-correction-key="{esc(correction_key)}" placeholder="在这里记录本局订正、人工判定或待查问题。"></textarea>
  </article>
  <div class="trick-list">{tricks}</div>
</section>
"""


def render_initial_hands(round_data: Dict[str, Any], rules: Rules) -> str:
    hands = round_data.get("debug", {}).get("initial_hands", [])
    if not hands:
        return ""
    trump_suit = round_data.get("trump_suit", -1)
    current_rank = round_data.get("rank", 2)
    rows = []
    for seat, raw_hand in enumerate(hands):
        display_hand = sort_raw_cards_for_display(raw_hand, rules, trump_suit, current_rank)
        rows.append(
            f"""
<details class="initial-hand">
  <summary>S{seat} {esc(seat_name(seat))} 初始手牌（{len(display_hand)} 张）</summary>
  <div class="hand-cards">{render_cards(display_hand)}</div>
</details>
"""
        )
    return f"""
<article class="card summary wide">
  <h2>初始手牌</h2>
  <div class="initial-hands">{"".join(rows)}</div>
</article>
"""


def render_trick(t_report: Dict[str, Any], round_data: Dict[str, Any], round_idx: int, rules: Rules) -> str:
    t = t_report["trick"]
    issues = t_report["issues"]
    plays = {p.get("seat"): p for p in t.get("plays", [])}
    winner = t.get("winner")
    lead = t.get("lead_seat")
    title_class = "has-error" if any(i["level"] == "error" for i in issues) else ("has-warning" if issues else "")
    correction_key = f"round-{round_data.get('round_num')}-trick-{t.get('trick_num')}"
    seat_blocks = []
    for seat, pos in [(2, "north"), (3, "west"), (1, "east"), (0, "south")]:
        play = plays.get(seat, {})
        seat_blocks.append(render_seat_play(seat, play, pos, winner, lead))
    issue_html = render_issues(issues, compact=True)
    hand_html = render_hand_snapshots(t, round_data, rules)
    return f"""
<details class="trick-card" open>
  <summary class="{title_class}">
    <span>第 {esc(t.get("trick_num"))} 墩</span>
    <span>先手 S{esc(lead)} · 赢家 S{esc(winner)} {esc("攻方" if t.get("winner_side") == "attack" else "庄家方")} · 本墩 {esc(t.get("trick_points", t.get("trick_score")))} 分 · 攻方 {esc(t.get("attack_score_before"))} → {esc(t.get("attack_score_after"))}</span>
  </summary>
  <div class="trick-table">
    {''.join(seat_blocks)}
    <div class="center-pot">
      <b>最大：S{esc(winner)} {esc(seat_name(winner))}</b>
      <span>{esc(t.get("debug", {}).get("winner_reason", ""))}</span>
    </div>
  </div>
  {issue_html}
  <div class="play-detail">
    {''.join(render_play_detail(p, round_data) for p in t.get("plays", []))}
  </div>
  {hand_html}
  <div class="correction-inline">
    <label>本墩人工订正</label>
    <textarea data-correction-key="{esc(correction_key)}" placeholder="记录这一墩的人工订正。"></textarea>
  </div>
</details>
"""


def render_hand_snapshots(trick: Dict[str, Any], round_data: Dict[str, Any], rules: Rules) -> str:
    trump_suit = round_data.get("trump_suit", -1)
    current_rank = round_data.get("rank", 2)
    rows = []
    for seat in range(4):
        before = sort_raw_cards_for_display(find_hand_before(trick, seat), rules, trump_suit, current_rank)
        after = sort_raw_cards_for_display(find_hand_after(trick, seat), rules, trump_suit, current_rank)
        play = next((p for p in trick.get("plays", []) if p.get("seat") == seat), {})
        played = play.get("cards", [])
        if not before and not after:
            continue
        rows.append(
            f"""
<details class="hand-snapshot">
  <summary>S{seat} {esc(seat_name(seat))} 手牌：{len(before)} → {len(after)}</summary>
  <div class="hand-compare">
    <div>
      <b>出牌前</b>
      <div class="hand-cards">{render_cards(before, highlighted=played)}</div>
    </div>
    <div>
      <b>出牌后</b>
      <div class="hand-cards">{render_cards(after)}</div>
    </div>
  </div>
</details>
"""
        )
    if not rows:
        return ""
    return f'<div class="hand-snapshots"><h3>本墩前后手牌</h3>{"".join(rows)}</div>'


def render_seat_play(seat: int, play: Dict[str, Any], pos: str, winner: int, lead: int) -> str:
    tags = []
    if seat == winner:
        tags.append('<span class="tag win">最大</span>')
    if seat == lead:
        tags.append('<span class="tag lead">先手</span>')
    return f"""
<div class="seat-play {pos} {'winner' if seat == winner else ''}">
  <div class="seat-title">S{seat} {esc(seat_name(seat))} {''.join(tags)}</div>
  <div class="cards">{render_cards(play.get("cards", []))}</div>
  <div class="meta">{esc(play.get("pattern", ""))} · {esc(format_domain(play.get("domain")))} · v={esc("/".join(str(v) for v in play.get("sort_values", [])))}</div>
</div>
"""


def render_play_detail(play: Dict[str, Any], round_data: Dict[str, Any]) -> str:
    return f"""
<div class="play-row">
  <b>S{esc(play.get("seat"))} {esc(seat_name(play.get("seat", 0)))}</b>
  <span>{render_cards(play.get("cards", []))}</span>
  <code>{esc(play.get("pattern", ""))}</code>
  <code>{esc(format_domain(play.get("domain")))}</code>
  <code>{esc("/".join(str(v) for v in play.get("sort_values", [])))}</code>
</div>
"""


def render_issues(issues: List[Dict[str, Any]], compact: bool = False) -> str:
    if not issues:
        return '<div class="issues ok">未发现自动检测问题</div>' if not compact else ""
    rows = []
    for i in issues:
        rows.append(f'<li class="{esc(i["level"])}"><b>{esc(i["level"].upper())}</b> <code>{esc(i["code"])}</code> {esc(i["message"])}</li>')
    cls = "issues compact" if compact else "issues"
    return f'<ul class="{cls}">{"".join(rows)}</ul>'


def render_cards(raw_cards: Iterable[str], highlighted: Optional[Iterable[str]] = None) -> str:
    highlight_counts: Dict[str, int] = {}
    for card in highlighted or []:
        highlight_counts[card] = highlight_counts.get(card, 0) + 1
    tokens = []
    for card in raw_cards:
        classes = ["card-token", card_color(card)]
        if highlight_counts.get(card, 0) > 0:
            classes.append("played-highlight")
            highlight_counts[card] -= 1
        tokens.append(f'<span class="{" ".join(classes)}">{esc(card)}</span>')
    return "".join(tokens)


def card_color(raw: str) -> str:
    return "red" if raw.startswith("♥") or raw.startswith("♦") or raw == "RedJoker" else "black"


def esc(value: Any) -> str:
    return html.escape("" if value is None else str(value))


def seat_name(seat: Optional[int]) -> str:
    if seat is None or seat < 0 or seat > 3:
        return "无"
    return SEAT_NAMES[seat]


def team_label(team_idx: int) -> str:
    return TEAM_NAMES[team_idx] if team_idx in (0, 1) else "未知队"


def format_dealer(seat: Any) -> str:
    try:
        seat_int = int(seat)
    except (TypeError, ValueError):
        return "无"
    if seat_int < 0:
        return "不换庄"
    return f"S{seat_int} {seat_name(seat_int)}"


def format_domain(dom: Any) -> str:
    if not isinstance(dom, dict):
        return ""
    dtype = dom.get("type")
    suit = dom.get("suit", -1)
    if dtype == 0:
        return "主牌"
    if dtype == 1:
        return f"{SUIT_ID_TO_SYMBOL.get(suit, '?')}副"
    return "无域"


def render_bid(bid: Dict[str, Any]) -> str:
    action = bid.get("action")
    seat = bid.get("seat")
    if action == "bid":
        return f"S{seat} 亮 {bid.get('suit_symbol', '')}"
    return f"S{seat} 跳过({bid.get('reason', '')})"


CSS = """
:root { color-scheme: light; --bg:#f6f7fb; --card:#fff; --ink:#172033; --muted:#667085; --line:#d9deea; --red:#b42318; --green:#087443; --amber:#b54708; --blue:#175cd3; }
* { box-sizing: border-box; }
body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif; background:var(--bg); color:var(--ink); }
.app-header { position:sticky; top:0; z-index:10; display:flex; justify-content:space-between; gap:20px; align-items:center; padding:18px 28px; background:rgba(255,255,255,.94); border-bottom:1px solid var(--line); backdrop-filter: blur(10px); }
h1 { margin:0 0 6px; font-size:22px; }
h2 { margin:0 0 12px; font-size:18px; }
p { margin:6px 0; }
button { border:1px solid var(--line); background:#fff; color:var(--ink); padding:8px 12px; border-radius:10px; cursor:pointer; }
button:hover, .round-tab.active { border-color:var(--blue); color:var(--blue); box-shadow:0 0 0 3px rgba(23,92,211,.08); }
.header-actions { display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end; }
.round-nav { display:flex; gap:10px; padding:14px 28px; overflow:auto; }
.round-tab span { margin-left:8px; color:var(--muted); font-size:12px; }
main { padding:0 28px 40px; }
.round-section { display:none; }
.round-section.active { display:block; }
.round-grid { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
.card, .trick-card { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px; box-shadow:0 8px 24px rgba(23,32,51,.05); }
.wide { grid-column:1 / -1; }
.kv { display:grid; grid-template-columns:120px 1fr; gap:8px 14px; }
.kv span, .meta, .app-header p { color:var(--muted); }
.issues { margin:14px 0; padding:12px 16px 12px 34px; background:#fff; border:1px solid var(--line); border-radius:14px; }
.issues.ok { padding:12px 16px; color:var(--green); }
.issues.compact { margin:10px 0; }
.issues li { margin:6px 0; }
.issues .error { color:var(--red); }
.issues .warning { color:var(--amber); }
textarea { width:100%; min-height:78px; resize:vertical; border:1px solid var(--line); border-radius:12px; padding:10px; font:inherit; }
.trick-list { display:grid; gap:14px; margin-top:16px; }
.trick-card { padding:0; overflow:hidden; }
.trick-card summary { display:flex; justify-content:space-between; gap:16px; padding:14px 16px; cursor:pointer; border-bottom:1px solid var(--line); }
.trick-card summary.has-error { background:#fff1f0; }
.trick-card summary.has-warning { background:#fff7ed; }
.trick-table { position:relative; display:grid; grid-template-columns:1fr 210px 1fr; grid-template-rows:auto auto auto; gap:12px; min-height:300px; padding:18px; align-items:center; }
.seat-play { border:1px solid var(--line); border-radius:14px; padding:12px; background:#fbfcff; min-height:92px; }
.seat-play.winner { border-color:var(--green); background:#ecfdf3; }
.north { grid-column:2; grid-row:1; }
.west { grid-column:1; grid-row:2; }
.east { grid-column:3; grid-row:2; }
.south { grid-column:2; grid-row:3; }
.center-pot { grid-column:2; grid-row:2; text-align:center; padding:14px; border:1px dashed var(--line); border-radius:999px; background:#fff; }
.center-pot span { display:block; margin-top:6px; color:var(--muted); font-size:12px; }
.seat-title { display:flex; gap:6px; align-items:center; font-weight:700; margin-bottom:8px; }
.tag { font-size:12px; padding:2px 7px; border-radius:999px; color:#fff; }
.tag.win { background:var(--green); }
.tag.lead { background:var(--blue); }
.card-token { display:inline-block; min-width:34px; text-align:center; margin:2px; padding:5px 7px; border-radius:8px; border:1px solid var(--line); background:#fff; font-weight:700; }
.card-token.red { color:#c0102e; }
.card-token.black { color:#111827; }
.card-token.played-highlight { border-color:var(--amber); background:#fff4d6; box-shadow:0 0 0 2px rgba(181,71,8,.18); }
.play-detail { display:grid; gap:8px; padding:0 16px 16px; }
.play-row { display:grid; grid-template-columns:110px 1fr 110px 100px 110px; gap:10px; align-items:center; padding:8px 0; border-top:1px solid #eef1f6; }
.hand-snapshots { margin:0 16px 16px; padding:12px; border:1px solid var(--line); border-radius:14px; background:#fbfcff; }
.hand-snapshots h3 { margin:0 0 10px; font-size:15px; }
.hand-snapshot, .initial-hand { border-top:1px solid #eef1f6; padding:8px 0; }
.hand-snapshot:first-of-type, .initial-hand:first-of-type { border-top:0; }
.hand-snapshot summary, .initial-hand summary { display:block; padding:4px 0; border:0; font-weight:700; color:var(--blue); cursor:pointer; }
.hand-compare { display:grid; grid-template-columns:1fr; gap:12px; margin-top:8px; }
.hand-cards { margin-top:6px; line-height:2.2; }
.initial-hands { display:grid; gap:4px; }
code { background:#eef2ff; padding:3px 6px; border-radius:6px; }
.correction-inline { padding:0 16px 16px; }
.correction-inline label { display:block; margin-bottom:6px; color:var(--muted); }
@media (max-width: 900px) {
  .app-header, .round-grid, .trick-card summary { display:block; }
  .round-grid { grid-template-columns:1fr; }
  .wide { grid-column:auto; }
  .trick-table { grid-template-columns:1fr; grid-template-rows:auto; }
  .north,.west,.east,.south,.center-pot { grid-column:1; grid-row:auto; }
  .play-row { grid-template-columns:1fr; }
}
"""


JS = """
const tabs = [...document.querySelectorAll('.round-tab')];
const sections = [...document.querySelectorAll('.round-section')];
function activate(id) {
  tabs.forEach(t => t.classList.toggle('active', t.dataset.target === id));
  sections.forEach(s => s.classList.toggle('active', s.id === id));
}
tabs.forEach(t => t.addEventListener('click', () => activate(t.dataset.target)));
if (tabs.length) activate(tabs[0].dataset.target);

document.getElementById('expand-all').addEventListener('click', () => {
  document.querySelectorAll('details.trick-card').forEach(d => d.open = true);
});
document.getElementById('collapse-all').addEventListener('click', () => {
  document.querySelectorAll('details.trick-card').forEach(d => d.open = false);
});

const storageKey = 'shengji-log-corrections:' + location.pathname;
const saved = JSON.parse(localStorage.getItem(storageKey) || '{}');
document.querySelectorAll('[data-correction-key]').forEach(el => {
  const key = el.dataset.correctionKey;
  el.value = saved[key] || '';
  el.addEventListener('input', () => {
    saved[key] = el.value;
    localStorage.setItem(storageKey, JSON.stringify(saved, null, 2));
  });
});
document.getElementById('export-corrections').addEventListener('click', () => {
  const payload = {...window.REPLAY_CORRECTIONS_SEED, corrections: saved, exported_at: new Date().toISOString()};
  const blob = new Blob([JSON.stringify(payload, null, 2)], {type:'application/json;charset=utf-8'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'game_log_corrections.json';
  a.click();
  URL.revokeObjectURL(a.href);
});
"""




def main() -> None:
    force_utf8_stdout()

    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", type=Path, help="对局日志 JSON")
    parser.add_argument("-o", "--output", type=Path, default=None,
                        help="输出 HTML 路径（默认与日志同名）")
    args = parser.parse_args()

    log_path = args.log
    if not log_path.is_file():
        alt = Path(__file__).resolve().parents[1] / log_path
        if alt.is_file():
            log_path = alt
        else:
            raise SystemExit(f"日志不存在: {args.log}")

    log = json.loads(log_path.read_text(encoding="utf-8"))

    try:
        analysis = build_analysis(log)
    except LogFormatError as exc:
        raise SystemExit(
            f"无法分析该日志: {exc}\n"
            f"提示：2026-07-28 之前生成的日志缺少 upgrade_table 等字段，请重新生成。"
        )

    reconstruct_hand_snapshots(log)

    out_path = args.output or log_path.with_suffix(".html")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        normalize_html_output(render_html(log, analysis, log_path)), encoding="utf-8")

    errors = sum(1 for i in analysis["issues"] if i["level"] == "error")
    warnings = sum(1 for i in analysis["issues"] if i["level"] == "warning")
    print(f"HTML 复盘已生成: {out_path}")
    print(f"规则校验: {errors} error / {warnings} warning")
    for skipped in analysis["skipped"]:
        print(f"  [跳过] {skipped}")


if __name__ == "__main__":
    main()
