-- Counts temper.pcall calls (`orelse` today) and bubbles per Wherewith
-- workload, and times each untraced. Usage: lua count_wherewith_lua.lua LUA_OUT_DIR
local out = arg[1]
package.path = out .. "/?/init.lua;" .. out .. "/?.lua;" .. package.path
local temper = require("temper-core")
local ww = require("wherewith")
local Dialect, PS, QB = ww.Dialect, ww.PlaceholderStyle, ww.QueryBuilder

local counting = false
local c = { pcall = 0, failed = 0, bubble = 0 }
local real_pcall, real_bubble = temper.pcall, temper.bubble
temper.pcall = function(f, ...)
  if counting then c.pcall = c.pcall + 1 end
  local res = table.pack(real_pcall(f, ...))
  if counting and not res[1] then c.failed = c.failed + 1 end
  return table.unpack(res, 1, res.n)
end
temper.bubble = function(...)
  if counting then c.bubble = c.bubble + 1 end
  return real_bubble(...)
end

local function example()
  local b = QB(Dialect.common)
  b:appendSafe('SELECT title, "dueDate" FROM tasks WHERE title LIKE ')
  b:appendString("Launch")
  b:appendSafe([[ || '%' ESCAPE '!' ORDER BY "dueDate" NULLS LAST LIMIT ]])
  b:appendInt(20)
  b:appendSafe(" OFFSET ")
  b:appendInt(40)
  return b:build()
end
local function bigger()
  local b = QB(Dialect.common)
  b:appendSafe("SELECT u.id, u.name, count(o.id) AS orders, sum(o.total) AS spent "
    .. "FROM users AS u LEFT JOIN orders AS o ON o.user_id = u.id WHERE u.created_at >= ")
  b:appendString("2026-01-01")
  b:appendSafe(" AND (u.status = ")
  b:appendString("active")
  b:appendSafe(" OR u.status = ")
  b:appendString("trial")
  b:appendSafe(") AND u.id NOT IN (SELECT user_id FROM bans) GROUP BY u.id, u.name HAVING count(o.id) > ")
  b:appendInt(2)
  b:appendSafe(" ORDER BY spent DESC NULLS LAST LIMIT ")
  b:appendInt(50)
  return b:build()
end
local function render4(q)
  q:render(Dialect.sqlite, PS.question)
  q:render(Dialect.postgres, PS.dollarNumbered)
  q:render(Dialect.mysql, PS.percentS)
  q:render(Dialect.duckdb, PS.dollarNumbered)
end
local function syntax_error()
  local b = QB(Dialect.common)
  b:appendSafe("SELECT a, b FROM t WHERE a = (b + ")
  return b.templateProblem
end
local q, qb = example(), bigger()
local jobs = {
  { "example: build", example },
  { "example: render x4", function() render4(q) end },
  { "bigger: build", bigger },
  { "bigger: render x4", function() render4(qb) end },
  { "syntax error", syntax_error },
}
for _, job in ipairs(jobs) do
  local name, fn = job[1], job[2]
  fn()
  c.pcall, c.failed, c.bubble = 0, 0, 0
  counting = true; fn(); counting = false
  local n, t0 = 0, os.clock()
  while os.clock() - t0 < 1 do fn(); n = n + 1 end
  print(string.format("%-20s %7.0f us/op  pcall %d failed %d bubble %d", name, (os.clock() - t0) / n * 1e6, c.pcall, c.failed, c.bubble))
end
