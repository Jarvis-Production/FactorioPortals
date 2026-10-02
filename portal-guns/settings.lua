local constants = require("scripts.constants")

data:extend({
  {
    type = "int-setting",
    name = constants.setting_range,
    setting_type = "runtime-global",
    default_value = 50,
    minimum_value = 10,
    maximum_value = 500,
    order = "a"
  },
  {
    type = "bool-setting",
    name = constants.setting_vehicles,
    setting_type = "runtime-global",
    default_value = true,
    order = "b"
  },
  {
    type = "bool-setting",
    name = constants.setting_units,
    setting_type = "runtime-global",
    default_value = true,
    order = "c"
  },
  {
    type = "bool-setting",
    name = constants.setting_cross_surface,
    setting_type = "runtime-global",
    default_value = false,
    order = "d"
  },
  {
    type = "bool-setting",
    name = constants.setting_labels,
    setting_type = "runtime-global",
    default_value = true,
    order = "e"
  }
})
