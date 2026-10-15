-- ============================================================================
-- harness.lua — 场景驱动 + 断言收集（Agent 与 UI 的"交互层"）
-- 提供场景脚本可直接使用的全局：
--   Snapshot(label)      打印结构树/ASCII/色彩网格/告警（= Vision.Snapshot）
--   check(label, cond)   记录一条断言，立即打印 [PASS]/[FAIL]
--   pump(seconds)        推进虚拟时钟（会触发 RenderStepped/Heartbeat 与到期协程）
--   tapUI(inst)          模拟一次完整点击（Began+Ended+Click+Activated）
--   fireUI(inst,ev,in)   触发指定输入事件
--   findByName/findByText/findFirstOfClass   布局后按条件查找
--   guiRoot()/countInstances()/dumpWarnings()/vclockNow()
-- 由 run_ui.py 在 mock_runtime.lua、vision.lua 之后加载
-- ============================================================================

local H = {}
__HARNESS = H   -- 裸全局导出（lupa 下写入 _G；luau 下写入共享默认环境）

H.checks = { pass = 0, fail = 0 }
H.errors = {}          -- 场景运行期错误（Lua 报错/超时/停滞）
H.snapshots = 0

local M = __MOCK
local Vision = Vision

-- ---------------------------------------------------------------------------
-- 断言
-- ---------------------------------------------------------------------------

function check(label, cond, detail)
    if cond then
        H.checks.pass = H.checks.pass + 1
        print(string.format("[PASS] %s", label))
    else
        H.checks.fail = H.checks.fail + 1
        print(string.format("[FAIL] %s%s", label, detail and ("  -> " .. tostring(detail)) or ""))
    end
    return cond
end

function checkEqual(label, got, want)
    return check(label, got == want, string.format("got=%s want=%s", tostring(got), tostring(want)))
end

function checkNear(label, got, want, tol)
    tol = tol or 0.51
    return check(label, type(got) == "number" and math.abs(got - want) <= tol,
        string.format("got=%s want=%s±%s", tostring(got), tostring(want), tostring(tol)))
end

-- ---------------------------------------------------------------------------
-- 场景驱动
-- ---------------------------------------------------------------------------

-- 驱动场景协程直到结束；返回 {frames=, seconds=}
-- 场景经 task.wait 让出时由调度器在帧步进中自动恢复
function H.drive(co, opts)
    opts = opts or {}
    local maxSeconds = opts.maxSeconds or 300
    local frames = 0
    local maxFrames = maxSeconds * 60
    -- 协程错误升级为硬错误（默认只 warn）
    M.onCoroutineError = function(msg)
        H.errors[#H.errors + 1] = "场景协程报错: " .. tostring(msg)
    end
    M.enqueue({ at = M.vclock(), co = co, args = {} })
    while coroutine.status(co) ~= "dead" do
        frames = frames + 1
        if frames > maxFrames then
            H.errors[#H.errors + 1] = string.format("场景超过最大虚拟时间 %ds 未结束", maxSeconds)
            break
        end
        M.pumpFrame()
    end
    -- 场景结束后把剩余到期协程跑干净（最多再 3 秒，避免动画悬挂）
    for _ = 1, 180 do
        if M.queueLength() == 0 then break end
        M.pumpFrame()
    end
    return { frames = frames, seconds = M.vclock() }
end

-- 编译并运行一段场景源码；返回 {ok=bool, err=?}
function H.runScenario(src, name, opts)
    name = name or "scenario"
    local chunk, err = loadstring(src, "@" .. name)
    if not chunk then
        H.errors[#H.errors + 1] = "场景编译失败: " .. tostring(err)
        return { ok = false, err = err }
    end
    local co = coroutine.create(chunk)
    local info = H.drive(co, opts)
    print(string.format("[harness] 场景结束: %d 帧 / 虚拟时间 %.2fs", info.frames, info.seconds))
    return { ok = true, frames = info.frames, seconds = info.seconds }
end

-- ---------------------------------------------------------------------------
-- 场景可用的全局
-- ---------------------------------------------------------------------------

function Snapshot(label)
    H.snapshots = H.snapshots + 1
    return Vision.Snapshot(label)
end

-- pump(seconds)：在协程内让出，由驱动循环推进虚拟时间（不会触发嵌套告警）；
-- 不在协程内（主线程直调）时退化为 pumpSeconds
function pump(seconds)
    seconds = seconds or 0
    local yielded = false
    pcall(function()
        -- 逐帧让出（1/60 一步），让 Heartbeat/RenderStepped 每帧触发，
        -- 真实库里依赖帧事件推进的动画（loader / 补间手柄）才能正常推进。
        local steps = math.ceil(seconds / (1 / 60))
        for _ = 1, steps do
            coroutine.yield(1 / 60)
        end
        yielded = true
    end)
    if not yielded then
        M.pumpSeconds(seconds)
    end
end

function tapUI(inst, opts)
    if not inst then
        M.warn("tapUI: 目标为 nil")
        return
    end
    M.tap(inst, opts)
end

function fireUI(inst, eventName, input)
    if not inst then
        M.warn("fireUI: 目标为 nil")
        return
    end
    M.fireInput(inst, eventName, input or M.mkInput())
end

function mkInput(opts) return M.mkInput(opts) end

function findByName(name)
    local inst = Vision.findByName(name)
    return inst
end

function findByText(text, exact)
    return Vision.findByText(text, exact)
end

function findFirstOfClass(className)
    return Vision.findFirstOfClass(className)
end

-- 返回 (inst, rect)
function findByNameR(name) return Vision.findByName(name) end
function findByTextR(text, exact) return Vision.findByText(text, exact) end
function findFirstOfClassR(className) return Vision.findFirstOfClass(className) end

function guiRoot()
    for _, g in ipairs(M.screenGuis) do
        if g.Enabled ~= false then return g end
    end
    return nil
end

function countInstances()
    local n = 0
    local function walk(inst)
        for _, c in ipairs(rawget(inst, "_children") or {}) do
            if not c._destroyed then
                n = n + 1
                walk(c)
            end
        end
    end
    for _, g in ipairs(M.screenGuis) do walk(g) end
    return n
end

function dumpWarnings()
    local w = M.warnings
    if #w == 0 then
        print("[warnings] 无")
    else
        print(string.format("[warnings] 共 %d 条:", #w))
        for i, msg in ipairs(w) do
            print(string.format("  %d. %s", i, msg))
        end
    end
    return #w
end

function vclockNow() return M.vclock() end

function tweenCount() return #M.tweenLog end

-- ---------------------------------------------------------------------------
-- 把场景结果序列化到 JSON（供真实 luau 解释器路径的 Python 渲染器读取）
-- ---------------------------------------------------------------------------

local function jsonValue(v, out)
    local t = type(v)
    if t == "nil" then
        out[#out + 1] = "null"
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then
            out[#out + 1] = string.format("%d", v)
        else
            out[#out + 1] = string.format("%.6g", v)
        end
    elseif t == "string" then
        out[#out + 1] = "\""
        local s = v
        for i = 1, #s do
            local ch = string.sub(s, i, i)
            local b = string.byte(ch)
            if ch == "\"" then out[#out + 1] = "\\\""
            elseif ch == "\\" then out[#out + 1] = "\\\\"
            elseif ch == "\n" then out[#out + 1] = "\\n"
            elseif ch == "\t" then out[#out + 1] = "\\t"
            elseif ch == "\r" then out[#out + 1] = "\\r"
            elseif b < 32 then out[#out + 1] = string.format("\\u%04x", b)
            else out[#out + 1] = ch end
        end
        out[#out + 1] = "\""
    elseif t == "table" then
        -- 数组判定：连续整数键 1..#t
        local n = #v
        local isArr = true
        for k, _ in pairs(v) do
            if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
                isArr = false; break
            end
        end
        if isArr then
            out[#out + 1] = "["
            for i = 1, n do
                if i > 1 then out[#out + 1] = "," end
                jsonValue(v[i], out)
            end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for k, val in pairs(v) do
                if type(k) == "string" then
                    if not first then out[#out + 1] = "," end
                    first = false
                    out[#out + 1] = "\"" .. k .. "\":"
                    jsonValue(val, out)
                end
            end
            out[#out + 1] = "}"
        end
    else
        out[#out + 1] = "null"
    end
end

function EmitReport(path)
    path = path or "report.json"
    -- 确保画布已生成
    if not Vision.lastCanvas then Vision.Snapshot("luau_render") end
    local cv = Vision.encodeCanvas(Vision.lastCanvas)
    -- 结构树
    local layout = Vision.computeLayout()
    local nodes = {}
    for _, gl in ipairs(layout) do
        for _, e in ipairs(gl.entries) do
            local inst = e.inst
            nodes[#nodes + 1] = {
                name = inst.Name or "",
                class = inst.ClassName or "",
                x = math.floor(e.rect.x + 0.5),
                y = math.floor(e.rect.y + 0.5),
                w = math.floor(e.rect.w + 0.5),
                h = math.floor(e.rect.h + 0.5),
                z = inst.ZIndex or 1,
                visible = e.visible ~= false,
            }
        end
    end
    local report = {
        engine = "luau",
        viewport = { w = Vision.viewport.w, h = Vision.viewport.h },
        cell = { w = cv.cellW, h = cv.cellH },
        canvas = {
            cols = cv.cols, rows = cv.rows,
            colors = cv.colors, glyphs = cv.glyphs, fg = cv.fgs,
        },
        structure = nodes,
        draws = Vision.buildDrawList(),   -- 矢量绘制列表（高分辨率渲染用）
        checks = { pass = H.checks.pass, fail = H.checks.fail },
        errors = H.errors,
        warnings = M.warnings,
        tweenCount = #M.tweenLog,
    }
    local out = {}
    jsonValue(report, out)
    -- 通过 stdout 输出带哨兵的 JSON（真实 luau 解释器禁用了 io 库，
    -- 故不走文件，而由 Python 启动器从 stdout 抽取）
    print("\n--ROBLOXUI_JSON_BEGIN--")
    print(table.concat(out))
    print("--ROBLOXUI_JSON_END--")
    return true
end

-- 汇总输出（由 run_ui.py 在场景结束后调用）
function H.summary()
    print("")
    print("──────── 运行汇总 ────────")
    print(string.format("断言: 通过 %d / 失败 %d", H.checks.pass, H.checks.fail))
    print(string.format("快照: %d 次", H.snapshots))
    print(string.format("Tween: %d 次", #M.tweenLog))
    local nw = #M.warnings
    print(string.format("mock 警告: %d 条", nw))
    if nw > 0 then dumpWarnings() end
    if #H.errors > 0 then
        print(string.format("错误: %d 条", #H.errors))
        for _, e in ipairs(H.errors) do print("  ! " .. e) end
    else
        print("错误: 0 条")
    end
    print("──────────────────────────")
    return H.checks.fail == 0 and #H.errors == 0
end

return H
