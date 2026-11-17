-- What a compiler-known result type might cost in Lua, hand-written beside
-- failbench's generated `bubble` and `null` runners. ns per item, min and
-- median of 7 runs after warm-up. Arguments: n, rate in per mille, variant.
--
--   value  success as the plain value, failure as a table with a
--          metatable marking it failed (checked with getmetatable)
--
-- Each has a depth-5 form passing the failure up four more functions.
local m = require("failbench")
local N = tonumber(arg[1] or "50000")
local only = tonumber(arg[2] or "-1")

local Failed = {}
local function failed(input) return setmetatable({error = {input = input}}, Failed) end

-- Written as the generated code is (its arithmetic helpers, its inputAt,
-- while loops), so only the failure handling differs from `null`.
local temper = require("temper-core")
local inputAt = m.inputAt

local function stepValue(x)
  if x < 0 then return failed(x) end
  return temper.int32_add(temper.int32_mul(x, 3), 1)
end
local function v2(x)
  local r = stepValue(x)
  if getmetatable(r) == Failed then return r end
  return temper.int32_add(r, 1)
end
local function v3(x)
  local r = v2(x)
  if getmetatable(r) == Failed then return r end
  return temper.int32_add(r, 1)
end
local function v4(x)
  local r = v3(x)
  if getmetatable(r) == Failed then return r end
  return temper.int32_add(r, 1)
end
local function v5(x)
  local r = v4(x)
  if getmetatable(r) == Failed then return r end
  return temper.int32_add(r, 1)
end
local function runValue(n, failMille)
  local sum = 0
  local i = 0
  while i < n do
    local x = inputAt(i, failMille)
    local r = stepValue(x)
    sum = temper.int32_add(sum, getmetatable(r) == Failed and 0 or r)
    i = temper.int32_add(i, 1)
  end
  return sum
end
local function runValue5(n, failMille)
  local sum = 0
  local i = 0
  while i < n do
    local x = inputAt(i, failMille)
    local r = v5(x)
    sum = temper.int32_add(sum, getmetatable(r) == Failed and 0 or r)
    i = temper.int32_add(i, 1)
  end
  return sum
end

local R = {{"bubble", m.runBubble}, {"null", m.runNull}, {"value", runValue},
           {"bubble5", m.runBubble5}, {"null5", m.runNull5}, {"value5", runValue5}}
for _, pct in ipairs({0, 1, 10, 100}) do
  if only < 0 or pct == only then
    for _, r in ipairs(R) do
      local name, f = r[1], r[2]
      if arg[3] == nil or arg[3] == name then
        for _ = 1, 2 do f(N, pct) end
        local ts = {}
        for i = 1, 7 do local t = os.clock(); f(N, pct); ts[i] = (os.clock() - t) * 1e9 / N end
        table.sort(ts)
        print(string.format("lua %d %s %.1f %.1f", pct, name, ts[1], ts[4]))
      end
    end
  end
end
for _, r in ipairs(R) do
  local want = r[1]:sub(-1) == "5" and m.runNull5(2000, 10) or m.runNull(2000, 10)
  assert(r[2](2000, 10) == want, r[1])
end
