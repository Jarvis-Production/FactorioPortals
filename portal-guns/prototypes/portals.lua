-- Portal entities, their animations (drawn from script with LuaRendering) and the placement probe.
local util = require("util")
local constants = require("scripts.constants")
local sounds = require("prototypes.sounds")

local graphics = constants.mod_path .. "/graphics/entity/portal/"
local h = constants.portal_half_size

-- One 4x4 sheet of 192x192 frames per layer. Drawn at scale 0.5, so a frame covers 3x3 tiles; the portal's
-- rim sits on a circle of radius 1 tile and the rest is glow.
local function sheet(color, layer, extra)
  local animation = {
    type = "animation",
    name = (layer == "body") and constants.portal_body_animation[color] or constants.portal_glow_animation[color],
    filename = graphics .. "portal-" .. color .. "-" .. layer .. ".png",
    priority = "high",
    width = 192,
    height = 192,
    frame_count = 16,
    line_length = 4,
    scale = 0.5,
    animation_speed = 1
  }
  for k, v in pairs(extra or {}) do animation[k] = v end
  return animation
end

local function portal_entity(color)
  local tint = constants.tint[color]
  return {
    type = "simple-entity-with-owner",
    name = constants.portal_entity[color],
    icon = constants.mod_path .. "/graphics/icons/portal-" .. color .. ".png",
    icon_size = 64,
    flags =
    {
      "placeable-neutral", "placeable-off-grid", "not-rotatable", "not-blueprintable", "not-deconstructable",
      "not-upgradable", "not-repairable", "not-flammable", "no-copy-paste", "not-in-kill-statistics",
      "not-in-made-in"
    },
    hidden = true,
    max_health = 1000,
    create_ghost_on_death = false,
    -- Mining a portal by hand closes it (there is nothing to pick up).
    minable = {mining_time = 0.5},
    mined_sound = sounds.close,
    collision_box = {{-h, -h}, {h, h}},
    selection_box = {{-1, -1}, {1, 1}},
    selection_priority = 30,
    -- Shares no layer with characters, cars, units or spidertrons, so they walk and drive over it, but
    -- buildings, rails, belts, trees and dropped items can't overlap it.
    collision_mask = {layers = {item = true, transport_belt = true}},
    render_layer = "lower-object-above-shadow",
    picture = util.empty_sprite(),
    map_color = {tint.r, tint.g, tint.b},
    allow_copy_paste = false,
    remove_decoratives = "true"
  }
end

data:extend({
  sheet("blue", "body"),
  sheet("blue", "glow", {blend_mode = "additive", draw_as_glow = true}),
  sheet("orange", "body"),
  sheet("orange", "glow", {blend_mode = "additive", draw_as_glow = true}),
  portal_entity("blue"),
  portal_entity("orange"),
  {
    -- Never placed. Used with can_place_entity / find_non_colliding_position to ask "could a portal open
    -- here?". It collides with buildings, trees, rocks, cliffs, belts, water, lava and space, but shares no
    -- layer with portals, so an old portal never blocks its own replacement.
    type = "simple-entity-with-owner",
    name = constants.probe,
    icon = constants.mod_path .. "/graphics/icons/portal-blue.png",
    icon_size = 64,
    flags = {"placeable-neutral", "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable"},
    hidden = true,
    collision_box = {{-h, -h}, {h, h}},
    collision_mask = {layers = {object = true, water_tile = true, lava_tile = true, empty_space = true, out_of_map = true}},
    picture = util.empty_sprite()
  }
})
