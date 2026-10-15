-- ============================================================================
-- rich_ui.lua — 富特性示例 UI（用于展示引擎「尽量贴近 Roblox」的渲染能力）
--
-- 覆盖：UIGradient 颜色渐变 · UIGradient.Transparency 渐隐 · TextStroke 文字描边 ·
--       Rotation 旋转 · ImageLabel 图标 · CanvasGroup 组透明度 · ClipsDescendants 裁剪 ·
--       UIListLayout 列表布局 · UICorner 多种圆角 · UIStroke 描边 · 阴影式面板
--
-- 语法：Lua 5.x 可编译子集（无 continue / += / 类型标注 / 字符串插值），
--       同一份代码既可跑真实 Roblox/Luau，也可跑进本 mock 运行时。
-- ============================================================================

local Rich = {}

local T = {
    Bg     = Color3.fromRGB(15, 17, 23),
    Panel  = Color3.fromRGB(24, 27, 36),
    Card   = Color3.fromRGB(31, 35, 46),
    Text   = Color3.fromRGB(233, 238, 246),
    Sub    = Color3.fromRGB(150, 159, 178),
    A1     = Color3.fromRGB(58, 132, 246),   -- 蓝
    A2     = Color3.fromRGB(149, 89, 246),   -- 紫
    Green  = Color3.fromRGB(52, 211, 153),
    Red    = Color3.fromRGB(244, 96, 96),
    Line   = Color3.fromRGB(58, 64, 80),
}

local function make(class, props)
    local i = Instance.new(class)
    if props then
        for k, v in pairs(props) do i[k] = v end
    end
    return i
end

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = o
end

local function stroke(o, col, th, tr)
    local s = Instance.new("UIStroke")
    s.Color = col
    s.Thickness = th
    s.Transparency = tr or 0
    s.Parent = o
end

-- 颜色渐变
local function gradient(o, c1, c2, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    g.Rotation = rot or 0
    g.Parent = o
end

-- 颜色 + 透明度渐变（沿轴渐隐）
local function fade(o, c1, c2)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    g.Parent = o
end

local function text(parent, s, size, color, xa, ya, bold)
    local l = make("TextLabel", {
        BackgroundTransparency = 1,
        Text = s,
        TextSize = size,
        TextColor3 = color,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = xa or Enum.TextXAlignment.Left,
        TextYAlignment = ya or Enum.TextYAlignment.Center,
        Size = UDim2.new(1, 0, 1, 0),
    })
    l.Parent = parent
    return l
end

-- 行容器（供 UIListLayout 排列）
local function row(parent, name, h)
    local f = make("Frame", {
        Name = name,
        Size = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = T.Card,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
    })
    corner(f, 10)
    stroke(f, T.Line, 1, 0.35)
    f.Parent = parent
    return f
end

-- 开关（绿色渐变 ON）
local function toggle(parent, on)
    local track = make("Frame", {
        Name = "ToggleTrack",
        Size = UDim2.new(0, 46, 0, 26),
        Position = UDim2.new(1, -58, 0.5, -13),
        BackgroundColor3 = on and T.Green or Color3.fromRGB(70, 76, 92),
        BorderSizePixel = 0,
    })
    corner(track, 13)
    if on then gradient(track, T.Green, Color3.fromRGB(34, 197, 150)) end
    track.Parent = parent
    local knob = make("Frame", {
        Name = "ToggleKnob",
        Size = UDim2.new(0, 20, 0, 20),
        Position = UDim2.new(0, on and 22 or 3, 0.5, -10),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
    })
    corner(knob, 10)
    stroke(knob, Color3.fromRGB(0, 0, 0), 1, 0.85)
    knob.Parent = track
end

-- 进度条（渐变填充 + 渐隐尾迹）——置于行底部，避免压住文字
local function bar(parent, pct, c1, c2)
    local track = make("Frame", {
        Name = "BarTrack",
        Size = UDim2.new(1, -28, 0, 8),
        Position = UDim2.new(0, 14, 1, -15),
        BackgroundColor3 = Color3.fromRGB(44, 49, 62),
        BorderSizePixel = 0,
    })
    corner(track, 4)
    track.Parent = parent
    local fill = make("Frame", {
        Name = "Fill",
        Size = UDim2.new(pct, 0, 1, 0),
        BackgroundColor3 = c1,
        BorderSizePixel = 0,
    })
    corner(fill, 4)
    gradient(fill, c1, c2)
    fill.Parent = track
end

function Rich.build()
    local gui = make("ScreenGui", { Name = "RichUI", ResetOnSpawn = false, DisplayOrder = 20 })
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- 全屏底色
    local bg = make("Frame", {
        Name = "Backdrop", Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = T.Bg, BackgroundTransparency = 0, BorderSizePixel = 0,
    })
    bg.Parent = gui

    -- 窗口
    local win = make("Frame", {
        Name = "RichWindow",
        Size = UDim2.new(0, 620, 0, 470),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = T.Panel, BorderSizePixel = 0,
    })
    corner(win, 18)
    stroke(win, T.Line, 2, 0.15)
    win.Parent = gui

    -- 顶部渐变标题栏（含旋转的 NEW 徽标）
    local header = make("Frame", {
        Name = "Header", Size = UDim2.new(1, 0, 0, 86),
        BackgroundColor3 = T.A1, BorderSizePixel = 0,
    })
    corner(header, 18)
    gradient(header, T.A1, T.A2, 0)
    header.Parent = win
    local ht = text(header, "富特性渲染自检", 24, Color3.fromRGB(255, 255, 255),
        Enum.TextXAlignment.Left, Enum.TextYAlignment.Center, true)
    ht.Position = UDim2.new(0, 22, 0, 20)
    ht.Size = UDim2.new(1, -140, 0, 30)
    ht.TextStrokeTransparency = 0.35
    ht.TextStrokeColor3 = Color3.fromRGB(20, 24, 40)
    local hs = text(header, "渐变 · 渐隐 · 描边 · 旋转 · 裁剪 · 组透明度",
        13, Color3.fromRGB(228, 232, 255), Enum.TextXAlignment.Left)
    hs.Position = UDim2.new(0, 22, 0, 50)
    hs.Size = UDim2.new(1, -140, 0, 18)

    -- 旋转徽标
    local badge = make("Frame", {
        Name = "Badge", Size = UDim2.new(0, 54, 0, 24),
        Position = UDim2.new(1, -78, 0, 14),
        BackgroundColor3 = T.Red, BorderSizePixel = 0, Rotation = 15,
    })
    corner(badge, 6)
    gradient(badge, Color3.fromRGB(255, 122, 122), T.Red)
    badge.Parent = header
    local bt = text(badge, "NEW", 12, Color3.fromRGB(255, 255, 255),
        Enum.TextXAlignment.Center, Enum.TextYAlignment.Center, true)
    bt.Parent = badge
    bt.Size = UDim2.new(1, 0, 1, 0)

    -- 底部渐隐分隔条（演示 UIGradient.Transparency）
    local fade1 = make("Frame", {
        Name = "FadeBar", Size = UDim2.new(1, -44, 0, 3),
        Position = UDim2.new(0, 22, 0, 86),
        BackgroundColor3 = Color3.fromRGB(120, 140, 255), BorderSizePixel = 0,
    })
    fade(fade1, Color3.fromRGB(120, 140, 255), Color3.fromRGB(120, 140, 255))
    fade1.Parent = win

    -- 裁剪的滚动内容区
    local scroll = make("ScrollingFrame", {
        Name = "Content", Size = UDim2.new(1, -44, 1, -124),
        Position = UDim2.new(0, 22, 0, 104),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 340),
        ClipsDescendants = true,
    })
    scroll.Parent = win
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 10)
    list.FillDirection = Enum.FillDirection.Vertical
    list.Parent = scroll

    -- 行 1：图标 + 文字 + 开关
    local r1 = row(scroll, "RowRadio", 46)
    local icon = make("ImageLabel", {
        Name = "Icon", Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(0, 12, 0.5, -12),
        BackgroundColor3 = T.A1, BackgroundTransparency = 0.1,
        Image = "rbxassetid://0", ImageColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
    })
    corner(icon, 6)
    icon.Parent = r1
    local t1 = text(r1, "实时高亮", 15, T.Text)
    t1.Position = UDim2.new(0, 46, 0, 0); t1.Size = UDim2.new(1, -120, 1, 0)
    toggle(r1, true)

    -- 行 2：文字 + 数值 + 渐变滑块
    local r2 = row(scroll, "RowSlider", 46)
    local t2 = text(r2, "渲染质量", 15, T.Text)
    t2.Position = UDim2.new(0, 14, 0, 6); t2.Size = UDim2.new(1, -120, 0, 20)
    local v2 = text(r2, "82%", 14, T.Sub, Enum.TextXAlignment.Right)
    v2.Position = UDim2.new(1, -70, 0, 6); v2.Size = UDim2.new(0, 56, 0, 20)
    bar(r2, 0.82, T.A1, T.A2)

    -- 行 3：文字 + 绿色进度条（渐隐）
    local r3 = row(scroll, "RowLoad", 46)
    local t3 = text(r3, "资源载入", 15, T.Text)
    t3.Position = UDim2.new(0, 14, 0, 6); t3.Size = UDim2.new(1, -120, 0, 20)
    bar(r3, 0.55, T.Green, Color3.fromRGB(120, 240, 200))

    -- 行 4：开关关闭态
    local r4 = row(scroll, "RowTeam", 46)
    local t4 = text(r4, "显示队友信息", 15, T.Text)
    t4.Position = UDim2.new(0, 14, 0, 0); t4.Size = UDim2.new(1, -120, 1, 0)
    toggle(r4, false)

    -- 右侧：CanvasGroup 半透明浮层（组透明度）
    local cg = make("CanvasGroup", {
        Name = "Overlay",
        Size = UDim2.new(0, 168, 0, 74),
        Position = UDim2.new(1, -190, 1, -96),
        BackgroundColor3 = Color3.fromRGB(12, 14, 20),
        BackgroundTransparency = 0.15, BorderSizePixel = 0,
        GroupTransparency = 0.25,
    })
    corner(cg, 14)
    stroke(cg, T.A1, 1.5, 0.2)
    cg.Parent = win
    local ct = text(cg, "CanvasGroup 半透明浮层", 13, T.Text,
        Enum.TextXAlignment.Center, Enum.TextYAlignment.Center)
    ct.Size = UDim2.new(1, -16, 1, 0)
    ct.Position = UDim2.new(0, 8, 0, 0)
    ct.TextWrapped = true

    return gui
end

return Rich
