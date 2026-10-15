# RobloxUiExpert —— 让 Agent「看见」Roblox UI 的无头开发环境

把对真实 Roblox UI 库（7000+ 行 DynamicCowUI 风格）的审计、mock 测试与布局修复经验，
沉淀为一个**可直接运行的无头运行时 + 视觉渲染器**。Agent 用 Luau 代码构建 UI，运行时给出
三类「视图」，让你像看截图一样理解画面，而**无需 Roblox Studio**。

- **结构树** —— 每个 GuiObject 的绝对位置 / 尺寸 / 圆角 / 描边 / 文本 / 透明度
- **ASCII 线框** —— 终端里画出 UI 轮廓，边框避让文字
- **色彩网格** —— 量化后的颜色图例，验证渐变 / 主题色

## 快速上手

```bash
# 1) 自带演示 UI（13 条断言 + 3 张快照，期望全过）
python3 scripts/run_ui.py \
  --lib "https://mock.local/demo_ui.lua=examples/demo_ui.lua" \
  --scenario examples/demo_scenario.lua --output /tmp/demo.txt

# 2) 真实库冒烟（验证运行时承载力，19 条断言全过）
python3 scripts/run_ui.py \
  --lib "URL_A=/path/DynamicCowUI.lua" \
  --lib "URL_B=/path/lucide_init_v6.lua" \
  --scenario examples/smoke_dynamiccow.lua

# 3) 用【真实 Luau 解释器】执行并渲染出 PNG（原生 Luau 语法，13/13 全过）
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
  --scenario examples/simple_scenario.lua \
  --out /workspace/ui_render_luau.png

# 4) 要「清晰」的图：矢量高清渲染（1600x1200，可读中文）
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
  --scenario examples/simple_scenario.lua \
  --out /workspace/ui_clear.png --style hires --scale 2 --ss 3

# 5) 要「可交互」的版本：自包含 HTML（浏览器打开，悬停探查/缩放/边界框）
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
  --scenario examples/rich_scenario.lua \
  --out /workspace/rich.html --style html

# 6) 在线预览：上传任意 .lua 就渲染（浏览器交互；点击画布可触发真实事件）
python3 scripts/preview_server.py --port 8765
# 打开 http://127.0.0.1:8765/ ；或 ?demo=simple|rich|delta 直接看内置示例
# 点击画布 = hitTest 命中测试 + tapUI 派发点击 + 重放重渲染；"重置交互"清空点击序列

# CLI 侧等价的交互：在场景之后按坐标点击（可多次）
python3 scripts/run_ui_luau.py --lib "..." --scenario s.lua --out o.png --click 25,465 --click 1240,775
```

**用真实大型库验证（DeltaUI，475KB）：**

```bash
# lupa（Lua 5.5）
python3 scripts/run_ui.py \
  --lib "https://mock.local/DeltaUI.lua=/root/uploads/1791642772656330982-DeltaUI.lua.txt" \
  --lib "https://cdn.jsdelivr.net/gh/WasKKal/DeltaExecutor-UI-Rebuild@latest/lucide/init.lua=examples/lucide_stub.lua" \
  --lib "https://raw.githubusercontent.com/WasKKal/DeltaExecutor-UI-Rebuild/master/lucide/init.lua=examples/lucide_stub.lua" \
  --scenario examples/delta_scenario.lua --viewport 1280x800
# 真实 luau：把 run_ui.py 换成 run_ui_luau.py 并加 --style both --out /workspace/delta.png
# 两条路径均 12/12、0 错误；元素数一致（357）
```

## 它是怎么工作的

```
Luau 库/场景  ──►  mock_runtime.lua（Instance 树 + 虚拟时钟 + 执行器 FS）
                    │
                    ▼
                vision.lua（布局引擎：Scale/Offset→绝对矩形；UICorner/UIStroke/CanvasGroup 处理）
                    │
                    ▼
        run_ui.py（CLI：加载库 + 驱动场景 + 产出结构树/ASCII/色彩网格 + 断言报告）
                    │
                    ▼
   run_ui_luau.py（真实 luau 解释器执行同一套模块 → 渲染真实 PNG 像素图）
```

核心心智模型：**mock 是静态布局引擎 + 虚拟时钟**。补间 `Play()` 立即应用目标属性，但
`Completed` 延迟到补间时长后触发（与真实 Roblox 一致），所以「先 `Play()` 再
`Completed:Connect()`」的惯用法也能正确推进。`pump(seconds)` 按 1/60 逐帧让出虚拟时钟，
让 `RenderStepped`/`Heartbeat` 每帧触发，从而驱动入场动画。

## 目录结构

```
Roblox-Ui-Expert-Skill/
├── SKILL.md                  # Skill 主入口（触发关键词 + 用法）
├── README.md                 # 本文件
├── scripts/
│   ├── mock_runtime.lua      # 无头运行时
│   ├── vision.lua            # 布局引擎 + 渲染器
│   ├── harness.lua           # 场景驱动 + 断言设施
│   ├── run_ui.py             # CLI（lupa/Lua 5.5）
│   ├── run_ui_luau.py        # CLI（真实 Luau 解释器，渲染 PNG/HTML）
│   ├── render_png.py         # 色彩网格 → PNG（逐格放大，粗）
│   ├── render_hires.py       # 矢量高清渲染（圆角/渐变/描边/旋转/真实字体）
│   ├── render_html.py        # DOM+CSS → 自包含可交互 HTML
│   └── preview_server.py     # 在线预览：上传 .lua → 真实引擎渲染 → 网页交互
├── examples/
│   ├── demo_ui.lua           # 自包含演示 UI
│   ├── demo_scenario.lua     # 演示场景（13 断言）
│   ├── simple_ui.lua         # 简易 UI 库
│   ├── simple_scenario.lua   # 简易场景（luau 渲染验证）
│   ├── rich_ui.lua           # 富特性 UI（渐变/渐隐/描边/旋转/组透明/裁剪）
│   ├── rich_scenario.lua     # 富特性场景（16 断言）
│   ├── delta_scenario.lua    # 真实大型库 DeltaUI 渲染自检（12 断言）
│   └── smoke_dynamiccow.lua  # 真实库冒烟（19 断言）
└── references/
    ├── vision-api.md         # 完整 API 参考
    ├── ui-pitfalls.md        # ≈25 条 Roblox UI 常见坑（审计清单）
    ├── luau-compat.md        # Luau → Lua 5.5 兼容说明
    └── mock-runtime.md       # 运行时能力边界
```

## 写场景脚本

场景是普通 Luau，运行在 mock 内，可直接调用库公开 API：

```lua
local ok, Library = pcall(loadstring, game:HttpGet("URL"))
local win = Library:CreateWindow({ Title = "X", Info = "Y", Icon = "skull" })
check("CreateWindow 成功", type(win) == "table")

win:Add()
pump(1.0)                                  -- 推进虚拟时钟，让入场动画执行
local tab = win:AddTab({ Title = "主页" })
tab:AddToggle({ Title = "自动", Default = true })
Snapshot("初始状态")

local node = findByText("自动")
fireUI(node, "MouseButton1Click")          -- 触发点击事件
pump(0.5)
check("切换生效", node:GetValue() == false)
__HARNESS.summary()                         -- 必须：打印断言汇总
```

更多 API 见 [`references/vision-api.md`](references/vision-api.md)。

## 验证清单（改动后必跑）

| 场景 | 期望 |
|------|------|
| `examples/demo_scenario.lua` | 13/13 通过、0 错误、0 警告 |
| `examples/smoke_dynamiccow.lua` | 19/19 通过、0 错误 |
| `examples/simple_scenario.lua`（`run_ui_luau.py`） | 13/13 通过、0 错误，PNG 与 lupa 路径一致 |
| `examples/rich_scenario.lua`（`run_ui_luau.py --style both`） | 16/16 通过、0 错误，产出 PNG + HTML |
| `examples/delta_scenario.lua`（真实库 DeltaUI，luau + lupa） | 12/12 通过、0 错误，元素数一致（357） |

任何改动 `mock_runtime.lua` / `vision.lua` 后先重跑这几条；新增断言不得让既有场景失败。
两个运行时共用同一套模块源码，改动须同时兼容（避免 `_G.*` 写入、避免同名局部导出）。

## 已知边界

- 无头静态运行时：不模拟像素级渲染、不模拟真实字体度量、不模拟 hover 态。
- 真实库的多阶段入场状态机（分裂球→展开面板→`buildTabUI`）在静态 mock 下通常推进到
  「标题 handoff」阶段即停（依赖真实渲染循环的属性变更事件），不影响核心能力验证。
- 语法子集：`run_ui.py`（lupa）仅接受 Luau 的 Lua-5 兼容子集；`run_ui_luau.py`
  （真实 luau 解释器）**原生支持全 Luau 语法**（见 `references/luau-compat.md`）。

## 适用场景

- 开发 / 改写 Roblox UI 库（窗口框架、灵动岛、Tab、各类控件）
- 不依赖 Studio 验证布局正确性
- 审计 ZIndex 层级、遮挡、补间并发、文本溢出、圆角擦除等
- 复现并定位「元素错位 / 重叠 / 不显示 / 闪烁」类 bug
- 为真实库编写回归冒烟场景
