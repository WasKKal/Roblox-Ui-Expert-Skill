#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
render_png.py — 把无头 UI 引擎的渲染结果导出为 PNG 图片

与 run_ui.py 的区别：
  run_ui.py    输出「结构树 + ASCII 画面 + 色彩网格」的文本报告（给 Agent 读）
  render_png.py 把同一份渲染结果画成真正的 PNG（给人看 / 存档 / 分享）

绘制内容即引擎真实算出的东西：
  · 每个单元格的颜色（已按 Roblox 规则做 src-over 合成，含渐变求值）
  · 每个单元格的 alpha（与背景色混合，透明处透出背景）
  · 每个单元格的字形（░ 不透明 / ▒ 半透 / · 高透 / # 描边 / +|=|- 边框 / ▓ 图像）

用法：
    python3 render_png.py \
        --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
        --scenario examples/simple_scenario.lua \
        --out /workspace/ui_render.png

    python3 render_png.py --scenario s.lua --out out.png --viewport 800x600 --cell 8x16

参数：
    --scenario FILE   场景脚本（必填）
    --lib URL=PATH    把场景里 HttpGet(URL) 映射到本地文件（可多次）
    --out FILE        输出 PNG 路径（默认 ./ui_render.png）
    --viewport WxH    视口像素，默认 800x600
    --cell WxH        单元格像素，默认 8x16（越小分辨率越高、越慢）
    --bg COLOR        画布背景色，默认 #0F1115（透明处透出的颜色）
    --no-glyphs       不绘制字符（只输出纯色块，更接近真实 UI 观感）
    --max-seconds N   场景最大虚拟秒数，默认 300
退出码：0 = 成功；2 = 用法/加载错误
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = ["mock_runtime.lua", "vision.lua", "harness.lua"]
MONO_FONTS = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",  # 中英文均覆盖
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf",
]


def fail(msg, code=2):
    print("[render_png] " + msg, file=sys.stderr)
    sys.exit(code)


def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    # 剥离 BOM / U+FFFC（执行器导出的 Luau 文件常见）
    return data.decode("utf-8").lstrip("\ufeff\ufffc")


def parse_lib(spec):
    """URL=PATH；PATH 也支持 http(s)://（走 run_ui.py 的缓存逻辑，此处从简）"""
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


def hex_to_rgb(s):
    s = s.lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    if len(s) != 6:
        fail("--bg 应为 #RRGGBB，如 #0F1115")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def load_mono_font(size):
    from PIL import ImageFont
    for p in MONO_FONTS:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--scenario", required=True, help="场景脚本路径")
    ap.add_argument("--lib", action="append", default=[], help="URL=PATH，可多次")
    ap.add_argument("--out", default="./ui_render.png", help="输出 PNG 路径")
    ap.add_argument("--viewport", default="800x600")
    ap.add_argument("--cell", default="8x16")
    ap.add_argument("--bg", default="#0F1115", help="画布背景色 #RRGGBB")
    ap.add_argument("--no-glyphs", action="store_true", help="不绘制字符，只出纯色块")
    ap.add_argument("--max-seconds", type=float, default=300.0)
    args = ap.parse_args()

    try:
        import lupa
        from PIL import Image, ImageDraw
    except ImportError as exc:
        fail("缺少依赖（需 lupa 与 Pillow）: %s" % exc, 2)
    from lupa import lua55

    try:
        vw, vh = (int(x) for x in args.viewport.lower().split("x"))
        cw, ch = (int(x) for x in args.cell.lower().split("x"))
    except ValueError:
        fail("--viewport/--cell 格式应为 WxH，如 800x600")
    if vw <= 0 or vh <= 0 or cw <= 0 or ch <= 0:
        fail("视口与网格必须为正数")

    if not os.path.exists(args.scenario):
        fail("场景文件不存在: " + args.scenario)
    scenario_src = read_text(args.scenario)
    libs = [parse_lib(s) for s in args.lib]

    sources = {}
    for name in SCRIPTS:
        path = os.path.join(HERE, name)
        if not os.path.exists(path):
            fail("缺少脚本: " + path)
        sources[name] = read_text(path)

    lua = lua55.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()

    # Lua 侧 print 转发到 Python（场景里的 print 仍可见）
    def lua_print(*a):
        print("\t".join(str(x) for x in a))

    g.print = lua_print

    lua.execute(sources["mock_runtime.lua"])
    g.Vision = lua.eval("function(s) return load(s)() end")(sources["vision.lua"])
    g.Harness = lua.eval("function(s) return load(s)() end")(sources["harness.lua"])
    g.Vision.viewport = {"w": vw, "h": vh}
    g.Vision.cell = {"w": cw, "h": ch}

    lib_map = lua.eval("function() return {} end")()
    for url, content in libs:
        lib_map[url] = content
    g.__LIB_MAP = lib_map
    lua.execute("for url, content in pairs(__LIB_MAP) do __MOCK.RegisterLib(url, content) end")

    H = g.Harness
    H.runScenario(scenario_src, os.path.basename(args.scenario), {"maxSeconds": args.max_seconds})
    # 场景未产生快照时补拍一张（与 run_ui.py 行为一致）
    if int(H.snapshots) == 0:
        lua.execute('Snapshot("结束状态")')

    enc = g.Vision.encodeCanvas()
    if not enc:
        fail("未能取到渲染 canvas（场景里未产生快照？）", 2)

    cols = int(enc["cols"])
    rows = int(enc["rows"])
    cell_w = int(enc["cellW"])
    cell_h = int(enc["cellH"])
    colors = str(enc["colors"])
    glyphs = str(enc["glyphs"])
    fgs = str(enc["fgs"] or "")

    bg = hex_to_rgb(args.bg)
    img = Image.new("RGB", (cols * cell_w, rows * cell_h), bg)
    drw = ImageDraw.Draw(img)
    font = None if args.no_glyphs else load_mono_font(max(6, int(cell_h * 0.78)))

    n = cols * rows
    for i in range(n):
        r, gg, b, a = (
            int(colors[i * 8:i * 8 + 2], 16),
            int(colors[i * 8 + 2:i * 8 + 4], 16),
            int(colors[i * 8 + 4:i * 8 + 6], 16),
            int(colors[i * 8 + 6:i * 8 + 8], 16),
        )
        if a == 0:
            continue
        # src-over 到背景
        f = a / 255.0
        pr = int(r * f + bg[0] * (1 - f))
        pg = int(gg * f + bg[1] * (1 - f))
        pb = int(b * f + bg[2] * (1 - f))
        row, col = divmod(i, cols)
        x0, y0 = col * cell_w, row * cell_h
        drw.rectangle([x0, y0, x0 + cell_w - 1, y0 + cell_h - 1], fill=(pr, pg, pb))

        # 文字格：用记录的原始前景色画字形（fgs alpha=0 表示非文字格，不画字符，
        # 避免 ░▒·/# 等终端纹理符号污染像素图——色块本身已表达填充与边框）
        if font is not None and i * 8 + 8 <= len(fgs):
            fa = int(fgs[i * 8 + 6:i * 8 + 8], 16)
            if fa > 8:
                fr = int(fgs[i * 8:i * 8 + 2], 16)
                fg_ = int(fgs[i * 8 + 2:i * 8 + 4], 16)
                fb = int(fgs[i * 8 + 4:i * 8 + 6], 16)
                ch_ = glyphs[i] if i < len(glyphs) else " "
                if ch_ and ch_ != " ":
                    ff = fa / 255.0
                    tfr = int(fr * ff + pr * (1 - ff))
                    tfg = int(fg_ * ff + pg * (1 - ff))
                    tfb = int(fb * ff + pb * (1 - ff))
                    try:
                        drw.text((x0 + cell_w / 2, y0 + cell_h / 2), ch_,
                                 font=font, fill=(tfr, tfg, tfb), anchor="mm")
                    except Exception:
                        pass

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    img.save(args.out, "PNG")
    print("[render_png] 已导出 %s  (%dx%d px, 网格 %dx%d, cell %dx%d)"
          % (args.out, img.width, img.height, cols, rows, cell_w, cell_h))
    sys.exit(0)


if __name__ == "__main__":
    main()
