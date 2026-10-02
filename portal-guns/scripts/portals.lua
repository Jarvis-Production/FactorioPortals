-- Portal state: placement, visuals, linking and closing.
--
-- storage.portals[id]        = portal record (see create_portal; `awake`/`next_wake` belong to transit.lua)
-- storage.owners[owner]      = {blue = id?, orange = id?, next_shot_tick = tick}
--                              owner is a player index, or any number/string a script chose (remote API)
-- storage.by_registration[n] = id, for on_object_destroyed
-- storage.animating[id]      = tick the portal (re)opened at
local constants = require("scripts.constants")
local geometry = require("scripts.geometry")
local config = require("scripts.config")

local portals = {}

local LINKED = {speed = 0.33, color = {1, 1, 1, 1}, light = 0.85}
local UNLINKED = {speed = 0.12, color = {0.55, 0.55, 0.55, 0.7}, light = 0.35}
local RENDER_LAYER = "lower-object-above-shadow"

function portals.init_storage()
  storage.next_id = storage.next_id or 1
  storage.portals = storage.portals or {}
  storage.owners = storage.owners or {}
  storage.by_registration = storage.by_registration or {}
  storage.animating = storage.animating or {}
end

--- Fills in fields that older saves of this mod may lack (called from on_configuration_changed).
function portals.migrate()
  for _, portal in pairs(storage.portals) do
    if portal.entity.valid then
      portal.surface = portal.surface or portal.entity.surface
      portal.next_wake = portal.next_wake or 0
      portal.occupants = portal.occupants or {}
    end
  end
end

function portals.owner_record(owner, create)
  local record = storage.owners[owner]
  if not record and create then
    record = {next_shot_tick = 0}
    storage.owners[owner] = record
  end
  return record
end

--- The player behind an owner key, if there is one.
function portals.owner_player(owner)
  if type(owner) ~= "number" then return nil end
  local player = game.get_player(owner)
  if player and player.valid then return player end
  return nil
end

--- The owner's open portal of the given colour, if any (dead records are cleaned up on the way).
function portals.get(owner, color)
  local record = storage.owners[owner]
  local id = record and record[color]
  if not id then return nil end
  local portal = storage.portals[id]
  if portal and portal.entity.valid then return portal end
  if portal then portals.forget(portal) else record[color] = nil end
  return nil
end

function portals.partner(portal)
  return portals.get(portal.owner, constants.other_color[portal.color])
end

--- Both portals exist and are allowed to connect.
function portals.linked(a, b)
  if not (a and b and a.entity.valid and b.entity.valid) then return false end
  return a.surface_index == b.surface_index or config.cross_surface
end

local function notify(owner, message, position, surface)
  local player = portals.owner_player(owner)
  if not player then return end
  player.create_local_flying_text{text = message, position = position, surface = surface}
  player.play_sound{path = constants.denied_sound}
end
portals.notify = notify

local function effect(name, surface, position)
  surface.create_entity{name = name, position = position}
end
portals.effect = effect

local function set_scale(portal, scale)
  for _, object in pairs({portal.body, portal.glow}) do
    if object and object.valid then
      object.x_scale = scale
      object.y_scale = scale
    end
  end
  if portal.light and portal.light.valid then portal.light.scale = 1.6 * scale end
end

local function set_look(portal, look)
  for _, object in pairs({portal.body, portal.glow}) do
    if object and object.valid then
      object.animation_speed = look.speed
      object.color = look.color
    end
  end
  if portal.light and portal.light.valid then portal.light.intensity = look.light end
end

local function owner_label(owner)
  local player = portals.owner_player(owner)
  if player then return player.name end
  return tostring(owner)
end

local function update_label(portal)
  if config.labels and not (portal.label and portal.label.valid) then
    portal.label = rendering.draw_text{
      text = owner_label(portal.owner),
      surface = portal.surface,
      target = {entity = portal.entity, offset = {0, -1.35}},
      color = constants.tint[portal.color],
      scale = 1.1,
      alignment = "center",
      vertical_alignment = "middle",
      only_in_alt_mode = true
    }
  elseif not config.labels and portal.label then
    if portal.label.valid then portal.label.destroy() end
    portal.label = nil
  end
end

local function draw_visuals(portal)
  local entity, color = portal.entity, portal.color
  local offset = (portal.id * 7) % 16
  local common = {
    target = entity,
    surface = entity.surface,
    render_layer = RENDER_LAYER,
    x_scale = 0.05,
    y_scale = 0.05,
    animation_speed = UNLINKED.speed,
    animation_offset = offset
  }
  common.animation = constants.portal_body_animation[color]
  portal.body = rendering.draw_animation(common)
  common.animation = constants.portal_glow_animation[color]
  portal.glow = rendering.draw_animation(common)
  portal.light = rendering.draw_light{
    sprite = "utility/light_medium",
    target = entity,
    surface = entity.surface,
    color = constants.tint[color],
    scale = 0.1,
    intensity = UNLINKED.light
  }
  update_label(portal)
end

--- Updates both portals of an owner to look linked (bright, fast swirl) or waiting (dim, slow).
function portals.refresh_look(owner)
  local blue, orange = portals.get(owner, "blue"), portals.get(owner, "orange")
  local look = portals.linked(blue, orange) and LINKED or UNLINKED
  if blue then set_look(blue, look) end
  if orange then set_look(orange, look) end
end

--- After a settings change: labels, looks, and what counts as already standing in a portal (so a pair that
--- just became linked doesn't yank whatever was standing in it).
function portals.refresh_all()
  for owner in pairs(storage.owners) do
    portals.refresh_look(owner)
    for _, color in pairs(constants.colors) do
      local portal = portals.get(owner, color)
      if portal then
        update_label(portal)
        portals.refresh_occupants(portal)
      end
    end
  end
end

--- Entities standing in a portal right now don't get pulled through; they have to step in.
function portals.refresh_occupants(portal)
  local occupants = {}
  portal.awake, portal.next_wake = true, 0
  local found = portal.surface.find_entities_filtered{
    position = portal.position,
    radius = constants.portal_radius,
    type = constants.traveller_types
  }
  for _, entity in pairs(found) do
    if entity.unit_number then occupants[entity.unit_number] = true end
  end
  portal.occupants = occupants
end

local function start_opening(portal)
  storage.animating[portal.id] = game.tick
  set_scale(portal, 0.05)
end

function portals.animate(tick)
  for id, start in pairs(storage.animating) do
    local portal = storage.portals[id]
    if not (portal and portal.entity.valid) then
      storage.animating[id] = nil
    else
      local t = (tick - start) / constants.open_ticks
      if t >= 1 then
        set_scale(portal, 1)
        storage.animating[id] = nil
      else
        local eased = 1 - (1 - t) ^ 3
        set_scale(portal, 0.05 + 0.95 * eased)
      end
    end
  end
end

--- Is there room for a portal at `position`, ignoring the portal `moving` (the one being re-shot)?
local function overlaps_other_portal(surface, position, moving)
  local found = surface.find_entities_filtered{
    position = position,
    radius = constants.portal_min_spacing,
    name = {constants.portal_entity.blue, constants.portal_entity.orange}
  }
  for _, entity in pairs(found) do
    if not (moving and moving.entity == entity) then return true end
  end
  return false
end

local function fits(surface, position, moving)
  return surface.can_place_entity{name = constants.probe, position = position}
    and not overlaps_other_portal(surface, position, moving)
end

-- Candidate spots: the aimed point, then rings around it out to nudge_radius.
local RINGS = {{0.5, 8}, {1.0, 8}, {1.5, 12}, {2.0, 16}}

--- Where a portal aimed at `target` actually opens, or nil and a reason. A shot that lands on another
--- portal fails; one that lands on a small obstacle (a tree, a corner of a building) slides off it.
function portals.find_spot(surface, target, moving)
  if overlaps_other_portal(surface, target, moving) then return nil, "too-close" end
  if fits(surface, target, moving) then return target end
  for _, ring in pairs(RINGS) do
    local radius, count = ring[1], ring[2]
    if radius <= constants.nudge_radius then
      for i = 0, count - 1 do
        local spot = geometry.offset(target, geometry.orientation_vector(i / count), radius)
        if fits(surface, spot, moving) then return spot end
      end
    end
  end
  return nil, "fizzle"
end

local function create_portal(owner, color, surface, position)
  local entity = surface.create_entity{
    name = constants.portal_entity[color],
    position = position,
    force = "neutral",
    create_build_effect_smoke = false
  }
  if not entity then return nil end
  entity.destructible = false
  local player = portals.owner_player(owner)
  if player then entity.last_user = player end

  local id = storage.next_id
  storage.next_id = id + 1
  local portal = {
    id = id,
    owner = owner,
    color = color,
    entity = entity,
    surface = surface,
    surface_index = surface.index,
    position = geometry.position(entity.position),
    occupants = {},
    awake = true,
    next_wake = 0,
    registration = script.register_on_object_destroyed(entity)
  }
  storage.portals[id] = portal
  storage.by_registration[portal.registration] = id
  portals.owner_record(owner, true)[color] = id
  draw_visuals(portal)
  return portal
end

--- Opens (or moves) the owner's portal of `color` at `target` on `surface`.
--- Returns the portal record, or nil and a reason ("fizzle" / "too-close" / "failed").
function portals.open(owner, color, surface, target)
  target = geometry.position(target)
  local portal = portals.get(owner, color)
  local spot, reason = portals.find_spot(surface, target, portal)
  if not spot then
    effect(constants.fizzle_effect[color], surface, target)
    notify(owner, {"portal-guns." .. reason}, target, surface)
    return nil, reason
  end

  if portal and portal.surface_index == surface.index then
    -- Same surface: move it. teleport() does no build check of its own; the spot was validated above.
    effect(constants.close_effect[color], surface, portal.position)
    portal.entity.teleport(spot)
    portal.position = geometry.position(portal.entity.position)
  else
    local old = portal
    portal = create_portal(owner, color, surface, spot)
    if not portal then
      effect(constants.fizzle_effect[color], surface, target)
      return nil, "failed"
    end
    if old then portals.close(old) end
  end

  start_opening(portal)
  effect(constants.open_effect[color], surface, portal.position)
  -- Whatever stands in either portal now stays put until it steps out and back in.
  portals.refresh_occupants(portal)
  local partner = portals.partner(portal)
  if partner then portals.refresh_occupants(partner) end
  portals.refresh_look(owner)
  return portal
end

--- Drops a portal from storage (the entity is already gone or about to be).
function portals.forget(portal)
  storage.portals[portal.id] = nil
  storage.animating[portal.id] = nil
  if portal.registration then storage.by_registration[portal.registration] = nil end
  local record = storage.owners[portal.owner]
  if record and record[portal.color] == portal.id then record[portal.color] = nil end
end

function portals.close(portal, silent)
  local entity = portal.entity
  if entity.valid then
    if not silent then effect(constants.close_effect[portal.color], entity.surface, portal.position) end
    entity.destroy()
  end
  portals.forget(portal)
  portals.refresh_look(portal.owner)
end

--- Closes the owner's portals; `color` nil closes both. Returns how many were closed.
function portals.close_owned(owner, color)
  local closed = 0
  for _, c in pairs(constants.colors) do
    if color == nil or color == c then
      local portal = portals.get(owner, c)
      if portal then
        portals.close(portal)
        closed = closed + 1
      end
    end
  end
  return closed
end

function portals.on_object_destroyed(event)
  local id = storage.by_registration[event.registration_number]
  if not id then return end
  storage.by_registration[event.registration_number] = nil
  local portal = storage.portals[id]
  if portal then
    portals.forget(portal)
    portals.refresh_look(portal.owner)
  end
end

--- A plain-data view of a portal for the remote interface.
function portals.describe(portal)
  if not portal then return nil end
  local partner = portals.partner(portal)
  return {
    id = portal.id,
    owner = portal.owner,
    color = portal.color,
    entity = portal.entity,
    surface_index = portal.surface_index,
    position = {x = portal.position.x, y = portal.position.y},
    linked = portals.linked(portal, partner)
  }
end

return portals
