-- Times kelpto-md parsing one file in Lua: min of N parses.
-- Usage: lua time_kelpto_lua.lua LUA_OUT_DIR FILE.md [N]
package.path = arg[1] .. "/?/init.lua;" .. arg[1] .. "/?.lua;" .. package.path
local md = require("kelpto-md")
local fh = assert(io.open(arg[2], "rb")); local text = fh:read("a"); fh:close()
local parser = md.MarkdownParser.commonMark
for i = 1, 2 do parser:parse(text) end
local best = math.huge
for i = 1, tonumber(arg[3] or 5) do
  collectgarbage("collect")
  local t0 = os.clock(); parser:parse(text); local t = os.clock() - t0
  if t < best then best = t end
  io.write(string.format("%.3f ", t))
end
print(string.format("min %.3f", best))
