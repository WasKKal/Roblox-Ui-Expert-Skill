#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
render_hires.py — 用矢量方式把引擎绘制列表渲染成【清晰】的 PNG

与「色彩网格逐格放大」的旧做法不同：
本渲染器消费 vision.buildDrawList() 输出的「每个 GuiObject 的精确矩形 + 样式」，
用 PIL 以【超采样 + 真实字体】矢量绘制：
  · 圆角矩形（按 UICorner 半径）
  · 线性渐变（UIGradient，按 Rotation + 关键点求值）
  · 描边（UIStroke）/ 边框（BorderSizePixel）
  · 文本（按 TextSize / 字体 / 对齐 / 自动换行 / TextScaled，用真实 CJK 字体）
  · 裁剪（父级 ClipsDescendants / ScrollingFrame 的裁剪矩形）
  · 层级（按绘制序叠加，alpha 合成）

用法（一般由 run_ui_luau.py 调用）：
    from render_hires import render_hires
    render_hires(report, "out.png", scale=2)
"""

import io
import math
import os
import re
from PIL import Image, ImageDraw, ImageFont, ImageChops

try:
    import icons as _icons          # 同目录：图标资源解析（lucide SVG / 位图）
except Exception:                   # pragma: no cover
    _icons = None

# 拉丁字形用 Roblox 同源字体（Source Sans 3 ≈ Enum.Font.SourceSans，Inter ≈ Gotham），
# 中文（CJK）回退到 Noto Sans CJK（Roblox 本身也没有 CJK 字形，由引擎回退）
_ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "fonts")
_FONT_DIRS = [_ASSETS, "/usr/share/fonts/truetype/robloxlike"]
_FONT_FILES = {
    "sans": {"400": "SourceSans3-400.ttf", "600": "SourceSans3-600.ttf"},
    "inter": {"400": "Inter-400.ttf", "600": "Inter-600.ttf"},
}


def _font_path(family, bold):
    """按字重取字体文件：先找同目录的 600 字重，再退 400。"""
    files = _FONT_FILES.get(family)
    if not files:
        return None
    for key in (("600", "400") if bold else ("400",)):
        name = files.get(key)
        if not name:
            continue
        for d in _FONT_DIRS:
            p = os.path.join(d, name)
            if os.path.exists(p):
                return p
    return None
_CJK_REGULAR = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]
_CJK_BOLD = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

_font_cache = {}


def family_of(fontname):
    """Roblox Enum.Font 名 → 字体族。

    Builder Sans（Roblox 现在的默认 UI 字体）是自研字体，最接近的开源替代是 Inter；
    Gotham / Montserrat 同属几何无衬线，也走 Inter。Source Sans / Legacy 保持同源字体。
    """
    n = fontname or ""
    if ("Gotham" in n) or ("Builder" in n) or ("Montserrat" in n):
        return "inter"
    return "sans"          # SourceSans / Legacy / 其它一律用 Source Sans 3


def load_font(size, bold=False, family="sans"):
    size = max(4, int(round(size)))
    key = (size, bool(bold), family)
    if key in _font_cache:
        return _font_cache[key]
    font = None
    path = _font_path(family, bold)
    if path:
        try:
            font = ImageFont.truetype(path, size)
            if bold:
                try:
                    font.set_variation_by_axes([600])   # 可变字体时进一步加粗
                except Exception:
                    pass
        except Exception:
            font = None
    if font is None:                                    # CJK / 兜底
        for p in (_CJK_BOLD if bold else _CJK_REGULAR):
            if os.path.exists(p):
                try:
                    font = ImageFont.truetype(p, size)
                    break
                except Exception:
                    font = None
    if font is None:
        try:
            font = ImageFont.load_default(size=size)
        except TypeError:
            font = ImageFont.load_default()
    _font_cache[key] = font
    return font


def _is_cjk(ch):
    o = ord(ch)
    return (0x2E80 <= o <= 0x9FFF) or (0xF900 <= o <= 0xFAFF) or (0xFF00 <= o <= 0xFFEF) \
        or (0x3000 <= o <= 0x303F) or (0x20000 <= o <= 0x3FFFF)


def runs_of(text, size, bold, family):
    """按字符把文本切成 (子串, 字体) 段：拉丁→Roblox 同源字体，CJK→Noto"""
    out = []
    for ch in text:
        fam = "cjk" if _is_cjk(ch) else family
        if out and out[-1][1] == fam:
            out[-1][0] += ch
        else:
            out.append([ch, fam])
    return [(s, load_font(size, bold, fam)) for s, fam in out]


def measure(text, size, bold, family, draw):
    return sum(draw.textlength(s, font=f) for s, f in runs_of(text, size, bold, family))


def _clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def _rgb(c):
    if not c:
        return (0, 0, 0)
    return (int(round(_clamp(c.get("r", 0), 0, 1) * 255)),
            int(round(_clamp(c.get("g", 0), 0, 1) * 255)),
            int(round(_clamp(c.get("b", 0), 0, 1) * 255)))


def _a255(x):
    return int(round(_clamp(x, 0, 1) * 255))


def _grad_surface(w, h, grad):
    """按 UIGradient 生成 RGBA 渐变图。

    Rotation 为任意角度（0=左→右，90=上→下，顺时针），沿渐变轴做投影采样；
    同时支持 Transparency 关键点（沿轴渐隐）与 Offset（沿轴平移）。
    """
    kps = sorted(grad.get("kps") or [], key=lambda k: k.get("t", 0))
    if not kps:
        return None
    w = max(1, int(round(w)))
    h = max(1, int(round(h)))
    rot = math.radians(float(grad.get("rotation", 0) or 0))
    ux, uy = math.cos(rot), math.sin(rot)
    span = abs(w * ux) + abs(h * uy)
    if span < 1e-6:
        span = 1.0
    off = float(grad.get("ox", 0) or 0) * ux + float(grad.get("oy", 0) or 0) * uy

    import numpy as np
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = ((xx - (w - 1) / 2.0) * ux + (yy - (h - 1) / 2.0) * uy) / span + 0.5 + off
    t = np.clip(t, 0.0, 1.0)

    ts = [float(k.get("t", 0)) for k in kps]
    if len(ts) == 1:
        ts = [0.0, 1.0]
        r = np.full_like(t, float(kps[0].get("r", 0)))
        g = np.full_like(t, float(kps[0].get("g", 0)))
        b = np.full_like(t, float(kps[0].get("b", 0)))
    else:
        r = np.interp(t, ts, [float(k.get("r", 0)) for k in kps])
        g = np.interp(t, ts, [float(k.get("g", 0)) for k in kps])
        b = np.interp(t, ts, [float(k.get("b", 0)) for k in kps])

    tr = grad.get("tr")
    if tr:
        tts = [float(k.get("t", 0)) for k in tr]
        tv = [1.0 - float(k.get("v", 0)) for k in tr]
        a = np.interp(t, tts, tv) if len(tts) > 1 else np.full_like(t, tv[0])
    else:
        a = np.ones_like(t)

    arr = np.dstack([
        np.clip(r * 255.0, 0, 255).astype(np.uint8),
        np.clip(g * 255.0, 0, 255).astype(np.uint8),
        np.clip(b * 255.0, 0, 255).astype(np.uint8),
        np.clip(a * 255.0, 0, 255).astype(np.uint8),
    ])
    return Image.fromarray(arr, "RGBA")

def _wrap(lines, size, bold, family, max_w):
    """按 Roblox 的换行语义折行：优先在空格处断，超长单词再按字符断。"""
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    out = []
    for line in lines:
        if line == "":
            out.append("")
            continue
        if max_w <= 0 or measure(line, size, bold, family, d) <= max_w:
            out.append(line)
            continue
        cur = ""
        for word in re.findall(r"\s+|\S+", line):
            if cur and measure(cur + word, size, bold, family, d) > max_w:
                out.append(cur.rstrip())
                cur = ""
                word = word.lstrip()
                if word == "":
                    continue
            while word and measure(cur + word, size, bold, family, d) > max_w:
                # 单词本身超宽：逐字符塞入
                take = ""
                for ch in word:
                    if cur and measure(cur + take + ch, size, bold, family, d) > max_w:
                        break
                    take += ch
                if take == "":
                    take = word[:1]
                cur += take
                word = word[len(take):]
                if word:
                    out.append(cur)
                    cur = ""
            cur += word
        out.append(cur)
    return out

def _image_surface(op, w, h, S=1):
    """把 ImageLabel / ImageButton 解码成一张 w×h 的 RGBA 图（按 ScaleType 摆放）。"""
    ref = op.get("imageRef") or ""
    ic = _rgb(op.get("imageColor") or {"r": 1, "g": 1, "b": 1})
    ia = _clamp(float(op.get("imageAlpha", 1)), 0.0, 1.0)
    tw = max(1, int(round(w)))
    th = max(1, int(round(h)))
    if ia <= 0.004:
        return None

    im = None
    if _icons is not None:
        name = _icons.icon_name(ref)
        if name:
            png = _icons.rasterize(name, max(tw, th),
                                   {"r": ic[0] / 255.0, "g": ic[1] / 255.0, "b": ic[2] / 255.0})
            if png:
                try:
                    im = Image.open(io.BytesIO(png)).convert("RGBA")
                except Exception:
                    im = None
        if im is None:
            raw = _icons.fetch_image(ref)
            if raw:
                try:
                    im = Image.open(io.BytesIO(raw)).convert("RGBA")
                except Exception:
                    im = None

    if im is None:
        return None

    st = (op.get("scaleType") or "Stretch")
    tile = op.get("tile")
    if tile:
        st = "Tile"
    if st == "Fit" and im.size != (tw, th):
        k = min(tw / float(im.width), th / float(im.height))
        nw, nh = max(1, int(round(im.width * k))), max(1, int(round(im.height * k)))
        sm = im.resize((nw, nh), Image.LANCZOS)
        im = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        im.alpha_composite(sm, ((tw - nw) // 2, (th - nh) // 2))
    elif st == "Crop" and im.size != (tw, th):
        k = max(tw / float(im.width), th / float(im.height))
        nw, nh = max(1, int(round(im.width * k))), max(1, int(round(im.height * k)))
        sm = im.resize((nw, nh), Image.LANCZOS)
        left, top = (nw - tw) // 2, (nh - th) // 2
        im = sm.crop((left, top, left + tw, top + th))
    elif st == "Tile":
        tw0 = int(round(float((tile or {}).get("w", 0)) * S)) if tile else tw
        th0 = int(round(float((tile or {}).get("h", 0)) * S)) if tile else th
        tw0 = max(1, tw0)
        th0 = max(1, th0)
        sm = im.resize((tw0, th0), Image.LANCZOS)
        canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        for yy in range(0, th, th0):
            for xx in range(0, tw, tw0):
                canvas.alpha_composite(sm, (xx, yy))
        im = canvas
    elif im.size != (tw, th):
        im = im.resize((tw, th), Image.LANCZOS)

    if ia < 0.999:
        im.putalpha(im.split()[3].point(lambda v: int(v * ia)))
    return im


def _ellipsize(line, size, bold, family, d, max_w):
    ell = "\u2026"
    if measure(ell, size, bold, family, d) > max_w:
        return ""
    lo, hi = 0, len(line)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if measure(line[:mid] + ell, size, bold, family, d) <= max_w:
            lo = mid
        else:
            hi = mid - 1
    return line[:lo].rstrip() + ell


def _font_stack(op):
    fontname = op.get("font") or ""
    bold = ("Bold" in fontname) or ("Black" in fontname)
    return bold, family_of(fontname)


def _text_layout(op, S, avail_w, avail_h):
    """计算文本排版：返回 (字号, 行列表, 行高, 总高, 最宽行宽)。

    行高按 Roblox 的 TextSize*1.2 处理（与 mock 的 TextBounds 估算一致），
    TextScaled 时在 [MinTextSize, MaxTextSize] 内二分求最大可容纳字号。
    """
    text = op.get("text") or ""
    bold, family = _font_stack(op)
    base_size = max(1.0, float(op.get("textSize", 14)) * S)
    wrapped = bool(op.get("wrapped"))
    scaled = bool(op.get("scaled"))
    raw_lines = text.split("\n")
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))

    def metrics(size):
        ls = _wrap(raw_lines, size, bold, family, avail_w) if wrapped else raw_lines
        lh = size * 1.2
        bw = 0.0
        for ln in ls:
            ww = measure(ln, size, bold, family, d)
            if ww > bw:
                bw = ww
        return ls, lh, lh * len(ls), bw

    if scaled:
        lo = max(1.0, float(op.get("minTextSize", 1)) * S)
        hi = min(base_size, float(op.get("maxTextSize", 400)) * S)
        if hi < lo:
            hi = lo
        best = None
        for _ in range(18):
            mid = (lo + hi) / 2.0
            ls, lh, th, bw = metrics(mid)
            if bw <= avail_w + 0.01 and th <= avail_h + 0.01:
                best = (mid, ls, lh, th, bw)
                lo = mid
            else:
                hi = mid
        if best is None:
            s0, lh0, th0, bw0 = metrics(max(1.0, lo))
            best = (max(1.0, lo), s0, lh0, th0, bw0)
        return best
    return (base_size,) + metrics(base_size)


def _draw_text(layer, op, ox, oy, w, h, S, layout=None):
    text = op.get("text") or ""
    if text == "":
        return
    pad = op.get("pad")
    ax, ay, aw, ah = ox, oy, w, h
    if pad:
        ax += pad.get("l", 0) * S
        ay += pad.get("t", 0) * S
        aw -= (pad.get("l", 0) + pad.get("r", 0)) * S
        ah -= (pad.get("t", 0) + pad.get("b", 0)) * S
    if aw <= 1 or ah <= 1:
        return

    tc = _rgb(op.get("textColor") or {"r": 1, "g": 1, "b": 1})
    ta = _a255(op.get("textAlpha", 1))
    if ta <= 6:
        return
    bold, family = _font_stack(op)
    if layout is None:
        layout = _text_layout(op, S, aw, ah)
    size, ls, lh, total_h, block_w = layout
    d = ImageDraw.Draw(layer)

    # 基线：行盒内居中（半行距），各字体段共用同一条基线，
    # 避免中文 fallback 字体的 ascent 更大而整体下沉。
    f0 = load_font(size, bold, family)
    try:
        asc, desc = f0.getmetrics()
    except Exception:
        asc, desc = size * 0.8, size * 0.2
    lead = (lh - (asc + desc)) / 2.0

    xa = op.get("xa", "Left")
    ya = op.get("ya", "Center")
    if ya == "Center":
        by = ay + (ah - total_h) / 2.0
    elif ya == "Bottom":
        by = ay + ah - total_h
    else:
        by = ay

    fill = (tc[0], tc[1], tc[2], ta)
    stroke = op.get("textStroke")
    truncate = op.get("truncate")
    for i, ln in enumerate(ls):
        if ln == "":
            continue
        draw_ln = ln
        lw = measure(ln, size, bold, family, d)
        if truncate and not op.get("wrapped") and lw > aw:
            draw_ln = _ellipsize(ln, size, bold, family, d, aw)
            lw = measure(draw_ln, size, bold, family, d)
        if xa == "Center":
            bx = ax + (aw - lw) / 2.0
        elif xa == "Right":
            bx = ax + aw - lw
        else:
            bx = ax
        base_y = by + i * lh + lead + asc
        runs = runs_of(draw_ln, size, bold, family)
        if stroke and float(stroke.get("a", 0)) > 0.02:
            sc = _rgb(stroke)
            sa = _a255(float(stroke.get("a", 1)))
            rr = max(1.0, size * 0.07)
            for dx, dy in ((-rr, 0), (rr, 0), (0, -rr), (0, rr),
                           (-rr, -rr), (rr, -rr), (-rr, rr), (rr, rr)):
                xx = bx
                for seg, f in runs:
                    try:
                        d.text((xx + dx, base_y + dy), seg, font=f,
                               fill=(sc[0], sc[1], sc[2], sa), anchor="ls")
                    except Exception:
                        d.text((xx + dx, base_y + dy - asc), seg, font=f,
                               fill=(sc[0], sc[1], sc[2], sa))
                    xx += d.textlength(seg, font=f)
        xx = bx
        for seg, f in runs:
            try:
                d.text((xx, base_y), seg, font=f, fill=fill, anchor="ls")
            except Exception:
                d.text((xx, base_y - asc), seg, font=f, fill=fill)
            xx += d.textlength(seg, font=f)


def render_image(report, bg=(15, 17, 21), scale=2, ss=3, show_text=True):
    """把 report['draws'] 渲染成 PIL RGB 图像（不落盘）。

    scale：最终图像相对视口的放大倍数（输出尺寸 = 视口 × scale）
    ss   ：超采样倍数（内部按 scale×ss 绘制，再降采样抗锯齿）；ss=1 则不抗锯齿
    """
    ops = report.get("draws") or []
    vp = report.get("viewport") or {}
    W = int(vp.get("w", 800))
    H = int(vp.get("h", 600))
    zoom = max(1, int(scale))
    SS = max(1, int(ss))
    # 画布像素保护：超采样是"按 zoom×SS 绘制再降采样"，超大视口下会画到几千万像素，
    # 渲染时间线性增长。这里在超过预算时自动降 SS（保留 zoom，输出尺寸不变）。
    MAX_CANVAS_PIXELS = 24000000
    while SS > 1 and (W * zoom * SS) * (H * zoom * SS) > MAX_CANVAS_PIXELS:
        SS -= 1
    if SS != max(1, int(ss)):
        import sys as _sys
        print("[render_hires] 画布 %dx%d 超采样超预算，ss 由 x%d 降为 x%d（输出尺寸不变）"
              % (W * zoom, H * zoom, max(1, int(ss)), SS), file=_sys.stderr)
    S = zoom * SS                      # 实际绘制倍率
    cw, ch = W * S, H * S
    canvas = Image.new("RGBA", (cw, ch), (bg[0], bg[1], bg[2], 255))

    for op in ops:
        x = float(op.get("x", 0)) * S
        y = float(op.get("y", 0)) * S
        w = float(op.get("w", 0)) * S
        h = float(op.get("h", 0)) * S
        if w < 0.5 or h < 0.5:
            continue

        stroke = op.get("stroke")
        border = op.get("border")
        ex = 0.0
        if stroke:
            ex = max(ex, float(stroke.get("thickness", 0)) * S)
        if border:
            ex = max(ex, float(border.get("size", 0)) * S)
        exL = exR = exT = exB = ex

        # 文本可能溢出元素矩形（Roblox 不用元素矩形裁剪自身文字），预先算好外延
        tl = None
        if show_text and op.get("text"):
            pad = op.get("pad")
            aw = w - ((pad.get("l", 0) + pad.get("r", 0)) * S if pad else 0)
            ah = h - ((pad.get("t", 0) + pad.get("b", 0)) * S if pad else 0)
            if aw > 1 and ah > 1:
                tl = _text_layout(op, S, aw, ah)
                _sz, _ls, _lh, th, bw = tl
                xa = op.get("xa", "Left")
                ya = op.get("ya", "Center")
                over_w = max(0.0, bw - aw)
                # TextTruncate 会把文本裁到可用宽度内，不需要为溢出扩边
                if op.get("truncate") and not op.get("wrapped"):
                    over_w = 0.0
                if over_w > 0:
                    if xa == "Center":
                        exL = max(exL, over_w / 2.0)
                        exR = max(exR, over_w / 2.0)
                    elif xa == "Right":
                        exL = max(exL, over_w)
                    else:
                        exR = max(exR, over_w)
                over_h = max(0.0, th - ah)
                if over_h > 0:
                    if ya == "Center":
                        exT = max(exT, over_h / 2.0)
                        exB = max(exB, over_h / 2.0)
                    elif ya == "Bottom":
                        exT = max(exT, over_h)
                    else:
                        exB = max(exB, over_h)

        rx0, ry0, rx1, ry1 = x - exL, y - exT, x + w + exR, y + h + exB
        clip = op.get("clip")
        if clip:
            rx0 = max(rx0, clip["x"] * S)
            ry0 = max(ry0, clip["y"] * S)
            rx1 = min(rx1, (clip["x"] + clip["w"]) * S)
            ry1 = min(ry1, (clip["y"] + clip["h"]) * S)
        rx0 = max(0.0, rx0)
        ry0 = max(0.0, ry0)
        rx1 = min(float(cw), rx1)
        ry1 = min(float(ch), ry1)
        RW = int(round(rx1 - rx0))
        RH = int(round(ry1 - ry0))
        if RW <= 0 or RH <= 0:
            continue

        # 元素矩形在图层坐标系中的位置（layer 左上角 = canvas 的 (rx0, ry0)）
        ox = x - rx0
        oy = y - ry0
        L = Image.new("RGBA", (RW, RH), (0, 0, 0, 0))
        radius = max(0.0, float(op.get("corner", 0)) * S)
        radius = min(radius, min(w, h) / 2.0)

        # 1) 填充：渐变优先，否则纯色
        bgA = float(op.get("bgAlpha", 0))
        grad = op.get("gradient")
        bgc = op.get("bg")
        if grad or (bgc and bgA > 0.004):
            if grad:
                strip = _grad_surface(w, h, grad)
                if strip is not None:
                    gl = Image.new("RGBA", (RW, RH), (0, 0, 0, 0))
                    gl.paste(strip, (int(round(ox)), int(round(oy))))
                    mask = Image.new("L", (RW, RH), 0)
                    ImageDraw.Draw(mask).rounded_rectangle(
                        [ox, oy, ox + w - 1, oy + h - 1], radius=radius, fill=255)
                    m = mask.point(lambda v: int(v * _clamp(bgA, 0, 1)))
                    gl.putalpha(ImageChops.multiply(gl.split()[3], m))
                    L = Image.alpha_composite(L, gl)
            else:
                r, g, b = _rgb(bgc)
                ImageDraw.Draw(L).rounded_rectangle(
                    [ox, oy, ox + w - 1, oy + h - 1], radius=radius,
                    fill=(r, g, b, _a255(bgA)))

        # 2) 图像 / 图标（ImageLabel、ImageButton）：按 ScaleType 摆放，并被 UICorner 裁剪
        if op.get("image"):
            im = _image_surface(op, w, h, S)
            if im is None:
                ic = _rgb(op.get("imageColor") or {"r": 1, "g": 1, "b": 1})
                ia = _clamp(float(op.get("imageAlpha", 1)), 0.0, 1.0)
                im = Image.new("RGBA", (max(1, int(w)), max(1, int(h))),
                               (ic[0], ic[1], ic[2], _a255(ia * 0.20)))
            if radius > 0.5:
                mk = Image.new("L", im.size, 0)
                ImageDraw.Draw(mk).rounded_rectangle(
                    [0, 0, im.width - 1, im.height - 1], radius=radius, fill=255)
                im.putalpha(ImageChops.multiply(im.split()[3], mk))
            dx, dy = int(round(ox)), int(round(oy))
            if dx < 0 or dy < 0:
                cx0, cy0 = max(0, -dx), max(0, -dy)
                im = im.crop((cx0, cy0, im.width, im.height))
                dx += cx0
                dy += cy0
            L.alpha_composite(im, (dx, dy))

        # 3) 边框（BorderSizePixel）：沿圆角、画在内侧
        if border and float(border.get("size", 0)) > 0:
            bs = max(1, int(round(float(border["size"]) * S)))
            bc = _rgb(border.get("color"))
            ImageDraw.Draw(L).rounded_rectangle(
                [ox + bs / 2.0, oy + bs / 2.0, ox + w - 1 - bs / 2.0, oy + h - 1 - bs / 2.0],
                radius=max(0.0, radius - bs / 2.0),
                outline=(bc[0], bc[1], bc[2], 255), width=bs)

        # 4) 描边（UIStroke）：以元素边界为中心，内外各一半
        if stroke:
            th = max(1, int(round(float(stroke.get("thickness", 0)) * S)))
            sc = (int(round(stroke.get("r", 0) * 255)),
                  int(round(stroke.get("g", 0) * 255)),
                  int(round(stroke.get("b", 0) * 255)))
            sa = _a255(float(stroke.get("a", 1)))
            ImageDraw.Draw(L).rounded_rectangle(
                [ox - th / 2.0, oy - th / 2.0, ox + w - 1 + th / 2.0, oy + h - 1 + th / 2.0],
                radius=radius + th / 2.0, outline=(sc[0], sc[1], sc[2], sa), width=th)

        # 5) 文本（统一基线 + 可选描边 + TextTruncate）
        if show_text and op.get("text"):
            _draw_text(L, op, ox, oy, w, h, S, tl)

        # 6) 父级圆角裁剪（ClipsDescendants + UICorner）：裁剪区是圆角矩形
        if clip and float(clip.get("r", 0) or 0) > 0.01:
            mk = Image.new("L", (RW, RH), 0)
            ImageDraw.Draw(mk).rounded_rectangle(
                [clip["x"] * S - rx0, clip["y"] * S - ry0,
                 (clip["x"] + clip["w"]) * S - rx0 - 1, (clip["y"] + clip["h"]) * S - ry0 - 1],
                radius=float(clip["r"]) * S, fill=255)
            L.putalpha(ImageChops.multiply(L.split()[3], mk))

        # 7) 旋转（Roblox Rotation：绕元素中心顺时针）→ 合成到临时整幅层再旋转
        rot = float(op.get("rotation", 0) or 0)
        if abs(rot) > 0.01:
            tmp = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            tmp.alpha_composite(L, (int(round(rx0)), int(round(ry0))))
            cx = x + w / 2.0
            cy = y + h / 2.0
            tmp = tmp.rotate(-rot, center=(cx, cy), resample=Image.BICUBIC)
            canvas.alpha_composite(tmp)
        else:
            canvas.alpha_composite(L, (int(round(rx0)), int(round(ry0))))

    # 降采样到目标尺寸（超采样抗锯齿）
    target = (W * zoom, H * zoom)
    if canvas.size != target:
        canvas = canvas.resize(target, Image.LANCZOS)
    out = Image.new("RGB", canvas.size, bg)
    out.paste(canvas, (0, 0), canvas)

    return out


def _ensure_dir(path):
    d = os.path.dirname(os.path.abspath(path))
    if d:
        os.makedirs(d, exist_ok=True)


def render_hires(report, out_path, bg=(15, 17, 21), scale=2, ss=3, show_text=True):
    """渲染单帧清晰 PNG（= render_image + 落盘）。"""
    out = render_image(report, bg=bg, scale=scale, ss=ss, show_text=show_text)
    _ensure_dir(out_path)
    out.save(out_path, "PNG")
    return out


def render_apng(report, out_path, bg=(15, 17, 21), scale=2, ss=3, show_text=True, fps=0.0):
    """把 report['frames'] 逐帧渲染并合成 APNG（动画 PNG，浏览器可直接播放）。

    fps=0 时按引擎的采样间隔推算播放帧率。
    """
    frames = report.get("frames") or []
    if len(frames) < 2:
        return None
    interval = float(report.get("frameInterval") or 0.2)
    duration = (1000.0 / float(fps)) if (fps and float(fps) > 0) else max(20.0, interval * 1000.0)
    vp = report.get("viewport") or {}
    imgs = []
    for f in frames:
        sub = {"viewport": vp, "draws": f.get("draws") or []}
        imgs.append(render_image(sub, bg=bg, scale=scale, ss=ss, show_text=show_text))
    _ensure_dir(out_path)
    imgs[0].save(out_path, "PNG", save_all=True, append_images=imgs[1:],
                 duration=int(round(duration)), loop=0)
    return imgs[0]


if __name__ == "__main__":
    import json
    import sys
    if len(sys.argv) < 3:
        print("用法: render_hires.py <report.json> <out.png> [scale] [ss]", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        rep = json.load(f)
    sc = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    ssp = int(sys.argv[4]) if len(sys.argv) > 4 else 3
    img = render_hires(rep, sys.argv[2], scale=sc, ss=ssp)
    print("已导出 %s  (%dx%d)" % (sys.argv[2], img.width, img.height))
