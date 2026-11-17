-- Counts temper.pcall calls (each an `orelse` today), failed pcalls,
-- and temper.bubble calls, per task, on one Markdown file, by call site.
-- Usage: lua count_kelpto_lua.lua LUA_OUT_DIR FILE.md (SITES=TASK lists the top sites)
local out, file = arg[1], arg[2]
package.path = out .. "/?/init.lua;" .. out .. "/?.lua;" .. package.path
local temper = require("temper-core")
local md = require("kelpto-md")

local counts = { pcall = 0, failed = 0, bubble = 0 }
local sites = {}
local real_pcall, real_bubble = temper.pcall, temper.bubble
temper.pcall = function(f, ...)
  counts.pcall = counts.pcall + 1
  local info = debug.getinfo(2, "Sl")
  local key = info.short_src:match("[^/]+/[^/]+$") .. ":" .. info.currentline
  sites[key] = (sites[key] or 0) + 1
  local res = table.pack(real_pcall(f, ...))
  if not res[1] then counts.failed = counts.failed + 1 end
  return table.unpack(res, 1, res.n)
end
temper.bubble = function(...)
  counts.bubble = counts.bubble + 1
  return real_bubble(...)
end

local fh = assert(io.open(file, "rb")); local text = fh:read("a"); fh:close()
local parser = md.MarkdownParser.commonMark
local renderer = md.MarkdownRenderer():withRawHtmlTrusted()
local tasks = {
  parse = function() return parser:parse(text).span.end_ end,
  render = function() return #renderer:render(parser:parse(text)) end,
  walk = function()
    local doc = parser:parse(text)
    local n = 0
    for _, v in ipairs(doc.descendants) do if temper.instance_of(v, md.Heading) then n = n + 1 end end
    return n + #doc.asWritten
  end,
  transform = function()
    local doc = parser:parse(text)
    local editor = doc:editor()
    local edits = 0
    for _, h in ipairs(doc.headings) do
      local level = h.level
      if level < 6 and not (level == 2 and h.style == "setext") then
        editor:setLevel(h, level + 1); edits = edits + 1
      end
    end
    counts.edits = edits
    return #editor:toDocument().asWritten
  end,
}
local lines = select(2, text:gsub("\n", ""))
print(string.format("file %s bytes %d lines %d", file:match("[^/]+$"), #text, lines))
for _, name in ipairs({ "parse", "render", "walk", "transform" }) do
  counts.pcall, counts.failed, counts.bubble, counts.edits = 0, 0, 0, nil
  sites = {}
  local t0 = os.clock()
  tasks[name]()
  local t = os.clock() - t0
  local nsites = 0
  for _ in pairs(sites) do nsites = nsites + 1 end
  print(string.format("%-9s pcall %8d failed %d bubble %d sites %d edits %s time_s %.3f",
    name, counts.pcall, counts.failed, counts.bubble, nsites, tostring(counts.edits), t))
  if os.getenv("SITES") == name then
    local keys = {}
    for k in pairs(sites) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return sites[a] > sites[b] end)
    for i = 1, math.min(25, #keys) do print("   ", sites[keys[i]], keys[i]) end
  end
end
