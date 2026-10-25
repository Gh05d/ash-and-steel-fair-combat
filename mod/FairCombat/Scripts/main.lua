-- Fair Combat for Of Ash and Steel - UE4SS Lua mod
--
-- Ends stagger-lock chains and gives enemies a Souls-like attack rhythm: after you stagger you can't be
-- staggered again for a moment, the enemy who staggered you gets one follow-up hit and then waits, and only
-- a limited number of melee enemies attack you at the same time. Archers are left alone.
local VERSION = "0.1.0"

local CFG = require("config")
local Policy = require("policy")

local function log(fmt, ...)
    print("[FairCombat] " .. string.format(fmt, ...) .. "\n")
end

local function dbg(fmt, ...)
    if CFG.debug then log(fmt, ...) end
end

local policy = Policy.new(CFG)

log("v%s loaded", VERSION)
