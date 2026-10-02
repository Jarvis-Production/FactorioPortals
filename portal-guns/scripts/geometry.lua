-- Small vector helpers. Factorio's map: x grows east, y grows south; orientation 0 is north, clockwise.
local geometry = {}

local sqrt, sin, cos, pi = math.sqrt, math.sin, math.cos, math.pi

--- Accepts {x=, y=} or {x, y}.
function geometry.position(p)
  return {x = p.x or p[1], y = p.y or p[2]}
end

function geometry.distance(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  return sqrt(dx * dx + dy * dy)
end

function geometry.normalize(v)
  local length = sqrt(v.x * v.x + v.y * v.y)
  if length < 1e-6 then return nil end
  return {x = v.x / length, y = v.y / length}
end

function geometry.offset(position, direction, length)
  return {x = position.x + direction.x * length, y = position.y + direction.y * length}
end

--- RealOrientation (0..1, clockwise from north) to a unit vector.
function geometry.orientation_vector(orientation)
  local angle = orientation * 2 * pi
  return {x = sin(angle), y = -cos(angle)}
end

--- defines.direction (16 steps in 2.0) to a unit vector.
function geometry.direction_vector(direction)
  return geometry.orientation_vector(direction / 16)
end

function geometry.area_center(area)
  local left_top = geometry.position(area.left_top or area[1])
  local right_bottom = geometry.position(area.right_bottom or area[2])
  return {x = (left_top.x + right_bottom.x) / 2, y = (left_top.y + right_bottom.y) / 2}
end

--- Moves `target` towards `origin` until it is at most `range` away.
function geometry.clamp_to_range(origin, target, range)
  local distance = geometry.distance(origin, target)
  if distance <= range then return target end
  local k = range / distance
  return {x = origin.x + (target.x - origin.x) * k, y = origin.y + (target.y - origin.y) * k}
end

return geometry
