local constants = require("scripts.constants")
local geometry = require("scripts.geometry")
local config = require("scripts.config")
local portals = require("scripts.portals")
local shots = require("scripts.shots")
local transit = require("scripts.transit")

local function init_storage()
  portals.init_storage()
  shots.init_storage()
end

script.on_init(function()
  config.refresh()
  init_storage()
end)

script.on_load(function()
  config.refresh()
end)

script.on_configuration_changed(function()
  config.refresh()
  init_storage()
  portals.migrate()
  portals.refresh_all()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if not event.setting:find("^portal%-guns%-") then return end
  config.refresh()
  portals.refresh_all()
end)

script.on_event(defines.events.on_tick, function(event)
  shots.process(event.tick)
  portals.animate(event.tick)
  transit.tick(event.tick)
end)

-- The gun: left click blue, right click orange, shift closes that colour.
local function gun_event(color, close)
  return function(event)
    if event.item ~= constants.gun_item then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    if close then
      shots.cancel(player.index, color)
      portals.close_owned(player.index, color)
    else
      shots.fire_from_player(player, color, event.surface, geometry.area_center(event.area))
    end
  end
end

script.on_event(defines.events.on_player_selected_area, gun_event("blue", false))
script.on_event(defines.events.on_player_reverse_selected_area, gun_event("orange", false))
script.on_event(defines.events.on_player_alt_selected_area, gun_event("blue", true))
script.on_event(defines.events.on_player_alt_reverse_selected_area, gun_event("orange", true))

local function close_all(player_index)
  local player = game.get_player(player_index)
  if not player then return end
  shots.cancel(player_index)
  if portals.close_owned(player_index) == 0 then
    player.create_local_flying_text{text = {"portal-guns.no-portals"}, create_at_cursor = true}
  end
end

script.on_event(constants.close_input, function(event)
  close_all(event.player_index)
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == constants.close_shortcut then close_all(event.player_index) end
end)

script.on_event(defines.events.on_player_removed, function(event)
  shots.cancel(event.player_index)
  portals.close_owned(event.player_index)
  storage.owners[event.player_index] = nil
end)

script.on_event(defines.events.on_object_destroyed, portals.on_object_destroyed)

local function resolve_surface(surface)
  if type(surface) == "userdata" or type(surface) == "table" then
    assert(surface.valid and surface.object_name == "LuaSurface", "portal-guns: not a LuaSurface")
    return surface
  end
  local resolved = game.get_surface(surface)
  assert(resolved, "portal-guns: unknown surface " .. tostring(surface))
  return resolved
end

local function check(owner, color, color_optional)
  assert(owner ~= nil, "portal-guns: owner must be a player index or another number/string key")
  assert((color_optional and color == nil) or constants.other_color[color],
    "portal-guns: color must be \"blue\" or \"orange\"")
end

--- Remote interface, for scenarios and other mods. `owner` is a player index, or any number/string key that
--- names a portal pair that belongs to no player (a scenario's fixed portals, for example).
remote.add_interface(constants.mod_name, {
  --- Opens (or moves) a portal right away. Returns the portal id, or nil and "fizzle" / "too-close" / "failed".
  open_portal = function(owner, color, surface, position)
    check(owner, color)
    local portal, reason = portals.open(owner, color, resolve_surface(surface), position)
    return portal and portal.id, reason
  end,
  --- Fires a shot (projectile and all) from `origin` to `target`; the portal opens when it lands.
  --- Returns the tick it lands on. No range limit or cooldown applies.
  fire = function(owner, color, surface, origin, target, shooter)
    check(owner, color)
    return shots.fire(owner, color, resolve_surface(surface), origin, target, shooter)
  end,
  --- Like `fire`, but with the gun's rules: the range setting and the per-owner cooldown.
  --- Returns the landing tick, or nil and "cooldown".
  shoot = function(owner, color, surface, origin, target, shooter)
    check(owner, color)
    return shots.shoot(owner, color, resolve_surface(surface), origin, target, shooter)
  end,
  --- Closes one colour, or both when `color` is nil, and cancels those shots still in flight.
  --- Returns how many portals were closed.
  close_portals = function(owner, color)
    check(owner, color, true)
    shots.cancel(owner, color)
    return portals.close_owned(owner, color)
  end,
  get_portal = function(owner, color)
    check(owner, color)
    return portals.describe(portals.get(owner, color))
  end,
  get_portals = function()
    local list = {}
    for owner in pairs(storage.owners) do
      for _, color in pairs(constants.colors) do
        local portal = portals.get(owner, color)
        if portal then list[#list + 1] = portals.describe(portal) end
      end
    end
    return list
  end,
  --- Changes one of this mod's runtime-global settings. A mod may only change its own settings, so scenarios
  --- and other mods go through here, e.g. set_setting("portal-guns-cross-surface", true).
  set_setting = function(name, value)
    assert(type(name) == "string" and name:find("^portal%-guns%-") and settings.global[name],
      "portal-guns: unknown setting " .. tostring(name))
    settings.global[name] = {value = value}
  end,
  --- Names of the custom events this mod raises. "on_teleported" carries entity, owner, from_portal,
  --- to_portal and cross_surface; subscribe with script.on_event("portal-guns-on-teleported", handler).
  get_event_names = function()
    return {on_teleported = constants.teleported_event}
  end
})
