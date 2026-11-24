-- ============================================================================
-- fidelity_scenario.lua — mock 与 Roblox 行为一致性回归
-- 覆盖历史迭代中反复踩坑、现已按真机语义修复的保真点：
--   1. HttpService 方法自吞 self（colon / dot 两种调用）
--   2. Luau 数学/表/字符串内建（sign/lerp/map/log2/find/create/trim/starts/ends）
--   3. 值类型算术运算与 Lerp/Magnitude（Vector/UDim/UDim2/Color3）
--   4. task.cancel 真机语义（运行中报错 / 结束线程空操作 / 挂起线程取消）
--   5. DataModel 容器方法（game:WaitForChild / FindFirstChild / GetChildren）
--   6. typeof / Color3.fromHex / Enum.TextTruncate 等既有保真点
-- 两条执行路径（lupa / 真实 luau）应得到完全一致的结果。
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
local function ok(f) local r, v = pcall(f); return r, v end

local _, guard = ok(function() return loadstring(game:HttpGet("https://mock.local/fidelity_ui.lua")) end)
if type(guard) ~= "function" then guard = function() end end
pcall(guard)

-- 1. HttpService 自吞 self
local HS = game:GetService("HttpService")
local enc = HS:JSONEncode({ a = 1, b = "x" })
local encT = HS:JSONDecode(enc)
check("HttpService:JSONEncode colon 调用", encT.a == 1 and encT.b == "x", enc)
check("HttpService.JSONEncode dot 调用", HS:JSONDecode(HS.JSONEncode({ a = 1 })).a == 1)
check("HttpService:JSONDecode colon 调用", HS:JSONDecode('{"k":7}').k == 7)
check("HttpService.JSONDecode dot 调用", HS.JSONDecode('{"k":8}').k == 8)
check("JSONEncode 不泄漏服务表字段", not tostring(enc):find("GetAsync", 1, true))

-- 2. Luau 内建
check("math.sign 负数", math.sign(-3) == -1)
check("math.sign 零", math.sign(0) == 0)
check("math.lerp", math.lerp(0, 10, 0.25) == 2.5)
check("math.map", math.map(5, 0, 10, 0, 100) == 50)
check("math.log2", math.floor(math.log2(8) + 0.5) == 3)
check("table.find 命中", table.find({ 3, 5, 7 }, 5) == 2)
check("table.find 未命中", table.find({ 3, 5 }, 9) == nil)
check("table.create 填充", #table.create(3, 0) == 3 and table.create(3, 0)[2] == 0)
check("string.trim", string.trim("  hi  ") == "hi")
check("string.startswith", string.startswith("hello", "he") == true)
check("string.endswith", string.endswith("hello", "lo") == true)

-- 3. 值类型算术
check("Vector2 相加", (Vector2.new(1, 2) + Vector2.new(3, 4)).X == 4)
check("Vector2 标量乘", (Vector2.new(1, 2) * 2).Y == 4)
check("Vector3 相减", (Vector3.new(5, 5, 5) - Vector3.new(1, 2, 3)).Z == 2)
check("UDim 相加", math.floor((UDim.new(0.1, 2) + UDim.new(0.2, 3)).Offset + 0.5) == 5)
check("UDim2 偏移相加", (UDim2.fromOffset(1, 2) + UDim2.fromOffset(3, 4)).X.Offset == 4)
check("Vector2:Lerp", Vector2.new(0, 0):Lerp(Vector2.new(10, 10), 0.5).X == 5)
check("Vector3:Magnitude", Vector3.new(0, 3, 4):Magnitude() == 5)
check("Color3 相加", math.floor((Color3.new(0.1, 0.2, 0.3) + Color3.new(0.1, 0.2, 0.3)).R * 10 + 0.5) == 2)
check("Color3 标量乘", math.floor((Color3.new(0.5, 0.5, 0.5) * 2).R * 10 + 0.5) == 10)
check("Color3:Lerp", Color3.new(0, 0, 0):Lerp(Color3.new(1, 1, 1), 0.5).R == 0.5)

-- 4. task.cancel 语义
local dead = coroutine.create(function() end)
coroutine.resume(dead)
local okDead = ok(function() task.cancel(dead) end)
check("task.cancel 已结束线程为空操作", okDead)
local suspended = coroutine.create(function() coroutine.yield() end)
local okSuspend = ok(function() task.cancel(suspended) end)
check("task.cancel 可接受挂起线程", okSuspend)
local okRunning, errRunning = ok(function() task.cancel(coroutine.running()) end)
check("task.cancel 运行线程报错(真机语义)", not okRunning and tostring(errRunning):lower():find("cancel") ~= nil)

-- 5. DataModel 容器方法
check("game:WaitForChild(已有)", game:WaitForChild("Players") ~= nil)
check("game:WaitForChild(缺失)返回 nil", game:WaitForChild("NoSuchService", 0) == nil)
check("game:FindFirstChild(已有)", game:FindFirstChild("HttpService") ~= nil)
check("game:GetChildren 返回表", type(game:GetChildren()) == "table")

-- 6. 既有保真点回归
check("typeof(Color3)", typeof(Color3.new()) == "Color3")
check("typeof(Instance)", typeof(Instance.new("Frame")) == "Instance")
check("Color3.fromHex", Color3.toHex(Color3.fromHex("#FF0000")) == "#FF0000")
check("Enum.TextTruncate.AtEnd", Enum.TextTruncate.AtEnd ~= nil)

print(string.format("保真回归: 通过 %d / 失败 %d", passed, failed))
