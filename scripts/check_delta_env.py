#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_delta_env.py — Delta 执行器环境特征的双路径差分审计。

对 9 种 DELTA_MODE 逐一调用 run_ui.py（lupa）/ run_ui_luau.py（真实 luau），
执行 examples/delta_env_scenario.lua（一次运行内部已用 DeltaEnv.build 遍历
9 种模式做语义断言），再校验每种模式下 apply() 的 [delta-sim] 诊断行与断言。

用法：
    python3 scripts/check_delta_env.py                 # 双路径 × 9 模式
    python3 scripts/check_delta_env.py --luau          # 只跑 luau 路径
    python3 scripts/check_delta_env.py --mode G_nil    # 只跑某一种模式
    python3 scripts/check_delta_env.py --json          # 机器可读

退出码：全部模式通过且 0 失败断言 / 0 错误时为 0，否则 1。
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCENARIO = os.path.join(ROOT, "examples", "delta_env_scenario.lua")

sys.path.insert(0, HERE)
from delta_modes import DELTA_MODES  # noqa: E402


def run_one(mode, backend):
    with tempfile.TemporaryDirectory(prefix="robloxui_delta_") as td:
        if backend == "luau":
            cmd = [sys.executable, os.path.join(HERE, "run_ui_luau.py"),
                   "--scenario", SCENARIO, "--delta-mode", mode,
                   "--style", "none", "--pump-after", "0",
                   "--out", os.path.join(td, "o.png")]
        else:
            cmd = [sys.executable, os.path.join(HERE, "run_ui.py"),
                   "--scenario", SCENARIO, "--delta-mode", mode,
                   "--no-final-snapshot"]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired:
            return {"mode": mode, "backend": backend, "error": "timeout"}
        out = (p.stdout or "") + (p.stderr or "")

    sim = re.search(r"\[delta-sim\][^\n]*", out)
    summary = re.search(r"断言:\s*通过\s*(\d+)\s*/\s*失败\s*(\d+)", out)
    errs = re.search(r"错误:\s*(\d+)\s*条", out)
    fails = re.findall(r"^\[FAIL\]\s*(.+)$", out, flags=re.M)
    res = {
        "mode": mode,
        "backend": backend,
        "diagnostic": sim.group(0).strip() if sim else None,
        "pass": int(summary.group(1)) if summary else None,
        "fail": int(summary.group(2)) if summary else None,
        "errors": int(errs.group(1)) if errs else None,
        "exit": p.returncode,
        "fail_lines": fails[:6],
    }
    if res["diagnostic"] is None or res["pass"] is None:
        res["error"] = "场景未正常产出诊断/断言汇总"
        res["raw_tail"] = out[-1200:]
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--luau", action="store_true", help="只跑真实 luau 路径")
    ap.add_argument("--lupa", action="store_true", help="只跑 lupa 路径")
    ap.add_argument("--mode", default="", help="只跑指定 DELTA_MODE")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    modes = [args.mode] if args.mode else list(DELTA_MODES)
    bad_mode = [m for m in modes if m not in DELTA_MODES]
    if bad_mode:
        print("未知模式: " + ", ".join(bad_mode))
        return 2
    backends = ["lupa"] if args.lupa else (["luau"] if args.luau else ["lupa", "luau"])

    rows = []
    for backend in backends:
        for mode in modes:
            r = run_one(mode, backend)
            rows.append(r)
            ok = ("error" not in r and r.get("fail") == 0
                  and r.get("errors") == 0 and r.get("exit") == 0
                  and r.get("diagnostic") and ("MODE=" + mode) in r["diagnostic"])
            r["ok"] = bool(ok)
            if not args.json:
                print("[%s] %-14s %-9s pass=%s fail=%s err=%s %s"
                      % ("OK " if ok else "BAD", mode, backend,
                         r.get("pass"), r.get("fail"), r.get("errors"),
                         (r.get("diagnostic") or r.get("error", ""))))

    total = len(rows)
    passed = sum(1 for r in rows if r["ok"])
    if args.json:
        print(json.dumps({"total": total, "passed": passed,
                          "all_pass": passed == total, "rows": rows},
                         ensure_ascii=False, indent=2))
    else:
        print("\n=== Delta env matrix: %d/%d PASS ===" % (passed, total))
        for r in rows:
            if not r["ok"]:
                print("  BAD", r["mode"], r["backend"],
                      r.get("fail_lines") or r.get("error") or r.get("raw_tail", "")[-300:])
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
