-- Fair Combat for Of Ash and Steel - UE4SS Lua mod
--
-- Ends stagger-lock chains and gives enemies a Souls-like attack rhythm: after you stagger you can't be
-- staggered again for a moment, the enemy who staggered you gets one follow-up hit and then waits, and only
-- a limited number of melee enemies attack you at the same time. Archers are left alone.
--
-- UE4SS calls hooks on blueprint functions after the function ran. So a hit that already landed can't be
-- undone; the mod can only cancel its hit reaction and keep the next hits from landing:
--   * GitHit / Knock / Reaction (player, once per hit) tell whether a hit got through and what it did,
--     GotHit (player, once per hit) then counts it and cancels the stagger inside a protection window.
--   * EnableTrace (enemy, once per swing): if this enemy may not hit right now, the player ignores hits
--     (the game's own invincibility flag) until the swing ends.
--   * Every tickMs: enemies fighting the player get attack rights; the others are held back through the
--     behavior tree key "DefenceMode?" (the attack branch only runs while it is not set).
local VERSION = "0.1.0"

local UEHelpers = require("UEHelpers")
local CFG = require("config")
local Policy = require("policy")

local PLAYER = "/Game/Components/Combat/CombatModule_Player.CombatModule_Player_C"
local ENEMY = "/Game/Components/Combat/CombatModule_AI_Humanoid.CombatModule_AI_Humanoid_C"
local P = {
    gotHit = PLAYER .. ":GotHit",
    reaction = PLAYER .. ":Reaction",
    gitHit = PLAYER .. ":GitHit",
    knock = PLAYER .. ":Knock",
    enemyTrace = ENEMY .. ":EnableTrace",
}
local IN_COMBAT = 6                                 -- blackboard Status "inCombat"
local ATTACKING = { [0] = true, [11] = true, [12] = true } -- Character_CombatState Attacking, HeavyAttack, SpecialAttack
local SWING_MAX = 1.5                               -- safety: invincibility for one swing never lasts longer (s)
local SCAN_MS = 1500                                -- how often the list of AI controllers is rebuilt
local SAME_HIT = 0.02                               -- Reaction and GotHit of one hit run in the same frame (s)

-- While the mod holds the player's invincibility it leaves this file next to the script, so a script reload
-- (Ctrl+R) in the middle of a blocked swing can still give the flag back.
local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
local FLAG = DIR .. "blocking.flag"

local policy = Policy.new(CFG)
local owned = {}        -- controller full name -> controller we set "DefenceMode?" on
local blocking = nil    -- { id = attacker, since = t, module = player combat module } while we hold invincibility
local seen = { t = -1, kind = "none" } -- what the last Reaction did (set by the Reaction/GitHit/Knock hooks)
local controllers, nextScan = {}, 0
local names, classes = {}, {}

local function log(fmt, ...)
    print("[FairCombat] " .. string.format(fmt, ...) .. "\n")
end

local function dbg(fmt, ...)
    if CFG.debug then log(fmt, ...) end
end

local function key(s)
    names[s] = names[s] or FName(s)
    return names[s]
end

local function valid(o)
    return o ~= nil and o:IsValid()
end

local function class(path)
    if not valid(classes[path]) then classes[path] = StaticFindObject(path) end
    return valid(classes[path]) and classes[path] or nil
end

local function now()
    local ok, t = pcall(function() return UEHelpers.GetGameplayStatics():GetTimeSeconds(UEHelpers.GetWorld()) end)
    if ok and type(t) == "number" then return t end
    return nil
end

local function playerPawn()
    local pc = UEHelpers.GetPlayerController()
    if not valid(pc) then return nil end
    local pawn = pc.Pawn
    return valid(pawn) and pawn or nil
end

local function component(actor, path)
    local cls = class(path)
    if not cls then return nil end
    local m = actor:GetComponentByClass(cls)
    return valid(m) and m or nil
end

-- The enemy is a ranged fighter while it keeps its distance: the behavior tree itself switches to melee
-- within 750 cm (gs_checkrangeweapon).
local function isRanged(dist)
    return dist > CFG.rangedDistance
end

local function block(id, t)
    local pawn = playerPawn()
    local m = pawn and component(pawn, PLAYER)
    if not m or m["invincibleFrame?"] then return end -- the game set it (parry, finisher, dialog): leave it alone
    m["invincibleFrame?"] = true
    blocking = { id = id, since = t, module = m }
    pcall(function()
        local f = io.open(FLAG, "w")
        if f then f:write(id) f:close() end
    end)
    dbg("block hits from %s", id)
end

local function unblock()
    if not blocking then return end
    if valid(blocking.module) then blocking.module["invincibleFrame?"] = false end
    dbg("unblock (%s)", blocking.id)
    blocking = nil
    pcall(os.remove, FLAG)
end

-- After a script reload: give back an invincibility the previous script instance left behind.
local function recoverFlag()
    local f = io.open(FLAG, "r")
    if not f then return end
    f:close()
    local pawn = playerPawn()
    local m = pawn and component(pawn, PLAYER)
    if not m then return end -- not in the world yet; ClientRestart tries again
    m["invincibleFrame?"] = false
    os.remove(FLAG)
    log("cleared invincibility left over from a script reload")
end

local function onReaction()
    seen.t = now() or -1
    seen.reacted = true
end

local function onGitHit() seen.kind = "stagger" end
local function onKnock() seen.kind = "knock" end

-- After GotHit: only hits that reached Reaction count (not blocked, dodged or ignored ones). Inside a
-- protection window, or from an enemy that has to wait, the stagger/knockdown the hit started is cancelled.
local function onGotHit(ctx, _impact, _damage, _stamina, _stagger, _direction, attacker)
    local ok, err = pcall(function()
        local t = now()
        local landed = t and seen.reacted and math.abs(seen.t - t) < SAME_HIT
        local reaction = landed and seen.kind or "none"
        seen.reacted, seen.kind = false, "none"
        if not landed then return end
        -- GotHit gets the attacking character; rules and blackboards are keyed by its AI controller.
        local enemy = attacker:get()
        local pawn = playerPawn()
        if not valid(enemy) or not pawn then return end
        local ctrl = enemy.Controller
        if not valid(ctrl) then return end
        local id = ctrl:GetFullName()
        -- Hits that don't come from an NPC (traps, falling, your own thrown junk) never lock anyone.
        local npc = ctrl:GetClass():GetFName():ToString() == "GS_AI_NPCController_C"
        local ranged = not npc or isRanged(enemy:GetDistanceTo(pawn))

        local protected = policy:protection(t)
        local mayHit = policy:mayHit(t, id, ranged)
        if CFG.antiStunlock and reaction ~= "none" and (protected or not mayHit) then
            local anim = pawn.Mesh:GetAnimInstance()
            local montage = valid(anim) and anim:GetCurrentActiveMontage() or nil
            if valid(montage) then anim:Montage_Stop(0.15, montage) end
            dbg("hit by %s (%s, %s): cancelled %s", id, protected or "locked", reaction,
                valid(montage) and montage:GetFName():ToString() or "?")
            reaction = "none"
        end
        policy:hit(t, id, CFG.antiStunlock and reaction or "none", ranged)
        dbg("hit by %s reaction=%s ranged=%s window=%s", id, reaction, tostring(ranged), tostring(policy:protection(t)))
    end)
    if not ok then log("GotHit hook error: %s", tostring(err)) end
end

-- After an enemy's EnableTrace (start/end of one swing): block the player's hits while an enemy swings
-- that may not hit right now (used its hit in the window, or waits for the player to recover).
local function onEnemyTrace(ctx, enable)
    local ok, err = pcall(function()
        if not CFG.antiStunlock then return end
        local on = enable:get()
        local enemy = ctx:get():GetOwner()
        if not valid(enemy) then return end
        local ctrl = enemy.Controller
        if not valid(ctrl) then return end
        local id = ctrl:GetFullName()
        if not on then
            if blocking and blocking.id == id then unblock() end
            return
        end
        local pawn = playerPawn()
        local t = now()
        if not pawn or not t or blocking then return end
        local bb = ctrl.Blackboard
        local target = valid(bb) and bb:GetValueAsObject(key("Target")) or nil
        if not valid(target) or target:GetFullName() ~= pawn:GetFullName() then return end
        if not policy:mayHit(t, id, isRanged(enemy:GetDistanceTo(pawn))) then block(id, t) end
    end)
    if not ok then log("EnableTrace hook error: %s", tostring(err)) end
end

local function hold(ctrl, id, want)
    local bb = ctrl.Blackboard
    if not valid(bb) then return end
    if want and not owned[id] then
        bb:SetValueAsBool(key("DefenceMode?"), true)
        owned[id] = ctrl
        dbg("hold %s", id)
    elseif not want and owned[id] then
        bb:SetValueAsBool(key("DefenceMode?"), false)
        owned[id] = nil
        dbg("release %s", id)
    end
end

local function releaseAll()
    for id, ctrl in pairs(owned) do
        if valid(ctrl) then pcall(hold, ctrl, id, false) end
        owned[id] = nil
    end
end

local function tick()
    local t = now()
    if not t then return end
    if blocking and t - blocking.since > SWING_MAX then unblock() end
    local pawn = playerPawn()
    if not pawn then return end
    if t >= nextScan then
        controllers = FindAllOf("GS_AI_NPCController_C") or {}
        nextScan = t + SCAN_MS / 1000
    end
    local me = pawn:GetFullName()
    local enemies, byId = {}, {}
    for _, ctrl in ipairs(controllers) do
        local bb = valid(ctrl) and ctrl.Blackboard or nil
        local enemy = valid(ctrl) and ctrl.Pawn or nil
        if valid(bb) and valid(enemy) and bb:GetValueAsEnum(key("Status")) == IN_COMBAT then
            local target = bb:GetValueAsObject(key("Target"))
            if valid(target) and target:GetFullName() == me then
                local id = ctrl:GetFullName()
                local dist = enemy:GetDistanceTo(pawn)
                local module = component(enemy, ENEMY)
                local attacking = module ~= nil and ATTACKING[module.CombatState] == true
                policy:observe(t, id, bb:GetValueAsInt(key("ComboAttackCounter")), attacking)
                enemies[#enemies + 1] = { id = id, dist = dist, ranged = isRanged(dist), targetsPlayer = true }
                byId[id] = ctrl
            end
        end
    end
    local roles = policy:roles(t, enemies)
    for _, e in ipairs(enemies) do
        local role = roles[e.id]
        local want = (CFG.attackRights and (role == "ready" or role == "wait"))
            or (CFG.antiStunlock and not e.ranged and not policy:available(t, e.id))
        hold(byId[e.id], e.id, want)
    end
    for id, ctrl in pairs(owned) do -- left the fight, died or no longer targets the player
        if not byId[id] then
            if valid(ctrl) then pcall(hold, ctrl, id, false) end
            owned[id] = nil
            policy:forget(id)
        end
    end
end

-- A script reload (Ctrl+R) loses the list of enemies the mod held back; nothing else in the game uses
-- "DefenceMode?", so clear it everywhere once.
local function clearAllHolds()
    for _, ctrl in ipairs(FindAllOf("GS_AI_NPCController_C") or {}) do
        local bb = valid(ctrl) and ctrl.Blackboard or nil
        if valid(bb) and bb:GetValueAsBool(key("DefenceMode?")) then bb:SetValueAsBool(key("DefenceMode?"), false) end
    end
end

-- The game's blueprint functions only exist once the world is loaded (at game start the mod already runs in
-- the main menu). So the hooks are registered from PlayerController:ClientRestart, the usual UE4SS way,
-- and right away if the functions are already there (script reload in game).
local hooked = {}
local function registerGameHooks()
    local hooks = {
        { P.gitHit, onGitHit, "GitHit" }, { P.knock, onKnock, "Knock" }, { P.reaction, onReaction, "Reaction" },
        { P.gotHit, onGotHit, "GotHit" }, { P.enemyTrace, onEnemyTrace, "enemy EnableTrace" },
    }
    for _, h in ipairs(hooks) do
        local path, fn, name = h[1], h[2], h[3]
        if not hooked[path] then
            local f = StaticFindObject(path)
            if f and f:IsValid() then
                local ok, err = pcall(RegisterHook, path, fn)
                hooked[path] = true
                if ok then dbg("hooked " .. name) else log("hook " .. name .. " failed: " .. tostring(err)) end
            end
        end
    end
end

-- ClientRestart also fires when the game re-possesses the player inside the same level (respawn, cutscenes),
-- so give back what the mod holds before forgetting it.
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    pcall(releaseAll)
    pcall(unblock)
    pcall(recoverFlag)
    policy:reset()
    owned, blocking, controllers, nextScan = {}, nil, {}, 0
    registerGameHooks()
end)
registerGameHooks()
pcall(clearAllHolds)
pcall(recoverFlag)

-- All Lua runs on the game thread (LoopInGameThreadWithDelay). Async loops/timers (LoopAsync, ExecuteWithDelay)
-- run Lua on other threads at the same time and corrupted UE4SS's Lua state in Camp Everywhere.
LoopInGameThreadWithDelay(CFG.tickMs, function()
    if not (CFG.attackRights or CFG.antiStunlock) then return end
    local ok, err = pcall(tick)
    if not ok then
        log("tick error: %s", tostring(err))
        pcall(releaseAll)
    end
end)

pcall(function()
    RegisterLoadMapPostHook(function()
        policy:reset()
        owned, blocking, controllers, nextScan = {}, nil, {}, 0
    end)
end)

log("v%s loaded", VERSION)
