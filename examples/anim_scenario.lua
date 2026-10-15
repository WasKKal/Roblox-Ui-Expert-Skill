-- ==========================================
-- anim_scenario.lua — 动效渲染自检场景
-- ==========================================
-- 加载 examples/anim_ui.lua，搭出带动效的卡片，pump 推进动画，做结构断言。
--
-- 文本报告：
--   python3 scripts/run_ui.py \
--     --lib "https://mock.local/anim_ui.lua=examples/anim_ui.lua" \
--     --scenario examples/anim_scenario.lua
--
-- 静态图 + 动画（APNG）+ 可交互 HTML（含时间轴播放器）：
--   python3 scripts/run_ui_luau.py \
--     --lib "https://mock.local/anim_ui.lua=examples/anim_ui.lua" \
--     --scenario examples/anim_scenario.lua \
--     --out /workspace/anim.png --style both --capture 0.1 --anim
-- ==========================================

local Anim = loadstring(game:HttpGet("https://mock.local/anim_ui.lua"))()
check("anim_ui.lua 加载成功", type(Anim) == "table" and type(Anim.build) == "function")

local gui = Anim.build({})
check("ScreenGui 已创建", type(gui) == "table" and gui.ClassName == "ScreenGui")

-- 推进动画（0.1s 后入场刚开始，1.2s 后进度条接近满，2.4s 后全部稳定）
pump(2.4)
Snapshot("动画结束态")

-- ── 结构断言 ────────────────────────────────────────────────────────────
check("卡片存在", findByName("Card") ~= nil)
check("标题栏存在", findByName("TitleBar") ~= nil)
check("进度条轨道存在", findByName("BarTrack") ~= nil)
check("进度条填充存在", findByName("BarFill") ~= nil)
check("脉冲圆点存在", findByName("Pulse") ~= nil)
check("三行列表齐全", findByName("Row1") ~= nil and findByName("Row2") ~= nil
    and findByName("Row3") ~= nil)
check("播放了补间动画", __MOCK.tweenLog and #__MOCK.tweenLog >= 5,
    "tweens=" .. tostring(__MOCK.tweenLog and #__MOCK.tweenLog))

-- 入场补间完成：卡片应回到居中且不透明
local card, crect = findByName("Card")
if card then
    local ga = 1 - (card.BackgroundTransparency or 0)
    check("卡片已完成淡入", ga > 0.95, "alpha=" .. tostring(ga))
end

-- 进度条填充已达到目标宽度（>60%）
local fill, frect = findByName("BarFill")
if fill and frect then
    local _, trect = findByName("BarTrack")
    if trect and trect.w > 0 then
        local ratio = frect.w / trect.w
        check("进度条已完成填充 (>0.6)", ratio > 0.6, string.format("ratio=%.2f", ratio))
    end
end

-- 图标元素（ImageLabel）数量
local imgs = 0
local function walk(n, d)
    if d > 8 or n == nil then return end
    for _, c in ipairs(n:GetChildren()) do
        if c.ClassName == "ImageLabel" or c.ClassName == "ImageButton" then
            imgs = imgs + 1
        end
        walk(c, d + 1)
    end
end
local root = guiRoot()
if root then walk(root, 0) end
check("图标元素 >= 6", imgs >= 6, "imgs=" .. tostring(imgs))
