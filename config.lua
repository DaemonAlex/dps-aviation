-- dps-aviation: how our aircraft behave.
--
-- Everything here is a dial. Fly it, tell me what feels wrong, and it changes
-- in one place rather than across 44 aircraft files.

Config = {}

-- ===========================================================================
-- Engine and throttle
-- ===========================================================================

-- The fault this was written for: in GTA, holding the throttle down on a plane
-- past idle shuts the engine off, so easing off on approach kills it. With this
-- on, the engine is kept alive whenever the aircraft is flying or rolling, and
-- a shutdown is only allowed when you are stopped on the ground with the
-- parking brake set.
Config.keepEngineAlive = true

-- Ground speed (m/s) below which an aircraft counts as "stopped" for the
-- purpose of allowing a shutdown. 1.5 m/s is a walking pace.
Config.stoppedSpeed = 1.5

-- ===========================================================================
-- In-flight stability
-- ===========================================================================

-- Aircraft in GTA are twitchy: a tap of the stick spins them. This damps the
-- rotation that the player is NOT asking for, so an aircraft settles instead of
-- wallowing, and feels like it has mass.
Config.stabilise = true

-- How much of the unwanted rotation is removed per tick, 0 to 1.
-- 0.00 = no damping (vanilla), 0.35 = firm. Roll is damped least so turns still
-- feel like turns.
Config.dampPitch = 0.16
Config.dampRoll  = 0.10
Config.dampYaw   = 0.22

-- Damping is skipped while the player is actually moving the stick, and below
-- this height above ground so it never fights you on the runway.
Config.stabiliseMinAltitude = 15.0

-- ===========================================================================
-- Ground handling and taxi
-- ===========================================================================

-- Taxi assist: holds a sensible taxi speed and stops aircraft creeping when the
-- throttle is neutral. Takeoff is detected by holding full throttle, so this
-- never stands between you and the runway.
Config.taxiAssist = true

-- Target taxi speed in m/s. 8 m/s is about 15 knots, a normal taxi.
Config.taxiSpeed = 8.0

-- Full throttle held for this long (ms) releases the taxi limit for takeoff.
Config.takeoffHold = 1200

-- No instruments here: jg-hud already shows speed and altitude.

-- ===========================================================================
-- Preflight: spool-up, NO GO, master alarm
-- ===========================================================================
--
-- What the dead BigDaddy Preflight did, done here. Enter a cold aircraft (or
-- /astart) and the engines take real time to come up. A plane idles and can
-- taxi while it spools, but full throttle will not release the taxi limit
-- until GO. A helicopter's rotors stay down until GO. GO lives on the aircraft
-- (state bag), so a warm aircraft stays warm when crews swap; /ashutdown makes
-- it cold again.
Config.preflight = true

-- The start SEQUENCES, in REAL seconds, from how the real machines start
-- (researched 2026-09-24):
--   Piston  - crank is quick; the wait is the warm-up. Cessna 172: 2 min at
--             ~1000 RPM warm weather, 4 min cold, then a run-up; ready when the
--             throttle opens without a stumble.
--   Turboprop (PT6) - starter limited to 40 s on; light-off within ~10 s of
--             fuel; ~35 s to idle; short warm-up.
--   Jet     - APU first (~1-2 min), then ONE engine at a time, ~40-60 s each
--             to stable idle, second only after the first is stable; then idle
--             before takeoff power ("for example three minutes").
--   Turbine helicopter - battery and avionics, engine start(s) 20-120 s each,
--             then the rotor is engaged and brought to RPM; a medium twin is
--             60-180 s cold. The game cannot spin a rotor with the engine off,
--             so the engine comes on at the rotor-engage stage.
-- `engineOn` marks the stage the engine actually lights; from there a plane
-- idles and can taxi, and it stays on. GO comes at the end of the last stage.
Config.startSequence = {
    piston = {
        { seconds = 15,  label = 'BATTERY / AVIONICS' },
        { seconds = 10,  label = 'PRIME AND CRANK', engineOn = true },
        { seconds = 150, label = 'WARM-UP' },
        { seconds = 20,  label = 'RUN-UP' },
    },
    turboprop = {
        { seconds = 20,  label = 'BATTERY / AVIONICS' },
        { seconds = 40,  label = 'ENGINE START', engineOn = true },
        { seconds = 60,  label = 'WARM-UP' },
    },
    jet = {   -- bizjets and regional jets
        { seconds = 30,  label = 'BATTERY / AVIONICS' },
        { seconds = 75,  label = 'APU START' },
        { seconds = 50,  label = 'ENGINE 2 START', engineOn = true },
        { seconds = 50,  label = 'ENGINE 1 START' },
        { seconds = 180, label = 'IDLE - WARM-UP' },
    },
    airliner = {   -- the big jets: the whole flight-deck flow, one engine at a time
        { seconds = 25,  label = 'BATTERY / EXTERNAL POWER' },
        { seconds = 75,  label = 'APU START' },
        { seconds = 60,  label = 'FMC / FUEL / HYDRAULICS' },
        { seconds = 55,  label = 'ENGINE 2 START', engineOn = true },
        { seconds = 55,  label = 'ENGINE 1 START' },
        { seconds = 45,  label = 'FLAPS / TRIM / BEFORE-TAXI CHECKLIST' },
        { seconds = 180, label = 'IDLE - WARM-UP' },
    },
    -- The rotor engage stage is the one that takes a real minute or more, and
    -- the blades are driven up through it (SetHeliBladesSpeed) rather than
    -- letting the game snap them to speed in ten seconds.
    -- Tuned from the seat 2026-09-24: a minute cold to GO for a single is
    -- right, two was a lot. Twins get a little more for the second engine.
    heli = {
        { seconds = 15,  label = 'BATTERY / AVIONICS' },
        { seconds = 25,  label = 'ENGINE START' },
        { seconds = 50,  label = 'ROTOR ENGAGE', engineOn = true, rotor = true },
        { seconds = 10,  label = 'RPM AND CHECKS' },
    },
    heli_twin = {
        { seconds = 15,  label = 'BATTERY / AVIONICS' },
        { seconds = 25,  label = 'ENGINE 1 START' },
        { seconds = 25,  label = 'ENGINE 2 START' },
        { seconds = 55,  label = 'ROTOR ENGAGE', engineOn = true, rotor = true },
        { seconds = 15,  label = 'RPM AND CHECKS' },
    },
}

-- Drive the rotor blade speed by hand through the engage stage
-- (SetHeliBladesSpeed) so it visibly winds up over the minute? OFF while we
-- test: the first heli that took off with it on went out of control
-- (2026-09-24). Off = the game spins the blades itself once the engine is on.
Config.driveRotor = false

-- One dial for how much of real time we play out. 1.0 = the real numbers
-- above (an airliner is ~8 min cold to GO). 0.6 is the shipped feel: single
-- heli ~60 s, twin ~80 s, piston ~2 min, bizjet ~4 min, airliner ~5 min - and
-- a jet taxis during its warm-up, as the real one does.
Config.timeScale = 0.6

-- Per-model TOTAL override in real seconds (before timeScale), when a craft
-- should be quicker or slower than its class. Names, not hashes.
Config.spinupModel = {
    -- DPS 2026-10-25 fleet cut: 2021medheli removed
}

-- Which start sequence a model gets. Anything in class 16 not listed here is
-- piston; anything in class 15 not in twinHelis is a single. Names, not
-- hashes; add addons as they arrive.
Config.airlinerModels = {
    'jet', 'cargoplane',                                      -- vanilla 747-class
    '737', '737400', '737500', '737600', '737700', '737800', '737900', '737900er',
    '7310', '738', '757', '757f', '7674',                     -- dpsveh-air Boeings (737200, 739 cut 2026-10-25)
}
Config.jetModels = {
    -- vanilla
    'luxor', 'luxor2', 'shamal', 'miljet', 'nimbus', 'vestra', 'lazer', 'hydra',
    'besra', 'molotok', 'starling', 'alkonost', 'strikeforce', 'avenger',
    -- DPS regional and bizjets (dpsveh-air)
    'jetstar', 'jetstar2',                                    -- e145, l650 cut 2026-10-25
}
Config.turbopropModels = {
    'titan', 'bombushka', 'volatol',   -- vanilla
    '208', '8q400',                    -- Caravan, Dash 8
}
-- Twins get the two-engine sequence. Singles (buzzard, frogger, conada and
-- their liveried copies, the AM-117) are everything else in class 15.
Config.twinHelis = {
    -- vanilla twins (Maverick/Polmav are Bell 412 class; Swift, Annihilator, Cargobob)
    'maverick', 'polmav', 'swift', 'swift2', 'annihilator', 'annihilator2', 'cargobob', 'cargobob2',
    'cargobob3', 'cargobob4', 'valkyrie', 'valkyrie2', 'savage', 'skylift', 'supervolito', 'supervolito2',
    -- DPS packs
    'ec135med', '2vd_supervolito',                                -- EMS (2021medheli cut 2026-10-25)
    'hvpolmav', 'roxpolmav', 'hvannihilator', 'hvannihilator2', 'hvcargobob5', -- LEO
    'hvfdannihilator', 'hvfdannihilator2', 'hvfdswift', 'cghelir',              -- fire, coast guard
    'newsheli', 'newsheli2',                                                    -- news (Maverick base)
}

-- Models that skip preflight entirely (drones, toys). The old script had rcmavic.
Config.preflightExempt = { 'rcmavic' }

-- NO GO lines. Fuel below this (ox_fuel units, 0-100) refuses a start.
Config.minFuel = 1.0

-- Engine health (0-1000). At alarmHealth the master alarm sounds once; at
-- deadHealth the keep-alive stops relighting the engine and /astart refuses -
-- it is seized until a mechanic repairs it.
Config.alarmHealth = 350
Config.deadHealth  = 100
Config.alarmBeeps  = 4
Config.alarmShowMs = 5000
Config.goShowMs    = 2500

-- The one-line status. Kept to one line on purpose: jg-hud is the HUD.
Config.textStyle = {
    cold  = { position = 'top-center', icon = 'power-off',            style = { backgroundColor = '#1a1e20', color = '#a3acb0' } },
    spool = { position = 'top-center', icon = 'fan',                  style = { backgroundColor = '#1a1e20', color = '#ff7a45' } },
    go    = { position = 'top-center', icon = 'plane-departure',      style = { backgroundColor = '#1f5a3a', color = '#ffffff' } },
    nogo  = { position = 'top-center', icon = 'ban',                  style = { backgroundColor = '#5a1f1f', color = '#ffffff' } },
    alarm = { position = 'top-center', icon = 'triangle-exclamation', style = { backgroundColor = '#7a1f1f', color = '#ffffff' } },
}

-- ===========================================================================
-- Scope
-- ===========================================================================

-- Vehicle classes this script touches. 16 is Planes, 15 is Helicopters. Helis
-- get the engine keep-alive and preflight; taxi assist is planes only (a heli
-- does not taxi, and while cold its engine is simply off).
Config.classes = { [15] = true, [16] = true }

-- City pilot licences, earned in the City Services app (dps-services, Damon
-- 2026-10-11): flying any plane needs Private Pilot (or higher), any helicopter
-- needs the Helicopter licence. Emergency jobs fly their own aircraft without it.
Config.licences = {
    enabled = true,
    plane = { 'pilot_private', 'pilot_commercial', 'pilot_atp' }, -- any one of these
    heli = { 'heli' },
    exemptJobTypes = { leo = true, ems = true, military = true }, -- police, EMS and fire, National Guard
}
