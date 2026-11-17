-- Per-call cost of checking a returned value for a Failed table (values design, Lua).
local Failed = {}
local node = setmetatable({}, {})
local function leaf() return node end
local function plain() return leaf() end
local function checked() local r = leaf(); if getmetatable(r) == Failed then return r end; return r end
local N = 5000000
for rnd = 1, 3 do
  local t = {}
  for i, f in ipairs({ plain, checked }) do
    local t0 = os.clock(); for _ = 1, N do f() end; t[i] = (os.clock() - t0) / N * 1e9
  end
  print(string.format("round %d: plain %.1f ns, getmetatable check +%.1f ns", rnd, t[1], t[2] - t[1]))
end
