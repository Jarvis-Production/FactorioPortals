-- Benchmark map for tools/run_tests.py --perf: PAIRS portal pairs (one per made-up owner) on a cleared patch of
-- grass, each with a character standing next to its blue portal. Marker mods written by the runner change it:
--   portal-guns-perf-unlinked  only the blue portals open, so nothing is linked or scanned (the baseline)
--   portal-guns-perf-nochars   no characters, so every portal has nothing nearby (idle)
local PAIRS = 100

script.on_init(function()
  local s = game.surfaces.nauvis
  s.always_day = true
  s.peaceful_mode = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
  local area = {{-200, -200}, {200, 200}}
  for _, entity in pairs(s.find_entities_filtered{area = area}) do entity.destroy() end
  local tiles = {}
  for x = -200, 199 do
    for y = -200, 199 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end
  end
  s.set_tiles(tiles)
  for i = 1, PAIRS do
    local x, y = -180 + (i % 10) * 36, -180 + math.floor(i / 10) * 30
    assert(remote.call("portal-guns", "open_portal", 5000 + i, "blue", "nauvis", {x, y}))
    if not script.active_mods["portal-guns-perf-unlinked"] then
      assert(remote.call("portal-guns", "open_portal", 5000 + i, "orange", "nauvis", {x + 18, y}))
    end
    if not script.active_mods["portal-guns-perf-nochars"] then
      s.create_entity{name = "character", position = {x - 2, y}, force = "player"}
    end
  end
  print("PERF pairs=" .. PAIRS .. " portals=" .. #remote.call("portal-guns", "get_portals"))
end)
