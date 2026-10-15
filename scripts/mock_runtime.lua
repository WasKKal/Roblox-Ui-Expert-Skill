-- ============================================================================
-- mock_runtime.lua —— Roblox UI 无头 mock 运行时（Lua 5.x / lupa）
--
-- 目标：让 Agent 通过执行 Luau/Lua 代码「看到」UI 画面。
-- 本文件模拟 Roblox 客户端 UI 相关的全部基础设施：
--   * Instance 树（Frame/TextLabel/TextButton/ImageLabel/ScrollingFrame/
--     ScreenGui/UICorner/UIStroke/UIGradient/UIPadding/UIListLayout/CanvasGroup...）
--   * 值类型（UDim/UDim2/Vector2/Vector3/Color3/ColorSequence/NumberSequence/TweenInfo）
--   * Enum 常量表
--   * TweenService（Play 立即应用目标属性，记录 tweenLog）
--   * game / 各 Service（Players/RunService/UserInputService/HttpService/TextService...）
--   * task 调度器 + 虚拟时钟（task.spawn/wait/delay，pumpSeconds 推进）
--   * 输入模拟（fireInput/tap/mkInput，InputObject.Changed）
--   * 执行器文件系统（isfile/readfile/writefile/isfolder/makefolder/getgenv/loadstring）
--   * typeof / IsA / 属性变更信号
--
-- 布局与渲染不在这里——见 vision.lua。
-- ============================================================================

local M = {}
__MOCK = M   -- 裸全局导出（lupa 下写入 _G；luau 下写入共享默认环境）

M.warnings = {}
function M.warn(msg)
    M.warnings[#M.warnings + 1] = tostring(msg)
end

-- ----------------------------------------------------------------------------
-- Luau 内建兼容层（Lua 5.x 缺失，但 Luau 脚本/模块普遍使用）
-- ----------------------------------------------------------------------------
-- 安全设置库表字段：luau CLI 把 math/string/coroutine/table 等标准库表设为【只读表】
-- （原生已带大部分函数），直接赋值会抛 "attempt to modify a readonly table"。
-- 用 rawget 判缺失 + pcall 包裹写入：缺失才设置、设置失败则跳过。
-- lupa（Lua 5.x）下这些表可写，正常补上 shim。
local function safeSet(lib, k, v)
    if rawget(lib, k) == nil then
        pcall(function() lib[k] = v end)
    end
end
safeSet(table, "freeze", function(t) return t end)
safeSet(table, "clone", function(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    local mt = getmetatable(t)
    if mt then setmetatable(c, mt) end
    return c
end)
safeSet(table, "move", function(a1, f, e, t, a2)
    a2 = a2 or a1
    if e >= f then
        if t > f and t <= e and a1 == a2 then
            for i = e - f, 0, -1 do a2[t + i] = a1[f + i] end
        else
            for i = 0, e - f do a2[t + i] = a1[f + i] end
        end
    end
    return a2
end)
safeSet(math, "round", function(x) return math.floor(x + 0.5) end)
safeSet(math, "clamp", function(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end)
safeSet(coroutine, "close", function(co)
    if coroutine.status(co) == "dead" then return true end
    return false
end)
safeSet(string, "split", function(s, sep)
    sep = sep or ","
    local out = {}
    if s == nil then return out end
    if sep == "" then out[#out + 1] = s return out end
    local plain = true
    for i = 1, #sep do
        local ch = sep:sub(i, i)
        if ch:match("[%^%$%(%)%%%.%[%]%*%+%-%?]") then plain = false break end
    end
    local pattern
    if plain then pattern = sep else pattern = sep:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") end
    local start = 1
    while true do
        local f, e = s:find(pattern, start)
        if not f then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, f - 1)
        start = e + 1
    end
    return out
end)

-- 遗留/执行器全局：Luau 原生自带（unpack/getfenv/setfenv/newproxy/table.getn），
-- 而 Lua 5.4+ 已移除。仅在缺失时补齐（避免覆盖 Luau 原生实现）。
if type(unpack) ~= "function" then unpack = table.unpack end
if type(getfenv) ~= "function" then
    getfenv = function(_) return _G end          -- lupa 下 _G 即可写全局环境
end
if type(setfenv) ~= "function" then
    setfenv = function(f, _) return f end        -- 近似：不改环境，直接返回
end
if type(newproxy) ~= "function" then
    newproxy = function() return {} end
end
safeSet(table, "getn", function(t) return #t end)

-- task 调度器状态（前向声明，供 Signal:Wait 直接入队）
local queue, vclock

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ============================================================================
-- 值类型
-- ============================================================================

local function marker(t, name)
    rawset(t, "__" .. name, true)
    return t
end

UDim = {}
function UDim.new(scale, offset)
    return marker({ Scale = scale or 0, Offset = offset or 0 }, "udim")
end

UDim2 = {}
function UDim2.new(sx, ox, sy, oy)
    return marker({ X = UDim.new(sx, ox), Y = UDim.new(sy, oy) }, "udim2")
end
function UDim2.fromScale(x, y) return UDim2.new(x or 0, 0, y or 0, 0) end
function UDim2.fromOffset(x, y) return UDim2.new(0, x or 0, 0, y or 0) end

Vector2 = {}
function Vector2.new(x, y)
    return marker({ X = x or 0, Y = y or 0 }, "vector2")
end

Vector3 = {}
function Vector3.new(x, y, z)
    return marker({ X = x or 0, Y = y or 0, Z = z or 0 }, "vector3")
end

Color3 = {}
function Color3.new(r, g, b)
    return marker({ R = r or 0, G = g or 0, B = b or 0 }, "color3")
end
function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.toRGB(c)
    return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
end
function Color3.lerp(a, b, t)
    return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(time, color)
    -- 真机字段为 .Value，同时挂 .Color 别名兼容两种写法
    return { Time = time or 0, Value = color, Color = color }
end

NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(time, value)
    return { Time = time or 0, Value = value or 0 }
end

ColorSequence = {}
function ColorSequence.new(...)
    local kps = ...
    if type(kps) ~= "table" then kps = { ... } end
    return marker({ __cs = true, keypoints = kps }, "colorsequence")
end

NumberSequence = {}
function NumberSequence.new(...)
    local kps = ...
    if type(kps) ~= "table" then kps = { ... } end
    return marker({ __ns = true, keypoints = kps }, "numbersequence")
end

TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
    return marker({
        Time = time or 0,
        EasingStyle = style or Enum.EasingStyle.Quad,
        EasingDirection = direction or Enum.EasingDirection.Out,
        RepeatCount = repeatCount or 0,
        Reverses = reverses or false,
        DelayTime = delayTime or 0,
    }, "tweeninfo")
end

Rect = {}
function Rect.new(minx, miny, maxx, maxy)
    return marker({ Min = Vector2.new(minx, miny), Max = Vector2.new(maxx, maxy) }, "rect")
end

NumberRange = {}
function NumberRange.new(a, b)
    return marker({ Min = a or 0, Max = b or 0 }, "numberrange")
end

CFrame = {}
function CFrame.new(x, y, z)
    if type(x) == "table" then x, y, z = x.X, x.Y, x.Z end
    return marker({ X = x or 0, Y = y or 0, Z = z or 0 }, "cframe")
end

-- ============================================================================
-- Enum
-- 注意：此处故意【不】用 local，直接声明为全局 Enum。否则末尾 `Enum = Enum`
-- 这种同名裸赋值会被 Luau 解析为对局部 Enum 的自身赋值，全局 Enum 永远建不出来
-- （luau CLI 的 _G 又是只读表，不能用 _G.Enum = Enum）。全局 Enum 对 lupa/luau 双运行时都成立。
-- ============================================================================

Enum = {}
local function eitem(group, name, value)
    return { Name = name, EnumType = group, Value = value }
end
local function egroup(name, items)
    local t = {}
    for i, n in ipairs(items) do t[n] = eitem("Enum." .. name, n, i - 1) end
    -- 容错：真实 Enum 成员极多，脚本可能引用未列举/自定义成员；
    -- 返回带 Name 的占位 item，避免 mock 因 nil 索引崩栈（vision 靠 Name 渲染）
    setmetatable(t, { __index = function(_, k)
        if type(k) == "string" then
            local it = eitem("Enum." .. name, k, -1)
            t[k] = it
            return it
        end
    end })
    return t
end
-- Enum 顶层同样容错：访问未定义分组时按需创建空组
setmetatable(Enum, { __index = function(_, k)
    if type(k) == "string" then
        local g = egroup(k, {})
        Enum[k] = g
        return g
    end
end })
Enum.Font = egroup("Font", { "Legacy", "SourceSans", "SourceSansBold", "SourceSansItalic",
    "SourceSansLight", "Gotham", "GothamBold", "GothamBlack", "GothamMedium", "FredokaOne" })
Enum.EasingStyle = egroup("EasingStyle", { "Linear", "Sine", "Back", "Quad", "Quart", "Quint",
    "Bounce", "Elastic", "Exponential", "Circular", "Cubic" })
Enum.EasingDirection = egroup("EasingDirection", { "In", "Out", "InOut" })
Enum.TextXAlignment = egroup("TextXAlignment", { "Left", "Center", "Right" })
Enum.TextYAlignment = egroup("TextYAlignment", { "Top", "Center", "Bottom" })
Enum.FillDirection = egroup("FillDirection", { "Horizontal", "Vertical" })
Enum.SortOrder = egroup("SortOrder", { "Name", "LayoutOrder" })
Enum.HorizontalAlignment = egroup("HorizontalAlignment", { "Left", "Center", "Right" })
Enum.VerticalAlignment = egroup("VerticalAlignment", { "Top", "Center", "Bottom" })
Enum.UserInputType = egroup("UserInputType", { "MouseButton1", "MouseButton2", "MouseButton3",
    "MouseWheel", "MouseMovement", "Touch", "Keyboard", "Focus", "Gamepad1", "Screenshot" })
Enum.UserInputState = egroup("UserInputState", { "Begin", "Change", "End", "Cancel", "None" })
Enum.KeyCode = egroup("KeyCode", { "Unknown", "W", "A", "S", "D", "Space", "Return", "Escape",
    "LeftShift", "E", "Q", "F", "Tab" })
Enum.ZIndexBehavior = egroup("ZIndexBehavior", { "Sibling", "Global" })
Enum.ScrollingDirection = egroup("ScrollingDirection", { "X", "Y", "XY" })
Enum.AutomaticSize = egroup("AutomaticSize", { "None", "X", "Y", "XY" })
Enum.PlaybackState = egroup("PlaybackState", { "Begin", "Delayed", "Playing", "Paused", "Completed", "Cancelled" })
Enum.ApplyStrokeMode = egroup("ApplyStrokeMode", { "Contextual", "Border" })
Enum.ScaleType = egroup("ScaleType", { "Stretch", "Fit", "Crop", "Tile", "Slice" })
Enum.TextTruncate = egroup("TextTruncate", { "None", "AtEnd", "SplitWord", "WithEllipsis" })
Enum.ElasticBehavior = egroup("ElasticBehavior", { "WhenScrollable", "Always", "Never" })
M.Enum = Enum

-- ============================================================================
-- Signal（事件）
-- ============================================================================

local SignalMT = {}
SignalMT.__index = SignalMT

function SignalMT:Connect(fn)
    if type(fn) ~= "function" then error("Signal:Connect 需要函数", 2) end
    local h = { fn = fn, alive = true }
    self._h[#self._h + 1] = h
    return {
        Disconnect = function()
            h.alive = false
        end,
    }
end

function SignalMT:Once(fn)
    local conn
    conn = self:Connect(function(...)
        conn.Disconnect()
        fn(...)
    end)
    return conn
end

function SignalMT:Fire(...)
    local snapshot = {}
    for _, h in ipairs(self._h) do
        if h.alive then snapshot[#snapshot + 1] = h.fn end
    end
    for _, fn in ipairs(snapshot) do
        local ok, err = pcall(fn, ...)
        if not ok then M.warn("事件回调报错: " .. tostring(err)) end
    end
end

function SignalMT:Wait()
    local co = coroutine.running()
    if not co then error("Signal:Wait 必须在协程内调用", 2) end
    local woken = false
    local conn
    conn = self:Connect(function(...)
        if woken then return end
        woken = true
        conn.Disconnect()
        -- 把等待协程重新入队；恢复时传入事件参数
        queue[#queue + 1] = { at = vclock, co = co, args = { ... } }
    end)
    return coroutine.yield()
end

local function newSignal()
    return setmetatable({ _h = {} }, SignalMT)
end
M.newSignal = newSignal

-- ============================================================================
-- Instance
-- ============================================================================

local GuiClassChain = {
    Frame = { GuiObject = true },
    TextLabel = { GuiObject = true, GuiButton = false },
    TextButton = { GuiObject = true, GuiButton = true },
    ImageLabel = { GuiObject = true },
    ImageButton = { GuiObject = true, GuiButton = true },
    ScrollingFrame = { GuiObject = true, GuiScrollFrame = true },
    CanvasGroup = { GuiObject = true },
    ScreenGui = { GuiBase2d = true, LayerCollector = true },
    BillboardGui = { GuiBase2d = true, LayerCollector = true },
    SurfaceGui = { GuiBase2d = true, LayerCollector = true },
}

local VALUE_TYPES = {
    UDim = true, UDim2 = true, Vector2 = true, Vector3 = true, Color3 = true,
    NumberRange = true, NumberSequence = true, NumberSequenceKeypoint = true,
    Rect = true, CFrame = true, ColorSequence = true, ColorSequenceKeypoint = true,
    TweenInfo = true, Enum = true, EnumItem = true, Font = true, BrickColor = true,
    PhysicalProperties = true, Random = true, Region3 = true, Ray = true, PathWaypoint = true,
}

local DEFAULT_PROPS = {
    Visible = true,
    ZIndex = 1,
    LayoutOrder = 0,
    Position = UDim2.new(0, 0, 0, 0),
    Size = UDim2.new(0, 0, 0, 0),
    AnchorPoint = Vector2.new(0, 0),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    BorderColor3 = Color3.new(0, 0, 0),
    ClipsDescendants = false,
    Active = false,
    Selectable = true,
    AutoButtonColor = true,
    Modal = false,
    DisplayOrder = 0,
    ResetOnSpawn = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = false,
    Text = "",
    TextColor3 = Color3.new(1, 1, 1),
    TextTransparency = 0,
    TextSize = 18,
    TextWrapped = false,
    TextScaled = false,
    RichText = false,
    -- 真机默认：TextLabel/TextButton/TextBox 的 X/Y 对齐都是 Center（此前误设 Left/Top，
    -- 会让"未显式设置对齐"的文本出现位置偏差）
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    TextStrokeTransparency = 1,
    Font = Enum.Font.SourceSans,
    Image = "",
    ImageColor3 = Color3.new(1, 1, 1),
    ImageTransparency = 0,
    ScaleType = "Stretch",
    CanvasPosition = Vector2.new(0, 0),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.None,
    ScrollBarThickness = 12,
    ScrollBarImageTransparency = 0,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ElasticBehavior = "WhenScrollable",
    GroupTransparency = 0,
}

local CLASS_DEFAULTS = {
    UICorner = { CornerRadius = UDim.new(0, 8) },
    UIStroke = { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0,
        ApplyStrokeMode = { Name = "Contextual" }, LineJoinMode = { Name = "Round" } },
    UIGradient = { Rotation = 0, Offset = Vector2.new(0, 0), Enabled = true },
    UIPadding = { PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0),
        PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0) },
    UIListLayout = { Padding = UDim.new(0, 0), FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder },
    UIGridLayout = { CellSize = UDim2.new(0, 100, 0, 100), CellPadding = UDim2.new(0, 0, 0, 0),
        FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder },
    UITableLayout = {},
    UIAspectRatioConstraint = { AspectRatio = 1, AspectType = { Name = "FitWithinMax" } },
    UISizeConstraint = { MaxSize = Vector2.new(1e9, 1e9), MinSize = Vector2.new(0, 0) },
    UITextSizeConstraint = { MaxTextSize = 100, MinTextSize = 1 },
    ScreenGui = { Enabled = true },
    -- 真机默认：文本/图片类没有背景（透明），只有 Button/Frame 才有可见底色
    TextLabel = { BackgroundTransparency = 1 },
    ImageLabel = { BackgroundTransparency = 1 },
}

local EVENT_KEYS = {
    InputBegan = true, InputEnded = true, InputChanged = true,
    MouseButton1Down = true, MouseButton1Up = true, MouseButton1Click = true,
    MouseEnter = true, MouseLeave = true, MouseMoved = true, MouseWheelForward = true,
    MouseWheelBackward = true, Activated = true, SelectionGained = true, SelectionLost = true,
    TextFocused = true, FocusLost = true, Changed = true,
    RenderStepped = true, Heartbeat = true, Stepped = true, PostSimulation = true,
    PlayerAdded = true, PlayerRemoving = true, CharacterAdded = true,
    ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
    AncestryChanged = true,
}

local InstanceMT = {}
local InstanceMethods = {}
Instance = {}                      -- Instance.new(...) 构造入口

function InstanceMT.__index(self, key)
    local m = InstanceMethods[key]
    if m then return m end
    local p = rawget(self, "_props")
    if p and p[key] ~= nil then return p[key] end
    if key == "AbsoluteSize" then
        local a = rawget(self, "_abs")
        return Vector2.new(a.w, a.h)
    end
    if key == "AbsolutePosition" then
        local a = rawget(self, "_abs")
        return Vector2.new(a.x, a.y)
    end
    -- TextBounds：真机文本类有该属性（Vector2，随 Text/TextSize 变化）。
    -- 无头下按字体 em 系数粗略估算（ASCII≈0.55em，非 ASCII≈1em；行高≈1.2*TextSize）。
    if key == "TextBounds" then
        local cls = rawget(self, "ClassName")
        if cls == "TextLabel" or cls == "TextButton" or cls == "TextBox" then
            local s = (p and p.Text) or DEFAULT_PROPS.Text or ""
            local size = (p and p.TextSize) or DEFAULT_PROPS.TextSize or 18
            local w = 0
            for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                if string.byte(ch) > 127 then w = w + size else w = w + size * 0.55 end
            end
            local lines = 1
            for _ in s:gmatch("\n") do lines = lines + 1 end
            return Vector2.new(w, size * 1.2 * lines)
        end
    end
    if EVENT_KEYS[key] then
        local evs = rawget(self, "_events")
        if not evs[key] then evs[key] = newSignal() end
        return evs[key]
    end
    -- 真机 Instance.Name 永远返回字符串（默认等于类名），mock 亦然
    if key == "Name" then return rawget(self, "ClassName") or "" end
    local cd = CLASS_DEFAULTS[rawget(self, "ClassName")]
    if cd and cd[key] ~= nil then return cd[key] end
    if DEFAULT_PROPS[key] ~= nil then return DEFAULT_PROPS[key] end
    return nil
end

local function firePropChanged(self, key, old)
    local sigs = rawget(self, "_propsigs")
    local s = sigs[key]
    if s then s:Fire(old) end
    local changed = rawget(self, "_events")
    local cs = changed.Changed
    if cs and #cs._h > 0 then cs:Fire(key) end
end

function InstanceMT.__newindex(self, key, value)
    if key == "Parent" then
        local p = rawget(self, "_props")
        local old = p.Parent
        if old == value then return end
        -- 父级可能是"未模拟 service 的 stub"（非真正 Instance），其 _children 未必是表，须守卫
        local oc = old and rawget(old, "_children")
        if type(oc) == "table" then
            for i, c in ipairs(oc) do
                if c == self then table.remove(oc, i) break end
            end
        end
        p.Parent = value
        local vc = value and rawget(value, "_children")
        if type(vc) == "table" then
            vc[#vc + 1] = self
        end
        local sigs = rawget(self, "_propsigs")
        if sigs.Parent then sigs.Parent:Fire(old) end
        return
    end
    local p = rawget(self, "_props")
    local old = p[key]
    if old ~= value then
        p[key] = value
        firePropChanged(self, key, old)
    end
end

function Instance.new(className)
    if type(className) ~= "string" then error("Instance.new 需要字符串类名", 2) end
    if VALUE_TYPES[className] then
        error(string.format("Unable to create an Instance of type \"%s\"", className), 2)
    end
    local self = setmetatable({}, InstanceMT)
    rawset(self, "__instance", true)
    rawset(self, "ClassName", className)
    rawset(self, "_props", {})
    rawset(self, "_children", {})
    rawset(self, "_events", {})
    rawset(self, "_propsigs", {})
    rawset(self, "_abs", { x = 0, y = 0, w = 0, h = 0 })
    rawset(self, "_destroyed", false)
    if className == "ScreenGui" then
        M.screenGuis[#M.screenGuis + 1] = self
    end
    return self
end
M.screenGuis = {}

function InstanceMethods:IsA(className)
    if self.ClassName == className then return true end
    if className == "Instance" then return true end
    local chain = GuiClassChain[self.ClassName]
    return chain ~= nil and chain[className] == true
end

function InstanceMethods:FindFirstChild(name)
    if type(name) ~= "string" then return nil end
    for _, c in ipairs(rawget(self, "_children")) do
        if c.Name == name and not c._destroyed then return c end
    end
    return nil
end

function InstanceMethods:FindFirstChildOfClass(className)
    for _, c in ipairs(rawget(self, "_children")) do
        if c.ClassName == className and not c._destroyed then return c end
    end
    return nil
end

function InstanceMethods:FindFirstChildWhichIsA(className, recursive)
    for _, c in ipairs(rawget(self, "_children")) do
        if c:IsA(className) and not c._destroyed then return c end
        if recursive then
            local r = c:FindFirstChildWhichIsA(className, true)
            if r then return r end
        end
    end
    return nil
end

function InstanceMethods:FindFirstAncestorOfClass(className)
    local cur = rawget(self, "_props").Parent
    while cur do
        if cur.ClassName == className then return cur end
        cur = rawget(cur, "_props").Parent
    end
    return nil
end

function InstanceMethods:WaitForChild(name, timeout)
    local c = self:FindFirstChild(name)
    if c then return c end
    M.warn("WaitForChild 超时返回 nil: " .. tostring(name))
    return nil
end

function InstanceMethods:GetChildren()
    local out = {}
    for _, c in ipairs(rawget(self, "_children")) do
        if not c._destroyed then out[#out + 1] = c end
    end
    return out
end

function InstanceMethods:GetDescendants()
    local out = {}
    local function walk(inst)
        for _, c in ipairs(rawget(inst, "_children")) do
            if not c._destroyed then
                out[#out + 1] = c
                walk(c)
            end
        end
    end
    walk(self)
    return out
end

function InstanceMethods:ClearAllChildren()
    for _, c in ipairs(rawget(self, "_children")) do
        c._destroyed = true
    end
    rawset(self, "_children", {})
end

function InstanceMethods:Destroy()
    if rawget(self, "_destroyed") then return end
    rawset(self, "_destroyed", true)
    local par = rawget(self, "_props").Parent
    if par and par._children then
        for i, c in ipairs(par._children) do
            if c == self then table.remove(par._children, i) break end
        end
    end
    local kids = {}
    for _, c in ipairs(rawget(self, "_children")) do kids[#kids + 1] = c end
    for _, c in ipairs(kids) do pcall(function() c:Destroy() end) end
    rawset(self, "_children", {})
    for _, ev in pairs(rawget(self, "_events")) do
        if type(ev) == "table" and ev._h then ev._h = {} end
    end
    rawset(self, "_events", {})
    for i, g in ipairs(M.screenGuis) do
        if g == self then table.remove(M.screenGuis, i) break end
    end
end

function InstanceMethods:Clone()
    local function cloneInst(src)
        local c = Instance.new(src.ClassName)
        for k, v in pairs(rawget(src, "_props")) do
            if k ~= "Parent" then rawset(rawget(c, "_props"), k, v) end
        end
        for _, ch in ipairs(rawget(src, "_children")) do
            if not ch._destroyed then cloneInst(ch).Parent = c end
        end
        return c
    end
    return cloneInst(self)
end

function InstanceMethods:GetFullName()
    local parts = { self.Name or self.ClassName }
    local cur = rawget(self, "_props").Parent
    while cur do
        table.insert(parts, 1, cur.Name or cur.ClassName)
        cur = rawget(cur, "_props").Parent
    end
    return table.concat(parts, ".")
end

function InstanceMethods:SetAttribute(name, value)
    local a = rawget(self, "_attrs")
    if not a then a = {} rawset(self, "_attrs", a) end
    a[name] = value
end
function InstanceMethods:GetAttribute(name)
    local a = rawget(self, "_attrs")
    return a and a[name] or nil
end
function InstanceMethods:GetAttributes()
    return rawget(self, "_attrs") or {}
end

function InstanceMethods:GetPropertyChangedSignal(prop)
    local sigs = rawget(self, "_propsigs")
    if not sigs[prop] then sigs[prop] = newSignal() end
    return sigs[prop]
end

function InstanceMethods:TweenSize(size, ...)
    local ti, style, dir = ...
    self.Size = size
    return { Play = function() end, Cancel = function() end }
end

function InstanceMethods:TweenPosition(pos, ...)
    self.Position = pos
    return { Play = function() end, Cancel = function() end }
end

M.Instance = Instance

-- ============================================================================
-- typeof
-- ============================================================================

local TYPE_MARKERS = {
    __udim = "UDim", __udim2 = "UDim2", __vector2 = "Vector2", __vector3 = "Vector3",
    __color3 = "Color3", __colorsequence = "ColorSequence", __numbersequence = "NumberSequence",
    __tweeninfo = "TweenInfo", __rect = "Rect", __cframe = "CFrame", __numberrange = "NumberRange",
}

function typeof(v)
    local t = type(v)
    if t ~= "table" then return t end
    if rawget(v, "__instance") then return "Instance" end
    for mark, name in pairs(TYPE_MARKERS) do
        if rawget(v, mark) then return name end
    end
    if rawget(v, "EnumType") then return "EnumItem" end
    return "table"
end
M.typeof = typeof

-- ============================================================================
-- TweenService
-- ============================================================================

local TweenService = {}
M.tweenLog = {}
M.activeTweens = {}          -- 进行中的补间（由 stepTweens 每帧推进）

-- 缓动函数：只定义 In 形态，Out/InOut 由 ease() 组合（与真机公式一致）
local FIN = {
    Linear = function(u) return u end,
    Sine = function(u) return 1 - math.cos(u * math.pi / 2) end,
    Quad = function(u) return u * u end,
    Cubic = function(u) return u * u * u end,
    Quart = function(u) return u * u * u * u end,
    Quint = function(u) return u ^ 5 end,
    Exponential = function(u)
        if u <= 0 then return 0 end
        return 2 ^ (10 * (u - 1))
    end,
    Circular = function(u) return 1 - math.sqrt(1 - u * u) end,
    Back = function(u)
        local c = 1.70158
        return c * u * u * u - c * u * u
    end,
    Elastic = function(u)
        if u <= 0 then return 0 end
        return -(2 ^ (10 * u - 10)) * math.sin((u * 10 - 10.75) * (2 * math.pi / 3))
    end,
    Bounce = function(u)
        local n, d = 7.5625, 2.75
        if u < 1 / d then return n * u * u end
        if u < 2 / d then u = u - 1.5 / d return n * u * u + 0.75 end
        if u < 2.5 / d then u = u - 2.25 / d return n * u * u + 0.9375 end
        u = u - 2.625 / d
        return n * u * u + 0.984375
    end,
}

local function ease(style, dir, t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local fin = FIN[style] or FIN.Quad
    if dir == "In" then return fin(t) end
    if dir == "InOut" then
        if t < 0.5 then return fin(t * 2) * 0.5 end
        return 1 - fin((1 - t) * 2) * 0.5
    end
    return 1 - fin(1 - t)          -- Out（默认）
end

-- 值插值：支持 number / UDim2 / Vector2 / Color3；其它类型直接取终值
local function lerpValue(a, b, t)
    if type(a) == "number" and type(b) == "number" then
        return a + (b - a) * t
    end
    if type(a) == "table" and type(b) == "table" then
        if type(a.X) == "table" and type(b.X) == "table" and a.X.Offset ~= nil then
            return UDim2.new(a.X.Scale + (b.X.Scale - a.X.Scale) * t,
                a.X.Offset + (b.X.Offset - a.X.Offset) * t,
                a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t,
                a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
        end
        if type(a.X) == "number" and type(b.X) == "number" and a.X ~= nil then
            return Vector2.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
        end
        if a.R ~= nil and b.R ~= nil then
            return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
        end
    end
    return b
end

local function makeTween(inst, goal, dur, style, dir, delay)
    dur = dur or 1 / 60
    if dur <= 0 then dur = 1 / 60 end
    delay = delay or 0
    local t = {
        _cancelled = false,
        _fired = false,
        Completed = newSignal(),
    }
    function t:Play()
        if self._cancelled then return end
        if self._rec then self._rec.dead = true end        -- 重播：废弃上一段
        local from = {}
        for k in pairs(goal) do
            local ok, v = pcall(function() return inst[k] end)
            from[k] = ok and v or nil
        end
        M.tweenLog[#M.tweenLog + 1] = { inst = inst, goal = goal }
        local rec = {
            tween = self, inst = inst, goal = goal, from = from,
            dur = dur, start = vclock + delay, style = style or "Quad", dir = dir or "Out",
        }
        self._rec = rec
        M.activeTweens[#M.activeTweens + 1] = rec
    end
    function t:Cancel()
        self._cancelled = true
        if self._rec then self._rec.dead = true end
    end
    function t:Pause() end
    function t:Destroy() end
    return t
end

-- 每帧推进所有进行中的补间（由 stepFrame 调用）
function M.stepTweens()
    local list = M.activeTweens
    local i = 1
    while i <= #list do
        local rec = list[i]
        if rec.dead then
            table.remove(list, i)
        else
            local span = rec.dur > 0 and rec.dur or (1 / 60)
            local a = (vclock - rec.start) / span
            if a < 0 then a = 0 end
            if a > 1 then a = 1 end
            local k = ease(rec.style, rec.dir, a)
            for name, target in pairs(rec.goal) do
                local v = lerpValue(rec.from[name], target, k)
                local ok, err = pcall(function() rec.inst[name] = v end)
                if not ok then
                    M.warn("Tween 设置属性失败: " .. tostring(name) .. " -> " .. tostring(err))
                end
            end
            if a >= 1 then
                table.remove(list, i)
                local tw = rec.tween
                -- Completed 延迟到下一帧触发：库里「Play() 后紧接 Connect()」是惯用法
                task.defer(function()
                    if not tw._cancelled and not tw._fired then
                        tw._fired = true
                        tw.Completed:Fire(Enum.PlaybackState.Completed)
                    end
                end)
            else
                i = i + 1
            end
        end
    end
end

function TweenService:Create(inst, tweenInfo, goalProps)
    if typeof(inst) ~= "Instance" then
        M.warn("TweenService:Create 目标不是 Instance")
    end
    if type(goalProps) ~= "table" then
        M.warn("TweenService:Create 目标属性表为空")
    end
    local dur = 1 / 60
    local style, dir, delay = "Quad", "Out", 0
    if type(tweenInfo) == "table" then
        dur = tweenInfo.Time or 1 / 60
        delay = tweenInfo.DelayTime or 0
        local st = tweenInfo.EasingStyle
        local dr = tweenInfo.EasingDirection
        if type(st) == "table" and st.Name then style = st.Name end
        if type(dr) == "table" and dr.Name then dir = dr.Name end
    end
    return makeTween(inst, goalProps or {}, dur, style, dir, delay)
end
M.TweenService = TweenService

-- ============================================================================
-- task 调度器 + 虚拟时钟
-- ============================================================================

vclock = 0
queue = {}

M.vclock = function() return vclock end

task = {}

local function runQueued(entry)
    local co = entry.co
    local ok, a, b = coroutine.resume(co, table.unpack(entry.args or {}))
    if not ok then
        M.onCoroutineError(tostring(a))
        return
    end
    if coroutine.status(co) == "dead" then return end
    -- 产出值：数字=等待时长；{__pump=n}=推进虚拟时间 n 秒；其它=下一帧继续
    local waitT = a
    if type(waitT) == "table" and waitT.__pump then waitT = waitT.__pump end
    if type(waitT) ~= "number" then waitT = 0 end
    queue[#queue + 1] = { at = vclock + waitT, co = co, args = { b } }
end

-- 协程错误钩子：默认走 warn；harness 可覆盖以记录为硬错误
M.onCoroutineError = function(msg) M.warn("协程报错: " .. tostring(msg)) end

local function scheduleNow(fn, ...)
    local co = coroutine.create(fn)
    queue[#queue + 1] = { at = vclock, co = co, args = { ... } }
end

function task.spawn(fn, ...)
    if type(fn) ~= "function" then error("task.spawn 需要函数", 2) end
    local args = { ... }
    scheduleNow(function(...)
        local ok, err = pcall(fn, ...)
        if not ok then M.warn("task.spawn 报错: " .. tostring(err)) end
    end, table.unpack(args))
end

function task.defer(fn, ...)
    task.delay(0, fn, ...)
end

function task.delay(t, fn, ...)
    local args = { ... }
    local co = coroutine.create(function(...)
        local ok, err = pcall(fn, ...)
        if not ok then M.warn("task.delay 报错: " .. tostring(err)) end
    end)
    queue[#queue + 1] = { at = vclock + (t or 0), co = co, args = args }
end

function task.wait(t)
    return coroutine.yield(t or 0)
end

function wait(t)
    return coroutine.yield(t or 0)
end

function spawn(fn, ...)
    task.spawn(fn, ...)
end

function delay(t, fn, ...)
    task.delay(t, fn, ...)
end

function tick() return vclock end
function time() return vclock end

M.pumping = false

-- 单帧步进：推进虚拟时钟 1/60（或指定 dt），触发帧事件，处理到期协程
local function stepFrame(dt)
    dt = dt or 1 / 60
    vclock = vclock + dt
    M.stepTweens()                 -- 补间按虚拟时钟插值（先于事件，贴近真机帧序）
    M.frameEvent("RenderStepped", dt, vclock)
    M.frameEvent("Heartbeat", dt, vclock)
    local i = 1
    while i <= #queue do
        if queue[i].at <= vclock then
            local e = table.remove(queue, i)
            runQueued(e)
        else
            i = i + 1
        end
    end
    -- 帧钩子（harness 用它做动画帧采样；在帧末调用，等价于"这一帧渲染出来的样子"）
    if M.onFrame then M.onFrame() end
end

-- 推进一帧（供外部驱动循环逐帧步进）
M.pumpFrame = function()
    if M.pumping then
        M.warn("pumpFrame 嵌套调用被忽略")
        return
    end
    M.pumping = true
    stepFrame()
    M.pumping = false
end

M.pumpSeconds = function(dt)
    if M.pumping then
        M.warn("pumpSeconds 嵌套调用被忽略")
        return
    end
    M.pumping = true
    local target = vclock + (dt or 0)
    local guard = 0
    while vclock < target do
        guard = guard + 1
        if guard > 500000 then
            M.warn("pumpSeconds 触发保护上限，可能存在 0 延时自激循环")
            break
        end
        stepFrame(math.min(1 / 60, target - vclock))
    end
    M.pumping = false
end

-- 调度队列的外部操作入口（harness 驱动场景协程用）
M.enqueue = function(entry) queue[#queue + 1] = entry end
M.queueLength = function() return #queue end

M.scheduleNow = scheduleNow

-- ============================================================================
-- HttpService（迷你 JSON）
-- ============================================================================

local function jsonEncode(v)
    local t = type(v)
    if t == "table" then
        local isArray = true
        local n = 0
        for k in pairs(v) do
            n = n + 1
            if type(k) ~= "number" then isArray = false end
        end
        if n == 0 then return "{}" end
        local parts = {}
        if isArray then
            for _, item in ipairs(v) do parts[#parts + 1] = jsonEncode(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, item in pairs(v) do
                parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. jsonEncode(item)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "number" then
        return tostring(v)
    elseif t == "boolean" then
        return v and "true" or "false"
    end
    return "null"
end

local function jsonDecode(s)
    if type(s) ~= "string" then error("JSONDecode 需要字符串") end
    local pos = 1
    local function skipws()
        while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
    end
    local parseVal
    local function parseString()
        pos = pos + 1
        local out = {}
        while pos <= #s do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1 return table.concat(out) end
            if c == "\\" then
                local nx = s:sub(pos + 1, pos + 1)
                if nx == "n" then out[#out + 1] = "\n"
                elseif nx == "t" then out[#out + 1] = "\t"
                elseif nx == "u" then
                    local hex = s:sub(pos + 2, pos + 5)
                    out[#out + 1] = hex:len() == 4 and (tonumber(hex, 16) and "?" or "?") or "?"
                    pos = pos + 4
                else out[#out + 1] = nx end
                pos = pos + 2
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        error("JSONDecode: 字符串未闭合")
    end
    parseVal = function()
        skipws()
        local c = s:sub(pos, pos)
        if c == '"' then return parseString() end
        if c == "{" then
            pos = pos + 1
            local obj = {}
            skipws()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return obj end
            while true do
                skipws()
                local key = parseString()
                skipws()
                if s:sub(pos, pos) ~= ":" then error("JSONDecode: 缺少冒号") end
                pos = pos + 1
                obj[key] = parseVal()
                skipws()
                local d = s:sub(pos, pos)
                if d == "," then pos = pos + 1
                elseif d == "}" then pos = pos + 1 return obj
                else error("JSONDecode: 对象格式错误") end
            end
        end
        if c == "[" then
            pos = pos + 1
            local arr = {}
            skipws()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return arr end
            while true do
                arr[#arr + 1] = parseVal()
                skipws()
                local d = s:sub(pos, pos)
                if d == "," then pos = pos + 1
                elseif d == "]" then pos = pos + 1 return arr
                else error("JSONDecode: 数组格式错误") end
            end
        end
        if s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
        if s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
        if s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil end
        local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
        if num then pos = pos + #num return tonumber(num) end
        error("JSONDecode: 无法解析字符 " .. c)
    end
    local v = parseVal()
    return v
end

local HttpService = {
    JSONEncode = jsonEncode,
    JSONDecode = jsonDecode,
    JSONEncode2 = jsonEncode,
    GenerateGUID = function() return "mock-guid" end,
    UrlEncode = function(_, s) return s end,
    GetAsync = function() return "" end,
}
M.HttpService = HttpService

-- ============================================================================
-- TextService（近似文本测量）
-- ============================================================================

local TextService = {}
function TextService:GetTextSize(text, fontSize, font, boundsSize)
    -- 与 vision.lua 使用同一套近似度量，保证渲染与测量一致
    local w = 0
    for _ in 1, #tostring(text or "") do w = w + 1 end
    return Vector2.new(w * (fontSize or 18) * 0.58, (fontSize or 18) * 1.25)
end
M.TextService = TextService

-- ============================================================================
-- Players / 输入
-- ============================================================================

local LocalPlayer = setmetatable({}, {
    __index = function(_, k)
        if k == "Name" then return "LocalPlayer" end
        if k == "UserId" then return 1 end
        if k == "DisplayName" then return "LocalPlayer" end
        if k == "Character" then return nil end
        if k == "PlayerGui" then return Services.PlayerGui end
        if k == "GetMouse" then return function() return M.mouseStub end end
        return nil
    end,
})

local Players = {
    LocalPlayer = LocalPlayer,
    GetPlayers = function() return { LocalPlayer } end,
    GetPlayerFromCharacter = function() return nil end,
    PlayerAdded = newSignal(),
    PlayerRemoving = newSignal(),
    CharacterAdded = newSignal(),
}
M.Players = Players

local UserInputService = {
    InputBegan = newSignal(),
    InputEnded = newSignal(),
    InputChanged = newSignal(),
    TouchEnabled = false,
    KeyboardEnabled = true,
    MouseEnabled = true,
    MouseIconEnabled = true,
    GetMouseLocation = function() return Vector2.new(0, 0) end,
    Modal = nil,
}
M.UserInputService = UserInputService

local RunService = {
    RenderStepped = newSignal(),
    Heartbeat = newSignal(),
    Stepped = newSignal(),
    PostSimulation = newSignal(),
    IsClient = true,
    IsServer = false,
    IsStudio = false,
    IsRunning = true,
    IsEdit = false,
}
M.RunService = RunService

-- 通用代理：未模拟字段的兜底。既可被当作函数调用（X() → nil/自身），
-- 又可被索引（X.MessageOut.Connect(...)）、可 #（长度 0），避免上层库因类型不符而崩。
-- 注意：原本返回 function 也是"真值"，故改为该代理不改变任何真值性分支判断。
local universalStub
do
    local u
    u = setmetatable({}, {
        __call = function(_, ...) return u end,
        __index = function(_, k)
            if k == "Connect" or k == "Once" then return function() return u end end
            if k == "Wait" then return function() return nil end end
            if k == "Fire" or k == "Disconnect" or k == "Destroy" then return function() end end
            return u
        end,
        __newindex = function() end,
        __len = function() return 0 end,
        __tostring = function() return "Stub" end,
    })
    universalStub = u
end

-- 未模拟 service 的占位对象：尽量表现得像 Instance，避免上层库因字段类型不符而崩。
-- 关键：暴露真实的 _children 表（Parent 挂接需要），并给出常见的类行为方法。
local function makeStub(name)
    local t = {}
    rawset(t, "_children", {})
    rawset(t, "ClassName", name)
    rawset(t, "Name", name)
    return setmetatable(t, {
        __index = function(self, k)
            if k == "Parent" then return nil end
            if k == "IsA" then return function() return false end end
            if k == "GetChildren" then return function() return rawget(self, "_children") end end
            if k == "GetDescendants" then return function() return {} end end
            if k == "FindFirstChild" or k == "FindFirstChildOfClass" or k == "FindFirstChildWhichIsA" then
                return function() return nil end
            end
            if k == "WaitForChild" then return function() return nil end end
            if k == "Destroy" then return function() end end
            -- 未知字段：返回通用代理（支持调用 + 索引 + :Connect 等）
            return universalStub
        end,
        __newindex = function(self, k, v)
            if k == "Parent" then return end     -- stub 不参与父子树，静默接受
            rawset(self, k, v)
        end,
    })
end

local Workspace = setmetatable({
    CurrentCamera = {
        ViewportSize = Vector2.new(800, 600),
        CFrame = CFrame.new(0, 0, 0),
    },
    Gravity = 196.2,
}, { __index = function(_, k) M.warn("Workspace." .. tostring(k) .. " 未模拟") return nil end })

local ReplicatedStorage = Instance.new("Folder")
ReplicatedStorage.Name = "ReplicatedStorage"
local StarterGui = Instance.new("Folder")
StarterGui.Name = "StarterGui"
local PlayerGui = Instance.new("Folder")
PlayerGui.Name = "PlayerGui"

Services = {
    Workspace = Workspace,
    Players = Players,
    RunService = RunService,
    UserInputService = UserInputService,
    TweenService = TweenService,
    HttpService = HttpService,
    TextService = TextService,
    ReplicatedStorage = ReplicatedStorage,
    StarterGui = StarterGui,
    PlayerGui = PlayerGui,
    Lighting = makeStub("Lighting"),
    GuiService = makeStub("GuiService"),
    -- Stats：真机带 PerformanceStats（Ping/内存等），上层库常读 Ping 做延迟显示
    Stats = setmetatable({
        PerformanceStats = setmetatable({
            Ping = { GetValue = function() return 42 end },
            Heartbeat = { GetValue = function() return 16 end },
        }, { __index = function() return { GetValue = function() return 0 end } end }),
        GetTotalMemoryUsageMb = function() return 512 end,
    }, { __index = function() return universalStub end }),
    SoundService = makeStub("SoundService"),
    CollectionService = makeStub("CollectionService"),
    ContentProvider = makeStub("ContentProvider"),
    MarketplaceService = makeStub("MarketplaceService"),
    Teams = makeStub("Teams"),
    PathfindingService = makeStub("PathfindingService"),
}
M.Services = Services

-- ============================================================================
-- game
-- ============================================================================

local libRegistry = {}
M.RegisterLib = function(url, content)
    libRegistry[url] = content
end

game = {
    PlaceId = 0,
    GameId = 0,
    CreatorId = 0,
    JobId = "mock",
    Name = "MockPlace",
    GetService = function(_, name)
        local s = Services[name]
        if s then return s end
        M.warn("GetService: 未模拟的 service \"" .. tostring(name) .. "\"，返回空壳")
        local stub = makeStub(tostring(name))
        Services[name] = stub
        return stub
    end,
    HttpGet = function(_, url)
        local c = libRegistry[url]
        if c then return c end
        return ""
    end,
   HttpGetAsync = function(_, url)
        return libRegistry[url] or ""
    end,
}
M.game = game

M.frameEvent = function(name, dt, t)
    local s = RunService[name]
    -- 真实签名：RenderStepped/Heartbeat 回调均为 (deltaTime, time)
    if s then s:Fire(dt or 1 / 60, t or vclock) end
end

-- ============================================================================
-- InputObject / 输入模拟
-- ============================================================================

M.mouseStub = setmetatable({}, {
    __index = function(_, k)
        if k == "Hit" then return Vector2.new(0, 0) end
        if k == "X" or k == "Y" then return 0 end
        return function() return nil end
    end,
})

function mkInput(opts)
    opts = opts or {}
    local input = {
        UserInputType = opts.UserInputType or Enum.UserInputType.MouseButton1,
        UserInputState = Enum.UserInputState.Begin,
        Position = opts.Position or Vector2.new(0, 0),
        Delta = opts.Delta or Vector2.new(0, 0),
        KeyCode = opts.KeyCode or Enum.KeyCode.Unknown,
    }
    input.Changed = newSignal()
    return input
end
M.mkInput = mkInput

function fireInput(inst, eventName, input)
    if typeof(inst) ~= "Instance" then
        M.warn("fireInput 目标不是 Instance")
        return
    end
    if eventName == "InputBegan" then
        input.UserInputState = Enum.UserInputState.Begin
        input.Changed:Fire(input.UserInputState)
        UserInputService.InputBegan:Fire(input, false)
    elseif eventName == "InputEnded" then
        input.UserInputState = Enum.UserInputState.End
        input.Changed:Fire(input.UserInputState)
        UserInputService.InputEnded:Fire(input, false)
    elseif eventName == "InputChanged" then
        input.Changed:Fire(input.UserInputState)
        UserInputService.InputChanged:Fire(input, false)
    end
    local sig = rawget(inst, "_events")
    local ev = sig and sig[eventName]
    if ev then ev:Fire(input) end
end
M.fireInput = fireInput

function tap(inst, opts)
    if typeof(inst) ~= "Instance" then return end
    local input = mkInput(opts)
    local pos = inst._abs
    input.Position = Vector2.new((pos.x or 0) + (pos.w or 0) / 2, (pos.y or 0) + (pos.h or 0) / 2)
    fireInput(inst, "InputBegan", input)
    fireInput(inst, "InputEnded", input)
    local sigs = rawget(inst, "_events")
    if sigs and sigs.MouseButton1Click then sigs.MouseButton1Click:Fire() end
    if sigs and sigs.Activated then sigs.Activated:Fire() end
end
M.tap = tap

-- ============================================================================
-- 执行器文件系统 / 全局
-- ============================================================================

local FS_FILES = {}
local FS_DIRS = { [""] = true }

function isfile(path)
    if type(path) ~= "string" then return false end
    return FS_FILES[path] ~= nil
end
function readfile(path)
    local c = FS_FILES[path]
    if c == nil then error("readfile: 文件不存在 " .. tostring(path), 2) end
    return c
end
function writefile(path, content)
    FS_FILES[path] = tostring(content)
    return true
end
function appendfile(path, content)
    FS_FILES[path] = (FS_FILES[path] or "") .. tostring(content)
    return true
end
function isfolder(path)
    if type(path) ~= "string" then return false end
    if FS_DIRS[path] then return true end
    for dir in pairs(FS_DIRS) do
        if #dir > #path and dir:sub(1, #path + 1) == path .. "/" then return true end
    end
    return false
end
function makefolder(path)
    if type(path) ~= "string" or #path == 0 then return end
    FS_DIRS[path] = true
    -- 递归创建父级
    local parent = path:match("^(.*)/[^/]*$")
    if parent and not FS_DIRS[parent] then makefolder(parent) end
end
function delfile(path) FS_FILES[path] = nil end
function delfolder(path)
    FS_DIRS[path] = nil
    for p in pairs(FS_FILES) do
        if p:sub(1, #path + 1) == path .. "/" then FS_FILES[p] = nil end
    end
end
function listfiles(path)
    local out = {}
    local prefix = (path and #path > 0) and (path .. "/") or ""
    for p in pairs(FS_FILES) do
        if p:sub(1, #prefix) == prefix then out[#out + 1] = p end
    end
    for d in pairs(FS_DIRS) do
        if d ~= "" and d:sub(1, #prefix) == prefix and not d:sub(#prefix + 1):find("/", 1, true) then
            out[#out + 1] = d .. "/"
        end
    end
    return out
end
M.fs = { files = FS_FILES, dirs = FS_DIRS, reset = function()
    FS_FILES, FS_DIRS = {}, { [""] = true }
end }

if type(load) == "function" then loadstring = load end
setclipboard = function() M.warn("setclipboard 未模拟") end
identifyexecutor = function() return "MockRuntime", "1.0" end
getgenv = function() return M.genv end
M.genv = {}
getrenv = function() return _G end

-- 执行器自定义资源（getcustomasset/getsynasset）：本地文件 -> rbxasset:// URL
-- 真实执行器写入磁盘缓存并返回可加载 URL；mock 返回确定性 URL 供 ImageLabel.Image 使用
local function mockGetCustomAsset(path)
    if type(path) ~= "string" or #path == 0 then return nil end
    return "rbxasset://" .. path
end
getcustomasset = mockGetCustomAsset
getsynasset = mockGetCustomAsset

-- gethui()：执行器隐藏 UI 容器（真实执行器挂到 CoreGui 下防检测）
-- mock 返回专用 Folder；ScreenGui 在 Instance.new 时已注册进 M.screenGuis，guiRoot 不受影响
local huiContainer = Instance.new("Folder")
huiContainer.Name = "HuiContainer"
gethui = function() return huiContainer end

-- 执行器 HTTP（request / http_request / syn.request / http.request）
-- 从 libRegistry 取预置内容（由 run_ui.py --lib 注入），模拟真实执行器的网络请求
local function mockRequest(opts)
    opts = opts or {}
    local url = opts.Url or opts.url
    local c = libRegistry[url]
    if c ~= nil then
        return { StatusCode = 200, Body = c, Success = true }
    end
    return { StatusCode = 404, Body = "", Success = false }
end
request = mockRequest
http_request = mockRequest
syn = { request = mockRequest }
http = { request = mockRequest }

-- 兼容老式全局
M.newSignal = newSignal

-- ============================================================================
-- Roblox 全局符号导出
-- ============================================================================

Enum = Enum                    -- 裸全局导出（供场景脚本使用）
workspace = Workspace            -- 全局 workspace

-- Luau 的 warn(...)：录制为 mock 警告（真实库的 reportError 走此路径，缺失会炸）
function warn(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    local msg = table.concat(parts, " ")
    M.warnings[#M.warnings + 1] = msg
    print("[warn] " .. msg)
end
script = { Name = "MockScript", Source = "", GetChildren = function() return {} end }

print("[mock_runtime] Roblox UI 无头运行时就绪")
return M
