# Luau → Lua 5.5 兼容说明

本 Skill 的运行时跑在 **Lua 5.5**（通过 lupa）上，而 Roblox 用的是 **Luau**。两者大部分
兼容，但有几处差异。本文件说明：mock 已补哪些 Luau 内建、哪些 Luau **语法**不被
标准 Lua 解析器接受、写 UI 代码时该用哪个子集。

---

## 一、mock 已补齐的 Luau 内建（可直接用）

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

## 二、Luau **语法**不被 Lua 5.5 解析器接受（写库代码要避开）

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

## 三、写 UI 代码时推荐用的子集

针对本 mock 写 UI 库 / 场景时，遵循：

1. 只用 `local`/`function`/`for`/`while`/`if`，**不用** `continue` 与复合赋值。
2. 字符串拼接用 `..`，不用插值。
3. 变量不写类型注解。
4. 用 `pairs`/`ipairs` 遍历；遍历需要稳定顺序时，用 `(key, 原始插入序)` 比较。
5. 用 `task.spawn`/`task.delay`/`task.wait` 做并发与延迟（mock 已模拟虚拟时钟）。
6. 用 `TweenService:Create(...):Play()` 做动画；记得 `Play()` 立即落属性，
   `Completed` 延迟触发——别假设 Play 当帧属性才变。
7. 事件用 `Signal:Connect(...)` / `:Fire(...)`（mock 同步触发）。
8. 文本用 UTF-8；CJK 全角按 1 em、ASCII 按字体系数度量，断行/溢出由 vision 自动算。

---

## 四、判断一段 Luau 能否在本运行时跑

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

## 五、真实 Luau 解释器路径（`run_ui_luau.py`）

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
