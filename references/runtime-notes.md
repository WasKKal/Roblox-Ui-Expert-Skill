# 运行时说明（mock 覆盖范围 · lupa 与真实 Luau 两条路径）

本 Skill 有两个可互换的执行路径，**共用同一套 Lua 源码**（`mock_runtime.lua` /
`vision.lua` / `harness.lua`）：

| 路径 | 解释器 | 入口 | 用途 |
|------|--------|------|------|
| **lupa** | Lua 5.5（Python 内嵌） | `scripts/run_ui.py` | 快速文本报告 / 结构树 / 断言，无外部依赖 |
| **真实 Luau** | 源码编译的官方 `luau` CLI | `scripts/run_ui_luau.py` | 执行原生 Luau 语法（`+=` / `continue` / 类型注解 / 字符串插值），并渲染 PNG / HTML / APNG |

两者跑同一场景得到的结果一致（早期实测：两条路径导出的图像逐字节相同）。差异只在于
**解释器能力**与**输出形态**，写 UI 代码时按「A 节末尾的语法子集」约束即可双跑。

---

## A. mock 运行时模拟了什么 / 没模拟什么

`mock_runtime.lua` 是一个跑在 Lua 5.5 上的 Roblox 运行环境子集。下面按模块列出
**已模拟**（可直接用）与**未模拟 / 近似**（写了也不报错但不生效，或需替换写法）。

---

### 一、已模拟

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
- `TweenService:Create(inst, info, goal):Play()`：**按虚拟时钟逐帧真实插值**——
  记录起止值与时长，每帧按 `EasingStyle` × `EasingDirection`（含 `In`/`Out`/`InOut`）
  求值并写回属性；`DelayTime` 会让补间延迟起算（延迟期间保持起始值）。
- 到时长后**下一帧**触发 `Completed`（与真机一致），因此
  「先 `Play()` 再 `Completed:Connect()`」的惯用法能正确推进。
- 可插值类型：`number` / `UDim2` / `Vector2` / `Color3`；其它类型直接取终值。
- `Cancel()` 立即中止；`Pause()` / `Destroy()` 已实现（空操作）。
- 因此：**动画的中间态是真实存在的**——这也是能采到动画帧（`--capture`）的前提。

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

### 二、未模拟 / 近似（写了不报错但不生效）

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

### 三、已知边界（使用须知）

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

### 六、为兼容真实大型库补齐的真机语义

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

---

### 七、贴近真机的文本/样式默认值

真机（Roblox）的属性默认值与"直觉"不同，直接影响文本位置，已按真机修正：

| 属性 | 真机默认 | 之前 mock 的错误值 | 影响 |
|------|----------|-------------------|------|
| `TextXAlignment` | `Center` | `Left` | 未显式设置时文本水平位置偏移 |
| `TextYAlignment` | `Center` | `Top` | **最典型**：文本被顶到上沿而非垂直居中 |
| `TextLabel.BackgroundTransparency` | `1`（无底色） | `0` | 文本标签会多出一块纯色底 |
| `ImageLabel.BackgroundTransparency` | `1`（无底色） | `0` | 同上 |

> 排查"渲染出来文字位置和真实 Roblox 对不上"时，先核对这几项默认值。

### 八、文本字体的贴近

渲染侧（HTML / PNG）使用与 Roblox 同源的字体，缩小字宽/行高差异：

- `Enum.Font.SourceSans*` → **Source Sans 3**（Roblox 用的就是 Source Sans 家族）
- `Enum.Font.Gotham*` → **Inter**（近似 Gotham）
- 中文（CJK）→ Noto Sans CJK 回退（Roblox 自身也无 CJK 字形，由引擎回退）
- 字体文件在 `assets/fonts/`（可变字体，一份覆盖全字重）：
  HTML 以 base64 内嵌为 `@font-face`；PNG 渲染按字符分段选字体
- 同时修正了字重映射：`*Bold/*Black` 名 → `font-weight:700/900`（此前 HTML 完全没设 font-weight，粗体被渲染成常规体）

---

## B. Luau 兼容与语法子集

本 Skill 的运行时跑在 **Lua 5.5**（通过 lupa）上，而 Roblox 用的是 **Luau**。两者大部分
兼容，但有几处差异。本文件说明：mock 已补哪些 Luau 内建、哪些 Luau **语法**不被
标准 Lua 解析器接受、写 UI 代码时该用哪个子集。

---

### 一、mock 已补齐的 Luau 内建（可直接用）

这些在 `mock_runtime.lua` 开头注入，库里若用到会被正常解析：

| 内建 | 实现 | 说明 |
|------|------|------|
| `table.freeze(t)` | 原样返回 `t` | Luau 冻结；mock 不强制只读（仅占位，保持语义） |
| `table.clone(t)` | 浅拷贝 | |
| `table.move(a1,f,e,t,a2)` | 跨表搬移 | 仅当原生缺失时注入 |
| `math.round(x)` | `floor(x+0.5)` | |
| `coroutine.close(co)` | 空实现 | |
| `string.split(s, sep)` | 返回分割数组 | |
| `bit32` | 基础位运算表 | 仅当原生缺失时注入 |
| `tick()` | 返回虚拟时钟 `vclock` | 让依赖墙钟的进度计算也能随 pump 前进 |
| `os.clock()` | 同 `vclock` | 同上 |
| `loadstring` | 别名到 `load` | 执行器环境常用 |

> 依赖 `os.clock()`/`tick()` 的动画在 mock 里能正确推进（因为返回虚拟时钟而非真实墙钟），
> 这是刻意的：真实环境里这类动画用墙钟，但无头测试里必须用虚拟时钟才能「快进」。

---

### 二、Luau **语法**不被 Lua 5.5 解析器接受（写库代码要避开）

如果你的 UI 库用了以下 Luau 专属语法，`loadstring`/`load` 会直接报语法错误。
本 mock 用标准 Lua 解释器，**无法**执行这些：

| Luau 语法 | 等价 Lua 5.x 写法 |
|-----------|------------------|
| `continue` | `goto` 或重构循环 / 用 `if not ... then ... end` 包裹 |
| `x += 1` / `s ..= "a"` / `x -= 1` | `x = x + 1` / `s = s .. "a"` |
| 复合比较赋值 `x += y`（任意） | `x = x + y` |
| 类型标注 `local x: number = 1` | `local x = 1` |
| 函数类型 `function f(x: number): string` | 去掉注解 |
| 泛型 `local t: {string}= {}` | `local t = {}` |
| 字符串插值 `` `值={x}` `` | `"值=" .. tostring(x)` |
| `for i, v in t` 的类型注解 | 去掉注解 |
| 默认参数 `function f(x = 1)` | 函数体内 `x = x or 1` |

**结论**：本运行时只接受 Luau 的「Lua 5 兼容子集」。真实 Luau 库（如 DynamicCowUI）
若只用标准 Lua 语法即可直接 `loadstring` 加载；若含上述语法，需先转写为兼容子集。

---

### 三、写 UI 代码时推荐用的子集

针对本 mock 写 UI 库 / 场景时，遵循：

1. 只用 `local`/`function`/`for`/`while`/`if`，**不用** `continue` 与复合赋值。
2. 字符串拼接用 `..`，不用插值。
3. 变量不写类型注解。
4. 用 `pairs`/`ipairs` 遍历；遍历需要稳定顺序时，用 `(key, 原始插入序)` 比较。
5. 用 `task.spawn`/`task.delay`/`task.wait` 做并发与延迟（mock 已模拟虚拟时钟）。
6. 用 `TweenService:Create(...):Play()` 做动画；属性会**按虚拟时钟逐帧插值**，
   所以 `pump(秒)` 推进时间即可看到中间态；`Completed` 在时长后的下一帧触发。
7. 事件用 `Signal:Connect(...)` / `:Fire(...)`（mock 同步触发）。
8. 文本用 UTF-8；CJK 全角按 1 em、ASCII 按字体系数度量，断行/溢出由 vision 自动算。

---

### 四、判断一段 Luau 能否在本运行时跑

```bash
# 直接用 Lua 5.5 试编译，能编译即通过
python3 -c "
import lupa
lua = lupa.lua55.LuaRuntime(unpack_returned_tuples=True)
src = open('your_lib.lua', encoding='utf-8').read()
r = lua.eval('function(s) local f,e=load(s) if f then return \"OK\" else return tostring(e) end end')(src)
print(r)
"
```

若报 `unexpected symbol near ...`（如 `continue`、`+=`、`:` 注解），按第二节改写即可。

---

### 五、真实 Luau 解释器路径（`run_ui_luau.py`）

`run_ui_luau.py` 用从源码编译的**官方 luau 解释器**（`cmake` + `make Luau.Repl.CLI`
得到 `luau`）执行**同一套** `mock_runtime.lua` / `vision.lua` / `harness.lua`，再
把引擎算出的色彩网格渲染成真实 PNG。两节的区别：**真实 luau 原生支持全 Luau 语法**
（`+=`、`continue`、类型注解、字符串插值），第二节的转写规则只对 `run_ui.py` 适用。

### 为兼容 luau CLI 的安全限制，模块做了这些适配（对 lupa 无害）

luau CLI 出于沙箱安全，收紧了若干能力，实测结论：

| 限制 | 现象 | 适配 |
|------|------|------|
| 禁用 `io` 库 | `io` 为 `nil`，`io.open` 不可用 | 报表不再写文件，改由 stdout 哨兵 `--ROBLOXUI_JSON_BEGIN/END--` 回传 JSON |
| 禁用 `load` | `load` 为 `nil` | 统一用 `loadstring`；mock 里 `loadstring = load` 加了 `type(load)=="function"` 守卫 |
| `_G` 只读且与可写全局脱钩 | `_G.X = v` 抛 "readonly table"；裸全局**不**出现在 `_G` | 模块间**只用裸全局名**共享（`__MOCK` / `Vision` / `Harness`），禁止 `_G.X` 读写 |
| `loadstring` 第 3 个 env 参数被忽略 | 传入的 env 未生效，chunk 仍在默认全局环境 | **弃用自定义 ENV**；多个 `loadstring` 调用本就共享同一默认全局环境 |
| 标准库表只读 | `math.round = ...` / `string.split = ...` / `table.freeze = ...` 抛错 | 用 `safeSet(lib, k, v)`（`rawget` 判缺失 + `pcall` 包裹写入）注入 shim；luau 原生已有这些函数则跳过 |

### 两个易踩的坑

1. **同名"裸赋值"不会导出全局**：`local Enum = {}` 之后再写 `Enum = Enum`，Luau 会
   把左侧 `Enum` 解析为**局部变量**，全局 `Enum` 永远建不出来（`_G` 又只读）。
   正确做法：直接声明 `Enum = {}`（全局），或改用不同名（`__MOCK = M` 就因此正确）。
2. **跨运行时一致性**：模块源码被 lupa 与真实 luau **共用**，任何改动都要在两边
   都成立。已验证 `run_ui_luau.py` 与 `run_ui.py` 对同一场景产出的画布**逐字节一致**
   （PNG md5 相同）。

### 快速自检真实 luau 路径

```bash
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
  --scenario examples/simple_scenario.lua \
  --out /tmp/ui_render_luau.png
# 期望：13/13 通过、0 错误，并生成 /tmp/ui_render_luau.png
```
