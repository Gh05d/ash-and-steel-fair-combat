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
--     behavior tree key "DefenceMode?" (the attack branch only runs while it is not set), raise their guard
--     and walk around the player.
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
    rotate = "/Game/Characters/NPC/NPC_Parent/Base_NPC.Base_NPC_C:Combat_RotateToTarget",
}
local ROTATE_LENGTH = 0.5                           -- length of Base_NPC's RotateToTarget timeline (s)
local IN_COMBAT = 6                                 -- blackboard Status "inCombat"
local ATTACKING = { [0] = true, [11] = true, [12] = true } -- Character_CombatState Attacking, HeavyAttack, SpecialAttack
local SWING_MAX = 1.5                               -- safety: invincibility for one swing never lasts longer (s)
local SCAN_MS = 1500                                -- how often the list of AI controllers is rebuilt
local SAME_HIT = 0.02                               -- Reaction and GotHit of one hit run in the same frame (s)
local HUMAN = "GS_AI_NPCController_C"               -- human NPCs; animals have GS_AI_AnimalController_C
local ANIMAL = "GS_AI_AnimalController_C"
local ANIMAL_HELD = 10                              -- SimpleAttackCounter this high: animals taunt and dodge instead of biting

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
        local pc = UEHelpers.GetPlayerController()
        local npc = not valid(pc) or ctrl:GetFullName() ~= pc:GetFullName()
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

local function isHuman(ctrl)
    return ctrl:GetClass():GetFName():ToString() == HUMAN
end

-- Held humans raise their guard (the game's own SetDefenceMode) and walk around the player at a distance,
-- facing them. Without this they only follow the player (the behavior tree's MoveToTarget branch).
-- Animals need none of this: their tree taunts, dodges and jumps when it may not bite.
local moves = {}        -- controller full name -> { next = t, guard = t, sign = 1|-1, guarded = bool }
local turn = 1

local function stopWander(ctrl, id)
    local w = moves[id]
    moves[id] = nil
    if not w or not valid(ctrl) then return end
    local enemy = ctrl.Pawn
    local m = valid(enemy) and component(enemy, ENEMY) or nil
    if w.guarded and m then m:ReturnToBasicMode() end
    ctrl:StopMovement()
    ctrl:K2_ClearFocus()
end

local function wander(ctrl, enemy, pawn, id, role, t)
    if not CFG.waitBehavior then return end
    local w = moves[id]
    if not w then
        turn = -turn
        w = { next = 0, guard = 0, sign = turn }
        moves[id] = w
    end
    if t >= w.guard then
        local m = component(enemy, ENEMY)
        if m then
            m:SetDefenceMode(false)
            w.guarded = true
        end
        w.guard = t + CFG.guardEvery
    end
    if t >= w.next then
        local a, b = pawn:K2_GetActorLocation(), enemy:K2_GetActorLocation()
        local radius = role == "ready" and CFG.readyDistance or CFG.waitDistance
        local x, y = Policy.orbitPoint(a.X, a.Y, b.X, b.Y, radius, CFG.orbitStep, w.sign)
        ctrl:MoveToLocation({ X = x, Y = y, Z = b.Z }, 50, true, true, true, true, nil, true)
        ctrl:K2_SetFocus(pawn)
        w.next = t + CFG.orbitEvery
    end
end

-- Humans: the attack branch of their tree only runs while "DefenceMode?" is not set. Animals: simple bites
-- only run while SimpleAttackCounter is at most 3; their taunt resets it, so it is set again every tick.
-- After Combat_RotateToTarget (start of an attack, taunt or dodge): the game turns the enemy towards the
-- player for 0.5 s, almost all the way. A faster timeline ends the turn early, so side steps work.
local function onRotate(ctx, target, _mesh, speed, interp, stop)
    local ok, err = pcall(function()
        if not CFG.turnLimit or stop:get() then return end
        local pawn = playerPawn()
        local who = target:get()
        if not pawn or not valid(who) or who:GetFullName() ~= pawn:GetFullName() then return end
        local timeline = ctx:get().RotateToTarget
        if not valid(timeline) then return end
        local rate = Policy.trackingRate(CFG.attackTracking, interp:get(), ROTATE_LENGTH, speed:get())
        timeline:SetPlayRate(rate)
        dbg("turn limit: rate %.2f -> %.2f", speed:get(), rate)
    end)
    if not ok then log("Combat_RotateToTarget hook error: %s", tostring(err)) end
end

local function hold(ctrl, id, want)
    local bb = ctrl.Blackboard
    if not valid(bb) then return end
    local human = isHuman(ctrl)
    if want and not human then bb:SetValueAsInt(key("SimpleAttackCounter"), ANIMAL_HELD) end
    if want and not owned[id] then
        if human then bb:SetValueAsBool(key("DefenceMode?"), true) end
        owned[id] = ctrl
        dbg("hold %s", id)
    elseif not want and owned[id] then
        if human then bb:SetValueAsBool(key("DefenceMode?"), false) else bb:SetValueAsInt(key("SimpleAttackCounter"), 0) end
        owned[id] = nil
        pcall(stopWander, ctrl, id)
        dbg("release %s", id)
    end
end

-- Animals turn with their movement component (bUseControllerDesiredRotation, e.g. 90-180 deg/s). While
-- they attack the player they turn at animalTurnFactor of that, so a side step during a bite pays off; lining
-- up for an attack stays at full speed (slower made them never face the player, so they never bit).
-- The class default is the original.
local slowed = {}       -- movement component full name -> movement component

local function defaultYaw(enemy)
    local cdo = enemy:GetClass():GetCDO()
    local mv = valid(cdo) and cdo.CharacterMovement or nil
    return valid(mv) and mv.RotationRate.Yaw or nil
end

local function slowTurn(enemy, on)
    local mv = enemy.CharacterMovement
    if not valid(mv) then return end
    local name = mv:GetFullName()
    if on == (slowed[name] ~= nil) then return end
    local yaw = defaultYaw(enemy)
    if not yaw then return end
    local r = mv.RotationRate
    mv.RotationRate = { Pitch = r.Pitch, Yaw = on and yaw * CFG.animalTurnFactor or yaw, Roll = r.Roll }
    slowed[name] = on and mv or nil
    dbg("%s turn %s: yaw %.0f", enemy:GetFName():ToString(), on and "slow" or "normal", mv.RotationRate.Yaw)
end

-- Humans: their attack tasks start a 0.01 s timer that turns them towards the target every frame during the
-- first half of the attack (Combat_RotateToTarget, speed 5). After humanTrackTime of an attack the mod pauses
-- that timer and stops the turn timeline: the enemy aims briefly, then commits to the direction.
local ATTACK_TASKS = { "AI_C_Attack_C", "AI_C_AttackCombo_C", "AI_C_AttackHeavy_C", "AI_C_AttackWithFake_C",
    "AI_C_AttackSpecial_C", "AI_C_AttackTired_C" }
local aiming = {}       -- controller full name -> { since = t, done = bool }

local function commitAttack(enemy)
    local world, ksl = UEHelpers.GetWorld(), UEHelpers.GetKismetSystemLibrary()
    local me, paused = enemy:GetFullName(), 0
    for _, cls in ipairs(ATTACK_TASKS) do
        for _, task in ipairs(FindAllOf(cls) or {}) do
            local p = valid(task) and task["Controlled Pawn"] or nil
            if valid(p) and p:GetFullName() == me then
                ksl:K2_PauseTimerHandle(world, task.Timer)
                paused = paused + 1
            end
        end
    end
    local timeline = enemy.RotateToTarget
    if valid(timeline) and timeline:IsPlaying() then timeline:Stop() end
    dbg("%s commits to its attack (%d task timers paused)", enemy:GetFName():ToString(), paused)
end

local function trackHuman(id, enemy, attacking, t)
    if not attacking then
        aiming[id] = nil
        return
    end
    local a = aiming[id]
    if not a then
        aiming[id] = { since = t }
    elseif not a.done and t - a.since >= CFG.humanTrackTime then
        a.done = true
        commitAttack(enemy)
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
        controllers = {}
        for _, cls in ipairs({ HUMAN, ANIMAL }) do
            for _, c in ipairs(FindAllOf(cls) or {}) do controllers[#controllers + 1] = c end
        end
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
                enemies[#enemies + 1] = { id = id, dist = dist, ranged = isRanged(dist), targetsPlayer = true, attacking = attacking }
                byId[id] = ctrl
            end
        end
    end
    local roles = policy:roles(t, enemies)
    for _, e in ipairs(enemies) do
        local role = roles[e.id]
        local want = (CFG.attackRights and (role == "ready" or role == "wait"))
            or (CFG.antiStunlock and not e.ranged and not policy:available(t, e.id))
        local ctrl = byId[e.id]
        hold(ctrl, e.id, want)
        if CFG.animalTurnFactor < 1 and not isHuman(ctrl) then pcall(slowTurn, ctrl.Pawn, e.attacking) end
        if CFG.humanTurnLimit and isHuman(ctrl) then
            local ok, err = pcall(trackHuman, e.id, ctrl.Pawn, e.attacking, t)
            if not ok then dbg("turn limit %s: %s", e.id, tostring(err)) end
        end
        if owned[e.id] and isHuman(ctrl) then
            local ok, err = pcall(wander, ctrl, ctrl.Pawn, pawn, e.id, role, t)
            if not ok then dbg("wander %s: %s", e.id, tostring(err)) end
        end
    end
    for name, mv in pairs(slowed) do -- animals that left the fight turn normally again
        local enemy = valid(mv) and mv:GetOwner() or nil
        local ctrl = valid(enemy) and enemy.Controller or nil
        if not valid(ctrl) or not byId[ctrl:GetFullName()] then
            if valid(enemy) then pcall(slowTurn, enemy, false) end
            slowed[name] = nil
        end
    end
    for id, ctrl in pairs(owned) do -- left the fight, died or no longer targets the player
        if not byId[id] then
            if valid(ctrl) then pcall(hold, ctrl, id, false) end
            owned[id] = nil
            moves[id] = nil
            policy:forget(id)
        end
    end
end

-- A script reload (Ctrl+R) loses the list of enemies the mod held back; nothing else in the game uses
-- "DefenceMode?", so clear it everywhere once.
local function clearAllHolds()
    for _, ctrl in ipairs(FindAllOf(HUMAN) or {}) do
        local bb = valid(ctrl) and ctrl.Blackboard or nil
        if valid(bb) and bb:GetValueAsBool(key("DefenceMode?")) then bb:SetValueAsBool(key("DefenceMode?"), false) end
    end
    for _, ctrl in ipairs(FindAllOf(ANIMAL) or {}) do -- turn rates back to the class default
        local enemy = valid(ctrl) and ctrl.Pawn or nil
        local mv = valid(enemy) and enemy.CharacterMovement or nil
        local yaw = valid(mv) and defaultYaw(enemy) or nil
        if yaw and mv.RotationRate.Yaw ~= yaw then
            local r = mv.RotationRate
            mv.RotationRate = { Pitch = r.Pitch, Yaw = yaw, Roll = r.Roll }
        end
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
    -- Combat_RotateToTarget fires up to ~70 times per second (live 2026-10-26): never hook it by default.
    if CFG.turnLimit then hooks[#hooks + 1] = { P.rotate, onRotate, "Combat_RotateToTarget" } end
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
    pcall(clearAllHolds)
    policy:reset()
    owned, blocking, controllers, nextScan, moves, slowed, aiming = {}, nil, {}, 0, {}, {}, {}
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
        owned, blocking, controllers, nextScan, moves, slowed, aiming = {}, nil, {}, 0, {}, {}, {}
    end)
end)

log("v%s loaded", VERSION)
