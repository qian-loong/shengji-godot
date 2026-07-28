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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest", type=Path, help="manifest.json from generate_matrix.py")
    ap.add_argument("--games", type=int, default=None, help="Override games_per_case")
    ap.add_argument("--max-rounds", type=int, default=None, help="Override max_rounds")
    ap.add_argument("--timeout", type=int, default=180, help="Per-game timeout seconds")
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
    print(f"out={rel(out_root)}")

    results = {
        "run_id": run_id,
        "manifest": rel(manifest_path),
        "games_per_case": games,
        "max_rounds": max_rounds,
        "seed_base": seed_base,
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
            r = run_one(godot, config_path, log_path, seed, max_rounds, case_id, args.timeout)
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
    failed = sum(1 for c in results["cases"] for g in c.get("games", []) if not g.get("ok"))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
