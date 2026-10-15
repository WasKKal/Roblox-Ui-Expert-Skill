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
│   ├── run_ui_luau.py        # CLI（真实 Luau 解释器路径）：跑 Luau 引擎并渲染真实 PNG
│   └── render_png.py         # 把色彩网格渲染成高清 PNG（真实像素图）
├── examples/
│   ├── demo_ui.lua           # 自包含演示 UI（淡入 / Tab / 各类控件 / 提示）
│   ├── demo_scenario.lua     # 演示场景：13 条断言 + 3 张快照
│   ├── simple_ui.lua         # 简易 UI 库（标题栏+按钮+开关+滑条+进度+提示）
│   ├── simple_scenario.lua   # 简易场景：13 条断言，用于 luau PNG 渲染验证
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
`--no-glyphs`（只出纯色块，更接近真实 UI）、`--luau PATH`（指定解释器）。

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

任何改动 `mock_runtime.lua` / `vision.lua` 后，先重跑这三条；新增断言不得让
既有场景失败。注意：两个运行时**共用同一套模块源码**，改动须同时兼容 lupa 与
真实 luau（避免 `_G.*` 写入、避免同名局部导出如 `Enum = Enum`）。

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
