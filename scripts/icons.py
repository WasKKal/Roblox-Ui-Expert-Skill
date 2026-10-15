#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""图标资源解析：把 Roblox 的 Image 引用还原成可绘制的图标。

Roblox 里的 ImageLabel.Image 可能是：
  * rbxasset://lucide-stub/terminal      —— 本 Skill 的 lucide 桩返回的确定性 URL
  * rbxasset://lucide/terminal.svg       —— 直接指向 lucide 名称
  * http(s)://host/path/terminal.png     —— 网络图片（可下载缓存）
  * rbxassetid://123456                  —— Roblox 官方资源（无鉴权无法获取 → 回退占位）
  * /abs/path/icon.png                   —— 本地文件（执行器 getcustomasset 场景）

本模块把前两类解析为 **Lucide 矢量图标**（本地 assets/icons 缓存优先，
缺失时按需下载并落盘），第四类直接读文件，其余回退几何占位。
"""
import os
import re
import io
import json
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ICON_DIR = os.path.join(ROOT, "assets", "icons")
CACHE_DIR = os.path.join(ROOT, "assets", "cache")

# 按需下载源（依次尝试）
_LUCIDE_SOURCES = (
    "https://cdn.jsdelivr.net/npm/lucide-static@latest/icons/%s.svg",
    "https://unpkg.com/lucide-static@latest/icons/%s.svg",
)
_UA = {"User-Agent": "RobloxUiExpert/1.0"}

_name_cache = {}
_svg_cache = {}
_img_cache = {}
_PACK = os.path.join(ROOT, "assets", "icons.json")
_pack_cache = None


def _load_pack():
    """加载打包的图标库 assets/icons.json（{图标名: SVG 源码}）。"""
    global _pack_cache
    if _pack_cache is None:
        _pack_cache = {}
        if os.path.exists(_PACK):
            try:
                with open(_PACK, "r", encoding="utf-8") as f:
                    _pack_cache = json.load(f)
            except Exception:
                _pack_cache = {}
    return _pack_cache


# ---------------------------------------------------------------------------
# 引用 → 图标名
# ---------------------------------------------------------------------------

def icon_name(ref):
    """从 Image 引用里提取图标名；无法判定时返回 None。"""
    if not ref:
        return None
    if ref in _name_cache:
        return _name_cache[ref]
    name = None
    s = str(ref).strip()

    # 明确带 lucide 的路径（rbxasset://lucide-stub/<name>、.../lucide/<name>.svg）
    m = re.search(r"lucide[a-z-]*/([A-Za-z0-9][A-Za-z0-9._-]*)", s)
    if m:
        name = m.group(1)
    elif re.match(r"^[A-Za-z][A-Za-z0-9-]*$", s):
        # 裸名（有些库直接写图像名）
        name = s
    else:
        # 取路径末段（去扩展名）
        m = re.search(r"([^/\\?#]+?)(?:\.(?:svg|png|jpg|jpeg|webp))?(?:[?#].*)?$", s)
        if m:
            name = m.group(1)

    if name:
        name = name.strip().lower()
        name = re.sub(r"\.(svg|png|jpe?g|webp)$", "", name)   # 去扩展名
        # Uri 编码 / 常见后缀清理
        name = re.sub(r"%[0-9a-f]{2}", "-", name)
        name = re.sub(r"[^a-z0-9-]", "-", name).strip("-")
        # Roblox 官方资源 id 不是名字
        if not name or name.isdigit() or re.match(r"^rbxasset", name):
            name = None
    _name_cache[ref] = name
    return name


# ---------------------------------------------------------------------------
# 图标名 → SVG
# ---------------------------------------------------------------------------

def _svg_path(name):
    return os.path.join(ICON_DIR, name + ".svg")


def _try_fetch_svg(name):
    """在线获取 lucide SVG，成功则落盘缓存。"""
    for tpl in _LUCIDE_SOURCES:
        url = tpl % name
        try:
            req = urllib.request.Request(url, headers=_UA)
            with urllib.request.urlopen(req, timeout=12) as r:
                if r.status != 200:
                    continue
                data = r.read()
            text = data.decode("utf-8", "replace")
            if "<svg" not in text:
                continue
            os.makedirs(ICON_DIR, exist_ok=True)
            with open(_svg_path(name), "w", encoding="utf-8") as f:
                f.write(text)
            return text
        except Exception:
            continue
    return None


def svg_for(name, allow_fetch=True):
    """返回图标的 SVG 源码。

    查找顺序：内存缓存 → 打包文件 assets/icons.json → 单文件 assets/icons/<name>.svg
    → 在线按需下载（成功则落盘缓存）。
    """
    if not name:
        return None
    if name in _svg_cache:
        return _svg_cache[name]
    text = None
    pack = _load_pack()
    if name in pack:
        text = pack[name]
    if text is None:
        p = _svg_path(name)
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    text = f.read()
            except Exception:
                text = None
    if text is None and allow_fetch:
        text = _try_fetch_svg(name)
    _svg_cache[name] = text
    return text


_SVG_HEAD = re.compile(r"<svg\b([^>]*)>", re.I)
_VIEWBOX = re.compile(r'viewBox\s*=\s*"([^"]*)"', re.I)
_FILL = re.compile(r'\bfill\s*=\s*"([^"]*)"', re.I)


def _rebuild_head(attrs, stroke):
    """按 lucide 的绘制约定重建 <svg> 头：尺寸自适应、描边着色、圆头圆角。"""
    vb = _VIEWBOX.search(attrs)
    view = vb.group(1) if vb else "0 0 24 24"
    fm = _FILL.search(attrs)
    fill = fm.group(1) if (fm and fm.group(1).lower() not in ("none", "")) else "none"
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s" width="100%%" height="100%%"'
            ' fill="%s" stroke="%s" stroke-width="2" stroke-linecap="round"'
            ' stroke-linejoin="round" preserveAspectRatio="xMidYMid meet">'
            % (view, fill, stroke))


def _with_head(svg_text, stroke):
    m = _SVG_HEAD.search(svg_text)
    if not m:
        return None
    return _rebuild_head(m.group(1), stroke) + svg_text[m.end():]


def inline_svg(svg_text, size=None):
    """把 lucide SVG 改写成可内联到 HTML 的片段（尺寸自适应、颜色继承 currentColor）。"""
    if not svg_text:
        return None
    return _with_head(svg_text, "currentColor")


# ---------------------------------------------------------------------------
# SVG → 位图（PNG 渲染用）
# ---------------------------------------------------------------------------

def rasterize(name, px, color=None, allow_fetch=True):
    """把图标渲染成 RGBA PNG 字节流（边长 px）。失败返回 None。"""
    svg_text = svg_for(name, allow_fetch=allow_fetch)
    if not svg_text:
        return None
    rgb = None
    if color:
        rgb = "#%02x%02x%02x" % (
            max(0, min(255, int(round(color.get("r", 1) * 255)))),
            max(0, min(255, int(round(color.get("g", 1) * 255)))),
            max(0, min(255, int(round(color.get("b", 1) * 255)))),
        )
    key = (name, int(px), rgb)
    if key in _img_cache:
        return _img_cache[key]
    src = _with_head(svg_text, rgb or "currentColor") or svg_text
    out = None
    try:
        import cairosvg
        out = cairosvg.svg2png(bytestring=src.encode("utf-8"),
                               output_width=int(px), output_height=int(px))
    except Exception:
        out = None
    _img_cache[key] = out
    return out


# ---------------------------------------------------------------------------
# 网络位图 / 本地位图
# ---------------------------------------------------------------------------

def _cache_key(ref):
    return re.sub(r"[^A-Za-z0-9]", "_", str(ref))[-80:]


def fetch_image(ref, allow_fetch=True):
    """下载/读取一个位图，返回字节流；失败返回 None。"""
    if not ref:
        return None
    if ref in _img_cache:
        return _img_cache[ref]
    data = None
    s = str(ref)
    if s.startswith(("http://", "https://")):
        key = _cache_key(s)
        os.makedirs(CACHE_DIR, exist_ok=True)
        cp = os.path.join(CACHE_DIR, key)
        if os.path.exists(cp):
            try:
                with open(cp, "rb") as f:
                    data = f.read()
            except Exception:
                data = None
        if data is None and allow_fetch:
            try:
                req = urllib.request.Request(s, headers=_UA)
                with urllib.request.urlopen(req, timeout=15) as r:
                    data = r.read()
                with open(cp, "wb") as f:
                    f.write(data)
            except Exception:
                data = None
    elif os.path.isabs(s) and os.path.exists(s):
        try:
            with open(s, "rb") as f:
                data = f.read()
        except Exception:
            data = None
    _img_cache[ref] = data
    return data


# ---------------------------------------------------------------------------
# 占位（无法还原资源时）
# ---------------------------------------------------------------------------

def placeholder_kind(ref):
    """返回 'lucide' / 'bitmap' / 'unknown'，供渲染器选择回退样式。"""
    s = str(ref or "")
    if icon_name(s):
        return "lucide"
    if s.startswith(("http://", "https://", "/")):
        return "bitmap"
    return "unknown"


def stats():
    n = 0
    if os.path.isdir(ICON_DIR):
        n = len([f for f in os.listdir(ICON_DIR) if f.endswith(".svg")])
    return {"icons_packed": len(_load_pack()), "icons_cached": n, "icon_dir": ICON_DIR}


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "stats":
        print(json.dumps(stats(), ensure_ascii=False, indent=2))
    else:
        print("用法: python3 icons.py stats")
