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
import os
from PIL import Image, ImageDraw, ImageFont, ImageChops

try:
    import icons as _icons          # 同目录：图标资源解析（lucide SVG / 位图）
except Exception:                   # pragma: no cover
    _icons = None

# 拉丁字形用 Roblox 同源字体（Source Sans 3 ≈ Enum.Font.SourceSans，Inter ≈ Gotham），
# 中文（CJK）回退到 Noto Sans CJK（Roblox 本身也没有 CJK 字形，由引擎回退）
_ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "fonts")
_ROBLOX_FONTS = {
    "sans": os.path.join(_ASSETS, "SourceSans3-400.ttf"),
    "inter": os.path.join(_ASSETS, "Inter-400.ttf"),
}
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
    """Roblox Enum.Font 名 → 字体族"""
    n = fontname or ""
    if "Gotham" in n:
        return "inter"
    return "sans"          # SourceSans / Legacy / 其它一律用 Source Sans 3


def load_font(size, bold=False, family="sans"):
    size = max(4, int(round(size)))
    key = (size, bool(bold), family)
    if key in _font_cache:
        return _font_cache[key]
    font = None
    if family in _ROBLOX_FONTS and os.path.exists(_ROBLOX_FONTS[family]):
        try:
            font = ImageFont.truetype(_ROBLOX_FONTS[family], size)   # 可变字体：一份覆盖全字重
            if bold:
                try:
                    font.set_variation_by_axes([600])
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


def _grad_strip(w, h, grad):
    """按 UIGradient（Rotation + 关键点）生成一张 RGB 渐变图（尺寸 w×h）。"""
    kps = sorted(grad.get("kps") or [], key=lambda k: k.get("t", 0))
    if not kps:
        return None
    rot = int(round(grad.get("rotation", 0))) % 360
    w = max(1, int(round(w)))
    h = max(1, int(round(h)))

    def color_at(t):
        t = _clamp(t, 0.0, 1.0)
        prev = kps[0]
        for kp in kps:
            tt = kp.get("t", 0)
            if tt > t:
                span = tt - prev.get("t", 0)
                f = (t - prev.get("t", 0)) / span if span > 1e-9 else 1.0
                return tuple(int(round(_clamp(prev[k] + (kp[k] - prev[k]) * f, 0, 1) * 255))
                             for k in ("r", "g", "b"))
            prev = kp
        return tuple(int(round(_clamp(prev[k], 0, 1) * 255)) for k in ("r", "g", "b"))

    if rot in (0, 180):
        strip = Image.new("RGB", (w, 1))
        px = strip.load()
        for x in range(w):
            t = x / max(1, w - 1)
            if rot == 180:
                t = 1 - t
            px[x, 0] = color_at(t)
        return strip.resize((w, h))
    else:
        strip = Image.new("RGB", (1, h))
        px = strip.load()
        for y in range(h):
            t = y / max(1, h - 1)
            if rot == 270:
                t = 1 - t
            px[0, y] = color_at(t)
        return strip.resize((w, h))


def _wrap(lines, size, bold, family, max_w):
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    out = []
    for line in lines:
        if line == "":
            out.append("")
            continue
        cur = ""
        for ch in line:
            if ch == "\n":
                out.append(cur)
                cur = ""
                continue
            if cur == "" or measure(cur + ch, size, bold, family, d) <= max_w:
                cur += ch
            else:
                out.append(cur)
                cur = ch
        out.append(cur)
    return out


def _draw_image(L, op, ox, oy, w, h):
    """把 ImageLabel / ImageButton 真正画成图标。

    资源解析顺序：
      1) Image 引用能判定为图标名（rbxasset://lucide-stub/terminal 等）→ 用本地
         lucide SVG 经 cairosvg 光栅化，并以 ImageColor3 着色（矢量、任意尺寸清晰）
      2) http(s) / 本地文件位图 → 解码后按元素矩形缩放
      3) 都无法还原（如 rbxassetid:// 官方资源）→ 半透明占位块
    """
    ref = op.get("imageRef") or ""
    ic = _rgb(op.get("imageColor") or {"r": 1, "g": 1, "b": 1})
    ia = _clamp(float(op.get("imageAlpha", 1)), 0.0, 1.0)
    # 注意：调用处传入的 w/h 已经是「视口尺寸 × S」，不要再乘一次 S
    tw = max(1, int(round(w)))
    th = max(1, int(round(h)))
    if ia <= 0.004 or tw <= 0 or th <= 0:
        return

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

    if im is not None:
        if im.size != (tw, th):
            im = im.resize((tw, th), Image.LANCZOS)
        if ia < 0.999:
            im.putalpha(im.split()[3].point(lambda v: int(v * ia)))
        L.alpha_composite(im, (int(round(ox)), int(round(oy))))
        return

    # 回退：半透明占位（无法获取该资源像素时）
    ImageDraw.Draw(L).rectangle(
        [ox, oy, ox + w - 1, oy + h - 1], fill=(ic[0], ic[1], ic[2], _a255(ia * 0.20)))


def _draw_text(layer, op, ox, oy, w, h, S):
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
    fontname = op.get("font") or ""
    bold = ("Bold" in fontname) or ("Black" in fontname)
    family = family_of(fontname)
    base_size = float(op.get("textSize", 14)) * S
    wrapped = bool(op.get("wrapped"))
    scaled = bool(op.get("scaled"))
    lines = text.split("\n")
    d = ImageDraw.Draw(layer)

    def line_metrics(size):
        f0 = load_font(size, bold, family)
        try:
            asc, desc = f0.getmetrics()
        except Exception:
            asc, desc = size, size * 0.25
        lh = asc + desc
        ls = _wrap(lines, size, bold, family, aw) if wrapped else lines
        tw = max((measure(s, size, bold, family, d) for s in ls), default=0)
        return ls, lh, lh * len(ls), tw

    if scaled:
        # 二分求最大可容纳字号（宽/高双约束）
        lo, hi = 1.0, max(base_size, 4.0)
        best = None
        for _ in range(18):
            mid = (lo + hi) / 2
            ls, lh, th, tw = line_metrics(mid)
            if tw <= aw and th <= ah:
                best = (mid, ls, lh, th)
                lo = mid
            else:
                hi = mid
        if best is None:
            ls0, lh0, th0, _ = line_metrics(4.0)
            best = (4.0, ls0, lh0, th0)
        size, ls, lh, total_h = best
    else:
        size = base_size
        ls, lh, total_h, _ = line_metrics(size)

    xa = op.get("xa", "Left")
    ya = op.get("ya", "Top")
    if ya == "Center":
        by = ay + (ah - total_h) / 2
    elif ya == "Bottom":
        by = ay + ah - total_h
    else:
        by = ay

    fill = (tc[0], tc[1], tc[2], ta)
    for i, ln in enumerate(ls):
        if ln == "":
            continue
        lw = measure(ln, size, bold, family, d)
        if xa == "Center":
            bx = ax + (aw - lw) / 2
        elif xa == "Right":
            bx = ax + aw - lw
        else:
            bx = ax
        yy = by + i * lh
        for seg, f in runs_of(ln, size, bold, family):
            d.text((bx, yy), seg, font=f, fill=fill)
            bx += d.textlength(seg, font=f)


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
        ex = 0
        if stroke:
            ex = max(ex, float(stroke.get("thickness", 0)) * S)
        if border:
            ex = max(ex, float(border.get("size", 0)) * S)

        rx0, ry0, rx1, ry1 = x - ex, y - ex, x + w + ex, y + h + ex
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

        ox = rx0 - x
        oy = ry0 - y
        L = Image.new("RGBA", (RW, RH), (0, 0, 0, 0))
        radius = max(0.0, float(op.get("corner", 0)) * S)
        radius = min(radius, min(w, h) / 2.0)

        # 1) 填充：渐变优先，否则纯色
        bgA = float(op.get("bgAlpha", 0))
        grad = op.get("gradient")
        bgc = op.get("bg")
        if grad or (bgc and bgA > 0.004):
            if grad:
                strip = _grad_strip(w, h, grad)
                if strip is not None:
                    gl = Image.new("RGBA", (RW, RH), (0, 0, 0, 0))
                    gl.paste(strip.convert("RGBA"), (int(round(ox)), int(round(oy))))
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

        # 2) 图像 / 图标（ImageLabel、ImageButton）
        if op.get("image"):
            _draw_image(L, op, ox, oy, w, h)

        # 3) 边框（BorderSizePixel）
        if border and float(border.get("size", 0)) > 0:
            bs = max(1, int(round(float(border["size"]) * S)))
            bc = _rgb(border.get("color"))
            ImageDraw.Draw(L).rectangle(
                [ox + bs / 2.0, oy + bs / 2.0, ox + w - 1 - bs / 2.0, oy + h - 1 - bs / 2.0],
                outline=(bc[0], bc[1], bc[2], 255), width=bs)

        # 4) 描边（UIStroke，圆角命中）
        if stroke:
            th = max(1, int(round(float(stroke.get("thickness", 0)) * S)))
            sc = (int(round(stroke.get("r", 0) * 255)),
                  int(round(stroke.get("g", 0) * 255)),
                  int(round(stroke.get("b", 0) * 255)))
            sa = _a255(float(stroke.get("a", 1)))
            ImageDraw.Draw(L).rounded_rectangle(
                [ox + th / 2.0, oy + th / 2.0, ox + w - 1 - th / 2.0, oy + h - 1 - th / 2.0],
                radius=radius, outline=(sc[0], sc[1], sc[2], sa), width=th)

        # 5) 文本
        if show_text and op.get("text"):
            _draw_text(L, op, ox, oy, w, h, S)

        # 6) 旋转（Roblox Rotation：绕元素中心顺时针）→ 合成到临时整幅层再旋转
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
