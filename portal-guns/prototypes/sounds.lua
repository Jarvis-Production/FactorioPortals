-- Sound definitions. The same files are used as inline `Sound`s (explosions) and as SoundPrototypes
-- (played from script with LuaSurface.play_sound / LuaPlayer.play_sound).
local constants = require("scripts.constants")

local sounds = {}

local function file(name)
  return constants.mod_path .. "/sound/" .. name .. ".ogg"
end

-- Many biters walking through a portal at once must not turn into a wall of noise.
local busy_aggregation = {max_count = 3, remove = true, count_already_playing = true}

sounds.fire = {
  blue = {filename = file("portal-fire-blue"), volume = 0.55, aggregation = busy_aggregation},
  orange = {filename = file("portal-fire-orange"), volume = 0.55, aggregation = busy_aggregation},
}
sounds.open = {filename = file("portal-open"), volume = 0.6, aggregation = busy_aggregation}
sounds.close = {filename = file("portal-close"), volume = 0.5, aggregation = busy_aggregation}
sounds.fizzle = {filename = file("portal-fizzle"), volume = 0.6, aggregation = busy_aggregation}
sounds.enter = {filename = file("portal-enter"), volume = 0.5, aggregation = busy_aggregation}
sounds.denied = {filename = file("portal-denied"), volume = 0.5}

data:extend({
  {
    type = "sound",
    name = constants.denied_sound,
    category = "gui-effect",
    filename = sounds.denied.filename,
    volume = sounds.denied.volume
  }
})

return sounds
