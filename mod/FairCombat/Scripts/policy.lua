-- Fair Combat rules: pure Lua, no Unreal calls. Time is passed in (seconds), enemies are string ids.
--
-- Protection window: a stagger (or knockdown) opens a window in which you can't be staggered or knocked
-- down again. Every melee enemy may land one hit in it; the enemy who caused it gets exactly one follow-up
-- and then waits until you have recovered (window end + recoverBuffer). Ranged enemies are not limited.
-- Attack rights: at most cfg.attackers melee enemies attack, cfg.ready more wait close by, the rest keep
-- their distance. Whoever holds an attack slot keeps it until they are locked, back off or leave.
local Policy = {}
Policy.__index = Policy

function Policy.new(cfg)
    local p = setmetatable({ cfg = cfg }, Policy)
    p:reset()
    return p
end

function Policy:reset()
    self.window = nil      -- { kind = "stagger"|"knock", from = t, to = t, causer = id }
    self.used = {}         -- id -> true: has used its hit in the current window
    self.lock = {}         -- id -> { from = t, to = t }
    self.backoff = {}      -- id -> t (backing off until)
    self.holders = {}      -- ordered list of ids holding an attack slot
    self.combo = {}        -- id -> { count = n, running = bool, wasAttacking = bool }
end

function Policy:forget(id)
    self.used[id], self.lock[id], self.backoff[id], self.combo[id] = nil, nil, nil, nil
    for i = #self.holders, 1, -1 do
        if self.holders[i] == id then table.remove(self.holders, i) end
    end
end

function Policy:protection(now)
    local w = self.window
    if w and now < w.to then return w.kind end
    return nil
end

-- After a window comes a grace period (staggerGrace / knockGrace) in which nothing can stagger or knock the
-- player down again; hits still deal damage and are not limited.
function Policy:mayStagger(now)
    local w = self.window
    return not (w and now < w.graceTo)
end

-- The enemy who caused the last window waits until the player has recovered: none of its hits may land,
-- not even from a combo that was already running.
function Policy:locked(now, id)
    local l = self.lock[id]
    return l ~= nil and l.from <= now and now < l.to
end

function Policy:mayHit(now, id, ranged)
    if ranged then return true end
    if self:locked(now, id) then return false end
    if not self:protection(now) then return true end
    return not self.used[id]
end

function Policy:hit(now, id, reaction, ranged)
    if not ranged and self:locked(now, id) then return end
    if self:protection(now) then
        if not ranged and not self.used[id] then
            self.used[id] = true
            local l = self.lock[id]
            if id == self.window.causer and l then l.from = now end
        end
        return
    end
    if reaction ~= "stagger" and reaction ~= "knock" then return end
    if not self:mayStagger(now) then return end
    self:restart(now, id, reaction, ranged)
end

-- Opens a new protection window from now. Also used when the mod could not cancel a stagger the player got
-- inside a window: then the player recovers from this one, and window, grace and lock start over.
function Policy:restart(now, id, reaction, ranged)
    local length = reaction == "knock" and self.cfg.knockWindow or self.cfg.staggerWindow
    local to = now + length
    local grace = reaction == "knock" and self.cfg.knockGrace or self.cfg.staggerGrace
    self.window = { kind = reaction, from = now, to = to, graceTo = to + grace, causer = id }
    self.used = {}
    if not ranged then
        self.lock[id] = { from = to, to = to + self.cfg.recoverBuffer }
    end
end

function Policy:comboEnded(now, id)
    self.backoff[id] = now + self.cfg.comboBackoff
end

-- Called every tick per enemy: comboCount = blackboard ComboAttackCounter, attacking = in an attack state.
-- The combo task starts once the counter reached 3 and resets it; the combo ends when the enemy stops attacking.
function Policy:observe(now, id, comboCount, attacking)
    local c = self.combo[id] or {}
    if (c.count or 0) >= 3 and comboCount < 3 then c.running = true end
    if c.running and not attacking and c.wasAttacking then
        c.running = false
        self:comboEnded(now, id)
    end
    c.count, c.wasAttacking = comboCount, attacking
    self.combo[id] = c
end

-- Point on a circle of `radius` around the player (px, py), turned `angle` degrees from the enemy's
-- current direction (sign 1 = counter-clockwise, -1 = clockwise). Waiting enemies walk there.
function Policy.orbitPoint(px, py, ex, ey, radius, angle, sign)
    local dx, dy = ex - px, ey - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then dx, dy, len = 1, 0, 1 end
    dx, dy = dx / len, dy / len
    local a = math.rad(angle) * sign
    local rx, ry = dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a)
    return px + rx * radius, py + ry * radius
end

-- Wind-up: an attack whose hit window starts `traceStart` s into the montage (at play rate 1) takes
-- traceStart / rate in game. Returns the play rate that makes the wind-up last at least `minWindup` s.
function Policy.windupRate(traceStart, minWindup, rate)
    if traceStart < 0.05 or traceStart / rate >= minWindup then return rate end -- a trace from frame one: no wind-up to stretch
    return traceStart / minWindup
end

-- Is this a hit reaction of the player (stagger or knockdown) and not, say, the player's own attack or a parry?
function Policy.isReactionMontage(name)
    if type(name) ~= "string" or name:find("Parry", 1, true) then return false end
    return name:find("_Hit_", 1, true) ~= nil or name:find("Knockdown", 1, true) ~= nil
end

-- A montage the engine built at runtime from a single animation (ALS transitions such as stopping or landing).
function Policy.isDynamicMontage(name)
    return type(name) == "string" and name:find("^AnimMontage_%d+$") ~= nil
end

-- Hit stop: after one of the player's hits, player and enemy run almost frozen for `d` s. Returns the stop
-- { from, to } after a hit at `now`; a hit during a running stop extends it, but never past 2 * d in total.
function Policy.hitStop(stop, now, d)
    if not stop or now >= stop.to then return { from = now, to = now + d } end
    stop.to = math.max(stop.to, math.min(now + d, stop.from + 2 * d))
    return stop
end

-- An actor still running at the hit-stop scale although no stop runs: left over from a script reload.
function Policy.stuck(dilation, scale)
    return type(dilation) == "number" and math.abs(dilation - scale) < 0.001
end

-- Parry out of a stagger: once the stagger (started at `staggerAt`) has run `cancel` s, a parry press ends
-- it. Earlier presses are lost, as in the game. `cancel` false = off.
function Policy.mayParryOut(now, staggerAt, cancel)
    return cancel ~= false and cancel ~= nil and staggerAt ~= nil and now - staggerAt >= cancel - 1e-9
end

-- Can this enemy attack right now (not locked, not backing off, has not used its hit in the window)?
function Policy:available(now, id)
    if self:locked(now, id) then return false end
    local b = self.backoff[id]
    if b and now < b then return false end
    if self.used[id] and self:protection(now) then return false end
    return true
end

-- enemies: array of { id = string, dist = number, ranged = bool, targetsPlayer = bool }
-- returns { [id] = "attack" | "ready" | "wait" | "free" } for every enemy that targets the player
function Policy:roles(now, enemies)
    local roles, melee, present = {}, {}, {}
    for _, e in ipairs(enemies) do
        if e.targetsPlayer then
            if e.ranged then
                roles[e.id] = "free"
            else
                melee[#melee + 1] = e
                present[e.id] = true
            end
        end
    end
    table.sort(melee, function(a, b) return a.dist < b.dist end)

    local kept = {}
    for _, id in ipairs(self.holders) do
        if present[id] and self:available(now, id) and #kept < self.cfg.attackers then
            kept[#kept + 1] = id
            roles[id] = "attack"
        end
    end
    for _, e in ipairs(melee) do
        if #kept >= self.cfg.attackers then break end
        if not roles[e.id] and self:available(now, e.id) then
            kept[#kept + 1] = e.id
            roles[e.id] = "attack"
        end
    end
    self.holders = kept

    local ready = 0
    for _, e in ipairs(melee) do
        if not roles[e.id] then
            if ready < self.cfg.ready and self:available(now, e.id) then
                roles[e.id] = "ready"
                ready = ready + 1
            else
                roles[e.id] = "wait"
            end
        end
    end
    return roles
end

return Policy
