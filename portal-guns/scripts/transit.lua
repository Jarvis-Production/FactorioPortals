-- Moving things through linked portals. Runs every tick for every owner whose two portals are linked.
--
-- Each portal keeps `occupants` (unit_number -> true): what was inside it last tick. Only something that is
-- inside now and wasn't before has "stepped in" and goes through. Arrivals are added to the exit portal's
-- occupants, so nothing bounces straight back.
--
-- Scanning is cheap but not free, so a linked portal "sleeps" while nothing that could travel is within
-- wake_radius, and only looks around again every wake_interval ticks.
local constants = require("scripts.constants")
local geometry = require("scripts.geometry")
local config = require("scripts.config")
local portals = require("scripts.portals")

local transit = {}

local function allowed(entity)
  local entity_type = entity.type
  if constants.character_types[entity_type] then
    return entity.vehicle == nil -- passengers travel with their vehicle
  elseif constants.vehicle_types[entity_type] then
    return config.vehicles
  elseif constants.unit_types[entity_type] then
    return config.units
  end
  return false
end

--- Which way the entity is moving, as a unit vector, or nil when it isn't really moving.
local function heading(entity, portal_position)
  local entity_type = entity.type
  if entity_type == "car" then
    local speed = entity.speed or 0
    if math.abs(speed) < 0.001 then return nil end
    local v = geometry.orientation_vector(entity.orientation)
    if speed < 0 then v.x, v.y = -v.x, -v.y end
    return v
  elseif entity_type == "character" then
    local walking = entity.walking_state
    if walking.walking then return geometry.direction_vector(walking.direction) end
    return nil
  elseif entity_type == "unit" then
    return geometry.orientation_vector(entity.orientation)
  end
  -- Spidertrons and spider units: assume they were heading for the portal's centre.
  local position = entity.position
  return geometry.normalize{x = portal_position.x - position.x, y = portal_position.y - position.y}
end

--- Sends `entity` from portal `from` to portal `to`. Returns true if it went through.
local function pass_through(entity, from, to)
  local exit_surface = to.surface
  local cross_surface = to.surface_index ~= from.surface_index
  if cross_surface and not constants.cross_surface_types[entity.type] then return false end

  local direction = heading(entity, from.position)
  local exit = direction and geometry.offset(to.position, direction, constants.exit_offset) or to.position
  local spot = exit_surface.find_non_colliding_position(entity.name, exit, constants.exit_search_radius, 0.25)
  if not spot then return false end

  local speed = entity.type == "car" and entity.speed or nil
  local ok
  if cross_surface then
    ok = entity.teleport(spot, exit_surface, true)
  else
    ok = entity.teleport(spot, nil, true)
  end
  if not ok then return false end
  -- Speedy thing goes in, speedy thing comes out (a jump to another surface resets a car's speed).
  if speed and entity.speed ~= speed then entity.speed = speed end

  portals.effect(constants.teleport_effect[from.color], from.surface, from.position)
  portals.effect(constants.teleport_effect[to.color], exit_surface, to.position)
  script.raise_event(constants.teleported_event, {
    entity = entity,
    owner = from.owner,
    from_portal = from.id,
    to_portal = to.id,
    cross_surface = cross_surface
  })
  return true
end

local function awake(portal, tick)
  if tick >= portal.next_wake then
    portal.next_wake = tick + constants.wake_interval
    local surface = portal.surface
    portal.awake = surface.valid and surface.count_entities_filtered{
      position = portal.position,
      radius = constants.wake_radius,
      type = constants.traveller_types,
      limit = 1
    } > 0
    -- Nothing nearby means nothing inside either.
    if not portal.awake and next(portal.occupants) then portal.occupants = {} end
  end
  return portal.awake
end

local function process(portal, partner)
  local found = portal.surface.find_entities_filtered{
    position = portal.position,
    radius = constants.portal_radius,
    type = constants.traveller_types
  }
  local occupants, current = portal.occupants, {}
  for i = 1, #found do
    local entity = found[i]
    -- A handler of the teleported event (another mod) may have destroyed it in the meantime.
    local unit_number = entity.valid and entity.unit_number
    if unit_number then
      if occupants[unit_number] or not allowed(entity) or not pass_through(entity, portal, partner) then
        current[unit_number] = true
      else
        partner.occupants[unit_number] = true
        partner.awake = true
      end
    end
  end
  portal.occupants = current
end

function transit.tick(tick)
  local all = storage.portals
  for _, record in pairs(storage.owners) do
    local blue, orange = all[record.blue], all[record.orange]
    if blue and orange and (blue.surface_index == orange.surface_index or config.cross_surface) then
      -- A destroyed portal stays in storage until on_object_destroyed arrives, and a handler of the teleported
      -- event (another mod) may close one, so the entities are checked before every scan.
      if awake(blue, tick) and blue.entity.valid and orange.entity.valid then process(blue, orange) end
      if awake(orange, tick) and orange.entity.valid and blue.entity.valid then process(orange, blue) end
    end
  end
end

return transit
