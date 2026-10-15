# 无头运行时模拟了什么 / 没模拟什么

`mock_runtime.lua` 是一个跑在 Lua 5.5 上的 Roblox 运行环境子集。下面按模块列出
**已模拟**（可直接用）与**未模拟 / 近似**（写了也不报错但不生效，或需替换写法）。

---

## 一、已模拟

### 实例系统（Instance）
- `Instance.new(className, parent?)`：GuiObject 全系（Frame / TextLabel / TextButton /
  ImageLabel / ImageButton / ScrollingFrame / CanvasGroup / UIListLayout / UIPadding /
  UICorner / UIStroke / UIGradient / ScreenGui 等）、Folder、BindableEvent 等。
- 属性读写：`Name` / `ClassName` / `Size`(UDim2) / `Position`(UDim2) / `BackgroundColor3` /
  `BackgroundTransparency` / `ZIndex` / `Visible` / `AnchorPoint` / `BorderSizePixel` /
  `Text` / `TextSize` / `TextColor3` / `Font` / `CornerRadius`(UICorner) / `Thickness`(UIStroke) /
  `GroupTransparency`(CanvasGroup) 等。
- `:GetChildren()` / `:FindFirstChild(name)` / `:FindFirstChildOfClass(class)` /
  `:IsA(class)` / `:Destroy()` / `:Clone()`。
- `guiRoot()`：返回根 `ScreenGui`（视口挂载点），快照从此遍历。

### 值类型
`UDim` / `UDim2` / `Vector2` / `Vector3` / `Color3`(`fromRGB`/`new`) / `ColorSequence` /
`NumberSequence` / `Rect` / `TweenInfo` / `BrickColor` / `Font` / `EnumItem`。

### Enum（常用组已预置）
`Font` / `EasingStyle` / `EasingDirection` / `TextXAlignment` / `TextYAlignment` /
`FillDirection` / `SortOrder` / `HorizontalAlignment` / `VerticalAlignment` /
`UserInputType` / `UserInputState` / `KeyCode` / `ZIndexBehavior` / `ScrollingDirection` /
`AutomaticSize` / `PlaybackState` / `ApplyStrokeMode` / `ScaleType` / `TextTruncate` /
`ElasticBehavior`。
- 未列举成员访问返回占位 `EnumItem`（不报错），但建议显式补到 `Enum` 表。

### 信号 / 事件
`Signal:Connect(fn)` / `:Fire(...)` / `:Wait()`（同步）；`Changed` / `MouseButton1Click` /
`InputBegan` / `InputEnded` / `InputChanged` 等。mock 里 `Fire` **同步**调用 handler。

### 补间（TweenService）⚠️ 关键语义
- `TweenService:Create(inst, info, goal):Play()`：**立即应用目标属性**，但
  `Completed` 事件**延迟到 `info.Time` 之后触发**（与真实 Roblox 一致）。
- 这样「先 `Play()` 再 `Completed:Connect()`」的惯用法也能正确推进。
- `Cancel()` / `Pause()` / `Destroy()` 均已实现。

### 调度器（task / 虚拟时钟）
- `task.spawn` / `task.defer` / `task.delay(t, fn)` / `task.wait(t)`：基于虚拟时钟 `vclock`
  的事件队列；`pump(seconds)` 按 1/60 逐帧推进，`RenderStepped`/`Heartbeat` 每帧触发
  （回调带 `dt` 参数）。
- `tick()` / `os.clock()`：返回虚拟时钟（让依赖墙钟的动画也能快进）。

### 服务（game:GetService）
`Players`（含 `LocalPlayer.PlayerGui`）/ `Lighting` / `RunService`(RenderStepped,
Heartbeat) / `TextService` / `UserInputService` / `Workspace` / `ReplicatedStorage` /
`TweenService` / `HttpService`(JSONEncode/Decode) / `GuiService` / `StarterGui` 等。
未模拟的服务会返回空壳并记一条警告（不崩溃）。

### 执行器环境（executor）
- `loadstring`(=load) / `getgenv` / `getrenv` / `identifyexecutor` / `setclipboard`(记警告)。
- 执行器文件系统：`isfile` / `readfile` / `writefile` / `isfolder` / `makefolder`（内存 FS，
  可被场景预置缓存文件）。
- 执行器 HTTP：`request` / `http_request` / `syn.request` / `http.request` / `getcustomasset` /
  `getsynasset` —— 从 `libRegistry`（由 `run_ui.py --lib` 注入）取预置内容，
  模拟真实执行器的网络请求与图标资源。
- `gethui()`：返回隐藏 UI 容器（ScreenGui 在 `Instance.new` 时已注册进快照根）。
- `warn(...)`：记录进 `M.warnings`（用于捕获库内部 `reportError`）。

### Luau 内建
`table.freeze` / `table.clone` / `table.move` / `math.round` / `coroutine.close` /
`string.split` / `bit32`（详见 `references/luau-compat.md`）。

---

## 二、未模拟 / 近似（写了不报错但不生效）

| 能力 | 现状 | 影响 |
|------|------|------|
| 像素级渲染 | 不渲染，只算布局矩形 | 无法验证实际像素；用 ASCII/色彩网格近似 |
| 真实字体度量 | 用按字体的 em 系数近似 | `TextBounds` 是估计值，长文本溢出判断为近似 |
| 鼠标悬停 / 按压态 | 仅 `tapUI`/`fireUI` 触发点击事件 | 无 hover 态验证 |
| `GetPropertyChangedSignal` / `AbsoluteSize` 变更事件 | 静态布局引擎不发射 | 依赖「属性变更→回调」的入场状态机可能停在中间态 |
| `ContentProvider` / 资源真正下载 | 不下载，URL 占位 | ImageLabel 只占位 |
| 物理 / 碰撞 / 3D | 无 | 本 Skill 只服务 2D Gui |
| `GetFullName` / 远程事件 `RemoteEvent` | 部分 | 仅本地 UI 相关 |

---

## 三、已知边界（使用须知）

1. **多阶段入场状态机的完整展开**
   真实库（如 DynamicCowUI）的「分裂球 loader → 品牌字渐绿 → 展开面板 → buildTabUI」
   依赖真实渲染循环的属性变更事件，静态 mock 下通常推进到「标题 handoff」阶段即停。
   这**不影响**加载 / `CreateWindow` / 全部控件工厂 / 补间 / 调度 / `HttpGet` 等核心能力验证
   （`examples/smoke_dynamiccow.lua` 19/19 全过）。

2. **属性在 Play 即落定**
   不要假设「某帧后属性才变化」——`Play()` 那一刻终值就已写入；变的是 `Completed` 回调时机。

3. **事件同步触发**
   mock 的 `Signal:Fire` 同步调用 handler；真实环境是下一帧。顺序敏感的逻辑需注意。

4. **只接受 Luau 的 Lua-5 兼容子集**
   `continue` / `+=` / 类型注解 / 字符串插值等 Luau 语法在 Lua 5.5 解析器下会报语法错
   （见 `references/luau-compat.md`）。

5. **性能**
   布局/渲染为纯 Lua，单次 `Snapshot` 在 800×600 / 100×38 网格下毫秒级；超大 UI（数千节点）
   会线性变慢，属预期。

---

## 六、为兼容真实大型库补齐的真机语义

跑真实库（DeltaUI 475KB、DynamicCowUI 等）时暴露的 mock 保真缺口，已按 Roblox 语义补齐：

| 项 | 真机行为 | mock 处理 |
|----|----------|-----------|
| `Instance.Name` | 永远返回字符串（默认=类名） | `__index` 未设置时返回 `ClassName`（此前 nil，会让 Luau 的 `string.format("%s")` 报错） |
| `TextLabel.TextBounds` | 随 Text/TextSize 变化的 Vector2 | 按 em 系数估算（ASCII≈0.55em，非 ASCII≈1em，行高≈1.2×TextSize） |
| `Stats.PerformanceStats.*` | 有 `Ping`/`Heartbeat` 等，`.GetValue()` 返回数字 | 专用小 mock（Ping=42），未知项返回数字 0 |
| 未模拟 service 的未知字段 | —— | 返回**通用代理**：可调用、可索引、含 `Connect/Wait/Fire`、`#` 为 0（真值性同"函数"，不改变库的分支判断） |
| 未模拟 service 的 `_children` | 真实容器 | 暴露真实空表（`.Parent = CoreGui` 之类可安全挂接，不再崩） |
| 全局 `unpack` | Luau 自带 | lupa（Lua 5.4+ 已移除）下补 `unpack = table.unpack` |
| 全局 `getfenv` / `setfenv` | Luau 自带（且 `getfenv()` 可写） | lupa 下补近似实现（`getfenv()` 返回 `_G`） |
| `math.floor(CornerRadius.Offset)` 等 | 属性为整数 | 报告格式化统一 `toInt()` 取整，避免 `%d` 收到浮点报错 |

> `_G` 写入：真实 luau CLI 的 `_G` 是只读表，但 `getfenv()` 返回同一个**可写**默认全局环境。
> 因此执行「大量写 `_G` 的库」时，可给源码前置一行 `local _G = (getfenv and getfenv()) or _G`
> （见 `examples/delta_scenario.lua`），lupa 与 luau 均成立。
