-- ============================================================================
-- vision.lua — UI 布局引擎 + ASCII/色彩网格渲染
-- 作用：让 Agent 通过文本"看到" Roblox UI 的真实画面
--   · computeLayout  按 Roblox 规则算出每个 GuiObject 的绝对矩形，并回写 _abs
--   · describeTree   结构树：类/名/ZIndex/矩形/颜色/文字/装饰/告警
--   · renderAscii    ASCII 画面：填充/边框/圆角/描边/文字
--   · renderColorGrid 色彩网格：每格一个字母 + #RRGGBB 图例（含渐变求值）
--   · Snapshot       一次打印全部视图
-- 依赖：必须先加载 mock_runtime.lua（本文件使用其 Instance/UDim2/Color3/typeof）
-- 注意：本文件只读实例树，不触发任何事件，可随时安全调用
-- ============================================================================

local Vision = {}
local M = __MOCK          -- mock_runtime 导出的模块表（裸全局，luau 下为共享默认环境）

-- 不作为可见对象的装饰类（挂到父级备注，不占矩形）
local DECOR_CLASSES = {
    UICorner = true, UIStroke = true, UIGradient = true, UIPadding = true,
    UIListLayout = true, UIGridLayout = true, UITableLayout = true,
    UIAspectRatioConstraint = true, UISizeConstraint = true, UITextSizeConstraint = true,
}

-- 字体平均字宽（单位 em），仅用于估算文本像素宽
local FONT_EM = {
    Legacy = 0.60, SourceSans = 0.55, SourceSansBold = 0.58, SourceSansItalic = 0.55,
    SourceSansLight = 0.55, Gotham = 0.60, GothamBold = 0.62, GothamBlack = 0.66,
    GothamMedium = 0.60, FredokaOne = 0.62,
}

Vision.viewport = { w = 800, h = 600 }   -- 视口像素
Vision.cell = { w = 8, h = 16 }          -- 网格单元格像素

-- ---------------------------------------------------------------------------
-- 小工具
-- ---------------------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function enumName(v)
    if type(v) == "table" and v.Name then return v.Name end
    return tostring(v)
end

local function isObj(v) return type(v) == "table" and rawget(v, "__instance") == true end

local function hex(c)
    if type(c) ~= "table" or not c.R then return "#------" end
    local r = clamp(math.floor(c.R * 255 + 0.5), 0, 255)
    local g = clamp(math.floor(c.G * 255 + 0.5), 0, 255)
    local b = clamp(math.floor(c.B * 255 + 0.5), 0, 255)
    return string.format("#%02X%02X%02X", r, g, b)
end

-- 量化到 4bit/通道，用于色彩图例去重
local function q4(c)
    if type(c) ~= "table" or not c.R then return nil end
    local function q(v) return clamp(math.floor(v * 15 + 0.5), 0, 15) end
    return { r = q(c.R), g = q(c.G), b = q(c.B) }
end

local function hexQ(cq)
    return string.format("#%02X%02X%02X", cq.r * 17, cq.g * 17, cq.b * 17)
end

-- 取显式设置的属性（绕过 DEFAULT_PROPS 兜底，用于判断 ScrollingFrame 默认裁剪等）
local function explicit(inst, key)
    local p = rawget(inst, "_props")
    return p and p[key]
end

local function rgb255(c)
    return clamp(math.floor(c.R * 255 + 0.5), 0, 255),
        clamp(math.floor(c.G * 255 + 0.5), 0, 255),
        clamp(math.floor(c.B * 255 + 0.5), 0, 255)
end

-- ---------------------------------------------------------------------------
-- 文本度量
-- ---------------------------------------------------------------------------

-- 全角/CJK 字符宽度按 1 em，其余按字体系数
local function isWide(ch)
    local b = ch:byte()
    if b >= 0x2E80 then return true end          -- CJK/全角标点/谚文等大致区间
    return false
end

local function fontEm(name)
    return FONT_EM[name] or 0.56
end

-- 去掉 RichText 标签（<b> <font ...> <stroke> 等）
local function stripTags(s)
    return (s:gsub("<[^>]->", ""))
end

local function charPx(ch, size, em)
    if isWide(ch) then return size * 1.0 end
    return size * em
end

-- 估算一行文本的像素宽
local function lineWidth(line, size, em)
    local w = 0
    for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        w = w + charPx(ch, size, em)
    end
    return w
end

-- 按可用宽度贪心换行（近似 Roblox 的换行行为）
local function wrapLine(line, size, em, availW)
    if availW <= 0 or lineWidth(line, size, em) <= availW then return { line } end
    local lines, cur, curW = {}, "", 0
    for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local cw = charPx(ch, size, em)
        if curW + cw > availW and #cur > 0 then
            lines[#lines + 1] = cur
            cur, curW = "", 0
        end
        cur = cur .. ch
        curW = curW + cw
    end
    if #cur > 0 then lines[#lines + 1] = cur end
    if #lines == 0 then lines[1] = "" end
    return lines
end

-- 计算一段文本的排版结果：{ lines = {str...}, size = 有效字号, lineH = 行高, blockW = 宽 }
local function layoutText(inst, rect)
    local raw = inst.Text
    if type(raw) ~= "string" or raw == "" then return nil end
    if inst.RichText then raw = stripTags(raw) end
    local size = inst.TextSize or 18
    local em = fontEm(enumName(inst.Font))
    local availW = rect.w
    if availW < 4 then availW = 4 end

    local lines = {}
    for seg in (raw .. "\n"):gmatch("([^\n]*)\n") do
        local wrapped
        if inst.TextWrapped or inst.TextScaled then
            wrapped = wrapLine(seg, size, em, availW)
        else
            wrapped = { seg }
        end
        for _, l in ipairs(wrapped) do lines[#lines + 1] = l end
    end
    if #lines == 0 then lines[1] = "" end

    -- TextScaled：估算一个能塞进矩形的字号（宽度与高度都约束）
    if inst.TextScaled then
        local best = size
        local function fits(sz)
            local e = fontEm(enumName(inst.Font))
            local lh = sz * 1.25
            if #lines * lh > rect.h + 0.01 then return false end
            for _, l in ipairs(lines) do
                if lineWidth(l, sz, e) > availW + 0.01 then return false end
            end
            return true
        end
        if not fits(size) then
            local lo, hi = 1, math.max(1, math.floor(size))
            while lo < hi do
                local mid = math.floor((lo + hi + 1) / 2)
                if fits(mid) then lo = mid else hi = mid - 1 end
            end
            best = lo
            -- 用新字号重新断行（TextScaled 通常不换行，这里按原 seg 重新包）
            if inst.TextWrapped then
                local relines = {}
                for seg in (raw .. "\n"):gmatch("([^\n]*)\n") do
                    for _, l in ipairs(wrapLine(seg, best, em, availW)) do
                        relines[#relines + 1] = l
                    end
                end
                if #relines > 0 then lines = relines end
            end
        end
        size = best
    end

    local lineH = size * 1.25
    local blockW = 0
    for _, l in ipairs(lines) do
        local w = lineWidth(l, size, em)
        if w > blockW then blockW = w end
    end
    return { lines = lines, size = size, lineH = lineH, blockW = blockW, em = em }
end

-- ---------------------------------------------------------------------------
-- 布局引擎
-- ---------------------------------------------------------------------------

-- 收集直接子级里的装饰类（返回 decor 表 + 可见子级列表）
local function splitChildren(inst)
    local decor, kids = {}, {}
    for _, c in ipairs(rawget(inst, "_children") or {}) do
        if c._destroyed then
            -- 跳过
        elseif DECOR_CLASSES[c.ClassName] then
            decor[#decor + 1] = c
        elseif c:IsA("GuiObject") then
            kids[#kids + 1] = c
        end
    end
    return decor, kids
end

local function findDecor(decor, className)
    for _, d in ipairs(decor) do
        if d.ClassName == className then return d end
    end
    return nil
end

-- UIPadding 收缩内容区
local function applyPadding(rect, decor)
    local pad = findDecor(decor, "UIPadding")
    if not pad then return rect end
    local l = pad.PaddingLeft.Offset
    local r = pad.PaddingRight.Offset
    local t = pad.PaddingTop.Offset
    local b = pad.PaddingBottom.Offset
    return { x = rect.x + l, y = rect.y + t, w = rect.w - l - r, h = rect.h - t - b }
end

-- UIListLayout：按 Roblox 规则覆盖子级 Position（presets[c] 为预算矩形，直接改写 x/y）
local function applyListLayout(kids, content, layout, presets)
    local n = #kids
    if n == 0 then return end
    local dir = enumName(layout.FillDirection)
    local padPx = layout.Padding.Offset or 0
    local hAlign = enumName(layout.HorizontalAlignment)
    local vAlign = enumName(layout.VerticalAlignment)

    -- SortOrder（稳定排序：同键按原始子级顺序）
    local order = enumName(layout.SortOrder)
    local sorted = {}
    for i, c in ipairs(kids) do sorted[i] = { inst = c, idx = i } end
    if order == "Name" then
        table.sort(sorted, function(a, b)
            if a.inst.Name == b.inst.Name then return a.idx < b.idx end
            return a.inst.Name < b.inst.Name
        end)
    else
        table.sort(sorted, function(a, b)
            local la, lb = a.inst.LayoutOrder or 0, b.inst.LayoutOrder or 0
            if la == lb then return a.idx < b.idx end
            return la < lb
        end)
    end
    local seq = {}
    for i, e in ipairs(sorted) do seq[i] = e.inst end
    sorted = seq

    local cursor
    if dir == "Horizontal" then
        local total = 0
        for _, c in ipairs(sorted) do total = total + presets[c].w end
        total = total + padPx * (n - 1)
        cursor = content.x
        if hAlign == "Center" then cursor = content.x + (content.w - total) / 2
        elseif hAlign == "Right" then cursor = content.x + content.w - total end
        for _, c in ipairs(sorted) do
            local y = content.y
            if vAlign == "Center" then y = content.y + (content.h - presets[c].h) / 2
            elseif vAlign == "Bottom" then y = content.y + content.h - presets[c].h end
            presets[c].x, presets[c].y = cursor, y
            cursor = cursor + presets[c].w + padPx
        end
    else
        local total = 0
        for _, c in ipairs(sorted) do total = total + presets[c].h end
        total = total + padPx * (n - 1)
        cursor = content.y
        if vAlign == "Center" then cursor = content.y + (content.h - total) / 2
        elseif vAlign == "Bottom" then cursor = content.y + content.h - total end
        for _, c in ipairs(sorted) do
            local x = content.x
            if hAlign == "Center" then x = content.x + (content.w - presets[c].w) / 2
            elseif hAlign == "Right" then x = content.x + content.w - presets[c].w end
            presets[c].x, presets[c].y = x, cursor
            cursor = cursor + presets[c].h + padPx
        end
    end
end

local function intersectClip(a, b)
    if not a then return b end
    if not b then return a end
    local x1 = math.max(a.x, b.x)
    local y1 = math.max(a.y, b.y)
    local x2 = math.min(a.x + a.w, b.x + b.w)
    local y2 = math.min(a.y + a.h, b.y + b.h)
    if x2 <= x1 or y2 <= y1 then return { x = x1, y = y1, w = 0, h = 0 } end
    return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

-- 递归布局：把结果写入 inst._vrect 并收集绘制条目
-- parentRect = 父级矩形；preset = UIListLayout 预先算好的矩形（存在则跳过重算）
local function layoutObject(inst, parentRect, clip, depth, out, isLastSibling, preset, groupAlpha)
    local decor, kids = splitChildren(inst)

    local rect
    if preset then
        rect = preset
    else
        local pos = inst.Position
        local size = inst.Size
        local ap = inst.AnchorPoint or { X = 0, Y = 0 }
        local pw, ph = parentRect.w, parentRect.h
        local x = parentRect.x + (pos.X.Scale or 0) * pw + (pos.X.Offset or 0)
        local y = parentRect.y + (pos.Y.Scale or 0) * ph + (pos.Y.Offset or 0)
        local w = (size.X.Scale or 0) * pw + (size.X.Offset or 0)
        local h = (size.Y.Scale or 0) * ph + (size.Y.Offset or 0)
        x = x - (ap.X or 0) * w
        y = y - (ap.Y or 0) * h
        rect = { x = x, y = y, w = w, h = h }
    end
    inst._vrect = rect

    local entry = {
        inst = inst, rect = rect, decor = decor, depth = depth,
        clip = clip, visible = inst.Visible ~= false, isLastSibling = isLastSibling,
        groupAlpha = groupAlpha,
    }
    out[#out + 1] = entry

    -- ScrollingFrame：内容整体偏移 CanvasPosition；默认裁剪
    local childBase = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    local childClip = clip
    if inst.ClassName == "ScrollingFrame" then
        local cp = inst.CanvasPosition or { X = 0, Y = 0 }
        local dir = enumName(inst.ScrollingDirection)
        if dir == "X" or dir == "XY" then childBase.x = childBase.x - (cp.X or 0) end
        if dir == "Y" or dir == "XY" then childBase.y = childBase.y - (cp.Y or 0) end
        local clips = explicit(inst, "ClipsDescendants")
        if clips == nil then clips = true end       -- ScrollingFrame 默认裁剪
        if clips then childClip = intersectClip(clip, rect) end
    elseif inst.ClipsDescendants then
        childClip = intersectClip(clip, rect)
    end

    -- CanvasGroup：GroupTransparency 影响整棵子树（向下传递）
    if inst.ClassName == "CanvasGroup" then
        groupAlpha = (groupAlpha or 1) * (1 - (inst.GroupTransparency or 0))
        entry.groupAlpha = groupAlpha
    end

    -- UIListLayout：按父矩形预算子级矩形，再用布局规则改写 x/y
    local content = applyPadding({ x = rect.x, y = rect.y, w = rect.w, h = rect.h }, decor)
    local listLayout = findDecor(decor, "UIListLayout")
    local presets = nil
    if listLayout then
        presets = {}
        for _, c in ipairs(kids) do
            local p = c.Position
            local s = c.Size
            local a = c.AnchorPoint or { X = 0, Y = 0 }
            local cw = (s.X.Scale or 0) * rect.w + (s.X.Offset or 0)
            local ch = (s.Y.Scale or 0) * rect.h + (s.Y.Offset or 0)
            presets[c] = {
                x = rect.x + (p.X.Scale or 0) * rect.w + (p.X.Offset or 0) - (a.X or 0) * cw,
                y = rect.y + (p.Y.Scale or 0) * rect.h + (p.Y.Offset or 0) - (a.Y or 0) * ch,
                w = cw, h = ch,
            }
        end
        applyListLayout(kids, content, listLayout, presets)
    end

    -- 绘制顺序 = DFS + 同层按 (ZIndex, 原始顺序) 稳定排序
    -- （ZIndexBehavior.Sibling 语义：ZIndex 只在兄弟间比较，子树整体顺序由兄弟层决定）
    local order = {}
    for i, c in ipairs(kids) do order[i] = { inst = c, idx = i } end
    table.sort(order, function(a, b)
        local za, zb = a.inst.ZIndex or 1, b.inst.ZIndex or 1
        if za ~= zb then return za < zb end
        return a.idx < b.idx
    end)
    for i, e in ipairs(order) do
        layoutObject(e.inst, childBase, childClip, depth + 1, out, i == #order,
            presets and presets[e.inst] or nil, groupAlpha)
    end
end

-- 主入口：布局所有 ScreenGui，回写 _abs，返回 [{gui, rect, entries}]
function Vision.computeLayout()
    local guis = {}
    for _, g in ipairs(M.screenGuis) do
        if g.Enabled ~= false then
            guis[#guis + 1] = g
        end
    end
    table.sort(guis, function(a, b)
        local da, db = a.DisplayOrder or 0, b.DisplayOrder or 0
        if da == db then return false end
        return da < db
    end)

    local result = {}
    for gi, g in ipairs(guis) do
        local rect = { x = 0, y = 0, w = Vision.viewport.w, h = Vision.viewport.h }
        g._vrect = rect
        local entries = {}
        local kids = {}
        for _, c in ipairs(rawget(g, "_children") or {}) do
            if not c._destroyed and c:IsA("GuiObject") then kids[#kids + 1] = c end
        end
        local order = {}
        for i, c in ipairs(kids) do order[i] = { inst = c, idx = i } end
        table.sort(order, function(a, b)
            local za, zb = a.inst.ZIndex or 1, b.inst.ZIndex or 1
            if za ~= zb then return za < zb end
            return a.idx < b.idx
        end)
        for i, e in ipairs(order) do
            layoutObject(e.inst, rect, nil, 1, entries, i == #order, nil, 1)
        end
        result[#result + 1] = { gui = g, rect = rect, entries = entries }
    end

    -- 回写 _abs：让库代码读到的 AbsolutePosition/AbsoluteSize 是真实值
    for _, gl in ipairs(result) do
        for _, e in ipairs(gl.entries) do
            local a = rawget(e.inst, "_abs")
            a.x, a.y, a.w, a.h = e.rect.x, e.rect.y, e.rect.w, e.rect.h
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- 渐变求值
-- ---------------------------------------------------------------------------

local function evalGradient(grad, rect, cx, cy)
    local kps = rawget(grad, "keypoints")
    if not kps or #kps == 0 then return nil end
    local rot = grad.Rotation or 0
    local t
    if rot == 0 then t = (cx - rect.x) / math.max(rect.w, 0.001)
    elseif rot == 90 then t = (cy - rect.y) / math.max(rect.h, 0.001)
    elseif rot == 180 then t = 1 - (cx - rect.x) / math.max(rect.w, 0.001)
    elseif rot == 270 then t = 1 - (cy - rect.y) / math.max(rect.h, 0.001)
    else t = (cx - rect.x) / math.max(rect.w, 0.001) end
    t = clamp(t, 0, 1)
    local prev = kps[1]
    for _, kp in ipairs(kps) do
        if (kp.Time or 0) > t then
            local span = (kp.Time or 0) - (prev.Time or 0)
            local f = span > 0 and (t - (prev.Time or 0)) / span or 1
            local c1 = prev.Value or prev.Color
            local c2 = kp.Value or kp.Color
            if c1 and c2 then
                return {
                    R = c1.R + (c2.R - c1.R) * f,
                    G = c1.G + (c2.G - c1.G) * f,
                    B = c1.B + (c2.B - c1.B) * f,
                }
            end
            return c2 or c1
        end
        prev = kp
    end
    return prev.Value or prev.Color
end

-- 计算某对象在某单元格中心处的背景色（含 UIGradient）与不透明度
local function cellBg(entry, cx, cy)
    local inst = entry.inst
    local alpha = 1 - (inst.BackgroundTransparency or 0)
    local color = inst.BackgroundColor3
    local grad = findDecor(entry.decor, "UIGradient")
    if grad and grad.Enabled ~= false then
        local gc = evalGradient(grad, entry.rect, cx, cy)
        if gc then color = gc end
    end
    return color, alpha
end

-- ---------------------------------------------------------------------------
-- 渲染：ASCII 画面 + 色彩网格
-- ---------------------------------------------------------------------------

local paintSeq = 0          -- 全局绘制序号（模拟 Roblox 的绘制先后）
local pendingRings = {}     -- 边框/描边环：本体画完后补绘，保证压在自身底色上、子级之下

local function newCanvas()
    local cols = math.max(1, math.ceil(Vision.viewport.w / Vision.cell.w))
    local rows = math.max(1, math.ceil(Vision.viewport.h / Vision.cell.h))
    local cells = {}
    for r = 1, rows do
        cells[r] = {}
        for c = 1, cols do
            cells[r][c] = { r = 0, g = 0, b = 0, a = 0, glyph = " ", kind = "empty" }
        end
    end
    return { cols = cols, rows = rows, cells = cells }
end

local function putCell(cv, col, row, glyph, color, alpha, kind, noOverwriteText)
    if col < 1 or col > cv.cols or row < 1 or row > cv.rows then return end
    local cell = cv.cells[row][col]
    -- 边框/描边不覆盖已有文字格（Roblox 中子级文字绘制在父级描边之上）
    if noOverwriteText and cell.kind == "text" then return end
    -- 颜色合成：src over dst
    local sa = clamp(alpha or 0, 0, 1)
    local da = cell.a
    local oa = sa + da * (1 - sa)
    if oa <= 0 then
        cell.r, cell.g, cell.b, cell.a = 0, 0, 0, 0
    else
        cell.r = ((color.R or 0) * sa + cell.r * da * (1 - sa)) / oa
        cell.g = ((color.G or 0) * sa + cell.g * da * (1 - sa)) / oa
        cell.b = ((color.B or 0) * sa + cell.b * da * (1 - sa)) / oa
        cell.a = oa
    end
    if glyph and sa > 0.02 then
        cell.glyph = glyph
        cell.kind = kind or cell.kind
        -- 文字格额外记录原始前景色（供 PNG 导出用字形色渲染，而非合成色）
        if kind == "text" then
            cell.fgR, cell.fgG, cell.fgB, cell.fgA = color.R or 0, color.G or 0, color.B or 0, sa
        end
    end
    paintSeq = paintSeq + 1
    cell.seq = paintSeq
end

-- 标记某格为"最新绘制"（圆角擦除用：阻止后绘环重新盖回来）
local function touchCell(cv, col, row)
    if col < 1 or col > cv.cols or row < 1 or row > cv.rows then return end
    paintSeq = paintSeq + 1
    cv.cells[row][col].seq = paintSeq
end

local function inClip(clip, x, y)
    if not clip then return true end
    return x >= clip.x - 0.01 and x < clip.x + clip.w - 0.01
        and y >= clip.y - 0.01 and y < clip.y + clip.h - 0.01
end

local function paintEntry(cv, entry)
    if not entry.visible then return end
    local inst = entry.inst
    local rect = entry.rect
    if rect.w <= 0 or rect.h <= 0 then return end
    local clip = entry.clip

    local cw, chh = Vision.cell.w, Vision.cell.h
    local col1 = math.max(1, math.floor(rect.x / cw) + 1)
    local col2 = math.min(cv.cols, math.floor((rect.x + rect.w - 0.001) / cw) + 1)
    local row1 = math.max(1, math.floor(rect.y / chh) + 1)
    local row2 = math.min(cv.rows, math.floor((rect.y + rect.h - 0.001) / chh) + 1)

    -- 1) 背景填充
    local ga = entry.groupAlpha or 1
    local bgA = (1 - (inst.BackgroundTransparency or 0)) * ga
    if bgA > 0.02 then
        for r = row1, row2 do
            for c = col1, col2 do
                local cx = (c - 1) * cw + cw / 2
                local cy = (r - 1) * chh + chh / 2
                if inClip(clip, cx, cy) then
                    local color, alpha = cellBg(entry, cx, cy)
                    local glyph = "░"
                    if alpha >= 0.85 then glyph = "░"
                    elseif alpha >= 0.45 then glyph = "▒"
                    else glyph = "·" end
                    putCell(cv, c, r, glyph, color, alpha, "bg")
                end
            end
        end
    end

    -- 2) ImageLabel 图像占位
    if (inst.ClassName == "ImageLabel" or inst.ClassName == "ImageButton")
        and type(inst.Image) == "string" and inst.Image ~= "" then
        local ia = (1 - (inst.ImageTransparency or 0)) * ga
        if ia > 0.02 then
            for r = row1, row2 do
                for c = col1, col2 do
                    local cx = (c - 1) * cw + cw / 2
                    local cy = (r - 1) * chh + chh / 2
                    if inClip(clip, cx, cy) then
                        putCell(cv, c, r, "▓", inst.ImageColor3 or { R = 1, G = 1, B = 1 }, ia, "image")
                    end
                end
            end
        end
    end

    -- 3) 边框（BorderSizePixel）→ 登记为后绘环
    if (inst.BorderSizePixel or 0) > 0 then
        local bc = inst.BorderColor3 or { R = 0, G = 0, B = 0 }
        pendingRings[#pendingRings + 1] = {
            seq = paintSeq, color = bc, alpha = 1, kind = "border",
            col1 = col1, col2 = col2, row1 = row1, row2 = row2,
            horiz = "-", vert = "|", corner = "+", clip = clip,
        }
    end

    -- 4) UIStroke 描边（#）→ 登记为后绘环
    local stroke = findDecor(entry.decor, "UIStroke")
    if stroke and (stroke.Thickness or 0) > 0 and (stroke.Transparency or 0) < 0.98 then
        local sc = stroke.Color or { R = 0, G = 0, B = 0 }
        local sa = (1 - (stroke.Transparency or 0)) * ga
        pendingRings[#pendingRings + 1] = {
            seq = paintSeq, color = sc, alpha = sa, kind = "stroke",
            col1 = col1, col2 = col2, row1 = row1, row2 = row2,
            horiz = "#", vert = "#", corner = "#", clip = clip,
        }
    end

    -- 5) 文本
    local tl = entry.textLayout
    if tl then
        local ta = (1 - (inst.TextTransparency or 0)) * ga
        if ta > 0.02 then
            local tc = inst.TextColor3 or { R = 1, G = 1, B = 1 }
            local xa = enumName(inst.TextXAlignment)
            local ya = enumName(inst.TextYAlignment)
            local blockH = #tl.lines * tl.lineH
            local blockX = rect.x
            if xa == "Center" then blockX = rect.x + (rect.w - tl.blockW) / 2
            elseif xa == "Right" then blockX = rect.x + rect.w - tl.blockW end
            local blockY = rect.y
            if ya == "Center" then blockY = rect.y + (rect.h - blockH) / 2
            elseif ya == "Bottom" then blockY = rect.y + rect.h - blockH end
            for li, line in ipairs(tl.lines) do
                if line ~= "" then
                    local lineY = blockY + (li - 1) * tl.lineH
                    local penX = blockX
                    for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                        -- 每字符占整数个网格（CJK 约 2 格，ASCII 1 格），保证不错位
                        local adv = math.max(1, math.floor(charPx(ch, tl.size, tl.em) / cw + 0.5))
                        local col = math.floor(penX / cw) + 1
                        local row = math.floor((lineY + tl.lineH * 0.22) / chh) + 1
                        local cx = (col - 1) * cw + cw / 2
                        local cy = (row - 1) * chh + chh / 2
                        if inClip(clip, cx, cy) then
                            putCell(cv, col, row, ch, tc, ta, "text")
                        end
                        penX = penX + adv * cw
                    end
                end
            end
        end
    end

    -- 6) UICorner 圆角擦除（仅擦自身底色格：中心落在圆角矩形外的格清空）
    local corner = findDecor(entry.decor, "UICorner")
    if corner then
        local radius = (corner.CornerRadius and corner.CornerRadius.Offset) or 0
        if radius > 0 then
            local function erase(cornerX, cornerY, sx, sy)
                local ax, ay = cornerX + sx * radius, cornerY + sy * radius
                for r = row1, row2 do
                    for c = col1, col2 do
                        local cx = (c - 1) * cw + cw / 2
                        local cy = (r - 1) * chh + chh / 2
                        -- 只处理圆角盒内的格（沿两轴距角点都不超过半径）
                        local ox, oy = (cx - cornerX) * sx, (cy - cornerY) * sy
                        if ox > 0 and oy > 0 and ox <= radius and oy <= radius then
                            local dx, dy = cx - ax, cy - ay
                            if dx * dx + dy * dy > radius * radius then
                                if c >= 1 and c <= cv.cols and r >= 1 and r <= cv.rows then
                                    local cell = cv.cells[r][c]
                                    cell.r, cell.g, cell.b, cell.a = 0, 0, 0, 0
                                    cell.glyph, cell.kind = " ", "empty"
                                    touchCell(cv, c, r)
                                end
                            end
                        end
                    end
                end
            end
            erase(rect.x, rect.y, 1, 1)
            erase(rect.x + rect.w, rect.y, -1, 1)
            erase(rect.x, rect.y + rect.h, 1, -1)
            erase(rect.x + rect.w, rect.y + rect.h, -1, -1)
        end
    end
end

-- 后绘环：只盖"比自己旧"的格（自身底色），不盖子级内容与文字
local function paintRing(cv, ring)
    local cw, chh = Vision.cell.w, Vision.cell.h
    local function cell(col, row, glyph)
        if col < 1 or col > cv.cols or row < 1 or row > cv.rows then return end
        local c = cv.cells[row][col]
        if c.kind == "text" then return end
        if (c.seq or 0) >= ring.seq then return end
        local cx = (col - 1) * cw + cw / 2
        local cy = (row - 1) * chh + chh / 2
        if not inClip(ring.clip, cx, cy) then return end
        putCell(cv, col, row, glyph, ring.color, ring.alpha, ring.kind)
    end
    for c = ring.col1, ring.col2 do
        cell(c, ring.row1, ring.horiz)
        cell(c, ring.row2, ring.horiz)
    end
    for r = ring.row1, ring.row2 do
        cell(ring.col1, r, ring.vert)
        cell(ring.col2, r, ring.vert)
    end
    cell(ring.col1, ring.row1, ring.corner)
    cell(ring.col2, ring.row1, ring.corner)
    cell(ring.col1, ring.row2, ring.corner)
    cell(ring.col2, ring.row2, ring.corner)
end

-- 预计算每个绘制条目的文本排版（在布局之后、渲染之前）
local function prepareTexts(layout)
    for _, gl in ipairs(layout) do
        for _, e in ipairs(gl.entries) do
            local inst = e.inst
            if inst.ClassName == "TextLabel" or inst.ClassName == "TextButton" then
                e.textLayout = layoutText(inst, e.rect)
                if e.textLayout then
                    local tl = e.textLayout
                    local availW = e.rect.w
                    if tl.blockW > availW + 0.5 and not (inst.TextWrapped or inst.TextScaled) then
                        e.warnings = e.warnings or {}
                        e.warnings[#e.warnings + 1] = string.format(
                            "文本溢出: %q 约 %.0fpx > %.0fpx", inst.Text, tl.blockW, availW)
                    end
                end
            end
            -- 视口溢出告警
            local r = e.rect
            if r.w > 0 and r.h > 0 then
                local msgs = e.warnings or {}
                if r.x < -0.5 or r.y < -0.5 or r.x + r.w > Vision.viewport.w + 0.5
                    or r.y + r.h > Vision.viewport.h + 0.5 then
                    msgs[#msgs + 1] = string.format(
                        "超出视口: (%.0f,%.0f) %.0fx%.0f 视口 %dx%d",
                        r.x, r.y, r.w, r.h, Vision.viewport.w, Vision.viewport.h)
                end
                if r.w < 0.5 or r.h < 0.5 then
                    msgs[#msgs + 1] = string.format("尺寸接近 0: %.1fx%.1f", r.w, r.h)
                end
                e.warnings = msgs
            end
        end
    end
end

function Vision.renderAscii(layout)
    paintSeq = 0
    pendingRings = {}
    local cv = newCanvas()
    for _, gl in ipairs(layout) do
        for _, e in ipairs(gl.entries) do
            paintEntry(cv, e)
        end
    end
    -- 补绘边框/描边环（压在自身底色上、子级之下）
    for _, ring in ipairs(pendingRings) do
        paintRing(cv, ring)
    end
    -- 拼装为字符串
    local out = {}
    for r = 1, cv.rows do
        local line = {}
        for c = 1, cv.cols do
            line[c] = cv.cells[r][c].glyph
        end
        out[#out + 1] = table.concat(line)
    end
    return table.concat(out, "\n"), cv
end

-- ---------------------------------------------------------------------------
-- 色彩网格
-- ---------------------------------------------------------------------------

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

function Vision.renderColorGrid(layout, cv)
    cv = cv or select(2, Vision.renderAscii(layout))
    local legend = {}       -- 量化色 -> {letter, hex, count}
    local letterOf = {}
    local grid = {}
    for r = 1, cv.rows do
        grid[r] = {}
        for c = 1, cv.cols do
            local cell = cv.cells[r][c]
            if cell.a < 0.03 then
                grid[r][c] = " "
            else
                local q = q4({ R = cell.r, G = cell.g, B = cell.b })
                local key = string.format("%x%x%x", q.r, q.g, q.b)
                local L = letterOf[key]
                if not L then
                    local idx = #legend + 1
                    if idx > #LETTERS then
                        L = "?"          -- 超出 62 色：合并为 ?
                        letterOf[key] = L
                    else
                        L = LETTERS:sub(idx, idx)
                        letterOf[key] = L
                        legend[#legend + 1] = { letter = L, hex = hexQ(q), count = 1, key = key }
                    end
                else
                    for _, e in ipairs(legend) do
                        if e.key == key then e.count = e.count + 1 break end
                    end
                end
                grid[r][c] = L
            end
        end
    end
    local lines = {}
    for r = 1, cv.rows do
        lines[#lines + 1] = table.concat(grid[r])
    end
    local legendLines = {}
    for _, e in ipairs(legend) do
        legendLines[#legendLines + 1] = string.format("%s=%s", e.letter, e.hex)
    end
    -- 每行 8 个图例
    local packed = {}
    for i = 1, #legendLines, 8 do
        local chunk = {}
        for j = i, math.min(i + 7, #legendLines) do chunk[#chunk + 1] = legendLines[j] end
        packed[#packed + 1] = "  " .. table.concat(chunk, "  ")
    end
    return table.concat(lines, "\n"), table.concat(packed, "\n")
end

-- ---------------------------------------------------------------------------
-- 结构树
-- ---------------------------------------------------------------------------

local function decorNote(inst, decor)
    local notes = {}
    local corner = findDecor(decor, "UICorner")
    if corner then
        notes[#notes + 1] = string.format("圆角r=%d", (corner.CornerRadius and corner.CornerRadius.Offset) or 0)
    end
    local stroke = findDecor(decor, "UIStroke")
    if stroke then
        notes[#notes + 1] = string.format("描边%s t=%.1f a=%.2f",
            hex(stroke.Color), stroke.Thickness or 0, 1 - (stroke.Transparency or 0))
    end
    local grad = findDecor(decor, "UIGradient")
    if grad and rawget(grad, "keypoints") and #rawget(grad, "keypoints") >= 2 then
        local kps = rawget(grad, "keypoints")
        local c1 = kps[1].Value or kps[1].Color
        local c2 = kps[#kps].Value or kps[#kps].Color
        notes[#notes + 1] = string.format("渐变%s→%s @%d°", hex(c1), hex(c2), grad.Rotation or 0)
    end
    local pad = findDecor(decor, "UIPadding")
    if pad then
        local l, r, t, b = pad.PaddingLeft.Offset, pad.PaddingRight.Offset,
            pad.PaddingTop.Offset, pad.PaddingBottom.Offset
        if l + r + t + b > 0 then
            notes[#notes + 1] = string.format("内边距 L%d R%d T%d B%d", l, r, t, b)
        end
    end
    local ll = findDecor(decor, "UIListLayout")
    if ll then
        notes[#notes + 1] = string.format("列表布局 %s pad=%d %s",
            enumName(ll.FillDirection), ll.Padding.Offset or 0, enumName(ll.SortOrder))
    end
    local grid = findDecor(decor, "UIGridLayout")
    if grid then
        notes[#notes + 1] = string.format("网格布局 cell=%dx%d",
            grid.CellSize.X.Offset, grid.CellSize.Y.Offset)
    end
    return notes
end

local function describeEntry(sb, entry, prefix, isLast)
    local inst = entry.inst
    local r = entry.rect
    local branch = isLast and "└─ " or "├─ "
    if prefix == "" then branch = "" end
    local head = string.format("%s%s%s \"%s\" Z=%d (%.0f,%.0f) %.0fx%.0f",
        prefix, branch, inst.ClassName, inst.Name, inst.ZIndex or 1, r.x, r.y, r.w, r.h)
    local notes = {}
    if not entry.visible then notes[#notes + 1] = "隐藏" end
    local bgA = (1 - (inst.BackgroundTransparency or 0)) * (entry.groupAlpha or 1)
    if bgA > 0.03 then
        local grad = findDecor(entry.decor, "UIGradient")
        if grad and grad.Enabled ~= false then
            notes[#notes + 1] = string.format("bg=渐变(a=%.2f)", bgA)
        else
            notes[#notes + 1] = string.format("bg=%s(a=%.2f)", hex(inst.BackgroundColor3), bgA)
        end
    end
    if inst.ClassName == "CanvasGroup" then
        notes[#notes + 1] = string.format("组透明 a=%.2f", entry.groupAlpha or 1)
    end
    if (inst.BorderSizePixel or 0) > 0 then
        notes[#notes + 1] = string.format("边框%dpx %s", inst.BorderSizePixel, hex(inst.BorderColor3))
    end
    local tl = entry.textLayout
    if tl then
        notes[#notes + 1] = string.format("text=%q %dpx %s %s/%s",
            inst.Text, tl.size, hex(inst.TextColor3),
            enumName(inst.TextXAlignment), enumName(inst.TextYAlignment))
        if inst.TextWrapped then notes[#notes + 1] = "自动换行" end
        if inst.TextScaled then notes[#notes + 1] = "文字缩放" end
    end
    if (inst.ClassName == "ImageLabel" or inst.ClassName == "ImageButton")
        and type(inst.Image) == "string" and inst.Image ~= "" then
        notes[#notes + 1] = "image=" .. inst.Image
    end
    if inst.ClassName == "ScrollingFrame" then
        notes[#notes + 1] = string.format("滚动 canvas=(%.0f,%.0f) %s",
            (inst.CanvasPosition or {}).X or 0, (inst.CanvasPosition or {}).Y or 0,
            inst.ClipsDescendants and "裁剪" or "不裁剪")
    end
    for _, n in ipairs(decorNote(inst, entry.decor)) do notes[#notes + 1] = n end
    if #notes > 0 then head = head .. "  [" .. table.concat(notes, "] [") .. "]" end
    sb[#sb + 1] = head
    for _, w in ipairs(entry.warnings or {}) do
        sb[#sb + 1] = prefix .. (isLast and "    " or "│   ") .. "!! " .. w
    end
end

function Vision.describeTree(layout)
    local sb = {}
    for _, gl in ipairs(layout) do
        sb[#sb + 1] = string.format("ScreenGui \"%s\"%s DisplayOrder=%d  (视口 %dx%d)",
            gl.gui.Name, gl.gui.Enabled == false and " [禁用]" or "",
            gl.gui.DisplayOrder or 0, Vision.viewport.w, Vision.viewport.h)
        -- entries 为 DFS 顺序：每层记录"最近节点是否为末个兄弟"即可重建树线
        local lastAtDepth = {}
        for _, e in ipairs(gl.entries) do
            local prefix = ""
            for k = 1, e.depth - 1 do
                prefix = prefix .. (lastAtDepth[k] and "    " or "│   ")
            end
            describeEntry(sb, e, prefix, e.isLastSibling)
            lastAtDepth[e.depth] = e.isLastSibling
        end
    end
    return table.concat(sb, "\n")
end

-- ---------------------------------------------------------------------------
-- 汇总快照
-- ---------------------------------------------------------------------------

function Vision.Snapshot(label, opts)
    opts = opts or {}
    local layout = Vision.computeLayout()
    prepareTexts(layout)
    local ascii, cv = Vision.renderAscii(layout)
    Vision.lastCanvas = cv          -- 供 PNG 导出（render_png.py）取用
    local cgrid, legend = Vision.renderColorGrid(layout, cv)
    local tree = Vision.describeTree(layout)

    print("")
    print("════════════════════════════════════════════════════════════")
    print(string.format("SNAPSHOT: %s   t=%.2fs   视口 %dx%d   网格 %dx%d",
        label or "(未命名)", M.vclock and M.vclock() or 0,
        Vision.viewport.w, Vision.viewport.h, cv.cols, cv.rows))
    print("────────────────────────────────────────────────────────────")
    print("■ 结构树")
    print(tree)
    print("────────────────────────────────────────────────────────────")
    print("■ ASCII 画面（░=不透明 ▒=半透 ·=高透 #=描边 +=边框 |=边 -=上下边 ▓=图像）")
    print(ascii)
    print("────────────────────────────────────────────────────────────")
    print("■ 色彩网格（空格=完全透明；色彩已量化到 4bit/通道）")
    print(cgrid)
    if legend ~= "" then
        print("图例:")
        print(legend)
    end
    local warns = {}
    for _, gl in ipairs(layout) do
        for _, e in ipairs(gl.entries) do
            for _, w in ipairs(e.warnings or {}) do
                warns[#warns + 1] = string.format("%s/%s: %s", gl.gui.Name, e.inst.Name, w)
            end
        end
    end
    print("────────────────────────────────────────────────────────────")
    if #warns > 0 then
        print("■ 布局告警 (" .. #warns .. ")")
        for _, w in ipairs(warns) do print("  ! " .. w) end
    else
        print("■ 布局告警: 无")
    end
    print("════════════════════════════════════════════════════════════")
    return layout
end

-- ---------------------------------------------------------------------------
-- PNG 导出：把 canvas 序列化为 Python 可解析的字符串
--   colors: 每格 8 个 hex 字符（RRGGBBAA），按行优先拼接
--   glyphs: 每格 1 个字符（可能为多字节 UTF-8，Python 侧按 Unicode 解码后索引）
-- ---------------------------------------------------------------------------
function Vision.encodeCanvas(cv)
    cv = cv or Vision.lastCanvas
    if not cv then return nil end
    local ct = {}
    local gt = {}
    local ft = {}
    for r = 1, cv.rows do
        for c = 1, cv.cols do
            local cell = cv.cells[r][c]
            local rr = math.floor(clamp(cell.r or 0, 0, 1) * 255 + 0.5)
            local gg = math.floor(clamp(cell.g or 0, 0, 1) * 255 + 0.5)
            local bb = math.floor(clamp(cell.b or 0, 0, 1) * 255 + 0.5)
            local aa = math.floor(clamp(cell.a or 0, 0, 1) * 255 + 0.5)
            ct[#ct + 1] = string.format("%02X%02X%02X%02X", rr, gg, bb, aa)
            gt[#gt + 1] = cell.glyph or " "
            -- 前景色（仅文字格非 0；无前景 alpha=00）
            local fa = math.floor(clamp(cell.fgA or 0, 0, 1) * 255 + 0.5)
            if fa > 0 then
                ft[#ft + 1] = string.format("%02X%02X%02X%02X",
                    math.floor(clamp(cell.fgR or 0, 0, 1) * 255 + 0.5),
                    math.floor(clamp(cell.fgG or 0, 0, 1) * 255 + 0.5),
                    math.floor(clamp(cell.fgB or 0, 0, 1) * 255 + 0.5),
                    fa)
            else
                ft[#ft + 1] = "00000000"
            end
        end
    end
    return {
        cols = cv.cols,
        rows = cv.rows,
        cellW = Vision.cell.w,
        cellH = Vision.cell.h,
        colors = table.concat(ct),
        glyphs = table.concat(gt),
        fgs = table.concat(ft),
    }
end

-- 便捷查询：按名字/类/文本找对象（返回 inst, rect）
function Vision.findByName(name)
    local layout = Vision.computeLayout()
    for _, gl in ipairs(layout) do
        for _, e in ipairs(gl.entries) do
            if e.inst.Name == name then return e.inst, e.rect end
        end
    end
    return nil
end

function Vision.findByText(text, exact)
    local layout = Vision.computeLayout()
    for _, gl in ipairs(layout) do
        for _, e in ipairs(gl.entries) do
            local t = e.inst.Text
            if type(t) == "string" and t ~= "" then
                if (exact and t == text) or (not exact and t:find(text, 1, true)) then
                    return e.inst, e.rect
                end
            end
        end
    end
    return nil
end

function Vision.findFirstOfClass(className)
    local layout = Vision.computeLayout()
    for _, gl in ipairs(layout) do
        for _, e in ipairs(gl.entries) do
            if e.inst.ClassName == className then return e.inst, e.rect end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 矢量绘制列表（供高分辨率 PNG 渲染器 render_hires.py 使用）
-- 与 ASCII/色彩网格不同：这里输出【每个 GuiObject 的精确矩形 + 完整样式】，
-- 让 Python 侧以超采样 + 真实字体矢量绘制出清晰锐利的 UI 图。
-- 条目顺序 = 布局 DFS + 同层 (ZIndex, 原始序) 排序 = Roblox 绘制先后。
-- ---------------------------------------------------------------------------
local function colorOf(c)
    if type(c) ~= "table" then return nil end
    return { r = c.R or 0, g = c.G or 0, b = c.B or 0 }
end

local function cornerOf(decor, rect)
    local corner = findDecor(decor, "UICorner")
    if not corner then return 0 end
    local cr = corner.CornerRadius
    if type(cr) == "table" then
        return (cr.Scale or 0) * math.min(rect.w, rect.h) + (cr.Offset or 0)
    end
    return 0
end

local function gradInfo(decor)
    local grad = findDecor(decor, "UIGradient")
    if not grad or grad.Enabled == false then return nil end
    local kps = rawget(grad, "keypoints")
    if not kps or #kps == 0 then return nil end
    local out = { rotation = grad.Rotation or 0, kps = {} }
    for _, kp in ipairs(kps) do
        local c = kp.Value or kp.Color
        out.kps[#out.kps + 1] = {
            t = kp.Time or 0,
            r = c and c.R or 0, g = c and c.G or 0, b = c and c.B or 0,
        }
    end
    if #out.kps == 0 then return nil end
    return out
end

local function strokeInfo(decor, ga)
    local stroke = findDecor(decor, "UIStroke")
    if not stroke or (stroke.Thickness or 0) <= 0 then return nil end
    local a = (1 - (stroke.Transparency or 0)) * ga
    if a <= 0.02 then return nil end
    local c = stroke.Color or { R = 0, G = 0, B = 0 }
    return { thickness = stroke.Thickness or 0, a = a, r = c.R or 0, g = c.G or 0, b = c.B or 0 }
end

local function padInfo(decor)
    local pad = findDecor(decor, "UIPadding")
    if not pad then return nil end
    return {
        l = pad.PaddingLeft.Offset, r = pad.PaddingRight.Offset,
        t = pad.PaddingTop.Offset, b = pad.PaddingBottom.Offset,
    }
end

function Vision.buildDrawList()
    local layout = Vision.computeLayout()
    local ops = {}
    local seq = 0
    for _, gl in ipairs(layout) do
        for _, e in ipairs(gl.entries) do
            local inst = e.inst
            if e.visible and e.rect.w > 0.001 and e.rect.h > 0.001 then
                seq = seq + 1
                local ga = e.groupAlpha or 1
                local cls = inst.ClassName or ""
                local isText = (cls == "TextLabel" or cls == "TextButton" or cls == "TextBox")
                local isImage = (cls == "ImageLabel" or cls == "ImageButton")
                local op = {
                    seq = seq, class = cls, name = inst.Name or "",
                    x = e.rect.x, y = e.rect.y, w = e.rect.w, h = e.rect.h,
                    clip = e.clip,
                    bgAlpha = (1 - (inst.BackgroundTransparency or 0)) * ga,
                    bg = colorOf(inst.BackgroundColor3),
                    corner = cornerOf(e.decor, e.rect),
                    stroke = strokeInfo(e.decor, ga),
                    gradient = gradInfo(e.decor),
                    pad = padInfo(e.decor),
                }
                if (inst.BorderSizePixel or 0) > 0 then
                    op.border = {
                        size = inst.BorderSizePixel,
                        color = colorOf(inst.BorderColor3) or { r = 0, g = 0, b = 0 },
                    }
                end
                if isImage and type(inst.Image) == "string" and inst.Image ~= "" then
                    op.image = true
                    op.imageColor = colorOf(inst.ImageColor3) or { r = 1, g = 1, b = 1 }
                    op.imageAlpha = (1 - (inst.ImageTransparency or 0)) * ga
                end
                if isText then
                    local tc = inst.TextColor3 or { R = 1, G = 1, B = 1 }
                    local txt = tostring(inst.Text or "")
                    if inst.RichText then txt = stripTags(txt) end
                    op.text = txt
                    op.textColor = { r = tc.R or 0, g = tc.G or 0, b = tc.B or 0 }
                    op.textAlpha = (1 - (inst.TextTransparency or 0)) * ga
                    op.textSize = inst.TextSize or 14
                    op.font = enumName(inst.Font) or "SourceSans"
                    op.xa = enumName(inst.TextXAlignment) or "Left"
                    op.ya = enumName(inst.TextYAlignment) or "Top"
                    op.wrapped = inst.TextWrapped and true or false
                    op.scaled = inst.TextScaled and true or false
                end
                ops[#ops + 1] = op
            end
        end
    end
    return ops
end

Vision.DECOR_CLASSES = DECOR_CLASSES
return Vision
