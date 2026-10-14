-- demo_scenario.lua — 演示场景：加载 demo_ui.lua → 建窗口 → 快照 → 断言 → 交互 → 再快照
-- 运行：
--   python3 scripts/run_ui.py \
--       --lib "https://mock.local/demo_ui.lua=examples/demo_ui.lua" \
--       --scenario examples/demo_scenario.lua

local DemoUI = loadstring(game:HttpGet("https://mock.local/demo_ui.lua"))()
assert(type(DemoUI) == "table" and type(DemoUI.new) == "function", "demo_ui.lua 加载失败")

local ui = DemoUI.new({ title = "DemoUI 控制面板" })

-- 等淡入动画结束（12 步 x 0.05s = 0.6s）
pump(0.8)

Snapshot("初始状态")

-- ---------- 结构断言 ----------
local main = findByName("Main")
check("Main 框架已创建", main ~= nil)

local mainRect = select(2, findByNameR("Main"))
check("Main 位置 (56,52)", mainRect and math.abs(mainRect.x - 56) < 0.51 and math.abs(mainRect.y - 52) < 0.51,
    mainRect and string.format("(%.0f,%.0f)", mainRect.x, mainRect.y))
check("Main 尺寸 688x468", mainRect and math.abs(mainRect.w - 688) < 0.51 and math.abs(mainRect.h - 468) < 0.51,
    mainRect and string.format("%.0fx%.0f", mainRect.w, mainRect.h))

local list = findByName("List")
check("滚动列表已创建", list ~= nil)

-- 淡入结束：Fader 组透明应为 0
local fader = findByName("Fader")
check("淡入完成 GroupTransparency=0", fader and math.abs(fader.GroupTransparency) < 0.01,
    fader and tostring(fader.GroupTransparency))

-- 滑杆填充宽度（Track 宽 = List 宽 688 + Size 偏移 -240 = 448；62% ≈ 277.8px）
-- 注意：Size 的 Scale 相对父级完整尺寸，不受 UIPadding 影响（Roblox 规则）
local rowB = findByName("List"):FindFirstChild("RowBrightness")
local fillB = rowB and rowB:FindFirstChild("Track") and rowB:FindFirstChild("Track"):FindFirstChild("Fill")
local fillRect = nil
for _, e in ipairs((Vision.computeLayout())[1].entries) do
    if e.inst == fillB then fillRect = e.rect end
end
check("亮度填充约 62%", fillRect ~= nil and math.abs(fillRect.w - 448 * 0.62) < 2,
    fillRect and string.format("w=%.1f 期望≈%.1f", fillRect.w, 448 * 0.62))

-- 状态栏初始文字
local status = findByName("Status")
check("初始状态文字=就绪", status and status.Text == "就绪", status and status.Text)

-- ---------- 交互：点击刷新 ----------
tapUI(findByName("BtnRefresh"))
pump(0.3)
Snapshot("点击刷新后")
local status2 = findByName("Status")
check("刷新后状态文字变化", status2 and status2.Text ~= "就绪" and status2.Text:find("已刷新", 1, true) ~= nil,
    status2 and status2.Text)

-- ---------- 交互：点击应用（Toast 出现，1.2s 后自动消失） ----------
tapUI(findByName("BtnApply"))
pump(0.2)
local toast = findByName("Toast")
check("Toast 已显示", toast and toast.Visible == true)
Snapshot("Toast 显示中")
pump(1.5)
local toast2 = findByName("Toast")
check("Toast 1.2s 后自动隐藏", toast2 and toast2.Visible == false)

-- ---------- 交互：开关按钮 ----------
tapUI(findByName("BtnToggle"))
pump(0.2)
local btnToggle = findByName("BtnToggle")
check("开关按钮文字切换", btnToggle and btnToggle.Text == "开关: 关", btnToggle and btnToggle.Text)
check("内部状态 enabled=false", ui.state.enabled == false)

-- ---------- 无错误收尾 ----------
checkEqual("mock 警告数为 0", #(__MOCK.warnings), 0)

print("")
print("场景执行完毕。")
