-- Fair Combat settings. Times in seconds, distances in cm.
return {
    -- Anti-stunlock: after you stagger, no new stagger for this long (damage still applies).
    antiStunlock = true,
    staggerWindow = 1.5,
    recoverBuffer = 0.5, -- the enemy who staggered you waits this much longer after the window
    knockWindow = 3.5,   -- protection while you are knocked down and getting up

    -- Attack rights: how many melee enemies may attack you at once, and how many wait close by.
    attackRights = true,
    attackers = 1,
    ready = 1,
    comboBackoff = 1.5,  -- an enemy backs off this long after finishing a combo

    tickMs = 100,        -- how often enemies are re-evaluated (ms)
    debug = false,       -- log every decision to UE4SS.log
}
