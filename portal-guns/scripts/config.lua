-- Cached runtime-global settings. Settings are part of the synchronised game state, so caching them in a
-- local is deterministic as long as the cache is refreshed in on_init, on_load and when a setting changes.
local constants = require("scripts.constants")

local config = {
  range = 50,
  vehicles = true,
  units = true,
  cross_surface = false,
  labels = true,
}

function config.refresh()
  local global = settings.global
  config.range = global[constants.setting_range].value
  config.vehicles = global[constants.setting_vehicles].value
  config.units = global[constants.setting_units].value
  config.cross_surface = global[constants.setting_cross_surface].value
  config.labels = global[constants.setting_labels].value
end

return config
