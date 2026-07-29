#!/usr/bin/env python3
"""Run headless game_session for each case in a batch manifest.

Requires GODOT_EXE env (Godot 4.x console build).

Usage:
  python tools/batch/generate_matrix.py tools/batch/matrix_single_factor_quick.json
  python tools/batch/run_batch.py configs/batch/single_factor_quick_v1/manifest.json

  # smoke: 1 game each, 5 max rounds
  python tools/batch/run_batch.py configs/batch/single_factor_quick_v1/manifest.json --games 1 --max-rounds 5
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GODOT_PROJECT = REPO / "src" / "godot"
SESSION_SCRIPT = "res://scripts/gameplay/game_session.gd"

sys.path.insert(0, str(REPO / "tools"))
from validate_game_log import force_utf8_stdout, validate_file  # noqa: E402


def find_godot() -> str:
    exe = os.environ.get("GODOT_EXE") or os.environ.get("GODOT")
    if exe and Path(exe).exists():
        return exe
    print("Set GODOT_EXE to Godot console executable", file=sys.stderr)
    sys.exit(2)


def run_one(
    godot: str,
    config_path: Path,
    log_path: Path,
    seed: int,
    max_rounds: int,
    case_id: str,
    timeout: int,
    lead_strategy: str | None = None,
) -> dict:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    # Godot user args after script; also pass as plain args for compatibility
    cmd = [
        godot,
        "--headless",
        "--path",
        str(GODOT_PROJECT),
        "--script",
        SESSION_SCRIPT,
        f"--config={config_path}",
        f"--seed={seed}",
        f"--max-rounds={max_rounds}",
        f"--log-path={log_path}",
        f"--case-id={case_id}",
    ]
    if lead_strategy:
        cmd.append(f"--lead-strategy={lead_strategy}")
    t0 = time.time()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(GODOT_PROJECT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        elapsed = time.time() - t0
        return {
            "ok": proc.returncode == 0 and log_path.is_file(),
            "returncode": proc.returncode,
            "elapsed_sec": round(elapsed, 2),
            "stdout_tail": (proc.stdout or "")[-2000:],
            "stderr_tail": (proc.stderr or "")[-1000:],
            "log": str(log_path) if log_path.is_file() else "",
        }
    except subprocess.TimeoutExpired as e:
        out = e.stdout[-2000:] if isinstance(e.stdout, str) else (
            e.stdout.decode("utf-8", "replace")[-2000:] if e.stdout else ""
        )
        return {
            "ok": False,
            "returncode": -1,
            "elapsed_sec": timeout,
            "stdout_tail": out,
            "stderr_tail": f"timeout after {timeout}s",
            "log": "",
        }


def validate_log(log_path: Path) -> dict:
    """对单局日志跑规则校验，返回可入 run_results.json 的精简结果。

    跑得完 ≠ 跑得对：returncode 只能说明进程没崩，逻辑正确性要靠复算。
    """
    if not log_path.is_file():
        return {"ok": False, "fatal": "missing_log", "errors": 0, "warnings": 0, "codes": []}
    result = validate_file(log_path)
    codes = sorted({i["code"] for i in result["issues"] if i["level"] == "error"})
    return {
        "ok": result["ok"],
        "fatal": result["fatal"],
        "errors": result["errors"],
        "warnings": result["warnings"],
        "codes": codes,
        "skipped": result["skipped"],
    }


def main() -> int:
    force_utf8_stdout()

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest", type=Path, help="manifest.json from generate_matrix.py")
    ap.add_argument("--games", type=int, default=None, help="Override games_per_case")
    ap.add_argument("--max-rounds", type=int, default=None, help="Override max_rounds")
    ap.add_argument("--timeout", type=int, default=180, help="Per-game timeout seconds")
    ap.add_argument(
        "--lead-strategy",
        choices=["simple", "max_structure", "dump"],
        default=None,
        help=(
            "Override AI lead strategy. Engine default is 'simple' (singles only). "
            "'max_structure' activates pair/tractor rule paths but shifts the balance "
            "baseline (dethrone rate 0.50 -> 0.75) — keep it in a separate run-id."
        ),
    )
    ap.add_argument(
        "--no-validate",
        action="store_true",
        help="Skip rule validation (only check the process exit code)",
    )
    ap.add_argument(
        "--run-id",
        default=None,
        help="Batch run id (default: timestamp)",
    )
    args = ap.parse_args()

    manifest_path = args.manifest.resolve() if args.manifest.is_file() else (REPO / args.manifest).resolve()
    if not manifest_path.is_file():
        print(f"manifest not found: {args.manifest}", file=sys.stderr)
        return 1

    def rel(p: Path) -> str:
        try:
            return str(p.resolve().relative_to(REPO)).replace("\\", "/")
        except ValueError:
            return str(p.resolve()).replace("\\", "/")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    games = args.games if args.games is not None else int(manifest.get("games_per_case", 3))
    max_rounds = (
        args.max_rounds if args.max_rounds is not None else int(manifest.get("max_rounds", 30))
    )
    seed_base = int(manifest.get("seed_base", 42))
    run_id = args.run_id or datetime.now().strftime("%Y%m%d-%H%M%S")
    out_root = (REPO / "logs" / "batch" / run_id).resolve()
    out_root.mkdir(parents=True, exist_ok=True)

    godot = find_godot()
    print(f"GODOT_EXE={godot}")
    print(f"run_id={run_id} games/case={games} max_rounds={max_rounds}")
    if args.lead_strategy:
        print(f"lead_strategy={args.lead_strategy}（非默认 —— 与 simple 基线不可直接对比）")
    print(f"out={rel(out_root)}")

    results = {
        "run_id": run_id,
        "manifest": rel(manifest_path),
        "games_per_case": games,
        "max_rounds": max_rounds,
        "seed_base": seed_base,
        "lead_strategy": args.lead_strategy or "simple",
        "cases": [],
    }

    for case in manifest.get("cases", []):
        case_id = case["id"]
        config_rel = case["config"]
        config_path = (REPO / config_rel).resolve()
        if not config_path.is_file():
            print(f"[SKIP] missing config {config_rel}")
            results["cases"].append({"id": case_id, "error": "missing_config", "games": []})
            continue

        case_dir = out_root / case_id
        case_dir.mkdir(parents=True, exist_ok=True)
        # copy config snapshot beside logs
        (case_dir / "config.json").write_text(config_path.read_text(encoding="utf-8"), encoding="utf-8")

        game_results = []
        print(f"\n=== case {case_id} ({case.get('description', '')}) ===")
        for g in range(games):
            seed = seed_base + g
            log_path = case_dir / f"game_{g:02d}_seed{seed}.json"
            print(f"  game {g+1}/{games} seed={seed} ...", end=" ", flush=True)
            r = run_one(godot, config_path, log_path, seed, max_rounds, case_id,
                        args.timeout, args.lead_strategy)
            # normalize log path in result
            if r.get("log"):
                try:
                    r["log"] = rel(Path(r["log"]) if Path(r["log"]).is_absolute() else REPO / r["log"])
                except Exception:
                    pass
            # run_one stores absolute-ish; recompute
            if log_path.is_file():
                r["log"] = rel(log_path)

            status = "OK" if r["ok"] else f"FAIL(rc={r['returncode']})"

            if not args.no_validate:
                v = validate_log(log_path)
                r["validation"] = v
                if v["fatal"]:
                    status += f" | 校验中断: {v['fatal']}"
                elif not v["ok"]:
                    status += f" | 规则违规 {v['errors']} 处: {','.join(v['codes'][:4])}"
                else:
                    status += " | 校验通过"

            print(f"{status} {r['elapsed_sec']}s")
            if not r["ok"] and r.get("stderr_tail"):
                print(f"    stderr: {r['stderr_tail'][:300]}")
            if not r["ok"] and r.get("stdout_tail"):
                # show last lines of godot output for debugging
                tail = r["stdout_tail"].strip().splitlines()[-8:]
                for line in tail:
                    print(f"    out: {line}")
            game_results.append({"game_index": g, "seed": seed, **r})

        results["cases"].append(
            {
                "id": case_id,
                "description": case.get("description", ""),
                "config": config_rel,
                "overrides": case.get("overrides", {}),
                "games": game_results,
            }
        )

    results_path = out_root / "run_results.json"
    results_path.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\nrun_results: {rel(results_path)}")
    print("Next: python tools/batch/summarize_batch.py " + rel(results_path))

    all_games = [g for c in results["cases"] for g in c.get("games", [])]
    failed = sum(1 for g in all_games if not g.get("ok"))
    invalid = sum(
        1 for g in all_games
        if isinstance(g.get("validation"), dict) and not g["validation"]["ok"]
    )

    print(f"\n运行失败 {failed}/{len(all_games)} 局", end="")
    if args.no_validate:
        print("（已跳过规则校验 —— 本次结果不能证明逻辑正确）")
    else:
        print(f"，规则违规 {invalid}/{len(all_games)} 局")
        if invalid:
            offenders: dict[str, int] = {}
            for g in all_games:
                v = g.get("validation")
                if isinstance(v, dict) and not v["ok"]:
                    for code in (v["codes"] or [v["fatal"] or "unknown"]):
                        offenders[code] = offenders.get(code, 0) + 1
            print("违规类型:")
            for code, n in sorted(offenders.items(), key=lambda kv: -kv[1]):
                print(f"  {n:3d} × {code}")

    return 1 if (failed or invalid) else 0


if __name__ == "__main__":
    raise SystemExit(main())
