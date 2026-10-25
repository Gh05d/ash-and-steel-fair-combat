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

function Policy:mayStagger(now)
    return self:protection(now) == nil
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
    local length = reaction == "knock" and self.cfg.knockWindow or self.cfg.staggerWindow
    local to = now + length
    self.window = { kind = reaction, from = now, to = to, causer = id }
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
