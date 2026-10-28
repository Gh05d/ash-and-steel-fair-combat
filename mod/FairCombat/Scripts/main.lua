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
--   * Block\Parry (player, once per press): late in a stagger a parry press ends the stagger and parries.
--   * GotHit (enemy, once per hit): a melee hit of the player stops player and enemy for a moment; the game's
--     hit sounds play louder (hitsounds.lua).
--   * Every tickMs: enemies fighting the player get attack rights; the others are held back through the
--     behavior tree key "DefenceMode?" (the attack branch only runs while it is not set), raise their guard
--     and walk around the player.
local VERSION = "1.0.0"

local UEHelpers = require("UEHelpers")
local CFG = require("config")
local Policy = require("policy")
local WINDUPS = require("windups")
local HIT_SOUNDS = require("hitsounds")

local PLAYER = "/Game/Components/Combat/CombatModule_Player.CombatModule_Player_C"
local ENEMY = "/Game/Components/Combat/CombatModule_AI_Humanoid.CombatModule_AI_Humanoid_C"
local P = {
    gotHit = PLAYER .. ":GotHit",
    reaction = PLAYER .. ":Reaction",
    gitHit = PLAYER .. ":GitHit",
    knock = PLAYER .. ":Knock",
    enemyTrace = ENEMY .. ":EnableTrace",
    attackStart = "/Game/Components/Combat/AnimNotify/GS_RotateToEnemyAI.GS_RotateToEnemyAI_C:Received_NotifyBegin",
    playerTrace = PLAYER .. ":EnableTrace",
    enemyGotHit = ENEMY .. ":GotHit",
    blockParry = PLAYER .. ":Block\\Parry",
}
local WAS_HIT = 9                                   -- Character_CombatState WasHit (staggered)
local IDLE = 2                                      -- Character_CombatState Idle: Block\Parry only works then
local IN_COMBAT = 6                                 -- blackboard Status "inCombat"
local ATTACKING = { [0] = true, [11] = true, [12] = true } -- Character_CombatState Attacking, HeavyAttack, SpecialAttack
local SWING_MAX = 1.5                               -- safety: invincibility for one swing never lasts longer (s)
local SCAN_MS = 1500                                -- how often the list of AI controllers is rebuilt
local SAME_HIT = 0.02                               -- Reaction and GotHit of one hit run in the same frame (s)
local RETRY_MS = 50                                 -- second try to cancel a reaction montage that started late
local HUMAN = "GS_AI_NPCController_C"               -- human NPCs; animals have GS_AI_AnimalController_C
local ANIMAL = "GS_AI_AnimalController_C"
local STOP_SCALE = 0.05                            -- speed of player and enemy during a hit stop
local SOUND_EVERY = 30                              -- ticks between two runs of applyHitSounds
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

local function onGitHit()
    seen.kind = "stagger"
    seen.staggerAt = now()
end
local function onKnock() seen.kind = "knock" end

-- Measurement (debug only, changes nothing): for every swing of the player and of enemies fighting the
-- player, log the closest distance at start/end, whether it touched anyone, and the frame rate. Used to find
-- out where hits get lost (goal 3).
local fighting = {}     -- pawn full name -> pawn of every enemy that fought the player in the last tick
local playerSwing = nil -- { t, dist, hits, fps }
local enemySwing = {}   -- controller full name -> { t, dist, touched, name }

local function fps()
    local ok, d = pcall(function() return UEHelpers.GetGameplayStatics():GetWorldDeltaSeconds(UEHelpers.GetWorld()) end)
    return ok and d and d > 0 and 1 / d or 0
end

local function closestEnemy(pawn)
    local best = nil
    for name, enemy in pairs(fighting) do
        if valid(enemy) then
            local d = enemy:GetDistanceTo(pawn)
            if not best or d < best then best = d end
        else
            fighting[name] = nil
        end
    end
    return best
end

local function onPlayerTrace(_ctx, enable)
    pcall(function()
        if not CFG.debug then return end
        local pawn = playerPawn()
        if not pawn then return end
        local d = closestEnemy(pawn)
        if enable:get() then
            playerSwing = d and { t = now() or 0, dist = d, hits = 0, fps = fps() } or nil
        elseif playerSwing then
            local w = playerSwing
            playerSwing = nil
            log("measure player swing dist=%.0f->%.0f hits=%d fps=%.0f dur=%.2f", w.dist, d or -1, w.hits, w.fps,
                (now() or w.t) - w.t)
        end
    end)
end

-- Hit stop: on each of the player's melee hits player and enemy run at STOP_SCALE of their speed (the actor's
-- own time dilation, the rest of the world runs on) for hitStopMs, then get back the dilation they had.
local stops = {}        -- actor full name -> { actor, prev = dilation before, stop = { from, to } }

local function releaseStops(all, quiet)
    local t = now()
    local left = nil
    for name, s in pairs(stops) do
        if not valid(s.actor) then
            stops[name] = nil
        elseif all or not t or t >= s.stop.to - 0.001 or t - s.stop.from > SWING_MAX then
            s.actor.CustomTimeDilation = s.prev
            stops[name] = nil
        else
            left = math.max(left or 0, s.stop.to - t)
        end
    end
    if left and not quiet then ExecuteInGameThreadWithDelay(math.max(10, math.ceil(left * 1000)), function() pcall(releaseStops) end) end
end

local function hitStop(actors, t)
    local d = CFG.hitStopMs / 1000
    for _, a in ipairs(actors) do
        local name = a:GetFullName()
        local s = stops[name]
        if not s then
            local prev = a.CustomTimeDilation
            if Policy.stuck(prev, STOP_SCALE) then prev = 1.0 end
            s = { actor = a, prev = prev }
            stops[name] = s
            a.CustomTimeDilation = STOP_SCALE
        end
        s.stop = Policy.hitStop(s.stop, t, d)
    end
    ExecuteInGameThreadWithDelay(CFG.hitStopMs, function() pcall(releaseStops) end)
end

-- After a script reload (Ctrl+R) the list of running stops is gone: whoever still runs at the stop scale
-- and is not in a stop gets normal speed back.
local function unstick(actor)
    if valid(actor) and not stops[actor:GetFullName()] and Policy.stuck(actor.CustomTimeDilation, STOP_SCALE) then
        actor.CustomTimeDilation = 1.0
    end
end

-- The hit sounds are shared objects (loaded with the combat module), so they are set again every few seconds
-- in case the game loaded them anew.
local function applyHitSounds()
    if not CFG.hitSoundVolume then return end
    for _, path in ipairs(HIT_SOUNDS) do
        local cue = StaticFindObject(path)
        if valid(cue) then
            if cue.VolumeMultiplier ~= CFG.hitSoundVolume then cue.VolumeMultiplier = CFG.hitSoundVolume end
            if cue.PitchMultiplier ~= 1.0 then cue.PitchMultiplier = 1.0 end
        end
    end
end

-- After an enemy's GotHit (once per hit it takes): hit stop when the player hit it in melee; in debug also
-- counts the hit for the swing measurement.
local function onEnemyGotHit(ctx, _impact, _damage, _stamina, _stagger, _direction, attacker)
    local ok, err = pcall(function()
        local who, pawn = attacker:get(), playerPawn()
        if not valid(who) or not pawn or who:GetFullName() ~= pawn:GetFullName() then return end
        if playerSwing then playerSwing.hits = playerSwing.hits + 1 end
        local enemy = ctx:get():GetOwner()
        local t = now()
        if CFG.hitStopMs <= 0 or not valid(enemy) or not t or isRanged(enemy:GetDistanceTo(pawn)) then return end
        hitStop({ enemy, pawn }, t)
    end)
    if not ok then log("enemy GotHit hook error: %s", tostring(err)) end
end

local function measureEnemySwing(id, enemy, pawn, on)
    if not CFG.debug then return end
    local d = enemy:GetDistanceTo(pawn)
    if on then
        enemySwing[id] = { t = now() or 0, dist = d, touched = false, name = enemy:GetClass():GetFName():ToString(), fps = fps() }
    elseif enemySwing[id] then
        local w = enemySwing[id]
        enemySwing[id] = nil
        log("measure enemy swing %s dist=%.0f->%.0f touched=%s fps=%.0f dur=%.2f", w.name, w.dist, d, tostring(w.touched),
            w.fps, (now() or w.t) - w.t)
    end
end

-- After GotHit: only hits that reached Reaction count (not blocked, dodged or ignored ones). Inside a
-- protection window, or from an enemy that has to wait, the stagger/knockdown the hit started is cancelled.
local function onGotHit(ctx, _impact, _damage, _stamina, _stagger, _direction, attacker)
    pcall(function() -- measurement: this enemy's swing reached the player (also when blocked or dodged)
        local e = attacker:get()
        local c = valid(e) and e.Controller or nil
        local w = valid(c) and enemySwing[c:GetFullName()] or nil
        if w then w.touched = true end
    end)
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
        if CFG.antiStunlock and reaction ~= "none" and (not policy:mayStagger(t) or not mayHit) then
            local anim = pawn.Mesh:GetAnimInstance()
            local montage = valid(anim) and anim:GetCurrentActiveMontage() or nil
            -- only the reaction itself: when the player was attacking, the active montage can be their own swing
            local name = valid(montage) and montage:GetFName():ToString() or nil
            local stop = Policy.isReactionMontage(name)
            if stop then anim:Montage_Stop(0.15, montage) end
            dbg("hit by %s (%s, %s): %s %s", id, protected or (mayHit and "grace" or "locked"), reaction,
                stop and "cancelled" or "retry", tostring(name))
            if not stop then
                -- the reaction montage can start a frame later; if it still can't be found, the player really
                -- got staggered and the protection starts over from now
                local kind = reaction
                ExecuteInGameThreadWithDelay(RETRY_MS, function()
                    pcall(function()
                        local m = valid(anim) and anim:GetCurrentActiveMontage() or nil
                        local n = valid(m) and m:GetFName():ToString() or nil
                        if Policy.isReactionMontage(n) then
                            anim:Montage_Stop(0.15, m)
                            dbg("retry cancelled %s", n)
                        else
                            local t2 = now()
                            if t2 then policy:restart(t2, id, kind, ranged) end
                            dbg("could not cancel (%s): protection starts over", tostring(n))
                        end
                    end)
                end)
            end
            reaction = "none"
        end
        policy:hit(t, id, CFG.antiStunlock and reaction or "none", ranged)
        dbg("hit by %s reaction=%s ranged=%s window=%s", id, reaction, tostring(ranged), tostring(policy:protection(t)))
    end)
    if not ok then log("GotHit hook error: %s", tostring(err)) end
end

-- Parry out of a stagger: the game only takes a parry press while the player is Idle, and a stagger keeps the
-- player in WasHit for 1.4-1.7 s. Block\Parry still runs on every press (once per press); once the stagger has
-- run parryCancel, the mod ends it and passes the press on again.
local parrying = false

local function onBlockParry(ctx)
    if parrying then return end -- the mod's own call below
    local ok, err = pcall(function()
        local m = ctx:get()
        if not valid(m) or m.CombatState ~= WAS_HIT then return end
        local t = now()
        local pawn = m:GetOwner()
        local anim = valid(pawn) and pawn.Mesh:GetAnimInstance() or nil
        local montage = valid(anim) and anim:GetCurrentActiveMontage() or nil
        local name = valid(montage) and montage:GetFName():ToString() or "-"
        if not t or not Policy.mayParryOut(t, seen.staggerAt, CFG.parryCancel) or not Policy.isReactionMontage(name) then
            dbg("parry press in stagger after %.2f s (%s): too early or no hit reaction", t and seen.staggerAt and t - seen.staggerAt or -1, name)
            return
        end
        anim:Montage_Stop(0.1, montage)
        m.CombatState = IDLE
        parrying = true
        local called, cerr = pcall(function() m["Block\\Parry"](m) end)
        parrying = false
        dbg("parry out of stagger after %.2f s (%s)%s", t - seen.staggerAt, montage:GetFName():ToString(),
            called and "" or ": " .. tostring(cerr))
    end)
    parrying = false
    if not ok then log("Block\\Parry hook error: %s", tostring(err)) end
end

-- After an enemy's EnableTrace (start/end of one swing): block the player's hits while an enemy swings
-- that may not hit right now (used its hit in the window, or waits for the player to recover).
local swings = {}       -- controller full name -> true while that enemy's swing is active
local stretched = {}    -- controller full name -> { anim, montage, rate, since } while its wind-up is slowed

local function unstretch(id)
    local w = stretched[id]
    stretched[id] = nil
    if w and valid(w.anim) and valid(w.montage) then w.anim:Montage_SetPlayRate(w.montage, w.rate) end
end

-- After GS_RotateToEnemyAI begins (frame one of an enemy attack, once per attack): attacks whose hit window
-- opens very early (windups.lua) play slower until the swing starts, so they can be read.
local function onAttackStart(_ctx, meshComp, animation)
    local ok, err = pcall(function()
        if not CFG.windup then return end
        local montage = animation:get()
        local trace = valid(montage) and WINDUPS[montage:GetFName():ToString()] or nil
        if not trace then return end
        local mesh = meshComp:get()
        local enemy = valid(mesh) and mesh:GetOwner() or nil
        local ctrl = valid(enemy) and enemy.Controller or nil
        local pc, pawn = UEHelpers.GetPlayerController(), playerPawn()
        if not valid(ctrl) or not pawn or (valid(pc) and ctrl:GetFullName() == pc:GetFullName()) then return end -- never the player's own attacks
        local bb = ctrl.Blackboard
        local target = valid(bb) and bb:GetValueAsObject(key("Target")) or nil
        if not valid(target) or target:GetFullName() ~= pawn:GetFullName() then return end
        local anim = mesh:GetAnimInstance()
        if not valid(anim) then return end
        local rate = anim:Montage_GetPlayRate(montage)
        local slow = Policy.windupRate(trace, CFG.minWindup, rate)
        if slow >= rate then return end
        local id = ctrl:GetFullName()
        unstretch(id)
        anim:Montage_SetPlayRate(montage, slow)
        stretched[id] = { anim = anim, montage = montage, rate = rate, since = now() or 0 }
        dbg("wind-up %s: rate %.2f -> %.2f", montage:GetFName():ToString(), rate, slow)
    end)
    if not ok then log("attack start hook error: %s", tostring(err)) end
end

local function onEnemyTrace(ctx, enable)
    local ok, err = pcall(function()
        local on = enable:get()
        local enemy = ctx:get():GetOwner()
        if not valid(enemy) then return end
        local ctrl = enemy.Controller
        if not valid(ctrl) then return end
        local id = ctrl:GetFullName()
        if on then unstretch(id) end -- the swing itself plays at normal speed
        local me = playerPawn()
        local bb = ctrl.Blackboard
        local target = valid(bb) and bb:GetValueAsObject(key("Target")) or nil
        local atMe = me ~= nil and valid(target) and target:GetFullName() == me:GetFullName()
        swings[id] = (on and atMe) or nil
        if me and (atMe or enemySwing[id]) then pcall(measureEnemySwing, id, enemy, me, on) end
        if not on then
            if blocking and blocking.id == id then unblock() end
            return
        end
        local t = now()
        if not CFG.antiStunlock or not atMe or not t or blocking then return end
        if not policy:mayHit(t, id, isRanged(enemy:GetDistanceTo(me))) then block(id, t) end
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
-- (AI_C_Attack and AI_C_AttackTired never start that timer)
local ATTACK_TASKS = { "AI_C_AttackCombo_C", "AI_C_AttackHeavy_C", "AI_C_AttackWithFake_C", "AI_C_AttackSpecial_C" }
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
    if next(stops) then releaseStops(false, true) end -- safety net for the release timer
    for id, w in pairs(stretched) do
        if t - w.since > SWING_MAX then unstretch(id) end
    end
    -- a swing that started before its enemy got locked (e.g. the window ended mid-swing) is blocked now
    if CFG.antiStunlock and not blocking then
        for id in pairs(swings) do
            if not policy:mayHit(t, id, false) then
                block(id, t)
                break
            end
        end
    end
    local pawn = playerPawn()
    if not pawn then return end
    if t >= nextScan then
        controllers = {}
        for _, cls in ipairs({ HUMAN, ANIMAL }) do
            for _, c in ipairs(FindAllOf(cls) or {}) do controllers[#controllers + 1] = c end
        end
        nextScan = t + SCAN_MS / 1000
        unstick(pawn)
        for _, c in ipairs(controllers) do
            if valid(c) then unstick(c.Pawn) end
        end
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
                if CFG.debug then fighting[enemy:GetFullName()] = enemy end
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
            swings[id] = nil
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
        { P.attackStart, onAttackStart, "attack start (GS_RotateToEnemyAI)" },
        { P.enemyGotHit, onEnemyGotHit, "enemy GotHit" }, { P.blockParry, onBlockParry, "Block\\Parry" },
    }
    if CFG.debug then -- measurement only
        hooks[#hooks + 1] = { P.playerTrace, onPlayerTrace, "player EnableTrace" }
    end
    -- never hook Base_NPC:Combat_RotateToTarget: it fires up to ~70 times per second (live 2026-10-26)
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
    pcall(releaseStops, true)
    policy:reset()
    owned, blocking, controllers, nextScan, moves, slowed, aiming, swings, stretched, fighting = {}, nil, {}, 0, {}, {}, {}, {}, {}, {}
    registerGameHooks()
end)
registerGameHooks()
pcall(clearAllHolds)
pcall(recoverFlag)

-- All Lua runs on the game thread (LoopInGameThreadWithDelay). Async loops/timers (LoopAsync, ExecuteWithDelay)
-- run Lua on other threads at the same time and corrupted UE4SS's Lua state in Camp Everywhere.
local ticks = 0
LoopInGameThreadWithDelay(CFG.tickMs, function()
    if ticks % SOUND_EVERY == 0 then
        local ok, err = pcall(applyHitSounds)
        if not ok then log("hit sounds error: %s", tostring(err)) end
    end
    ticks = ticks + 1
    if not (CFG.attackRights or CFG.antiStunlock or CFG.windup or CFG.humanTurnLimit or CFG.animalTurnFactor < 1
        or CFG.hitStopMs > 0) then return end
    local ok, err = pcall(tick)
    if not ok then
        log("tick error: %s", tostring(err))
        pcall(releaseAll)
    end
end)

pcall(function()
    RegisterLoadMapPostHook(function()
        stops = {}
        policy:reset()
        owned, blocking, controllers, nextScan, moves, slowed, aiming, swings, stretched, fighting = {}, nil, {}, 0, {}, {}, {}, {}, {}, {}
    end)
end)

log("v%s loaded", VERSION)
