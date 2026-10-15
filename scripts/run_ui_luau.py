#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_ui_luau.py — 用【真实 Luau 解释器】执行 UI 代码并渲染出 PNG

与 run_ui.py 的区别：
  run_ui.py      用 lupa 的 Lua 5.5 运行时执行（手写 Lua 5.x 兼容层）
  run_ui_luau.py 用从源码编译的官方 luau 解释器执行（原生支持 += / continue /
                 类型注解 / 字符串插值等 Luau 语法）；由于该解释器禁用了 io 库，
                 所有模块/库/场景源码以 base64 内联进主入口，场景结果以带哨兵的
                 JSON 打印到 stdout，再由 Python + Pillow 画成真实像素图。

渲染的是引擎真实算出的东西：每个单元格的颜色（已按 Roblox 规则做 src-over 合成、
含 UIGradient 求值）、alpha（与背景混合）、字形（用记录的原始前景色绘制）。

用法：
    python3 run_ui_luau.py \
        --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
        --scenario examples/simple_scenario.lua \
        --out /workspace/ui_render_luau.png

    python3 run_ui_luau.py --scenario s.lua --out out.png --cell 4x4 --no-glyphs

参数：
    --lib URL=PATH    把场景里 game:HttpGet(URL) 映射到本地文件（可多次）
    --scenario FILE   场景脚本（必填）
    --out FILE        输出路径（默认 ./ui_render_luau.png）
    --viewport WxH    视口像素，默认 800x600
    --bg COLOR        画布背景色 #RRGGBB，默认 #0F1115
    --no-glyphs       不绘制文字（只看几何与图标）
    --style S         hires=矢量高清 PNG(默认) | html=可交互网页 | both=两者
    --scale N         输出放大倍数（默认 2：800x600→1600x1200）
    --ss N            超采样倍数（默认 3，越大边缘越平滑）
    --capture SEC     动画：按该间隔（虚拟秒）采样帧，0=关闭（例：--capture 0.1）
    --max-frames N    动画帧上限（默认 120）
    --anim            额外导出 APNG 动画（配合 --capture）
    --fps N           APNG 播放帧率，0=按采样间隔推算
    --offline         不联网获取图标资源（只用本地 assets/icons 缓存）
    --click X,Y       场景后在该点命中并派发点击（可多次），用于交互式重渲染
    --dump-json FILE  把引擎报告 JSON 落盘（可用 render_hires.py 离线重渲染）
    --max-seconds N   场景最大虚拟秒数，默认 300
    --pump-after N    场景结束后额外推进的虚拟秒数，默认 1
    --luau PATH       luau 可执行路径（默认自动探测）
退出码：0 = 全部通过；1 = 有失败断言或运行错误；2 = 用法/加载/解释器错误

示例：
    # 高清 PNG（+ 可交互 HTML）
    python3 run_ui_luau.py --lib "URL=examples/rich_ui.lua" \
        --scenario examples/rich_scenario.lua \
        --out /workspace/ui.png --style both --scale 2

    # 动画：每 0.1 虚拟秒采一帧，导出 APNG（HTML 自带时间轴播放器）
    python3 run_ui_luau.py --lib "URL=examples/anim_ui.lua" \
        --scenario examples/anim_scenario.lua \
        --out /workspace/anim.png --style both --capture 0.1 --anim
"""

import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = ["mock_runtime.lua", "vision.lua", "harness.lua"]

# Luau 侧：base64 解码器 + loadsrc
# 关键发现（实测）：
#   * luau CLI 的 _G 是只读表，且不与真实可写全局环境关联；裸全局不会出现在 _G 中。
#   * 但多个 loadstring 调用【共享同一默认全局环境】，裸全局在模块间天然可见。
#   * luau 禁用 load（为 nil），只用 loadstring；loadstring 第 3 个 env 参数被忽略。
# 因此：弃用自定义 ENV，所有模块与场景都用 2 参数 loadstring 在默认全局环境运行，
#       模块间靠【裸全局名】(__MOCK / Vision / Harness / Enum ...) 共享，双运行时兼容。
LUAU_HEADER = r"""
local REAL_LOADSTRING = loadstring

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64rev = {}
for i = 1, #b64chars do b64rev[string.sub(b64chars, i, i)] = i - 1 end
local function b64decode(s)
  s = string.gsub(s, "[^A-Za-z0-9%+%/%=]", "")
  local out = {}
  local acc = 0
  local bits = 0
  for i = 1, #s do
    local c = string.sub(s, i, i)
    local v = b64rev[c]
    if v == nil then v = 0 end
    acc = (acc * 64) + v
    bits = bits + 6
    if bits >= 8 then
      bits = bits - 8
      local byte = math.floor(acc / (2 ^ bits)) % 256
      out[#out + 1] = string.char(byte)
      acc = acc % (2 ^ bits)
    end
  end
  return table.concat(out)
end
local function loadsrc(name, b64)
  local src = b64decode(b64)
  local c, err = REAL_LOADSTRING(src, "@" .. name)
  if not c then error("加载 " .. name .. " 失败: " .. tostring(err)) end
  return c()
end
"""


def fail(msg, code=2):
    print("[run_ui_luau] " + msg, file=sys.stderr)
    sys.exit(code)


def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    return data.decode("utf-8").lstrip("\ufeff\ufffc")


def parse_lib(spec):
    if "=" in spec:
        url, _, target = spec.partition("=")
    else:
        url, target = spec, spec
    if target.startswith("http://") or target.startswith("https://"):
        import urllib.request
        with urllib.request.urlopen(target, timeout=30) as resp:
            return url, resp.read().decode("utf-8", "replace")
    if not os.path.exists(target):
        fail("库文件不存在: " + target)
    return url, read_text(target)


def find_luau(preferred):
    if preferred:
        if not os.path.exists(preferred):
            fail("指定的 luau 不存在: " + preferred, 2)
        return preferred
    for cand in ["/usr/local/bin/luau", shutil.which("luau")]:
        if cand and os.path.exists(cand):
            return cand
    fail("找不到 luau 解释器（用 --luau PATH 指定，或先编译 Luau）", 2)


def b64(s):
    return base64.b64encode(s.encode("utf-8")).decode("ascii")


def hex_to_rgb(s):
    s = s.lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    if len(s) != 6:
        fail("--bg 应为 #RRGGBB")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))



def hires_path(out_path):
    root, ext = os.path.splitext(out_path)
    return root + "_hires" + (ext or ".png")


def html_path(out_path):
    root, _ = os.path.splitext(out_path)
    return root + ".html"


def anim_path(out_path):
    """APNG 也用 .png 扩展名（浏览器/看图器识别为动画 PNG）。"""
    root, _ = os.path.splitext(out_path)
    return root + "_anim.png"


def extract_json(stdout_text):
    begin = "--ROBLOXUI_JSON_BEGIN--"
    end = "--ROBLOXUI_JSON_END--"
    i = stdout_text.find(begin)
    if i < 0:
        return None
    j = stdout_text.find(end, i)
    if j < 0:
        return None
    chunk = stdout_text[i + len(begin):j].strip()
    return chunk


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--lib", action="append", default=[], help="URL=PATH，可多次")
    ap.add_argument("--scenario", required=True, help="场景脚本路径")
    ap.add_argument("--out", default="./ui_render_luau.png", help="输出 PNG 路径")
    ap.add_argument("--viewport", default="800x600")
    ap.add_argument("--bg", default="#0F1115", help="画布背景色 #RRGGBB")
    ap.add_argument("--no-glyphs", action="store_true", help="不绘制文字（只看几何与图标）")
    ap.add_argument("--max-seconds", type=float, default=300.0)
    ap.add_argument("--pump-after", type=float, default=1.0)
    ap.add_argument("--luau", default="", help="luau 可执行路径")
    ap.add_argument("--style", choices=["none", "hires", "html", "both"], default="hires",
                    help="渲染风格：hires=矢量高清 PNG（默认）；html=可交互网页；both=两者；"
                         "none=只出引擎报告（供集成方取 draws，最快）")
    ap.add_argument("--scale", type=int, default=2, help="hires 输出放大倍数（默认 2，即 800x600→1600x1200）")
    ap.add_argument("--ss", type=int, default=3, help="hires 超采样倍数（默认 3，越大边缘越平滑）")
    ap.add_argument("--capture", type=float, default=0.0,
                    help="动画：按该间隔（虚拟秒）采样绘制帧，0=关闭（例：--capture 0.1）")
    ap.add_argument("--max-frames", type=int, default=120, help="动画帧上限（默认 120）")
    ap.add_argument("--anim", action="store_true", help="额外导出 APNG 动画（需配合 --capture）")
    ap.add_argument("--fps", type=float, default=0.0, help="APNG 播放帧率，0=按采样间隔推算")
    ap.add_argument("--offline", action="store_true",
                    help="不联网获取图标资源（只用本地 assets/icons 缓存）")
    ap.add_argument("--dump-json", default="", help="把引擎报告 JSON 落盘（便于离线重渲染）")
    ap.add_argument("--click", action="append", default=[],
                    help="X,Y：场景结束后依次在该点做命中测试并派发点击（可多次），用于交互式重渲染")
    args = ap.parse_args()

    try:
        vw, vh = (int(x) for x in args.viewport.lower().split("x"))
    except ValueError:
        fail("--viewport 格式应为 WxH")
    if vw <= 0 or vh <= 0:
        fail("视口必须为正数")

    if args.offline:
        try:
            import icons
            icons._LUCIDE_SOURCES = ()       # 关闭在线补充
        except Exception:
            pass

    if not os.path.exists(args.scenario):
        fail("场景文件不存在: " + args.scenario)
    scenario_src = read_text(args.scenario)
    libs = [parse_lib(s) for s in args.lib]

    for name in SCRIPTS:
        if not os.path.exists(os.path.join(HERE, name)):
            fail("缺少脚本: " + os.path.join(HERE, name))

    luau = find_luau(args.luau)
    bg = hex_to_rgb(args.bg)

    # 模块源码 base64 内联
    mod_b64 = {}
    for name in SCRIPTS:
        mod_b64[name] = b64(read_text(os.path.join(HERE, name)))

    tmp = tempfile.mkdtemp(prefix="robloxui_luau_")
    try:
        # 生成主入口 luau：解码并 load() 各模块（与 run_ui.py 的加载顺序一致）
        reg_lines = []
        for url, content in libs:
            reg_lines.append('__MOCK.RegisterLib([[%s]], b64decode([[%s]]))'
                             % (url, b64(content)))

        # 交互：场景结束后按顺序做命中测试 + 派发点击，再推进时钟
        click_items = []
        for spec in args.click:
            try:
                cx, cy = (float(t) for t in spec.split(","))
                click_items.append("{%r,%r}" % (cx, cy))
            except ValueError:
                fail("--click 格式应为 X,Y（如 640,300）")
        click_lines = ""
        if click_items:
            click_lines = (
                "\ndo\n  local __clicks = {%s}\n"
                "  for _, c in ipairs(__clicks) do\n"
                "    local __t = hitTest(c[1], c[2])\n"
                "    if __t then tapUI(__t) else print(b64decode([[VGFwMDo=]]) .. ' miss @ ' .. c[1] .. ',' .. c[2]) end\n"
                "    __MOCK.pumpSeconds(0.5)\n"
                "  end\n"
                "  Snapshot([[事件后]])\n"
                "end\n" % ",".join(click_items)
            )

        # 动画捕获：按虚拟时钟间隔采样绘制帧（必须在场景开始前启动）
        capture_line = ""
        if args.capture > 0:
            capture_line = "StartCapture(%r, %d)\n" % (args.capture, max(2, args.max_frames))

        main_src = (
            LUAU_HEADER
            + ("__EMIT_STRUCTURE = true\n" if args.dump_json else "")
            + "\nloadsrc([[mock_runtime.lua]], [[%s]])\n" % mod_b64["mock_runtime.lua"]
            + "Vision = loadsrc([[vision.lua]], [[%s]])\n" % mod_b64["vision.lua"]
            + "Harness = loadsrc([[harness.lua]], [[%s]])\n" % mod_b64["harness.lua"]
            + "Vision.viewport = { w = %d, h = %d }\n" % (vw, vh)
            + "Vision.cell = { w = 8, h = 16 }\n"
            + "\n".join(reg_lines) + "\n"
            + capture_line
            + "Harness.runScenario(b64decode([[%s]]), [[%s]], { maxSeconds = %s })\n"
              % (b64(scenario_src), os.path.basename(args.scenario), repr(args.max_seconds))
            + click_lines
            + "if Harness.snapshots == 0 then Snapshot([[结束状态]]) end\n"
            + "if %s > 0 then __MOCK.pumpSeconds(%s) end\n"
              % (repr(args.pump_after), repr(args.pump_after))
            + "StopCapture()\n"
            + "Harness.summary()\n"
            + "EmitReport([[dummy]])\n"
        )
        main_path = os.path.join(tmp, "main.luau")
        with open(main_path, "w", encoding="utf-8") as f:
            f.write(main_src)

        print("[run_ui_luau] 使用解释器: %s" % luau)
        print("[run_ui_luau] 视口 %dx%d  库 %d 个  场景 %s"
              % (vw, vh, len(libs), os.path.basename(args.scenario)))

        proc = subprocess.run([luau, main_path], capture_output=True, text=True)
        if proc.stdout:
            sys.stdout.write(proc.stdout)
        if proc.stderr:
            sys.stderr.write(proc.stderr)

        json_text = extract_json(proc.stdout or "")
        if not json_text:
            fail("未能从 luau 输出抽取 JSON（场景可能未正常结束）", 1)

        rep = json.loads(json_text)
        if args.dump_json:
            with open(args.dump_json, "w", encoding="utf-8") as f:
                json.dump(rep, f, ensure_ascii=False)

        frames = rep.get("frames") or []
        if frames:
            print("[run_ui_luau] 动画帧 %d（采样间隔 %.2fs）"
                  % (len(frames), float(rep.get("frameInterval", 0.2))))

        if args.style in ("hires", "both"):
            from render_hires import render_hires
            hp = args.out if args.style == "hires" else hires_path(args.out)
            himg = render_hires(rep, hp, bg=bg, scale=max(1, args.scale),
                                ss=max(1, args.ss), show_text=not args.no_glyphs)
            print("[run_ui_luau] 已导出(hires) %s  (%dx%d px, 放大 x%d · 超采样 x%d)"
                  % (hp, himg.width, himg.height, max(1, args.scale), max(1, args.ss)))
            if args.anim and len(frames) > 1:
                from render_hires import render_apng
                ap = anim_path(hp)
                aimg = render_apng(rep, ap, bg=bg, scale=max(1, args.scale),
                                   ss=max(1, args.ss), show_text=not args.no_glyphs,
                                   fps=args.fps)
                print("[run_ui_luau] 已导出(apng)  %s  (%dx%d px, %d 帧)"
                      % (ap, aimg.width, aimg.height, len(frames)))
        if args.style in ("html", "both"):
            from render_html import render_html
            pp = args.out if args.style == "html" else html_path(args.out)
            render_html(rep, pp, title=os.path.basename(args.scenario))
            print("[run_ui_luau] 已导出(html)  %s  (可交互预览%s)"
                  % (pp, "，含动画时间轴" if len(frames) > 1 else ""))

        checks = rep.get("checks", {})
        fails = int(checks.get("fail", 0))
        nerr = len(rep.get("errors", []))
        nwarn = len(rep.get("warnings", []))
        print("[run_ui_luau] 断言 通过 %d / 失败 %d | 错误 %d | 警告 %d | Tween %d"
              % (int(checks.get("pass", 0)), fails, nerr, nwarn,
                 int(rep.get("tweenCount", 0))))
        sys.exit(0 if (fails == 0 and nerr == 0) else 1)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
