# RobloxUiExpert — 让 Agent / 开发者「看见」Roblox UI

一套**无头 Roblox UI 运行时 + 视觉渲染器**。用 Luau 代码构建 UI，不需要 Roblox Studio
就能拿到：结构树 / ASCII 线框 / 矢量 PNG / 可交互 HTML / 动画（APNG）。

```
Luau 代码  ──►  mock_runtime.lua（Instance 树 · 虚拟时钟 · 补间插值 · task 调度）
                  │
                  ├─ vision.lua   布局引擎：Scale+Offset → 绝对矩形；产出结构树 + 绘制列表
                  │
                  └─ harness.lua  场景驱动：check / pump / tapUI / Snapshot / StartCapture
                          │
        ┌─────────────────┼──────────────────┬───────────────────┐
        ▼                 ▼                  ▼                   ▼
   文本报告          矢量 PNG           可交互 HTML          APNG 动画
  (run_ui.py)     (render_hires.py)   (render_html.py)   (render_hires.py)
```

## 快速开始

```bash
# 0) 依赖：pip3 install pillow lupa flask cairosvg fonttools
#    真实 Luau 路径需要 luau 可执行文件（源码编译）：
#    git clone --depth 1 https://github.com/luau-lang/luau && cd luau
#    cmake -B build && make -C build Luau.Repl.CLI && cp build/luau /usr/local/bin/

# 1) 文本报告 + 断言（lupa 路径，最快，无外部依赖）
python3 scripts/run_ui.py \
  --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
  --scenario examples/rich_scenario.lua

# 2) 清晰 PNG + 可交互 HTML（真实 Luau 解释器执行）
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
  --scenario examples/rich_scenario.lua \
  --out /workspace/rich.png --style both --scale 2

# 3) 动画：每 0.1 虚拟秒采一帧 → APNG + HTML 时间轴播放器
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/anim_ui.lua=examples/anim_ui.lua" \
  --scenario examples/anim_scenario.lua \
  --out /workspace/anim.png --style both --capture 0.1 --anim

# 4) 本地预览服务：上传任意 .lua 就渲染，可在画布上点击交互
python3 scripts/preview_server.py --port 8765
#    打开 http://127.0.0.1:8765/ ，或 ?demo=simple|rich|anim|delta 直达内置示例
```

## 目录结构

```
Roblox-Ui-Expert-Skill/
├── SKILL.md / README.md / LICENSE
├── scripts/
│   ├── mock_runtime.lua    # 无头运行时（Instance/Enum/Signal/Tween/task/输入/执行器 FS）
│   ├── vision.lua          # 布局引擎 + 结构树/ASCII + 绘制列表
│   ├── harness.lua         # 场景驱动 + 断言 + 动画帧捕获
│   ├── icons.py            # 图标资源（lucide SVG / 光栅化 / 位图）
│   ├── run_ui.py           # CLI：文本报告（lupa / Lua 5.5）
│   ├── run_ui_luau.py      # CLI：PNG / HTML / APNG / JSON（真实 luau）
│   ├── render_hires.py     # 矢量 PNG + APNG 渲染
│   ├── render_html.py      # DOM+CSS → 自包含可交互 HTML
│   └── preview_server.py   # 本地预览服务（上传 + 交互点击）
├── assets/fonts/           # Roblox 同源字体（Source Sans 3、Inter）
├── assets/icons/           # lucide 图标 SVG 缓存（约 150 个）
├── examples/               # simple / rich / anim / delta 场景与示例 UI
└── references/             # vision-api · ui-pitfalls · runtime-notes
```

## 工作原理

- **mock 运行时**：手写 Roblox 环境子集——`Instance` 树与属性继承、`UDim2`/`Color3`/
  `ColorSequence` 等值类型、`Enum`、`Signal`、`TweenService`、`task` 调度、
  `RunService` 帧事件、输入事件，以及执行器 FS API（`HttpGet` / `loadstring` /
  `getcustomasset` / `request`）。
- **虚拟时钟**：时间由 `pump(秒)` 推进，按 1/60 逐帧步进并触发 `RenderStepped` /
  `Heartbeat`。**补间按时间真实插值**（`EasingStyle` × `EasingDirection`、`DelayTime`），
  `Completed` 在时长后的下一帧触发。
- **布局引擎**：按 Roblox 规则折算 `Scale+Offset` / `AnchorPoint` / `UIListLayout` /
  `AutomaticSize` / `UIPadding` / `ClipsDescendants`，产出每个 GuiObject 的绝对矩形、
  生效裁剪、组透明度与层级（DFS + 同层 `ZIndex` 稳定排序）。
- **两个执行路径**：`lupa`（Lua 5.5，进程内，快）与**真实 luau 解释器**（源码编译，
  原生 Luau 语法）。两者共用同一套 Lua 源码，结果一致。

## 渲染能力一览

| 能力 | 说明 |
|------|------|
| 圆角 / 描边 / 边框 | `UICorner`（Scale+Offset）、`UIStroke`（含 `ApplyStrokeMode`）、`BorderSizePixel` |
| 渐变 | `UIGradient`（旋转 + 关键点），以及 `Transparency` 序列 → 沿轴渐隐 |
| 文本 | 字号 / 字体（同源 Source Sans 3、Inter + CJK 回退）/ 对齐 / 换行 / `TextScaled` / 文字描边 |
| 图标 | `ImageLabel.Image` → lucide 矢量图标（着色、透明度）；http/本地图片解码；未知资源占位 |
| 变换 | `Rotation` 旋转、`CanvasGroup` 组透明度、`ClipsDescendants` 裁剪 |
| 交互 | `hitTest` 命中测试 + `tapUI` 派发点击 → 重放重渲染（预览页可直接点画布） |
| 动画 | 逐帧采样 → APNG（Alpha 保真）+ HTML 时间轴播放器 |

## 验证清单

| 场景 | 期望 |
|------|------|
| `examples/simple_scenario.lua` | 13/13、0 错误（luau + lupa） |
| `examples/rich_scenario.lua` | 16/16、0 错误（luau + lupa） |
| `examples/anim_scenario.lua` | 11/11、0 错误（luau + lupa） |
| `examples/delta_scenario.lua`（真实库 DeltaUI） | 12/12、0 错误（luau + lupa） |

## 许可

MIT License，见 [LICENSE](LICENSE)。
