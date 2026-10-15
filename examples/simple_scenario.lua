-- ==========================================
-- simple_scenario.lua — 简易 UI 绘图自检场景
-- ==========================================
-- 用途：加载 examples/simple_ui.lua，搭出一个视觉元素丰富的窗口，
--       打一张快照做基础结构断言。
--
-- 文本报告（Agent 读）：
--   python3 scripts/run_ui.py \
--     --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
--     --scenario examples/simple_scenario.lua
--
-- PNG 图片（人看）：
--   python3 scripts/run_ui_luau.py \
--     --lib "https://mock.local/simple_ui.lua=examples/simple_ui.lua" \
--     --scenario examples/simple_scenario.lua \
--     --out /workspace/simple_ui_render.png
-- ==========================================

local SimpleUI = loadstring(game:HttpGet("https://mock.local/simple_ui.lua"))()
check("simple_ui.lua 加载成功", type(SimpleUI) == "table" and type(SimpleUI.new) == "function")

local ui = SimpleUI.new({
    Title = "SimpleUI 绘图自检",
    Info = "圆角 · 描边 · 渐变 · 列表布局 · 开关 · 滑块 · 进度条 · Toast",
})
check("窗口对象已创建", type(ui) == "table" and type(ui.gui) == "table")

-- 搭界面
ui:AddLabel("引擎绘制能力自检", "以下控件均由无头引擎按 Roblox 布局规则算出绝对矩形")
ui:AddToggle("启用自动拾取", true)
ui:AddToggle("显示队友血条", false)
ui:AddSlider("移动速度", 65)
ui:AddProgress("资源加载进度", 78)
ui:AddSeparator()
ui:AddButtons({
    { Text = "应用设置", Color = Color3.fromRGB(88, 150, 255) },
    { Text = "恢复默认", Color = Color3.fromRGB(238, 92, 104) },
})
ui:ShowNotify("绘制自检完成")

-- 快照（PNG 导出取的就是这一帧）
Snapshot("SimpleUI 绘图自检")

-- ---------- 结构断言 ----------
local main = findByName("Main")
check("Main 面板已创建", main ~= nil)

local mainRect = select(2, findByNameR("Main"))
check("Main 位置 (120,90)", mainRect and math.abs(mainRect.x - 120) < 0.51
    and math.abs(mainRect.y - 90) < 0.51,
    mainRect and string.format("(%.0f,%.0f)", mainRect.x, mainRect.y))
check("Main 尺寸 560x420", mainRect and math.abs(mainRect.w - 560) < 0.51
    and math.abs(mainRect.h - 420) < 0.51,
    mainRect and string.format("%.0fx%.0f", mainRect.w, mainRect.h))

check("标题栏存在", findByName("TitleBar") ~= nil)
check("Toast 已创建", findByName("Toast") ~= nil)
check("滑块轨道存在", findByName("Track") ~= nil)
check("开关轨道存在", findByName("ToggleTrack") ~= nil)
check("分隔线存在", findByName("Separator") ~= nil)

-- 行数：正文区应有 8 个子级（6 行 + 分隔线 + 按钮行）
local body = findByName("Body")
local bodyCount = body and #body:GetChildren() or 0
check("Body 挂载控件行数 >= 7", bodyCount >= 7, "count=" .. tostring(bodyCount))

-- 健康度
check("运行期间无协程错误", #__HARNESS.errors == 0, table.concat(__HARNESS.errors, " | "))
check("mock 警告数为 0", dumpWarnings() == 0)

__HARNESS.summary()
