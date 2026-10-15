# Vision API 参考（vision.lua + harness.lua）

`vision.lua` 是布局引擎 + 渲染器，把 mock 里的 Instance 树折算成绝对矩形并产出三类视图；
`harness.lua` 提供场景驱动与断言设施。两者在 `run_ui.py` 装配后，以下名字都成为
Lua 全局，场景脚本可直接调用。

---

## 一、三类视图（Snapshot 产出）

`Snapshot(label)` 会向报告输出三块内容：

1. **结构树（■）** —— 每个 GuiObject 一行，含：
   - `ClassName "Name" Z=ZIndex (x,y) WxH`
   - 修饰：`[圆角r=N]` `[描边#RRGGBB t=N a=A]` `[bg=#RRGGBB(a=A)]`
     `[文本="..." Npx #RRGGBB 对齐]` `[组透明 a=A]` `[列表布局 ...]` `[图像=...]`
   - 布局告警：文本溢出（字号×字宽 > 框宽）、负尺寸等
2. **ASCII 线框（■）** —— 终端线框图，图例：
   `░`不透明 `▒`半透 `·`高透 `#`描边 `+`边框 `|/=`边 `-`上下边 `▓`图像
   边框/描边环**避让文字**（后绘环机制，不会盖住字形）。
3. **色彩网格（■）** —— 量化到 4bit/通道的颜色字母图例 + 图例表。

---

## 二、harness 全局 API

### 断言

```lua
check(label, cond, detail)        -- cond 为真则 PASS，否则 FAIL（detail 进报告）
checkEqual(label, got, want)      -- got == want
checkNear(label, got, want, tol)  -- math.abs(got-want) <= (tol or 1e-6)
```

- 全部断言进入 `H.checks`（pass/fail 计数）。
- 失败时仅记录，不会中断场景；场景末尾调用 `__HARNESS.summary()` 汇总并打印通过率。

### 虚拟时钟 / 快照

```lua
pump(seconds)        -- 在协程内按 1/60 逐帧让出，让 RenderStepped/Heartbeat 每帧触发；
                     --   主线程直调时退化成 pumpSeconds。动画要「走完」就用它。
Snapshot(label)      -- 立即拍一张结构树+ASCII+色彩网格，label 显示在报告里
vclockNow()          -- 当前虚拟时钟（秒）
tweenCount()         -- 已创建的补间数量（#M.tweenLog）
```

> 注意：补间 `Play()` 会**立即应用目标属性**，但 `Completed` 事件**延迟到补间时长之后**
> 触发。所以「属性值」在 Play 当时就落定；变的是「完成回调」何时跑。想等动画副作用
> （如 chain 的下一步、UI 显隐切换），用 `pump(时长)` 推进。

### 交互模拟

```lua
tapUI(inst, opts)    -- 模拟点击：触发该实例的 MouseButton1Click / Activated
fireUI(inst, eventName, input)  -- 触发任意 Signal（如 "MouseButton1Click"）
                                 --   input 为可选 InputObject
mkInput(opts)        -- 构造一个 InputObject（opts: {KeyCode, Position, UserInputType,...}）
```

### 查询实例树

```lua
guiRoot()            -- 返回根 ScreenGui（视口挂载点）
findByName(name)     -- 全树按名字（子串）找，返回 table
findByText(text, exact)  -- 全树按 TextLabel/TextBox 的文本找（exact=false 时子串）
findFirstOfClass(className) -- 全树首个指定 ClassName
countInstances()     -- 当前实例总数
```

（另有 `*R` 后缀版本直接转发到 `Vision.findByName` 等，行为一致。）

### 健康度 / 收尾

```lua
dumpWarnings()       -- 返回 mock 警告条数（同时打印内容）；用 print 接返回值
__HARNESS.summary()  -- 打印「运行汇总」（断言/快照/Tween/警告/错误）并返回
                     --   (H.checks.fail==0 and #H.errors==0)
__HARNESS.errors     -- 场景协程报错数组（协程内 error 被捕获进这里，不终止运行）
__HARNESS.snapshots  -- 已拍快照数
```

---

## 三、vision.lua 内部 API（进阶 / 二次开发用）

`Vision` 表挂在 `_G.__MOCK` 命名空间，亦作为全局 `Vision` 暴露。

| 成员 | 作用 |
|------|------|
| `Vision.viewport = {w=800,h=600}` | 视口像素尺寸（可被 run_ui 的 `--viewport` 覆盖） |
| `Vision.cell = {w=8,h=16}` | 每个字符格的像素尺寸（ASCII 分辨率） |
| `Vision.computeLayout()` | 回溯 `_abs` 字段：为每个 GuiObject 算绝对 `(x,y,w,h)`、裁剪框、生效透明度 |
| `Vision.renderAscii(layout)` | 返回 ASCII 字符串（线框 + 边框避让文字） |
| `Vision.renderColorGrid(layout, cv)` | 返回色彩网格字符串 + 图例 |
| `Vision.describeTree(layout)` | 返回结构树字符串（含布局告警） |
| `Vision.Snapshot(label, opts)` | 内部快照入口（harness 的 `Snapshot` 转发到此） |
| `Vision.findByName(name)` | 按名查找 |
| `Vision.findByText(text, exact)` | 按文本查找 |
| `Vision.findFirstOfClass(className)` | 按类查找 |

### 布局规则（computeLayout 遵守的 Roblox 语义）

- `Size`/`Position` 的 `Scale` 相对**父级完整尺寸**（不受 UIPadding 影响）。
- `UIPadding` 只收缩 `UIListLayout` 内容区，不改变自身 Size 的 Scale 基准。
- `ScrollingFrame` 子级坐标减 `CanvasPosition`；默认 `ClipsDescendants=true`。
- `CanvasGroup.GroupTransparency` 向子树传递（子树实际 alpha = 父组 alpha × 自身 alpha）。
- 绘制顺序：DFS + 同层按 `(ZIndex, 原始插入序)` 稳定排序（ZIndexBehavior.Sibling 语义）；
  `ScreenGui` 之间按 `DisplayOrder` 排。
- `UICorner` 圆角：仅擦除「圆角盒内、且圆心距弧心 > radius」的格。
- CJK 字符按 1 em、ASCII 按字体的 em 系数（Gotham 0.60 等）度量；
  网格内每字符占整数格 `adv = max(1, round(charPx/cellW))`。

---

## 四、在场景里的最小可用骨架

```lua
local ok, Library = pcall(loadstring, game:HttpGet("URL"))
local win = Library:CreateWindow({ Title = "X", Info = "Y", Icon = "skull" })
check("CreateWindow 成功", type(win) == "table")

win:Add()
pump(1.0)                                  -- 入场动画
local tab = win:AddTab({ Title = "主页" })
local tg  = tab:AddToggle({ Title = "自动", Default = true })
Snapshot("初始状态")

local node = findByText("自动")             -- 或通过 guiRoot() 自写 walk
fireUI(node, "MouseButton1Click")
pump(0.5)
check("切换生效", tg:GetValue() == false)

__HARNESS.summary()                         -- 必须，否则报告不汇总
```

---

## 五、命中测试 `Vision.findByPoint(x, y)`

返回该点**最上层的可见 GuiObject**（沿绘制序倒序找第一个命中者，尊重 `Visible` 传播与裁剪矩形）。
配套 harness 全局 `hitTest(x, y)`。用于交互式点击：`local t = hitTest(x,y); if t then tapUI(t) end`。

---

## 六、矢量绘制列表 `Vision.buildDrawList()`

供**高分辨率清晰渲染**（`render_hires.py` / `run_ui_luau.py --style hires`）使用。
返回一个数组，每个元素对应一个可见 GuiObject，含其**精确矩形与完整样式**：

| 字段 | 含义 |
|------|------|
| `seq` | 绘制序（= 布局 DFS + 同层 ZIndex 排序，等同 Roblox 绘制先后） |
| `class` / `name` | 类名 / 实例名 |
| `x,y,w,h` | 绝对矩形（像素） |
| `zindex` | 实例 ZIndex（调试用；叠加顺序仍以 `seq` 为准） |
| `rotation` | 旋转角（度，绕元素中心，Roblox `Rotation`） |
| `clip` | 生效裁剪矩形 `{x,y,w,h}`（父级 ClipsDescendants / ScrollingFrame），无则缺省 |
| `bg` / `bgAlpha` | 背景色 `{r,g,b}`（0..1）与不透明度（含 CanvasGroup 组透明度） |
| `corner` | 圆角半径（UICorner，已折算 Scale+Offset） |
| `stroke` | UIStroke `{thickness, r,g,b, a, applyMode, lineJoin}`，无则缺省 |
| `border` | BorderSizePixel `{size, color}`，无则缺省 |
| `gradient` | UIGradient `{rotation, kps=[{t,r,g,b}...], tr=[{t,v}...]?, ox,oy?}`，无则缺省；`tr` 为 `Transparency` 的 NumberSequence 关键点 |
| `pad` | UIPadding `{l,r,t,b}`，无则缺省 |
| `image` / `imageColor` / `imageAlpha` | ImageLabel/ImageButton 占位信息 |
| `text` / `textColor` / `textAlpha` / `textSize` / `font` / `xa` / `ya` / `wrapped` / `scaled` | 文本样式与对齐（RichText 已剥离标签） |
| `textStroke` | 文字描边 `{r,g,b,a}`（`TextStrokeTransparency<1` 时存在） |

条目按 `seq` 升序即为正确的叠加顺序（父在子前、同层按 ZIndex）。
渲染器据此按序做 alpha 合成即可还原画面。

### 已还原的 Roblox 渲染语义

- **布局**：`Scale+Offset` 折算、`AnchorPoint`、`UIListLayout`（含 SortOrder/对齐/间距）、
  `UIPadding` 收缩内容区、`ClipsDescendants`/`ScrollingFrame` 矩形裁剪、`CanvasGroup` 组透明度向下传递、
  **`AutomaticSize`（X/Y/XY）按内容自适应尺寸**（有列表布局时沿主轴累加子级尺寸，无则取子级包围盒；子级自动尺寸递归计入）。
- **可见性**：`Visible` **沿树向下传递**——父级不可见 ⇒ 整棵子树不渲染（真实 Roblox 语义；
  缺此传播会导致"隐藏页面"的子节点仍被绘制，典型症状是**所有页面同时显示**）。
- **绘制序**：DFS + 同层 `(ZIndex, 原始序)` 稳定排序（`ZIndexBehavior.Sibling`）。
- **样式**：`Color3`、`BackgroundTransparency`、`UICorner`、`UIStroke`、`BorderSizePixel`、
  `UIGradient`（颜色 + `Transparency` 渐隐 + `Offset`）、`TextStroke`、`Rotation`。
- **文本**：X/Y 对齐、自动换行、`TextScaled`。
- **保真修复**：`UIGradient.Color` 以 `ColorSequence` 设置时，此前引擎用 `rawget` 读不到
  关键点（渐变不生效），已改为经实例索引读取；`Instance.Name` 现按真机语义在未设置时
  返回类名（此前为 nil，会让 Luau 的 `string.format("%s")` 报错）。
