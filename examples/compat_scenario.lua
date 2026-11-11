-- ==========================================
-- compat_scenario.lua — 无头运行时兼容性回归
-- ==========================================
-- 覆盖四项目标能力（这些曾需要调用方在场景里临时打补丁才能跑通真实 UI 库）：
--   1) Instance.new(className, parent) 双参数挂载（真实库普遍写法）
--   2) Color3:ToHSV() / Color3.fromHSV()（ColorPicker 依赖）
--   3) 内置 Lucide 离线桩自动注册（loadLucide 不再静默失败）
--   4) 未注册 HttpGet URL 被记录到 __MOCK.httpMisses（静默失败可诊断）
--
-- 运行：
--   python3 scripts/run_ui.py --scenario examples/compat_scenario.lua
--   python3 scripts/run_ui_luau.py --scenario examples/compat_scenario.lua --out /tmp/compat.png
--   （不需要任何 --lib；内置桩由 CLI 自动挂载）
-- ==========================================

-- 1) 双参数挂载
local holder = Instance.new("Folder")
holder.Name = "CompatHolder"
local frame = Instance.new("Frame", holder)
frame.Name = "ChildFrame"
check("Instance.new 双参数挂载到父级", frame.Parent == holder)
check("父级 GetChildren 含该子级", #holder:GetChildren() == 1
    and holder:GetChildren()[1] == frame)
local standalone = Instance.new("Frame")
check("Instance.new 单参数不设 Parent", standalone.Parent == nil)

-- 2) HSV 往返
local c = Color3.fromRGB(255, 96, 96)
local h, s, v = c:ToHSV()
local back = Color3.fromHSV(h, s, v)
local r2, g2, b2 = Color3.toRGB(back)
check("Color3:ToHSV 存在", type(c.ToHSV) == "function")
check("Color3.fromHSV 存在", type(Color3.fromHSV) == "function")
check("HSV 往返精度 <=1", math.abs(r2 - 255) <= 1 and math.abs(g2 - 96) <= 1
    and math.abs(b2 - 96) <= 1, string.format("got %d,%d,%d", r2, g2, b2))
check("纯红 ToHSV", (function()
    local rh, rs, rv = Color3.fromRGB(255, 0, 0):ToHSV()
    return math.abs(rh) < 0.001 and math.abs(rs - 1) < 0.001 and math.abs(rv - 1) < 0.001
end)())
-- 注意：真实 luau 解释器的内建 typeof() 会把 mock 的 Color3 值判为 "table"
-- （lupa 路径下 mock 自定义的 typeof 才返回 "Color3"）。故此处用与运行时无关的
-- 方式断言值类型标记，避免把两条执行路径的既有差异误报为回归。
check("Color3 值类型标记完好", rawget(c, "__color3") == true
    and type(c) == "table" and c.R ~= nil)

-- 3) 内置 Lucide 离线桩自动可用
local stubUrl = "https://gcore.jsdelivr.net/gh/WasKKal/DeltaExecutor-UI-Rebuild@lucide-v6/lucide/init.lua"
local src = game:HttpGet(stubUrl)
check("内置 Lucide 桩非空且够大", type(src) == "string" and #src > 5000,
    "len=" .. tostring(src and #src))
local mod = type(src) == "string" and loadstring(src)() or nil
check("Lucide 桩可加载且提供 GetAsset",
    type(mod) == "table" and type(mod.GetAsset) == "function")
local asset = type(mod) == "table" and mod.GetAsset("settings") or nil
check("Lucide 桩返回图标 URL", type(asset) == "table" and type(asset.Url) == "string"
    and asset.Url:find("settings", 1, true) ~= nil)

-- 4) 未注册 URL 被记录（诊断通道），且不影响 warnings 计数
local warnBefore = dumpWarnings()
local missing = game:HttpGet("https://example.invalid/not-registered-init.lua")
check("未注册 URL 返回空串", missing == "")
local misses = (__MOCK and __MOCK.httpMisses) or {}
local recorded = false
for _, u in ipairs(misses) do
    if u:find("not-registered-init.lua", 1, true) then recorded = true end
end
check("未注册 URL 被 httpMisses 记录", recorded)
check("httpMiss 不增加 warnings", dumpWarnings() == warnBefore)

-- 搭一个最小窗口，确认双参数挂载的子树能被布局引擎看见
local gui = Instance.new("ScreenGui")
gui.Name = "CompatGui"
local root = Instance.new("Frame", gui)
root.Name = "Root"
root.Size = UDim2.fromOffset(300, 180)
root.Position = UDim2.fromOffset(40, 40)
local label = Instance.new("TextLabel", root)
label.Name = "Caption"
label.Size = UDim2.fromOffset(240, 40)
label.Position = UDim2.fromOffset(20, 20)
label.Text = "Compat OK"
label.TextColor3 = Color3.new(1, 1, 1)
label.BackgroundTransparency = 1

pump(0.3)
Snapshot("compat regression")
check("双参数挂载的 ScreenGui 子树可见", findByName("Root") ~= nil
    and findByName("Caption") ~= nil)
check("运行期间无协程错误", #__HARNESS.errors == 0, table.concat(__HARNESS.errors, " | "))

__HARNESS.summary()
