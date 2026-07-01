import json, sys

path = sys.argv[1] if len(sys.argv) > 1 else "docs/game-logs/game_log_latest.json"
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

seat_names = {0: "南(你)", 1: "东", 2: "北", 3: "西"}

print(f"=== 共 {len(data['rounds'])} 局 ===\n")

for r in data["rounds"]:
    rn = r.get("round_num", "?")
    dealer = r.get("dealer", -1)
    dealer_name = seat_names.get(dealer, str(dealer))
    rank = r.get("rank_symbol", "?")
    trump = r.get("trump_suit_symbol", "?")
    tr = r.get("team_ranks", [])
    tr_sym = r.get("team_ranks_symbols", [str(x) for x in tr])
    ip = r.get("_in_progress", False)
    settle = r.get("settlement", {})
    ul = settle.get("upgrade_levels", "-")
    us = settle.get("upgrading_side", "-")
    nr_sym = settle.get("new_rank_symbol", "-")
    dd = settle.get("dealer_dethroned", "-")
    fs = settle.get("final_score", "-")

    side_label = {"0": "庄家方", "1": "攻方"}.get(str(us), str(us))
    status = " ** 进行中 **" if ip else ""
    team_str = f"南北={tr_sym[0] if len(tr_sym)>0 else '?'} 东西={tr_sym[1] if len(tr_sym)>1 else '?'}"

    print(f"第{rn}局: 庄={dealer_name}, 打{rank}, 主{trump}, [{team_str}]")
    if not ip and settle:
        print(f"  结算: 攻方{fs}分, {side_label}升{ul}级→{nr_sym}, 推翻庄家={'是' if dd else '否'}")
    if ip:
        print(f"  {status}")
    print()
