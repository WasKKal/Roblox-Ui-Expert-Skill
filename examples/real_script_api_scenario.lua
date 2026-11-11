-- real_script_api_scenario.lua — finite compatibility regression for real scripts.
--
-- The two real scripts used as compatibility samples (ttk silent-aim ESP and
-- Xi Pro / WindUI) are resident scripts: they contain `while task.wait(...) do`
-- / `while true do` main loops that never terminate in a virtual clock. Running
-- them verbatim would hang the headless driver, so this scenario instead asserts
-- every API those scripts depend on is present and usable. It is finite, fast,
-- and produces a clear "supported / total" compatibility rate.
--
-- Optionally map the remote UI library URL to examples/ui_lib_stub.lua to also
-- exercise the loadstring(... )() library-loading chain:
--   --lib "https://api.pastes.dev/wbm8z5CjsN=examples/ui_lib_stub.lua"

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local CG = game:GetService("CoreGui")
local SG = game:GetService("StarterGui")

local function fn(v) return type(v) == "function" end
local function tbl(v) return type(v) == "table" end

-- game-level Roblox API used by both scripts
check("game:IsLoaded", fn(game.IsLoaded) and game:IsLoaded() == true)
check("game.Loaded signal", tbl(game.Loaded) and fn(game.Loaded.Connect))
check("game:GetService", fn(game.GetService))
check("game:HttpGet", fn(game.HttpGet))

-- services referenced by the two scripts (no \"unmocked service\" warnings)
local svcNames = {
    "CoreGui", "LogService", "Players", "ProximityPromptService",
    "ReplicatedStorage", "RunService", "ScriptContext", "UserInputService",
    "VirtualInputManager", "VirtualUser", "Workspace", "StarterGui",
}
for _, n in ipairs(svcNames) do
    local ok, s = pcall(function() return game:GetService(n) end)
    check("GetService " .. n, ok and s ~= nil)
end

-- StarterGui:SetCore (ttk failure path)
check("StarterGui:SetCore", fn(SG.SetCore))
check("StarterGui:SetCore callable", pcall(function() SG:SetCore("SendNotification", { Title = "x" }) end))

-- LocalPlayer PlayerGui lookup (ttk failure path)
check("LocalPlayer", P.LocalPlayer ~= nil)
check("LocalPlayer:FindFirstChild", fn(P.LocalPlayer.FindFirstChild))
check("LocalPlayer:WaitForChild", fn(P.LocalPlayer.WaitForChild))
local okPG, pg = pcall(function() return P.LocalPlayer:WaitForChild("PlayerGui") end)
check("LocalPlayer PlayerGui", okPG and pg ~= nil)
check("CoreGui is real container", tbl(CG) and fn(CG.FindFirstChild))

-- workspace / camera / descendant events (Xi Pro failure path)
check("workspace alias", workspace ~= nil)
check("workspace.DescendantAdded", tbl(WS.DescendantAdded) and fn(WS.DescendantAdded.Connect))
check("CurrentCamera ViewportSize", WS.CurrentCamera.ViewportSize ~= nil)
check("CurrentCamera:WorldToViewportPoint", fn(WS.CurrentCamera.WorldToViewportPoint))

-- value types used by Xi Pro (Color3.fromHex gradients)
check("Color3.fromHex", fn(Color3.fromHex))
check("Color3.fromHex #00DBDE", (function()
    local ok, r, g, b = pcall(function() return Color3.toRGB(Color3.fromHex("#00DBDE")) end)
    return ok and r == 0 and g == 219 and b == 222
end)())
check("Color3.toHex", (function()
    local ok, v = pcall(function() return Color3.toHex(Color3.fromRGB(255, 96, 96)) end)
    return ok and v == "#FF6060"
end)())
check("Color3:ToHSV", (function()
    local h, s, v = Color3.fromRGB(255, 96, 96):ToHSV()
    return type(h) == "number" and type(s) == "number" and type(v) == "number"
end)())
check("UDim2.fromOffset", fn(UDim2.fromOffset))

-- Drawing (ttk FOV circle)
check("Drawing.new", tbl(Drawing) and fn(Drawing.new))
check("Drawing Circle object", (function()
    local ok, res = pcall(function()
        local c = Drawing.new("Circle")
        c.Thickness = 1.5
        c.NumSides = 60
        c.Filled = false
        c.Visible = true
        return c.Thickness == 1.5 and c.NumSides == 60
    end)
    return ok and res == true
end)())
check("Drawing.clear", tbl(Drawing) and fn(Drawing.clear))

-- instance methods used by both scripts
local probe = Instance.new("Folder")
for _, m in ipairs({ "WaitForChild", "FindFirstChild", "GetChildren", "GetDescendants",
                     "SetAttribute", "GetAttribute", "Destroy", "IsA", "Clone" }) do
    check("Instance:" .. m, fn(probe[m]))
end

-- executor globals used by the two scripts
for _, g in ipairs({ "getgenv", "getrenv", "getnamecallmethod", "hookmetamethod",
                     "newcclosure", "gethui", "getgc", "isfile", "readfile",
                     "writefile", "getcustomasset", "fireproximityprompt",
                     "get_hidden_gui", "getidentity", "setidentity",
                     "getthreadidentity", "setthreadidentity", "toclipboard",
                     "loadstring" }) do
    check("executor global " .. g, getfenv(0)[g] ~= nil)
end
check("getgenv() returns real env", tbl(getgenv()) and getgenv().Drawing ~= nil)
check("loadstring still native", fn(loadstring))

-- remote UI library loading chain (WindUI / Obsidian style)
local libSrc = game:HttpGet("https://api.pastes.dev/wbm8z5CjsN")
if type(libSrc) == "string" and #libSrc > 10 then
    local f = loadstring(libSrc)
    check("remote UI lib compiles", fn(f))
    if fn(f) then
        local ok, lib = pcall(f)
        check("remote UI lib loads", ok and lib ~= nil)
        if ok and lib then
            local chainOk = pcall(function()
                local win = lib:CreateWindow({ Title = "X" })
                local tab = win:AddTab("General")
                local toggle = tab:AddToggle({ Text = "Boost" })
                if toggle and toggle.SetValue then toggle:SetValue(true) end
                if lib.Options and lib.Options.Boost then lib.Options.Boost:SetValue(true) end
            end)
            check("remote UI lib CreateWindow chain", chainOk)
        end
    end
end

Snapshot("real script API compat")
