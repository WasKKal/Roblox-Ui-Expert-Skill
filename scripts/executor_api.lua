-- executor_api.lua — executor API compatibility layer.
-- Loaded right after mock_runtime.lua by both CLIs (SCRIPTS list).
-- Name list comes from references/executor-api-list.txt: 373 globals detected
-- in a real executor environment. Two layers:
--   * semantic implementations: filesystem / HTTP / clipboard / closures /
--     crypt / base64 / bit / debug / Drawing / time / identity / input ...
--     return sensible values so real scripts can keep running.
--   * presence stubs: the remaining probe/internal-only APIs are registered as
--     silent no-op functions so a missing global never aborts a script.
-- Stubs never emit warnings. Anything already defined by mock_runtime.lua with
-- a fuller implementation is kept (we only fill the gaps) unless explicitly
-- overridden below (e.g. getgenv / setclipboard).

local M = __MOCK
local G = getfenv(0)

local NOOP   = function() end
local EMPTY  = function() return {} end
local TRUE   = function() return true end
local FALSE  = function() return false end
local ZERO   = function() return 0 end
local STR    = function() return "" end

local functional = {}

local function override(name, value, isFunc)
    if value == nil then return end
    local ok = pcall(function() rawset(G, name, value) end)
    if not ok then pcall(function() G[name] = value end) end
    if isFunc then functional[name] = true end
end

-- Luau exposes some builtins (loadstring / getfenv ...) through the environment
-- metatable, not as raw keys. A raw-only check would overwrite them with a no-op
-- and break the harness. Never touch these, and prefer normal lookup over rawget.
local PROTECTED = {
    loadstring = true, load = true, getfenv = true, setfenv = true,
    print = true, type = true, tostring = true, tonumber = true,
    pcall = true, xpcall = true, error = true, assert = true,
    require = true, unpack = true, newproxy = true, select = true,
    rawget = true, rawset = true, rawlen = true, rawequal = true,
    setmetatable = true, getmetatable = true, next = true, pairs = true,
    ipairs = true, collectgarbage = true, coroutine = true,
    string = true, table = true, math = true, os = true,
    debug = true, bit = true, _G = true, _VERSION = true,
}

local function ensure(name, value, isFunc)
    if PROTECTED[name] then return end
    local readOk, cur = pcall(function() return G[name] end)
    if readOk and cur ~= nil then return end
    local ok = pcall(function() rawset(G, name, value or NOOP) end)
    if not ok then pcall(function() G[name] = value or NOOP end) end
    if isFunc then functional[name] = true end
end

local function ensureMany(list, value, isFunc)
    for i = 1, #list do ensure(list[i], value, isFunc) end
end

local function overrideMany(list, value, isFunc)
    for i = 1, #list do override(list[i], value, isFunc) end
end

local function copyTable(src)
    local t = {}
    if type(src) == "table" then
        for k, v in pairs(src) do pcall(function() t[k] = v end) end
    end
    return t
end

local function mark(name)
    functional[name] = true
end

-- ---------------------------------------------------------------------------
-- base64 (real implementation, shared by crypt / base64 / global aliases)
-- ---------------------------------------------------------------------------
local B64C = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64D = {}
for i = 1, 64 do B64D[string.sub(B64C, i, i)] = i - 1 end

local function b64encode(s)
    s = tostring(s or "")
    local out, i = {}, 1
    while i <= #s do
        local a, b, c = string.byte(s, i), string.byte(s, i + 1), string.byte(s, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local i1 = math.floor(n / 262144) % 64
        local i2 = math.floor(n / 4096) % 64
        local i3 = math.floor(n / 64) % 64
        local i4 = n % 64
        out[#out + 1] = string.sub(B64C, i1 + 1, i1 + 1) .. string.sub(B64C, i2 + 1, i2 + 1)
        out[#out + 1] = b and string.sub(B64C, i3 + 1, i3 + 1) or "="
        out[#out + 1] = c and string.sub(B64C, i4 + 1, i4 + 1) or "="
        i = i + 3
    end
    return table.concat(out)
end

local function b64decode(s)
    s = string.gsub(tostring(s or ""), "%s", "")
    local out, i = {}, 1
    while i <= #s do
        local c1 = string.sub(s, i, i)
        local c2 = string.sub(s, i + 1, i + 1)
        local c3 = string.sub(s, i + 2, i + 2)
        local c4 = string.sub(s, i + 3, i + 3)
        local n = (B64D[c1] or 0) * 262144 + (B64D[c2] or 0) * 4096
                  + (B64D[c3] or 0) * 64 + (B64D[c4] or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if c3 ~= "=" then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if c4 ~= "=" then out[#out + 1] = string.char(n % 256) end
        i = i + 4
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- bit32-style operations (pure arithmetic, works on both Lua 5.5 and Luau)
-- ---------------------------------------------------------------------------
local function u32(x) return math.floor(tonumber(x) or 0) % 4294967296 end
local function band(a, b)
    a, b = u32(a), u32(b)
    local r, p = 0, 1
    for _ = 1, 32 do
        if a % 2 >= 1 and b % 2 >= 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end
local function bor(a, b)
    a, b = u32(a), u32(b)
    local r, p = 0, 1
    for _ = 1, 32 do
        if a % 2 >= 1 or b % 2 >= 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end
local function bxor(a, b)
    a, b = u32(a), u32(b)
    local r, p = 0, 1
    for _ = 1, 32 do
        if (a % 2 >= 1) ~= (b % 2 >= 1) then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end
local function bnot(a) return 4294967295 - u32(a) end
local function lshift(a, n) return u32((u32(a)) * (2 ^ (u32(n) % 32))) end
local function rshift(a, n) return math.floor(u32(a) / (2 ^ (u32(n) % 32))) end
local function lrotate(a, n)
    n = u32(n) % 32
    return bor(lshift(a, n), rshift(a, 32 - n))
end
local function rrotate(a, n)
    n = u32(n) % 32
    return bor(rshift(a, n), lshift(a, 32 - n))
end
local function btest(a, b) return band(a, b) ~= 0 end
local function extract(a, field, width)
    return math.floor(u32(a) / (2 ^ u32(field))) % (2 ^ (u32(width) or 1))
end
local function replace(a, b, field, width)
    local w = u32(width) or 1
    local mask = lshift((2 ^ w) - 1, field)
    return bor(band(a, bnot(mask)), band(lshift(b, field), mask))
end
local function countlz(a)
    local n = 0
    for i = 31, 0, -1 do
        if rshift(a, i) % 2 == 1 then break end
        n = n + 1
    end
    return n
end
local function countrz(a)
    local n = 0
    for i = 0, 31 do
        if rshift(a, i) % 2 == 1 then break end
        n = n + 1
    end
    return n
end
local function byteswap(a)
    a = u32(a)
    return bor(lshift(band(a, 255), 24), lshift(band(rshift(a, 8), 255), 16),
              lshift(band(rshift(a, 16), 255), 8), band(rshift(a, 24), 255))
end

local bitT = {
    band = band, bor = bor, bxor = bxor, bnot = bnot,
    lshift = lshift, rshift = rshift, arshift = rshift,
    lrotate = lrotate, rrotate = rrotate, btest = btest,
    extract = extract, replace = replace, countlz = countlz,
    countrz = countrz, byteswap = byteswap,
}

-- ---------------------------------------------------------------------------
-- crypt / base64 namespaces
-- ---------------------------------------------------------------------------
local function mockHash(s)
    s = tostring(s or "")
    local h = 5381
    for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 4294967296 end
    return string.format("%08x", h)
end
local function mockBytes(n)
    n = math.max(0, math.floor(tonumber(n) or 16))
    local out = {}
    for i = 1, n do out[i] = string.char((i * 73 + 41) % 256) end
    return table.concat(out)
end
local function identity(s) return tostring(s or "") end

local base64T = { encode = b64encode, decode = b64decode }
local cryptT = {
    encrypt = identity, decrypt = identity,
    hash = mockHash, hmac = function(data, key) return mockHash(tostring(data or "") .. tostring(key or "")) end,
    random = mockBytes, generatekey = function() return mockBytes(32) end,
    generatebytes = mockBytes,
    lz4compress = identity, lz4decompress = identity,
    base64_encode = b64encode, base64_decode = b64decode,
    base64encode = b64encode, base64decode = b64decode,
    base64 = { encode = b64encode, decode = b64decode,
               base64_encode = b64encode, base64_decode = b64decode },
}
cryptT.base64_encode = b64encode
cryptT.base64_decode = b64decode
cryptT.base64encode = b64encode
cryptT.base64decode = b64decode

-- ---------------------------------------------------------------------------
-- debug namespace (keep native methods, add executor probes)
-- ---------------------------------------------------------------------------
local debugT = copyTable(rawget(G, "debug"))
local debugStubs = {
    getconstants = EMPTY, getconstant = function() return nil end,
    getprotos = EMPTY, getproto = function() return nil end,
    getupvalues = EMPTY, getupvalue = function() return nil end,
    setupvalue = NOOP, setconstant = NOOP,
    getstack = EMPTY, setstack = NOOP, getcallstack = EMPTY,
    validlevel = TRUE, isvalidlevel = TRUE,
    profilebegin = NOOP, profileend = NOOP,
    setmemorycategory = NOOP, getmemorycategory = STR, resetmemorycategory = NOOP,
    getregistry = EMPTY, dumpcodesize = ZERO, dumprefs = EMPTY,
    dumpheap = EMPTY, loadmodule = function() return nil end,
    getinfo = function() return {} end, info = function() return {} end,
    traceback = function() return "" end,
    getmetatable = function(o) return getmetatable(o) end,
    setmetatable = function(o, mt) return pcall(function() setmetatable(o, mt) end) end,
}
for k, v in pairs(debugStubs) do if debugT[k] == nil then debugT[k] = v end end

-- ---------------------------------------------------------------------------
-- Drawing (real script creates Circle/Square/Line/Text objects)
-- ---------------------------------------------------------------------------
local drawingObjects = {}
local function newDrawing(kind)
    local o = {
        __kind = kind or "Line", Visible = false, Transparency = 0,
        Thickness = 1, NumSides = 12, Filled = false, Radius = 0,
        ZIndex = 1, Center = false, Outline = false,
        Color = Color3.new(1, 1, 1), Position = Vector2.new(0, 0),
        From = Vector2.new(0, 0), To = Vector2.new(0, 0),
        Text = "", Size = 12, Font = 0,
    }
    function o:Remove() o.Visible = false end
    o.Destroy = o.Remove
    function o:Update() end
    drawingObjects[#drawingObjects + 1] = o
    return o
end
local DrawingT = {
    Fonts = { UI = 0, System = 1, Monospace = 2, Unknown = 3 },
    new = newDrawing,
    clear = function() for i = 1, #drawingObjects do drawingObjects[i].Visible = false end end,
}

-- ---------------------------------------------------------------------------
-- time / identity / misc namespaces
-- ---------------------------------------------------------------------------
local function duration(v)
    return { TotalSeconds = v, TotalMilliseconds = v * 1000, Seconds = v, Ticks = v * 10000000 }
end
local DurationT = {
    FromSeconds = duration, FromMilliseconds = function(v) return duration((v or 0) / 1000) end,
    FromMinutes = function(v) return duration((v or 0) * 60) end,
    FromHours = function(v) return duration((v or 0) * 3600) end,
    FromDays = function(v) return duration((v or 0) * 86400) end,
    FromMonths = function(v) return duration((v or 0) * 2592000) end,
    FromYears = function(v) return duration((v or 0) * 31536000) end,
    FromMicroseconds = function(v) return duration((v or 0) / 1000000) end,
    FromNanoseconds = function(v) return duration((v or 0) / 1000000000) end,
    TimeSinceEpoch = duration,
}
local StopwatchT = {
    new = function()
        local sw = { _t = 0, _running = false }
        function sw:Start() self._t = os.clock(); self._running = true end
        function sw:Stop() if self._running then self._t = os.clock() - self._t; self._running = false end end
        function sw:Reset() self._t = 0; self._running = false end
        function sw:Elapsed() return self._t end
        function sw:IsRunning() return self._running end
        return sw
    end,
}
local DeltaT = {
    is_android = false, is_ios = false, is_vng = false, is_mac = false,
    roblox_version = "0.0.0", version = "1.0.0", version_num = 100,
    version_hash = "mock", architecture_str = "x64", architecture = 0,
    get_platform = function() return "Windows" end,
}
local RegexT = {
    Escape = function(s) return string.gsub(tostring(s or ""), "([%%%(%)%.%[%]%*%+%-%?%^%$])", "%%%1") end,
    new = function(p) return { Pattern = p, Match = function() return nil end, Replace = function(s) return s end } end,
}
local WebSocketT = {
    connect = function(url)
        return {
            Url = url,
            Send = NOOP, Close = NOOP,
            OnMessage = { Connect = NOOP }, OnClose = { Connect = NOOP },
        }
    end,
}

local function stubSignal()
    return { Connect = NOOP, connect = NOOP, Fire = NOOP, fire = NOOP, Wait = NOOP }
end
local DeltaSignalT = { new = stubSignal }
local LuaStateProxyT = { new = function() return {} end }
local othT = {
    hook = NOOP, unhook = NOOP, get_original_thread = function() return nil end,
    is_hook_thread = FALSE, get_root_callback = function() return nil end,
}
local RakNetT = { desync = NOOP, is_enabled = FALSE }
local serverT = { has_authority = FALSE }
local cacheT = { replace = NOOP, iscached = FALSE, invalidate = NOOP }
local pibbleT = {
    gmail = STR, is_detected = FALSE, is_pibble = FALSE,
    washington = STR, getpibbles = EMPTY,
}

-- ---------------------------------------------------------------------------
-- install namespaces (overriding readonly native tables with writable copies)
-- ---------------------------------------------------------------------------
override("bit", bitT, true)
override("base64", base64T, true)
override("crypt", cryptT, true)
override("debug", debugT, true)
override("Drawing", DrawingT, true)
override("Duration", DurationT, true)
override("Stopwatch", StopwatchT, true)
override("Delta", DeltaT, true)
override("Regex", RegexT, true)
override("WebSocket", WebSocketT, true)
override("DeltaSignal", DeltaSignalT, true)
override("LuaStateProxy", LuaStateProxyT, true)
override("oth", othT, true)
override("RakNet", RakNetT, true)
override("server", serverT, true)
override("cache", cacheT, true)
override("pibble", pibbleT, true)

-- http / syn: keep the existing libRegistry-backed request, add aliases
local httpT = copyTable(rawget(G, "http"))
httpT.request = httpT.request or (rawget(G, "request") or EMPTY)
httpT.requestAsync = httpT.request
override("http", httpT, true)
local synT = copyTable(rawget(G, "syn"))
synT.request = synT.request or (rawget(G, "request") or EMPTY)
synT.request_async = synT.request
override("syn", synT, true)

local nsFunctional = {
    "bit.band", "bit.extract", "bit.byteswap", "bit.bor", "bit.bnot", "bit.countrz",
    "bit.bxor", "bit.arshift", "bit.rshift", "bit.rrotate", "bit.replace", "bit.lshift",
    "bit.lrotate", "bit.btest", "bit.countlz",
    "crypt.encrypt", "crypt.lz4compress", "crypt.hash", "crypt.hmac", "crypt.random",
    "crypt.lz4decompress", "crypt.base64decode", "crypt.generatekey", "crypt.generatebytes",
    "crypt.base64.encode", "crypt.base64.decode", "crypt.base64_decode", "crypt.base64_encode",
    "crypt.decrypt", "base64.encode", "base64.decode",
    "debug.dumpheap", "debug.getconstants", "debug.getproto", "debug.setmemorycategory",
    "debug.profilebegin", "debug.loadmodule", "debug.traceback", "debug.getstack",
    "debug.getcallstack", "debug.getregistry", "debug.setmetatable", "debug.getupvalues",
    "debug.getupvalue", "debug.getmemorycategory", "debug.resetmemorycategory",
    "debug.setupvalue", "debug.validlevel", "debug.isvalidlevel", "debug.dumpcodesize",
    "debug.setstack", "debug.getconstant", "debug.profileend", "debug.info",
    "debug.getinfo", "debug.getprotos", "debug.setconstant", "debug.getmetatable",
    "debug.dumprefs",
    "Drawing.clear", "Drawing.new",
    "Duration.FromMonths", "Duration.FromMilliseconds", "Duration.FromYears",
    "Duration.FromMicroseconds", "Duration.FromHours", "Duration.FromNanoseconds",
    "Duration.FromSeconds", "Duration.FromMinutes", "Duration.FromDays",
    "Duration.TimeSinceEpoch", "Stopwatch.new",
    "Delta.is_android", "Delta.is_ios", "Delta.is_vng", "Delta.roblox_version",
    "Delta.is_mac", "Delta.version", "Delta.version_num", "Delta.version_hash",
    "Delta.architecture_str", "Delta.architecture", "Delta.get_platform",
    "Regex.Escape", "Regex.new", "WebSocket.connect", "http.request",
    "base64_encode", "base64_decode", "base64encode", "base64decode",
    "base64.encode", "base64.decode", "base64_encode", "base64_decode",
}
for i = 1, #nsFunctional do mark(nsFunctional[i]) end

-- ---------------------------------------------------------------------------
-- top-level semantic globals
-- ---------------------------------------------------------------------------
local function getenvReal() return getfenv(0) end
local renv = copyTable(rawget(G, "_G"))
override("getgenv", getenvReal, true)
override("getrenv", function() return renv end, true)
override("getreg", function() return {} end, true)
override("identifyexecutor", function() return "MockRuntime", "1.0" end, true)
override("getexecutorname", function() return "MockRuntime" end, true)
override("isrbxactive", TRUE, true)
override("isgameactive", TRUE, true)
override("iswindowactive", TRUE, true)
override("gethwid", function() return "MOCK-HWID-0000" end, true)

override("setclipboard", NOOP, true)
overrideMany({ "toclipboard", "set_clipboard", "set_rbx_clipboard",
               "setrbxclipboard", "set_clipboard" }, NOOP, true)

overrideMany({ "base64_encode", "base64_decode", "base64encode", "base64decode" },
             function(s) return b64encode(s) end, true)
override("base64_decode", b64decode, true)
override("base64encode", b64encode, true)
override("base64decode", b64decode, true)
override("base64_encode", b64encode, true)

override("lz4compress", identity, true)
override("lz4decompress", identity, true)
override("lz4_compress", identity, true)
override("lz4_decompress", identity, true)
override("zstdcompress", identity, true)
override("zstddecompress", identity, true)
override("zstd_compress", identity, true)
override("zstd_decompress", identity, true)

override("getfpscap", function() return 60 end, true)
override("get_fps_cap", function() return 60 end, true)
override("setfpscap", NOOP, true)
override("set_fps_cap", NOOP, true)
override("setthreadidentity", NOOP, true)
override("set_thread_identity", NOOP, true)
override("set_thread_context", NOOP, true)
override("setidentity", NOOP, true)
override("getthreadidentity", function() return 2 end, true)
override("get_thread_identity", function() return 2 end, true)
override("get_thread_context", function() return 2 end, true)
override("getidentity", function() return 2 end, true)
override("getthreadcontext", function() return 2 end, true)
override("setthreadcontext", NOOP, true)
override("setsimulationradius", NOOP, true)
override("getsimulationradius", ZERO, true)
override("setfflag", NOOP, true)
override("getfflag", STR, true)
override("setrenderproperty", NOOP, true)
override("getrenderproperty", function() return nil end, true)
override("getrendersteppedlist", EMPTY, true)
override("get_renderstepped_list", EMPTY, true)
override("getrenderstepcallbacks", EMPTY, true)

override("getnamecallmethod", STR, true)
override("setnamecallmethod", NOOP, true)
override("checkcaller", TRUE, true)
override("checkparallel", TRUE, true)
override("isparallel", FALSE, true)
override("iscclosure", FALSE, true)
override("is_c_closure", FALSE, true)
override("islclosure", TRUE, true)
override("is_l_closure", TRUE, true)
override("isourclosure", FALSE, true)
override("is_our_closure", FALSE, true)
override("isexecutorclosure", FALSE, true)
override("is_executor_closure", FALSE, true)
override("is_delta_closure", FALSE, true)
override("isdeltafunction", FALSE, true)
override("isnewcclosure", FALSE, true)
override("iscustomcclosure", FALSE, true)
override("checkclosure", TRUE, true)
override("isexecutorthread", TRUE, true)
override("isourthread", TRUE, true)
override("isgamescriptconnection", FALSE, true)
override("isluaconnection", TRUE, true)
override("iswaitingconnection", FALSE, true)
override("isnetworkowner", FALSE, true)
override("isrenderobj", FALSE, true)
override("iscclosure", FALSE, true)
override("ishooked", FALSE, true)
override("is_function_hooked", FALSE, true)
override("isfunctionhooked", FALSE, true)
override("isreadonly", FALSE, true)
override("iswritable", TRUE, true)
override("isscriptable", TRUE, true)
override("isvalidlevel", TRUE, true)
override("validlevel", TRUE, true)
override("is_c_closure", FALSE, true)
override("isdeltafunction", FALSE, true)

override("newcclosure", function(f) return f end, true)
override("newlclosure", function(f) return f end, true)
override("clonefunction", function(f) return f end, true)
override("clonefunc", function(f) return f end, true)
override("cloneref", function(o) return o end, true)
override("clonereference", function(o) return o end, true)
override("hookmetamethod", function(_, _, _) return function() end end, true)
override("hookfunction", function(f, _) return f end, true)
override("detour_function", function(f, _) return f end, true)
override("detourfunction", function(f, _) return f end, true)
override("restorefunction", NOOP, true)
override("restorefunc", NOOP, true)
override("restoreclosure", NOOP, true)
override("restorefunc", NOOP, true)
override("replacefunc", NOOP, true)
override("replacefunction", NOOP, true)
override("replaceclosure", NOOP, true)
override("hookfunc", function(f, _) return f end, true)
override("hookproto", NOOP, true)
override("restoreproto", NOOP, true)
override("getrawmetatable", function(o) return getmetatable(o) or {} end, true)
override("setrawmetatable", function(o, mt) pcall(function() setmetatable(o, mt) end) end, true)
override("set_raw_metatable", function(o, mt) pcall(function() setmetatable(o, mt) end) end, true)
override("make_readonly", NOOP, true)
override("makereadonly", NOOP, true)
override("setreadonly", NOOP, true)
override("makewritable", NOOP, true)
override("make_writable", NOOP, true)
override("make_writeable", NOOP, true)
override("setscriptable", NOOP, true)
override("sethiddenproperty", NOOP, true)
override("sethiddenprop", NOOP, true)
override("set_hidden_property", NOOP, true)
override("gethiddenproperty", function() return nil, false end, true)
override("gethiddenprops", EMPTY, true)
override("gethiddenproperties", EMPTY, true)
override("get_hidden_props", EMPTY, true)
override("get_hidden_properties", EMPTY, true)
override("get_hidden_gui", function() return rawget(G, "gethui") and G.gethui() or {} end, true)
override("getproperties", EMPTY, true)
override("getprops", EMPTY, true)
override("getpcd", function() return nil end, true)
override("getpcdprop", function() return nil end, true)
override("compareinstances", FALSE, true)
override("getinstancecache", EMPTY, true)
override("getinstances", EMPTY, true)
override("getobjects", EMPTY, true)
override("getnilinstances", EMPTY, true)
override("get_nil_instances", EMPTY, true)
override("getscripts", EMPTY, true)
override("getscriptsthatrun", EMPTY, true)
override("getrunningscripts", EMPTY, true)
override("getloadedmodules", EMPTY, true)
override("getallthreads", EMPTY, true)
override("getallactors", EMPTY, true)
override("getactors", EMPTY, true)
override("get_actors", EMPTY, true)
override("get_deleted_actors", EMPTY, true)
override("getdestroyedactors", EMPTY, true)
override("get_destroyed_actors", EMPTY, true)
override("getactorstates", EMPTY, true)
override("getcurrentactor", function() return nil end, true)
override("get_current_actor", function() return nil end, true)
override("getgc", EMPTY, true)
override("filtergc", function() return nil end, true)
override("getsenv", EMPTY, true)
override("getmenv", EMPTY, true)
override("getcallingscript", function() return nil end, true)
override("getscriptclosure", function() return nil end, true)
override("getscriptfromthread", function() return nil end, true)
override("getscriptthread", function() return nil end, true)
override("getscriptbytecode", STR, true)
override("getfunctionbytecode", STR, true)
override("getscripthash", STR, true)
override("getfunctionhash", STR, true)
override("dumpstring", STR, true)
override("dumpbytecode", STR, true)
override("decompile", STR, true)
override("readbinarystring", STR, true)
override("readbinarystringpropertyvalue", STR, true)
override("getcallstack", EMPTY, true)
override("getstack", EMPTY, true)
override("setstack", NOOP, true)
override("setstackhidden", NOOP, true)
override("getupvalue", function() return nil end, true)
override("getupvalues", EMPTY, true)
override("setupvalue", NOOP, true)
override("getconstant", function() return nil end, true)
override("getconstants", EMPTY, true)
override("setconstant", NOOP, true)
override("getproto", function() return nil end, true)
override("getprotos", EMPTY, true)
override("getcallbackvalue", function() return nil end, true)
override("getcbvalue", function() return nil end, true)
override("getcallbackmember", function() return nil end, true)
override("getconnectionfunction", function() return nil end, true)
override("getconnectionthread", function() return nil end, true)
override("getconnections", EMPTY, true)
override("get_signal_cons", EMPTY, true)
override("setconnectionenabled", NOOP, true)
override("isconnectionenabled", TRUE, true)
override("firesignal", NOOP, true)
override("replicatesignal", NOOP, true)
override("getsignalarguments", EMPTY, true)
override("getsignalargumentsinfo", function() return nil end, true)
override("getsignalwhitelist", EMPTY, true)
override("firetouchinterest", NOOP, true)
override("fireclickdetector", NOOP, true)
override("fireproximityprompt", NOOP, true)
override("setproximitypromptduration", NOOP, true)
override("getproximitypromptduration", ZERO, true)
override("runonactor", NOOP, true)
override("run_on_actor", NOOP, true)
override("create_comm_channel", function() return {} end, true)
override("get_comm_channel", function() return nil end, true)
override("getgamestate", STR, true)
override("getthreadcontext", function() return 2 end, true)

override("keypress", NOOP, true)
override("keyrelease", NOOP, true)
override("keytap", NOOP, true)
override("keyclick", NOOP, true)
override("mouse1press", NOOP, true)
override("mouse1click", NOOP, true)
override("mouse1release", NOOP, true)
override("mouse2press", NOOP, true)
override("mouse2click", NOOP, true)
override("mouse2release", NOOP, true)
override("mousemoveabs", NOOP, true)
override("mousemoverel", NOOP, true)
override("mousescroll", NOOP, true)
override("getmousepos", function() return Vector2.new(0, 0) end, true)

override("queue_on_teleport", NOOP, true)
override("queueonteleport", NOOP, true)
override("clear_teleport_queue", NOOP, true)
override("clearteleportqueue", NOOP, true)
override("clearqueue_on_teleport", NOOP, true)
override("clearqueueonteleport", NOOP, true)

override("rconsolecreate", NOOP, true)
override("rconsoledestroy", NOOP, true)
override("rconsolename", NOOP, true)
override("rconsolesettitle", NOOP, true)
override("rconsoleprint", NOOP, true)
override("rconsoleinfo", NOOP, true)
override("rconsolewarn", NOOP, true)
override("rconsoleerr", NOOP, true)
override("rconsoleclear", NOOP, true)
override("rconsoleshow", NOOP, true)
override("rconsolehide", NOOP, true)
override("rconsoleinput", STR, true)
override("consolecreate", NOOP, true)
override("consoleprint", NOOP, true)
override("consoleclear", NOOP, true)
override("consolesettitle", NOOP, true)
override("consoledestroy", NOOP, true)
override("consoleinput", STR, true)
override("messagebox", NOOP, true)

override("httpget", function(url) return game:HttpGet(url) end, true)
override("httppost", function(url, body)
    local r = rawget(G, "request")
    if type(r) == "function" then return r({ Url = url, Method = "POST", Body = body }) end
    return { StatusCode = 404, Body = "", Success = false }
end, true)

override("dofile", function(path)
    local rf = rawget(G, "readfile")
    local src = type(rf) == "function" and rf(path) or nil
    if not src then return nil end
    return assert(load(src, "@" .. tostring(path)))()
end, true)
override("loadfile", function(path)
    local rf = rawget(G, "readfile")
    local src = type(rf) == "function" and rf(path) or nil
    if not src then return nil, "file not found" end
    return load(src, "@" .. tostring(path))
end, true)

-- ---------------------------------------------------------------------------
-- presence stubs: fill any remaining top-level name from the 373-name list.
-- Existing definitions (mock_runtime FS/HTTP, semantic overrides above) win.
-- ---------------------------------------------------------------------------
local TOPLEVEL = {
  "readbspval",
  "rconsolehide",
  "getbspval",
  "getsenv",
  "clear_teleport_queue",
  "cansignalreplicate",
  "getconnectionthread",
  "consolecreate",
  "queue_on_teleport",
  "getexecutorname",
  "get_nil_instances",
  "getallactors",
  "keytap",
  "getcurrentactor",
  "gethiddenprops",
  "getcallingscript",
  "getallthreads",
  "mouse1press",
  "toclipboard",
  "newcclosure",
  "request",
  "is_c_closure",
  "get_signal_cons",
  "setscriptable",
  "http_request",
  "lz4_decompress",
  "mousescroll",
  "isourclosure",
  "getrendersteppedlist",
  "setthreadidentity",
  "getproto",
  "isrbxactive",
  "getdeletedactors",
  "make_readonly",
  "getstack",
  "getrenderstepcallbacks",
  "mousemoveabs",
  "base64decode",
  "mouse1click",
  "ishooked",
  "get_renderstepped_list",
  "gethiddenproperty",
  "get_comm_channel",
  "setconnectionenabled",
  "makereadonly",
  "getnilinstances",
  "isvalidlevel",
  "iscclosure",
  "restorefunction",
  "get_hidden_gui",
  "getactorstates",
  "setstack",
  "isreadonly",
  "base64encode",
  "sethiddenproperty",
  "restoreproto",
  "base64_encode",
  "getconstant",
  "filtergc",
  "get_original_thread",
  "iswritable",
  "getscriptclosure",
  "is_delta_closure",
  "getfenv",
  "getscriptfromthread",
  "isdeltafunction",
  "get_deleted_actors",
  "setrenderproperty",
  "setconstant",
  "getinstances",
  "getconstants",
  "getloadedmodules",
  "get_hidden_properties",
  "is_our_closure",
  "getsignalargumentsinfo",
  "getrenderproperty",
  "getobjects",
  "consoleprint",
  "getscriptthread",
  "set_rbx_clipboard",
  "validlevel",
  "newlclosure",
  "zstdcompress",
  "delfolder",
  "getgenv",
  "keyrelease",
  "makewritable",
  "getscripthash",
  "getcallstack",
  "set_thread_context",
  "base64_decode",
  "getgamestate",
  "fireproximityprompt",
  "getpcdprop",
  "islclosure",
  "get_thread_context",
  "readbinarystringpropertyvalue",
  "get_current_actor",
  "lz4compress",
  "getscriptbytecode",
  "detour_function",
  "setfpscap",
  "setstackhidden",
  "get_destroyed_actors",
  "is_executor_closure",
  "get_fps_cap",
  "fireclickdetector",
  "getmenv",
  "rconsoleshow",
  "iswindowactive",
  "set_fps_cap",
  "getcallbackvalue",
  "runonactor",
  "firesignal",
  "makefolder",
  "set_hidden_property",
  "getinstancecache",
  "detourfunction",
  "isscriptable",
  "isluaconnection",
  "rconsolesettitle",
  "hookmetamethod",
  "isnewcclosure",
  "get_actors",
  "getrawmetatable",
  "getmousepos",
  "isgameactive",
  "set_raw_metatable",
  "setthreadcontext",
  "gethiddenproperties",
  "isparallel",
  "getthreadcontext",
  "isfunctionhooked",
  "getsignalarguments",
  "replacefunction",
  "cloneref",
  "setproximitypromptduration",
  "loadstring",
  "getproximitypromptduration",
  "getprotos",
  "hookfunction",
  "getluastate",
  "mouse2release",
  "rconsoleinfo",
  "get_thread_identity",
  "rconsolename",
  "getupvalue",
  "consolesettitle",
  "setidentity",
  "httpget",
  "set_clipboard",
  "isgamescriptconnection",
  "setupvalue",
  "isfolder",
  "create_comm_channel",
  "iscustomcclosure",
  "setrbxclipboard",
  "getscripts",
  "dumpstring",
  "keypress",
  "getproperties",
  "getscriptsthatrun",
  "getupvalues",
  "rconsoleclear",
  "replacefunc",
  "set_thread_identity",
  "messagebox",
  "getinfo",
  "getconnectionfunction",
  "is_function_hooked",
  "loadfile",
  "clonefunc",
  "getactors",
  "clearteleportqueue",
  "checkcaller",
  "clearqueue_on_teleport",
  "setreadonly",
  "setsimulationradius",
  "zstd_compress",
  "httppost",
  "setfflag",
  "restorefunc",
  "dumpbytecode",
  "readbinarystring",
  "getsignalwhitelist",
  "isnetworkowner",
  "compareinstances",
  "getcbvalue",
  "mouse1release",
  "replicatesignal",
  "gethui",
  "setnamecallmethod",
  "is_l_closure",
  "iswaitingconnection",
  "isconnectionenabled",
  "getconnections",
  "mouse2click",
  "getthreadidentity",
  "rconsoleerr",
  "sethiddenprop",
  "isfile",
  "getcustomasset",
  "replaceclosure",
  "zstddecompress",
  "getdestroyedactors",
  "getfflag",
  "isourthread",
  "lz4decompress",
  "consoledestroy",
  "run_on_actor",
  "keyclick",
  "getrenv",
  "consoleinput",
  "checkparallel",
  "getfunctionbytecode",
  "decompile",
  "isrenderobj",
  "cleardrawcache",
  "make_writeable",
  "isprotohooked",
  "hookfunc",
  "getrunningscripts",
  "getpcd",
  "setrawmetatable",
  "mousemoverel",
  "glooperror",
  "rconsoledestroy",
  "getscriptfunction",
  "getnamecallmethod",
  "rconsolewarn",
  "isexecutorthread",
  "mouse2press",
  "restoreclosure",
  "identifyexecutor",
  "checkclosure",
  "getfunctionhash",
  "setclipboard",
  "isexecutorclosure",
  "readfile",
  "appendfile",
  "get_callback_value",
  "consoleclear",
  "deletefolder",
  "writefile",
  "lz4_compress",
  "delfile",
  "getsimulationradius",
  "getcallbackmember",
  "clonereference",
  "getfpscap",
  "hookproto",
  "clonefunction",
  "getidentity",
  "rconsolecreate",
  "rconsoleprint",
  "get_properties",
  "firetouchinterest",
  "rconsoleinput",
  "getreg",
  "getprops",
  "listfiles",
  "clearqueueonteleport",
  "dofile",
  "zstd_decompress",
  "gethwid",
  "queueonteleport",
  "getgc"
}
ensureMany(TOPLEVEL, NOOP, false)

-- names already implemented by mock_runtime.lua count as functional
local mockFunctional = {
    "isfile", "readfile", "writefile", "appendfile", "isfolder", "makefolder",
    "delfile", "delfolder", "listfiles", "getcustomasset", "getsynasset",
    "gethui", "request", "http_request", "setclipboard", "loadstring",
}
for i = 1, #mockFunctional do mark(mockFunctional[i]) end

M.executorApiFunctional = functional
M.executorApiTotal = #TOPLEVEL + 0
