-- Names and tunables shared by the data stage and the runtime (control) stage.
local constants = {}

constants.mod_name = "portal-guns"
constants.mod_path = "__portal-guns__"

constants.gun_item = "portal-gun"
constants.cursor = "portal-guns-crosshair"
constants.probe = "portal-guns-placement-probe"
constants.close_input = "portal-guns-close-portals"
constants.close_shortcut = "portal-guns-close-portals"
-- Raised after something went through a portal; other mods subscribe with script.on_event(<this name>, ...).
constants.teleported_event = "portal-guns-on-teleported"

-- The two portal colours (blue is the primary one, fired with the left mouse button).
constants.colors = {"blue", "orange"}

constants.tint = {
  blue = {r = 0.16, g = 0.58, b = 1.00},
  orange = {r = 1.00, g = 0.50, b = 0.08},
}

constants.other_color = {blue = "orange", orange = "blue"}

-- Prototype names per colour.
constants.portal_entity = {blue = "portal-guns-portal-blue", orange = "portal-guns-portal-orange"}
constants.portal_body_animation = {blue = "portal-guns-portal-blue-body", orange = "portal-guns-portal-orange-body"}
constants.portal_glow_animation = {blue = "portal-guns-portal-blue-glow", orange = "portal-guns-portal-orange-glow"}
constants.shot = {blue = "portal-guns-shot-blue", orange = "portal-guns-shot-orange"}
constants.muzzle = {blue = "portal-guns-muzzle-blue", orange = "portal-guns-muzzle-orange"}
constants.open_effect = {blue = "portal-guns-open-blue", orange = "portal-guns-open-orange"}
constants.close_effect = {blue = "portal-guns-close-blue", orange = "portal-guns-close-orange"}
constants.fizzle_effect = {blue = "portal-guns-fizzle-blue", orange = "portal-guns-fizzle-orange"}
constants.teleport_effect = {blue = "portal-guns-teleport-blue", orange = "portal-guns-teleport-orange"}
constants.denied_sound = "portal-guns-denied"

-- Geometry, in tiles.
constants.portal_radius = 0.9        -- an entity whose centre comes this close to a portal goes through
constants.portal_half_size = 0.85    -- half of the portal's square footprint (collision box)
constants.portal_min_spacing = 1.8   -- two portals can't be closer than this (centre to centre)
constants.exit_offset = 0.5          -- how far ahead of the exit portal's centre things come out
constants.nudge_radius = 2.0         -- a blocked shot may land this far from where it was aimed
constants.exit_search_radius = 2.5   -- how far from the exit we look for room for the traveller
-- A linked portal only scans every tick while something that could use it is within wake_radius; that is
-- re-checked every wake_interval ticks (16 tiles in 10 ticks covers anything up to 1.5 tiles per tick).
constants.wake_radius = 16
constants.wake_interval = 10

-- Shots.
constants.shot_speed = 2.0           -- tiles per tick, constant (the projectile has no acceleration)
constants.shot_height = 0.6          -- how high above the ground the shot flies
constants.shot_cooldown = 15         -- ticks between two shots of the same player
constants.open_ticks = 12            -- length of the "portal opens" grow animation

-- Things that can go through portals.
constants.character_types = {character = true}
constants.vehicle_types = {car = true, ["spider-vehicle"] = true}
constants.unit_types = {unit = true, ["spider-unit"] = true}
constants.traveller_types = {"character", "car", "spider-vehicle", "unit", "spider-unit"}
-- LuaControl.teleport only moves these to another surface (anything else throws).
constants.cross_surface_types = {character = true, car = true, ["spider-vehicle"] = true}

-- Mod settings.
constants.setting_range = "portal-guns-range"
constants.setting_vehicles = "portal-guns-teleport-vehicles"
constants.setting_units = "portal-guns-teleport-units"
constants.setting_cross_surface = "portal-guns-cross-surface"
constants.setting_labels = "portal-guns-owner-labels"

return constants
