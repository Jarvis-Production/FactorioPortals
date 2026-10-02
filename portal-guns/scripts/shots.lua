-- Firing the gun. The projectile is only for show; the portal opens when the shot's flight time is up.
--
-- storage.shots[tick] = {{owner=, color=, surface_index=, target={x,y}}, ...}  (shots landing on that tick)
local constants = require("scripts.constants")
local geometry = require("scripts.geometry")
local config = require("scripts.config")
local portals = require("scripts.portals")

local shots = {}

local CAN_SHOOT = {
  [defines.controllers.character] = true,
  [defines.controllers.god] = true,
  [defines.controllers.editor] = true,
}

function shots.init_storage()
  storage.shots = storage.shots or {}
end

--- Fires a shot from `origin` to `target`. `shooter` (optional) is the entity the shot comes from.
--- Returns the tick the portal will open on.
function shots.fire(owner, color, surface, origin, target, shooter)
  origin, target = geometry.position(origin), geometry.position(target)
  local direction = geometry.normalize{x = target.x - origin.x, y = target.y - origin.y} or {x = 0, y = -1}
  local distance = geometry.distance(origin, target)
  local muzzle = geometry.offset(origin, direction, math.min(0.6, distance))

  portals.effect(constants.muzzle[color], surface, muzzle)
  local flight = geometry.distance(muzzle, target)
  if flight > 0.3 then
    surface.create_entity{
      name = constants.shot[color],
      position = muzzle,
      target = target,
      source = (shooter and shooter.valid) and shooter or muzzle,
      force = "neutral",
      speed = constants.shot_speed,
      max_range = flight + 2
    }
  end

  local arrival = game.tick + math.max(1, math.ceil(flight / constants.shot_speed))
  local due = storage.shots[arrival]
  if not due then
    due = {}
    storage.shots[arrival] = due
  end
  due[#due + 1] = {owner = owner, color = color, surface_index = surface.index, target = target}
  return arrival
end

--- Fires the way the gun does: at most once per cooldown per owner, and no further than the range setting.
--- Returns the landing tick, or nil and "cooldown".
function shots.shoot(owner, color, surface, origin, target, shooter)
  local record = portals.owner_record(owner, true)
  if game.tick < (record.next_shot_tick or 0) then return nil, "cooldown" end
  record.next_shot_tick = game.tick + constants.shot_cooldown
  origin = geometry.position(origin)
  target = geometry.clamp_to_range(origin, geometry.position(target), config.range)
  return shots.fire(owner, color, surface, origin, target, shooter)
end

--- A player clicked with the gun. `surface` and `target` come from the selection event.
function shots.fire_from_player(player, color, surface, target)
  if not CAN_SHOOT[player.physical_controller_type] then
    portals.notify(player.index, {"portal-guns.no-body"}, target, surface)
    return nil
  end
  if player.physical_surface_index ~= surface.index then
    portals.notify(player.index, {"portal-guns.wrong-surface"}, target, surface)
    return nil
  end
  local shooter = player.physical_vehicle or player.character
  return shots.shoot(player.index, color, surface, player.physical_position, target, shooter)
end

--- Cancels the owner's shots still in flight (one colour, or both when `color` is nil), so closing your
--- portals also stops the ones about to open.
function shots.cancel(owner, color)
  for tick, due in pairs(storage.shots) do
    for i = #due, 1, -1 do
      if due[i].owner == owner and (color == nil or due[i].color == color) then table.remove(due, i) end
    end
    if #due == 0 then storage.shots[tick] = nil end
  end
end

function shots.process(tick)
  local due = storage.shots[tick]
  if not due then return end
  storage.shots[tick] = nil
  for _, shot in pairs(due) do
    local surface = game.get_surface(shot.surface_index)
    if surface and surface.valid then
      portals.open(shot.owner, shot.color, surface, shot.target)
    end
  end
end

return shots
