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
│   └── run_ui.py             # CLI
├── examples/
│   ├── demo_ui.lua           # 自包含演示 UI
│   ├── demo_scenario.lua     # 演示场景（13 断言）
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

任何改动 `mock_runtime.lua` / `vision.lua` 后先重跑这两条；新增断言不得让既有场景失败。

## 已知边界

- 无头静态运行时：不模拟像素级渲染、不模拟真实字体度量、不模拟 hover 态。
- 真实库的多阶段入场状态机（分裂球→展开面板→`buildTabUI`）在静态 mock 下通常推进到
  「标题 handoff」阶段即停（依赖真实渲染循环的属性变更事件），不影响核心能力验证。
- 仅接受 Luau 的 Lua-5 兼容子集（见 `references/luau-compat.md`）。

## 适用场景

- 开发 / 改写 Roblox UI 库（窗口框架、灵动岛、Tab、各类控件）
- 不依赖 Studio 验证布局正确性
- 审计 ZIndex 层级、遮挡、补间并发、文本溢出、圆角擦除等
- 复现并定位「元素错位 / 重叠 / 不显示 / 闪烁」类 bug
- 为真实库编写回归冒烟场景
