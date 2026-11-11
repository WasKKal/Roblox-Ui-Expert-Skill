-- ui_lib_stub.lua — minimal stand-in for a remote UI library.
-- Used by real_scripts_scenario.lua to verify the headless runtime can carry a
-- real script all the way to window/tab/control creation without the actual
-- (network-only) UI library being available.
-- Any method call, property read, or chained call returns a fresh callable proxy,
-- so CreateWindow / AddTab / AddToggle / Options.* / SetValue all succeed.

local function proxy()
    local t = {}
    return setmetatable(t, {
        __index = function(_, k)
            return proxy()
        end,
        __call = function(_, ...)
            return proxy()
        end,
        __tostring = function() return "UiLibStub" end,
        __len = function() return 0 end,
    })
end

return proxy()
