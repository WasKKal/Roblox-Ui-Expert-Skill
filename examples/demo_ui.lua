-- demo_ui.lua — 自包含演示 UI 库（RobloxUi 开发专家 Skill 的示例靶子）
-- 用途：让 run_ui.py 无需真实 Roblox 也能渲染一个结构丰富的窗口：
--   圆角 / 描边 / 渐变填充 / 滚动列表 / UIListLayout / 开关 / 下拉胶囊 / Toast
-- 语法约束：Lua 5.x 可编译子集（无 continue / += / 字符串插值 / 类型标注）

local DemoUI = {}
DemoUI.__index = DemoUI

local THEME = {
    Page      = Color3.fromRGB(16, 18, 25),
    Panel     = Color3.fromRGB(30, 34, 46),
    PanelHigh = Color3.fromRGB(38, 43, 58),
    Stroke    = Color3.fromRGB(86, 96, 122),
    Text      = Color3.fromRGB(233, 236, 243),
    SubText   = Color3.fromRGB(146, 155, 175),
    Accent    = Color3.fromRGB(96, 165, 250),
    Track     = Color3.fromRGB(52, 58, 76),
    Green     = Color3.fromRGB(74, 222, 128),
}

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

local function label(parent, name, text, size, color)
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextSize = size or 14
    l.TextColor3 = color or THEME.Text
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Size = UDim2.new(1, 0, 0, (size or 14) * 1.5)
    l.Parent = parent
    return l
end

function DemoUI.new(opts)
    opts = opts or {}
    local self = setmetatable({}, DemoUI)
    self.state = { status = "就绪", brightness = 62, volume = 35, enabled = true, theme = "深色" }

    local gui = Instance.new("ScreenGui")
    gui.Name = "DemoUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 8
    self.gui = gui

    -- 外层 CanvasGroup：承担整体淡入
    local fader = Instance.new("CanvasGroup")
    fader.Name = "Fader"
    fader.GroupTransparency = 1
    fader.BackgroundTransparency = 1
    fader.Size = UDim2.new(1, 0, 1, 0)
    fader.Parent = gui
    self.fader = fader

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Position = UDim2.new(0, 56, 0, 52)
    main.Size = UDim2.new(0, 688, 0, 468)
    main.BackgroundColor3 = THEME.Panel
    main.BorderSizePixel = 0
    main.Parent = fader
    corner(main, 16)
    stroke(main, THEME.Stroke, 1.5, 0.4)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 18)
    pad.PaddingRight = UDim.new(0, 18)
    pad.PaddingTop = UDim.new(0, 14)
    pad.PaddingBottom = UDim.new(0, 14)
    pad.Parent = main
    self.main = main

    local titleLbl = label(main, "Title", opts.title or "DemoUI 控制面板", 22)
    titleLbl.Position = UDim2.new(0, 0, 0, 0)
    local subLbl = label(main, "Subtitle", "无头可视化演示 · 布局引擎 + ASCII/色彩网格", 13, THEME.SubText)
    subLbl.Position = UDim2.new(0, 0, 0, 34)

    -- 工具栏
    local toolbar = Instance.new("Frame")
    toolbar.Name = "Toolbar"
    toolbar.Position = UDim2.new(0, 0, 0, 64)
    toolbar.Size = UDim2.new(1, 0, 0, 34)
    toolbar.BackgroundTransparency = 1
    toolbar.Parent = main

    local function button(name, text, x, w)
        local b = Instance.new("TextButton")
        b.Name = name
        b.Position = UDim2.new(0, x, 0, 0)
        b.Size = UDim2.new(0, w, 1, 0)
        b.BackgroundColor3 = THEME.PanelHigh
        b.Text = text
        b.TextSize = 14
        b.TextColor3 = THEME.Text
        b.Font = Enum.Font.GothamMedium
        b.AutoButtonColor = true
        b.Parent = toolbar
        corner(b, 8)
        stroke(b, THEME.Stroke, 1, 0.55)
        return b
    end

    self.btnRefresh = button("BtnRefresh", "刷新状态", 0, 104)
    self.btnApply = button("BtnApply", "应用设置", 116, 104)
    self.btnToggle = button("BtnToggle", "开关: 开", 232, 104)

    -- 滚动列表（UIListLayout 管理子级）
    local list = Instance.new("ScrollingFrame")
    list.Name = "List"
    list.Position = UDim2.new(0, 0, 0, 110)
    list.Size = UDim2.new(1, 0, 1, -150)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.CanvasSize = UDim2.new(0, 0, 0, 4 * 62)
    list.ScrollBarThickness = 6
    list.ScrollingDirection = Enum.ScrollingDirection.Y
    list.Parent = main

    local lpad = Instance.new("UIPadding")
    lpad.PaddingLeft = UDim.new(0, 2)
    lpad.PaddingRight = UDim.new(0, 8)
    lpad.PaddingTop = UDim.new(0, 2)
    lpad.PaddingBottom = UDim.new(0, 2)
    lpad.Parent = list
    local ll = Instance.new("UIListLayout")
    ll.Padding = UDim.new(0, 10)
    ll.FillDirection = Enum.FillDirection.Vertical
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    ll.Parent = list

    local rowSeq = 0
    local function row(name, title)
        rowSeq = rowSeq + 1
        local r = Instance.new("Frame")
        r.Name = name
        r.Size = UDim2.new(1, 0, 0, 52)
        r.BackgroundColor3 = THEME.PanelHigh
        r.BorderSizePixel = 0
        r.LayoutOrder = rowSeq
        r.Parent = list
        corner(r, 10)
        label(r, "RowTitle", title, 14).Position = UDim2.new(0, 12, 0, 0)
        local t = r:FindFirstChild("RowTitle")
        t.Size = UDim2.new(0, 120, 1, 0)
        return r
    end

    -- 行1/行2：滑杆（填充带渐变，右侧更深）
    local function sliderRow(name, title, pct, key)
        local r = row(name, title)
        local track = Instance.new("Frame")
        track.Name = "Track"
        track.Position = UDim2.new(0, 140, 0.5, -6)
        track.Size = UDim2.new(1, -240, 0, 12)
        track.BackgroundColor3 = THEME.Track
        track.BorderSizePixel = 0
        track.Parent = r
        corner(track, 6)
        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.new(pct / 100, 0, 1, 0)
        fill.BackgroundColor3 = THEME.Accent
        fill.BorderSizePixel = 0
        fill.Parent = track
        corner(fill, 6)
        local grad = Instance.new("UIGradient")
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.Accent),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 64, 175)),
        })
        grad.Parent = fill
        local v = label(r, "Value", tostring(pct) .. "%", 13, THEME.SubText)
        v.Position = UDim2.new(1, -70, 0, 0)
        v.Size = UDim2.new(0, 70, 1, 0)
        v.TextXAlignment = Enum.TextXAlignment.Right
        self[key] = pct
        return r
    end

    sliderRow("RowBrightness", "亮度", 62, "brightness")
    sliderRow("RowVolume", "音量", 35, "volume")

    -- 行3：开关
    do
        local r = row("RowSwitch", "开关")
        local bg = Instance.new("Frame")
        bg.Name = "ToggleBg"
        bg.Position = UDim2.new(0, 140, 0.5, -12)
        bg.Size = UDim2.new(0, 52, 0, 24)
        bg.BackgroundColor3 = THEME.Green
        bg.BorderSizePixel = 0
        bg.Parent = r
        corner(bg, 12)
        local knob = Instance.new("Frame")
        knob.Name = "Knob"
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(1, -16, 0.5, 0)
        knob.Size = UDim2.new(0, 18, 0, 18)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel = 0
        knob.Parent = bg
        corner(knob, 9)
        local v = label(r, "Value", "开", 13, THEME.Green)
        v.Position = UDim2.new(1, -70, 0, 0)
        v.Size = UDim2.new(0, 70, 1, 0)
        v.TextXAlignment = Enum.TextXAlignment.Right
    end

    -- 行4：下拉胶囊（收起态）
    do
        local r = row("RowTheme", "主题")
        local dd = Instance.new("TextButton")
        dd.Name = "Dropdown"
        dd.Position = UDim2.new(0, 140, 0.5, -14)
        dd.Size = UDim2.new(0, 150, 0, 28)
        dd.BackgroundColor3 = THEME.Track
        dd.Text = "  深色 ▾"
        dd.TextSize = 13
        dd.TextColor3 = THEME.Text
        dd.Font = Enum.Font.Gotham
        dd.TextXAlignment = Enum.TextXAlignment.Left
        dd.Parent = r
        corner(dd, 14)
        stroke(dd, THEME.Stroke, 1, 0.4)
    end

    -- 状态栏
    local bar = Instance.new("Frame")
    bar.Name = "StatusBar"
    bar.Position = UDim2.new(0, 0, 1, -44)
    bar.Size = UDim2.new(1, 0, 0, 30)
    bar.BackgroundColor3 = THEME.Page
    bar.BorderSizePixel = 0
    bar.Parent = main
    corner(bar, 8)
    self.statusLabel = label(bar, "Status", "就绪", 13, THEME.SubText)
    self.statusLabel.Position = UDim2.new(0, 10, 0, 0)
    self.statusLabel.Size = UDim2.new(1, -20, 1, 0)

    -- Toast（默认隐藏）
    local toast = Instance.new("TextLabel")
    toast.Name = "Toast"
    toast.AnchorPoint = Vector2.new(0.5, 0)
    toast.Position = UDim2.new(0.5, 0, 1, -104)
    toast.Size = UDim2.new(0, 220, 0, 34)
    toast.BackgroundColor3 = THEME.PanelHigh
    toast.Text = "已保存"
    toast.TextSize = 13
    toast.TextColor3 = THEME.Text
    toast.Font = Enum.Font.GothamMedium
    toast.Visible = false
    toast.Parent = main
    corner(toast, 10)
    stroke(toast, THEME.Green, 1, 0.3)
    self.toast = toast

    -- 交互
    self.btnRefresh.MouseButton1Click:Connect(function()
        self.state.status = "已刷新 @" .. tostring(math.floor(vclockNow() * 10) / 10) .. "s"
        self.statusLabel.Text = self.state.status
    end)
    self.btnApply.MouseButton1Click:Connect(function()
        self.state.status = "设置已应用"
        self.statusLabel.Text = self.state.status
        self.toast.Visible = true
        task.delay(1.2, function()
            self.toast.Visible = false
        end)
    end)
    self.btnToggle.MouseButton1Click:Connect(function()
        self.state.enabled = not self.state.enabled
        self.btnToggle.Text = "开关: " .. (self.state.enabled and "开" or "关")
    end)

    -- 淡入动画（协程 + task.wait，驱动虚拟时钟）
    task.spawn(function()
        local steps = 12
        for i = 1, steps do
            fader.GroupTransparency = 1 - i / steps
            task.wait(0.05)
        end
        fader.GroupTransparency = 0
    end)

    gui.Parent = game:GetService("Players").LocalPlayer.PlayerGui
    return self
end

function DemoUI:setStatus(text)
    self.state.status = text
    self.statusLabel.Text = text
end

function DemoUI:destroy()
    self.gui:Destroy()
end

return DemoUI
