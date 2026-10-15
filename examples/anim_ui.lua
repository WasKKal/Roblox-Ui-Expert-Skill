-- ============================================================================
-- anim_ui.lua — 动效示例 UI（用于展示 TweenService 真实插值 + 图标渲染）
--
-- 覆盖：
--   * 卡片入场：Position 滑入 + BackgroundTransparency 淡入（Quad/Out）
--   * 三个列表行【错开延迟】入场（TweenInfo.DelayTime）
--   * 进度条填充宽度补间（0 → 68%）
--   * 脉冲圆点：Heartbeat 逐帧驱动 Size / Transparency（正弦）
--   * 循环扫描条：Heartbeat 逐帧推进位置，越界回到起点
--   * 图标：ImageLabel + lucide 资源名（渲染器还原为矢量图标）
--
-- 语法：Lua 5.x 可编译子集，真机与 mock 双跑。
-- ============================================================================

local Anim = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local T = {
    Bg     = Color3.fromRGB(12, 14, 20),
    Card   = Color3.fromRGB(26, 30, 40),
    Row    = Color3.fromRGB(35, 40, 53),
    Text   = Color3.fromRGB(236, 241, 249),
    Sub    = Color3.fromRGB(150, 160, 180),
    A1     = Color3.fromRGB(59, 130, 246),
    A2     = Color3.fromRGB(168, 85, 247),
    Green  = Color3.fromRGB(52, 211, 153),
    Amber  = Color3.fromRGB(251, 191, 36),
    Line   = Color3.fromRGB(52, 58, 74),
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

local function gradient(o, c1, c2, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    g.Rotation = rot or 0
    g.Parent = o
end

-- 图标：ImageLabel + lucide 资源名（渲染器会还原成矢量图标）
local function iconOf(parent, name, px, col)
    local i = make("ImageLabel", {
        Name = "Icon_" .. name,
        Size = UDim2.new(0, px, 0, px),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "rbxasset://lucide-stub/" .. name,
        ImageColor3 = col or T.Text,
    })
    i.Parent = parent
    return i
end

-- 播放一段补间（delay 用于错开入场）
local function tween(inst, time, props, delay)
    local info = TweenInfo.new(time or 0.4, Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out, 0, false, delay or 0)
    local t = TweenService:Create(inst, info, props)
    t:Play()
    return t
end

function Anim.build(opts)
    opts = opts or {}
    local gui = make("ScreenGui", {
        Name = "AnimUI",
        ResetOnSpawn = false,
        DisplayOrder = 30,
    })
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    make("Frame", {
        Name = "Backdrop",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = T.Bg,
        BorderSizePixel = 0,
        Parent = gui,
    })

    -- ── 卡片：从上方滑入 + 淡入 ───────────────────────────────────────────
    local card = make("Frame", {
        Name = "Card",
        Size = UDim2.new(0, 420, 0, 320),
        Position = UDim2.new(0.5, 0, 0.42, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = T.Card,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = gui,
    })
    corner(card, 16)
    stroke(card, T.Line, 1.5)
    tween(card, 0.5, {
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundTransparency = 0,
    })

    -- ── 标题栏（渐变 + 图标）─────────────────────────────────────────────
    local bar = make("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundColor3 = T.A1,
        BorderSizePixel = 0,
        Parent = card,
    })
    corner(bar, 16)
    gradient(bar, T.A1, T.A2, 0)

    local bi = iconOf(bar, "sparkles", 20)
    bi.Position = UDim2.new(0, 18, 0.5, -10)

    make("TextLabel", {
        Name = "Title",
        Text = "动效渲染自检",
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        TextColor3 = T.Text,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -80, 1, 0),
        Position = UDim2.new(0, 48, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = bar,
    })

    -- 脉冲圆点（Heartbeat 逐帧驱动）
    local dot = make("Frame", {
        Name = "Pulse",
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(1, -34, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = T.Amber,
        BorderSizePixel = 0,
        Parent = bar,
    })
    corner(dot, 10)

    local acc = 0
    RunService.Heartbeat:Connect(function(dt)
        acc = acc + (dt or 0)
        local s = 0.5 + 0.5 * math.sin(acc * 4.2)
        local px = 12 + 9 * s
        dot.Size = UDim2.new(0, px, 0, px)
        dot.BackgroundTransparency = 0.55 - 0.45 * s
    end)

    -- ── 三个列表行：错开延迟入场 ─────────────────────────────────────────
    local rows = {
        { "terminal", "执行脚本" },
        { "package", "导入模块" },
        { "sliders", "偏好设置" },
    }
    for i, it in ipairs(rows) do
        local y = 76 + (i - 1) * 62
        local row = make("Frame", {
            Name = "Row" .. tostring(i),
            Size = UDim2.new(1, -32, 0, 54),
            Position = UDim2.new(0, -6, 0, y),      -- 入场起点：偏左
            BackgroundColor3 = T.Row,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = card,
        })
        corner(row, 10)

        local ri = iconOf(row, it[1], 18)
        ri.Position = UDim2.new(0, 14, 0.5, -9)

        make("TextLabel", {
            Name = "RowLabel" .. tostring(i),
            Text = it[2],
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = T.Text,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -60, 1, 0),
            Position = UDim2.new(0, 46, 0, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })

        local chev = iconOf(row, "chevron-right", 16, T.Sub)
        chev.Position = UDim2.new(1, -30, 0.5, -8)

        tween(row, 0.42, {
            Position = UDim2.new(0, 16, 0, y),
            BackgroundTransparency = 0,
        }, 0.12 + i * 0.12)                      -- 逐行错开
    end

    -- ── 进度条：填充宽度补间 ─────────────────────────────────────────────
    make("TextLabel", {
        Name = "BarCaption",
        Text = "载入进度",
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = T.Sub,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -32, 0, 18),
        Position = UDim2.new(0, 16, 0, 268),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    local track = make("Frame", {
        Name = "BarTrack",
        Size = UDim2.new(1, -32, 0, 10),
        Position = UDim2.new(0, 16, 0, 290),
        BackgroundColor3 = Color3.fromRGB(44, 49, 62),
        BorderSizePixel = 0,
        Parent = card,
    })
    corner(track, 5)

    local fill = make("Frame", {
        Name = "BarFill",
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = T.Green,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, 5)
    gradient(fill, T.Green, T.A1, 0)
    tween(fill, 1.2, { Size = UDim2.new(0.68, 0, 1, 0) }, 0.35)

    -- ── 循环扫描条：每帧推进，越界回到起点 ───────────────────────────────
    local scan = make("Frame", {
        Name = "Scan",
        Size = UDim2.new(0.28, 0, 0, 3),
        Position = UDim2.new(0, 16, 0, 306),
        BackgroundColor3 = T.A2,
        BorderSizePixel = 0,
        Parent = card,
    })
    corner(scan, 2)

    RunService.Heartbeat:Connect(function(dt)
        local x = scan.Position.X.Scale + (dt or 0) * 0.7
        if x > 0.72 then x = 0 end
        scan.Position = UDim2.new(x, 0, 0, 306)
    end)

    return gui
end

return Anim
