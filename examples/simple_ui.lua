-- ==========================================
-- simple_ui.lua — 简易 UI 库（引擎绘图测试靶子）
-- ==========================================
-- 用途：用最少的代码搭一个视觉元素丰富的窗口，用来检验无头引擎的绘制效果，
--       并可由 scripts/render_png.py 导出为 PNG 直接查看。
--
-- 覆盖的绘制能力：
--   ScreenGui / CanvasGroup 分层 · Frame 圆角 · UIStroke 描边 · UIGradient 渐变
--   UIListLayout 自动排列 · TextLabel 文字 · 开关滑块 · 进度条 · 按钮 · Toast
--
-- 语法约束：Lua 5.x 可编译子集（无 continue / += / 类型标注 / 字符串插值），
--           以便同一份代码既能跑在真实 Roblox/Luau，也能跑进本 mock 运行时。
-- ==========================================

local SimpleUI = {}
SimpleUI.__index = SimpleUI

local THEME = {
    Bg        = Color3.fromRGB(13, 15, 21),
    Panel     = Color3.fromRGB(26, 30, 40),
    Row       = Color3.fromRGB(32, 37, 50),
    RowHigh   = Color3.fromRGB(40, 46, 62),
    Stroke    = Color3.fromRGB(74, 84, 108),
    Text      = Color3.fromRGB(236, 239, 246),
    SubText   = Color3.fromRGB(150, 159, 178),
    Accent    = Color3.fromRGB(88, 150, 255),
    Accent2   = Color3.fromRGB(158, 96, 255),
    Green     = Color3.fromRGB(66, 216, 130),
    Red       = Color3.fromRGB(238, 92, 104),
    Track     = Color3.fromRGB(48, 54, 72),
}

-- ---------- 通用小工具 ----------

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or THEME.Stroke
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
    return s
end

local function gradient(parent, c1, c2, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    g.Rotation = rotation or 0
    g.Parent = parent
    return g
end

local function textLabel(parent, name, txt, size, color, align)
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Text = txt or ""
    l.TextSize = size or 14
    l.TextColor3 = color or THEME.Text
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Size = UDim2.new(1, 0, 0, (size or 14) * 1.5)
    l.Parent = parent
    return l
end

-- ---------- 构建窗口 ----------

function SimpleUI.new(opts)
    opts = opts or {}
    local self = setmetatable({}, SimpleUI)
    self.rows = 0

    local gui = Instance.new("ScreenGui")
    gui.Name = "SimpleUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 10
    self.gui = gui

    -- 底层深色背景（让半透明区域有参照）
    local backdrop = Instance.new("Frame")
    backdrop.Name = "Backdrop"
    backdrop.BackgroundColor3 = THEME.Bg
    backdrop.BackgroundTransparency = 0.25
    backdrop.Size = UDim2.new(1, 0, 1, 0)
    backdrop.Parent = gui

    -- 主面板：居中 560x420
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Position = UDim2.new(0, 120, 0, 90)
    main.Size = UDim2.new(0, 560, 0, 420)
    main.BackgroundColor3 = THEME.Panel
    corner(main, 14)
    stroke(main, THEME.Stroke, 2)
    main.Parent = gui
    self.main = main

    -- 标题栏：蓝→紫渐变
    local bar = Instance.new("Frame")
    bar.Name = "TitleBar"
    bar.Size = UDim2.new(1, 0, 0, 62)
    bar.BackgroundColor3 = THEME.Accent
    gradient(bar, THEME.Accent, THEME.Accent2, 0)
    corner(bar, 14)
    bar.Parent = main
    self.bar = bar

    local title = textLabel(bar, "Title", opts.Title or "SimpleUI 演示面板", 20, THEME.Text)
    title.Position = UDim2.new(0, 18, 0, 10)
    title.Size = UDim2.new(1, -36, 0, 26)

    local sub = textLabel(bar, "SubTitle", opts.Info or "引擎绘图能力自检 · 圆角/描边/渐变/布局", 13, Color3.fromRGB(226, 232, 245))
    sub.Position = UDim2.new(0, 18, 0, 36)
    sub.Size = UDim2.new(1, -36, 0, 18)

    -- 内容区：UIListLayout 自动往下排
    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Position = UDim2.new(0, 14, 0, 74)
    body.Size = UDim2.new(1, -28, 1, -88)
    body.BackgroundTransparency = 1
    body.Parent = main
    self.body = body

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.Parent = body

    return self
end

-- 新增一行容器（高度 height，背景圆角 + 描边）
function SimpleUI:_row(name, height)
    self.rows = self.rows + 1
    local r = Instance.new("Frame")
    r.Name = name
    r.Size = UDim2.new(1, 0, 0, height or 46)
    r.BackgroundColor3 = THEME.Row
    r.LayoutOrder = self.rows
    corner(r, 9)
    stroke(r, THEME.Stroke, 1, 0.35)
    r.Parent = self.body
    return r
end

-- ---------- 控件 ----------

-- 纯文字说明行
function SimpleUI:AddLabel(text, sub)
    local r = self:_row("Row_Label", 40)
    local t = textLabel(r, "Text", text or "", 15, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 4)
    t.Size = UDim2.new(1, -28, 0, 20)
    if sub then
        local s = textLabel(r, "Sub", sub, 12, THEME.SubText)
        s.Position = UDim2.new(0, 14, 0, 23)
        s.Size = UDim2.new(1, -28, 0, 15)
    end
    return r
end

-- 分隔线
function SimpleUI:AddSeparator()
    self.rows = self.rows + 1
    local r = Instance.new("Frame")
    r.Name = "Separator"
    r.Size = UDim2.new(1, 0, 0, 2)
    r.BackgroundColor3 = THEME.Stroke
    r.BackgroundTransparency = 0.35
    r.LayoutOrder = self.rows
    r.Parent = self.body
    return r
end

-- 开关：轨道 + 圆滑块（右侧=开）
function SimpleUI:AddToggle(text, default)
    local r = self:_row("Row_Toggle", 44)
    local t = textLabel(r, "Text", text or "开关", 15, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 0)
    t.Size = UDim2.new(0, 300, 1, 0)

    local track = Instance.new("Frame")
    track.Name = "ToggleTrack"
    track.Position = UDim2.new(1, -70, 0.5, -11)
    track.Size = UDim2.new(0, 46, 0, 22)
    track.BackgroundColor3 = default and THEME.Green or THEME.Track
    corner(track, 11)
    track.Parent = r

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = default and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(245, 247, 252)
    corner(knob, 9)
    knob.Parent = track

    return r
end

-- 滑块：轨道 + 渐变填充 + 百分比
function SimpleUI:AddSlider(text, pct)
    pct = math.clamp(pct or 0, 0, 100)
    local r = self:_row("Row_Slider", 52)
    local t = textLabel(r, "Text", text or "滑块", 15, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 6)
    t.Size = UDim2.new(0, 320, 0, 20)

    local val = textLabel(r, "Value", tostring(pct) .. "%", 14, THEME.SubText, Enum.TextXAlignment.Right)
    val.Position = UDim2.new(1, -108, 0, 6)
    val.Size = UDim2.new(0, 94, 0, 20)

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.Position = UDim2.new(0, 14, 0, 32)
    track.Size = UDim2.new(1, -28, 0, 10)
    track.BackgroundColor3 = THEME.Track
    corner(track, 5)
    track.Parent = r

    if pct > 0 then
        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.new(pct / 100, 0, 1, 0)
        fill.BackgroundColor3 = THEME.Accent
        gradient(fill, THEME.Accent, THEME.Green, 0)
        corner(fill, 5)
        fill.Parent = track
    end
    return r
end

-- 进度条
function SimpleUI:AddProgress(text, pct)
    pct = math.clamp(pct or 0, 0, 100)
    local r = self:_row("Row_Progress", 50)
    local t = textLabel(r, "Text", text or "进度", 14, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 5)
    t.Size = UDim2.new(0, 320, 0, 18)

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.Position = UDim2.new(0, 14, 0, 28)
    track.Size = UDim2.new(1, -28, 0, 12)
    track.BackgroundColor3 = THEME.Track
    corner(track, 6)
    track.Parent = r

    if pct > 0 then
        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.new(pct / 100, 0, 1, 0)
        fill.BackgroundColor3 = THEME.Green
        gradient(fill, THEME.Green, Color3.fromRGB(40, 170, 110), 0)
        corner(fill, 6)
        fill.Parent = track
    end
    return r
end

-- 按钮行：可放 1~2 个按钮
function SimpleUI:AddButtons(items)
    local r = self:_row("Row_Buttons", 46)
    local n = math.max(1, #items)
    local gap = 10
    local w = (1 / n)
    for i, it in ipairs(items) do
        local b = Instance.new("TextButton")
        b.Name = "Button_" .. tostring(i)
        b.Text = it.Text or "按钮"
        b.TextSize = 14
        b.TextColor3 = Color3.fromRGB(250, 251, 254)
        b.Font = Enum.Font.Gotham
        b.Position = UDim2.new(w * (i - 1), (i == 1) and gap or (gap / 2), 0, 5)
        b.Size = UDim2.new(w, -gap, 0, 36)
        b.BackgroundColor3 = it.Color or THEME.Accent
        corner(b, 8)
        stroke(b, THEME.Stroke, 1, 0.4)
        b.Parent = r
    end
    return r
end

-- Toast 提示（右下角浮层）
function SimpleUI:ShowNotify(text)
    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    toast.Position = UDim2.new(1, -290, 1, -74)
    toast.Size = UDim2.new(0, 270, 0, 46)
    toast.BackgroundColor3 = THEME.RowHigh
    corner(toast, 10)
    stroke(toast, THEME.Green, 2, 0.15)
    toast.ZIndex = 50
    toast.Parent = self.gui

    local t = textLabel(toast, "ToastText", text or "", 14, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 0)
    t.Size = UDim2.new(1, -28, 1, 0)
    t.ZIndex = 51
    return toast
end

return SimpleUI
