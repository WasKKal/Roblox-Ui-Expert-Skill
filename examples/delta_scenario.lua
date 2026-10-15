-- ==========================================
-- delta_scenario.lua — DeltaUI 真实库渲染自检
-- ==========================================
-- DeltaUI 是「执行即建 UI + 常驻循环」的真实库：
--   · 加载执行其顶层代码会直接搭出整套界面；
--   · 顶层末尾进入常驻等待（不会返回），故用 task.spawn 让它跑在独立协程，
--     主场景继续 pump 推进并做断言。
--
-- lupa（Lua 5.5）路径：
--   python3 scripts/run_ui.py \
--     --lib "https://mock.local/DeltaUI.lua=/root/uploads/1791642772656330982-DeltaUI.lua.txt" \
--     --scenario examples/delta_scenario.lua --viewport 1280x800 --max-seconds 40
--
-- 真实 luau 路径 + PNG/HTML：
--   python3 scripts/run_ui_luau.py \
--     --lib "https://mock.local/DeltaUI.lua=/root/uploads/1791642772656330982-DeltaUI.lua.txt" \
--     --scenario examples/delta_scenario.lua --viewport 1280x800 --style both --scale 2
-- ==========================================

local URL = "https://mock.local/DeltaUI.lua"

local okFetch, src = pcall(function() return game:HttpGet(URL) end)
check("HttpGet 取到源码", okFetch and type(src) == "string" and #src > 1000,
    "len=" .. tostring(src and #src))

-- 兼容 shim：DeltaUI 有大量 `_G.xxx = ...` 写入。真实 luau CLI 的 `_G` 是只读表，
-- 但 getfenv() 返回的正是同一个"可写默认全局环境"。故前置一行把库内的 _G 绑到它
-- （lupa 下 mock 的 getfenv() 返回 _G，同样成立；两种运行时均无害）。
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

-- 健康度：允许「超出视口」类布局提示（真实库按更大屏幕设计），但不得有协程崩溃
local crash = nil
for _, e in ipairs(__HARNESS.errors) do
    if tostring(e):find("报错") then crash = e break end
end
check("运行期间无协程崩溃", crash == nil, tostring(crash))

__HARNESS.summary()
