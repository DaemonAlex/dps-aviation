# dps-aviation

Flight behaviour for Del Perro Sands: aircraft idle instead of cutting out, taxi at a sane speed, and every aircraft has a real start sequence before it will fly.

Client-only. Depends on `ox_lib`. No database, no server script.

## Status

Not running on DelPerroSands. It was in the server's resource list on 1 November 2026 and is not
on the server now. The server's aircraft packs and flight sim were removed on 8 November 2026.
The code is complete. No other DPS script replaces it.

## What it is for

In stock GTA a plane's engine shuts off when you ease off the throttle, aircraft creep across the
apron, and every aircraft starts the moment you sit in it. This script fixes those three things.
Engines idle, planes taxi at a steady walking pace, and each aircraft has a timed start sequence
before it will fly.

## On its own, and with other scripts

**On its own.** You sit in a cold aircraft and nothing happens until you touch the throttle. A
one-line banner then walks through the start stages for that kind of aircraft. A small helicopter
is ready in about a minute. An airliner takes about five. When the banner says GO you can take
off. An aircraft that is already warm stays warm when the crew swaps. An aircraft with no fuel, or
with a wrecked engine, will not start. The script reads the game's own fuel level, so it works
with any fuel script that sets it (ox_fuel does). It needs only `ox_lib`.

**With [dps-airlines](https://github.com/DaemonAlex/dps-airlines).** When the co-pilot finishes
the preflight checklist, the airline job starts this start sequence for the captain. Without
dps-airlines the captain starts it by hand with the throttle or `/astart`.

**With a paid HUD (jg-hud).** This script draws no speed or altitude readout, because the HUD
already shows them. There is no code link between the two.

## What it does

**Idle and taxi (Phase 1)**
- Rolling off the throttle no longer kills the engine; planes idle.
- Taxi assist holds a low ground speed on planes until full throttle is held. Helicopters are exempt.
- No instruments are drawn. The HUD already shows speed and altitude.

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

Everything is in `config.lua`: kinds and stage timings, model lists, `minFuel`, alarm thresholds, text styles, `Config.classes` (which vehicle classes are aircraft: 15 helicopters, 16 planes), `Config.driveRotor` (leave `false`: driving the rotor speed by script made helicopters uncontrollable).

## Known limits

- Handling stability (climb rate, mass) belongs in the vehicle packs' `handling.meta`, not here.
- The sequence is per client; a passenger cannot start a pilot's aircraft.
- Engine sounds are the packs' business (many addon planes ship the wrong bank).

## Install

Drop in `[dps]`, make sure `ox_lib` starts first. No config edits needed to run; add new models to the kind lists as packs arrive.

## Recent changes

- **12 November 2026.** README: status, what it is for, how it works alone and with paid scripts, other DPS scripts.
- **24 September 2026.** Idle and taxi behaviour, and the preflight start sequence. Stage times
  tuned in game. Driving the rotor speed by script was switched off after it made a helicopter
  uncontrollable.

## Author

Made by [DaemonAlex](https://github.com/DaemonAlex) for DelPerroSands.

## Other DPS scripts

All of these are made for DelPerroSands and run together on one Qbox server. Each one works on
its own. The ones marked "pairs with" do more when both are running.

| Script | What it does |
|---|---|
| [dps-inventory](https://github.com/DaemonAlex/dps-inventory) | The inventory: ox_inventory with equipment slots, backpacks, armour plates and a self status panel, in the DelPerroSands colours. |
| [dps-medical](https://github.com/DaemonAlex/dps-medical) | Patient records, illness and diagnostic tests. A companion to wasabi_ambulance. Pairs with dps-inventory: symptoms and diagnoses show on the status panel. |
| [dps-insurance](https://github.com/DaemonAlex/dps-insurance) | Ties m-Insurance into the MDT, impound, hospital and medical chart. Pairs with dps-medical. |
| [dps-studio](https://github.com/DaemonAlex/dps-studio) | Build rooms, doors and portals in game from one panel (`/studio`), with owners and managers so staff do not have to support them. |
| [dps-shops](https://github.com/DaemonAlex/dps-shops) | Shop clerks who greet and react to a robbery, then player-owned shops. |
| [dps-fleet](https://github.com/DaemonAlex/dps-fleet) | Vehicle browser and workshop on one panel: extras, liveries and mods for emergency vehicles. |
| [dps-parking](https://github.com/DaemonAlex/dps-parking) | Parking with valet, impound, violations and reserved spots. |
| [dps-vehiclepersistence](https://github.com/DaemonAlex/dps-vehiclepersistence) | Vehicles stay where they were parked. Pairs with dps-parking. |
| [dps-towjob](https://github.com/DaemonAlex/dps-towjob) | Queue-based tow job with jg-mechanic integration. |
| [dps-services](https://github.com/DaemonAlex/dps-services) | Request a tow and follow it live on the lb-phone and lb-tablet. Pairs with dps-towjob. |
| [dps-autoshops](https://github.com/DaemonAlex/dps-autoshops) | Self-service repair shops when no mechanic is on duty. |
| [dps-cityworker](https://github.com/DaemonAlex/dps-cityworker) | City infrastructure job and career. |
| [dps-ainpcs](https://github.com/DaemonAlex/dps-ainpcs) | NPCs you can talk to, with trust, quests and intel. |
| [dps-badpeds](https://github.com/DaemonAlex/dps-badpeds) | Police interaction with NPCs: stops, arrests, intel and jail records. |
| [dps-gangwars](https://github.com/DaemonAlex/dps-gangwars) | Ambient gang NPCs, territory population and war reinforcements. |
| [dps-rotations](https://github.com/DaemonAlex/dps-rotations) | Moves dealers, harvests and other spots on a fixed schedule. |
| [dps-trains](https://github.com/DaemonAlex/dps-trains) | The train system. Pairs with dps-trains-stock, dps-traintools and dps-transitapp. |
| [dps-transitapp](https://github.com/DaemonAlex/dps-transitapp) | Live train arrival boards on the lb-phone. |
| [dps-faceplant](https://github.com/DaemonAlex/dps-faceplant) | City help, reports and staff tools on the lb-phone and lb-tablet. |
| [dps-chat](https://github.com/DaemonAlex/dps-chat) | A command box for voice-only servers. No chat feed. |
| [dps-filmmode](https://github.com/DaemonAlex/dps-filmmode) | One key hides every HUD layer and gives a smooth free camera for recording. |
