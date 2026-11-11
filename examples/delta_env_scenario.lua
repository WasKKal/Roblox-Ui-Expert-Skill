-- ==========================================
-- delta_env_scenario.lua — Delta 执行器环境特征差分回归
-- ==========================================
-- 来源：delta_mock.txt 的 B 层（Delta 行为：_G = 0 字段空共享表）。
-- 用 DeltaEnv.build(mode, snap) 纯函数在【一次运行】里遍历 9 种 DELTA_MODE，
-- 断言每种模式下 _G / getgenv / getfenv / getrenv 的语义差异。
--
-- 运行（必须带 --delta-mode，否则 delta_env.lua 不会加载）：
--   python3 scripts/run_ui.py --scenario examples/delta_env_scenario.lua \
--       --delta-mode getfenv_real --no-final-snapshot
--   python3 scripts/run_ui_luau.py --scenario examples/delta_env_scenario.lua \
--       --delta-mode getfenv_real --style none --pump-after 0 --out /tmp/x.png
--
-- 也可用 scripts/check_delta_env.py 自动跑 9 模式 × 双路径。
-- ==========================================

if type(DeltaEnv) ~= "table" then
    check("DeltaEnv 已加载", false, "请用 --delta-mode <mode> 运行本场景")
    __HARNESS.summary()
    return
end
check("DeltaEnv 已加载", true)

local MODES = DeltaEnv.MODES
check("模式矩阵共 9 种", #MODES == 9, "count=" .. tostring(#MODES))

-- 预期表：每种模式的 [sharedG, getgenv, getfenv, getrenv] 语义
local EXPECT = {
    getfenv_real  = { g = "table",  genv = "real",    fenv = "real",    renv = "none" },
    getfenv_empty = { g = "table",  genv = "real",    fenv = "shared",  renv = "none" },
    getfenv_err   = { g = "table",  genv = "real",    fenv = "error",   renv = "none" },
    no_getfenv    = { g = "table",  genv = "real",    fenv = "nil",     renv = "none" },
    no_getgenv    = { g = "table",  genv = "nil",     fenv = "shared",  renv = "none" },
    getrenv_real  = { g = "table",  genv = "nil",     fenv = "shared",  renv = "real"   },
    getrenv_empty = { g = "table",  genv = "nil",     fenv = "shared",  renv = "shared" },
    getrenv_nil   = { g = "table",  genv = "nil",     fenv = "shared",  renv = "nilval" },
    G_nil         = { g = "nil",    genv = "real",    fenv = "real",    renv = "none" },
}

for _, mode in ipairs(MODES) do
    local e = DeltaEnv.build(mode, false)
    local ex = EXPECT[mode]
    check(mode .. " 有预期定义", ex ~= nil)

    -- 1) _G 是 0 字段空共享表，或 nil
    if ex.g == "nil" then
        check(mode .. " _G = nil", e.sharedG == nil)
    else
        check(mode .. " _G 为表", type(e.sharedG) == "table")
        check(mode .. " _G 0 字段", next(e.sharedG) == nil,
            "first=" .. tostring(next(e.sharedG)))
    end

    -- 2) REAL_ENV 独立且能回落到真实全局（Delta 下脚本仍可访问 game 等）
    check(mode .. " REAL_ENV 独立", type(e.realEnv) == "table"
        and e.realEnv ~= e.sharedG)
    check(mode .. " REAL_ENV 回落全局", e.realEnv.game ~= nil,
        "game=" .. tostring(e.realEnv.game))

    -- 3) getgenv
    if ex.genv == "nil" then
        check(mode .. " getgenv 缺失", e.getgenv == nil)
    else
        local ok, got = pcall(e.getgenv)
        check(mode .. " getgenv 返回 REAL_ENV", ok and got == e.realEnv)
        check(mode .. " getgenv ~= _G", got ~= e.sharedG)
    end

    -- 4) getfenv 四态
    if ex.fenv == "nil" then
        check(mode .. " getfenv 缺失", e.getfenv == nil)
    elseif ex.fenv == "error" then
        local ok = pcall(e.getfenv)
        check(mode .. " getfenv 抛错", ok == false)
    else
        local ok, got = pcall(e.getfenv)
        local want = (ex.fenv == "real") and e.realEnv or e.sharedG
        check(mode .. " getfenv -> " .. ex.fenv, ok and got == want)
    end

    -- 5) getrenv 四态（含「存在但返回 nil」）
    if ex.renv == "none" then
        check(mode .. " getrenv 未定义", e.getrenv == nil)
    elseif ex.renv == "nilval" then
        local ok, got = pcall(e.getrenv)
        check(mode .. " getrenv 返回 nil", ok and got == nil)
    else
        local ok, got = pcall(e.getrenv)
        local want = (ex.renv == "real") and e.realEnv or e.sharedG
        check(mode .. " getrenv -> " .. ex.renv, ok and got == want)
    end

    -- 6) setfenv 恒为 no-op
    check(mode .. " setfenv no-op", type(e.setfenv) == "function"
        and e.setfenv(1, {}) == nil)
end

-- ---------- DBG_SNAP：缺失键记录 ----------
local s = DeltaEnv.build("getfenv_real", true)
check("DBG_SNAP 提供 DBGDUMP", type(s.dump) == "function")
local probe = s.sharedG.NotDefinedAnywhere
check("访问空 _G 返回 nil", probe == nil)
check("DBG_SNAP 记录缺失键", #s.record == 1 and s.record[1] == "NotDefinedAnywhere",
    "record=" .. table.concat(s.record, ","))
local dumped = s.dump()
check("DBGDUMP 返回记录表", type(dumped) == "table" and #dumped == 1)

-- ---------- 运行时已安装的 Delta 语义 ----------
local rep = DeltaEnv.report()
check("apply 已执行", type(rep) == "table" and rep.mode ~= nil)
check("[delta-sim] 诊断字段齐全", type(rep.gType) == "string"
    and type(rep.gameType) == "string" and type(rep.applied) == "table")

check("checkcaller 恒 true（差分信任）", type(checkcaller) == "function"
    and checkcaller() == true)
check("iscclosure 识别 C 闭包", type(iscclosure) == "function"
    and iscclosure(typeof) == true)
check("iscclosure 不误判 Lua 闭包", iscclosure(function() end) == false)
check("islclosure 识别 Lua 闭包", type(islclosure) == "function"
    and islclosure(function() end) == true)

-- ---------- A 层：typeof / Instance 语义（delta_mock.txt 前半段） ----------
check("typeof 识别 Instance", typeof(Instance.new("Frame")) == "Instance")
check("typeof 识别 UDim2", typeof(UDim2.new(0, 1, 0, 2)) == "UDim2")
check("typeof 识别 Color3", typeof(Color3.new(1, 0, 0)) == "Color3")
check("typeof 识别 Vector2", typeof(Vector2.new(1, 2)) == "Vector2")

local parent = Instance.new("Frame")
local kid = Instance.new("UICorner")
kid.Parent = parent
check("FindFirstChildOfClass 可命中", parent:FindFirstChildOfClass("UICorner") == kid)
check("GetChildren 含子节点", #parent:GetChildren() == 1)
kid:Destroy()
check("Destroy 从父移除", #parent:GetChildren() == 0)
check("AbsolutePosition 为 Vector2",
    typeof(parent.AbsolutePosition) == "Vector2")
check("AbsoluteSize 为 Vector2", typeof(parent.AbsoluteSize) == "Vector2")

__HARNESS.summary()
