-- ==========================================
-- delta_scenario.lua — DeltaUI 真实库渲染自检（Delta 执行器环境）
-- ==========================================
-- DeltaUI 是「执行即建 UI + 常驻循环」的真实库（475KB / 约 1 万行）：
--   · 加载执行其顶层代码会直接搭出整套界面；
--   · 顶层末尾进入常驻等待（不会返回），故用 task.spawn 让它跑在独立协程，
--     主场景继续 pump 推进并做断言。
--
-- 【历史遗留项已解决】此前本场景 3/12 通过、0 实例，原因不是执行器环境探测，
-- 而是 auto_libs.py 只注册了 @lucide-v6 的三个 Lucide URL，DeltaUI 的
-- LoadLucide() 请求 @latest / master 两个 URL 全部落空，触发 4 次
-- task.wait(0.3) 重试，把顶层 UI 构建（约第 4882 行）拖到 pump(2.0) 之外。
-- 补齐 URL 后：638 实例 / 1 ScreenGui / 73 draws / 12 条断言全通过。
--
-- 【Delta 环境特征】用 --delta-mode 加载 delta_env.lua 后，_G 变为 0 字段空共享表，
-- getgenv()/getfenv() 返回独立 REAL_ENV。DeltaUI 有大量 `_G.__DeltaUI_*` 写入，
-- 正好用来验证「库状态落在 REAL_ENV 而非共享 _G」这一 Delta 指纹。
-- 不带 --delta-mode 时这些断言自动跳过（普通执行器环境）。
--
-- lupa（Lua 5.5）路径：
--   python3 scripts/run_ui.py \
--     --lib "https://mock.local/DeltaUI.lua=/root/uploads/1791642772656330982-DeltaUI.lua.txt" \
--     --scenario examples/delta_scenario.lua --viewport 1280x800 --max-seconds 40 \
--     --delta-mode getfenv_real
--
-- 真实 luau 路径 + PNG/HTML：
--   python3 scripts/run_ui_luau.py \
--     --lib "https://mock.local/DeltaUI.lua=/root/uploads/1791642772656330982-DeltaUI.lua.txt" \
--     --scenario examples/delta_scenario.lua --viewport 1280x800 --style both --scale 2 \
--     --delta-mode getfenv_real
-- ==========================================

local URL = "https://mock.local/DeltaUI.lua"

local okFetch, src = pcall(function() return game:HttpGet(URL) end)
check("HttpGet 取到源码", okFetch and type(src) == "string" and #src > 1000,
    "len=" .. tostring(src and #src))

-- 兼容 shim：DeltaUI 有大量 `_G.xxx = ...` 写入。真实 luau CLI 的 `_G` 是只读表，
-- 但 getfenv() 返回的正是可写环境；Delta 模式下它返回独立 REAL_ENV（同样可写，
-- 且通过 __index 回落真实全局），两种运行时均成立。
local SHIM = "local _G = (getfenv and getfenv()) or _G\n"

local fn, cerr = nil, nil
if type(src) == "string" then
    fn, cerr = loadstring(SHIM .. src, "@DeltaUI.lua")
end
check("DeltaUI 编译成功", fn ~= nil, tostring(cerr))

if fn then
    -- 常驻 UI：放到独立协程，主场景不被它的循环阻塞
    task.spawn(fn)
end

pump(2.0)                      -- 推进补间/入场/常驻循环

Snapshot("DeltaUI 渲染")

-- ---------- 结构断言 ----------
check("根 ScreenGui 存在", guiRoot() ~= nil)
check("实例数量可观 (>100)", countInstances() > 100, "count=" .. tostring(countInstances()))
check("存在 TextLabel", findFirstOfClass("TextLabel") ~= nil)
check("存在 TextButton", findFirstOfClass("TextButton") ~= nil)
check("存在 ScrollingFrame", findFirstOfClass("ScrollingFrame") ~= nil)

-- 控制台/列表类结构（DeltaUI 的编辑器与脚本列表）
check("存在 ImageLabel(图标)", findFirstOfClass("ImageLabel") ~= nil)
check("ScrollingFrame 数量 >= 2", (function()
    local n = 0
    for _, gl in ipairs(Vision.computeLayout()) do
        for _, e in ipairs(gl.entries) do
            if e.inst.ClassName == "ScrollingFrame" then n = n + 1 end
        end
    end
    return n >= 2
end)())

-- 关键节点（DeltaUI 自身命名，用于确认确实搭出了它的 UI）
check("存在悬浮球 DeltaUI_OrbFrame", findByName("DeltaUI_OrbFrame") ~= nil)
check("布局绘制条目数 (>200)", (function()
    local n = 0
    for _, gl in ipairs(Vision.computeLayout()) do n = n + #gl.entries end
    return n > 200
end)())

-- ---------- Delta 执行器环境特征（仅在 --delta-mode 下生效） ----------
if type(DeltaEnv) == "table" then
    local rep = DeltaEnv.report()
    check("Delta: apply 已安装", type(rep) == "table" and rep.mode ~= nil,
        "mode=" .. tostring(rep and rep.mode))
    check("Delta: _G 为空共享表或 nil",
        _G == nil or (type(_G) == "table" and next(_G) == nil))
    check("Delta: getgenv() 独立于 _G",
        type(getgenv) == "function" and getgenv() ~= _G)
    check("Delta: REAL_ENV 回落真实全局",
        type(getgenv) == "function" and getgenv().game ~= nil)
    -- DeltaUI 把整套 UI 状态写进它看到的 _G（= getfenv() = REAL_ENV）；
    -- 共享 _G 仍应为空，这正是「_G = 0 字段空共享表」的可观测证据。
    check("Delta: 库状态写入 getgenv 而非共享 _G",
        type(getgenv) == "function"
        and getgenv().__DeltaUI_screenGui ~= nil
        and (_G == nil or rawget(_G, "__DeltaUI_screenGui") == nil),
        "screenGui in genv=" .. tostring(type(getgenv) == "function"
            and getgenv().__DeltaUI_screenGui ~= nil))
    check("Delta: checkcaller 恒 true", type(checkcaller) == "function"
        and checkcaller() == true)
    check("Delta: typeof 识别 Instance",
        typeof(Instance.new("Frame")) == "Instance")
end

-- 健康度：允许「超出视口」类布局提示（真实库按更大屏幕设计），但不得有协程崩溃
local crash = nil
for _, e in ipairs(__HARNESS.errors) do
    if tostring(e):find("报错") then crash = e break end
end
check("运行期间无协程崩溃", crash == nil, tostring(crash))

__HARNESS.summary()
