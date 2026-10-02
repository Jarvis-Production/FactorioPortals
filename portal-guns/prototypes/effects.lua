-- Shots (visual projectiles) and one-shot effects (explosions carrying a flash, a light and a sound).
local constants = require("scripts.constants")
local sounds = require("prototypes.sounds")

local graphics = constants.mod_path .. "/graphics/entity/"

local function shot(color)
  local tint = constants.tint[color]
  return {
    type = "projectile",
    name = constants.shot[color],
    flags = {"not-on-map"},
    hidden = true,
    -- Purely visual: no acceleration (so arrival time is distance / speed), no collision box (so it can't hit
    -- anything on the way) and no action. The portal is opened by script when the shot arrives.
    acceleration = 0,
    rotatable = true,
    height = constants.shot_height,
    animation =
    {
      layers =
      {
        {
          filename = graphics .. "shot/shot-glow.png",
          priority = "high",
          width = 48,
          height = 128,
          scale = 0.5,
          tint = tint,
          blend_mode = "additive",
          draw_as_glow = true
        },
        {
          filename = graphics .. "shot/shot-core.png",
          priority = "high",
          width = 48,
          height = 128,
          scale = 0.5,
          blend_mode = "additive",
          draw_as_glow = true
        }
      }
    },
    light = {intensity = 0.8, size = 7, color = tint}
  }
end

-- `sheet` is "ring-burst" (an expanding ring with a flash) or "sparks"; both are white 4x4 sheets of 128x128
-- frames that get tinted per colour.
local function effect(name, color, params)
  local tint = constants.tint[color]
  return {
    type = "explosion",
    name = name,
    flags = {"not-on-map"},
    hidden = true,
    render_layer = params.render_layer or "explosion",
    animations =
    {
      {
        filename = graphics .. "effects/" .. params.sheet .. ".png",
        priority = "high",
        width = 128,
        height = 128,
        frame_count = 16,
        line_length = 4,
        scale = params.scale,
        tint = tint,
        blend_mode = "additive",
        draw_as_glow = true,
        animation_speed = params.animation_speed or 1,
        run_mode = params.run_mode or "forward"
      }
    },
    sound = params.sound,
    light = {intensity = params.light_intensity or 0.9, size = params.light_size or 8, color = tint},
    light_intensity_factor_initial = 1,
    light_intensity_factor_final = 0,
    light_size_factor_initial = 1,
    light_size_factor_final = 0.6
  }
end

local prototypes = {}
for _, color in pairs(constants.colors) do
  table.insert(prototypes, shot(color))
  table.insert(prototypes, effect(constants.muzzle[color], color, {
    sheet = "ring-burst", scale = 0.3, animation_speed = 1.5, sound = sounds.fire[color],
    light_intensity = 0.7, light_size = 4
  }))
  table.insert(prototypes, effect(constants.open_effect[color], color, {
    sheet = "ring-burst", scale = 0.85, animation_speed = 0.9, sound = sounds.open, light_size = 10
  }))
  table.insert(prototypes, effect(constants.close_effect[color], color, {
    sheet = "ring-burst", scale = 0.85, animation_speed = 1.2, run_mode = "backward", sound = sounds.close,
    light_intensity = 0.6, light_size = 8
  }))
  table.insert(prototypes, effect(constants.fizzle_effect[color], color, {
    sheet = "sparks", scale = 0.6, animation_speed = 0.8, sound = sounds.fizzle, light_intensity = 0.6,
    light_size = 5
  }))
  table.insert(prototypes, effect(constants.teleport_effect[color], color, {
    sheet = "ring-burst", scale = 0.55, animation_speed = 1.4, sound = sounds.enter, light_size = 7
  }))
end
data:extend(prototypes)
