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
