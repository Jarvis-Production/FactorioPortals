# MODLOG: Portal Guns for Factorio 2.0

Journal kept per the universal-modder `mod-any-game` loop. Newest entries at the bottom of each section.

## Environment (2026-10-02)
- Cloud Linux container, no GPU, no display, no Factorio client. Python 3.11, uv, ffmpeg, node 22.
- Network policy blocks `factorio.com`, `lua-api.factorio.com`, `mods.factorio.com`, `wiki.factorio.com`.
  Reachable: Docker Hub (+ cloudfront blobs), npm, PyPI, GitHub raw/git.
- No `FAL_KEY` → no fal assets; all art and audio is generated procedurally (see `tools/gen_assets.py`).

## Versions
- Factorio headless **2.0.77** (build 84539, linux64): Docker Hub `factoriotools/factorio:stable`
  (= `stable-2.0.77`), amd64 layer `sha256:040058c9…e675` (89.6 MB), sha256 verified after download, only
  `opt/factorio` extracted to `<factorio>`, outside the repo. Experimental line at the time:
  2.1.20.
- API docs: npm `typed-factorio@3.36.0` (dist-tag `factorio-2.0`), docs generated from 2.0.75 JSON.
- universal-modder skill repo @ `15d6f9d` (v0.2). `um kb search factorio` → no prior notes.

## Recon facts
- `um scan <factorio>` → engine unknown native (10%), no anti-cheat, known-game route
  "official Lua modding API (mods/ folder, data.lua + control.lua)".
- Headless build ships **no PNG/OGG at all** (0 files under `data/`): sprites and sounds are never loaded, so
  wrong file paths or sheet sizes are NOT caught by the server. Needs its own asset oracle.
- `--create map.zip` runs the data stage + `on_init`; `--benchmark map.zip --benchmark-ticks N` runs N
  ticks with mod scripts; Lua `print()` reaches stdout. A dedicated server has **0 players**, so player
  events can't be raised; logic must be reachable without a LuaPlayer (remote interface + owner ids).
- Selection tools (2.0): `select` = LMB, `alt_select` = Shift+LMB, `reverse_select` = RMB,
  `alt_reverse_select` = Shift+RMB (doc string on `alt_reverse_select`; base upgrade planner uses
  `reverse_select` for downgrade). Events: `on_player_selected_area`, `on_player_alt_selected_area`,
  `on_player_reverse_selected_area`, `on_player_alt_reverse_selected_area` with `area`, `surface`, `item`.
- `MouseCursor` prototype can use `system_cursor = "crosshair"` (commented example in core `cursors.lua`).
- `ThrowCapsuleAction.uses_stack = false` exists (rejected alternative: no right-click action for capsules).
- `LuaControl.teleport(position, surface?, raise?, snap?, build_check_type?)`: cross-surface only for
  characters (players), cars and spidertrons. Default build check `script`.
- `find_entities_filtered{position, radius}` looks at entity **centres** within the radius.
- `LuaEntity.speed` is writable for cars, units, projectiles; read-only for spidertrons.
- 2.0 `defines.direction` has 16 values (north=0 … northnorthwest=15); orientation 0 = north, clockwise.
- Default collision masks (core `collision-mask-defaults.lua`): character `{player, train, is_object}`,
  car `{player, car, train, is_object}`, unit `{player, train, is_object}`, spider-vehicle/spider-unit
  `{trigger_target}`; buildings/trees/rocks/cliffs/belts all include `object`. So a portal with mask
  `{object, water_tile, lava_tile, empty_space, out_of_map}` blocks building on it but not walking over it.
- Base laser projectile sprite is 12x33 (points north); projectiles are rotated to the travel direction.
- Shortcut icons in base: 56x56 `icon` + 24x24 `small_icon`.
- `rendering.draw_animation` accepts `animation_speed`, `animation_offset`, `x_scale`, `y_scale`, `tint`,
  `render_layer`, `target` (entity → object follows and dies with it). `LuaRenderObject.color` is the tint.

## Decisions
- Route: official Lua API. Gun = `selection-tool`; portals = `simple-entity-with-owner` + rendering.
- Shots: visual projectile (constant speed, no collision box so it can't hit anything en route) + arrival
  tick computed as `ceil(distance / speed)` stored in `storage.shots`. Deterministic and testable.
- Re-shooting a colour *moves* the existing portal with `teleport()` (its own build check excludes itself),
  so a blocked shot fizzles and leaves the old portal where it was.
- Exits keep the absolute heading ("speedy thing goes in, speedy thing comes out"): cars keep speed and
  orientation; characters keep walking because the player still holds the key.

## Log
- **Probe run 1 (headless 2.0.77, probe mod).** `can_place_entity` for a simple-entity-with-owner with mask
  `{object, water_tile, …}`: wall → false, water → false, overlapping itself → false, free → true; a
  character can stand on it (true). **`teleport()` of that simple entity does no build check at all**:
  onto a wall → true, onto water → true. So "move the old portal with teleport and let it fail" is wrong;
  placement must be validated before moving.
- Car: same-surface `teleport` keeps `speed` (0.298 → 0.298) and orientation. **Cross-surface teleport
  resets car speed to 0** → restore it after the jump.
- `teleport(pos, other_surface)` on a biter **throws** ("Surface teleport can only be done for players,
  characters, cars, and spidertrons at the moment.") instead of returning false → guard by type.
- `find_entities_filtered{type = {..., "spider-unit"}}` is fine without Space Age (type names are engine-level).
- Player-less characters walk when `walking_state` is set (0.148 tiles/tick) and keep walking afterwards;
  they walk straight over the portal entity (no collision). Biters with `go_to_location` face their travel
  direction: `orientation` ≈ 0.25 while walking east. Spidertron same-surface teleport works.
- Design change: portals get collision layers `{item, transport_belt}` (blocks buildings, rails, belts, trees
  and dropped items, but not characters/cars/units/spiders); validity is checked with a hidden probe prototype
  (`{object, water_tile, lava_tile, empty_space, out_of_map}`) that shares no layer with portals, so the old
  portal never blocks its own re-placement; portal-vs-portal overlap is checked in script.
- **First full mod load (2.0.77):** data stage + `on_init` clean with base only and with Space Age +
  Quality + Elevated Rails. `--dump-data` writes `<write-data>/script-output/data-raw-dump.json`; with
  Space Age the Quality mod adds a recycling recipe that also references the gun icon (39 vs 38 refs).
- **Asset oracle** (`tools/check_assets.py` on the dump): 38/39 references, 0 problems. Mutation check:
  wrong frame_count, missing sound file, wrong small_icon_size → all three reported, exit 1.
- **Test harness run 1:** 16/20 PASS. Two real findings:
  1. `settings.global[...] = {value = ...}` from another mod fails: "Settings can only be changed by the
     owning player or the mod that made the setting." → the mod exposes `remote.call("portal-guns",
     "set_setting", name, value)`; tests and scenarios go through it.
  2. After teleporting a car, a player-less **driver's position still reads the old spot on that same tick**;
     two ticks later it is inside the car at the exit (and `get_driver()` is unchanged). Cross-surface the
     driver comes along too. Tests now check after 2 ticks.
- **Run 2:** 20/20 on both mod sets. Mutation check: dropping the "arrivals are occupants" line → 9 tests
  fail (ping-pong); dropping the cross-surface speed restore → the cross-surface test fails (speed 0.000).
- Added: save/load test (portals opened in the test mod's `on_init` during `--create`, used after the
  benchmark loads the map), range-clamp + cooldown test via remote `shoot`, sleeping-portal tests.
- **Performance** (headless, 3600 ticks, 100 linked pairs = 200 portals): first version scanned every
  linked portal every tick: +0.8-1.0 ms/tick. `find_entities_filtered{position, radius 0.9, type = 5 types}`
  alone is ~1.4-1.5 µs per call (LuaProfiler, 20k calls); a wide `count_entities_filtered{radius 16, limit 1}`
  is ~2 µs. Added sleep/wake: a portal re-checks a 16-tile radius every 10 ticks and only scans per tick while
  something could reach it. Result: idle 100 pairs +0.08 ms/tick (0.5 % of a tick), busy (character at every
  blue portal) +0.7-0.8 ms/tick. Benchmarks on this VM vary by ±0.1 ms between runs.
- Final: 24/24 tests on base and on Space Age.
- Locale: `helpers.check_prototype_translations()` reports untranslated prototypes in the log (proven with a
  deliberately untranslated probe item); clean for `en` and for `locale=ru` (set in `config/config.ini`,
  restored afterwards). EN and RU cfg files have the same 29 keys. RU uses the game's own terms (кусака,
  плевака, паукотрон, стальная балка, режим дополнительной информации).
- Packaging: `tools/build.py` → `dist/portal-guns_1.0.0.zip` (41 files, ~1.3 MB); the server loads the zip.
  `um publish check` on the mod and on the whole repo: PASS, 0 failures, 0 warnings (after replacing absolute
  paths in the journals with `<factorio>` and adding READMEs). Field note `docs/field-note.md`: `um kb check` PASS.
- Not done: showcase video (no renderer, no client), publishing to the mod portal (the user's call), opening a
  PR with the field note to universal-modder (needs the human's OK).

## fal art pass (2026-10-02, second session)
- `fal.run`, `queue.fal.run`, `v3.fal.media` reachable after a network-policy change (bare `fal.media` 502s, unused).
- Added `tools/gen_fal_assets.py` (`generate` via `um fal`, `build` offline from `assets/fal/`, `preview`);
  `tools/gen_assets.py` now calls the fal build after the procedural steps (no-op without raws). Without a key or
  raws the procedural output is byte-identical to before (checked with `git status` after a full rebuild).
- **Blocked:** first fal call returned `HTTP 403 User is locked. Reason: Exhausted balance.` No assets generated yet.
- A `FAL_KEY` file had been committed (`8e9eb71`); removed from the tree and gitignored. It stays in history, so the
  key must be rotated.
