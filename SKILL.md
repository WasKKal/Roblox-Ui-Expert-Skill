---
name: RobloxUiExpert
description: >
  Roblox / Luau UI 开发专家。让 Agent 通过 Luau 代码在「无头 mock 运行时」中
  构建并「看见」UI 画面（结构树 + ASCII 线框 + 色彩网格），无需 Roblox Studio
  即可开发、调试、审计 UI 库（如 DynamicCowUI 风格的设置面板 / 灵动岛 / 控件库）。
  当用户提到 Roblox UI、Luau、Instance 树、UICorner、UIStroke、UIListLayout、
  CanvasGroup、ScrollingFrame、TweenService、或要求「用代码画出 UI / 渲染 UI /
  mock 一个 Roblox 界面 / 审查布局 bug / 让 Agent 看到 UI」时使用本 Skill。
---

# RobloxUiExpert —— 让 Agent「看见」Roblox UI 的无头开发环境

本 Skill 把过去对真实 Roblox UI 库（7000+ 行）的审计、mock 测试、布局修复经验，
沉淀为一个**可直接运行的无头运行时 + 视觉渲染器**。Agent 写 Luau 代码构建 UI，
运行时给出三类「视图」让 Agent 像看截图一样理解画面：

1. **结构树** —— 每个 GuiObject 的绝对位置 / 尺寸 / 圆角 / 描边 / 文本 / 透明度
2. **ASCII 线框** —— 在终端里画出 UI 轮廓，边框避让文字
3. **色彩网格** —— 量化后的颜色图例，验证渐变 / 主题色是否生效

## 何时用

- 开发或改写一个 Roblox UI 库（窗口框架、灵动岛、Tab、各类控件）
- 不依赖 Roblox Studio，仅用 Luau 代码验证布局是否正确
- 审计 ZIndex 层级、遮挡关系、补间动画、文本溢出、圆角擦除等问题
- 复现并定位「界面元素错位 / 重叠 / 不显示 / 闪烁」类 bug
- 为真实库（DynamicCowUI 等）编写回归冒烟场景

## 目录结构

```
Roblox-Ui-Expert-Skill/
├── SKILL.md                  # 本文件
├── README.md                 # 快速上手 + 原理
├── scripts/
│   ├── mock_runtime.lua      # 无头运行时：Instance 树 / 值类型 / Enum / Signal /
│   │                         #   TweenService(延迟 Completed) / task 调度 / 输入 /
│   │                         #   执行器 FS(HttpGet/loadstring/getcustomasset/request)
│   ├── vision.lua            # 布局引擎 + 渲染器：算绝对矩形、输出结构树/ASCII/色彩网格
│   ├── harness.lua           # 场景驱动：check/pump/tapUI/fireUI/Snapshot 等全局
│   ├── run_ui.py             # CLI（lupa/Lua 5.5 路径）：运行场景 + 产出快照与断言报告
│   ├── run_ui_luau.py        # CLI（真实 Luau 解释器路径）：跑 Luau 引擎并渲染 PNG/HTML
│   ├── render_png.py         # 色彩网格 → PNG（逐格放大，粗）
│   ├── render_hires.py       # 矢量高清渲染：圆角/渐变/描边/旋转/真实字体文本 → 清晰 PNG
│   ├── render_html.py        # DOM+CSS 还原 → 自包含可交互 HTML（悬停探查/缩放/边界框）
│   └── preview_server.py     # 在线预览服务：上传 .lua → 真实引擎渲染 → 网页交互
├── examples/
│   ├── demo_ui.lua           # 自包含演示 UI（淡入 / Tab / 各类控件 / 提示）
│   ├── demo_scenario.lua     # 演示场景：13 条断言 + 3 张快照
│   ├── simple_ui.lua         # 简易 UI 库（标题栏+按钮+开关+滑条+进度+提示）
│   ├── simple_scenario.lua   # 简易场景：13 条断言，用于 luau 渲染验证
│   ├── rich_ui.lua           # 富特性 UI（渐变/渐隐/描边/旋转/图片/组透明/裁剪）
│   ├── rich_scenario.lua     # 富特性场景：16 条断言
│   ├── delta_scenario.lua    # 真实大型库 DeltaUI 渲染自检（12 条断言）
│   └── smoke_dynamiccow.lua  # 真实库 DynamicCowUI 冒烟（19 条断言全过）
└── references/
    ├── vision-api.md          # vision.lua + harness 全部 API
    ├── ui-pitfalls.md         # ≈25 条 Roblox UI 常见坑（审计清单）
    ├── luau-compat.md         # Luau → Lua 5.5 兼容子集与差异
    └── mock-runtime.md        # mock 模拟了什么 / 没模拟什么
```

## 30 秒上手

**运行演示（自带 UI 库）：**

```bash
python3 scripts/run_ui.py \
  --lib "https://mock.local/demo_ui.lua=examples/demo_ui.lua" \
  --scenario examples/demo_scenario.lua \
  --output /tmp/demo_out.txt
# 产出：结构树 + ASCII 线框 + 色彩网格 + 13/13 断言
```

**运行真实库冒烟（验证运行时承载力）：**

```bash
python3 scripts/run_ui.py \
  --lib "URL_A=path/to/DynamicCowUI.lua" \
  --lib "URL_B=path/to/lucide_init_v6.lua" \
  --scenario examples/smoke_dynamiccow.lua
```

**用【真实 Luau 解释器】渲染出 PNG（原生 Luau 语法 + 真实像素图）：**

```bash
# 需要 luau 可执行文件（从源码编译：cmake + make Luau.Repl.CLI）
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
  --scenario examples/simple_scenario.lua \
  --out /workspace/ui_render_luau.png
# 产出：真实像素 PNG + 13/13 断言；与原 lupa 路径的画布逐字节一致
```

`run_ui_luau.py` 与 `run_ui.py` 的区别：

| | `run_ui.py`（lupa） | `run_ui_luau.py`（真实 luau） |
|---|---|---|
| 执行引擎 | lupa 的 Lua 5.5 + 手写兼容层 | 官方 luau 解释器（源码编译） |
| 语法 | Lua 5.x 安全子集（无 `+=`/`continue`，无类型注解） | **原生 Luau 全语法**（`+=`/`continue`/类型注解/字符串插值） |
| 输出 | 结构树 + ASCII + 色彩网格（文本） | 同上 + **真实 PNG 像素图** |
| 传参方式 | lupa 进程内直接加载模块 | 模块/库/场景 base64 内联进入口，JSON 经 stdout 哨兵回传 |

**参数速查（`run_ui.py`）：**

| 参数 | 含义 |
|------|------|
| `--lib "URL=PATH"` | 注册一个「URL→本地/下载内容」映射，库里 `game:HttpGet(URL)` 会回源到该内容；可多次 |
| `--scenario FILE` | 场景脚本（协程驱动，可用 `pump`/`Snapshot`/`check` 等全局） |
| `--viewport 800x600` | 视口尺寸（默认 800x600） |
| `--cell 8x16` | 每字符格的像素尺寸（默认 8x16，决定 ASCII 分辨率） |
| `--max-seconds 300` | 场景最大虚拟时长 |
| `--pump-after 1` | 场景结束后补拍的秒数 |
| `--output FILE` | 把报告 Tee 落盘 |

`run_ui_luau.py` 额外参数：`--out FILE`（PNG 路径）、`--bg #RRGGBB`（画布底色）、
`--no-glyphs`（不绘文字）、`--luau PATH`（指定解释器）。

**要「清晰」的图，用矢量高清渲染（`--style hires`）：**

```bash
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
  --scenario examples/simple_scenario.lua \
  --out /workspace/ui_clear.png --style hires --scale 2 --ss 3
# 产出 1600x1200 清晰 PNG：圆角/渐变/描边/真实字体的中文文本
```

对比：

| 渲染方式 | 原理 | 观感 |
|----------|------|------|
| `--style grid`（默认） | 彩色字符网格逐格放大 | 粗；文字被当整格填充，只适合快速看轮廓 |
| `--style hires` | 消费每个元素的**精确矩形 + 完整样式**，用 PIL 以**超采样 + 真实 CJK 字体**矢量绘制 | 清晰锐利：圆角、渐变、描边、可读中文、开关/滑块/进度条 |

`--scale N` 控制输出放大（视口 ×N）；`--ss N` 控制超采样倍数（内部按 ×ss 绘制再降采样抗锯齿）。
也可 `--dump-json report.json` 落盘引擎报告，再用 `python3 scripts/render_hires.py report.json out.png 2 3` 离线重渲染。

**要「可交互」的版本，出 HTML（`--style html`）：**

```bash
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
  --scenario examples/rich_scenario.lua \
  --out /workspace/rich.html --style html
# 生成自包含 HTML：浏览器打开即可交互
```

HTML 渲染把每个 GuiObject 映射成绝对定位 `<div>`，用 CSS 还原（`border-radius` 圆角、
`linear-gradient` 渐变、`box-shadow` 描边/内边框、`clip-path: inset()` 裁剪、flex 文本
对齐、`rotate()` 旋转）——**天然矢量、无限清晰**，并内置交互：

- 鼠标悬停高亮元素 + 提示类名/名字/矩形/ZIndex/绘制序
- 工具栏：缩放、显示边界框、显示绘制序、隐藏文字、切换浅色底
- 自包含单文件（内嵌 JSON + CSS + JS），可直接分享

`--style` 可选 `grid` / `hires` / `html` / `both`（三者全出）。

**要「上传自己的 Lua 就渲染」的在线预览（`preview_server.py`）：**

```bash
python3 scripts/preview_server.py --port 8765
# 浏览器打开 http://127.0.0.1:8765/
```

浏览器无法执行 Luau，故由本地服务代跑真实引擎：页面拖入 `.lua` → 服务用
`run_ui_luau.py`（或 lupa）执行 mock 运行时 + 布局引擎 → 返回绘制列表 → 页面用**同一套
DOM+CSS 渲染器**渲染。页面提供：引擎切换（luau / lupa）、视口、可选场景脚本、文件多选
（第一个为主库，其余按文件名映射为 `https://preview.local/<文件名>`）、内置示例一键渲染、
实时日志（断言/警告/错误）。`?demo=simple|rich|delta` 可直接打开指定示例。

不带场景时服务会用**自动场景**：加载库 → `task.spawn` 执行 → 若返回模块表则自动
`new()` / `CreateWindow()` 并补几个示例控件；「执行即建 UI」的库（如 DeltaUI）则直接成图。

**可交互**：渲染完成后，在右侧画布上**点击任意位置**即可触发真实事件回路——
服务端按点击坐标做 `hitTest` 命中测试 → `tapUI` 派发 `MouseButton1Click` → 重放
（库 → pump → 依次回放历史点击）→ 返回新画面。左侧日志显示每步结果，画布上以编号圆环
标出点击点，"重置交互"可清空点击序列。CLI 侧等价能力：`run_ui_luau.py --click X,Y`（可多次）。

> 用 DeltaUI 可直观验证：点左侧导航按钮切换页面（如 `--click 25,465` 进入"设置/Settings"，
> 元素数 73 → 250），点"重置交互"回到初始页。

**映射到公网**（沙箱无 cloudflared，用 SSH 反向隧道最省事）：

```bash
# 1) 带访问令牌启动（公网暴露务必加令牌：上传的 Lua 会在本机被执行）
python3 scripts/preview_server.py --port 8765 --token auto     # 或 --token 你的口令

# 2) 隧道守护：自动连接 + 断线重连 + 地址实测可用后才发布
python3 scripts/public_tunnel.py --port 8765 --token <token>
#   输出：“[tunnel] ✅ 公网地址: https://xxxx.lhr.life/?k=<token>”
#   最新地址同时写入 /workspace/PUBLIC_URL.txt（可随时读取）
```

`public_tunnel.py` 用 localhost.run / serveo.net（均免费、无需账号），并做了三件事：
建立 SSH 反向隧道（`-R 80:localhost:<port>`）、从输出解析公网地址、**实测 `?k=<token>` 的
`/api/health` 返回 200 后才发布**；隧道断开自动重连并刷新地址文件。

安全提示：`--token` 会拦截所有未携带 `?k=<token>` 的请求（API 返回 403、页面返回提示页）。
免费隧道域名是**临时**的，SSH 断开或沙箱休眠后会失效——守护脚本会自动换新域名。
要**固定域名**需注册服务账号：serveo 支持自定义子域，但需先用 GitHub/Google 登录
`https://console.serveo.net/ssh/keys` 注册本机公钥，然后
`python3 scripts/public_tunnel.py --engine serveo --identity ~/.ssh/serveo_key --subdomain <名字>`。

## 场景脚本怎么写

场景是普通 Luau，运行在 mock 运行时内，可直接调用库的公开 API：

```lua
local ok, Library = pcall(loadstring, game:HttpGet("URL"))  -- 走真实加载路径
local win = Library:CreateWindow({ Title = "X", Info = "...", Icon = "skull" })
check("CreateWindow 成功", type(win) == "table")
win:Add()
pump(1.0)                       -- 推进虚拟时钟，让补间/入场动画执行
local tab = win:AddTab({ Title = "主页" })
tab:AddToggle({ Title = "自动", Default = true })
Snapshot("初始状态")             -- 拍一张结构树+ASCII+色彩网格
-- 交互
local root = guiRoot()
local tg = findByText(root, "自动")
fireUI(tg, "MouseButton1Click") -- 触发点击事件
pump(0.5)
check("切换生效", tg:GetValue() == false)
__HARNESS.summary()              -- 打印断言汇总并退出
```

关键全局（详见 `references/vision-api.md`）：
`check / checkEqual / checkNear / pump / tapUI / fireUI / Snapshot / guiRoot /
findByName / findByText / findByClass / countInstances / dumpWarnings / vclockNow /
__HARNESS.summary`。

## 核心心智模型

> mock 是**静态布局引擎 + 虚拟时钟**：它按 Roblox 规则把 `Size/Position` 的
> `Scale+Offset` 折算成绝对矩形，再光栅化为三类视图。补间 `Play()` 会**立即应用
> 目标属性**，但 `Completed` 事件**延迟到补间时长之后触发**（与真实 Roblox 一致），
> 这样「先 `Play()` 再 `Completed:Connect()`」的惯用法也能正确推进。

因此：场景里想让动画走完，用 `pump(秒数)`（按 1/60 逐帧让出，让
`RenderStepped`/`Heartbeat` 每帧触发）；不要假设某帧后属性才变化——属性在 `Play()`
那一刻就已落定，变的是「完成回调」何时触发。

## 验证清单（交付前必跑）

1. `examples/demo_scenario.lua` → 期望 **13/13 通过、0 错误、0 警告**
2. `examples/smoke_dynamiccow.lua`（需真实库文件）→ 期望 **19/19 通过、0 错误**
3. `run_ui_luau.py --scenario examples/simple_scenario.lua`（真实 luau 路径）
   → 期望 **13/13 通过、0 错误**，且生成的 PNG 与 `run_ui.py` 渲染结果一致
4. `examples/rich_scenario.lua` → **16/16 通过、0 错误**（luau 与 lupa 均需过）
5. `examples/delta_scenario.lua`（真实大型库 DeltaUI）→ **12/12 通过、0 错误**
   （luau 与 lupa 均需过；两条路径元素数应一致）

任何改动 `mock_runtime.lua` / `vision.lua` 后，先重跑这几条；新增断言不得让
既有场景失败。注意：两个运行时**共用同一套模块源码**，改动须同时兼容 lupa 与
真实 luau（避免 `_G.*` 写入、避免同名局部导出如 `Enum = Enum`）。

> 真实库（如 DeltaUI）常会逼出 mock 的保真缺口——例如全局 `unpack`、`TextBounds`、
> `Stats.PerformanceStats`、未模拟 service 的字段类型等。已按真机语义补齐（见
> `references/mock-runtime.md`）。

## 已知边界（重要）

- 这是**无头静态**运行时：不模拟像素级渲染、不模拟真实字体度量（用按字体的
  em 系数近似）、不模拟鼠标悬停态。
- 真实库的**多阶段入场状态机**（如分裂球 loader → 品牌字渐绿 → 展开面板 →
  `buildTabUI`）在静态 mock 下通常推进到「标题 handoff」阶段即停，因为最终展开
  依赖真实渲染循环的属性变更事件（`GetPropertyChangedSignal` / `AbsoluteSize`
  更新）。这不影响「加载 / CreateWindow / 全控件工厂 / 补间 / 调度 / HttpGet」等
  核心能力的验证。
- **两条执行路径的语法差异**（见 `references/luau-compat.md`）：
  - `run_ui.py`（lupa/Lua 5.5）：仅支持 Luau 的**安全子集**——`table.freeze`、
    `math.round`、`string.split` 等内建已补；`continue`、`+=`、类型注解等不支持。
  - `run_ui_luau.py`（真实 luau）：**原生 Luau 全语法**（`+=`/`continue`/类型注解/
    字符串插值），无需兼容层。两条路径产出的画布**逐字节一致**（已验证 md5 相同）。
- `references/luau-compat.md` 记录的兼容层仅对 `run_ui.py` 有意义；真实 luau 路径下
  标准库表（`table`/`math`/`string`/`coroutine`）为只读，模块内不再写入这些表。

## 引用

- 完整 API：`references/vision-api.md`
- UI 坑清单（审计用）：`references/ui-pitfalls.md`
- 兼容层说明：`references/luau-compat.md`
- 运行时能力边界：`references/mock-runtime.md`
