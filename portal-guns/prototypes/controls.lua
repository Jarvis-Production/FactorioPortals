-- "Close my portals" (a keybinding and a shortcut-bar button) and the event other mods can listen to.
local constants = require("scripts.constants")

local icons = constants.mod_path .. "/graphics/icons/"

data:extend({
  {
    type = "custom-event",
    name = constants.teleported_event
  },
  {
    type = "custom-input",
    name = constants.close_input,
    key_sequence = "ALT + P",
    order = "a"
  },
  {
    type = "shortcut",
    name = constants.close_shortcut,
    order = "z[portal-guns]-a[close-portals]",
    action = "lua",
    localised_name = {"shortcut-name." .. constants.close_shortcut},
    associated_control_input = constants.close_input,
    technology_to_unlock = constants.gun_item,
    unavailable_until_unlocked = true,
    style = "blue",
    icon = icons .. "shortcut-close-portals-x56.png",
    icon_size = 56,
    small_icon = icons .. "shortcut-close-portals-x24.png",
    small_icon_size = 24
  }
})
