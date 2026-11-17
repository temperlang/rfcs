-- Cost of today's Lua `x as T orelse panic()` (closure + pcall) against a direct cast.
package.path = arg[1] .. "/?/init.lua;" .. arg[1] .. "/?.lua;" .. package.path
local temper = require("temper-core")
local T = { typename = "x.T" }
local obj = { [temper.type_tag] = { super = { ["x.T"] = true } } }
local n = 2000000
local function viaPcall(at)
  local b
  if not temper.pcall(function() b = temper.cast_to(at, T) end) then error("panic") end
  return b
end
local function direct(at)
  local b = temper.cast_to(at, T)
  return b
end
local function nullcheck(at)
  if at == nil then error("panic") end
  return at
end
for round = 1, 3 do
  for _, pair in ipairs({ { "pcall", viaPcall }, { "direct", direct }, { "nullcheck", nullcheck } }) do
    local f = pair[2]
    local t0 = os.clock()
    for i = 1, n do f(obj) end
    print(round, pair[1], string.format("%.1f ns", (os.clock() - t0) / n * 1e9))
  end
end
