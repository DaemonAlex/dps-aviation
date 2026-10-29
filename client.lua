-- dps-aviation — flight behaviour.
--
-- Scope note: stability is NOT fought from here. Aircraft handling files carry
-- fPitchStabilise / fRollStabilise / fYawStabilise in their flying handling
-- data, and that is the correct place to damp twitchiness - a script shoving
-- angular velocity around every frame desyncs in multiplayer and fights the
-- player. This resource covers the things handling data cannot express: an
-- engine that idles instead of shutting down and a sane taxi.

local KEEPALIVE_TICK <const> = 200
local TAXI_TICK <const> = 100

-- Controls we treat as "the pilot is flying it". Keyboard pitch/roll live on
-- the movement axes for aircraft; 71/72 are throttle up/down, 44/46 rudder.
local FLY_INPUTS <const> = { 32, 33, 34, 35, 44, 46, 71, 72 }

local fullThrottleSince = nil
local takeoffMode = false

-- ---------------------------------------------------------------------------
-- Preflight state
-- ---------------------------------------------------------------------------
-- An aircraft is GO once its engines have spooled. That lives on the entity as
-- a replicated state bag (`dpsGo`), so it follows the aircraft, not the pilot:
-- a warm aircraft stays warm when crews swap, a cold one needs its spool-up.
local spool = nil        -- { veh, startedAt, seconds, kind } while MY aircraft is spooling
local alarmed = {}       -- veh -> true after the master alarm has sounded for this engine event
local textShown = false

local JET, AIRLINER, TURBOPROP, TWIN, EXEMPT, SPIN_MODEL = {}, {}, {}, {}, {}, {}
for _, n in ipairs(Config.jetModels or {}) do JET[joaat(n)] = true end
for _, n in ipairs(Config.airlinerModels or {}) do AIRLINER[joaat(n)] = true end
for _, n in ipairs(Config.turbopropModels or {}) do TURBOPROP[joaat(n)] = true end
for _, n in ipairs(Config.twinHelis or {}) do TWIN[joaat(n)] = true end
for _, n in ipairs(Config.preflightExempt or {}) do EXEMPT[joaat(n)] = true end
for n, secs in pairs(Config.spinupModel or {}) do SPIN_MODEL[joaat(n)] = secs end

---@param veh number
---@return boolean
local function isGo(veh)
    return Entity(veh).state.dpsGo == true
end

---@param veh number
---@param go boolean
local function setGo(veh, go)
    Entity(veh).state:set('dpsGo', go, true)
end

---Which start sequence this aircraft gets.
---@param veh number
---@return string 'heli'|'heli_twin'|'airliner'|'jet'|'turboprop'|'piston'
local function spoolKind(veh)
    local model = GetEntityModel(veh)
    if GetVehicleClass(veh) == 15 then return TWIN[model] and 'heli_twin' or 'heli' end
    if AIRLINER[model] then return 'airliner' end
    if JET[model] then return 'jet' end
    if TURBOPROP[model] then return 'turboprop' end
    return 'piston'
end

---Build the timed stage list for a kind: real seconds x timeScale, with a
---per-model total override stretched across the stages proportionally.
---@param veh number
---@param kind string
---@return table stages { {label, engineOn, from, to} ... }, number total
local function buildStages(veh, kind)
    local seq = Config.startSequence[kind] or Config.startSequence.piston
    local real = 0
    for _, s in ipairs(seq) do real = real + s.seconds end
    local total = (SPIN_MODEL[GetEntityModel(veh)] or real) * (Config.timeScale or 1.0)
    local stages, t = {}, 0
    for _, s in ipairs(seq) do
        local len = total * (s.seconds / real)
        stages[#stages + 1] = { label = s.label, engineOn = s.engineOn == true, rotor = s.rotor == true, from = t, to = t + len }
        t = t + len
    end
    return stages, total
end

---@param veh number
---@return boolean
local function engineDead(veh)
    return GetVehicleEngineHealth(veh) <= (Config.deadHealth or 100)
end

---Why this aircraft cannot start right now, or nil if it can.
---@param veh number
---@return string?
local function noGoReason(veh)
    if engineDead(veh) then return 'ENGINE SEIZED - NEEDS REPAIR' end
    if (GetVehicleFuelLevel(veh) or 0) <= (Config.minFuel or 1.0) then return 'NO FUEL' end
    return nil
end

local function showText(text, style)
    lib.showTextUI(text, style)
    textShown = true
end

local function hideText()
    if textShown then
        lib.hideTextUI()
        textShown = false
    end
end

---@param veh number
---@return boolean
local function isOurAircraft(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    return Config.classes[GetVehicleClass(veh)] == true
end

---Is the local player the one flying it (not a passenger)?
---@return number? veh
local function pilotedAircraft()
    local ped = cache.ped or PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not isOurAircraft(veh) then return nil end
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return veh
end

local function anyFlyInput()
    for i = 1, #FLY_INPUTS do
        if IsControlPressed(0, FLY_INPUTS[i]) then return true end
    end
    return false
end

-- ===========================================================================
-- Engine keep-alive
-- ===========================================================================
--
-- In GTA, holding the throttle down past idle on a plane shuts the engine off,
-- which is why easing off on approach killed it (Damon, 2026-09-22). We keep it
-- running whenever the aircraft is flying or rolling, and only allow a shutdown
-- once it is stopped on the ground - at which point /ashutdown does it
-- deliberately, the way a pilot would.
local shutdownRequested = false

CreateThread(function()
    while true do
        local wait = KEEPALIVE_TICK
        local veh = pilotedAircraft()

        if veh and Config.keepEngineAlive then
            local speed = GetEntitySpeed(veh)
            local onGround = not IsEntityInAir(veh)
            local stopped = onGround and speed < Config.stoppedSpeed

            if shutdownRequested and stopped then
                -- Honour the pilot's own shutdown and stop nursing the engine.
                SetVehicleEngineOn(veh, false, true, true)
            elseif not GetIsVehicleEngineRunning(veh)
                and not engineDead(veh)                         -- a seized engine stays dead
                and (GetVehicleFuelLevel(veh) or 0) > (Config.minFuel or 1.0) -- DPS 2026-10-29: out of fuel stays out (MS FlightSim cuts it on purpose)
                and not EXEMPT[GetEntityModel(veh)]                 -- DPS 2026-10-29: MS aircraft are MS-owned
                and (isGo(veh) or (spool and spool.engineOn)) then -- before the engine stage it is OFF on purpose
                -- Relight it: this is the throttle-down cut, not a pilot choice.
                SetVehicleEngineOn(veh, true, true, false)
            end
        else
            shutdownRequested = false
            wait = 500
        end

        Wait(wait)
    end
end)

RegisterCommand('ashutdown', function()
    local veh = pilotedAircraft()
    if not veh then
        lib.notify({ description = 'Not flying anything.', type = 'error' })
        return
    end
    if IsEntityInAir(veh) or GetEntitySpeed(veh) >= Config.stoppedSpeed then
        lib.notify({ description = 'Come to a stop on the ground first.', type = 'error' })
        return
    end
    shutdownRequested = true
    -- Cold again: the next start spools from scratch.
    setGo(veh, false)
    SetVehicleUndriveable(veh, false)
    spool = nil
    hideText()
    lib.notify({ description = 'Engine shutdown.', type = 'inform' })
end, false)

---No city pilot licence for this aircraft? Returns the NO GO reason, or nil.
---@param veh number
---@return string|nil
local function licenceReason(veh)
    local L = Config.licences
    if not L or not L.enabled then return nil end
    local data = exports.qbx_core:GetPlayerData() or {}
    local job = data.job
    if job and L.exemptJobTypes[job.type] then return nil end
    local have = data.metadata and data.metadata.licences or {}
    local heli = GetVehicleClass(veh) == 15
    for _, id in ipairs(heli and L.heli or L.plane) do
        if have[id] == true then return nil end
    end
    return heli and 'NO HELICOPTER LICENCE' or 'NO PILOT LICENCE'
end

---Begin the start sequence on the aircraft I am flying. Shared by /astart,
---the preflight thread (auto-start on entering a cold aircraft) and the
---export dps-airlines' copilot checklist calls.
---@return boolean started
local function startPreflight()
    local veh = pilotedAircraft()
    if not veh then return false end
    if EXEMPT[GetEntityModel(veh)] then
        setGo(veh, true)
        SetVehicleEngineOn(veh, true, false, true)
        return true
    end
    local why = licenceReason(veh) or noGoReason(veh)
    if why then
        showText(('NO GO - %s'):format(why), Config.textStyle.nogo)
        lib.notify({ description = why:sub(1, 1) .. why:sub(2):lower(), type = 'error' })
        return false
    end
    shutdownRequested = false
    local kind = spoolKind(veh)
    local stages, total = buildStages(veh, kind)
    spool = { veh = veh, startedAt = GetGameTimer(), kind = kind, stages = stages, seconds = total, engineOn = false }
    -- Nothing turns until the sequence reaches its engine stage. Undriveable
    -- means the game will not auto-start the engine on a throttle press, so
    -- there is no start-then-cut flicker - the throttle just does nothing yet.
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    if kind == 'heli' or kind == 'heli_twin' then
        -- The rotor engages before GO, so hold the collective down until then:
        -- a per-frame guard that lives exactly as long as this spool does.
        CreateThread(function()
            while spool and spool.veh == veh do
                -- 87 is INPUT_VEH_FLY_THROTTLE_UP - the actual lift input.
                -- 71 is the car accelerate input and did nothing here.
                DisableControlAction(0, 87, true)
                DisableControlAction(0, 71, true)
                Wait(0)
            end
        end)
    end
    return true
end

RegisterCommand('astart', function()
    local veh = pilotedAircraft()
    if not veh then return end
    if isGo(veh) then
        shutdownRequested = false
        SetVehicleEngineOn(veh, true, false, true)
        lib.notify({ description = 'Engines already running.', type = 'inform' })
        return
    end
    if startPreflight() then
        lib.notify({ description = 'Engine start.', type = 'success' })
    end
end, false)

exports('startPreflight', startPreflight)

---'cold' | 'nogo' | 'spooling' | 'go' | nil when not flying anything.
exports('preflightStatus', function()
    local veh = pilotedAircraft()
    if not veh then return nil end
    if isGo(veh) then return 'go' end
    if spool and spool.veh == veh then return 'spooling' end
    if noGoReason(veh) then return 'nogo' end
    return 'cold'
end)

-- ===========================================================================
-- Taxi assist
-- ===========================================================================
--
-- Two jobs: stop aircraft creeping across the apron with the throttle at
-- neutral, and hold a walking-pace taxi unless the pilot is plainly going
-- flying. Full throttle held for a moment releases it, so it never gets between
-- you and the runway.
CreateThread(function()
    while true do
        local wait = TAXI_TICK
        local veh = pilotedAircraft()

        -- Planes only: helicopters do not taxi, and while cold their engine is
        -- simply off, which is all the holding they need.
        if veh and Config.taxiAssist and GetVehicleClass(veh) == 16 and not IsEntityInAir(veh) then
            local throttleUp = IsControlPressed(0, 71)
            local throttleDown = IsControlPressed(0, 72)
            local speed = GetEntitySpeed(veh)

            if throttleUp then
                fullThrottleSince = fullThrottleSince or GetGameTimer()
                if GetGameTimer() - fullThrottleSince >= Config.takeoffHold then
                    takeoffMode = true
                end
            else
                fullThrottleSince = nil
                if speed < Config.stoppedSpeed then takeoffMode = false end
            end

            -- Not GO yet: full throttle never releases the taxi limit. This is
            -- the preflight gate for planes - you can taxi, you cannot fly.
            if not isGo(veh) then
                takeoffMode = false
                fullThrottleSince = nil
            end

            if not takeoffMode then
                if speed > Config.taxiSpeed then
                    -- Ease it back to taxi speed rather than slamming the brakes.
                    SetVehicleBrake(veh, true)
                elseif not throttleUp and not throttleDown and speed < 1.0 then
                    -- Hold it still on the apron instead of drifting.
                    SetVehicleBrake(veh, true)
                else
                    SetVehicleBrake(veh, false)
                end
            else
                SetVehicleBrake(veh, false)
            end
        else
            takeoffMode = false
            fullThrottleSince = nil
            wait = 400
        end

        Wait(wait)
    end
end)

-- ===========================================================================
-- Preflight: spool-up and master alarm
-- ===========================================================================
--
-- Replaces the dead BigDaddy Preflight (closed C#, licence server gone). Engines
-- take real time to come up: a plane idles and taxis while it spools but the
-- taxi limit will not release for takeoff until GO; a helicopter's rotors stay
-- down until GO. Fuel and a seized engine are NO GO. The master alarm sounds
-- once when engine health falls to the alarm line, and below the dead line the
-- keep-alive stops relighting it - a wrecked engine quits, and stays quit.
--
-- Only runs while I am in a pilot seat; idles at half a second otherwise.
local function masterAlarm(veh)
    alarmed[veh] = true
    showText('MASTER CAUTION - ENGINE', Config.textStyle.alarm)
    CreateThread(function()
        for _ = 1, Config.alarmBeeps or 4 do
            PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
            Wait(450)
        end
        Wait(Config.alarmShowMs or 5000)
        -- Only clear our own line; a spool line may have replaced it already.
        if textShown and not spool then hideText() end
    end)
end

local coldVeh = nil -- the cold aircraft I am sitting in, held un-startable until the throttle asks

CreateThread(function()
    local lastLine = nil
    while true do
        local wait = 250
        local veh = pilotedAircraft()

        if veh and Config.preflight then
            if not isGo(veh) and not (spool and spool.veh == veh) then
                if EXEMPT[GetEntityModel(veh)] then
                    setGo(veh, true)
                else
                    -- A cold aircraft stays cold until the pilot asks for it:
                    -- sitting in it does nothing, the throttle starts the
                    -- sequence (Damon, 2026-09-24). Un-startable meanwhile, so
                    -- the game cannot auto-start the engine on that same press.
                    if coldVeh ~= veh then
                        SetVehicleEngineOn(veh, false, true, true)
                        SetVehicleUndriveable(veh, true)
                        coldVeh = veh
                    end
                    if IsControlPressed(0, 87) or IsControlPressed(0, 71) then
                        coldVeh = nil
                        if not startPreflight() then wait = 1500 end
                    elseif lastLine ~= 'cold' then
                        showText('COLD  -  THROTTLE TO START', Config.textStyle.cold)
                        lastLine = 'cold'
                    end
                end
            end

            if spool and spool.veh == veh then
                local elapsed = (GetGameTimer() - spool.startedAt) / 1000
                local remaining = spool.seconds - elapsed

                -- Walk the start sequence. The engine lights at the stage that
                -- says so and stays lit from there; before it, it stays off.
                local label, current = 'STARTING', nil
                for _, stage in ipairs(spool.stages) do
                    if elapsed >= stage.from then
                        label = stage.label
                        current = stage
                        if stage.engineOn then spool.engineOn = true end
                        if stage.rotor then spool.rotorFrom, spool.rotorTo = stage.from, stage.to end
                    end
                end
                local running = GetIsVehicleEngineRunning(veh)
                if spool.engineOn then
                    if not spool.driveable then
                        SetVehicleUndriveable(veh, false) -- the engine stage: it may run now
                        spool.driveable = true
                    end
                    if not running and not engineDead(veh) then
                        SetVehicleEngineOn(veh, true, false, true)
                    end
                elseif running then
                    SetVehicleEngineOn(veh, false, true, true)
                end
                -- Wind the rotor up across the engage stage instead of letting
                -- the game snap it to speed; hold it at full through the checks.
                if Config.driveRotor and spool.rotorFrom and running then
                    local p = (elapsed - spool.rotorFrom) / math.max(1, spool.rotorTo - spool.rotorFrom)
                    SetHeliBladesSpeed(veh, math.min(1.0, math.max(0.05, p)))
                end

                if remaining > 0 then
                    local r = math.ceil(remaining)
                    local line = r >= 60
                        and ('%s  %d:%02d'):format(label, r // 60, r % 60)
                        or  ('%s  %ds'):format(label, r)
                    if line ~= lastLine then
                        showText(line, Config.textStyle.spool)
                        lastLine = line
                    end
                else
                    setGo(veh, true)
                    if not engineDead(veh) then SetVehicleEngineOn(veh, true, false, true) end
                    if Config.driveRotor and spool.rotorFrom then SetHeliBladesFullSpeed(veh) end
                    spool = nil
                    lastLine = nil
                    showText('GO', Config.textStyle.go)
                    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
                    SetTimeout(Config.goShowMs or 2500, function()
                        if textShown and not spool and not alarmed[veh] then hideText() end
                    end)
                end
            end

            -- Master alarm: once per event, re-armed when the engine recovers.
            local h = GetVehicleEngineHealth(veh)
            if h <= (Config.alarmHealth or 350) and not alarmed[veh] then
                masterAlarm(veh)
            elseif h > (Config.alarmHealth or 350) + 100 and alarmed[veh] then
                alarmed[veh] = nil
            end
        else
            -- Left the seat: never leave an aircraft un-startable behind.
            if spool then
                if DoesEntityExist(spool.veh) then SetVehicleUndriveable(spool.veh, false) end
                spool = nil
            end
            if coldVeh then
                if DoesEntityExist(coldVeh) then SetVehicleUndriveable(coldVeh, false) end
                coldVeh = nil
            end
            lastLine = nil
            hideText()
            wait = 500
        end

        Wait(wait)
    end
end)

-- A resource restart mid-sequence must not leave the aircraft un-startable.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if spool and DoesEntityExist(spool.veh) then SetVehicleUndriveable(spool.veh, false) end
    if coldVeh and DoesEntityExist(coldVeh) then SetVehicleUndriveable(coldVeh, false) end
    if textShown then lib.hideTextUI() end
end)

-- Instruments are deliberately NOT drawn here: jg-hud already gives speed and
-- altitude, and two readouts on screen is worse than one (Damon, 2026-09-22).
-- The only text this draws is the one-line spool / GO / NO GO / alarm status.

print('[dps-aviation] loaded - engine keep-alive, taxi assist, preflight spool-up, master alarm')
