#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_ui.py — Roblox UI 无头可视化测试 CLI（RobloxUi 开发专家 Skill 的入口）

用法示例：
    python3 run_ui.py \
        --lib "https://raw.githubusercontent.com/WasKKal/DynamicCowUI/main/DynamicCowUI.lua=/workspace/DynamicCowUI.lua" \
        --scenario examples/demo_scenario.lua \
        --viewport 800x600 --cell 8x16

    python3 run_ui.py --lib URL=PATH --scenario s.lua --output out.txt

参数：
    --lib URL=PATH    把场景里 game:HttpGet(URL) 映射到本地 PATH（可多次）；
                      PATH 也可以是 http(s):// 链接（自动下载）
    --scenario FILE   场景脚本（Luau 风格，但须为 Lua 5.x 可编译子集）
    --viewport WxH    视口像素，默认 800x600
    --cell WxH        网格单元格像素，默认 8x16
    --max-seconds N   场景最大虚拟秒数，默认 300
    --pump-after N    场景结束后额外推进的虚拟秒数，默认 1
    --no-final-snapshot  场景未产生快照时不补拍结束快照
    --output FILE     完整输出同时写入文件
退出码：0 = 全部通过；1 = 有失败断言或运行错误；2 = 用法/加载错误
"""

import argparse
import hashlib
import io
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = ["mock_runtime.lua", "vision.lua", "harness.lua"]


def fail(msg, code=2):
    print("[run_ui] " + msg, file=sys.stderr)
    sys.exit(code)


def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    # 剥离 BOM / U+FFFC（执行器导出的 Luau 文件常见），避免 load 报 unexpected symbol
    return data.decode("utf-8").lstrip("\ufeff\ufffc")


def fetch_url(url, cache_dir):
    os.makedirs(cache_dir, exist_ok=True)
    key = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
    cache = os.path.join(cache_dir, key + ".lua")
    if os.path.exists(cache):
        return read_text(cache)
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            content = resp.read().decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001
        fail("下载失败 %s: %s" % (url, exc))
    with open(cache, "w", encoding="utf-8") as f:
        f.write(content)
    return content.lstrip("\ufeff\ufffc")


def parse_lib(spec, cache_dir):
    """URL=PATH / URL=URL / PATH（无 = 时按本地路径）"""
    if "=" in spec:
        url, _, target = spec.partition("=")
    else:
        url, target = spec, spec
    if target.startswith("http://") or target.startswith("https://"):
        return url, fetch_url(target, cache_dir)
    if not os.path.exists(target):
        fail("库文件不存在: " + target)
    return url, read_text(target)


class Tee(io.TextIOBase):
    def __init__(self, *streams):
        self.streams = streams

    def write(self, s):
        for st in self.streams:
            st.write(s)
        return len(s)

    def flush(self):
        for st in self.streams:
            st.flush()


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--lib", action="append", default=[],
                    help="URL=PATH，可多次；把 HttpGet(URL) 映射到本地文件")
    ap.add_argument("--scenario", required=True, help="场景脚本路径")
    ap.add_argument("--viewport", default="800x600")
    ap.add_argument("--cell", default="8x16")
    ap.add_argument("--max-seconds", type=float, default=300.0)
    ap.add_argument("--pump-after", type=float, default=1.0)
    ap.add_argument("--no-final-snapshot", action="store_true")
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    try:
        import lupa
    except ImportError:
        fail("缺少 lupa：pip install lupa", 2)
    from lupa import lua55

    # 视口/网格
    try:
        vw, vh = (int(x) for x in args.viewport.lower().split("x"))
        cw, ch = (int(x) for x in args.cell.lower().split("x"))
    except ValueError:
        fail("--viewport/--cell 格式应为 WxH，如 800x600")
    if vw <= 0 or vh <= 0 or cw <= 0 or ch <= 0:
        fail("视口与网格必须为正数")

    # 场景与库
    if not os.path.exists(args.scenario):
        fail("场景文件不存在: " + args.scenario)
    scenario_src = read_text(args.scenario)
    scenario_name = os.path.basename(args.scenario)

    cache_dir = os.path.join(HERE, ".cache")
    libs = [parse_lib(spec, cache_dir) for spec in args.lib]

    # 脚本装载
    sources = {}
    for name in SCRIPTS:
        path = os.path.join(HERE, name)
        if not os.path.exists(path):
            fail("缺少脚本: " + path)
        sources[name] = read_text(path)

    out_file = open(args.output, "w", encoding="utf-8") if args.output else None
    streams = [sys.stdout] + ([out_file] if out_file else [])
    real_stdout = sys.stdout
    sys.stdout = Tee(*streams)

    exit_code = 1
    try:
        lua = lua55.LuaRuntime(unpack_returned_tuples=True)
        g = lua.globals()

        # 把 Lua 侧 print 接到 Python 流（同时写控制台与输出文件）
        def lua_print(*args):
            line = "\t".join(str(a) for a in args)
            for st in streams:
                st.write(line + "\n")
                st.flush()

        g.print = lua_print

        # 1) mock 运行时
        lua.execute(sources["mock_runtime.lua"])
        # 2) 视觉层
        g.Vision = lua.eval("function(s) return load(s)() end")(sources["vision.lua"])
        # 3) 驱动层
        g.Harness = lua.eval("function(s) return load(s)() end")(sources["harness.lua"])

        # 视口/网格配置
        g.Vision.viewport = {"w": vw, "h": vh}
        g.Vision.cell = {"w": cw, "h": ch}

        # 库注册：URL -> 内容（经 Lua 表传递，避免 Python 对象直传）
        lib_map = lua.eval("function() return {} end")()
        for url, content in libs:
            lib_map[url] = content
        g.__LIB_MAP = lib_map
        lua.execute("""
            for url, content in pairs(__LIB_MAP) do
                __MOCK.RegisterLib(url, content)
            end
        """)

        print("[run_ui] 视口 %dx%d  网格 %dx%d  库 %d 个  场景 %s"
              % (vw, vh, cw, ch, len(libs), scenario_name))
        for url, content in libs:
            print("[run_ui] 库 %s  (%d 字节, sha256 %s)"
                  % (url, len(content.encode("utf-8")),
                     hashlib.sha256(content.encode("utf-8")).hexdigest()[:12]))

        H = g.Harness
        H.runScenario(scenario_src, scenario_name, {"maxSeconds": args.max_seconds})

        # 场景结束后补拍/收尾（主线程直调，不走协程让出）
        if args.pump_after and args.pump_after > 0:
            lua.execute("__MOCK.pumpSeconds(%r)" % args.pump_after)
        if not args.no_final_snapshot and int(H.snapshots) == 0:
            lua.execute('Snapshot("结束状态")')

        passed = bool(H.summary())
        exit_code = 0 if passed else 1
    except Exception as exc:  # noqa: BLE001
        import traceback
        traceback.print_exc()
        print("[run_ui] 运行器自身异常: %s" % exc)
        exit_code = 1
    finally:
        sys.stdout = real_stdout
        if out_file:
            out_file.close()

    if args.output:
        print("[run_ui] 输出已写入 %s" % args.output)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
