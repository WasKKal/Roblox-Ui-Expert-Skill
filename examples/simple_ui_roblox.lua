--!nolint
-- ==========================================
-- simple_ui_roblox.lua — 真实环境执行版（与无头引擎逐项对比）
-- ==========================================
-- 用法：整段复制到 Roblox Studio（LocalScript）/ 或脚本执行器里执行一次。
-- 执行后会：
--   1) 真的把 UI 显示出来（可直接肉眼看效果）
--   2) 在控制台打印每个控件的 AbsolutePosition / AbsoluteSize（真实 Roblox 算出的绝对矩形）
--   3) 与无头引擎报告 engine_layout_report.txt 的「结构树」逐项对账
--
-- 对账要点：
--   · 除 Toast 外全部使用绝对像素定位（UDim2.new(0,x,0,y)），
--     因此坐标不随屏幕尺寸变化，可直接与引擎的 (x,y) WxH 对比。
--   · Toast 默认也锁成绝对定位（LOCK_800x600 = true），保证 100% 可逐项比对；
--     若想恢复常规「贴右下角」写法，把 LOCK_800x600 改成 false 即可。
--   · 引擎视口固定 800x600；如果你的屏幕不是 800x600，
--     Toast 在 LOCK_800x600=false 时会随视口变化，需用脚本打印的视口尺寸换算。
-- ==========================================

local LOCK_800x600 = true   -- true=Toast 也用绝对定位（与引擎完全一致）

-- ---------- 挂载点兼容：执行器 gethui() → PlayerGui → CoreGui ----------
local function getParent()
    local hui = rawget(_G, "gethui")
    if type(hui) == "function" then
        local ok, h = pcall(hui)
        if ok and h then return h, "gethui()" end
    end
    local Players = game:GetService("Players")
    local lp = Players and Players.LocalPlayer
    if lp then
        local ok, pg = pcall(function() return lp:WaitForChild("PlayerGui", 3) end)
        if ok and pg then return pg, "PlayerGui" end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg, "CoreGui" end
    error("找不到 UI 挂载点")
end

-- ---------- 主题 ----------
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

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

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

-- ---------- 搭界面（参数与无头引擎示例完全一致）----------

local parent, parentName = getParent()

local gui = Instance.new("ScreenGui")
gui.Name = "SimpleUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
gui.IgnoreGuiInset = true          -- 与无头引擎一致：坐标不含顶栏插边
gui.Parent = parent

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.BackgroundColor3 = THEME.Bg
backdrop.BackgroundTransparency = 0.25
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.Parent = gui

local main = Instance.new("Frame")
main.Name = "Main"
main.Position = UDim2.new(0, 120, 0, 90)
main.Size = UDim2.new(0, 560, 0, 420)
main.BackgroundColor3 = THEME.Panel
corner(main, 14)
stroke(main, THEME.Stroke, 2)
main.Parent = gui

local bar = Instance.new("Frame")
bar.Name = "TitleBar"
bar.Size = UDim2.new(1, 0, 0, 62)
bar.BackgroundColor3 = THEME.Accent
gradient(bar, THEME.Accent, THEME.Accent2, 0)
corner(bar, 14)
bar.Parent = main

local title = textLabel(bar, "Title", "SimpleUI 绘图自检", 20, THEME.Text)
title.Position = UDim2.new(0, 18, 0, 10)
title.Size = UDim2.new(1, -36, 0, 26)

local sub = textLabel(bar, "SubTitle", "圆角 · 描边 · 渐变 · 列表布局 · 开关 · 滑块 · 进度条 · Toast",
    13, Color3.fromRGB(226, 232, 245))
sub.Position = UDim2.new(0, 18, 0, 36)
sub.Size = UDim2.new(1, -36, 0, 18)

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.new(0, 14, 0, 74)
body.Size = UDim2.new(1, -28, 1, -88)
body.BackgroundTransparency = 1
body.Parent = main

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 8)
list.Parent = body

local rowCount = 0
local function newRow(name, height)
    rowCount = rowCount + 1
    local r = Instance.new("Frame")
    r.Name = name
    r.Size = UDim2.new(1, 0, 0, height or 46)
    r.BackgroundColor3 = THEME.Row
    r.LayoutOrder = rowCount
    corner(r, 9)
    stroke(r, THEME.Stroke, 1, 0.35)
    r.Parent = body
    return r
end

-- 1) 文字说明行
do
    local r = newRow("Row_Label", 40)
    local t = textLabel(r, "Text", "引擎绘制能力自检", 15, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 4)
    t.Size = UDim2.new(1, -28, 0, 20)
    local s = textLabel(r, "Sub", "以下控件均由无头引擎按 Roblox 布局规则算出绝对矩形", 12, THEME.SubText)
    s.Position = UDim2.new(0, 14, 0, 23)
    s.Size = UDim2.new(1, -28, 0, 15)
end

-- 2) 开关（开）
do
    local r = newRow("Row_Toggle", 44)
    local t = textLabel(r, "Text", "启用自动拾取", 15, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 0)
    t.Size = UDim2.new(0, 300, 1, 0)
    local track = Instance.new("Frame")
    track.Name = "ToggleTrack"
    track.Position = UDim2.new(1, -70, 0.5, -11)
    track.Size = UDim2.new(0, 46, 0, 22)
    track.BackgroundColor3 = THEME.Green
    corner(track, 11)
    track.Parent = r
    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = UDim2.new(1, -20, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(245, 247, 252)
    corner(knob, 9)
    knob.Parent = track
end

-- 3) 开关（关）
do
    local r = newRow("Row_Toggle", 44)
    local t = textLabel(r, "Text", "显示队友血条", 15, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 0)
    t.Size = UDim2.new(0, 300, 1, 0)
    local track = Instance.new("Frame")
    track.Name = "ToggleTrack"
    track.Position = UDim2.new(1, -70, 0.5, -11)
    track.Size = UDim2.new(0, 46, 0, 22)
    track.BackgroundColor3 = THEME.Track
    corner(track, 11)
    track.Parent = r
    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(245, 247, 252)
    corner(knob, 9)
    knob.Parent = track
end

-- 4) 滑块 65%
do
    local pct = 65
    local r = newRow("Row_Slider", 52)
    local t = textLabel(r, "Text", "移动速度", 15, THEME.Text)
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
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(pct / 100, 0, 1, 0)
    fill.BackgroundColor3 = THEME.Accent
    gradient(fill, THEME.Accent, THEME.Green, 0)
    corner(fill, 5)
    fill.Parent = track
end

-- 5) 进度条 78%
do
    local pct = 78
    local r = newRow("Row_Progress", 50)
    local t = textLabel(r, "Text", "资源加载进度", 14, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 5)
    t.Size = UDim2.new(0, 320, 0, 18)
    local track = Instance.new("Frame")
    track.Name = "Track"
    track.Position = UDim2.new(0, 14, 0, 28)
    track.Size = UDim2.new(1, -28, 0, 12)
    track.BackgroundColor3 = THEME.Track
    corner(track, 6)
    track.Parent = r
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(pct / 100, 0, 1, 0)
    fill.BackgroundColor3 = THEME.Green
    gradient(fill, THEME.Green, Color3.fromRGB(40, 170, 110), 0)
    corner(fill, 6)
    fill.Parent = track
end

-- 6) 分隔线
do
    rowCount = rowCount + 1
    local r = Instance.new("Frame")
    r.Name = "Separator"
    r.Size = UDim2.new(1, 0, 0, 2)
    r.BackgroundColor3 = THEME.Stroke
    r.BackgroundTransparency = 0.35
    r.LayoutOrder = rowCount
    r.Parent = body
end

-- 7) 按钮行
do
    local r = newRow("Row_Buttons", 46)
    local items = {
        { Text = "应用设置", Color = THEME.Accent },
        { Text = "恢复默认", Color = THEME.Red },
    }
    local n = #items
    local gap = 10
    for i, it in ipairs(items) do
        local b = Instance.new("TextButton")
        b.Name = "Button_" .. tostring(i)
        b.Text = it.Text
        b.TextSize = 14
        b.TextColor3 = Color3.fromRGB(250, 251, 254)
        b.Font = Enum.Font.Gotham
        b.Position = UDim2.new((1 / n) * (i - 1), (i == 1) and gap or (gap / 2), 0, 5)
        b.Size = UDim2.new(1 / n, -gap, 0, 36)
        b.BackgroundColor3 = it.Color
        corner(b, 8)
        stroke(b, THEME.Stroke, 1, 0.4)
        b.Parent = r
    end
end

-- 8) Toast
do
    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    if LOCK_800x600 then
        toast.Position = UDim2.new(0, 510, 0, 526)   -- 与引擎报告一致，便于逐项对账
    else
        toast.Position = UDim2.new(1, -290, 1, -74)  -- 常规贴右下角写法
    end
    toast.Size = UDim2.new(0, 270, 0, 46)
    toast.BackgroundColor3 = THEME.RowHigh
    corner(toast, 10)
    stroke(toast, THEME.Green, 2, 0.15)
    toast.ZIndex = 50
    toast.Parent = gui
    local t = textLabel(toast, "ToastText", "绘制自检完成", 14, THEME.Text)
    t.Position = UDim2.new(0, 14, 0, 0)
    t.Size = UDim2.new(1, -28, 1, 0)
    t.ZIndex = 51
end

-- ---------- 打印真实布局（与引擎报告对账）----------

local function hex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function walk(inst, depth)
    local pad = string.rep("    ", depth)
    if inst:IsA("GuiObject") then
        local p, s = inst.AbsolutePosition, inst.AbsoluteSize
        local extra = ""
        if inst:IsA("TextLabel") or inst:IsA("TextButton") then
            extra = string.format(' [text="%s" %dpx %s]', inst.Text, inst.TextSize, hex(inst.TextColor3))
        else
            extra = string.format(" [bg=%s(a=%.2f)]", hex(inst.BackgroundColor3),
                1 - (inst.BackgroundTransparency or 0))
        end
        print(string.format("%s%s \"%s\" (%d,%d) %dx%d%s",
            pad, inst.ClassName, inst.Name,
            math.floor(p.X + 0.5), math.floor(p.Y + 0.5),
            math.floor(s.X + 0.5), math.floor(s.Y + 0.5), extra))
    end
    for _, c in ipairs(inst:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UICorner")
            and not c:IsA("UIStroke") and not c:IsA("UIGradient") then
            walk(c, depth + 1)
        end
    end
end

-- 等一帧让 AbsolutePosition/AbsoluteSize 生效
if task and task.wait then task.wait(0.5) else wait(0.5) end

local cam = workspace.CurrentCamera
local vs = cam and cam.ViewportSize or Vector2.new(0, 0)
print("")
print("===== SimpleUI 真实布局（对账用）=====")
print(string.format("挂载点: %s   视口: %dx%d   Toast锁定800x600基准: %s",
    parentName, math.floor(vs.X), math.floor(vs.Y), tostring(LOCK_800x600)))
print("格式: 类名 \"名称\" (x,y) 宽x高  —— 与无头引擎报告的「结构树」逐项对比")
print("-------------------------------------")
walk(gui, 0)
print("-------------------------------------")
print("对账提示: Main 应为 (120,90) 560x420；TitleBar (120,90) 560x62；")
print("          ToggleTrack 开=(596,223) 46x22 / 关=(596,275) 46x22；")
print("          滑块 Fill (148,348) 328x10；进度 Fill (148,404) 393x12；")
print("          Button_1 (144,449) 256x36 / Button_2 (405,449) 256x36；")
print("          Toast (510,526) 270x46（LOCK_800x600=true 时）。")
