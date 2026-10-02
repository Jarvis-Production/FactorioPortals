-- The portal gun: a selection tool, so the mouse buttons map exactly to Portal's controls.
--   left click            -> blue portal      (select)
--   right click           -> orange portal    (reverse_select)
--   shift + left click    -> close blue       (alt_select)
--   shift + right click   -> close orange     (alt_reverse_select)
local constants = require("scripts.constants")
local item_sounds = require("__base__.prototypes.item_sounds")

local function selection_mode(color)
  local tint = constants.tint[color]
  return {
    border_color = {tint.r, tint.g, tint.b, 0.8},
    cursor_box_type = "not-allowed",
    mode = {"nothing"}
  }
end

data:extend({
  {
    type = "mouse-cursor",
    name = constants.cursor,
    system_cursor = "crosshair"
  },
  {
    type = "selection-tool",
    name = constants.gun_item,
    icon = constants.mod_path .. "/graphics/icons/portal-gun.png",
    icon_size = 64,
    flags = {"not-stackable"},
    subgroup = "gun",
    order = "z[portal-gun]",
    stack_size = 1,
    inventory_move_sound = item_sounds.weapon_small_inventory_move,
    pick_sound = item_sounds.weapon_small_inventory_pickup,
    drop_sound = item_sounds.weapon_small_inventory_move,
    mouse_cursor = constants.cursor,
    select = selection_mode("blue"),
    alt_select = selection_mode("blue"),
    reverse_select = selection_mode("orange"),
    alt_reverse_select = selection_mode("orange")
  },
  {
    type = "recipe",
    name = constants.gun_item,
    enabled = false,
    energy_required = 10,
    ingredients =
    {
      {type = "item", name = "advanced-circuit", amount = 20},
      {type = "item", name = "battery", amount = 10},
      {type = "item", name = "steel-plate", amount = 10}
    },
    results = {{type = "item", name = constants.gun_item, amount = 1}}
  },
  {
    type = "technology",
    name = constants.gun_item,
    icon = constants.mod_path .. "/graphics/technology/portal-gun.png",
    icon_size = 256,
    prerequisites = {"chemical-science-pack", "battery"},
    effects =
    {
      {type = "unlock-recipe", recipe = constants.gun_item}
    },
    unit =
    {
      count = 200,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      time = 30
    }
  }
})
