#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
render_html.py — 把引擎绘制列表渲染成【自包含、可交互的 HTML】

思路：Roblox 的 GuiObject 模型（Position/Size/AnchorPoint + 圆角/描边/渐变/文本/
裁剪/ZIndex）与浏览器 DOM 盒模型高度同构，因此把每个元素映射成一个绝对定位 <div>，
用 CSS 还原样式——天然矢量、无限清晰，且能真实交互（悬停探查 / 缩放 / 切换视图）。

用法：
    from render_html import render_html
    render_html(report, "preview.html", title="SimpleUI")

或命令行：
    python3 render_html.py report.json out.html
"""

import base64
import html
import json
import os

# Roblox 同源字体（assets/fonts 下的可变字体 woff2）内嵌为 data URI，
# 让浏览器用与 Roblox 一致的字体度量渲染，缩小文本位置/宽度差异。
_FONT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         "assets", "fonts")
_FONT_FILES = [
    ("Source Sans 3", "SourceSans3-400.woff2"),   # ≈ Roblox Enum.Font.SourceSans*
    ("Inter", "Inter-400.woff2"),                 # ≈ Roblox Enum.Font.Gotham*
]


def _build_font_face_css():
    out = []
    for family, fn in _FONT_FILES:
        p = os.path.join(_FONT_DIR, fn)
        if not os.path.exists(p):
            continue
        with open(p, "rb") as f:
            b64 = base64.b64encode(f.read()).decode("ascii")
        out.append(
            "@font-face{font-family:'%s';font-style:normal;font-weight:100 900;"
            "font-display:swap;src:url(data:font/woff2;base64,%s) format('woff2');}"
            % (family, b64))
    return "\n".join(out)


FONT_FACE_CSS = _build_font_face_css()


def _esc_json(obj):
    s = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    # 避免文本里出现 </script> 破坏内联脚本
    return s.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


_CSS = r"""
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: #14161b;
  color: #c9d1d9;
  font-family: "Inter", "Noto Sans SC", "PingFang SC", "Microsoft YaHei", system-ui, sans-serif;
  min-height: 100vh;
  display: flex; flex-direction: column;
}
header {
  display: flex; align-items: center; gap: 14px; flex-wrap: wrap;
  padding: 10px 16px; background: #1b1e25; border-bottom: 1px solid #2b303b;
  position: sticky; top: 0; z-index: 9999;
}
header .title { font-weight: 700; font-size: 14px; color: #e6edf3; }
header .meta { font-size: 12px; color: #8b949e; }
header .ok { color: #3fb950; } header .bad { color: #f85149; }
header .spacer { flex: 1; }
button {
  background: #22262e; color: #c9d1d9; border: 1px solid #313744; border-radius: 6px;
  padding: 5px 10px; font-size: 12px; cursor: pointer; font-family: inherit;
}
button:hover { background: #2b303b; }
button.on { background: #2f6feb33; border-color: #2f6feb; color: #79c0ff; }
/* 用 overflow:auto + auto 外边距居中：视口比舞台大时从左上开始并**可滚动**，
   不会像 justify-content:center 那样向两侧溢出被裁剪（否则左侧会被面板盖住，
   导致"点左侧控件无反应"）。 */
.stage { flex: 1; padding: 20px; overflow: auto; }
.wrap { margin: 0 auto; position: relative; }
.viewport {
  position: relative; overflow: hidden;
  background: #0f1115;
  box-shadow: 0 24px 64px rgba(0,0,0,.55);
  outline: 1px solid #2b303b;
}
.gui { position: absolute; }
.gui.hl { outline: 2px solid #58a6ff !important; outline-offset: 0; }
.badges .gui[data-name]::after {
  content: attr(data-badge); position: absolute; left: 0; top: 0;
  transform: translateY(-100%); background: #2f6feb; color: #fff;
  font: 10px/1.4 ui-monospace, monospace; padding: 0 4px; border-radius: 3px 3px 0 0;
  pointer-events: none; white-space: nowrap;
}
.boxes .gui { outline: 1px dashed rgba(88,166,255,.35); }
.txt {
  width: 100%; height: 100%; display: flex; overflow: hidden;
}
.txt > span { display: block; width: 100%; }
#tip {
  position: fixed; pointer-events: none; z-index: 100000; display: none;
  background: #0d1117f2; border: 1px solid #30363d; border-radius: 6px;
  padding: 6px 9px; font: 11px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace;
  color: #c9d1d9; white-space: pre; box-shadow: 0 8px 24px rgba(0,0,0,.5);
}
"""

_JS = r"""
let REPORT = (typeof REPORT_DATA !== 'undefined' && REPORT_DATA) ? REPORT_DATA
             : { viewport: {w:800,h:600}, draws: [] };
let V = REPORT.viewport || {w:800,h:600};
let OPS = REPORT.draws || [];
const vp = document.getElementById('vp');

function c255(x){ return Math.max(0, Math.min(255, Math.round((x||0)*255))); }
function rgba(c, a){ return `rgba(${c255(c&&c.r)},${c255(c&&c.g)},${c255(c&&c.b)},${a})`; }

const FONTS = {
  Gotham: '"Inter","Montserrat","Segoe UI",system-ui',
  GothamBold: '"Inter","Montserrat","Segoe UI",system-ui',
  GothamBlack: '"Inter","Montserrat","Segoe UI",system-ui',
  GothamMedium: '"Inter","Montserrat","Segoe UI",system-ui',
  SourceSans: '"Source Sans 3","Segoe UI",system-ui',
  SourceSansBold: '"Source Sans 3","Segoe UI",system-ui',
  SourceSansItalic: '"Source Sans 3","Segoe UI",system-ui',
  SourceSansLight: '"Source Sans 3","Segoe UI",system-ui',
  Legacy: 'system-ui,"Segoe UI"',
  FredokaOne: '"Fredoka One","Baloo 2","Comic Sans MS"',
};
function fontStack(name){
  const base = FONTS[name] || FONTS.SourceSans;
  return base + ',"Noto Sans SC","PingFang SC","Microsoft YaHei",sans-serif';
}

function interp(stops, t, pick){
  if(!stops || !stops.length) return null;
  const s = stops.slice().sort((a,b)=>a.t-b.t);
  let prev = s[0];
  if(t <= (s[0].t||0)) return pick(s[0]);
  for(const k of s){
    if((k.t||0) >= t){ const span=(k.t-prev.t)||1; const f=(t-prev.t)/span;
      return pick(prev, k, f); }
    prev = k;
  }
  return pick(s[s.length-1]);
}

function backgroundOf(op){
  const bgA = op.bgAlpha==null?1:op.bgAlpha;
  const g = op.gradient;
  if(g && g.kps && g.kps.length){
    const rot = ((g.rotation||0)%360+360)%360;
    const ang = 90 + rot;   // Roblox 0=左→右；CSS 90deg 亦为左→右
    const tr = g.tr || [];
    const stops = g.kps.slice().sort((a,b)=>a.t-b.t).map(k=>{
      let a = bgA;
      if(tr.length){
        const tv = interp(tr, k.t, (p,q,f)=> f==null? p.v : p.v+(q.v-p.v)*f);
        if(tv!=null) a = bgA * (1 - tv);
      }
      return `${rgba(k,a)} ${(k.t*100).toFixed(2)}%`;
    });
    return `linear-gradient(${ang}deg, ${stops.join(',')})`;
  }
  const c = op.bg || {r:0,g:0,b:0};
  if(bgA<=0.004) return 'transparent';
  return rgba(c, bgA);
}

function shadowsOf(op){
  const sh = [];
  if(op.stroke){
    const st = op.stroke;
    sh.push(`0 0 0 ${st.thickness}px ${rgba(st, st.a==null?1:st.a)}`);
  }
  if(op.border && op.border.size>0){
    sh.push(`inset 0 0 0 ${op.border.size}px ${rgba(op.border.color,1)}`);
  }
  return sh.join(', ');
}

function clipOf(op){
  const c = op.clip; if(!c) return '';
  const rx0=Math.max(op.x,c.x), ry0=Math.max(op.y,c.y);
  const rx1=Math.min(op.x+op.w,c.x+c.w), ry1=Math.min(op.y+op.h,c.y+c.h);
  if(rx1<=rx0 || ry1<=ry0) return 'inset(0 0 100% 0)';
  const top=ry0-op.y, left=rx0-op.x, right=(op.x+op.w)-rx1, bottom=(op.y+op.h)-ry1;
  return `inset(${top}px ${right}px ${bottom}px ${left}px)`;
}

function mkText(op){
  const d = document.createElement('div');
  d.className = 'txt';
  const xa = op.xa||'Left', ya = op.ya||'Top';
  d.style.justifyContent = xa==='Center'?'center':(xa==='Right'?'flex-end':'flex-start');
  d.style.alignItems = ya==='Center'?'center':(ya==='Bottom'?'flex-end':'flex-start');
  if(op.pad){
    d.style.paddingTop=op.pad.t+'px'; d.style.paddingBottom=op.pad.b+'px';
    d.style.paddingLeft=op.pad.l+'px'; d.style.paddingRight=op.pad.r+'px';
  }
  const sp = document.createElement('span');
  sp.textContent = op.text;
  const size = op.textSize||14;
  const fname = op.font || '';
  sp.style.fontFamily = fontStack(fname);
  sp.style.fontSize = size+'px';
  // 按 Roblox 字体名映射字重（此前完全没设 font-weight，粗体也渲染成了常规体）
  sp.style.fontWeight = /Black/.test(fname) ? '900' : (/Bold|Medium/.test(fname) ? '700' : '400');
  sp.style.lineHeight = '1.2';
  sp.style.color = rgba(op.textColor, op.textAlpha==null?1:op.textAlpha);
  sp.style.whiteSpace = op.wrapped ? 'pre-wrap' : 'pre';
  sp.style.wordBreak = op.wrapped ? 'break-word' : 'normal';
  sp.style.textAlign = xa==='Center'?'center':(xa==='Right'?'right':'left');
  if(op.textStroke){
    const w = Math.max(1, Math.round(size*0.05));
    sp.style.webkitTextStroke = `${w}px ${rgba(op.textStroke, op.textStroke.a)}`;
  }
  if(op.scaled) sp.classList.add('scaled');
  d.appendChild(sp);
  return d;
}

function build(){
  vp.style.width = V.w+'px'; vp.style.height = V.h+'px';
  OPS.forEach(op=>{
    if(op.w<0.5||op.h<0.5) return;
    const el = document.createElement('div');
    el.className='gui';
    el.dataset.name = (op.class||'') + ' " ' + (op.name||'') + ' "';
    el.dataset.badge = '#'+op.seq;
    const st = el.style;
    st.left = op.x+'px'; st.top = op.y+'px';
    st.width = op.w+'px'; st.height = op.h+'px';
    const bg = backgroundOf(op);
    if(bg!=='transparent') st.background = bg;
    if(op.corner>0) st.borderRadius = op.corner+'px';
    const sh = shadowsOf(op); if(sh) st.boxShadow = sh;
    if(op.image){
      st.backgroundImage = `repeating-linear-gradient(45deg, ${rgba(op.imageColor,0.18)} 0 6px, transparent 6px 12px)`;
      st.backgroundBlendMode='overlay';
      if(bg!=='transparent') st.background = bg + ', ' + st.backgroundImage;
      else st.background = rgba(op.imageColor,0.10);
    }
    const cp = clipOf(op); if(cp) st.clipPath = cp;
    if(op.rotation) st.transform = `rotate(${op.rotation}deg)`;
    if(op.text) el.appendChild(mkText(op));

    el.addEventListener('mouseenter', ()=>showTip(op, el));
    el.addEventListener('mouseleave', hideTip);
    vp.appendChild(el);
  });
  fitScaled();
}

function fitScaled(){
  vp.querySelectorAll('span.scaled').forEach(sp=>{
    const box = sp.parentElement;
    const availW = box.clientWidth, availH = box.clientHeight;
    if(availW<=0||availH<=0) return;
    const text = sp.textContent;
    let lo=1, hi=200;
    for(let i=0;i<18;i++){
      const mid=(lo+hi)/2; sp.style.fontSize=mid+'px';
      const w = sp.scrollWidth, h = sp.scrollHeight;
      if(w<=availW && h<=availH) lo=mid; else hi=mid;
    }
    sp.style.fontSize=Math.floor(lo)+'px';
  });
}

const tip = document.getElementById('tip');
function showTip(op, el){
  const r = el.getBoundingClientRect();
  el.classList.add('hl');
  tip.textContent =
    `${op.class}  ${op.name||''}\n`+
    `x=${Math.round(op.x)} y=${Math.round(op.y)} w=${Math.round(op.w)} h=${Math.round(op.h)}\n`+
    `z=${op.zindex}  seq=${op.seq}`+
    (op.corner?`  radius=${op.corner}`:'')+
    (op.text?`\ntext=${JSON.stringify(op.text).slice(0,40)}`:'');
  tip.style.display='block';
  tip.style.left = Math.min(window.innerWidth-260, r.left)+'px';
  tip.style.top  = Math.min(window.innerHeight-80, r.bottom+6)+'px';
}
function hideTip(){ tip.style.display='none';
  vp.querySelectorAll('.gui.hl').forEach(e=>e.classList.remove('hl')); }

let zoom = 1;
let userZoomed = false;                    // 用户手动缩放后不再自动适应
// 缩放施加在 .viewport 上；外层 .wrap 按缩放后的尺寸撑开，保证滚动区与命中区域一致
function applyZoom(){
  const wrap = document.getElementById('wrap');
  const el = document.getElementById('vp');
  el.style.width = V.w + 'px';
  el.style.height = V.h + 'px';
  el.style.transformOrigin = 'top left';
  el.style.transform = `scale(${zoom})`;
  wrap.style.width = (V.w * zoom) + 'px';
  wrap.style.height = (V.h * zoom) + 'px';
}
// 自适应：让整个视口完整落在舞台内（避免超大视口被裁剪、点不到左侧）
function autoFitZoom(){
  const st = document.getElementById('stage');
  if (!st) return 1;
  const availW = st.clientWidth - 44, availH = st.clientHeight - 44;
  if (availW <= 60 || availH <= 60) return 1;
  return Math.max(0.2, Math.min(1, availW / V.w, availH / V.h));
}
document.getElementById('zin').onclick  = ()=>{ userZoomed=true; zoom=Math.min(6,zoom+0.25); applyZoom(); };
document.getElementById('zout').onclick = ()=>{ userZoomed=true; zoom=Math.max(0.2,zoom-0.25); applyZoom(); };
document.getElementById('z1').onclick   = ()=>{ userZoomed=true; zoom=1; applyZoom(); };
document.getElementById('tbox').onclick = e=>{ vp.classList.toggle('boxes'); e.target.classList.toggle('on'); };
document.getElementById('tseq').onclick = e=>{ vp.classList.toggle('badges'); e.target.classList.toggle('on'); };
document.getElementById('tx').onclick   = e=>{
  document.querySelectorAll('.txt').forEach(t=>t.style.visibility =
    (t.style.visibility==='hidden'?'visible':'hidden'));
  e.target.classList.toggle('on');
};
document.getElementById('tbg').onclick  = e=>{
  const cur = vp.style.background;
  vp.style.background = cur==='rgb(15, 17, 21)' ? '#f5f5f7' : '#0f1115';
  e.target.classList.toggle('on');
};

// 动态换渲染目标（预览服务器上传后调用）
function loadReport(rep) {
  REPORT = rep || { viewport: {w:800,h:600}, draws: [] };
  V = REPORT.viewport || {w:800,h:600};
  OPS = REPORT.draws || [];
  vp.innerHTML = '';
  hideTip();
  build();
  if (!userZoomed) zoom = autoFitZoom();
  applyZoom();
}
window.loadReport = loadReport;

if (typeof REPORT_DATA !== 'undefined' && REPORT_DATA) { build(); zoom = autoFitZoom(); applyZoom(); }
"""


def _header(meta):
    ok = meta.get("pass", 0)
    fail = meta.get("fail", 0)
    nerr = meta.get("errors", 0)
    cls = "ok" if (fail == 0 and nerr == 0) else "bad"
    return (
        '<header>'
        '<span class="title">Roblox UI 预览</span>'
        '<span class="meta">引擎 <b>%s</b></span>'
        '<span class="meta">视口 %dx%d</span>'
        '<span class="meta">元素 <b>%d</b></span>'
        '<span class="meta %s">断言 %d/%d · 错误 %d</span>'
        '<span class="spacer"></span>'
        '<button id="zout">−</button><button id="z1">100%%</button><button id="zin">＋</button>'
        '<button id="tbox">边界框</button>'
        '<button id="tseq">绘制序</button>'
        '<button id="tx">隐藏文字</button>'
        '<button id="tbg">浅色底</button>'
        '</header>' % (
            html.escape(str(meta.get("engine", "luau"))),
            int(meta.get("vw", 800)), int(meta.get("vh", 600)), int(meta.get("count", 0)),
            cls, ok, ok + fail, nerr,
        )
    )


def render_html(report, out_path, title="Roblox UI"):
    vp = report.get("viewport") or {}
    draws = report.get("draws") or []
    checks = report.get("checks") or {}
    meta = {
        "engine": report.get("engine", "luau"),
        "vw": vp.get("w", 800), "vh": vp.get("h", 600),
        "count": len(draws),
        "pass": int(checks.get("pass", 0)), "fail": int(checks.get("fail", 0)),
        "errors": len(report.get("errors") or []),
    }
    payload = {"viewport": vp, "draws": draws}
    doc = (
        "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n"
        "<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<title>" + html.escape(title) + "</title>\n"
        "<style>" + FONT_FACE_CSS + "\n" + _CSS + "</style>\n</head>\n<body>\n"
        + _header(meta) +
        "\n<div class=\"stage\" id=\"stage\"><div class=\"wrap\" id=\"wrap\">"
        "<div class=\"viewport\" id=\"vp\"></div></div></div>\n"
        "<div id=\"tip\"></div>\n"
        "<script>const REPORT_DATA=" + _esc_json(payload) + ";</script>\n"
        "<script>" + _JS + "</script>\n"
        "</body>\n</html>\n"
    )
    out_dir = os.path.dirname(os.path.abspath(out_path))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(doc)
    return out_path


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 3:
        print("用法: render_html.py <report.json> <out.html>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        rep = json.load(f)
    p = render_html(rep, sys.argv[2])
    print("已导出", p)
