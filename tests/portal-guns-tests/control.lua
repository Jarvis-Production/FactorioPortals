-- Scripted integration tests for Portal Guns. tools/run_tests.py creates a map with this mod enabled and runs
-- it on a headless server in --benchmark mode. A dedicated server has no players, so everything goes through
-- the mod's remote interface with made-up owner ids and player-less characters, cars, biters and spidertrons.
--
-- Each test is a list of steps. A step returns nil (next step on the next tick), a number (wait that many
-- ticks), or "retry" (run it again next tick, up to TIMEOUT ticks). Any error fails the test.

local MOD = "portal-guns"
local TIMEOUT = 900
local BLUE, ORANGE = "portal-guns-portal-blue", "portal-guns-portal-orange"
local SETTINGS = {
  units = "portal-guns-teleport-units",
  vehicles = "portal-guns-teleport-vehicles",
  cross = "portal-guns-cross-surface",
}

local function call(name, ...) return remote.call(MOD, name, ...) end
local function nauvis() return game.surfaces.nauvis end
local function fmt(p) return p and string.format("(%.2f, %.2f)", p.x, p.y) or "nil" end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function expect(condition, message, ...)
  if not condition then error(string.format(message, ...), 2) end
end
local function set_setting(name, value) call("set_setting", name, value) end

-- Every trip through a portal, from the mod's own custom event.
local teleports = {}
script.on_event("portal-guns-on-teleported", function(event)
  teleports[#teleports + 1] = {unit_number = event.entity.unit_number, owner = event.owner, cross = event.cross_surface}
end)
local function trips(entity)
  local n = 0
  for _, trip in pairs(teleports) do
    if trip.unit_number == entity.unit_number then n = n + 1 end
  end
  return n
end

local ctx -- per-test scratch: ctx.entities are destroyed after the test
local function spawn(name, position, force, surface)
  local entity = (surface or nauvis()).create_entity{name = name, position = position, force = force or "player"}
  assert(entity, "could not create " .. name)
  ctx.entities[#ctx.entities + 1] = entity
  return entity
end
local function open(owner, color, position, surface)
  local id, reason = call("open_portal", owner, color, surface or "nauvis", position)
  expect(id, "%s portal of %s at %s did not open: %s", color, tostring(owner), fmt({x = position[1], y = position[2]}), tostring(reason))
  return id
end
local function walk(character, direction)
  character.walking_state = {walking = direction ~= nil, direction = direction or defines.direction.north}
end
local function set_tiles(surface, name, x0, y0, x1, y1)
  local tiles = {}
  for x = x0, x1 do
    for y = y0, y1 do tiles[#tiles + 1] = {name = name, position = {x, y}} end
  end
  surface.set_tiles(tiles)
end

local tests = {}
local function test(name, steps) tests[#tests + 1] = {name = name, steps = steps} end

---------------------------------------------------------------------------------------------------- tests

test("portals opened before the map was saved still work after loading", {
  function()
    local blue, orange = call("get_portal", 2001, "blue"), call("get_portal", 2001, "orange")
    expect(blue and orange and blue.linked, "the pair made in on_init is gone or unlinked")
    expect(#rendering.get_all_objects(MOD) == 8, "%d render objects after loading", #rendering.get_all_objects(MOD))
    ctx.c = spawn("character", {96, -60})
  end,
  function()
    walk(ctx.c, defines.direction.east)
    if trips(ctx.c) == 0 then return "retry" end
    expect(dist(ctx.c.position, {x = 100.5, y = -30}) < 0.6, "came out at %s", fmt(ctx.c.position))
  end
})

test("prototypes, recipe, technology and settings exist", {function()
  local gun = prototypes.item["portal-gun"]
  expect(gun and gun.type == "selection-tool", "portal-gun should be a selection-tool")
  expect(prototypes.entity[BLUE] and prototypes.entity[ORANGE], "portal entities missing")
  expect(prototypes.entity["portal-guns-shot-blue"].type == "projectile", "shot should be a projectile")
  local tech = prototypes.technology["portal-gun"]
  expect(tech, "technology missing")
  for name in pairs(tech.prerequisites) do expect(prototypes.technology[name], "unknown prerequisite %s", name) end
  local unlocks = false
  for _, effect in pairs(tech.effects) do
    if effect.type == "unlock-recipe" and effect.recipe == "portal-gun" then unlocks = true end
  end
  expect(unlocks, "technology must unlock the recipe")
  expect(not game.forces.player.recipes["portal-gun"].enabled, "recipe should start locked")
  for _, ingredient in pairs(prototypes.recipe["portal-gun"].ingredients) do
    expect(prototypes.item[ingredient.name], "unknown ingredient %s", ingredient.name)
  end
  expect(prototypes.shortcut["portal-guns-close-portals"], "shortcut missing")
  expect(prototypes.custom_input["portal-guns-close-portals"], "custom input missing")
  expect(prototypes.custom_event["portal-guns-on-teleported"], "custom event missing")
  expect(helpers.is_valid_sound_path("portal-guns-denied"), "sound prototype missing")
  for _, name in pairs({"portal-guns-range", SETTINGS.units, SETTINGS.vehicles, SETTINGS.cross, "portal-guns-owner-labels"}) do
    expect(settings.global[name], "setting %s missing", name)
  end
  expect(call("get_event_names").on_teleported == "portal-guns-on-teleported", "remote get_event_names")
end})

test("two portals open, link, and grow to full size", {
  function()
    open(1001, "blue", {0, 0})
    local blue = call("get_portal", 1001, "blue")
    expect(not blue.linked, "a lone portal must not be linked")
    expect(dist(blue.position, {x = 0, y = 0}) < 0.01, "blue opened at %s", fmt(blue.position))
    expect(not blue.entity.destructible, "portals must be indestructible")
    open(1001, "orange", {20, 0})
    expect(call("get_portal", 1001, "blue").linked and call("get_portal", 1001, "orange").linked, "pair not linked")
    expect(#nauvis().find_entities_filtered{name = BLUE} == 1, "expected exactly one blue portal entity")
    return 20
  end,
  function()
    local objects = rendering.get_all_objects(MOD)
    expect(#objects == 8, "expected 8 render objects (body, glow, light, label x2), got %d", #objects)
    for _, object in pairs(objects) do
      if object.type == "animation" then
        expect(math.abs(object.x_scale - 1) < 1e-6, "portal still at scale %.2f after opening", object.x_scale)
        expect(math.abs(object.animation_speed - 0.33) < 1e-6, "linked portals should swirl fast")
      end
    end
  end
})

test("a shot at water fizzles and leaves the old portal alone", {function()
  local s = nauvis()
  set_tiles(s, "water", -3, 27, 3, 33)
  open(1002, "blue", {40, 30})
  local id, reason = call("open_portal", 1002, "blue", "nauvis", {0.5, 30.5})
  set_tiles(s, "grass-1", -3, 27, 3, 33)
  expect(id == nil and reason == "fizzle", "expected a fizzle, got %s / %s", tostring(id), tostring(reason))
  local blue = call("get_portal", 1002, "blue")
  expect(blue and dist(blue.position, {x = 40, y = 30}) < 0.01, "old portal moved to %s", fmt(blue and blue.position))
end})

test("a shot at a wall slides off it", {function()
  spawn("stone-wall", {60.5, 0.5})
  open(1003, "blue", {60.5, 0.5})
  local blue = call("get_portal", 1003, "blue")
  local d = dist(blue.position, {x = 60.5, y = 0.5})
  expect(d > 0.4 and d <= 2.01, "nudged %.2f tiles", d)
  expect(nauvis().can_place_entity{name = "portal-guns-placement-probe", position = blue.position}, "landed on the wall")
end})

test("portals can't overlap other portals", {function()
  open(1004, "blue", {80, 0})
  local id, reason = call("open_portal", 1004, "orange", "nauvis", {80.5, 0.5})
  expect(id == nil and reason == "too-close", "own pair: got %s / %s", tostring(id), tostring(reason))
  id, reason = call("open_portal", 1005, "blue", "nauvis", {81, 0})
  expect(id == nil and reason == "too-close", "other owner: got %s / %s", tostring(id), tostring(reason))
end})

test("re-shooting a colour moves that portal", {function()
  local first = open(1006, "blue", {0, -20})
  local second = open(1006, "blue", {10, -20})
  expect(first == second, "expected the same portal to move (%s vs %s)", first, second)
  expect(#nauvis().find_entities_filtered{name = BLUE, position = {0, -20}, radius = 1} == 0, "old spot still has a portal")
  local third = open(1006, "blue", {10.5, -20})
  expect(third == first, "a small re-aim overlapping the old spot must work")
  expect(#nauvis().find_entities_filtered{name = BLUE} == 1, "expected one blue portal")
end})

test("a character walks through and keeps walking", {
  function()
    open(1007, "blue", {0, 10})
    open(1007, "orange", {30, 10})
    ctx.c = spawn("character", {-4, 10})
    walk(ctx.c, defines.direction.east)
  end,
  function()
    walk(ctx.c, defines.direction.east)
    if ctx.c.position.x < 25 then return "retry" end
    expect(ctx.c.position.x >= 30 and ctx.c.position.x < 31.5, "came out at %s", fmt(ctx.c.position))
    expect(math.abs(ctx.c.position.y - 10) < 0.3, "came out at %s", fmt(ctx.c.position))
    return 30
  end,
  function()
    expect(ctx.c.position.x > 32, "should have walked on, is at %s", fmt(ctx.c.position))
    expect(trips(ctx.c) == 1, "expected 1 trip, got %d", trips(ctx.c))
  end
})

test("standing in the exit portal doesn't bounce you back; stepping back in does", {
  function()
    open(1008, "blue", {0, 40})
    open(1008, "orange", {30, 40})
    ctx.c = spawn("character", {-3, 40})
    walk(ctx.c, defines.direction.east)
  end,
  function()
    walk(ctx.c, defines.direction.east)
    if ctx.c.position.x < 25 then return "retry" end
    walk(ctx.c, nil)
    return 60
  end,
  function()
    expect(dist(ctx.c.position, {x = 30.5, y = 40}) < 0.6, "drifted to %s", fmt(ctx.c.position))
    expect(trips(ctx.c) == 1, "bounced: %d trips", trips(ctx.c))
    walk(ctx.c, defines.direction.west) -- out of the orange portal through its far side
  end,
  function()
    walk(ctx.c, defines.direction.west)
    if ctx.c.position.x > 28.6 then return "retry" end
    expect(trips(ctx.c) == 1, "walking out of a portal must not teleport (%d trips)", trips(ctx.c))
    walk(ctx.c, defines.direction.east) -- and back in
  end,
  function()
    walk(ctx.c, defines.direction.east)
    if ctx.c.position.x > 10 then return "retry" end
    expect(trips(ctx.c) == 2, "expected 2 trips, got %d", trips(ctx.c))
    expect(dist(ctx.c.position, {x = 0.5, y = 40}) < 0.6, "came out of blue at %s", fmt(ctx.c.position))
  end
})

test("whoever stands in a portal when the pair links stays put until stepping in", {
  function()
    open(1009, "blue", {0, 60})
    ctx.c = spawn("character", {0, 60})
    return 5
  end,
  function()
    open(1009, "orange", {30, 60})
    return 30
  end,
  function()
    expect(dist(ctx.c.position, {x = 0, y = 60}) < 0.1 and trips(ctx.c) == 0, "got pulled through")
    walk(ctx.c, defines.direction.east)
  end,
  function()
    walk(ctx.c, defines.direction.east)
    if ctx.c.position.x < 1.5 then return "retry" end
    walk(ctx.c, defines.direction.west)
  end,
  function()
    walk(ctx.c, defines.direction.west)
    if ctx.c.position.x < 20 then return "retry" end
    expect(trips(ctx.c) == 1, "expected 1 trip, got %d", trips(ctx.c))
    expect(dist(ctx.c.position, {x = 29.5, y = 60}) < 0.6, "came out at %s", fmt(ctx.c.position))
  end
})

test("a car keeps its speed and heading", {
  function()
    open(1010, "blue", {0, 80})
    open(1010, "orange", {40, 80})
    ctx.car = spawn("car", {-8, 80})
    ctx.car.orientation = 0.25
    ctx.car.speed = 0.35
  end,
  function()
    local car = ctx.car
    if car.position.x < 35 then
      ctx.last_speed = car.speed
      return "retry"
    end
    expect(math.abs(car.speed - ctx.last_speed) / ctx.last_speed < 0.03, "speed %.3f, was %.3f", car.speed, ctx.last_speed)
    expect(math.abs(car.orientation - 0.25) < 1e-6, "orientation changed to %.3f", car.orientation)
    expect(car.position.x >= 40 and car.position.x < 42, "came out at %s", fmt(car.position))
    return 20
  end,
  function()
    expect(ctx.car.position.x > 42 and trips(ctx.car) == 1, "car at %s after %d trips", fmt(ctx.car.position), trips(ctx.car))
  end
})

test("a reversing car comes out backwards", {
  function()
    open(1011, "blue", {0, 100})
    open(1011, "orange", {40, 100})
    ctx.car = spawn("car", {8, 100})
    ctx.car.orientation = 0.25
    ctx.car.speed = -0.3
  end,
  function()
    if ctx.car.position.x < 30 then return "retry" end
    expect(ctx.car.speed < -0.25, "speed %.3f", ctx.car.speed)
    expect(ctx.car.position.x < 40 and ctx.car.position.x > 38.5, "came out at %s", fmt(ctx.car.position))
  end
})

test("a car takes its driver along", {
  function()
    open(1012, "blue", {0, 120})
    open(1012, "orange", {40, 120})
    ctx.car = spawn("car", {-8, 120})
    ctx.car.orientation = 0.25
    ctx.driver = spawn("character", {-8, 122})
    ctx.car.set_driver(ctx.driver)
    ctx.car.speed = 0.3
  end,
  function()
    if ctx.car.position.x < 35 then return "retry" end
    ctx.driver_x_same_tick = ctx.driver.position.x
    return 2
  end,
  function()
    expect(ctx.car.get_driver() == ctx.driver, "driver fell out")
    expect(dist(ctx.driver.position, ctx.car.position) < 1, "driver at %s, car at %s (driver x on the jump tick: %.2f)",
      fmt(ctx.driver.position), fmt(ctx.car.position), ctx.driver_x_same_tick)
    expect(trips(ctx.car) == 1 and trips(ctx.driver) == 0, "car %d trips, driver %d", trips(ctx.car), trips(ctx.driver))
  end
})

test("a fast car from far away still makes it through a sleeping portal", {
  function()
    open(1022, "blue", {0, -10})
    open(1022, "orange", {60, -10})
    ctx.car = spawn("car", {-100, -10})
    ctx.car.orientation = 0.25
    ctx.car.speed = 1.2
  end,
  function()
    if ctx.car.position.x < 0 and ctx.car.surface.name == "nauvis" then return "retry" end
    expect(trips(ctx.car) == 1, "the car drove over a sleeping portal (%d trips), now at %s", trips(ctx.car), fmt(ctx.car.position))
    expect(ctx.car.position.x > 55, "car at %s", fmt(ctx.car.position))
  end
})

test("something put straight into a sleeping portal goes through within a wake interval", {
  function()
    open(1023, "blue", {100, 100})
    open(1023, "orange", {100, 130})
    return 25 -- nothing nearby: both portals fall asleep
  end,
  function()
    ctx.c = spawn("character", {100, 100})
    ctx.placed = game.tick
  end,
  function()
    if trips(ctx.c) == 0 then return "retry" end
    expect(game.tick - ctx.placed <= 12, "took %d ticks", game.tick - ctx.placed)
    expect(dist(ctx.c.position, {x = 100, y = 130}) < 0.6, "came out at %s", fmt(ctx.c.position))
  end
})

test("biters go through, unless the setting is off", {
  function()
    open(1013, "blue", {0, 140})
    open(1013, "orange", {30, 140})
    ctx.biter = spawn("small-biter", {-8, 140}, "enemy")
    ctx.biter.commandable.set_command{type = defines.command.go_to_location, destination = {12, 140}, distraction = defines.distraction.none}
  end,
  function()
    if trips(ctx.biter) == 0 then return "retry" end
    expect(math.abs(ctx.biter.position.x - 30) < 2, "biter came out at %s", fmt(ctx.biter.position))
    set_setting(SETTINGS.units, false)
    open(1014, "blue", {0, 150})
    open(1014, "orange", {30, 150})
    ctx.biter2 = spawn("small-biter", {-8, 150}, "enemy")
    ctx.biter2.commandable.set_command{type = defines.command.go_to_location, destination = {8, 150}, distraction = defines.distraction.none}
  end,
  function()
    if ctx.biter2.position.x < 4 then return "retry" end
    expect(trips(ctx.biter2) == 0, "biter went through with the setting off")
  end
})

test("vehicles stay out when the setting is off", {
  function()
    set_setting(SETTINGS.vehicles, false)
    open(1015, "blue", {60, 20})
    open(1015, "orange", {90, 20})
    ctx.car = spawn("car", {52, 20})
    ctx.car.orientation = 0.25
    ctx.car.speed = 0.3
  end,
  function()
    if ctx.car.position.x < 64 then return "retry" end
    expect(trips(ctx.car) == 0, "car went through with the setting off")
  end
})

test("a spidertron walks through", {
  function()
    open(1016, "blue", {0, -40})
    open(1016, "orange", {30, -40})
    ctx.spider = spawn("spidertron", {-10, -40})
    ctx.spider.add_autopilot_destination({10, -40})
  end,
  function()
    if trips(ctx.spider) == 0 then return "retry" end
    expect(math.abs(ctx.spider.position.x - 30) < 3, "spider came out at %s", fmt(ctx.spider.position))
  end
})

test("an exit with no room keeps you on your side", {
  function()
    open(1017, "blue", {60, 60})
    open(1017, "orange", {90, 60})
    for x = 85, 95 do
      for y = 55, 65 do spawn("stone-wall", {x + 0.5, y + 0.5}) end
    end
    ctx.c = spawn("character", {56, 60})
  end,
  function()
    walk(ctx.c, defines.direction.east)
    if ctx.c.position.x < 62 then return "retry" end
    expect(trips(ctx.c) == 0, "went through into a wall of stone")
    expect(ctx.c.position.x < 70, "ended up at %s", fmt(ctx.c.position))
  end
})

test("portals on different surfaces link only when allowed; units never cross", {
  function()
    local other = game.create_surface("pg-other")
    other.request_to_generate_chunks({0, 0}, 2)
    other.force_generate_chunk_requests()
    for _, entity in pairs(other.find_entities_filtered{area = {{-40, -40}, {40, 40}}}) do entity.destroy() end
    set_tiles(other, "grass-1", -40, -40, 39, 39)
    open(1018, "blue", {60, 40})
    open(1018, "orange", {0, 0}, "pg-other")
    expect(not call("get_portal", 1018, "blue").linked, "linked across surfaces with the setting off")
    ctx.c = spawn("character", {56, 40})
  end,
  function()
    walk(ctx.c, defines.direction.east)
    if ctx.c.position.x < 62 then return "retry" end
    walk(ctx.c, nil)
    expect(ctx.c.surface.name == "nauvis" and trips(ctx.c) == 0, "crossed with the setting off")
    set_setting(SETTINGS.cross, true)
    expect(call("get_portal", 1018, "blue").linked, "not linked with the setting on")
    ctx.c2 = spawn("character", {56, 40})
  end,
  function()
    walk(ctx.c2, defines.direction.east)
    if ctx.c2.surface.name ~= "pg-other" then return "retry" end
    walk(ctx.c2, nil)
    expect(dist(ctx.c2.position, {x = 0.5, y = 0}) < 0.6, "arrived at %s", fmt(ctx.c2.position))
    ctx.car = spawn("car", {54, 40})
    ctx.car.orientation = 0.25
    ctx.car.speed = 0.3
  end,
  function()
    if ctx.car.surface.name ~= "pg-other" then return "retry" end
    expect(ctx.car.speed > 0.25, "car lost its speed crossing surfaces (%.3f)", ctx.car.speed)
    ctx.car2 = spawn("car", {54, 40})
    ctx.car2.orientation = 0.25
    ctx.driver = spawn("character", {54, 42})
    ctx.car2.set_driver(ctx.driver)
    ctx.car2.speed = 0.3
  end,
  function()
    if ctx.car2.surface.name ~= "pg-other" then return "retry" end
    return 2
  end,
  function()
    expect(ctx.car2.get_driver() == ctx.driver, "the driver did not come along to the other surface")
    expect(ctx.driver.surface.name == "pg-other", "driver left on %s", ctx.driver.surface.name)
    ctx.biter = spawn("small-biter", {56, 40}, "enemy")
    ctx.biter.commandable.set_command{type = defines.command.go_to_location, destination = {64, 40}, distraction = defines.distraction.none}
  end,
  function()
    if ctx.biter.position.x < 62 then return "retry" end
    expect(ctx.biter.surface.name == "nauvis" and trips(ctx.biter) == 0, "a biter crossed surfaces")
  end
})

test("closing, destroying or mining a portal cleans up", {
  function()
    open(1019, "blue", {0, -50})
    open(1019, "orange", {20, -50})
    expect(call("close_portals", 1019, "blue") == 1, "close blue")
    expect(call("get_portal", 1019, "blue") == nil, "blue still listed")
    expect(not call("get_portal", 1019, "orange").linked, "orange still linked")
    expect(call("close_portals", 1019) == 1, "close the rest")
    expect(#nauvis().find_entities_filtered{name = {BLUE, ORANGE}, area = {{-5, -55}, {25, -45}}} == 0, "entities left behind")
    open(1019, "blue", {0, -50})
    open(1019, "orange", {20, -50})
    call("get_portal", 1019, "blue").entity.destroy()
    return 3
  end,
  function()
    expect(call("get_portal", 1019, "blue") == nil, "destroyed portal still listed")
    expect(not call("get_portal", 1019, "orange").linked, "orange still linked to a destroyed portal")
    local orange = call("get_portal", 1019, "orange").entity
    expect(orange.mine{force = true}, "mining the portal failed")
    return 3
  end,
  function()
    expect(call("get_portal", 1019, "orange") == nil, "mined portal still listed")
  end
})

test("a fired shot flies and opens the portal where it lands", {
  function()
    ctx.arrival = call("fire", 1020, "orange", "nauvis", {0, -30}, {40, -30})
    expect(ctx.arrival - game.tick >= 15 and ctx.arrival - game.tick <= 25, "flight takes %d ticks", ctx.arrival - game.tick)
    expect(#nauvis().find_entities_filtered{name = "portal-guns-shot-orange"} == 1, "no projectile in flight")
    expect(call("get_portal", 1020, "orange") == nil, "portal opened before the shot landed")
  end,
  function()
    if game.tick <= ctx.arrival then return "retry" end
    local orange = call("get_portal", 1020, "orange")
    expect(orange and dist(orange.position, {x = 40, y = -30}) < 0.01, "portal at %s", fmt(orange and orange.position))
    -- Closing your portals also cancels the shots still in flight.
    ctx.arrival = call("fire", 1020, "blue", "nauvis", {0, -34}, {40, -34})
    expect(call("close_portals", 1020) == 1, "close_portals should close the orange portal")
  end,
  function()
    if game.tick <= ctx.arrival + 2 then return "retry" end
    expect(call("get_portal", 1020, "blue") == nil, "a cancelled shot still opened a portal")
  end
})

test("shooting like the gun: range limit and cooldown", {
  function()
    ctx.first = call("shoot", 1021, "blue", "nauvis", {0, -60}, {200, -60})
    expect(ctx.first, "first shot refused")
    local again, reason = call("shoot", 1021, "orange", "nauvis", {0, -60}, {-20, -60})
    expect(again == nil and reason == "cooldown", "second shot in the same tick: %s / %s", tostring(again), tostring(reason))
    return 16
  end,
  function()
    ctx.second = call("shoot", 1021, "orange", "nauvis", {0, -60}, {-20, -60})
    expect(ctx.second, "shot after the cooldown refused")
  end,
  function()
    if game.tick <= math.max(ctx.first, ctx.second) then return "retry" end
    local range = settings.global["portal-guns-range"].value
    local blue, orange = call("get_portal", 1021, "blue"), call("get_portal", 1021, "orange")
    expect(blue and dist(blue.position, {x = range, y = -60}) < 0.01, "long shot landed at %s, range %d", fmt(blue and blue.position), range)
    expect(orange and dist(orange.position, {x = -20, y = -60}) < 0.01, "short shot landed at %s", fmt(orange and orange.position))
    expect(blue.linked, "pair not linked")
  end
})

test("nothing is left behind", {function()
  expect(#call("get_portals") == 0, "%d portals still open", #call("get_portals"))
  expect(#nauvis().find_entities_filtered{name = {BLUE, ORANGE}} == 0, "portal entities left on nauvis")
  expect(#rendering.get_all_objects(MOD) == 0, "%d render objects left", #rendering.get_all_objects(MOD))
end})

---------------------------------------------------------------------------------------------------- runner

local function prepare_world()
  local s = nauvis()
  s.always_day = true
  s.peaceful_mode = true
  game.map_settings.enemy_expansion.enabled = false
  s.request_to_generate_chunks({0, 40}, 7)
  s.force_generate_chunk_requests()
  local area = {{-130, -70}, {130, 170}}
  for _, entity in pairs(s.find_entities_filtered{area = area}) do
    if entity.valid then entity.destroy() end
  end
  set_tiles(s, "grass-1", -130, -70, 129, 169)
  s.destroy_decoratives{area = area}
end

local function cleanup()
  for _, portal in pairs(call("get_portals")) do call("close_portals", portal.owner) end
  for _, entity in pairs(ctx.entities) do
    if entity.valid then entity.destroy() end
  end
  teleports = {}
  set_setting(SETTINGS.units, true)
  set_setting(SETTINGS.vehicles, true)
  set_setting(SETTINGS.cross, false)
end

local runner

local function start(index)
  runner.index, runner.step, runner.wait_until, runner.step_started = index, 1, game.tick + 1, game.tick
  ctx = {entities = {}}
  if not tests[index] then
    print(string.format("TESTS DONE passed=%d failed=%d", runner.passed, runner.failed))
    runner.done = true
  end
end

local function finish(ok, message)
  local name = tests[runner.index].name
  if ok then
    runner.passed = runner.passed + 1
    print("PASS " .. name)
  else
    runner.failed = runner.failed + 1
    print("FAIL " .. name .. ": " .. tostring(message))
  end
  local cleaned, err = pcall(cleanup)
  if not cleaned then print("FAIL cleanup after " .. name .. ": " .. tostring(err)) end
  start(runner.index + 1)
end

-- The map is created (and saved) by `--create`; the tests run after the benchmark loads it again, so this pair
-- also checks that portals survive saving and loading.
script.on_init(function()
  prepare_world()
  call("open_portal", 2001, "blue", "nauvis", {100, -60})
  call("open_portal", 2001, "orange", "nauvis", {100, -30})
end)

script.on_event(defines.events.on_tick, function(event)
  if not runner then
    runner = {passed = 0, failed = 0}
    local mods = {}
    for name, version in pairs(script.active_mods) do mods[#mods + 1] = name .. " " .. version end
    table.sort(mods)
    print("TESTS START " .. #tests .. " tests; mods: " .. table.concat(mods, ", "))
    start(1)
    return
  end
  if runner.done or event.tick < runner.wait_until then return end
  local current = tests[runner.index]
  local ok, result = pcall(current.steps[runner.step], ctx)
  if not ok then return finish(false, result) end
  if result == "retry" then
    if event.tick - runner.step_started > TIMEOUT then
      finish(false, "timed out in step " .. runner.step)
    end
    return
  end
  runner.step = runner.step + 1
  runner.step_started = event.tick
  runner.wait_until = event.tick + (type(result) == "number" and result or 1)
  if runner.step > #current.steps then finish(true) end
end)
