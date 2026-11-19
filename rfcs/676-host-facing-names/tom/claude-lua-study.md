# Temper libraries from a Lua user's point of view

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

## The question

Does a Temper library look and behave like a Lua library to someone who
writes Lua, and what would make it more so?

**Short answer:** the shape is already close. Modules are tables,
classes are callable, properties read like fields, methods take `:`,
lists are ordinary 1-based tables, and callbacks are plain functions.
Where it falls short is at the edges a Lua user touches first: no-value
is a truthy `temper.null`, failures are a table whose message is
usually just "Bubble", the rockspecs don't install anything `require`
can find, the code doesn't load on PUC Lua 5.1 though the rockspecs
say it does, numbers and maps passed in from Lua aren't checked or
converted, and LuaLS can't check constructor calls. Most of these fixes are small; three are design questions
for this RFC and for [#164](../../164-exceptions/README.md).

## How this was studied

- Built the six showcase libraries (Argmas, Chromarite, Hrefine,
  Kelpto, Ordable, and Wherewith) with Temper's compiler
  (`temper build -b lua`, temperlang/temper at `b347b34f`, runtime
  `0.7.0.alpha.0.265`), and ran each library's Lua tour on Lua 5.4.6,
  LuaJIT 2.1, and PUC Lua 5.1.5.
- Wrote a small probe library (about 80 lines of Temper) and Lua
  scripts that use it the way a Lua user would. Every snippet below was
  run; output is quoted as printed.
- Read the Lua backend (`crates/temper-be-lua`), its runtime
  (`crates/temper-be-lua/runtime/temper-core/init.lua`), and
  `notes/api-compat.md`, whose item 8 already proposes returning `nil`.
- Checked user scripts with LuaLS 3.19.2 (`lua-language-server
  --check`), as an editor would, against the generated annotations and
  hand-edited variants of them (section 6; rebuilt at Temper
  `13dc5669`, same output for these cases).
- Version claims were checked against the source at each release tag
  of [lua/lua](https://github.com/lua/lua) (5.1 to 5.5.0) and against
  LuaJIT's source; LuaLS behavior against its source at tag
  [3.19.2](https://github.com/LuaLS/lua-language-server/tree/3.19.2).
  Library comparisons quote source at release tags: Penlight 1.15.0,
  busted 2.3.0 and luassert 1.9.0, LDoc 1.5.0, LPeg 1.1.0, and lua-cjson
  2.1.0.20. LuaSocket, LuaRocks 3.11.1, and lua-stdlib were checked
  against their docs; Programming in Lua, dkjson, and lua-argparse only
  through search excerpts, since their sites weren't reachable.

## 1. Values

### Null

**Today.** Temper's null is `temper.null`, a table, so it's truthy.
Nullable results return it; nullable parameters accept it or `nil`.

```lua
local u = hrefine.parseUrl("https://example.com/")
print(u.portNumber, u.portNumber and "truthy" or "falsy")
--> temper.null   truthy
if hrefine.Url.parse("setup.html") then print("passes!") end
--> passes!
```

Five of the six tours import the runtime, mostly to undo this:

```lua
-- Temper's runtime gives temper.null, not nil, for no value. It's a table,
-- so it's truthy: `if Url.parse(input) then` passes for every input. So
-- null_to_nil turns it into nil, and a policy's check has `passed`.
local temper = require("temper-core")
local null_to_nil = temper.null_to_nil
```

Inside lists, `temper.null` keeps the sequence intact, which `nil`
can't: `probe.nullables()` gives `{ "a", temper.null, "c" }`, `#` is 3.

**What Lua users expect.** `nil` for "no value" from a function or
field, so `if x then` and `x or default` work. A sentinel only where
`nil` can't go: inside arrays and maps. That is exactly lua-cjson's
`cjson.null`, a `NULL` light userdata, used because "In Lua, setting
"t[k] = nil" will delete k from the table"
([lua_cjson.c#L1889-L1892](https://github.com/openresty/lua-cjson/blob/2.1.0.20/lua_cjson.c#L1889-L1892)),
and dkjson's [`json.null`](http://dkolf.de/dkjson-lua/) (dkjson even
lets the caller pick the value used for null when decoding). Note that
`cjson.null` is truthy too: Lua users live with a truthy sentinel, but
only inside decoded data, never as a function's "no result".

**Options.**

| Option | Gains | Costs |
|---|---|---|
| A. Keep `temper.null` everywhere | No change; one rule | Every Lua user meets the truthy trap; tours need the runtime |
| B. `nil` at scalar boundaries (results, fields, getters, parameters), `temper.null` only inside lists and maps (api-compat item 8) | `if x then` works; matches lua-cjson | Breaking; two representations; generated code converts at each exported function and getter |
| C. `nil` everywhere, lists carry an explicit length (`n` field, as [`table.pack`](https://www.lua.org/manual/5.4/manual.html#pdf-table.pack)) | Purest Lua | `#` and `ipairs` stop at holes, so every user loop breaks; far too costly |

B is the recommendation. The conversion is cheap where it's needed:
only exported functions, methods, and getters whose Temper type is
nullable need `if r == temper.null then return nil end`, and inside
the library nothing changes. Lists and maps keep the sentinel, which
should then be exported by the library itself (`hrefine.null`), so
users never need `require("temper-core")`.

### Lists

**Today.** A `List` is a plain 1-based table, so `#`, `ipairs`, and
`table.concat` work, and Lua tables go straight in. That's the best
part of the mapping. Two gaps:

- **Indexes in the API are Temper's, from 0.** Chromarite's tour:
  `for i = 0, color.length - 1 do ... color:get(i, j)`. A Lua user
  reaching for `color:get(1, 1)` gets the second row, or
  `index 3 out of bounds for length 3` (the flat list's index, not the
  one passed).
- **Returned lists alias library state.** A Temper `List` is
  immutable, but the table returned is the library's own:

  ```lua
  local l = probe.fixedList(); l[1] = "changed"; table.insert(l, "c")
  print(probe.fixedFirst(), #probe.fixedList())  --> changed  3
  ```

  JS freezes such arrays.

**What Lua users expect.** 1-based positions everywhere (`string.find`,
`table.insert`, LPeg's `match`, which "returns the index in the subject
of the first character after the match"
([lpeg.html#L161](https://github.com/roberto-ieru/LPeg/blob/v1.1.0/lpeg.html#L161)),
and Penlight's `List:slice`, where negative indexes count from the end
([List.lua#L231-L238](https://github.com/lunarmodules/Penlight/blob/1.15.0/lua/pl/List.lua#L231-L238)));
"counted from 0" in a Lua API reads as a port.

**Options.** Indexes: (a) document them as 0-based (cheap, still
foreign); (b) a way for a library to mark index parameters and results,
shifted by one for Lua (a question for this RFC; Temper has no "index
type" to infer it from). Aliasing: copy lists the library keeps (fields
and module-level values) when returning them; a read-only proxy would
break `#` and `ipairs` on 5.1 and LuaJIT, which lack `__len` for
tables ([5.1's `len` event](https://www.lua.org/manual/5.1/manual.html#2.8);
LuaJIT has it only when built with
[`LUAJIT_ENABLE_LUA52COMPAT`](https://luajit.org/extensions.html)).

### Maps

**Today.** A `Map` is a table with two hidden keys: the key order and
a type tag. Results from Temper work through the runtime, but
`pairs` shows the internals, and plain Lua tables passed in break
partway:

```lua
for k, v in pairs(probe.makeMap()) do print(k, v) end
--> a 1 / b 2 / table: 0x…  table: 0x… / temper.type_tag  Map
probe.mapGet({ a = 1 }, "a")  --> 1
probe.mapSize({ a = 1 })
--> temper-core/init.lua:1198: attempt to get length of a nil value (field '?')
```

LuaLS types the parameter as `table<string, integer>`, so the editor
accepts the call that crashes. Argmas's tour works around it: "setMessages
takes Temper's map type, so a loop over a table is simpler."

**What Lua users expect.** A map is a table: `pairs` gives its entries,
and any table can be passed in. Order isn't expected (Lua's
[`next`](https://www.lua.org/manual/5.4/manual.html#pdf-next) order is
unspecified). Libraries that keep order do it beside the entries:
dkjson takes it as an encoder option ([`keyorder`](http://dkolf.de/dkjson-lua/))
rather than storing it in the table. Penlight's `OrderedMap` makes the
same trade as Temper: it does `rawset(self,'_keys',List())` on the
instance and sets `OrderedMap.__pairs = OrderedMap.iter`
([OrderedMap.lua#L25](https://github.com/lunarmodules/Penlight/blob/1.15.0/lua/pl/OrderedMap.lua#L25),
[#L147](https://github.com/lunarmodules/Penlight/blob/1.15.0/lua/pl/OrderedMap.lua#L147)),
so `pairs` hides `_keys` on 5.2+ but shows it on 5.1 and LuaJIT.

**Options.** (a) Accept plain tables wherever a `Map` is taken,
building the key order on first use; (b) move the order and tag into a
metatable or weak side table, with an ordered `__pairs`. LuaJIT honors
`__pairs` only when built with `LUAJIT_ENABLE_LUA52COMPAT`
(`if ((LJ_52 || tviscdata(o)) && !tvisnil(mo))`,
[lib_base.c#L91](https://github.com/LuaJIT/LuaJIT/blob/8ca762976ebc85ad9bde3e15f147a7e326e0dd01/src/lib_base.c#L91)),
so there and on 5.1 a side table still keeps `pairs` to the entries,
unordered. Together they make maps ordinary tables that keep order.

### Strings

**Today.** Lua strings, UTF-8, untouched; Temper's `StringIndex` is a
1-based byte offset, so it lines up with `string.sub`. Right as is.
Libraries that report positions (Hrefine's errors) count code points
from 0, the same in every language, while a Lua user assumes bytes
from 1 (`string.find`, LPeg's `lpeg.Cp()`). lua-cjson converts on the
way out: "token->index is 0 based, display starting from 1"
([lua_cjson.c#L1747-L1749](https://github.com/openresty/lua-cjson/blob/2.1.0.20/lua_cjson.c#L1747-L1749)).
**Option:** say so in each such API's docs, or shift positions that
reach messages; it's the library's choice, not Temper's.

### Int and Float64

**Today.** `Int` is 32-bit with wraparound, `Float64` a Lua float.
Neither is checked or converted at the boundary, and Lua 5.3+'s
integer subtype leaks through:

```lua
probe.square(3)            --> 9         (an integer, from Float64 * Float64)
probe.square(1 << 40)      --> 0         (integer multiply wrapped; 1.2e24 expected)
probe.addInts(1 << 40, 0)  --> 0         (silently truncated to 32 bits)
probe.addInts("2", 1)      --> 3         (Lua's string coercion)
probe.addInts(1.5, 1)      --> 5.4: "intnew.lua:68: number (local 'n') has no
                               integer representation"; LuaJIT and 5.1: 2.5
```

`Int64` differs by version: a Lua integer on 5.3+, a `{hi, lo}` table
with metamethods on 5.1 and LuaJIT, so the same call returns different
types:

```lua
local v = probe.parse64("9007199254740993")
print(type(v), v == 9007199254740993)
--> 5.4: number true      LuaJIT: table false
```

LuaLS is told `---@return integer` either way.

**What Lua users expect.** "A number" is the default; integers matter
mainly as table keys and in `string.format("%d")`. Libraries that need
integers check with [`math.type`](https://www.lua.org/manual/5.4/manual.html#pdf-math.type)
(new in 5.3.0, [lmathlib.c#L278](https://github.com/lua/lua/blob/v5.3.0/lmathlib.c#L278))
or `math.floor(x) == x` and raise
`bad argument #1 to 'f' (number has no integer representation)`, the
standard library's own message (from
[`luaL_checkinteger`](https://www.lua.org/manual/5.4/manual.html#luaL_checkinteger)).
On LuaJIT, 64-bit integers are `int64_t` cdata (`1LL`) via the
[FFI](https://luajit.org/ext_ffi_semantics.html), which is what LuaJIT
users would recognize.

**Options.**

- Float64 parameters: `x + 0.0` at exported entry points, one addition
  per call, fixes both the wrap and the integer results.
- Int parameters: check integrality and 32-bit range at exported entry
  points, with `bad argument` errors; internal calls skip it.
- Int64 on LuaJIT: `int64_t` cdata instead of tables, matching what
  LuaJIT users know and much faster; PUC 5.1 and 5.2 keep tables.

**Booleans** are Lua booleans both ways; the only trap is a `Boolean?`
result of `temper.null`, which reads as true.

## 2. API shape

### Modules and require paths

**Today.** `require("ordable")` returns a plain table of exports. A
library with several modules is required as `"lib/module"`
(`require("std/regex")`), and Kelpto ships as five rocks
(`kelpto-md`, `kelpto-html`, …). Libraries with tests also export a
`["$test"]` key holding internals, visible to `pairs`.

**What Lua users expect.** Dotted names
([`socket.http`](https://lunarmodules.github.io/luasocket/http.html),
[`pl.stringx`](https://lunarmodules.github.io/Penlight/)), which the
default searchers turn into directories
([`package.searchpath`](https://www.lua.org/manual/5.4/manual.html#pdf-package.searchpath))
and [`build.modules`](https://github.com/luarocks/luarocks/blob/main/docs/rockspec_format.md)
keys use ("in the format normally used by the require() function");
slash names work only because the default searchers pass them through.
Rock names may have hyphens (`lua-cjson`), module names rarely
(`cjson`). And a top-level `std` module clashes with
[lua-stdlib](https://lua-stdlib.github.io/lua-stdlib/)'s `std.*`.

**Options.** Dotted module names (`kelpto.md`), breaking for
multi-module libraries only. Rename the `std` rock and module
(`temper-std` / `temper_std`, as in Python). Drop `$test` from the
public table (tests can `require` an `-internal` module).

### Functions and methods

**Today.** Module functions and statics use `.` (`Color.fromList`),
instance methods `:`, exactly as LuaSocket's
[`client:send`](https://lunarmodules.github.io/luasocket/tcp.html) or
Penlight's [`List:append`](https://lunarmodules.github.io/Penlight/classes/pl.List.html). Forgetting the colon gives `attempt to index a nil value
(local 'this')`. **Option:** name the receiver `self`, so messages
read as Lua's own. Free, not breaking.

### Constructors

**Today.** `Point(1, 2)` through a `__call` metamethod on the class
table, positionally, with `nil` for an omitted optional. No
`Point.new`. Missing arguments aren't caught: `Point(1)` constructs,
and fails later with `no such key, getter, or method on probe.Point: y`.

**What Lua users expect.** `Foo(...)` (Penlight's classes, through the
same `mt.__call` on the class table,
[class.lua#L164](https://github.com/lunarmodules/Penlight/blob/1.15.0/lua/pl/class.lua#L164)),
`Foo.new(...)` (many plain modules), and `Foo:new(...)` (Programming in
Lua's [`Account:new`](https://www.lua.org/pil/16.1.html)) are all
common. Penlight doesn't check constructor arguments either; in Lua
that falls to the editor, which today can't help (section 6).

**Options.** Add `Foo.new` as an alias of `Foo(...)` (additive; a
PiL-style `Foo:new(...)` would pass `Foo` first, so document `.new`
only). Annotate the call signature so editors check it (section 6).

### Properties and getters

**Today.** `url.href` and `color.length` read like fields, through
`__index` getters; settable properties write through `__newindex`.
Very Lua-like. But reads of unknown keys raise, and writes to
read-only properties succeed and shadow the getter:

```lua
print(p.nope)        --> error: no such key, getter, or method on probe.Point: nope
p.length = 1         -- `length` is a getter only
print(p.length)      --> 1   (the getter is gone for this instance)
p.x = 5              -- `x` isn't a `var` in Temper; Lua allows it
```

**What Lua users expect.** Unknown keys read as `nil` (feature
checks like `if obj.close then` are common). Penlight's classes set
`c.__index = c`, and its `class.properties`, the closest match to
Temper's getters, ends its `__index` with `return rawget(t,'_'..key)`,
`nil` for unknown keys. Its `__newindex` calls a `set_` method if there
is one and otherwise does `rawset(t,key,value)`
([class.lua#L238-L260](https://github.com/lunarmodules/Penlight/blob/1.15.0/lua/pl/class.lua#L238-L260)),
so writing a getter-only property shadows it there too: today's write
behavior is ordinary Lua, and only the read behavior is foreign.

**Options.** Return `nil` for unknown keys (non-breaking for correct
code; loses a debugging aid that LuaLS's `undefined-field` gives in the
editor anyway, as section 6 shows). Raising on writes to getter-only and
non-`var` properties would be stricter than Lua precedent; worth it only
if cheap (it adds a `__newindex` check to every write).

### Optional and named parameters

**Today.** Defaults work with `nil` or omitted trailing arguments. For
long constructors, positional `nil`s pile up. Argmas's tour:

```lua
-- name, about, version, commandOptional, style, alsoStyle, completions
local cli = Command(CommandSpec("frob", nil, nil, nil, nil, nil, true))
-- name, short, help, env, negatable, inherited
local quiet = git:flag(FlagSpec("quiet", "q", "Say less.", nil, nil, true))
```

**What Lua users expect.** An options table, which `f{ … }` call
syntax exists for (LuaSocket's
[`http.request{ url = …, sink = … }`](https://lunarmodules.github.io/luasocket/http.html)),
or chained setters (lua-argparse's
[`parser:option("-o"):default("a.out")`](https://argparse.readthedocs.io/en/0.7.1/options.html)).

**Options.** Mirror JS's `static new(props)` (`notes/api-compat.md`):
a props form, `CommandSpec.new{ name = "frob", completions = true }`,
for constructors with two or more parameters. `CommandSpec{ … }` is
more Lua-like but ambiguous when the first parameter is a table.

### Callbacks and fun interfaces

**Today.** Function parameters and `@fun` interfaces take plain Lua
functions (callable tables work too). Good. Two small leaks: the fun
interface is exported as a class table (`probe.Scorer`) with a
LuaLS `apply` field nobody calls, and a callback returning the wrong
number type fails inside the runtime (`intnew.lua:68: number (local
'n') has no integer representation`).

Regular interfaces need the runtime: a plain table works until a
default method is called (`attempt to call a nil value (method
'describe')`); the working form, `temper.type("my.Circle",
probe.Shape)`, is documented nowhere a Lua user would look.

**Options.** Don't export fun interfaces to Lua. Export a library-named
`probe.Shape.extend{ area = function(self) … end }` returning a class,
or copy default methods into plain tables on first use.

### Iteration and type tests

**Today.** Lists iterate with `ipairs`; generators with `for _, v in g
do`. Maps need the runtime (see above). Sum types are tested with the
runtime's `temper.instance_of(result, Output)`, which raises on a
plain table: `instance_of({}, T)` gives
`attempt to index a nil value (field '?')`.

**What Lua users expect.** `ipairs` and `pairs`. Type tests vary
(`getmetatable(x) == Foo`, Penlight's `Foo:class_of(x)` and
`x:is_a(Foo)`), but none goes through a third module, and Penlight's
returns `false` for anything that isn't an object:
`if not m then return false end --*can't be an object!`
([class.lua#L73-L85](https://github.com/lunarmodules/Penlight/blob/1.15.0/lua/pl/class.lua#L73-L85)).

**Options.** A library-exported test (`Output.is(x)`, or
`argmas.is(x, Output)`), and `instance_of` returning `false` for
anything without a tag.

## 3. Errors

**Today.** A Temper failure (bubble) is `error()` with a table whose
`__tostring` gives its message, which is usually just "Bubble". A
panic is `error("panic")` with a position. Runtime misuse gives raw
Lua errors from inside `temper-core`.

| What happens | What the Lua user sees |
|---|---|
| `pcall(hrefine.parseUrl, "setup.html")` | `false, <table>`; `tostring` gives `Bubble` |
| Uncaught bubble, Lua 5.4 | `lua: Bubble`, no traceback, no position |
| Uncaught bubble, Lua 5.1 | `lua: (error object is not a string)` |
| `"failed: " .. err` | `attempt to concatenate a table value` |
| `xpcall(f, debug.traceback)` | the table back, no traceback |
| `Color.parse("not a color")`, uncaught | `lua: core.type Mapped.get() no such key not a color` |
| `orelse panic()` (Chromarite's `Color.fromList` with a bad count) | `chromarite/init.lua:181: panic` |
| `parseUrl(42)` | `temper-core/init.lua:1927: attempt to get length of a number value (local 'str')` |

**What Lua users expect.** [PiL's rule](https://www.lua.org/pil/8.3.html),
which the standard library follows: raise for errors that are easily
avoided (`math.sin("x")` raises); return `nil, message` for failures
that aren't (`io.open`). LuaSocket returns `nil, err` throughout
([TCP](https://lunarmodules.github.io/luasocket/tcp.html),
[HTTP](https://lunarmodules.github.io/luasocket/http.html)); dkjson's
[`decode`](http://dkolf.de/dkjson-lua/) returns `nil, pos, msg`. The
sources show the details:

- **lua-cjson** raises from `cjson.decode`, and `cjson.safe` wraps each
  function to "Convert and return thrown errors as: nil, "error
  message"", but "Deliberately throw an error for invalid arguments"
  ([lua_cjson.c#L1965-L1975](https://github.com/openresty/lua-cjson/blob/2.1.0.20/lua_cjson.c#L1965-L1975)).
  And `nil` is never a successful result: `decode("null")` gives the
  `cjson.null` sentinel, so `nil, err` is unambiguous.
- **Penlight** raises for wrong argument types (`utils.assert_arg`,
  level 2) and otherwise returns `utils.raise(err)`, which is `return
  nil, err` unless `utils.on_error('error')` switched a process-wide
  mode ([utils.lua#L290-L298, #L488-L519](https://github.com/lunarmodules/Penlight/blob/1.15.0/lua/pl/utils.lua#L290-L298)),
  which affects every library using Penlight at once.
- **busted** raises its own failures as tables, `{ message = emsg }`
  with `__tostring` and `__type`
  ([core.lua#L6-L10, #L143-L149](https://github.com/lunarmodules/busted/blob/v2.3.0/busted/core.lua#L6-L10)),
  and reports any error through `__tostring`. luassert's
  `assert.has_error(f, "msg")` compares `tostring(err)` for such tables
  ([assertions.lua#L181-L189](https://github.com/lunarmodules/luassert/blob/v1.9.0/src/assertions.lua#L181-L189)).
  So error tables are fine in Lua tests, if the message is real: today
  `"Bubble"` is the only string that matches a Temper failure.

Raised errors are usually strings with a position (`error(msg, 2)`
blames the caller), so `"failed: " .. err` works. The standalone `lua`
prints an uncaught error table through `__tostring` since 5.2
([lua.c#L165](https://github.com/lua/lua/blob/v5.2.0/lua.c#L165)); 5.1's
gives `msg = "(error object is not a string)"`
([lua.c#L67-L68](https://github.com/lua/lua/blob/v5.1.1/lua.c#L67-L68)),
as the table above shows. LuaJIT's [uses it](https://luajit.org/extensions.html).

**Tie to #164.** The current proposal there maps a declared failure to
a library-named tagged table with `__tostring`, returned as `nil,
failure` ([Lua translation](../../164-exceptions/tom/claude-translations/lua.md)).
From this study:

- `nil, failure` is right for the expected failures (`parseUrl`,
  `Identifier.named`, `Color.parse`), and `assert(f(…))` gives the
  raising form for free. But today's `nil` problem bites here: a
  function returning `T?` can't use `nil` for both "no value" and
  "failed". Settling null (section 1, option B) and #164 together
  avoids two breaking changes. lua-cjson shows one way out: a `T?`
  function that can also fail keeps returning the library's null
  sentinel for "no value", so `nil` always means failure.
- A `safe`-style form should still raise for argument misuse, as
  `cjson.safe` does; only expected failures become `nil, failure`.
- Whatever is raised needs a real message (today `temper.bubble()` is
  mostly called without one), level 2 for argument errors, and
  `panic`'s cause. Panics must not be caught by `orelse` (today's
  `temper.pcall` already re-raises non-bubbles; good).

## 4. Modules and packaging

**Today.** `temper build` writes a rockspec per library, plus
`temper-core` and `std`:

```lua
package = 'ordable'
version = 'dev-1'
build = { type = 'builtin', copy_directories = {'.'}, modules = {} }
dependencies = { 'lua >= 5.1', 'temper-core == 0.7.0.alpha.0.265' }
test_dependencies = { 'std == 0.7.0.alpha.0.265' }
source = { url = 'file://ordable.zip' }
```

Problems, in order of impact:

1. **Nothing installs where `require` looks.**
   [`copy_directories`](https://github.com/luarocks/luarocks/blob/main/docs/rockspec_format.md)
   copies into the rock's own directory, not `share/lua/5.x`, so after
   `luarocks make` (which succeeds), `require("ordable")` fails with
   `module 'ordable' not found`. Every tour sets `package.path` by hand
   ("Once Temper's rockspecs install properly, LuaRocks can replace
   this.").
2. **`lua >= 5.1` isn't true.** All six libraries fail to parse on PUC
   Lua 5.1: `goto continue` (`goto` is reserved from 5.2.0,
   [llex.c#L38](https://github.com/lua/lua/blob/v5.2.0/llex.c#L38))
   and lines starting `;(` (the empty statement arrived with it,
   `case ';': {  /* stat -> ';' (empty statement) */`,
   [lparser.c#L1530](https://github.com/lua/lua/blob/v5.2.0/lparser.c#L1530);
   [5.1](https://www.lua.org/manual/5.1/manual.html#2.4.1) allows
   `;` only after a statement). For example,
   `ordable/init.lua:696: '=' expected near 'continue'`. LuaJIT
   accepts both, and all six tours ran on LuaJIT (Ordable's tour
   itself uses `table.unpack`, which
   [LuaJIT lacks by default](https://luajit.org/extensions.html)).
   `docs/inconsistencies.md` (I13) notes 5.1 is untested.
3. **Exact runtime pin.** Libraries built by different Temper versions
   can't be installed together; LuaRocks loads one `temper-core`.
4. **Tests ship.** `copy_directories = {'.'}` installs `tests/`
   (Hrefine's is 638 KB, more than twice the library).
5. **Thin metadata.** No `summary` or `homepage` (optional, but what
   luarocks.org shows), and a `file://` `source.url`.

**What Lua users expect.** `luarocks install foo`, then `require("foo")`:
`build.modules = { foo = "foo/init.lua", ["foo.bar"] = "foo/bar.lua" }`,
a version range on dependencies (`temper-core >= 0.7, < 0.8`, the
[rockspec format's](https://github.com/luarocks/luarocks/blob/main/docs/rockspec_format.md)
own `lfs >= 1.0, < 2.0` form), and a `lua` range that CI actually
tests.

**Which Lua versions.**

Each feature's first release, from the source at lua/lua's tags:

| Feature | Since | Where |
|---|---|---|
| `goto`, empty statement `;`, `__pairs`, `__len` for tables, `table.unpack`, `__tostring` for uncaught errors in `lua` | 5.2.0 | `llex.c`, `lparser.c`, `lbaselib.c`, `lvm.c`, `ltablib.c`, `lua.c` |
| Integer subtype, `math.type`, `utf8` library | 5.3.0 (2015-01) | `lutf8lib.c` is absent at v5.2.0, present at v5.3.0 |
| `__name` in argument errors / in `tostring` | 5.3.0 / 5.3.4 | `lauxlib.c` (`luaL_tolstring` "try name") |
| `global` reserved, `for` control variables read-only | 5.5.0 (2025-12) | `llex.c`, `lparser.c` (`RDKCONST`) |

| Version | Today | Cost of supporting |
|---|---|---|
| 5.5 | Not run | `global` is reserved unless built with `LUA_COMPAT_GLOBAL` (on in the default [`luaconf.h`](https://github.com/lua/lua/blob/v5.5.0/luaconf.h#L340-L342)); Temper doesn't reserve it (bug 12). No generated or runtime code assigns a `for` control variable (scanned) |
| 5.4 | Tested; works | — |
| 5.3 | Same integer model as 5.4; not tested | A CI job |
| 5.2 | `goto` OK; no integers or `utf8`, so the 5.1 fallbacks (`intold.lua`) | A CI job; slower ints |
| 5.1 (PUC) | Doesn't parse | Emit `repeat … until true` with `break` for `continue`, avoid `;(`; Int64 as tables |
| LuaJIT 2.1 | Tested; works | Int64 as tables (cdata would be better); no `utf8` |

`lua >= 5.2` would be honest but would exclude LuaJIT, which LuaRocks
sees as 5.1 (it provides `lua` 5.1 plus a `luajit` virtual rock for
rockspec format 3.0+). Since [OpenResty](https://openresty.org/en/luajit.html)
and many embedders run LuaJIT, better to
keep `>= 5.1` and stop emitting the two 5.2-only constructs.

**Should users ever name `temper-core`?** Today they do, for
`temper.null`, `null_to_nil`, `instance_of`, and `temper.type`; with
recommendation 22 they wouldn't, as #676's principle 3 asks.

## 5. Speed and size

Microbenchmarks from the probe library against hand-written Lua doing
the same work, 5 runs each, on a noisy shared machine (ranges, ms):

| Case | Lua 5.4 generated | Lua 5.4 hand | LuaJIT generated | LuaJIT hand |
|---|---|---|---|---|
| Sum 1M floats in a list | 421–582 | 36–49 | 18–23 | 2.8–3.5 |
| Sum 1M ints through a callback | 498–767 | 91–101 | 19–22 | 3.0–3.2 |
| Count code points, 600 KB | 4.9–10 | 166–212 | 55–72 | 5.8–11 |
| 1M calls with `orelse panic()` vs without | 1477–1893 | 84–126 | 785–879 | 2.6–3.5 |

What the loops cost, from the generated code:

```lua
while i < temper.list_length(xs) do       -- a call per iteration
  t = t + temper.list_get(xs, i)          -- a call and a nil check
  i = temper.int32_add(i, 1)              -- a call and a mask
end
```

against `for i = 1, #xs do t = t + xs[i] end`: 5 to 16 times slower
on 5.4, 5 to 8 on LuaJIT. `orelse` costs a closure and a `pcall` on
every pass, success or not: 12 to 22 times on 5.4 and 200 to 300 on
LuaJIT, where creating a closure stops the trace compiler (57 `orelse`
closures in Chromarite, 51 in kelpto-md). Code point counting wins,
using 5.4's `utf8.len` in C. Planned already (`notes/output-speed.md`,
item 2): plain arithmetic where ranges rule out overflow. Lua-specific
additions: hoist `list_length` out of loop conditions, inline
`list_get` as `xs[i + 1]` where the index is known in range, and lower
`orelse` without `pcall` (#164's `nil, failure` form would anyway).

**Size.** `init.lua` runs from 66 KB (Ordable; 17 KB gzipped) to
444 KB (kelpto-md; 65 KB gzipped), roughly a fifth of its lines LuaLS
annotations, plus `temper-core` (about 180 KB, 50 KB of it the regex
runtime), shared by every Temper library, and `std` (120 KB) for
tests. Reasonable for what the libraries do.

## 6. Docs and editor support

**Today.** Generated code carries LuaCATS annotations (`---@param`,
`---@class`, `---@field`, and `---@operator call: probe.Point` on each
class table), checked by LuaLS in the backend's tests. I ran LuaLS
3.19.2's `--check` on one user script against the probe library, as
generated (A) and with hand-edited annotations (B to E):

```lua
local probe = require("probe")
local s = probe.maybe(true)            -- String?
if s then print(s:upper()) end         -- 3
print(probe.describe(nil))             -- 4: String? parameter
local p = probe.Point(1)               -- 5: missing argument
local q = probe.Point("a", "b")        -- 6: wrong types
print(p:scaled("x"), q)                -- 7
print(p.nope)                          -- 8
p.length = 1                           -- 9: getter only
print(probe.mapSize({ a = 1 }))        -- 11: crashes
print(probe.addInts(1.5, 2))           -- 12: wrong on every version
local r = probe.firstOrNull({})
print(r:upper())                       -- 14
```

| Line | A: as generated | B: + `temper-core` meta file | C: params `T\|temper.Null\|nil` | D: `T?` and `@overload` | E: `@operator call(number, number)` |
|---|---|---|---|---|---|
| 3 | mismatch (`string\|temper.Null`) | same | same | — (narrowed) | same as A |
| 4 | `Cannot assign nil` | same | — | — | same as A |
| 5 | — | — | — | `requires 2 argument(s)` | — |
| 6 | — | — | — | two mismatches | — |
| 7, 8 | mismatch; `Undefined field nope` | same | same | same | — (`p` untyped) |
| 14 | mismatch | same | same | `need-check-nil` | same as A |
| 9, 11, 12 | — | — | — | — | — |

What this settles:

- **`T|temper.Null` is honest today.** Lines 3 and 14 are real
  errors: `temper.null` is truthy, so `if s then` doesn't guard. Only
  parameters are wrong (line 4), and C fixes that alone, with no other
  change. `T?` (LuaLS's `T|nil`) for results is right only once
  results really are `nil` (section 1, option B); D shows it then gives
  narrowing and `need-check-nil`, as Lua users expect.
- **`---@operator call` gives no argument checks.** LuaLS uses a `call`
  operator only for the result type, passing no operands
  (`vm.runOperator('call', source.node)`,
  [compiler.lua#L2428-L2441](https://github.com/LuaLS/lua-language-server/blob/3.19.2/script/vm/compiler.lua#L2428-L2441)),
  so lines 5 and 6 pass. The operator takes one operand type, and the
  [annotations wiki](https://luals.github.io/wiki/annotations/) says "It
  is recommended to instead use @overload to specify the call signature
  for a class"; E's two-operand form even left `p` untyped. D's
  `---@overload fun(x: number, y: number): probe.Point` checks calls.
- **`@overload` has a cost:** a class with one no longer passes as its
  parent class. In D, `temper.instance_of(p, probe.Point)` gives
  `Cannot assign probe.Point.type to parameter temper.Type`, which
  reproduces in eight lines without Temper and is LuaLS's open
  [#2978](https://github.com/LuaLS/lua-language-server/issues/2978).
  Typing such parameters `temper.Type|function` in the meta file clears
  it (checked on the eight-line repro).
- **The meta file matters most when a library is vendored.** With the
  library in `workspace.library`, B changed nothing for probe's users;
  it only types direct `temper-core` calls, and flags
  `temper.null_to_nil`, which tours use but the backend's test meta file
  leaves out. With the rocks copied into the workspace, as every tour
  does, LuaLS checks the generated code itself: probe's `init.lua` has
  28 warnings without the meta file (15 for the undefined `temper.Null`
  and `temper.Type`) and 0 with it, but `temper-core` goes from 157 to
  270, 216 of them undefined fields. Shipping it needs the whole runtime
  surface, and `---@diagnostic disable` on the runtime's own files.
- **Not checked by any variant:** line 9 (LuaLS has no read-only
  fields), line 11 (`table<string, integer>` accepts the plain table
  that crashes), and line 12 (LuaLS's `type.castNumberToInteger`
  setting, on by default, lets a `number` pass as an `integer`).

Other gaps:

- **No prose.** The libraries' docs don't reach the Lua output (a
  `/** … */` doc produced only `---@param`), so hovers show only types,
  though Temper's IR keeps each declaration's doc (`temper-tmpl`'s `doc`
  field). LuaLS reads `---` prose as Markdown; LDoc reads the same
  summary, but its `@param` takes a name and a description, so
  `---@param x number` reads as "x: number", and it warns on tags such
  as `@class` (`"unknown tag: '"..tag.."'"`,
  [doc.lua#L526](https://github.com/lunarmodules/LDoc/blob/v1.5.0/ldoc/doc.lua#L526)).
  Prose serves both; LDoc-clean tags would mean dropping LuaCATS.
- **Instances without `toString` print as `table: 0x…`.** A `__name`
  gives `probe.Point: 0x…` from `tostring` (5.3.4+) and `(string
  expected, got probe.Point)` in argument errors (5.3+), checked on
  5.4.6, the form of Penlight's default `__tostring`
  ([class.lua#L110-L117](https://github.com/lunarmodules/Penlight/blob/1.15.0/lua/pl/class.lua#L110-L117)).
  No `__eq` either, even for `@auto("==")`.
- **Generated code reads well,** apart from cast noise like
  `;(log --[[@as hrefine.ErrorLog]]).pathStart = …`. Options:
  recommendations 3, 7, and 8.

## Recommendations

**Quick wins** (none breaking):

1. Fix the rockspecs: `build.modules` entries so `require` works after
   `luarocks install`; don't install `tests/`; add summary and homepage.
2. Make generated code parse on PUC 5.1 (no `goto`, no leading `;`);
   test 5.1 and 5.3 in CI beside 5.4 and LuaJIT; reserve `global` (5.5).
3. Annotations: nullable parameters `T|temper.Null|nil`; constructors
   as `---@overload` with their parameters; ship a complete
   `temper-core` meta file, with `temper.Type|function` parameters.
4. Accept plain Lua tables as `Map` parameters.
5. `temper.instance_of` returns `false` for untagged tables, as
   Penlight's `is_a` does.
6. Name method receivers `self`; give bubbles a message (busted and
   luassert show and match `tostring(err)`); keep `panic`'s cause.
7. Add `Foo.new` as an alias of `Foo(...)`; set `__name` on instances.
8. Emit Temper doc comments as `---` prose.

**Medium changes:**

9. Coerce `Float64` arguments to floats, and check `Int` arguments
   (integral, 32-bit) at exported entry points, with standard
   `bad argument` messages.
10. Hide maps' bookkeeping from `pairs` (metatable or side table), with
    an ordered `__pairs`.
11. Copy (or freeze) lists the library holds when returning them.
12. Read unknown keys as `nil`, as Penlight does *(changes errors to
    `nil`)*; raising on read-only writes is optional.
13. Drop `$test` from the public module table; rename the `std` rock and
    module *(breaking for anyone requiring `std`)*.
14. Hoist lengths and inline list reads in loops; lower `orelse` without
    `pcall` where possible.
15. Int64 as LuaJIT cdata *(breaking on LuaJIT)*, annotated to match.

**Design questions for #676 and #164:**

16. **Null at the boundary** *(breaking)*: option B, annotated `T?`.
    Decide with #164's `nil, failure`, since a `T?` result can't use
    `nil` for both; lua-cjson keeps the sentinel for a null result.
17. **Failures** *(breaking)*: #164's failure tables (with `message`
    and `__tostring`, like busted's) returned as `nil, failure`, or
    raised. Lua does both (`io.open`, `cjson.decode`); for both, a
    second module like `cjson.safe` beats a global switch like
    Penlight's `utils.on_error`, and argument misuse raises in either.
18. **Named arguments** *(additive)*: a props-table form for
    constructors with two or more parameters, like JS's `new(props)`;
    which name it gets (`Foo.new{…}`, `Foo{…}`, or `Foo.of{…}`).
19. **Module names** *(breaking for multi-module libraries)*: dotted
    (`kelpto.md`) instead of slash (`std/regex`) and hyphenated
    (`kelpto-md`) names.
20. **0-based indexes in Lua APIs:** document only, or a way for a
    library to mark index parameters so Lua sees 1-based ones.
21. **Implementing interfaces from Lua:** a library-named `extend`
    instead of `temper.type`.
22. **Is the runtime ever named?** With 16, 21, and a library `is`
    test, Lua users would never `require("temper-core")`.

## Bugs found

On Temper `b347b34f` (1 to 10) or `13dc5669` (11 to 15) and Lua 5.4.6
unless noted; `probe` is built from the Temper shown.

1. **Rockspecs install nothing `require` finds:** `luarocks make
   --tree=t ordable-dev-1.rockspec` succeeds (`modules = {}`,
   `copy_directories`), then `require("ordable")` gives `module
   'ordable' not found`.
2. **No PUC 5.1 parse despite `lua >= 5.1`:** `goto continue`, and
   casts on lines starting `;(`. `luac5.1 -p`: Ordable `:696: '='
   expected near 'continue'`; Hrefine `:601: unexpected symbol near ';'`.
3. **Writing a getter-only property shadows the getter:** with `public
   get length()` on `Point`, `p.length = 1; print(p.length)` prints
   `1`; non-`var` `p.x = 5` succeeds. (As in Penlight; low priority.)
4. **Plain tables as `Map` arguments crash:** `export let mapSize(m:
   Map<String, Int>): Int { m.length }`; `probe.mapSize({ a = 1 })`
   gives `init.lua:1198: attempt to get length of a nil value`.
5. **`pairs` over a returned `Map` shows internals:** for `new
   Map([new Pair("a", 1)])`, also the key-order table and
   `temper.type_tag`.
6. **`temper.instance_of({}, probe.Point)` raises** `attempt to index
   a nil value (field '?')` instead of returning `false`.
7. **Integer arguments to `Float64` keep integer arithmetic:** `export
   let square(x: Float64): Float64 { x * x }`; `probe.square(1 << 40)`
   is `0`, `probe.square(3)` integer `9`.
8. **`Int` arguments unchecked, version-dependent:** `export let
   addInts(a: Int, b: Int): Int { a + b }`; `addInts(1 << 40, 0)` is
   `0`; `addInts(1.5, 1)` raises on 5.4 (`intnew.lua:68: number has no
   integer representation`) and returns `2.5` on LuaJIT and 5.1.
9. **Returned lists alias library state:** `let fixed = ["a", "b"];
   export let fixedList(): List<String> { fixed }`;
   `probe.fixedList()[1] = "changed"` changes what later calls see.
10. **LuaLS rejects `nil` for nullable parameters:** `String?` is
    `string|temper.Null`, so `probe.describe(nil)`, which works, gets
    `Cannot assign nil to parameter`. Fix: `string|temper.Null|nil`.
11. **LuaLS can't check constructor calls:** `export class Point(public
    x: Float64, public y: Float64)` gets `---@operator call:
    probe.Point`, so `probe.Point(1)` passes. With `---@overload fun(x:
    number, y: number): probe.Point`: `This function requires 2
    argument(s) but instead it is receiving 1`.
12. **`global` isn't reserved:** `export let bump(global: Int): Int {
    let local2 = global; local2 + 1 }` emits `local function
    bump(global)`, a syntax error on Lua 5.5 built without
    `LUA_COMPAT_GLOBAL` (not run: no 5.5 here). `names.rs`'s
    `KEYWORDS` lists 5.4's words.
13. **Vendored libraries fail LuaLS's checks:** with `probe/` and
    `temper-core/` copied into a workspace, as the tours do, `--check`
    gives 28 warnings in probe's `init.lua` (`undefined-doc-name` for
    `temper.Null`, `undefined-doc-class` for `temper.Type`, …) and 157
    in `temper-core`, none of which users can act on.
14. **The LuaLS meta file isn't shipped, and isn't complete:**
    `tests/luals/temper-core.lua` covers what generated library code
    calls. Of the 184 names the runtime's `init.lua` defines directly
    (`function temper.x` or `temper.x =`), 72 aren't declared, among
    them `null_to_nil`, `pairs`, `type_tag`, `import`, `int_eq`, and
    `listof`. Copied in as-is, user code gets `Undefined field
    null_to_nil`, and `temper-core` 216 `undefined-field` warnings.
15. **Int64 annotated `integer` on every Lua:** `export let parse64(s:
    String): Int64 throws Bubble { … }` has `---@return integer` but
    returns a table on LuaJIT and 5.1.
