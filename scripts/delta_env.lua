-- delta_env.lua — Delta 执行器环境特征层（可选模块）
--
-- 来源：用户提供的 delta_mock.txt（「Roblox/Luau 执行器环境 mock，红蓝对抗 +
-- 复杂脚本验证用」）。该文件分两层：
--   A 层：通用执行器代理（_G 可写代理 + 活 globals 双写、执行器函数族、
--         checkcaller 恒 true、iscclosure 的 C_SET 判定、debug/bit、typeof
--         标记识别、Instance 语义、服务 mock）——本工具 mock_runtime.lua /
--         executor_api.lua 已覆盖，见 DELTA_FEATURES。
--   B 层：Delta 特有的环境指纹——本文件实现的部分：
--         * _G 是 0 字段空共享表，或 nil（不是真实全局环境）
--         * getgenv() 返回独立的 REAL_ENV 代理（__index 回落真实全局），≠ _G
--         * getfenv() 4 态：REAL_ENV / 空 _G / 抛错 / 缺失
--         * getrenv() 3 态：REAL_ENV / 空 _G / nil
--         * setfenv() no-op
--         * DELTA_MODE 9 种模式矩阵
--         * DBG_SNAP：记录对 _G 的缺失键访问，DBGDUMP() 输出 MISSING_KEYS
--         * [delta-sim] 启动诊断行
--
-- 加载时机：必须在 mock_runtime / executor_api / vision / harness 之后
-- （由 --delta-mode 触发），因为 apply() 会覆盖 getfenv / getgenv 等裸全局，
-- 而上述模块在加载阶段依赖真实 getfenv(0)。工具内部通过裸全局名共享状态，
-- 不依赖 _G，因此把 _G 换成空表不会破坏渲染引擎。
--
-- 对外接口：
--   DeltaEnv.MODES                 9 种模式名
--   DeltaEnv.build(mode, snap)    纯函数，构造并返回一套环境（不改全局）
--   DeltaEnv.apply(mode, snap)    把环境安装到运行时，返回诊断表
--   DeltaEnv.report()             返回最近一次 apply 的诊断表
--   DeltaEnv.isC(f)               Delta 语义的 C 闭包判定

local G = getfenv(0)          -- 真实可写默认全局环境；apply 后 getfenv 可能被覆盖，先捕获
local DeltaEnv = {}

DeltaEnv.MODES = {
    "getfenv_real", "getfenv_empty", "getfenv_err", "no_getfenv",
    "no_getgenv", "getrenv_real", "getrenv_empty", "getrenv_nil", "G_nil",
}

local NOOP = function() end

-- A 层：C 闭包集合（弱键），配合 debug.getinfo 实现真实的 iscclosure 语义
local C_SET = setmetatable({}, { __mode = "k" })
local function markC(f)
    if type(f) == "function" then C_SET[f] = true end
    return f
end

function DeltaEnv.isC(f)
    if type(f) ~= "function" then return false end
    if C_SET[f] then return true end
    local ok, info = pcall(debug.getinfo, f, "S")
    return ok and type(info) == "table" and info.what == "C"
end
DeltaEnv.markC = markC

-- 构造一套 Delta 环境（纯函数，可供差分回归在一次运行里遍历 9 种模式）
function DeltaEnv.build(mode, snap)
    mode = mode or "getfenv_real"
    snap = snap and true or false

    -- Delta 行为：_G = 0 字段空共享表，或 nil
    local sharedG
    if mode == "G_nil" then sharedG = nil else sharedG = {} end

    -- REAL_ENV：独立代理表，未命中字段回落到真实全局环境
    local REAL_ENV = setmetatable({}, { __index = G })

    REAL_ENV.getgenv = function() return REAL_ENV end
    REAL_ENV.getfenv = function(_)
        if mode == "getfenv_empty" then return sharedG end
        if mode == "getfenv_err" then error("getfenv unsupported", 0) end
        return REAL_ENV
    end
    REAL_ENV.setfenv = NOOP

    if mode == "no_getfenv" then
        REAL_ENV.getfenv = nil
    end
    if mode == "no_getgenv" then
        REAL_ENV.getgenv = nil
        REAL_ENV.getfenv = function() return sharedG end
    end
    if mode == "getrenv_real" then
        REAL_ENV.getgenv = nil
        REAL_ENV.getfenv = function() return sharedG end
        REAL_ENV.getrenv = function() return REAL_ENV end
    elseif mode == "getrenv_empty" then
        REAL_ENV.getgenv = nil
        REAL_ENV.getfenv = function() return sharedG end
        REAL_ENV.getrenv = function() return sharedG end
    elseif mode == "getrenv_nil" then
        REAL_ENV.getgenv = nil
        REAL_ENV.getfenv = function() return sharedG end
        REAL_ENV.getrenv = function() return nil end
    end

    -- DBG_SNAP：给空 _G 装上 __index 记录器，捕获脚本访问了哪些未定义全局
    local RECORD = {}
    local dump = nil
    if snap and type(sharedG) == "table" then
        setmetatable(sharedG, {
            __index = function(_, k)
                RECORD[#RECORD + 1] = tostring(k)
                return nil
            end,
        })
        dump = function()
            print("MISSING_KEYS: " .. table.concat(RECORD, ","))
            return RECORD
        end
    end

    -- 必须用 rawget：REAL_ENV 有 __index 回落，普通取键会把工具已有的
    -- getgenv/getfenv/getrenv 全局「带回来」，使「该模式缺失」的判断失真。
    return {
        mode = mode,
        snap = snap,
        realEnv = REAL_ENV,
        sharedG = sharedG,
        getgenv = rawget(REAL_ENV, "getgenv"),
        getfenv = rawget(REAL_ENV, "getfenv"),
        getrenv = rawget(REAL_ENV, "getrenv"),
        setfenv = rawget(REAL_ENV, "setfenv"),
        dump = dump,
        record = RECORD,
    }
end

local function put(name, value)
    local ok = pcall(function() rawset(G, name, value) end)
    if not ok then ok = pcall(function() G[name] = value end) end
    return ok
end

local CURRENT = nil

-- 安装到运行时。逐项 pcall：luau 的 _G 是只读表、getfenv 可能由环境元表提供，
-- 覆盖失败时降级为「该特征在此运行时不可用」，绝不中断渲染。
function DeltaEnv.apply(mode, snap)
    local env = DeltaEnv.build(mode, snap)
    local rep = {
        mode = env.mode, snap = env.snap,
        applied = {}, readonly = {},
    }
    local function install(name, value)
        if put(name, value) then
            rep.applied[#rep.applied + 1] = name
        else
            rep.readonly[#rep.readonly + 1] = name
        end
    end

    install("_G", env.sharedG)
    install("getgenv", env.getgenv)
    install("getfenv", env.getfenv)
    install("getrenv", env.getrenv)
    install("setfenv", env.setfenv)
    install("DBGDUMP", env.dump)

    -- A 层语义：checkcaller 恒 true（差分信任，避免误杀）
    install("checkcaller", function() return true end)
    install("iscclosure", DeltaEnv.isC)
    install("islclosure", function(f)
        return type(f) == "function" and not DeltaEnv.isC(f)
    end)
    -- 把 mock 里应当被视为 C 闭包的全局登记进 C_SET
    markC(rawget(G, "typeof"))
    markC(rawget(G, "print"))
    markC(rawget(G, "warn"))
    local instLib = rawget(G, "Instance")
    if type(instLib) == "table" then markC(instLib.new) end

    rep.gType = type(env.sharedG)
    rep.getfenvType = type(env.getfenv)
    rep.getgenvType = type(env.getgenv)
    rep.getrenvType = type(env.getrenv)
    rep.gameType = type(game)
    CURRENT = rep

    print(string.format(
        "[delta-sim] MODE=%s _G=%s getfenv=%s getgenv=%s getrenv=%s game=%s",
        rep.mode, rep.gType, rep.getfenvType, rep.getgenvType,
        rep.getrenvType, rep.gameType))
    return rep
end

function DeltaEnv.report()
    return CURRENT
end

-- 裸全局导出（lupa / luau 双路径共享默认全局环境）
rawset(G, "DeltaEnv", DeltaEnv)

-- CLI 通过 DELTA_MODE / DELTA_SNAP 两个全局选择模式；模块被加载即自动生效
DeltaEnv.apply(rawget(G, "DELTA_MODE") or "getfenv_real",
               rawget(G, "DELTA_SNAP") and true or false)

return DeltaEnv
