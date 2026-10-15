---
name: RobloxUiExpert
description: >
  Roblox / Luau UI 开发专家。让 Agent 通过 Luau 代码在「无头 mock 运行时」中
  构建并「看见」UI 画面（结构树 + ASCII 线框 + 矢量 PNG + 可交互 HTML + 动画帧），
  无需 Roblox Studio 即可开发、调试、审计 UI 库（如 DynamicCowUI / DeltaUI 风格的
  设置面板 / 灵动岛 / 控件库）。当用户提到 Roblox UI、Luau、Instance 树、UICorner、
  UIStroke、UIListLayout、CanvasGroup、ScrollingFrame、TweenService、或要求
  「用代码画出 UI / 渲染 UI / mock 一个 Roblox 界面 / 审查布局 bug / 让 Agent 看到 UI」
  时使用本 Skill。
---

# RobloxUiExpert —— 让 Agent「看见」Roblox UI 的无头开发环境

把对真实 Roblox UI 库（数千~数万行）的审计、mock 测试、布局修复经验，沉淀为一个
**可直接运行的无头运行时 + 视觉渲染器**。写 Luau 代码构建 UI，运行时给出四类「视图」：

| 视图 | 形态 | 用途 |
|------|------|------|
| **结构树** | 文本 | 每个 GuiObject 的绝对位置/尺寸/圆角/描边/文本/透明度 |
| **ASCII 线框** | 终端 | 快速看 UI 轮廓，边框避让文字 |
| **矢量渲染** | PNG | 圆角/渐变/描边/旋转/图标/真实字体，任意倍率超采样 |
| **可交互 HTML** | 网页 | DOM+CSS 还原，悬停探查元素、点击触发真实事件回路 |
| **动画** | APNG / HTML 时间轴 | 按虚拟时钟逐帧采样，回放补间与循环动效 |

## 何时用

- 开发或改写一个 Roblox UI 库（窗口框架、灵动岛、Tab、各类控件）
- 不依赖 Roblox Studio，仅用 Luau 代码验证布局是否正确
- 审计 ZIndex 层级、遮挡关系、补间动画、文本溢出、圆角擦除等问题
- 复现并定位「界面元素错位 / 重叠 / 不显示 / 闪烁 / 所有页面同时显示」类 bug
- 为真实库（DynamicCowUI / DeltaUI 等）编写回归冒烟场景
- 渲染出 UI 截图（PNG / HTML）给人看，或做成动图

## 目录结构

```
Roblox-Ui-Expert-Skill/
├── SKILL.md                  # 本文件
├── README.md                 # 快速上手 + 原理
├── LICENSE                   # MIT
├── scripts/
│   ├── mock_runtime.lua      # 无头运行时：Instance 树 / 值类型 / Enum / Signal /
│   │                         #   TweenService（按虚拟时钟真实插值）/ task 调度 / 输入 /
│   │                         #   执行器 FS（HttpGet/loadstring/getcustomasset/request）
│   ├── vision.lua            # 布局引擎 + 渲染器：算绝对矩形、结构树/ASCII、绘制列表
│   ├── harness.lua           # 场景驱动：check/pump/tapUI/fireUI/Snapshot/StartCapture
│   ├── icons.py              # 图标资源：lucide SVG 解析 / 光栅化 / 位图缓存
│   ├── run_ui.py             # CLI（lupa/Lua 5.5 路径）：文本报告 + 断言
│   ├── run_ui_luau.py        # CLI（真实 Luau 解释器路径）：PNG / HTML / APNG / JSON
│   ├── render_hires.py       # 矢量 PNG 渲染（含图标）与 APNG 合成
│   ├── render_html.py        # DOM+CSS → 自包含可交互 HTML（含动画时间轴）
│   └── preview_server.py     # 本地预览服务：上传 .lua → 真实引擎渲染 → 网页交互
├── assets/
│   ├── fonts/                # Roblox 同源字体（Source Sans 3 ≈ SourceSans、Inter ≈ Gotham）
│   └── icons/                # lucide 图标 SVG 缓存（约 150 个常用图标；缺失可按需下载）
├── examples/
│   ├── simple_ui.lua         # 简易 UI（标题栏+按钮+开关+滑条+进度+提示）
│   ├── simple_scenario.lua   # 简易场景（13 条断言）
│   ├── rich_ui.lua           # 富特性 UI（渐变/渐隐/描边/旋转/图标/组透明/裁剪）
│   ├── rich_scenario.lua     # 富特性场景（16 条断言）
│   ├── anim_ui.lua           # 动效 UI（补间入场 + 错开延迟 + 心跳脉冲 + 扫描条 + 图标）
│   ├── anim_scenario.lua     # 动效场景（11 条断言）
│   ├── delta_scenario.lua    # 真实大型库 DeltaUI 渲染自检（12 条断言）
│   └── lucide_stub.lua       # lucide 图标模块离线桩（让真实库离线可跑）
└── references/
    ├── vision-api.md         # vision.lua + harness 全部 API
    ├── ui-pitfalls.md        # ≈25 条 Roblox UI 常见坑（审计清单）
    └── runtime-notes.md      # mock 覆盖范围 · lupa 与真实 Luau 两条路径的兼容性
```

## 30 秒上手

**① 文本报告（最快，lupa 路径，无外部依赖）：**

```bash
python3 scripts/run_ui.py \
  --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
  --scenario examples/rich_scenario.lua
# 产出：结构树 + ASCII 线框 + 16/16 断言
```

**② 出图（真实 Luau 解释器执行 + 矢量渲染）：**

```bash
# 真实 luau 可执行文件：从 github.com/luau-lang/luau 源码编译
#   cmake -B build && make -C build Luau.Repl.CLI && cp build/luau /usr/local/bin/
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
  --scenario examples/rich_scenario.lua \
  --out /workspace/rich.png --style both --scale 2
# 产出：1600x1200 清晰 PNG（含图标）+ 可交互 HTML + 16/16 断言
```

**③ 出动画（逐帧采样 → APNG + HTML 时间轴）：**

```bash
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/anim_ui.lua=examples/anim_ui.lua" \
  --scenario examples/anim_scenario.lua \
  --out /workspace/anim.png --style both --capture 0.1 --anim
# 产出：静图 + 35 帧 APNG + 带播放器（▶ / 进度条 / 逐帧）的 HTML
```

**④ 本地预览服务（上传任意 .lua 就渲染，可点击交互）：**

```bash
python3 scripts/preview_server.py --port 8765
# 浏览器打开 http://127.0.0.1:8765/ ；?demo=simple|rich|anim|delta 直达内置示例
```

### 两条执行路径

| | `run_ui.py`（lupa） | `run_ui_luau.py`（真实 luau） |
|---|---|---|
| 执行引擎 | lupa 的 Lua 5.5 + 手写兼容层 | 官方 luau 解释器（源码编译） |
| 语法 | Lua 5.x 安全子集（无 `+=`/`continue`/类型注解） | **原生 Luau 全语法** |
| 输出 | 结构树 + ASCII（文本） | 同上 + **PNG / APNG / HTML / JSON** |
| 用途 | 快速回归、CI 断言 | 出图、交互、动画 |

两者跑同一场景结果一致（早期实测：两条路径导出图像逐字节相同）。书写时按
`references/runtime-notes.md` B 节的语法子集约束即可双跑。

### 参数速查

`run_ui.py`：

| 参数 | 含义 |
|------|------|
| `--lib "URL=PATH"` | 注册「URL→本地内容」映射，库里 `game:HttpGet(URL)` 回源到该内容；可多次 |
| `--scenario FILE` | 场景脚本（协程驱动，可用 `pump`/`Snapshot`/`check` 等全局） |
| `--viewport 800x600` | 视口尺寸 |
| `--cell 8x16` | ASCII 每格像素尺寸 |
| `--max-seconds 300` | 场景最大虚拟时长 |
| `--pump-after 1` | 场景结束后补拍的秒数 |
| `--output FILE` | 报告落盘 |

`run_ui_luau.py` 额外参数：

| 参数 | 含义 |
|------|------|
| `--out FILE` | 输出路径（PNG 或 HTML，按 `--style`） |
| `--style S` | `hires`（默认）/ `html` / `both` / `none`（只出报告，最快） |
| `--scale N` | 输出放大倍数（视口 ×N，默认 2） |
| `--ss N` | 超采样倍数（默认 3；画布像素超预算时自动降级） |
| `--capture SEC` | 动画：按该虚拟秒间隔采样帧（如 `0.1`） |
| `--max-frames N` | 动画帧上限（默认 120） |
| `--anim` | 额外导出 APNG（配合 `--capture`） |
| `--fps N` | APNG 播放帧率（0 = 按采样间隔） |
| `--click X,Y` | 场景后在该点命中并派发点击（可多次） |
| `--bg #RRGGBB` | 画布底色 |
| `--no-glyphs` | 不绘文字（只看几何与图标） |
| `--offline` | 不联网获取图标资源（只用本地 `assets/icons`） |
| `--dump-json FILE` | 落盘引擎报告（含结构树，可用 `render_hires.py` 离线重渲染） |

## 渲染能力

### 矢量 PNG（`--style hires`）

消费引擎输出的「每个 GuiObject 的精确矩形 + 完整样式」，用 PIL 以**超采样**绘制：

- 圆角（UICorner，含 Scale+Offset 折算）、UIStroke 描边、BorderSizePixel
- UIGradient 线性渐变（含 `Transparency` 序列 → 沿轴渐隐）
- **Rotation 旋转**、CanvasGroup 组透明度、ClipsDescendants / ScrollingFrame 裁剪
- **文本**：`TextSize` / 字体（Roblox 同源 Source Sans 3、Inter）/ 对齐 / 自动换行 /
  `TextScaled` 二分求最大字号 / `TextStroke`（文字描边）/ `TextTruncate`
- **图标**：`ImageLabel.Image` 解析为 lucide 矢量图标（本地 SVG 缓存 → `cairosvg`
  光栅化 → 按 `ImageColor3` 着色、`ImageTransparency` 调透明度）；http/本地图片按
  位图解码；`rbxassetid://` 等无法获取的资源回退占位块

### 可交互 HTML（`--style html`）

把每个 GuiObject 映射成绝对定位 `<div>`，用 CSS 还原（`border-radius` /
`linear-gradient` / `box-shadow` 描边 / `clip-path: inset()` 裁剪 / flex 文本对齐 /
`rotate()`）——**天然矢量、无限清晰**，且**图标以内联 SVG 呈现**。内置：

- 悬停高亮 + 提示 类名/名字/矩形/ZIndex/绘制序
- 工具栏：缩放（含**自适应**，保证整个视口可见可点）、边界框、绘制序、隐藏文字、浅色底
- 多帧时自动出现**播放器**：▶ 播放/暂停、进度条拖动、帧号
- 自包含单文件（内嵌 JSON / CSS / 字体 / 图标），可直接分享

### 动画

引擎的 `TweenService` **按虚拟时钟真实插值**（`EasingStyle` × `EasingDirection`、
`DelayTime`、`Cancel`），配合每帧钩子按间隔采样 `draws`：

```bash
--capture 0.1 --anim        # 每 0.1 虚拟秒采一帧，导出 APNG
```

APNG 用 Alpha 保真（不是 256 色 GIF），浏览器/看图器可直接播放；HTML 侧则内嵌全部
帧并提供时间轴，可播放/暂停/逐帧拖动。

## 场景脚本怎么写

场景是普通 Luau，运行在 mock 运行时内，可直接调用库的公开 API：

```lua
local Anim = loadstring(game:HttpGet("https://mock.local/anim_ui.lua"))()
local gui = Anim.build({})
pump(2.4)                        -- 推进虚拟时钟：补间逐帧插值、Heartbeat 逐帧回调
Snapshot("结束态")                -- 结构树 + ASCII 快照
check("卡片存在", findByName("Card") ~= nil)
local root = guiRoot()
local btn = findByText(root, "执行脚本")
pump(0.4); tapUI(btn)            -- 命中并派发点击
__HARNESS.summary()              -- 断言汇总
```

关键全局（详见 `references/vision-api.md`）：
`check / checkEqual / checkNear / pump / tapUI / fireUI / hitTest / Snapshot /
StartCapture / StopCapture / guiRoot / findByName / findByText / findByClass /
countInstances / dumpWarnings / vclockNow / __HARNESS.summary`。

## 核心心智模型

> mock 是**布局引擎 + 虚拟时钟**。它按 Roblox 规则把 `Size/Position` 的 `Scale+Offset`
> 折算成绝对矩形，并维护一个可逐帧推进的虚拟时钟：`TweenService` 的补间**按时间插值**
> （每帧写回中间值），`Completed` 在时长到达后的**下一帧**触发（与真机一致，因此
> 「先 `Play()` 再 `Completed:Connect()`」的惯用法能正确推进）。

因此：场景里用 `pump(秒数)` 推进时间即可——动画会逐帧演化（因此才能被 `--capture`
采到中间帧）；`Heartbeat` / `RenderStepped` 连接的回调也每帧触发。`pump` 在协程内
逐帧让出，在主线程直调时同步推进。

## 验证清单（交付前必跑）

| 场景 | 期望 |
|------|------|
| `examples/simple_scenario.lua` | **13/13**、0 错误（luau + lupa） |
| `examples/rich_scenario.lua` | **16/16**、0 错误（luau + lupa） |
| `examples/anim_scenario.lua` | **11/11**、0 错误（luau + lupa） |
| `examples/delta_scenario.lua`（真实大型库 DeltaUI） | **12/12**、0 错误（luau + lupa） |

任何改动 `mock_runtime.lua` / `vision.lua` 后先重跑这几条；新增断言不得让既有场景失败。
两个运行时**共用同一套模块源码**，改动须同时兼容 lupa 与真实 luau（避免 `_G.*` 写入、
避免同名局部导出如 `Enum = Enum`）。

> 真实库（DeltaUI 等）常会逼出 mock 的保真缺口——例如全局 `unpack`、`TextBounds`、
> `Stats.PerformanceStats`、未模拟 service 的字段类型、`AutomaticSize`、`Name` 默认值等。
> 已按真机语义补齐，清单见 `references/runtime-notes.md`。

## 性能

- 引擎本身很快：`--style none` 跑 DeltaUI（475KB 库、357 元素）约 **0.3s**。
- 出图的主要成本是**超采样**：`--ss 3` + `--scale 2` 会按 6 倍绘制再降采样；渲染器
  有画布像素预算（2400 万），超出时自动降低 `ss` 并提示（输出尺寸不变）。
- 预览服务的交互点击（重放 + 重渲染）实测 **0.3s 左右**：报告不再携带已废弃的
  「色彩网格」负载，直连 stdout 取 JSON（不落盘、不带结构树），图标走本地缓存。

## 已知边界

- **无头静态**运行时：不模拟像素级 rasterization、不模拟真实字形度量（按字体的 em
  系数近似）、不模拟鼠标悬停态与输入法。
- 真实库的**多阶段入场状态机**（分裂球 loader → 品牌字渐绿 → 展开面板 → `buildTabUI`）
  在静态 mock 下通常推进到「标题 handoff」阶段即停，因为最终展开依赖真实渲染循环的
  属性变更事件（`GetPropertyChangedSignal` / `AbsoluteSize` 更新）。这不影响
  「加载 / CreateWindow / 全控件工厂 / 补间 / 调度 / HttpGet / 交互」等核心能力的验证。
- **图标资源**：Roblox 官方 `rbxassetid://` 资源无鉴权无法获取（渲染为占位块）；
  lucide 类图标（可判定图标名）会被还原为矢量图标。离线环境用 `--offline` 只走本地
  `assets/icons` 缓存。
- 语法差异：真实 luau 路径支持全语法，lupa 路径仅支持安全子集（见
  `references/runtime-notes.md`）。

## 引用

- 完整 API：`references/vision-api.md`
- UI 坑清单（审计用）：`references/ui-pitfalls.md`
- 运行时说明（mock 覆盖范围 + 两条路径兼容性）：`references/runtime-notes.md`

## 许可

MIT License（见 `LICENSE`）。
