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
say it does, and numbers and maps passed in from Lua aren't checked or
converted. Most of these fixes are small; three are design questions
for this RFC and for [#164](../../164-exceptions/README.md).

## How this was studied

- Built the six showcase libraries (Argmas, Chromarite, Hrefine,
  Kelpto, Ordable, and Wherewith) with Temper's compiler
  (`temper build -b lua`, temperlang/temper at `b347b34f`, runtime
  `0.7.0.alpha.0.265`), and ran each library's Lua tour on Lua 5.4.6,
  LuaJIT 2.1, and PUC Lua 5.1.5.
- Wrote a small probe library (about 80 lines of Temper: floats, ints,
  nullables, defaults, lists, maps, callbacks, a fun interface, an
  interface, classes, and failures), and Lua scripts that use it the
  way a Lua user would. Every snippet below was run; output is quoted
  as printed.
- Read the Lua backend (`crates/temper-be-lua`), its runtime
  (`crates/temper-be-lua/runtime/temper-core/init.lua`), and
  `notes/api-compat.md`, whose item 8 already proposes returning `nil`.
- Checked a user script with LuaLS (`lua-language-server --check`), as
  an editor would.
- Lua conventions come from well-known libraries' documented behavior
  (Penlight, LPeg, LuaSocket, lua-cjson, dkjson, lua-argparse, and
  LuaRocks). Their sites weren't reachable during this study, so check
  details there before quoting them further.

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
`cjson.null` and dkjson's `json.null` (dkjson even lets the caller pick
the value used for null when decoding).

**Options.**

| Option | Gains | Costs |
|---|---|---|
| A. Keep `temper.null` everywhere | No change; one rule | Every Lua user meets the truthy trap; tours need the runtime |
| B. `nil` at scalar boundaries (results, fields, getters, parameters), `temper.null` only inside lists and maps (api-compat item 8) | `if x then` works; matches lua-cjson | Breaking; two representations; generated code converts at each exported function and getter |
| C. `nil` everywhere, lists carry an explicit length (`n` field, as `table.pack`) | Purest Lua | `#` and `ipairs` stop at holes, so every user loop breaks; far too costly |

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
`table.insert`, LPeg, Penlight's `List`); "counted from 0" in a Lua API
reads as a port.

**Options.** Indexes: (a) document them as 0-based (cheap, still
foreign); (b) a way for a library to mark index parameters and results,
shifted by one for Lua (a question for this RFC; Temper has no "index
type" to infer it from). Aliasing: copy lists the library keeps (fields
and module-level values) when returning them; a read-only proxy would
break `#` and `ipairs` on 5.1 and LuaJIT, which lack `__len` for
tables.

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
and any table can be passed in. Order isn't expected (Lua's `pairs`
order is unspecified), though libraries that keep order (dkjson's
`keyorder`, Penlight's `OrderedMap`) do it in a side table or
metatable, never in visible keys.

**Options.** (a) Accept plain tables wherever a `Map` is taken,
building the key order on first use (a few lines in the runtime);
(b) move the order and tag into a metatable or weak side table, with an
ordered `__pairs` (5.2+). Together they make maps ordinary tables that
happen to keep order.

### Strings

**Today.** Lua strings, UTF-8, untouched; Temper's `StringIndex` is a
1-based byte offset, so it lines up with `string.sub`. Right as is.
Libraries that report positions (Hrefine's errors) count code points
from 0, the same in every language, while a Lua user assumes bytes
from 1 (`string.find`, LPeg). **Option:** say so in each such API's
docs; it's the library's choice, not Temper's.

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

**What Lua users expect.** "A number" is the default; integers matter
mainly as table keys and in `string.format("%d")`. Libraries that need
integers check with `math.type` or `math.floor(x) == x` and raise
`bad argument #1 to 'f' (number has no integer representation)`, the
standard library's own message. On LuaJIT, 64-bit integers are
`int64_t` cdata (`1LL`) via the FFI, which is what LuaJIT users would
recognize.

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

**What Lua users expect.** Dotted names (`socket.http`, `pl.stringx`),
which `package.path` turns into directories and `build.modules` keys
use; slash names work only by accident of the default searchers. Rock
names may have hyphens (`lua-cjson`), module names rarely (`cjson`).
And a top-level `std` module clashes with lua-stdlib's `std.*`.

**Options.** Dotted module names (`kelpto.md`, `wherewith.dialects`),
which is breaking for multi-module libraries only. Rename the `std`
rock and module (`temper-std` / `temper_std`, as Python's
`temper_std`). Drop `$test` from the public table (tests can
`require` an `-internal` module, which the backend already uses for
some tests).

### Functions and methods

**Today.** Module functions and statics use `.` (`Color.fromList`),
instance methods `:`, exactly as LuaSocket's `sock:send` or Penlight's
`List:append`. Forgetting the colon gives `attempt to index a nil value
(local 'this')`. **Option:** name the receiver `self`, so messages
read as Lua's own. Free, not breaking.

### Constructors

**Today.** `Point(1, 2)` through a `__call` metamethod on the class
table, positionally, with `nil` for an omitted optional. No
`Point.new`. Missing arguments aren't caught: `Point(1)` constructs,
and fails later with `no such key, getter, or method on probe.Point: y`.

**What Lua users expect.** Both `Foo(...)` (Penlight's classes,
middleclass) and `Foo.new(...)` (Programming in Lua's examples, most
plain modules) are common.

**Options.** Add `Foo.new` as an alias of `Foo(...)` (additive,
cheap). Check required arguments for `nil` in exported constructors
(`bad argument #2 to 'Point' (number expected, got nil)`).

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
checks like `if obj.close then` are common), and writes to read-only
fields raise. That's the opposite of today.

**Options.** Return `nil` for unknown keys (non-breaking for correct
code; loses a debugging aid that LuaLS's `undefined-field` already
gives in the editor). Raise on writes to getter-only and non-`var`
properties (breaking only for code that's already wrong).

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
syntax exists for (LuaSocket's `http.request{ url = …, sink = … }`), or
chained setters (lua-argparse's `parser:option("-o"):default("a.out")`).

**Options.** Mirror JS's `static new(props)` (already in
`notes/api-compat.md`'s JS rules): constructors with two or more
parameters get a props form, `CommandSpec.new{ name = "frob",
completions = true }`. If `.new` is also the positional alias above,
one of them needs another name; `CommandSpec{ … }` (a single table
argument with no type tag) is the most Lua-like but ambiguous when the
first parameter is itself a table. A design question below.

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
way to implement an interface, such as `probe.Shape.extend{ area =
function(self) … end }` returning a class, or let plain tables in by
copying default methods in on first use.

### Iteration and type tests

**Today.** Lists iterate with `ipairs`; generators with `for _, v in g
do`. Maps need the runtime (see above). Sum types are tested with the
runtime's `temper.instance_of(result, Output)`, which raises on a
plain table: `instance_of({}, T)` gives
`attempt to index a nil value (field '?')`.

**What Lua users expect.** `ipairs` and `pairs`. Type tests vary
(`getmetatable(x) == Foo`, Penlight's `Foo:class_of(x)`,
`x:is_a(Foo)`), but none goes through a third module.

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

The Hrefine tour says it plainly: "parseUrl raises an error, which
pcall catches. It's Temper's bubble, whose message is only "Bubble", so
checkUrl says why."

**What Lua users expect.** PiL's rule, which the standard library
follows: raise for programmer errors and things easily avoided
(`math.sin("x")` raises); return `nil, message` for expected failures
(`io.open`). LuaSocket returns `nil, err` throughout; dkjson's `decode`
returns `nil, pos, msg`; lua-cjson's `decode` raises, and its
`cjson.safe` module offers the same functions returning `nil, err`;
Penlight returns `nil, err` and can be switched to raising. Errors
raised are usually strings with a position (`error(msg, 2)` blames
the caller), so `print("failed: " .. err)` works; error tables, where
used, have `__tostring`.

**Tie to #164.** The current proposal there maps a declared failure to
a library-named tagged table with `__tostring`, returned as `nil,
failure` ([Lua translation](../../164-exceptions/tom/claude-translations/lua.md)).
From this study:

- `nil, failure` is right for the expected failures (`parseUrl`,
  `Identifier.named`, `Color.parse`), and `assert(f(…))` gives the
  raising form for free. But today's `nil` problem bites here: a
  function returning `T?` can't use `nil` for both "no value" and
  "failed". Settling null (section 1, option B) and #164 together
  avoids two breaking changes.
- Whatever is raised should have a real message. Today
  `temper.bubble()` is mostly called without one; the failure's own
  message, or at least the function name, would help even before
  #164 lands.
- Raise with level 2 (blame the caller) for argument errors, and keep
  `panic`'s cause in its message.
- Panics must not be caught by `orelse` (today's `temper.pcall` already
  re-raises non-bubbles; good).

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

1. **Nothing installs where `require` looks.** `copy_directories`
   copies into the rock's own directory, not `share/lua/5.x`, so after
   `luarocks make` (which succeeds), `require("ordable")` fails with
   `module 'ordable' not found`. Every tour sets `package.path` by hand
   ("Once Temper's rockspecs install properly, LuaRocks can replace
   this.").
2. **`lua >= 5.1` isn't true.** All six libraries fail to parse on PUC
   Lua 5.1: `goto continue` (5.2+) and lines starting `;(` (an empty
   statement, 5.2+). For example,
   `ordable/init.lua:696: '=' expected near 'continue'`. LuaJIT
   accepts both, and all six tours ran on LuaJIT (Ordable's tour
   itself uses `table.unpack`, which LuaJIT lacks by default).
   `docs/inconsistencies.md` (I13) notes 5.1 is untested.
3. **Exact runtime pin.** Two libraries built by different Temper
   versions can't be installed together, since LuaRocks loads one
   `temper-core`.
4. **Tests ship.** `copy_directories = {'.'}` installs `tests/`
   (Hrefine's is 638 KB, more than twice the library).
5. **Thin metadata.** No `summary`, `homepage`, or real `source.url`,
   which `luarocks upload` needs.

**What Lua users expect.** `luarocks install foo`, then `require("foo")`:
`build.modules = { foo = "foo/init.lua", ["foo.bar"] = "foo/bar.lua" }`,
a version range on dependencies (`temper-core >= 0.7, < 0.8`), and a
`lua` range that CI actually tests.

**Which Lua versions.**

| Version | Today | Cost of supporting |
|---|---|---|
| 5.4 | Tested; works | — |
| 5.3 | Same integer model as 5.4; not tested | A CI job |
| 5.2 | `goto` OK; no integers or `utf8`, so the 5.1 fallbacks (`intold.lua`) | A CI job; slower ints |
| 5.1 (PUC) | Doesn't parse | Emit `repeat … until true` with `break` for `continue`, avoid `;(`; Int64 as tables |
| LuaJIT 2.1 | Tested; works | Int64 as tables (cdata would be better); no `utf8` |

`lua >= 5.2` would be honest but would exclude LuaJIT, which LuaRocks
sees as 5.1. Since OpenResty and many embedders run LuaJIT, better to
keep `>= 5.1` and stop emitting the two 5.2-only constructs.

**Should users ever name `temper-core`?** Today they do, for
`temper.null`, `null_to_nil`, `is_null`, `instance_of`, and
`temper.type`. With null as `nil`, a library-exported null sentinel,
`Foo.is`, and an `extend` helper, they wouldn't need to; it would be a
dependency they install and never import, as #676's principle 3 asks.

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

against `for i = 1, #xs do t = t + xs[i] end`. That's 5 to 16 times
slower on 5.4 and 5 to 8 times on LuaJIT. `orelse` costs a closure and
a `pcall` on every pass, success or not: 12 to 22 times on 5.4 and
200 to 300 times on LuaJIT, where creating a closure stops the trace
compiler. The libraries use it often (57 `orelse` closures in
Chromarite, 51 in kelpto-md). Code point counting is the one place
generated code wins, using 5.4's `utf8.len` in C.

Planned already (`notes/output-speed.md`, item 2): plain arithmetic
where ranges rule out overflow. Lua-specific additions: hoist
`list_length` out of loop conditions, inline `list_get` as `xs[i + 1]`
where the index is known in range, and lower `orelse` without `pcall`
(#164's `nil, failure` form would do this anyway).

**Size.** Library output, with roughly a fifth of the lines being
LuaLS annotations:

| Library | `init.lua` | Gzipped | Lines | Annotation lines |
|---|---|---|---|---|
| Ordable | 66 KB | 17 KB | 1,083 | 183 |
| Chromarite | 110 KB | 19 KB | 3,441 | 690 |
| Argmas | 188 KB | 30 KB | 5,605 | 1,410 |
| Hrefine | 251 KB | 56 KB | 6,240 | 1,135 |
| Wherewith | 361 KB | 53 KB | 10,640 | 2,274 |
| kelpto-md | 444 KB | 65 KB | 12,949 | 2,653 |

Plus `temper-core` (about 180 KB, 50 KB of it the regex runtime),
shared by every Temper library, and `std` (120 KB) for tests.
Reasonable for what the libraries do.

## 6. Docs and presentation

**Today.** Generated code carries LuaCATS annotations (`---@param`,
`---@class`, `---@field`, `---@operator call`), checked by LuaLS in the
backend's tests. In a user's editor, that gives real help: LuaLS
caught a wrong argument type, a wrong method argument, a typo'd field,
and a `string|temper.Null` used as a string:

```
user.lua:3:8  Cannot assign `string|temper.Null` to parameter `string|number`.
user.lua:4:19 Cannot assign `integer` to parameter `string`.
user.lua:7:9  Undefined field `nope`.
user.lua:8:22 Cannot assign `nil` to parameter `string|temper.Null`.
```

The last one is wrong: `describe(nil)` works at run time, but nullable
parameters are typed `string|temper.Null` while optional ones are
`string?`. And it missed `mapSize({ a = 1 })`, which crashes, and
`addInts(1.5, 2)`.

Gaps:

- **No prose.** The libraries are literate Temper with good docs, but
  none reaches the Lua output, so hovering `compareSmart` shows only
  its types. Temper's IR already keeps a declaration's doc
  (`temper-tmpl`'s `doc` field); no backend emits it yet.
- **The runtime has no annotations.** `temper.Null` and `temper.Type`
  aren't defined in what's shipped; the backend's tests check against
  a separate `tests/luals/temper-core.lua` that users never get.
- **Instances without `toString` print as `table: 0x…`;** a `__name`
  (which 5.3+ error messages use) and a default `__tostring` with the
  class name would help. No `__eq` either, even for `@auto("==")`.
- **Generated code reads well,** apart from cast noise like
  `;(log --[[@as hrefine.ErrorLog]]).pathStart = …`.

**Options.** Emit doc comments as `---` lines above each exported
declaration (LuaLS shows them on hover, and LDoc reads the same form).
Ship a `---@meta` file with `temper-core`. Type nullable parameters as
`T?` (or `T|nil|temper.Null` while both are accepted).

## Recommendations

**Quick wins** (none breaking):

1. Fix the rockspecs: `build.modules` entries so `require` works after
   `luarocks install`; don't install `tests/`; add summary and homepage.
2. Make generated code parse on PUC 5.1 (no `goto`, no leading `;`), and
   test 5.1 and 5.3 in CI beside 5.4 and LuaJIT.
3. Type nullable parameters so LuaLS accepts `nil`; ship `temper-core`'s
   LuaLS meta file.
4. Accept plain Lua tables as `Map` parameters.
5. `temper.instance_of` returns `false` for untagged tables.
6. Name method receivers `self`; give bubbles a message (the failing
   function at least); keep the cause in `orelse panic()`'s message.
7. Add `Foo.new` as an alias of `Foo(...)`.
8. Emit Temper doc comments as `---` comments.

**Medium changes:**

9. Coerce `Float64` arguments to floats, and check `Int` arguments
   (integral, 32-bit) at exported entry points, with standard
   `bad argument` messages.
10. Hide maps' bookkeeping from `pairs` (metatable or side table), with
    an ordered `__pairs`.
11. Copy (or freeze) lists the library holds when returning them.
12. Raise on writes to read-only properties *(breaking for wrong code
    only)*; read unknown keys as `nil` *(changes errors to `nil`)*.
13. Drop `$test` from the public module table; rename the `std` rock and
    module *(breaking for anyone requiring `std`)*.
14. Hoist lengths and inline list reads in loops; lower `orelse` without
    `pcall` where possible.
15. Int64 as LuaJIT cdata *(breaking on LuaJIT)*.

**Design questions for #676 and #164:**

16. **Null at the boundary** *(breaking)*: `nil` for scalar results,
    fields, and parameters, the sentinel only inside lists and maps,
    exported by each library (option B). Decide together with #164's
    `nil, failure`, since a `T?` result can't use `nil` for both.
17. **Failures** *(breaking)*: #164's library-named failure tables
    returned as `nil, failure`, versus raising them. Lua precedent
    supports both (`io.open` vs lua-cjson); a `cjson.safe`-style second
    module could offer the other form later.
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
    test, Lua users would never need `require("temper-core")`.

## Bugs found

On Temper `b347b34f` and Lua 5.4.6 unless noted; `probe` is built from
the Temper shown.

1. **Rockspecs install nothing `require` finds** (`modules = {}` with
   `copy_directories`): `luarocks make --tree=t ordable-dev-1.rockspec`
   succeeds, then `require("ordable")` gives `module 'ordable' not found`.
2. **No PUC 5.1 parse despite `lua >= 5.1`:** `continue` emits
   `goto continue`, casts emit lines starting `;(`. `luac5.1 -p` on
   Ordable: `:696: '=' expected near 'continue'`; Hrefine: `:601:
   unexpected symbol near ';'`.
3. **Writing a getter-only property shadows the getter:** with
   `public get length(): Float64 { … }` on `Point`,
   `p.length = 1; print(p.length)` prints `1`. Non-`var` `p.x = 5`
   also succeeds.
4. **Plain tables as `Map` arguments crash:** `export let mapSize(m:
   Map<String, Int>): Int { m.length }`; `probe.mapSize({ a = 1 })`
   gives `init.lua:1198: attempt to get length of a nil value`
   (`getOr` works; LuaLS says `table<string, integer>`).
5. **`pairs` over a returned `Map` shows internals:** for
   `new Map([new Pair("a", 1)])`, `pairs` also yields the key-order
   table and `temper.type_tag`.
6. **`temper.instance_of({}, probe.Point)` raises** `attempt to index
   a nil value (field '?')` instead of returning `false`.
7. **Integer arguments to `Float64` keep integer arithmetic:**
   `export let square(x: Float64): Float64 { x * x }`;
   `probe.square(1 << 40)` returns `0`, `probe.square(3)` integer `9`.
8. **`Int` arguments unchecked, version-dependent:** `export let
   addInts(a: Int, b: Int): Int { a + b }`; `addInts(1 << 40, 0)` is
   `0`; `addInts(1.5, 1)` raises `intnew.lua:68: number has no integer
   representation` on 5.4 and returns `2.5` on LuaJIT and 5.1.
9. **Returned lists alias library state:** `let fixed = ["a", "b"];
   export let fixedList(): List<String> { fixed }`; setting
   `probe.fixedList()[1] = "changed"` changes what later calls see.
10. **LuaLS rejects `nil` for nullable parameters:** `String?` is
    annotated `string|temper.Null`, so `probe.describe(nil)`, which
    works, gets `Cannot assign nil to parameter`.
