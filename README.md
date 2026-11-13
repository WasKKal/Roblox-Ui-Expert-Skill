# Roblox-Ui-Expert-Skill

<p align="center">
  <img src="https://img.shields.io/badge/Roblox-Luau-00a2ff?style=for-the-badge&logo=roblox" alt="Roblox Luau" />
  <img src="https://img.shields.io/badge/Renderer-Headless%20Vector-6f42c1?style=for-the-badge" alt="Headless Vector Renderer" />
  <img src="https://img.shields.io/badge/Executor%20API-373%2F373-3fb950?style=for-the-badge" alt="Executor API Coverage" />
  <img src="https://img.shields.io/badge/Delta%20Env-9%20modes-orange?style=for-the-badge" alt="Delta Env Modes" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License" />
</p>

> 一套**无头 Roblox UI 运行时 + 矢量渲染器**：用 Luau 代码构建 UI，不需要 Roblox Studio，就能拿到结构树 / ASCII 线框 / 清晰 PNG / 可交互 HTML / APNG 动画，并可直接渲染真实 UI 库与真实脚本。

---

## ✨ 特性

- 🧊 **完整无头运行时** —— `Instance` 树、值类型（`UDim2` / `Color3` / `ColorSequence` / `Vector3` / `CFrame`）、`Enum`、`Signal`、`TweenService`、`task` 调度与虚拟时钟，补间按时间真实插值。
- 🎨 **矢量高清渲染** —— 超采样 + Roblox 同源字体，还原圆角、渐变、描边、边框、图标、裁剪、旋转、组透明度与文本对齐。
- 📐 **像素级贴合** —— 同心圆角描边与字形 ink-bbox 对齐，附带可复现的几何精度自检（见「渲染精度」）。
- 🔌 **执行器 API 兼容层** —— 覆盖真实执行器环境探测到的 **373 个全局 API**，让真实脚本不再因缺全局函数而中断。
- 🅱️ **Delta 执行器环境模拟** —— 复刻 `_G` 空共享表、`getgenv()` 独立 `REAL_ENV`、`getfenv` / `getrenv` 多形态与 9 种 `DELTA_MODE`，可对真实库做红蓝对抗式差分验证。
- 🧩 **真实库开箱即用** —— `Instance.new(class, parent)` 双参数、`Color3:ToHSV()`、Lucide 离线桩（含 DeltaUI 的 `@latest` / `master` 兜底 URL）、`HttpGet` 未命中诊断全部内置，无需在场景里手写 shim。
- 🖱️ **交互与动画** —— 命中测试 + 点击派发、逐帧采样 APNG 与 HTML 时间轴播放器、本地预览服务。
- 🔍 **静默失败可观测** —— 未注册的 `HttpGet` / `request` URL 单独记录，不污染 warnings 断言。
- 🧪 **双执行路径** —— `lupa`（Lua 5.5，进程内）与真实 `luau` 解释器共用同一套 Lua 源码，结果一致。

## 📦 安装

```bash
# 运行时依赖
pip3 install pillow lupa flask cairosvg fonttools

# PNG 超清渲染需要真实 Luau 解释器（源码编译，可选）
git clone --depth 1 https://github.com/luau-lang/luau && cd luau
cmake -B build && make -C build Luau.Repl.CLI && cp build/luau /usr/local/bin/
```

> `lupa` 路径（文本报告 + 断言）无需 `luau` 可执行文件；`PNG / HTML / APNG` 路径需要它。

## 🚀 快速开始

```bash
# 1) 文本报告 + 断言（最快）
python3 scripts/run_ui.py \
  --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
  --scenario examples/rich_scenario.lua

# 2) 清晰 PNG + 可交互 HTML
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
  --scenario examples/rich_scenario.lua \
  --out rich.png --style both --scale 2 --ss 3

# 3) 动画：每 0.1 虚拟秒采一帧 → APNG + 时间轴播放器
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/anim_ui.lua=examples/anim_ui.lua" \
  --scenario examples/anim_scenario.lua \
  --out anim.png --style both --capture 0.1 --anim

# 4) 渲染真实 UI 库：只映射库 URL，Lucide CDN 桩由 CLI 自动补齐
python3 scripts/run_ui_luau.py \
  --lib "https://ghfast.top/https://raw.githubusercontent.com/OWNER/REPO/main/MyLib.lua=/path/MyLib.lua" \
  --scenario my_scenario.lua --out mylib.png --offline

# 5) Delta 执行器环境：渲染真实 DeltaUI（_G 空表 + getgenv 独立 REAL_ENV）
python3 scripts/run_ui_luau.py \
  --lib "https://mock.local/DeltaUI.lua=/path/DeltaUI.lua" \
  --scenario examples/delta_scenario.lua --delta-mode getfenv_real \
  --out delta.png --style both --scale 2
python3 scripts/check_delta_env.py          # 9 模式 × 双路径差分矩阵

# 6) 本地预览服务：上传任意 .lua 即渲染，可在画布上点击交互
python3 scripts/preview_server.py --port 8765
```

> 真实库用 `loadstring(game:HttpGet(...))()` 加载时，只需 `--lib URL=PATH`；`Instance.new` 双参数、`Color3` HSV、Lucide 图标均无需手写 shim。

## 🗂️ 能力一览

| 类别 | 能力 | 入口 |
| --- | --- | --- |
| 渲染 | 圆角 / 描边 / 边框 / 渐变 / 图标 / 变换 | `scripts/render_hires.py`、`scripts/render_html.py` |
| 输出 | 文本报告 / 结构树 / ASCII / PNG / HTML / APNG | `scripts/run_ui.py`、`scripts/run_ui_luau.py` |
| 兼容 | 执行器 API 兼容层、内置 Lucide 离线桩自动注册 | `scripts/executor_api.lua`、`scripts/auto_libs.py` |
| Delta 环境 | `_G` 空表 / 独立 `REAL_ENV` / 9 模式矩阵 / `DBG_SNAP` | `scripts/delta_env.lua`、`scripts/delta_modes.py` |
| 自检 | 渲染几何精度、执行器 API 支持率、Delta 环境差分、真实脚本 API 兼容 | `scripts/check_render_precision.py`、`scripts/check_api_support.py`、`scripts/check_delta_env.py`、`examples/real_script_api_scenario.lua` |
| 交互 | 命中测试 / 点击重放 / 预览服务 | `scripts/preview_server.py` |

## 📐 渲染精度

渲染器以「主体轮廓」为唯一基准绘制描边与文字，附带 `check_render_precision.py` 做像素级回归：

```bash
python3 scripts/check_render_precision.py            # 人类可读
python3 scripts/check_render_precision.py --json --strict   # CI（超阈值退出码 1）
```

| 指标（逻辑像素） | 修复前 | 修复后 |
| --- | --- | --- |
| 圆角描边中心线偏离主体轮廓 | `5.0` | **`0.0`** |
| 直边描边内缩 / 外扩 | 偏外 `3.0` | `-1.5 / +1.5`（居中） |
| 主体填充中心偏移 | `-5.33` | **`0.0`** |
| 文字垂直居中偏差 | `+2.17` | **`-0.17`** |

根因与修复：

- 裁剪层局部原点 `ox` 符号写反，所有带 `UIStroke` / `BorderSizePixel` 的元素整体偏移并被裁掉边角（因此只有「部分」线条不贴合）；
- `UIStroke` 原用 PIL `rounded_rectangle(width=...)` 向内画且不同步调整圆角半径，角部必然错位；现改为**外框 / 内框差分的同心环形**，半径同步 `±thickness/2`；
- `BorderSizePixel` 原用直角 `rectangle`，现改为同样贴合圆角的环形；
- 文字原按字体行盒（`asc+desc`）+ PIL 默认 ascender 锚点定位，现改为基于**可见字形 ink bbox** 与基线锚点对齐；HTML 渲染器同步改用同心圆角描边层与 `line-height: 1`。

## 🔌 API 兼容层

`references/executor-api-list.txt` 固化了真实执行器环境探测到的 **373 个全局 API**。`scripts/executor_api.lua` 分两层覆盖：

| 层级 | 说明 |
| --- | --- |
| **语义实现** | 文件系统、HTTP、剪贴板、闭包 / hook、`crypt` / `base64` / `bit`、`debug`、`Drawing`、时间 / 身份 / 输入、`getgenv()` 真实环境代理等，返回合理值，脚本可继续往下执行 |
| **存在性桩** | 探测型 / 内部型 API 注册为静默无副作用函数，保证「全局函数不存在」不再中断脚本 |

> 诚实边界：373/373 指**环境探测意义上的存在性覆盖**；其中多数内部 hook / 调试 API 为无副作用桩，并不模拟真实副作用。核心子集（约 80 个）具备可用语义。

量化结果：

| 指标 | 改进前 | 改进后 |
| --- | --- | --- |
| 执行器 API 支持率（`lupa`） | `29/373 · 7.8%` | **`373/373 · 100%`** |
| 执行器 API 支持率（`luau`） | `22/373 · 5.9%` | **`373/373 · 100%`** |
| 两份真实脚本的关键 API 断言 | `41/68 · 60.3%`（另 5 条警告） | **`68/68 · 100%`**（0 错误 0 警告，双路径） |

```bash
python3 scripts/check_api_support.py              # 支持率（lupa）
python3 scripts/check_api_support.py --luau --details   # 真实 luau 路径 + 缺失清单
python3 scripts/run_ui.py --scenario examples/real_script_api_scenario.lua \
  --lib "https://api.pastes.dev/wbm8z5CjsN=examples/ui_lib_stub.lua"
```

Roblox 侧同步补齐：`Color3.fromHex/toHex`、`game:IsLoaded()` / `game.Loaded`、`StarterGui:SetCore`、`LocalPlayer:WaitForChild("PlayerGui")`、`workspace.DescendantAdded`、`CurrentCamera:WorldToViewportPoint`，以及 20+ 常用 `GetService` 服务（消除「未模拟 service」警告）。

> 说明：两份真实脚本是**常驻外挂脚本**，含 `while task.wait(...) do` / `while true do` 主循环，无头虚拟时钟无法自然终止，因此不做完整执行回归；改用有限的 `real_script_api_scenario.lua` 断言其依赖 API，并用 `--lib` 把远程 UI 库映射到 `examples/ui_lib_stub.lua` 验证加载链。

## 🅱️ Delta 执行器环境

`scripts/delta_env.lua` 把这些特征做成**可选环境层**，由 `--delta-mode` 在所有引擎模块加载完之后注入（工具内部靠裸全局名共享，不依赖 `_G`，因此替换 `_G` 不会破坏渲染引擎）：

| Delta 特征 | 普通执行器环境 | Delta 模拟 |
| --- | --- | --- |
| `_G` | 真实可写全局 / 只读内建表 | **0 字段空共享表或 nil** |
| `getgenv()` | `getfenv(0)` 真实全局 | **独立 `REAL_ENV`**（`__index` 回落真实全局），≠ `_G` |
| `getfenv()` | 返回 `_G` | **4 态**：REAL_ENV / 空 `_G` / 抛错 / 缺失 |
| `getrenv()` | 复制的 `_G` | **3 态**：REAL_ENV / 空 `_G` / 返回 nil |
| `setfenv()` | no-op | no-op |
| `checkcaller()` | 恒 true | 恒 true（差分信任，避免误杀） |
| `iscclosure()` | 常量 false | `C_SET` 标记 + `debug.getinfo().what=="C"` 真判定 |
| `DBG_SNAP` | 无 | 记录对空 `_G` 的缺失键访问，`DBGDUMP()` 输出 |

9 种模式（单一数据源 `scripts/delta_modes.py` ↔ `DeltaEnv.MODES`）：

```bash
python3 scripts/check_delta_env.py                 # 9 模式 × lupa/luau，18 项全通过
python3 scripts/check_delta_env.py --mode G_nil --json
python3 scripts/run_ui.py --scenario examples/delta_env_scenario.lua \
  --delta-mode getfenv_real --no-final-snapshot    # 单次运行 106 条语义断言
```

| 模式 | `_G` | `getgenv` | `getfenv` | `getrenv` |
| --- | --- | --- | --- | --- |
| `getfenv_real`（默认） | 空表 | → REAL_ENV | → REAL_ENV | 未定义 |
| `getfenv_empty` | 空表 | → REAL_ENV | → 空 `_G` | 未定义 |
| `getfenv_err` | 空表 | → REAL_ENV | 抛错 | 未定义 |
| `no_getfenv` | 空表 | → REAL_ENV | 缺失 | 未定义 |
| `no_getgenv` | 空表 | 缺失 | → 空 `_G` | 未定义 |
| `getrenv_real` | 空表 | 缺失 | → 空 `_G` | → REAL_ENV |
| `getrenv_empty` | 空表 | 缺失 | → 空 `_G` | → 空 `_G` |
| `getrenv_nil` | 空表 | 缺失 | → 空 `_G` | → nil |
| `G_nil` | **nil** | → REAL_ENV | → REAL_ENV | 未定义 |

新增的 7 条 Delta 断言验证了一个可观测指纹：DeltaUI 顶层把整套 UI 写进它看到的 `_G`（经 shim 绑定为 `getfenv()` = `REAL_ENV`），`getgenv().__DeltaUI_screenGui` 有值，而**共享 `_G` 仍是空表**。预览服务的 DeltaUI 示例也提供模式下拉框（`?mode=` / `?snap=1`）。

> 诚实边界：`getfenv_err` / `no_getfenv` 等模式下，依赖 `getfenv()` 的库会按真实 Delta 变体那样加载失败——这正是差分验证要暴露的差异，不是工具缺陷。luau 的 `_G` 为只读表，无法完全置空；`apply()` 逐项 `pcall` 降级并在 `[delta-sim]` / `DeltaEnv.report()` 中如实标注该运行时下不可用的特征。

## ✅ 验证清单

| 场景 | 期望 |
| --- | --- |
| `examples/simple_scenario.lua` | **13/13**、0 错误（luau + lupa） |
| `examples/rich_scenario.lua` | **16/16**、0 错误（luau + lupa） |
| `examples/anim_scenario.lua` | **11/11**、0 错误（luau + lupa） |
| `examples/compat_scenario.lua` | **16/16**、0 错误（luau + lupa） |
| `examples/real_script_api_scenario.lua` | **68/68**、0 错误 0 警告（luau + lupa） |
| `examples/delta_scenario.lua`（真实库 DeltaUI） | **12/12**（普通环境）/ **19/19**（`--delta-mode getfenv_real`），0 错误（luau + lupa） |
| `examples/delta_env_scenario.lua` | **106/106**、0 错误（9 模式语义差分，单次运行） |
| `scripts/check_delta_env.py` | **18/18**（9 模式 × lupa/luau） |
| `scripts/check_render_precision.py --strict` | 7 项几何指标全部通过 |
| `scripts/check_api_support.py` | `373/373`（lupa + luau） |

## 🎯 设计理念

- **单一数据源**：布局引擎产出「每个 GuiObject 的精确矩形 + 样式」，PNG / HTML / APNG 三个渲染器共用同一份绘制列表，避免各写一套布局规则。
- **双运行时一致**：`lupa` 与真实 `luau` 复用同一套 Lua 源码；差异（如内建 `typeof`、只读 `_G`）由场景断言显式规避，而非掩盖。
- **环境可切换**：执行器环境不是硬编码常量，而是可选模块 + 模式矩阵；同一份 UI 源码可在普通 / 9 种 Delta 变体下重复渲染，差异由断言显式暴露。
- **静默失败可观测**：缺资源、缺全局不再无声无息——`httpMisses` 独立通道、支持率探针、几何自检与环境差分共同构成可量化的回归网。
- **兼容但不假装**：兼容层明确区分「语义实现」与「存在性桩」，文档与报告都不把存在性覆盖当成功能等价。

## 📄 许可证

本项目基于 [MIT License](./LICENSE) 开源。

---

<p align="center">Made with ❤️ by WasKKal</p>
