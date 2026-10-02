# Factorio modding plan: Portal Guns

Written with the `game-recon` step of [universal-modder](https://github.com/rehan-remade/universal-modder)
(`mod-any-game` loop). The journal with every fact and dead end is in [`MODLOG.md`](MODLOG.md).

- **Idea (one sentence):** a handheld portal gun for Factorio 2.0: left click shoots a blue portal, right click
  an orange one, and anything that walks or drives into one comes out of the other (players, cars and tanks
  with their speed, spidertrons, biters).
- **Done means:** the mod loads in Factorio 2.0 with and without Space Age, the portal logic passes scripted
  tests in the real game engine (headless server), and the package is ready to drop into `mods/`.

## Game
- **Install used for testing:** Factorio headless server **2.0.77** (build 84539, linux64), the current stable.
  `factorio.com` is blocked in this sandbox, so it was taken from the community Docker image
  `factoriotools/factorio:stable` (layer digest verified, binary only, kept outside the repo).
- **Engine:** Wube's own C++ engine. Mods are Lua 5.2 (Factorio fork), sandboxed and deterministic.
  `um scan` → "Unknown native engine", known-game route "official Lua modding API".
- **Anti-cheat / online:** none. Mods are an official feature; multiplayer is lockstep, so every mod must be
  deterministic (no local state in `control.lua` outside `storage`).
- **Saves / logs:** `<write-data>/saves`, `<write-data>/factorio-current.log`; script `print()` goes to stdout,
  `log()` to the log file (and stdout on the headless server).

## Community route
- Official modding API: `info.json`, `settings.lua`, `data.lua` (prototypes), `control.lua` (runtime events),
  `locale/<lang>/*.cfg`. Docs: lua-api.factorio.com (blocked here); the same documentation ships in the npm
  package `typed-factorio@3.36.0` (`factorio-2.0` dist-tag, generated from the 2.0.75 JSON docs). The base
  game's own prototypes are in the server's `data/` folder.
- **Prior art:** Bilka's [Portals](https://mods.factorio.com/mods/Bilka/Portals) (0.16-1.1) and its 2.0 port
  "Portals chaosfork": the portal gun *builds* portals (left click / shift+left click) and teleports players only.
  This mod differs: real shots with projectiles, Portal-style controls, per-player pairs, vehicles keep their
  speed, biters and spidertrons go through, optional cross-surface links.

## Chosen route for "portal guns"
**Loader API = the official Lua modding API.** No lower route is needed or allowed.
- The gun is a `selection-tool` item: `select` (LMB) = blue, `reverse_select` (RMB) = orange,
  `alt_select` / `alt_reverse_select` (Shift) close that colour. That is exactly Portal's control scheme with
  no keybinding conflicts (a capsule would need a toggle key, a gun+ammo is fired with `C` only).
- Shots: a visual projectile entity + a deterministic arrival timer in `storage`; on arrival the portal opens.
- Portals: `simple-entity-with-owner` (collision layer `object` + water/lava/void tiles, so nothing can be
  built on them and they can't be shot onto water, buildings, trees or cliffs; characters, cars and units don't
  collide with that mask). Visuals via `rendering.draw_animation` + `draw_light` attached to the entity.
- Teleport: every tick, for each *linked* pair, `find_entities_filtered{position, radius, type}`; entities that
  newly entered a portal go to the partner; occupancy sets stop ping-pong.

## Lab plan
- Headless server in `<factorio>` (a folder outside the repo), lab mod folder with its own `mod-list.json`.
- Oracle 1 (data stage): `--create` a map with the mod; any prototype error aborts with a message.
- Oracle 2 (runtime): a test-harness mod drives the remote interface in `--benchmark` mode and prints
  `PASS`/`FAIL` lines; run with base only and with Space Age + Quality + Elevated Rails.
- Oracle 3 (assets): headless builds ship no graphics/sounds and never load them, so `--dump-data` + a script
  checks that every `__portal-guns__/` file exists and every sheet matches its declared frame grid.
- No saves of the user are touched; all tests use throwaway maps.

## Unknowns to resolve first
- Does a zero-area click with a selection tool raise the selected-area events? (Yes in practice for planners;
  handled by using the area centre.) Can't be tested headless: no players exist on a dedicated server.
- Does `teleport()` keep a car's speed? (Set it back explicitly after teleporting.)
- Which entity types can teleport cross-surface? Docs: characters, cars, spidertrons only.
