# Lua

**Hand-written illustration, not generated or run.** The worked example
from [the README](README.md#the-example), as the Lua backend might emit
it. Today the parser raises a table whose `tostring` is "Bubble", the
fallback `orelse` (a `pcall`) catches every error, Lua runtime errors
included, and the reason comes only from `selectProblem`.

## Failure types

Lua has no classes or required error type; anything can be raised. A
failure type is a metatable, a library's failures share a base through
`__index`, and `__tostring` gives the message (`print`, `tostring`, and
the standalone interpreter's error report all use it).

```lua
local WherewithError = { kind = "WherewithError" }
WherewithError.__index = WherewithError
WherewithError.__tostring = function(e) return e.message end

--- True if `e` is a failure from Wherewith, or of the given type.
function WherewithError.is(e, class)
  local mt = type(e) == "table" and getmetatable(e)
  while mt do
    if mt == (class or WherewithError) then return true end
    mt = getmetatable(mt) and getmetatable(mt).__index
  end
  return false
end

local SqlProblem = setmetatable({ kind = "SqlProblem" }, { __index = WherewithError })
SqlProblem.__index = SqlProblem
SqlProblem.__tostring = WherewithError.__tostring

---@param text string
---@param word integer
---@param message string?
---@param cause any
function SqlProblem.new(text, word, message, cause)
  return setmetatable({
    text = text, word = word,
    message = message or (text .. " at word " .. word),
    cause = cause,
  }, SqlProblem)
end
```

No category: Lua has no standard error types to join. Equality is
identity, as for any table.

## Declared failures

Failures are raised with `error(problem)`. A Temper `orelse` becomes a
closure in `pcall` that checks the type and re-raises anything else, so
Lua runtime errors and panics pass through (today they don't). That
closure and `pcall` are the 5 to 10 percent success-path cost
[measured](../claude-findings.md#2-speed).

```lua
function Parser:select()
  self:keyword("SELECT")
  local columns = { self:name("a column") }
  while self:peek() == "," do
    self.pos = self.pos + 1
    columns[#columns + 1] = self:name("a column")
  end
  self:keyword("FROM")
  local tbl = self:name("a table")
  if self:peek() ~= nil then
    error(self:problem("expected the end"))
  end
  return Select.new(columns, tbl)
end

function Parser:need(message)
  local w = self:peek()
  if w == nil then error(self:problem(message)) end
  return w
end

function Parser:problem(text)
  return SqlProblem.new(text, self.pos + 1)
end

--- Parses `SELECT a, b FROM t`. Raises a `SqlProblem` if it can't.
function M.parseSelect(text)
  return Parser.new(split(text, " ")):select()
end
```

## Failures as values

Lua's own idiom for expected failures is `nil, message` (as `io.open`
does), so the value form is the host form: no wrapper.

```lua
function Parser:select()
  local ok, problem = self:keyword("SELECT")
  if not ok then return nil, problem end
  local first; first, problem = self:name("a column")
  if first == nil then return nil, problem end
  local columns = { first }
  while self:peek() == "," do
    self.pos = self.pos + 1
    local more; more, problem = self:name("a column")
    if more == nil then return nil, problem end
    columns[#columns + 1] = more
  end
  -- … FROM and the table the same way …
  if self:peek() ~= nil then return nil, self:problem("expected the end") end
  return Select.new(columns, tbl)
end

--- Parses `SELECT a, b FROM t`. Returns nil and a `SqlProblem` if it can't.
function M.parseSelect(text)
  return Parser.new(split(text, " ")):select()
end
```

A function whose success value can itself be `nil` (a result of `T?`)
needs callers to test the second value rather than the first; the
generated code does, and its docs say so.

**Which types can be failures (meeting point 6).** With any type allowed,
a failure can be a plain string, which is the most traditional Lua
`nil, message`; a class failure is a table with `__tostring`. Nothing
needs wrapping. **Combined (the recommendation):** the same output, with
every exported failure a `SqlProblem`-style table.

## Host caller

```lua
local wherewith = require("wherewith")

-- Declared failures: pcall, then check the type.
local ok, result = pcall(wherewith.parseSelect, "SELECT a FROM")
if not ok then
  if wherewith.WherewithError.is(result, wherewith.SqlProblem) then
    print(tostring(result) .. " (word " .. result.word .. ")")
  else
    error(result, 0)  -- not ours: re-raise
  end
end

-- Failures as values:
local sel, problem = wherewith.parseSelect("SELECT a FROM")
if not sel then
  print(tostring(problem) .. " (word " .. problem.word .. ")")
end

-- Under values, a caller that wants an error raised:
local sel2 = assert(wherewith.parseSelect("SELECT a FROM"))  -- values
```

`assert(v, message)` raises its second argument as the error object when
the first is `nil` (Lua 5.3 and later accept any value there), so under
values, `assert(f(…))` is the one-word throwing form Lua programmers
already use.
