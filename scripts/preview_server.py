#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
preview_server.py — 可上传文件的 Roblox UI 在线预览服务器

浏览器无法执行 Luau，故本服务用**本地真实引擎**（luau / lupa）代跑：
  浏览器上传 .lua → 服务落盘 → 调用 run_ui_luau.py 执行 mock 运行时 + 布局引擎
  → 产出绘制列表 JSON → 页面用与 render_html.py 同一套 DOM+CSS 渲染器渲染。

用法：
    python3 scripts/preview_server.py --port 8765
    # 浏览器打开 http://127.0.0.1:8765/

API：
    GET  /                   预览页面（上传 + 渲染 + 交互 + 日志）
    POST /api/render         multipart：file(主库) / extra(可多个) / scenario(可选) /
                             engine / viewport   → { ok, report, logs, error }
    GET  /api/demo?name=...  渲染内置示例（simple / rich / delta）
    GET  /api/health
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import uuid

from flask import Flask, jsonify, request, Response

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL_ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from render_html import _CSS, _JS, FONT_FACE_CSS  # noqa: E402  复用同一套渲染器
from run_ui_luau import extract_json  # noqa: E402  复用同一套哨兵 JSON 抽取

app = Flask(__name__)

# 访问令牌：设置后所有页面/接口都需携带 ?k=<token>（或 X-Preview-Token 头）。
# 暴露到公网时建议开启——上传的 Lua 会在本机被执行，令牌可挡住随机扫描者。
ACCESS_TOKEN = None


@app.before_request
def _gate():
    if not ACCESS_TOKEN:
        return None
    tok = request.args.get("k") or request.headers.get("X-Preview-Token") or ""
    if tok == ACCESS_TOKEN:
        return None
    if request.method == "GET" and not request.path.startswith("/api/"):
        return Response(
            "<meta charset='utf-8'><h3>403 · 需要访问令牌</h3>"
            "<p>请在链接后附加 <code>?k=&lt;令牌&gt;</code> 再打开。</p>",
            status=403, mimetype="text/html")
    return jsonify({"ok": False, "error": "403 需要访问令牌"}), 403

RUN_LUAU = os.path.join(HERE, "run_ui_luau.py")
RUN_LUPA = os.path.join(HERE, "run_ui.py")
LUCIDE_STUB = os.path.join(SKILL_ROOT, "examples", "lucide_stub.lua")
EXAMPLES = os.path.join(SKILL_ROOT, "examples")

LUCIDE_URLS = [
    "https://cdn.jsdelivr.net/gh/WasKKal/DeltaExecutor-UI-Rebuild@latest/lucide/init.lua",
    "https://raw.githubusercontent.com/WasKKal/DeltaExecutor-UI-Rebuild/master/lucide/init.lua",
    "https://gcore.jsdelivr.net/gh/WasKKal/DeltaExecutor-UI-Rebuild@lucide-v6/lucide/init.lua",
]

# ---------------------------------------------------------------------------
# 自动场景：兼容「执行即建 UI」与「模块式库」两类
# ---------------------------------------------------------------------------
AUTO_SCENARIO = r"""
-- 由 preview_server.py 自动生成
local src = game:HttpGet("https://preview.local/main.lua")
local shim = "local _G = (getfenv and getfenv()) or _G\n"
local chunk, cerr = loadstring(shim .. src, "@main.lua")
check("编译成功", chunk ~= nil, tostring(cerr))

local moduleReturn
if chunk then
    task.spawn(function() moduleReturn = chunk() end)
end
pump(2.5)

-- 模块式库（返回带 new / CreateWindow 的表）：自动装配一个示例窗口
if guiRoot() == nil and type(moduleReturn) == "table" then
    pcall(function()
        local win
        if type(moduleReturn.new) == "function" then
            win = moduleReturn.new({ Title = "HTML 预览", Info = "上传的自定义 UI 库" })
        elseif type(moduleReturn.CreateWindow) == "function" then
            win = moduleReturn.CreateWindow({ Title = "HTML 预览", Info = "上传的自定义 UI 库" })
        end
        if type(win) == "table" then
            if type(win.Add) == "function" then win:Add() end
            if type(win.AddLabel) == "function" then win:AddLabel("预览", "由上传的 Lua 库构建") end
            if type(win.AddToggle) == "function" then win:AddToggle({ Title = "开关", Default = true }) end
            if type(win.AddSlider) == "function" then win:AddSlider({ Title = "数值", Default = 60 }) end
            if type(win.AddButton) == "function" then win:AddButton({ Text = "按钮", Callback = function() end }) end
        end
    end)
    pump(1.5)
end

Snapshot("preview")
check("已构建 UI（存在可见 GuiObject）", guiRoot() ~= nil)
check("实例数 > 5", countInstances() > 5, "count=" .. tostring(countInstances()))
__HARNESS.summary()
"""


def _run_engine(engine, workdir, scenario_path, libs, viewport, clicks=None, timeout=300):
    """调用 CLI 跑引擎，返回 (report dict or None, stdout 文本, 返回码)"""
    out_json = os.path.join(workdir, "_report.json")
    clicks = clicks or []
    if engine == "lupa":
        cmd = [sys.executable, RUN_LUPA, "--scenario", scenario_path,
               "--viewport", viewport, "--max-seconds", "40", "--emit-json"]
        for url, path in libs:
            cmd += ["--lib", "%s=%s" % (url, path)]
        # lupa 路径暂不支持交互点击（真实 luau 路径支持）
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        rep = None
        txt = (proc.stdout or "") + (proc.stderr or "")
        chunk = extract_json(txt)
        if chunk:
            try:
                rep = json.loads(chunk)
            except Exception:
                rep = None
        return rep, txt, proc.returncode

    cmd = [sys.executable, RUN_LUAU, "--scenario", scenario_path,
           "--viewport", viewport, "--max-seconds", "40",
           "--style", "grid", "--out", os.path.join(workdir, "_grid.png"),
           "--dump-json", out_json]
    for url, path in libs:
        cmd += ["--lib", "%s=%s" % (url, path)]
    for cx, cy in clicks:
        cmd += ["--click", "%s,%s" % (cx, cy)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    rep = None
    if os.path.exists(out_json):
        try:
            with open(out_json, "r", encoding="utf-8") as f:
                rep = json.load(f)
        except Exception:
            rep = None
    return rep, (proc.stdout or "") + (proc.stderr or ""), proc.returncode


def _clean_logs(text):
    """去掉巨大 JSON 段与噪声，保留人可读日志"""
    text = re.sub(r"--ROBLOXUI_JSON_BEGIN--.*?--ROBLOXUI_JSON_END--", "", text, flags=re.S)
    lines = []
    for ln in text.splitlines():
        if len(ln) > 400:
            ln = ln[:400] + " …"
        lines.append(ln)
    if len(lines) > 400:
        lines = lines[:200] + ["... (省略 %d 行)" % (len(lines) - 300)] + lines[-100:]
    return "\n".join(lines)


def _render(main_bytes, main_name, scenario_text, engine, viewport, extra_files, clicks=None):
    workdir = tempfile.mkdtemp(prefix="ui_preview_")
    try:
        libs = []
        # 主库：同时注册到两个 URL，兼容自动场景与按文件名约定的自定义场景
        main_path = os.path.join(workdir, "main.lua")
        with open(main_path, "wb") as f:
            f.write(main_bytes)
        libs.append(("https://preview.local/main.lua", main_path))
        if main_name:
            safe = os.path.basename(main_name)
            libs.append(("https://mock.local/" + safe, main_path))
        # 附加库：URL = https://preview.local/<文件名>
        for name, data in extra_files:
            safe = os.path.basename(name) or "extra.lua"
            p = os.path.join(workdir, safe)
            with open(p, "wb") as f:
                f.write(data)
            libs.append(("https://preview.local/" + safe, p))
        # Lucide 图标桩（DeltaUI 等库会请求；离线映射到内置桩）
        if os.path.exists(LUCIDE_STUB):
            for u in LUCIDE_URLS:
                libs.append((u, LUCIDE_STUB))

        scen = scenario_text.strip() or AUTO_SCENARIO
        scen_path = os.path.join(workdir, "scenario.lua")
        with open(scen_path, "w", encoding="utf-8") as f:
            f.write(scen)

        rep, logs, code = _run_engine(engine, workdir, scen_path, libs, viewport, clicks)
        if rep is None:
            return {"ok": False, "error": "引擎未产出绘制列表（见日志）",
                    "logs": _clean_logs(logs), "exit": code}
        return {"ok": True, "report": rep, "logs": _clean_logs(logs), "exit": code}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "执行超时", "logs": ""}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": "%s: %s" % (type(e).__name__, e), "logs": ""}
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


# ---------------------------------------------------------------------------
# 会话：记住上传内容与渲染参数，用于交互式点击的"重放"
# 每次点击 = 从头重放（库 → pump → 依次派发历史点击 + 新点击）→ 重新出图
# ---------------------------------------------------------------------------
SESSIONS = {}
SESSION_LOCK = threading.Lock()
MAX_SESSIONS = 40


def _new_session(main_bytes, main_name, scenario, engine, viewport, extras):
    sid = uuid.uuid4().hex[:12]
    with SESSION_LOCK:
        if len(SESSIONS) >= MAX_SESSIONS:
            for k in list(SESSIONS.keys())[:len(SESSIONS) - MAX_SESSIONS + 1]:
                SESSIONS.pop(k, None)
        SESSIONS[sid] = {"main": main_bytes, "name": main_name, "scenario": scenario,
                         "engine": engine, "viewport": viewport, "extras": extras,
                         "clicks": []}
    return sid


def _render_session(sess, extra_click=None):
    clicks = list(sess.get("clicks") or [])
    if extra_click:
        clicks = clicks + [extra_click]
    return _render(sess["main"], sess["name"], sess["scenario"], sess["engine"],
                   sess["viewport"], sess["extras"], clicks)


@app.post("/api/render")
def api_render():
    engine = request.form.get("engine", "luau")
    viewport = request.form.get("viewport", "800x600")
    if not re.match(r"^\d+x\d+$", viewport):
        viewport = "800x600"
    scenario = request.form.get("scenario", "")
    up = request.files.get("file")
    if up is None or not up.filename:
        return jsonify({"ok": False, "error": "请先选择要渲染的 Lua 文件"})
    lib_bytes = up.read()
    extras = []
    for f in request.files.getlist("extra"):
        if f and f.filename:
            extras.append((f.filename, f.read()))
    d = _render(lib_bytes, up.filename, scenario, engine, viewport, extras)
    if d.get("ok"):
        d["sessionId"] = _new_session(lib_bytes, up.filename, scenario, engine, viewport, extras)
    return jsonify(d)


@app.post("/api/click")
def api_click():
    data = request.get_json(silent=True) or {}
    sid = data.get("sessionId")
    sess = SESSIONS.get(sid)
    if not sess:
        return jsonify({"ok": False, "error": "会话已失效，请重新渲染"})
    if sess.get("engine") != "luau":
        return jsonify({"ok": False, "error": "交互点击仅支持 luau 引擎"})
    try:
        x = float(data.get("x")); y = float(data.get("y"))
    except (TypeError, ValueError):
        return jsonify({"ok": False, "error": "坐标无效"})
    sess.setdefault("clicks", []).append([x, y])
    d = _render_session(sess)
    d["sessionId"] = sid
    d["click"] = {"x": x, "y": y, "count": len(sess["clicks"])}
    return jsonify(d)


@app.post("/api/reset")
def api_reset():
    data = request.get_json(silent=True) or {}
    sid = data.get("sessionId")
    sess = SESSIONS.get(sid)
    if not sess:
        return jsonify({"ok": False, "error": "会话已失效，请重新渲染"})
    sess["clicks"] = []
    d = _render_session(sess)
    d["sessionId"] = sid
    d["click"] = None
    return jsonify(d)


@app.get("/api/demo")
def api_demo():
    name = request.args.get("name", "simple")
    table = {
        "simple": ("simple_ui.lua", "simple_scenario.lua"),
        "rich": ("rich_ui.lua", "rich_scenario.lua"),
    }
    if name == "delta":
        candidate = "/root/uploads/1791642772656330982-DeltaUI.lua.txt"
        if not os.path.exists(candidate):
            return jsonify({"ok": False, "error": "未找到 DeltaUI 上传文件"})
        lib, scen = candidate, os.path.join(EXAMPLES, "delta_scenario.lua")
    elif name in table:
        lib = os.path.join(EXAMPLES, table[name][0])
        scen = os.path.join(EXAMPLES, table[name][1])
    else:
        return jsonify({"ok": False, "error": "未知示例: " + name})

    if not os.path.exists(lib):
        return jsonify({"ok": False, "error": "示例文件缺失: " + lib})
    engine = request.args.get("engine", "luau")
    viewport = request.args.get("viewport", "1280x800" if name == "delta" else "800x600")
    with open(lib, "rb") as f:
        lib_bytes = f.read()
    with open(scen, "r", encoding="utf-8") as f:
        scen_text = f.read()
    # 示例场景按 https://mock.local/<文件名> 约定请求，故主库名取真实文件名
    main_name = os.path.basename(lib)
    if name == "simple":
        main_name = "simple_ui.lua"
    elif name == "rich":
        main_name = "rich_ui.lua"
    elif name == "delta":
        main_name = "DeltaUI.lua"
    d = _render(lib_bytes, main_name, scen_text, engine, viewport, [])
    if d.get("ok"):
        d["sessionId"] = _new_session(lib_bytes, main_name, scen_text, engine, viewport, [])
        d["demo"] = name
    return jsonify(d)


@app.get("/api/health")
def api_health():
    luau = shutil.which("luau") or ("/usr/local/bin/luau" if os.path.exists("/usr/local/bin/luau") else None)
    return jsonify({"ok": True, "luau": luau, "skill": SKILL_ROOT})


PAGE = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Roblox UI 在线预览 · 上传渲染</title>
<style>
__CSS__
/* ---- 预览页专属 ---- */
body { height: 100vh; }
.layout { flex: 1; display: flex; min-height: 0; }
.panel {
  width: 340px; flex: none; background: #161a21; border-right: 1px solid #2b303b;
  padding: 14px; overflow: auto; display: flex; flex-direction: column; gap: 12px;
}
.panel h3 { margin: 0; font-size: 13px; color: #e6edf3; font-weight: 700; }
.panel label { font-size: 12px; color: #8b949e; display: block; margin-bottom: 4px; }
.panel input[type=file], .panel select, .panel input[type=text], .panel textarea {
  width: 100%; background: #0d1117; color: #c9d1d9; border: 1px solid #30363d;
  border-radius: 6px; padding: 6px 8px; font-size: 12px; font-family: inherit;
}
.panel textarea { font-family: ui-monospace, Menlo, monospace; min-height: 120px; resize: vertical; }
.drop {
  border: 1.5px dashed #3a4150; border-radius: 10px; padding: 18px 12px; text-align: center;
  color: #8b949e; font-size: 12px; cursor: pointer; transition: .15s;
}
.drop.hot { border-color: #2f6feb; background: #2f6feb14; color: #79c0ff; }
.row { display: flex; gap: 8px; }
.row > * { flex: 1; }
.go { background: #2f6feb; border-color: #2f6feb; color: #fff; font-weight: 600; padding: 8px; }
.go:hover { background: #3b7bf5; }
.logs {
  flex: 1; min-height: 140px; background: #0d1117; border: 1px solid #30363d; border-radius: 8px;
  padding: 8px; overflow: auto; font: 11px/1.5 ui-monospace, Menlo, monospace; color: #8b949e;
  white-space: pre-wrap; word-break: break-word;
}
.logs .p { color: #3fb950; } .logs .f { color: #f85149; } .logs .e { color: #ffa657; }
.hint { font-size: 11px; color: #6e7681; line-height: 1.5; }
.spin { display:none; }
.busy .spin { display:inline; } .busy .go-txt { display:none; }
.viewport { cursor: crosshair; }
.clickmark {
  position: absolute; width: 18px; height: 18px; margin: -9px 0 0 -9px;
  border: 2px solid #58a6ff; border-radius: 50%; background: #58a6ff55;
  color: #fff; font: 10px/14px ui-monospace, monospace; text-align: center;
  pointer-events: none; z-index: 99999; box-shadow: 0 0 0 2px #0007;
}
</style>
</head><body>
<header>
  <span class="title">Roblox UI 在线预览</span>
  <span class="meta" id="hstat">上传 Lua → 真实引擎渲染</span>
  <span class="spacer"></span>
  <button id="zout">−</button><button id="z1">100%</button><button id="zin">＋</button>
  <button id="tbox">边界框</button><button id="tseq">绘制序</button>
  <button id="tx">隐藏文字</button><button id="tbg">浅色底</button>
  <button id="treset">重置交互</button>
</header>
<div class="layout">
  <aside class="panel">
    <h3>1 · 选择 Lua 文件</h3>
    <div class="drop" id="drop">拖入 .lua / .txt，或点击选择<input type="file" id="file" accept=".lua,.txt,.luau" multiple style="display:none"></div>
    <div class="hint" id="fileinfo">可多选：第一个为主库，其余按 文件名 映射为 https://preview.local/&lt;文件名&gt;</div>

    <h3>2 · 渲染设置</h3>
    <label>引擎</label>
    <select id="engine">
      <option value="luau">luau（真实 Luau 解释器，推荐）</option>
      <option value="lupa">lupa（Lua 5.5）</option>
    </select>
    <label>视口（WxH）</label>
    <input type="text" id="viewport" value="1280x800">
    <label>场景脚本（可选；留空则自动装配）</label>
    <textarea id="scenario" placeholder="留空 = 自动：加载库 → task.spawn 执行 → 若返回模块表则自动 new()/CreateWindow 并加示例控件"></textarea>
    <button class="go" id="go"><span class="go-txt">渲染</span><span class="spin">渲染中…</span></button>

    <h3>内置示例</h3>
    <div class="row">
      <button onclick="demo('simple')">简易 UI</button>
      <button onclick="demo('rich')">富特性</button>
      <button onclick="demo('delta')">DeltaUI</button>
    </div>

    <h3>日志</h3>
    <div class="logs" id="logs">等待渲染…</div>
  </aside>
  <div class="stage" id="stage"><div class="wrap" id="wrap"><div class="viewport" id="vp"></div></div></div>
</div>
<div id="tip"></div>
<script>window.PREVIEW_SERVER = true;</script>
<script>__JS__</script>
<script>
const $ = id => document.getElementById(id);
const K = new URLSearchParams(location.search).get('k') || '';
function api(u){ return K ? (u + (u.indexOf('?') >= 0 ? '&' : '?') + 'k=' + encodeURIComponent(K)) : u; }
let picked = [];

function setLogs(html){ $('logs').innerHTML = html; }
function colorize(text){
  return text.split('\\n').map(l=>{
    if (l.startsWith('[PASS]') || l.includes('通过')) return '<span class="p">'+esc(l)+'</span>';
    if (l.startsWith('[FAIL]')) return '<span class="f">'+esc(l)+'</span>';
    if (l.includes('报错') || l.includes('错误:') && !l.includes('错误: 0')) return '<span class="e">'+esc(l)+'</span>';
    return esc(l);
  }).join('\\n');
}
function esc(s){ return s.replace(/&/g,'&amp;').replace(/</g,'&lt;'); }

function applyPicked(){
  picked = Array.from($('file').files || []);
  if (picked.length) {
    $('fileinfo').textContent = '已选 ' + picked.length + ' 个：' + picked.map(f=>f.name).join('、')
      + '（主库：' + picked[0].name + '）';
  } else {
    $('fileinfo').textContent = '可多选：第一个为主库，其余按 文件名 映射为 https://preview.local/<文件名>';
  }
}
$('file').addEventListener('change', applyPicked);

const drop = $('drop');
['dragenter','dragover'].forEach(e=>drop.addEventListener(e, ev=>{ev.preventDefault();drop.classList.add('hot');}));
['dragleave','drop'].forEach(e=>drop.addEventListener(e, ev=>{ev.preventDefault();drop.classList.remove('hot');}));
drop.addEventListener('drop', ev=>{
  $('file').files = ev.dataTransfer.files; applyPicked();
});
drop.addEventListener('click', ()=>$('file').click());

async function render(payload, isForm){
  document.body.classList.add('busy');
  setLogs('渲染中… 引擎执行 + 布局计算');
  try {
    const res = await fetch(api('/api/render'), { method:'POST', body: payload });
    const j = await res.json();
    if (j.logs) setLogs(colorize(j.logs));
    if (!j.ok) { setLogs(colorize((j.logs||'') + '\\n[ERROR] ' + (j.error||'渲染失败'))); return; }
    SID = j.sessionId || null; clicks = [];
    window.loadReport(j.report); drawMarkers();
    $('hstat').textContent = '元素 ' + (j.report.draws||[]).length + ' · 断言 '
      + (j.report.checks?(j.report.checks.pass+'/'+((j.report.checks.pass||0)+(j.report.checks.fail||0))):'-')
      + ' · 错误 ' + ((j.report.errors||[]).length)
      + (SID ? ' · 可点击' : '');
  } catch (e) {
    setLogs('[ERROR] ' + e);
  } finally {
    document.body.classList.remove('busy');
  }
}

// ---- 交互：点击画布 → 命中测试 + 派发点击 → 重放重渲染 ----
let SID = null, clicks = [];
function drawMarkers(){
  const vp = document.getElementById('vp');
  clicks.forEach((c, i)=>{
    const d = document.createElement('div');
    d.className = 'clickmark';
    d.style.left = c.x + 'px'; d.style.top = c.y + 'px';
    d.textContent = (i + 1);
    vp.appendChild(d);
  });
}
function busy(on){ document.body.classList.toggle('busy', !!on); }

document.getElementById('vp').addEventListener('click', async e=>{
  if (!SID) { setLogs('当前画面没有可交互会话：请先在左侧上传/渲染（交互需要会话）'); return; }
  const vp = document.getElementById('vp');
  const r = vp.getBoundingClientRect();
  const x = (e.clientX - r.left) / zoom, y = (e.clientY - r.top) / zoom;
  busy(true); setLogs('点击 (' + Math.round(x) + ',' + Math.round(y) + ') → 命中测试并派发事件…');
  try {
    const res = await fetch(api('/api/click'), { method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ sessionId: SID, x: x, y: y }) });
    const j = await res.json();
    if (j.logs) setLogs(colorize(j.logs));
    if (!j.ok) { setLogs(colorize((j.logs||'') + '\\n[ERROR] ' + (j.error||''))); return; }
    clicks.push({x: x, y: y});
    window.loadReport(j.report); drawMarkers();
    $('hstat').textContent = '元素 ' + (j.report.draws||[]).length + ' · 已点击 ' + clicks.length + ' 次';
  } catch(err) { setLogs('[ERROR] ' + err); }
  finally { busy(false); }
});

document.getElementById('treset').onclick = async ()=>{
  if (!SID) return;
  busy(true);
  try {
    const res = await fetch(api('/api/reset'), { method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ sessionId: SID }) });
    const j = await res.json();
    if (j.logs) setLogs(colorize(j.logs));
    if (!j.ok) { setLogs(colorize((j.logs||'') + '\\n[ERROR] ' + (j.error||''))); return; }
    clicks = [];
    window.loadReport(j.report); drawMarkers();
    $('hstat').textContent = '已重置交互 · 元素 ' + (j.report.draws||[]).length;
  } catch(err){ setLogs('[ERROR] ' + err); }
  finally { busy(false); }
};

$('go').onclick = () => {
  if (!picked.length) { alert('请先选择 Lua 文件'); return; }
  const fd = new FormData();
  fd.append('file', picked[0]);
  for (let i=1;i<picked.length;i++) fd.append('extra', picked[i]);
  fd.append('engine', $('engine').value);
  fd.append('viewport', $('viewport').value.trim());
  fd.append('scenario', $('scenario').value);
  render(fd, true);
};

async function demo(name){
  document.body.classList.add('busy');
  setLogs('加载内置示例 ' + name + ' …');
  try {
    const res = await fetch(api('/api/demo?name=' + encodeURIComponent(name)
      + '&engine=' + $('engine').value + '&viewport=' + encodeURIComponent($('viewport').value.trim())));
    const j = await res.json();
    if (j.logs) setLogs(colorize(j.logs));
    if (!j.ok) { setLogs(colorize((j.logs||'') + '\\n[ERROR] ' + (j.error||''))); return; }
    SID = j.sessionId || null; clicks = [];
    window.loadReport(j.report); drawMarkers();
    $('hstat').textContent = '示例 ' + name + ' · 元素 ' + (j.report.draws||[]).length
      + (SID ? ' · 可点击' : '');
  } catch(e){ setLogs('[ERROR] ' + e); }
  finally { document.body.classList.remove('busy'); }
}
window.demo = demo;

// 首屏自动渲染：?demo=simple|rich|delta 或默认 rich
const q = new URLSearchParams(location.search);
demo(q.get('demo') || 'rich');
</script>
</body></html>
"""


@app.get("/")
def index():
    html = PAGE.replace("__CSS__", FONT_FACE_CSS + "\n" + _CSS).replace("__JS__", _JS)
    return Response(html, mimetype="text/html; charset=utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--token", default="",
                    help="访问令牌；设置后需以 ?k=<token> 访问（公网映射时建议开启，可写 auto 自动生成）")
    args = ap.parse_args()
    global ACCESS_TOKEN
    if args.token == "auto":
        import secrets
        ACCESS_TOKEN = secrets.token_urlsafe(9)
        print("[preview_server] 访问令牌: %s" % ACCESS_TOKEN)
    elif args.token:
        ACCESS_TOKEN = args.token
    print("[preview_server] http://%s:%d/  (skill: %s)" % (args.host, args.port, SKILL_ROOT))
    app.run(host=args.host, port=args.port, debug=False, threaded=True)


if __name__ == "__main__":
    main()
