-- ==========================================
-- rich_scenario.lua — 富特性渲染自检场景
-- ==========================================
-- 加载 examples/rich_ui.lua，搭出覆盖全部渲染特性的窗口，打快照并做结构断言。
--
-- 文本报告（Agent 读）：
--   python3 scripts/run_ui.py \
--     --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
--     --scenario examples/rich_scenario.lua
--
-- 清晰 PNG / 可交互 HTML：
--   python3 scripts/run_ui_luau.py \
--     --lib "https://mock.local/rich_ui.lua=examples/rich_ui.lua" \
--     --scenario examples/rich_scenario.lua \
--     --out /workspace/rich.png --style both --scale 2
-- ==========================================

local Rich = loadstring(game:HttpGet("https://mock.local/rich_ui.lua"))()
check("rich_ui.lua 加载成功", type(Rich) == "table" and type(Rich.build) == "function")

local gui = Rich.build()
check("ScreenGui 已创建", type(gui) == "table" and gui.ClassName == "ScreenGui")

Snapshot("富特性渲染自检")

-- ---------- 结构断言 ----------
check("窗口存在", findByName("RichWindow") ~= nil)
check("标题文字存在", findByText("富特性渲染自检") ~= nil)
check("副标题存在", findByText("渐变 · 渐隐 · 描边 · 旋转 · 裁剪 · 组透明度") ~= nil)

-- 旋转徽标
local badge = findByName("Badge")
check("旋转徽标 Rotation=15", badge ~= nil and badge.Rotation == 15,
    badge and ("rot=" .. tostring(badge.Rotation)))

-- 顶部标题栏应有 UIGradient 子级
local header = findByName("Header")
local hasGrad = false
if header then
    for _, c in ipairs(header:GetChildren()) do
        if c.ClassName == "UIGradient" then hasGrad = true end
    end
end
check("标题栏含 UIGradient", hasGrad)

-- 底部渐隐条：UIGradient 带 Transparency NumberSequence
local fadeBar = findByName("FadeBar")
local hasFade = false
if fadeBar then
    for _, c in ipairs(fadeBar:GetChildren()) do
        if c.ClassName == "UIGradient" and c.Transparency ~= nil then hasFade = true end
    end
end
check("FadeBar 含透明度渐变", hasFade)

-- 裁剪
local content = findByName("Content")
check("内容区开启裁剪", content ~= nil and content.ClipsDescendants == true)

-- CanvasGroup 组透明度
local overlay = findByName("Overlay")
check("CanvasGroup 组透明度=0.25", overlay ~= nil and overlay.GroupTransparency == 0.25,
    overlay and ("gt=" .. tostring(overlay.GroupTransparency)))

-- 开关与进度条
check("开关轨道存在", findByName("ToggleTrack") ~= nil)
check("进度条填充存在", findByName("Fill") ~= nil)
check("图标存在", findByName("Icon") ~= nil)

-- 内容区行数
local rowCount = content and #content:GetChildren() or 0
check("内容区子级 >= 5", rowCount >= 5, "count=" .. tostring(rowCount))

-- 健康度
check("运行期间无协程错误", #__HARNESS.errors == 0, table.concat(__HARNESS.errors, " | "))
check("mock 警告数为 0", dumpWarnings() == 0)

__HARNESS.summary()
