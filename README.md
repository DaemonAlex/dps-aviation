# dps-aviation

Flight behaviour for Del Perro Sands: aircraft idle instead of cutting out, taxi at a sane speed, and every aircraft has a real start sequence before it will fly.

Client-only. Depends on `ox_lib`. No database, no server script.

## What it does

**Idle and taxi (Phase 1)**
- Rolling off the throttle no longer kills the engine; planes idle.
- Taxi assist holds a low ground speed on planes until full throttle is held. Helicopters are exempt.
- Basic instruments text (planes).

**Preflight / start sequence (Phase 2)**
- A freshly entered aircraft is **cold**: undriveable, engine off, "COLD - THROTTLE TO START". Sitting in it does nothing.
- The first throttle input (keyboard or pad, control 87 for helicopters / 71 for planes) starts the sequence for that aircraft's kind. Stages walk with a text banner; the engine comes on at the stage the config marks `engineOn`; the last stage sets **GO**.
- GO is a replicated entity state bag (`dpsGo`) on the aircraft, so it follows the airframe, not the pilot.
- A master alarm sounds/flashes when engine health drops under `Config.alarmHealth`; under `Config.deadHealth` the aircraft is dead.
- `/astart` starts the sequence by hand, `/ashutdown` shuts down.

**Kinds** (`Config.startSequence`): `piston`, `turboprop`, `jet`, `airliner`, `heli`, `heli_twin`. A model is a jet if it is in `Config.jetModels`, an airliner if in `Config.airlinerModels`, a turboprop if in `Config.turbopropModels`, a twin heli if in `Config.twinHelis`; helicopters are detected by class; everything else is piston. `Config.spinupModel` overrides the rotor time per model. `Config.timeScale` scales every stage (0.6 = 60% of the listed seconds). `Config.preflightExempt` lists models that never go cold (the RC drone).

Stage times were tuned in game on 2026-09-24: a single heli takes about a minute to GO, a twin about two and a half; airliners are long on purpose.

## Exports (client)

```lua
exports['dps-aviation']:startPreflight()      -- start the sequence on the aircraft the player is in (no-op if already running / GO)
exports['dps-aviation']:preflightStatus()     -- 'cold' | 'spool' | 'go' | 'nogo' | 'alarm' | nil when not in an aircraft
```

`dps-airlines` calls `startPreflight` for the pilot once the copilot's preflight checklist is complete.

## Config

Everything is in `config.lua`: kinds and stage timings, model lists, `minFuel`, alarm thresholds, text styles, `Config.classes` (which vehicle classes are aircraft: 15 helicopters, 16 planes), `Config.driveRotor` (leave `false` — driving the rotor speed by script made helicopters uncontrollable).

## Known limits

- Handling stability (climb rate, mass) belongs in the vehicle packs' `handling.meta`, not here.
- The sequence is per client; a passenger cannot start a pilot's aircraft.
- Engine sounds are the packs' business (many addon planes ship the wrong bank).

## Install

Drop in `[dps]`, make sure `ox_lib` starts first. No config edits needed to run; add new models to the kind lists as packs arrive.
