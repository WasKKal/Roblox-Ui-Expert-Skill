#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_render_precision.py — 无头渲染器的几何精度自检。

构造一组最小绘制指令，交给 render_hires.render_image()，再用像素分析量化：

  A) 圆角描边贴合：主体为纯黑圆角矩形，UIStroke 为纯白。沿 45° 角射线测量
     「主体轮廓半径」与「描边外沿半径」的差（gap）。理想值 ~0（描边贴在轮廓上），
     旧实现把描边盒子内缩 th/2 且不同步调整圆角半径，会出现明显缝隙。
     同时测量直边（水平中线）上的内缩量。

  B) 文字居中偏差：居中 TextLabel，白色文字 + 纯黑容器。取文字 ink 像素的
     bbox 中心，与容器几何中心比较。理想 |dx|,|dy| <= 1 逻辑像素。

用法：
    python3 scripts/check_render_precision.py            # 打印报告
    python3 scripts/check_render_precision.py --json      # 机器可读
    python3 scripts/check_render_precision.py --strict    # 超阈值时退出码 1

退出码 0 表示全部指标在容差内；--strict 下超阈值返回 1（用于 CI 回归）。
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_hires import render_image

BG = (0, 0, 255)          # 纯蓝背景：便于区分主体（黑）与描边（白）
BLACK = {"r": 0.0, "g": 0.0, "b": 0.0}
WHITE = {"r": 1.0, "g": 1.0, "b": 1.0}
BLUE = {"r": 0.0, "g": 0.0, "b": 1.0}
S = 3                      # scale=3, ss=1 → 每个逻辑像素对应 3×3 实际像素

# ---- 场景 A：圆角 + 描边 -------------------------------------------------
RX, RY, RW, RH = 60.0, 60.0, 100.0, 100.0
CORNER = 24.0
THICK = 3.0

# ---- 场景 B：居中文字 ---------------------------------------------------
TX, TY, TW, TH = 60.0, 220.0, 200.0, 64.0
TEXT = "Ag"


def build_report():
    ops = [
        {
            "seq": 1, "class": "Frame", "name": "RoundStroke",
            "x": RX, "y": RY, "w": RW, "h": RH,
            "bg": BLACK, "bgAlpha": 1.0, "corner": CORNER,
            "stroke": {"thickness": THICK, "a": 1.0, "r": 1.0, "g": 1.0, "b": 1.0},
        },
        {
            "seq": 2, "class": "TextLabel", "name": "CenteredText",
            "x": TX, "y": TY, "w": TW, "h": TH,
            "bg": BLACK, "bgAlpha": 1.0, "corner": 0.0,
            "text": TEXT, "textColor": WHITE, "textAlpha": 1.0,
            "textSize": 24.0, "font": "SourceSans",
            "xa": "Center", "ya": "Center", "wrapped": False, "scaled": False,
        },
    ]
    return {"viewport": {"w": 400, "h": 340}, "draws": ops}


def _is_white(px):
    return px[0] > 200 and px[1] > 200 and px[2] > 200


def _is_black(px):
    return px[0] < 55 and px[1] < 55 and px[2] < 55


def measure_corner(im):
    """沿左上角 45° 射线测量描边与主体轮廓的贴合误差（逻辑像素）。"""
    a = np.array(im.convert("RGB"))
    # 角圆心（逻辑坐标）
    cx, cy = RX + CORNER, RY + CORNER
    ux, uy = -1.0 / math.sqrt(2), -1.0 / math.sqrt(2)
    # 从 r=0 到 r=CORNER+8 逐步采样（每 0.1 逻辑像素）
    samples = []
    for step in range(0, int((CORNER + 10) * 10)):
        r = step / 10.0
        x = int(round((cx + ux * r) * S))
        y = int(round((cy + uy * r) * S))
        if 0 <= y < a.shape[0] and 0 <= x < a.shape[1]:
            px = a[y, x]
            samples.append((r, _is_white(px), _is_black(px), px))
    white_r = [r for r, w, b, px in samples if w]
    black_r = [r for r, w, b, px in samples if b]
    if not white_r:
        return {"ok": False, "reason": "no stroke pixels on 45deg ray"}
    # 期望：描边外沿在 r=CORNER（主体轮廓）之外（约 +th/2），内沿在之内
    outer = max(white_r)
    inner = min(white_r)
    # 主体色出现在描边外侧 = 存在缝隙（描边被画到主体内部，与边缘不贴合）
    outer_black = [r for r in black_r if r > outer + 0.2]
    gap = (min(outer_black) - outer) if outer_black else 0.0
    # 描边中心线相对主体轮廓的偏移（正=向外，负=向内）
    center_offset = (outer + inner) / 2.0 - CORNER
    return {
        "ok": True,
        "stroke_outer_r": round(outer, 2),
        "stroke_inner_r": round(inner, 2),
        "corner_radius": CORNER,
        "center_offset": round(center_offset, 2),
        "gap_black_outside_stroke": round(gap, 2),
        "stroke_width_measured": round(outer - inner + 0.1, 2),
    }


def measure_straight_edge(im):
    """直边（水平中线）：描边外沿距主体左边界的距离，理想为 0 或略负（外扩）。"""
    a = np.array(im.convert("RGB"))
    y = int(round((RY + RH / 2.0) * S))
    row = a[y]
    # 从左边界外 8px 扫到内 20px
    x0 = int((RX - 10) * S)
    x1 = int((RX + 22) * S)
    whites = [i for i in range(x0, x1) if _is_white(row[i])]
    if not whites:
        return {"ok": False, "reason": "no stroke pixels on straight edge"}
    outer = min(whites) / S - RX        # 逻辑像素，负=在边界外
    inner = max(whites) / S - RX
    return {
        "ok": True,
        "edge_outer_offset": round(outer, 2),
        "edge_inner_offset": round(inner, 2),
        "inset_from_edge": round(outer, 2),   # 正=描边整体内缩、不贴合
    }


def measure_body(im):
    """主体填充 bbox 的中心偏移（逻辑像素）。

    旧实现把 ox 写成 rx0-x，带 stroke 的元素会整体偏移 ex 像素并被裁掉边角，
    中心随之偏移约 5px；这里量测中心，防止该回归。
    注意：描边居中绘制会覆盖主体边缘约 th/2，故不用边界、改用 bbox 中心。
    """
    a = np.array(im.convert("RGB"))
    reg = a[0:int(200 * S), :, :]
    blk = (reg[:, :, 0] < 55) & (reg[:, :, 1] < 55) & (reg[:, :, 2] < 55)
    ys, xs = np.nonzero(blk)
    if len(xs) == 0:
        return {"ok": False, "reason": "no body pixels"}
    cx = (float(xs.min()) + float(xs.max())) / 2.0 / S
    cy = (float(ys.min()) + float(ys.max())) / 2.0 / S
    return {
        "ok": True,
        "center_dx": round(cx - (RX + RW / 2.0), 2),
        "center_dy": round(cy - (RY + RH / 2.0), 2),
    }


def measure_text(im):
    """文字 ink bbox 中心与容器几何中心的偏差（逻辑像素）。"""
    a = np.array(im.convert("RGB"))
    x0, y0 = int(TX * S), int(TY * S)
    x1, y1 = int((TX + TW) * S), int((TY + TH) * S)
    reg = a[y0:y1, x0:x1]
    white = (reg[:, :, 0] > 200) & (reg[:, :, 1] > 200) & (reg[:, :, 2] > 200)
    ys, xs = np.nonzero(white)
    if len(xs) == 0:
        return {"ok": False, "reason": "no text ink pixels"}
    ink_x0, ink_x1 = float(xs.min()) / S, float(xs.max()) / S
    ink_y0, ink_y1 = float(ys.min()) / S, float(ys.max()) / S
    cx = (ink_x0 + ink_x1) / 2.0
    cy = (ink_y0 + ink_y1) / 2.0
    box_cx, box_cy = TW / 2.0, TH / 2.0
    return {
        "ok": True,
        "ink_bbox": [round(ink_x0, 1), round(ink_y0, 1), round(ink_x1, 1), round(ink_y1, 1)],
        "ink_size": [round(ink_x1 - ink_x0, 1), round(ink_y1 - ink_y0, 1)],
        "dx": round(cx - box_cx, 2),
        "dy": round(cy - box_cy, 2),
    }


def main():
    strict = "--strict" in sys.argv
    as_json = "--json" in sys.argv
    rep = build_report()
    im = render_image(rep, bg=BG, scale=S, ss=1)
    res = {
        "body": measure_body(im),
        "corner": measure_corner(im),
        "straight_edge": measure_straight_edge(im),
        "text": measure_text(im),
    }
    bd = res["body"]
    co = res["corner"]
    se = res["straight_edge"]
    tx = res["text"]
    # 容差：主体落点 <=1.2、角部中心线偏移 <=1.5、缝隙 <=0.6、
    # 直边内缩 <=1.2；文字 |dx|,|dy| <=1.5（单位均为逻辑像素）
    checks = {
        "body_center_x": bool(bd.get("ok") and abs(bd.get("center_dx", 99)) <= 1.2),
        "body_center_y": bool(bd.get("ok") and abs(bd.get("center_dy", 99)) <= 1.2),
        "corner_center_offset": bool(co.get("ok") and abs(co.get("center_offset", 99)) <= 1.5),
        "corner_no_gap": bool(co.get("ok") and co.get("gap_black_outside_stroke", 99) <= 0.6),
        "straight_edge_inset": bool(se.get("ok") and se.get("inset_from_edge", 99) <= 1.2),
        "text_dx": bool(tx.get("ok") and abs(tx.get("dx", 99)) <= 1.5),
        "text_dy": bool(tx.get("ok") and abs(tx.get("dy", 99)) <= 1.5),
    }
    res["checks"] = checks
    res["all_pass"] = bool(all(checks.values()))
    if as_json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print("=== render precision check (scale=%d, ss=1) ===" % S)
        print("body        :", bd)
        print("corner      :", co)
        print("straight    :", se)
        print("text        :", tx)
        print("checks      :", checks)
        print("ALL PASS    :", res["all_pass"])
    if strict and not res["all_pass"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
