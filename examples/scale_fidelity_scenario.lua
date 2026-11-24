-- ============================================================================
-- scale_fidelity_scenario.lua — UIScale 等比缩放保真回归
-- 真机语义：UIScale 缩放整棵子树，几何(Position/Size)之外的像素视觉属性
-- （TextSize / UICorner 半径 / UIStroke 厚度 / BorderSizePixel / UIPadding /
--  TileSize）也必须按同一系数缩放。
-- 本场景用两个并列的 ScreenGui 子容器，各自带 1.0 与 0.5 的 UIScale，
-- 内部放结构完全相同的 TextLabel / Frame，比较两者 draw op 的像素属性比例。
-- ============================================================================

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
        print("[OK] " .. name)
    else
        failed = failed + 1
        print("[FAIL] " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
    end
end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.51) end

local sg = Instance.new("ScreenGui")
sg.Name = "ScaleFidelityGui"
sg.IgnoreGuiInset = true

local function build(tag, k, ox)
    local root = Instance.new("Frame")
    root.Name = tag
    root.Size = UDim2.fromOffset(200, 120)
    root.Position = UDim2.fromOffset(ox, 20)
    root.BackgroundColor3 = Color3.new(0, 0, 0)
    root.Parent = sg
    instUIScale(root, k)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = root
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.new(1, 1, 1)
    stroke.Parent = root

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingTop = UDim.new(0, 8)
    pad.Parent = root

    local txt = Instance.new("TextLabel")
    txt.Name = tag .. "Text"
    txt.Size = UDim2.fromOffset(160, 40)
    txt.Position = UDim2.fromOffset(20, 40)
    txt.Text = "Scale"
    txt.TextSize = 20
    txt.Parent = root
    return root, txt
end

-- mock 没有 UIScale 的 Instance.new 简写，补一个本地 helper
function instUIScale(parent, k)
    local s = Instance.new("UIScale")
    s.Scale = k
    s.Parent = parent
    return s
end

build("Full", 1.0, 10)
build("Half", 0.5, 260)

local draws = Vision.buildDrawList()
local function find(name)
    for _, d in ipairs(draws) do if d.name == name then return d end end
    return nil
end

local full = find("Full")
local half = find("Half")
local fullTx = find("FullText")
local halfTx = find("HalfText")

check("两个缩放容器都绘制", full ~= nil and half ~= nil)
check("两个文本都绘制", fullTx ~= nil and halfTx ~= nil)

if full and half then
    check("几何宽度按 0.5 缩放", near(half.w, full.w * 0.5), tostring(half.w) .. " vs " .. tostring(full.w))
    check("圆角半径按 0.5 缩放", near(half.corner, full.corner * 0.5), tostring(half.corner) .. " vs " .. tostring(full.corner))
    check("描边厚度按 0.5 缩放", half.stroke and full.stroke and near(half.stroke.thickness, full.stroke.thickness * 0.5),
        tostring(half.stroke and half.stroke.thickness) .. " vs " .. tostring(full.stroke and full.stroke.thickness))
    check("UIPadding 按 0.5 缩放", half.pad and full.pad and near(half.pad.l, full.pad.l * 0.5),
        tostring(half.pad and half.pad.l) .. " vs " .. tostring(full.pad and full.pad.l))
end

if fullTx and halfTx then
    check("TextSize 按 0.5 缩放", near(halfTx.textSize, fullTx.textSize * 0.5), tostring(halfTx.textSize) .. " vs " .. tostring(fullTx.textSize))
    check("文本几何宽度按 0.5 缩放", near(halfTx.w, fullTx.w * 0.5), tostring(halfTx.w) .. " vs " .. tostring(fullTx.w))
end

print(string.format("UIScale 保真回归: 通过 %d / 失败 %d", passed, failed))
