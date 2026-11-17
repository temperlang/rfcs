-- Times failbench's runners: ns per item, min and median of 7 runs after warm-up.
local m = require("failbench")
local N = tonumber(arg[1] or "50000")
local only = tonumber(arg[2] or "-1")
local R = {{"bubble", m.runBubble}, {"null", m.runNull}, {"result", m.runResult},
           {"bubble5", m.runBubble5}, {"null5", m.runNull5}, {"result5", m.runResult5}}
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
