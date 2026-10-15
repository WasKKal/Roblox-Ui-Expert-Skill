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
    --out FILE        输出 PNG 路径（默认 ./ui_render_luau.png）
    --viewport WxH    视口像素，默认 800x600
    --cell WxH        网格单元格像素，默认 8x16
    --bg COLOR        画布背景色 #RRGGBB，默认 #0F1115
    --no-glyphs       不绘制字符（只出纯色块，更接近真实 UI）
    --max-seconds N   场景最大虚拟秒数，默认 300
    --pump-after N    场景结束后额外推进的虚拟秒数，默认 1
    --luau PATH       luau 可执行路径（默认自动探测）
退出码：0 = 全部通过；1 = 有失败断言或运行错误；2 = 用法/加载/解释器错误
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
MONO_FONTS = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf",
]

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


def render_report(rep, out_path, bg, no_glyphs):
    from PIL import Image, ImageDraw
    cv = rep["canvas"]
    cols, rows = int(cv["cols"]), int(cv["rows"])
    cell_w, cell_h = int(cv.get("cell", {}).get("w", 8)), int(cv.get("cell", {}).get("h", 16))
    colors = str(cv["colors"])
    glyphs = str(cv.get("glyphs", ""))
    fgs = str(cv.get("fg", ""))

    img = Image.new("RGB", (cols * cell_w, rows * cell_h), bg)
    drw = ImageDraw.Draw(img)
    font = None if no_glyphs else load_mono_font(max(6, int(cell_h * 0.78)))

    n = cols * rows
    for i in range(n):
        r = int(colors[i * 8:i * 8 + 2], 16)
        gg = int(colors[i * 8 + 2:i * 8 + 4], 16)
        b = int(colors[i * 8 + 4:i * 8 + 6], 16)
        a = int(colors[i * 8 + 6:i * 8 + 8], 16)
        if a == 0:
            continue
        f = a / 255.0
        pr = int(r * f + bg[0] * (1 - f))
        pg = int(gg * f + bg[1] * (1 - f))
        pb = int(b * f + bg[2] * (1 - f))
        row, col = divmod(i, cols)
        x0, y0 = col * cell_w, row * cell_h
        drw.rectangle([x0, y0, x0 + cell_w - 1, y0 + cell_h - 1], fill=(pr, pg, pb))

        if font is not None and i * 8 + 8 <= len(fgs):
            fa = int(fgs[i * 8 + 6:i * 8 + 8], 16)
            if fa > 8:
                fr = int(fgs[i * 8:i * 8 + 2], 16)
                fgc = int(fgs[i * 8 + 2:i * 8 + 4], 16)
                fb = int(fgs[i * 8 + 4:i * 8 + 6], 16)
                ch_ = glyphs[i] if i < len(glyphs) else " "
                if ch_ and ch_ != " ":
                    ff = fa / 255.0
                    tfr = int(fr * ff + pr * (1 - ff))
                    tfg = int(fgc * ff + pg * (1 - ff))
                    tfb = int(fb * ff + pb * (1 - ff))
                    try:
                        drw.text((x0 + cell_w / 2, y0 + cell_h / 2), ch_,
                                 font=font, fill=(tfr, tfg, tfb), anchor="mm")
                    except Exception:
                        pass

    out_dir = os.path.dirname(os.path.abspath(out_path))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    img.save(out_path, "PNG")
    return img


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
    ap.add_argument("--cell", default="8x16")
    ap.add_argument("--bg", default="#0F1115", help="画布背景色 #RRGGBB")
    ap.add_argument("--no-glyphs", action="store_true", help="不绘制字符，只出纯色块")
    ap.add_argument("--max-seconds", type=float, default=300.0)
    ap.add_argument("--pump-after", type=float, default=1.0)
    ap.add_argument("--luau", default="", help="luau 可执行路径")
    args = ap.parse_args()

    try:
        vw, vh = (int(x) for x in args.viewport.lower().split("x"))
        cw, ch = (int(x) for x in args.cell.lower().split("x"))
    except ValueError:
        fail("--viewport/--cell 格式应为 WxH")
    if vw <= 0 or vh <= 0 or cw <= 0 or ch <= 0:
        fail("视口与网格必须为正数")

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

        main_src = (
            LUAU_HEADER
            + "\nloadsrc([[mock_runtime.lua]], [[%s]])\n" % mod_b64["mock_runtime.lua"]
            + "Vision = loadsrc([[vision.lua]], [[%s]])\n" % mod_b64["vision.lua"]
            + "Harness = loadsrc([[harness.lua]], [[%s]])\n" % mod_b64["harness.lua"]
            + "Vision.viewport = { w = %d, h = %d }\n" % (vw, vh)
            + "Vision.cell = { w = %d, h = %d }\n" % (cw, ch)
            + "\n".join(reg_lines) + "\n"
            + "Harness.runScenario(b64decode([[%s]]), [[%s]], { maxSeconds = %s })\n"
              % (b64(scenario_src), os.path.basename(args.scenario), repr(args.max_seconds))
            + "if Harness.snapshots == 0 then Snapshot([[结束状态]]) end\n"
            + "if %s > 0 then __MOCK.pumpSeconds(%s) end\n"
              % (repr(args.pump_after), repr(args.pump_after))
            + "Harness.summary()\n"
            + "EmitReport([[dummy]])\n"
        )
        main_path = os.path.join(tmp, "main.luau")
        with open(main_path, "w", encoding="utf-8") as f:
            f.write(main_src)

        print("[run_ui_luau] 使用解释器: %s" % luau)
        print("[run_ui_luau] 视口 %dx%d  网格 %dx%d  库 %d 个  场景 %s"
              % (vw, vh, cw, ch, len(libs), os.path.basename(args.scenario)))

        proc = subprocess.run([luau, main_path], capture_output=True, text=True)
        if proc.stdout:
            sys.stdout.write(proc.stdout)
        if proc.stderr:
            sys.stderr.write(proc.stderr)

        json_text = extract_json(proc.stdout or "")
        if not json_text:
            fail("未能从 luau 输出抽取 JSON（场景可能未正常结束）", 1)

        rep = json.loads(json_text)
        img = render_report(rep, args.out, bg, args.no_glyphs)
        print("[run_ui_luau] 已导出 %s  (%dx%d px)" % (args.out, img.width, img.height))

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
