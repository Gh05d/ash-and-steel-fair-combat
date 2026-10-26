-- Fair Combat settings. Times in seconds, distances in cm.
return {
    -- Anti-stunlock: after you stagger, no new stagger for this long (damage still applies).
    antiStunlock = true,
    staggerWindow = 1.5,
    recoverBuffer = 1.0, -- the enemy who staggered you waits this much longer after the window
    knockWindow = 3.5,   -- protection while you are knocked down and getting up
    staggerGrace = 1.5,  -- after the window: this long nothing can stagger or knock you down again (damage still applies)
    knockGrace = 2.5,    -- the same after a knockdown

    -- Attack rights: how many melee enemies may attack you at once, and how many wait close by.
    attackRights = true,
    attackers = 1,
    ready = 1,
    comboBackoff = 1.5,  -- an enemy backs off this long after finishing a combo
    rangedDistance = 750, -- enemies farther away than this count as ranged (archers) and are left alone

    -- Waiting enemies raise their guard and walk around you instead of just following you.
    waitBehavior = true,
    readyDistance = 250, -- the enemy next in line circles this close
    waitDistance = 400,  -- everyone else keeps this distance
    orbitStep = 50,      -- degrees around you per move
    orbitEvery = 1.0,    -- a new move every this many seconds
    guardEvery = 8.0,    -- the guard stance is renewed this often (the game ends it after 8-12 s)

    -- Turning: enemies turn towards you at the start of an attack. With turnLimit they only follow this
    -- share of the angle (the game: about 0.92), so stepping to the side or behind them pays off.
    turnLimit = false,   -- experimental: hooks a function that runs every frame
    attackTracking = 0.4,

    humanTurnLimit = true,
    humanTrackTime = 0.15,  -- humans aim this long at the start of an attack, then commit to the direction
    animalTurnFactor = 0.7, -- attacking animals turn at this share of their normal speed (1 = off)

    tickMs = 100,        -- how often enemies are re-evaluated (ms)
    debug = false,       -- log every decision to UE4SS.log
}
