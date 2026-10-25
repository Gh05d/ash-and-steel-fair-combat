-- Fair Combat rules: pure Lua, no Unreal calls. Time is passed in (seconds).
local Policy = {}
Policy.__index = Policy

function Policy.new(cfg)
    return setmetatable({ cfg = cfg }, Policy)
end

return Policy
