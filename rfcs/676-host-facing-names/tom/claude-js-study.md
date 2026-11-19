# Temper libraries from a JavaScript and TypeScript user's point of view

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

## The question

Does a Temper library look and behave like a JavaScript library to
someone who writes JavaScript or TypeScript, and what would make it
more so?

**Short answer:** at run time, mostly yes. Packages are plain ES
modules that run unchanged on Node 17 to 24, Bun, Deno, and Chromium;
functions are functions, classes are classes with getters, lists are
frozen arrays, maps are `Map`s, `Int64` is a `bigint`, callbacks are
plain functions, and constructors with two or more parameters also take
an options object (`CommandSpec.new({ name: "frob" })`). The weak spot
is TypeScript. Nothing ships a `.d.ts`, so a strict TypeScript project
gets `TS7016` ("implicitly has an 'any' type") on the first import, and
an editor's JavaScript project silently gets `any`; the JSDoc types are
good once TypeScript is made to read them, but only three module hops
deep. One runtime bug matters more than the rest: a `filter` that
keeps every element freezes the array it was given, the caller's own
or the library's builder. Beyond that: implementing a library's
interface by subclassing it fails at run time, objects print as
`Url {}` and stringify as `{}`, failures are `Error`s with empty
messages, `orelse panic()` swallows the host's own errors, public names are escaped when they match the
runtime's helper names (`from_`, `empty_`, `it_`), and a bundler can't
drop anything a page doesn't use. Most fixes are small and not
breaking; a few are design questions for this RFC and for
[#164](../../164-exceptions/README.md).

## How this was studied

- Built the six showcase libraries (Argmas, Chromarite, Hrefine,
  Kelpto, Ordable, and Wherewith) with Temper's compiler (`temper build
  -b js`; `temper 0.7.0-alpha.0.267` at `13dc5669`, a release build
  whose working tree also changed how the backend runs JS tests, which
  shows only in the generated `scripts.test`), installed them into a
  user project's `node_modules` as `npm install` would lay them out,
  and ran each library's JS tour against them: all six match their
  `expected.txt` on Node 24.
- Wrote a probe library (about 150 lines of Temper: nullables,
  defaults, `Int` and `Int64`, lists and maps in and out, a module
  list, a builder held by a class, getters and a `var`, statics, a
  generic class, keyword-named members, a fun interface, an interface
  with a default method, bubbles and panics, and builders changed
  during their own callbacks), plus two small ones for names and
  `orelse`. Every snippet below was run; output is quoted as printed.
- Used it as JS and TS users would: Node ESM `import`, CommonJS
  `require`, TypeScript 7.0.2 (`tsc --strict`, the version the
  libraries' sites pin) against the JSDoc types and against
  declarations `tsc` emits from them, esbuild 0.28.2 bundles for the
  browser, and the tours bundled into headless Chromium 153. Runtimes:
  Node 17.3, 18.12, and 24.22, Bun 1.4.5, and Deno 2.9.8. No Node 20 or
  22 was available.
- Read the JS backend (`crates/temper-be-js`, especially `names.rs` and
  `translate/classes.rs`), its runtime
  (`crates/temper-be-js/runtime/temper-core`), `notes/api-compat.md`
  (its JS section), the JS translation in
  [#164's survey](../../164-exceptions/tom/claude-translations/js.md),
  and the sibling studies for [Lua](claude-lua-study.md),
  [Rust](claude-rust-study.md), and [C++](claude-cpp-study.md), whose
  cross-backend checks are repeated here.
- TypeScript's docs (typescriptlang.org) were reachable and are quoted;
  MDN and nodejs.org weren't, so built-in behavior is quoted from what
  Node 24 printed, and claims about other npm packages are from memory,
  marked as such, not rechecked against their sources.

## 1. Types and editors

### Today

Each library ships JSDoc only: `@param`, `@returns`, `@template`, and
`readonly T[]` for lists, with no `.d.ts` and no `"types"` field. What
TypeScript does with that depends on settings most users never touch:

| Setup | What a user gets |
|---|---|
| `tsconfig.json`, `strict` (default `maxNodeModuleJsDepth` 0) | `error TS7016: Could not find a declaration file for module 'jprobe'. … implicitly has an 'any' type.` |
| `jsconfig.json`, as an editor's JS project (depth 2) | No error, and every import is `any`: `maybe(true).toUpperCase()` passes |
| `allowJs` with `maxNodeModuleJsDepth` 3 | Full types (table below) |
| Importing the facade subpath, `from "jprobe/jprobe"`, depth 2 | Full types |

Depth matters because the types live three files down: `index.js` does
`export * from "./jprobe.js"`, which re-exports from
`jprobe.internal.js`. TypeScript's own docs advise against the setting
that makes this work: "Ideally this should stay at 0 (the default), and
d.ts files should be used to explicitly define the shape of modules"
([maxNodeModuleJsDepth](https://www.typescriptlang.org/tsconfig/maxNodeModuleJsDepth.html)).
Chromarite's site works around both: its `jsconfig.json` maps
`chromarite` to the output's `index.js` with `paths`, and turns
strictness off ("not strict, since plain JS and Temper's runtime
aren't written for it").

Once TypeScript reads the JSDoc, the types are good. One user file,
checked with `--strict --allowJs --maxNodeModuleJsDepth 3`:

```ts
const s = maybe(true);
console.log(s.toUpperCase());               // 3
console.log(describe(undefined));           // 5: String? parameter
const p = new Point(1);                     // 7
const q = new Point("a", "b");              // 8
p.x = 3;                                    // 9: getter only
console.log(p.nope);                        // 10
const b: Box<number> = boxed();             // 11: Box<String>
const l = nullables(); l.push("x");         // 12: List<String?>
const m = makeMap(); m.set("z", 1);         // 13: Map<String, Int>
new Bag().live.push("x");                   // 14: Listed<String>
class Circle extends Shape { area() { return 3; } }    // 15
console.log(describeShape({ area: () => 1 }));         // 16
console.log(scoreAll(["a"], (x) => x.length));         // 17
console.log(add64(1, 2));                              // 18: Int64
const n: number = parse64("1");                        // 20
```

| Line | TypeScript says | Right? |
|---|---|---|
| 3 | `TS18047: 's' is possibly 'null'` | Yes |
| 5 | `TS2345: Argument of type 'undefined' is not assignable to parameter of type 'string \| null'` | No: the code does `x == null`, so `undefined` works (bug 4) |
| 7, 8 | `Expected 2 arguments, but got 1`; `string` not assignable to `number` | Yes |
| 9, 10 | `Cannot assign to 'x' because it is a read-only property`; `Property 'nope' does not exist` | Yes |
| 11, 12, 14 | generic mismatch; `push` doesn't exist on `readonly …[]` | Yes |
| 13 | nothing | No: the map is frozen and `set` throws at run time (bug 5) |
| 15 | `TS2425: Class 'Shape' defines instance member property 'area', but extended class 'Circle' defines it as instance member function` | Matches the run-time failure (bug 1) |
| 16 | `Property 'describe' is missing` | Yes |
| 17 | `x` inferred as `string` | Yes |
| 18, 20 | `number` not assignable to `bigint`, and back | Yes |

Other gaps:

- **Classes don't have their interfaces' members.** Temper's `class
  Square extends Shape` becomes `class Square extends type(Shape)`, and
  TypeScript can't see what `type()` copies:
  `describeShape(new Square(2))` gives `TS2741: Property 'describe' is
  missing in type 'Square' but required in type 'Shape'`, and
  `new Square(2).describe()` gives `TS2339` (bug 2).
- **Declarations emitted from the JSDoc leak `any`.** Running `tsc
  --declaration --allowJs` over the generated code, the obvious way to
  ship a `.d.ts`, gives `declare const Point_base: any; export declare
  class Point extends Point_base`, for every class (29 in Argmas, 43 in
  Wherewith, 48 in kelpto-md). With those declarations, `pt.whatever`
  and `pt.foo(1, 2, 3)` type-check, because a class with an `any` base
  accepts any member. The runtime's `type()` is annotated `@return
  {Union}` with no `Union` type in scope.
- **The runtime fails users' strict builds.** Three runtime files start
  with `// @ts-check`, so a TS user who imports `@temperlang/core` (as
  Hrefine's tour must, for `Pair`) gets 35 errors in `core.js`,
  `regex.js`, and `float.js` (`Parameter 'jsonAdapter' implicitly has
  an 'any' type`, …); `skipLibCheck` covers only `.d.ts` (bug 12).
- **No prose.** `/** A point in the plane. */` on a Temper class, or on
  its getter, doesn't reach the output, so hovers show only signatures
  (bug 11). Same in Lua and Rust.
- **Callbacks are `(arg0: string) => number`.** Temper function types
  have no parameter names; a named fun interface (`Scorer`) could be a
  JSDoc `@callback Scorer`, so hovers say `scorer: Scorer`.

### What TypeScript users expect

`npm install foo`, then `import { x } from "foo"` with types, under
`strict`, with no settings. That means declarations in the package,
found through `"types"` (or a `"types"` condition in `"exports"`, or a
`.d.ts` beside each `.js`). The handbook: "Set the types property to
point to your bundled declaration file"
([publishing](https://www.typescriptlang.org/docs/handbook/declaration-files/publishing.html)).
From memory, not rechecked: the packages TS users reach for first
(zod, date-fns, and most of what DefinitelyTyped no longer needs to
cover) ship their own declarations, and a package without them is
expected to have a `@types/` package.

### Options

| Option | Gains | Costs |
|---|---|---|
| A. Point `"."` at the facade (`./jprobe.js`), or have `index.js` re-export from the internal file | Editor JS projects get types at their default depth | TS projects still get `TS7016`; still `allowJs` |
| B. `tsc --declaration` over the output at build time, with `type()` typed properly | Real `.d.ts`; `"types"` works | Needs `tsc` at build time; inherits every JSDoc gap (B fixes none of bugs 1, 2, 4, 5) |
| C. The backend writes `.d.ts` itself, from Temper's types | Exact types: `ReadonlyMap`, `T \| null \| undefined` parameters, interfaces as `interface` plus `implements`, docs, overloads where JSDoc can't say it | A second printer to keep in step with the JS |

A now, C as the goal. C also fixes the interface story cleanly: export
`Shape` as an abstract class whose abstract members are methods, and
declare `Square extends Shape` in the `.d.ts` (the runtime's
`Symbol.hasInstance` already makes `instanceof` agree).

## 2. Modules and packaging

### ESM, CommonJS, and runtimes

Generated packages are ESM only (`"type": "module"`), with `"exports"`
mapping `"."` and `"./<module>"` and keeping the `.internal.js` files
private (`import("hrefine/hrefine.internal.js")` gives
`ERR_PACKAGE_PATH_NOT_EXPORTED`; good). `require` of them:

| Runtime | `require("jprobe")` from a `.cjs` file |
|---|---|
| Node 17.3, 18.12 | `Error [ERR_REQUIRE_ESM]: require() of ES Module …/jprobe/index.js … not supported.` |
| Node 24.22 | Works (`p.__esModule` is `undefined`) |
| Bun 1.4.5 | Works (`p.__esModule` is `true`) |
| Deno 2.9.8 | Works |

Node made `require(esm)` work without a flag in 22.12 and 20.19 (from
the release notes, from memory; not checked here). ESM-only is a
reasonable choice in 2026, many well-known packages went ESM-only years
ago, but the package should say what it needs: no `"engines"` field is
written. The newest features the code relies on are the RegExp `d`
flag (`new RegExp(formatted, "dgu")` in the runtime's regex support),
private methods, and `??=`, all of which Node 17 handled; Node 16 is
the likely floor.

### package.json

What `temper build` writes for Hrefine, in full:

```json
{
    "name": "hrefine",
    "license": "Apache-2.0 OR MIT",
    "type": "module",
    "exports": { "./hrefine": "./hrefine.js", ".": "./index.js" },
    "scripts": { "test": "node --test \"test/**/*.js\"" },
    "dependencies": { "@temperlang/core": "0.7.0-alpha.0.267" },
    "devDependencies": { "@temperlang/std": "0.7.0-alpha.0.267" }
}
```

Problems, in order of impact:

1. **No `version` unless the library declares one.** Only Argmas does,
   so for five of six, `npm pack` fails: `npm error Invalid package,
   must have name and version` (bug 10).
2. **The runtime it pins isn't on npm.** `@temperlang/core` on npm
   stops at 0.6.0 (2025-12-30), and the runtime `temper build` writes
   has `"private": true`. Until 0.7 is published, a published library
   can't be installed.
3. **Exact pins, `"*"` between siblings.** Two libraries built by
   different Temper versions install two runtimes (13.8 KB minified
   each). They interoperate, since `isBubble` checks
   `Symbol.for("@temperlang/core.Bubble")`, which every copy shares,
   and interfaces carry their own symbols, but a bundle carries both.
   Kelpto's packages depend on each other as `"kelpto-core": "*"`, so
   any version satisfies them.
4. **Tests and maps ship.** With no `"files"` field, `npm pack` of
   Argmas includes `test/argmas.js` (264 KB, more than the library's
   171 KB) and the source map (29 KB). Kelpto's test suites are built
   as six more packages (`kelpto-gfm-tests`, …, up to 549 KB each).
5. **Source maps point outside the package.** `sources` is relative to
   the output directory: `["../../../src/jprobe.temper.md"]` in the
   default layout, and with `-o` elsewhere, a path climbing to the
   builder's home (`../../../../../../../../../home/<user>/projects/argmas/src/command.temper.md`).
   There's no `sourcesContent`, so `node --enable-source-maps` prints
   a path that doesn't exist on the user's machine (bug 9). The
   mapping itself is right: `at positive (…/jprobe.temper.md:19:21)`.
6. **Thin metadata.** No `description`, `repository`, `homepage`,
   `types`, `sideEffects`, or `engines`, though `config.temper.md`
   often has the first three.
7. **Subpaths repeat the root.** `"./hrefine"` and `"."` export the
   same names; Kelpto's are `kelpto-md/kelpto_md`, with an underscore.

**npm names.** All six unscoped names (`argmas`, `chromarite`,
`hrefine`, `kelpto`, `ordable`, `wherewith`) were free on the registry
on 2026-11-19; the runtime and std are under `@temperlang/`, which
users never need to name once section 3's leaks are fixed.

### Bundles and tree-shaking

esbuild, `--bundle --minify --format=esm`, one import against the whole
library:

| Entry | Minified | gzip |
|---|---|---|
| `import * as h from "hrefine"` | 107,515 | 40,839 |
| `import { HostKind } from "hrefine"` (an enum-like class) | 106,215 | 40,199 |
| `import * as c from "chromarite"` | 36,413 | 12,691 |
| `import { HueMethod } from "chromarite"` | 36,260 | 12,619 |
| `import { Dialect } from "wherewith"` | 107,168 | 29,146 |
| `import { greet } from "jprobe"` (a two-line function) | 2,343 | 939 |
| `import * as k from "@temperlang/core"` | 13,808 | 5,516 |

Nothing is dropped: in the probe's bundle all seven classes survive
beside `greet`. Every class is `class X extends type(...)`, and a
bundler must assume a call has side effects. Adding
`/* @__PURE__ */` before each `type(` (a `sed` over the output) took
the probe to 1,371 bytes and Chromarite's `HueMethod` bundle from
36,260 to 10,880. Hrefine stayed at 105 KB: its module-level statics
and tables (`HostKind$domain = new HostKind("domain")`, `const
specialHosts = parseSpecialHosts(specialHostTable)`) run at load, and
everything they reach stays. Chromarite's own site measures its bundle
the same way (36,010 bytes, 12,499 gzipped).

**Browsers.** Five tours, bundled for the browser, printed their
expected output in headless Chromium 153 (Argmas's needs
`process.argv`). The output needs ES2022 (class fields, private
methods, `??=`) and the RegExp `d` flag.

## 3. Values and API shape

### Null and undefined

**Today.** Temper's null is JS `null`; results are `T | null`;
nullable and optional parameters test `== null` or use `??=`, so
`undefined` and omitted arguments work too:

```js
p.maybe(false)               // null
p.describe(undefined)        // "none"
p.greet("A", undefined)      // "Hello, A"
p.nullables()                // [ 'a', null, 'c' ]
```

**What JS users expect.** Both appear in the platform: `null` from
`URL.parse("x")`, `"ab".match(/z/)`, and `querySelector`; `undefined`
from `Map.prototype.get` and `Array.prototype.find`. A library that
returns `null` for "no value" and accepts either is ordinary. The only
gap is the type: parameters say `string | null`, so TypeScript rejects
the `undefined` that works (bug 4). **Option:** type nullable
parameters `string | null | undefined` (or optional, `x?: string |
null`, where trailing). Not breaking.

### Numbers

**Today.** `Int` is a JS number kept to 32 bits with `| 0` and
`Math.imul`; `Float64` is a number; `Int64` is a `bigint`, wrapped to
64 bits. Nothing is checked at the boundary:

```js
p.addInts(2 ** 31 - 1, 1)         // -2147483648
p.addInts(1.5, 1)                 // 2
p.addInts("2", 1)                 // 21: "2" + 1 is "21", then | 0
p.add64(1, 2)                     // TypeError: Cannot mix BigInt and other types, use explicit conversions
p.add64(2n ** 63n - 1n, 1n)       // -9223372036854775808n
p.parse64("9007199254740993")     // 9007199254740993n
```

**What JS users expect.** Numbers are numbers; integer-ness is
checked where it matters, with a `RangeError` (`BigInt(1.5)` gives
`RangeError: The number 1.5 cannot be converted to a BigInt because it
is not an integer`; `"a".repeat(-1)` gives `RangeError: Invalid count
value: -1`). `bigint` for 64-bit values is now the norm, and TypeScript
users get `bigint` in the signature. The silent truncation of `1.5` is
the JS norm for bit operations, and TypeScript catches `"2"`.
**Option:** leave it; maybe check `Int` arguments of exported functions
in a debug build only. Lua's study found the same shape, with worse
consequences there.

### Strings

**Today.** JS strings, and Temper's string index is a UTF-16 offset,
so `String.end` is `s.length` and indexes line up with `slice`. Code
point reads are right (`firstCodePoint("😀x")` is 128512;
`codePoints("😀x")` is 2 where `.length` is 3). Positions a library
reports are the library's choice, and Hrefine's count code points, the
same in every language, so JS's `slice` takes the wrong text after an
astral character:

```js
const input = "https://😀😀.example/a\tb";
const e = checkUrl(input).errors[0];
String(e), e.position, e.length          // "invalid-URL-unit at 20", 20, 1
input.slice(e.position, e.position + 1)  // "/", not "\t"
```

**Option:** as in Lua, say so in each such API's docs, or add a
`utf16Position` beside it in JS; Temper can't decide it for libraries.

### Lists and maps

**Today.** Lists are arrays, frozen when Temper's type is `List`:
`nullables()` is frozen, assigning an element throws `Cannot assign to
read only property '0'`, and TypeScript sees `readonly string[]`. A
module-level list is returned as itself, but frozen, so it can't be
changed (Lua's and C++'s studies found such lists changeable). Plain
arrays go in without copying. That's the best part of the mapping.

Three holes:

- **`filter` freezes its input when it keeps everything.** The
  runtime's `listedFilter` returns `Object.freeze(ls)` when no element
  is dropped, freezing the array it was given rather than a copy. So
  `export let keepAll(xs: List<Int>): List<Int> { xs.filter { (x: Int):
  Boolean => true } }` freezes the caller's own array (`a.push(3)`
  afterwards: `TypeError: Cannot add property 2, object is not
  extensible`), and a library that filters its own `ListBuilder` and
  then adds to it fails the same way, in valid Temper code (bug 16).
  The fix is one `slice()`.
- **Builders the library holds leak.** A getter typed `Listed<String>`
  that returns a class's `ListBuilder` gives the builder itself:
  `bag.live.push("sneaky")` changes `bag.all`. TypeScript says
  `readonly string[]`, so only plain JS users can do it.
- **Maps are `Map`s that look writable.** A Temper `Map` is a
  `FreezeMap`, a `Map` subclass whose `set`, `delete`, and `clear`
  throw `TypeError` with an empty message; `Map.prototype.set.call(m,
  "z", 9)` still changes it. JSDoc says `Map<string, number>`, so
  TypeScript accepts `m.set(…)` (bug 5). Maps going in must be real
  `Map`s: `mapSize({ a: 1 })` returns `undefined`, and `mapGet({ a: 1 },
  "a")` throws `TypeError: map.get is not a function`. TypeScript
  catches both.

**What JS users expect.** Read-only results as frozen arrays and
`ReadonlyMap` (TypeScript's own type for exactly this), with any
`Map` or iterable accepted on the way in. **Options:** type `Map`
results as `ReadonlyMap<K, V>`; give `FreezeMap`'s errors a message
(`TypeError: Cannot set on a read-only Map`); return a snapshot
(`listBuilderToList`) or a frozen view for getters typed `Listed` when
the library holds a builder.

### Pairs and the runtime in APIs

Hrefine's `UrlSearchParams.fromEntries` takes Temper's `Pair`s, so its
tour starts with `import { Pair } from "@temperlang/core"`, the only
tour that names the runtime. JS's own form, `[["q", "a b"]]` (what
`new URLSearchParams` and `Object.fromEntries` take), is accepted, and
fails later, inside `toString`: `TypeError: Cannot read properties of
undefined (reading 'length') at formEncodeOnto`. And in TypeScript,
`new Pair("q", "a b")` is `TS2693: 'Pair' only refers to a type, but is
being used as a value here`: the runtime's `index.js` does `export *`
from both `pair.js` (the class) and `mapped.js` (a `@typedef … Pair`),
and TypeScript resolves the clash to the typedef (bug 6).

**Option:** accept `[key, value]` arrays (or any iterable of them)
wherever `Pair`s go in, as `Map` and `URLSearchParams` do; `Pair`
already has `[0]`, `[1]`, and `length`, so reading `p[0]` and `p[1]`
instead of `.key` and `.value` would take both. Then no user names the
runtime, as #676's principle 3 asks.

### Classes, getters, and printing

**Today.** Each class keeps its fields in `#private` fields with public
getters (setters for `var`s); writing a getter-only property throws in
strict code (`Cannot set property x of [object Object] which has only a
getter`), and statics are `static get`. That's tidy, and TypeScript
reads it as `readonly`. The cost is that nothing shows an object's
state:

```js
console.log(new Point(3, 4))                  // Point {}
console.log(Url.parse("https://example.com/a?b#c"))   // Url {}
console.log(Color.parse("rebeccapurple"))     // Color {}
String(Color.parse("rebeccapurple"))          // "[object Object]"
JSON.stringify({ u, c })                      // {"u":{},"c":{}}
structuredClone(new Point(3, 4))              // {}
```

Node prints its own `URL` with every part (`URL { href:
'https://example.com/a?b', origin: …, searchParams: URLSearchParams {
'b' => '' }, … }`), which is what users compare against. Node's hook is
`util.inspect.custom`, which is `Symbol.for("nodejs.util.inspect.custom")`
(checked: `true`), so a library can define it without importing
`node:util`. As a prototype, one function on each class's prototype
listing its getters gave, identically on Node, Bun, and Deno:

```js
Point { x: 3, y: 4, length: 5 }
Counter { count: 1, peek: 8 }
Color { space: Space {}, alpha: null, length: 1, width: 3 }
```

The runtime's `type()` builds every class's base, so it could add this
once. It should list stored properties only, not computed getters
(`length` above), and never private state.

**Equality.** `===` is identity. Some classes have an `eq` method
(`Url.eq`); `Color` has none. JS has no operator to hook, and the
platform's newer value types use `equals` (`Temporal`'s, from memory).
A question for #676: `eq`, `equals`, or both.

**Constructors.** Positional (`new Point(3, 4)`), with no argument
checks (`new Point(1)` makes a point whose `y` is `undefined`; JS
norm, and TypeScript catches it), plus `static new(props)` for two or
more parameters, typed with optional keys:
`CommandSpec.new({ name: "frob", about: "Frobnicate files." })`. Argmas's
tour reads well with it. JS's usual spelling for an options-object
factory is `from` (`Array.from`, `Temporal.PlainDate.from({ year,
month, day })`, from memory) or an options object to the constructor
itself; `.new(…)` is unusual but clear.

### Names

**Today.** Names keep Temper's camelCase, which is JS's own. Escapes,
from `names.rs`:

- **Module-level names** take `_` if they're JS keywords, contextual
  words (`from`, `of`, `get`, `set`, `type`, `as`, …), the 111 names
  the translator prints (runtime helpers such as `empty`, `bubble`,
  `panic`, `stringGet`, and `listedGet`, and globals such as `console`,
  `Map`, and `Math`), or `it` (for `node:test` in test files). So an exported function
  named `from`, `empty`, `it`, `stringGet`, or `console` is exported as
  `from_`, `empty_`, `it_`, `stringGet_`, `console_` (checked), though
  all are valid JS export names. A library's API changes if the runtime
  adds a helper with the same name.
- **Members** take `_` if they're keywords (`delete_()`, `else_()`,
  `new_`), though ES5 allows any name after a dot (`Map.prototype.delete`
  is one). Contextual words aren't escaped on members (`get class()`,
  `get get()`, `get static()`), and `static new(props)` reads
  `props.new` while the getter is `new_` (bug 8).

`notes/api-compat.md` keeps member escaping deliberately, to not break
users. Module-level escapes can be fixed without breaking anyone:
ES2015 export names are independent of bindings, so the facade can
`export { from_ as from, empty_ as empty }`, and even `export { delete_
as delete }` (imported as `import { delete as del }`). Exporting both
spellings for a release keeps old imports working.

### Callbacks and interfaces

**Today.** Function parameters and `@fun` interfaces take plain
functions, and the fun interface isn't exported at all (unlike Lua,
which exports an unused class table). Good.

Regular interfaces are classes, and the obvious way to implement one
fails:

```js
class Circle extends Shape { area() { return 3 * this.r * this.r; } }
new Circle(1).describe()   // TypeError: this.area is not a function
new Circle(1).area         // undefined
```

For TypeScript's sake (`classes.rs`: "an interface declares its
abstract members as fields with their types, initialized to an
`undefined` cast to `any`, which nothing stores: nothing makes an
interface's instance"), `Shape` has a field `area = undefined`, and a
user's subclass does make an instance, so the field shadows the user's
method (bug 1). A plain object fails differently (`TypeError:
s.describe is not a function`), as expected, since it lacks the
default. The working form, `class Circle extends type(Shape)`, needs
the runtime's `type`, and then TypeScript sees no `describe` (bug 2).

Replacing the field by a method stub (`area() { throw new
TypeError("Shape.area is abstract"); }`, checked by editing the
output) made `class Circle extends Shape` work: `describeShape(c)`
gave `shape of area 12.0`, `c instanceof Shape` was `true`, and
`Square` was unaffected, since `type()` copies the prototype before a
class's own methods. **Option:** that, plus `.d.ts` declarations as in
section 1, C; then subclassing the interface is the documented way, and
nobody imports `type`.

### Changing a collection during its own callback

The other studies' cross-backend check, repeated (`b` a `ListBuilder`
or `MapBuilder` changed by the callback walking it):

| Case | JS (Node 24) | Python | Lua 5.4 | C++ (its study) |
|---|---|---|---|---|
| `reduceFrom` that grows `b` | 12 | 1299 | 12 | heap-use-after-free |
| `map` that shrinks `b`, length | 3 | 2 | 2 | 3, reading past the end |
| `forEach` on a map, adding keys | 30 (sees new keys) | `RuntimeError: dictionary changed size during iteration` | 30 | stops early by luck |
| `forEach` on a map, removing a later key | 3 (skips it) | same `RuntimeError` | 3 | `std::out_of_range` |
| `sort` whose comparison grows `b`, length | 7 (6 on Bun and Deno) | `ValueError: list modified during sort` | 8 | heap-use-after-free |

JS is memory safe in all of them, but `map` reads past the shrunken end
and stores `undefined` in a list typed `number[]`:
`listedMap(b, (x) => { listBuilderRemoveLast(b); return x; })` gives
`[ 1, 2, undefined ]` (bug 13), and `sort`'s result depends on the
engine's algorithm. Map iteration follows JS's `Map.forEach`, which
visits keys added during the walk. Which behavior Temper promises is a
cross-backend question the C++ study raised; JS needs only `map` and
`filter` to stop at the live length (or snapshot) to be safe whichever
way it goes.

## 4. Errors

### Today

A bubble is the runtime's `class Bubble extends Error` (`name`
"Bubble"), thrown with no message; a panic is a plain `Error`, usually
with the message "panic"; runtime misuse surfaces as JS's own errors.

| What happens | What the JS user sees |
|---|---|
| `positive(-1)` (bubbles) | `Bubble` with message `""`; `e instanceof Error` is true |
| uncaught, Node 24 | `Bubble` and a stack into `@temperlang/core/core.js:303` and `jprobe.internal.js:142` |
| uncaught, `--enable-source-maps` | `at positive (…/jprobe/src/jprobe.temper.md:19:21)`, a path from the build machine |
| `needsPositive(-1)` (`orelse panic()`) | `Error: panic` |
| list index out of range | `Error: index 5 out of bounds for length 2` |
| `parseUrl("setup.html")` | `Bubble`, empty message; Hrefine's tour: "parseUrl throws a plain Error, with no message, so checkUrl says why" |
| `makeMap().set("c", 3)` | `TypeError` with message `""` |
| `orPanic("x", () => { throw new TypeError("host bug"); })` | `Error: panic`, `cause` undefined (bug 7) |
| same callback, `orelse -1` | `TypeError: host bug` (rethrown, right) |

The last two rows differ because `f(s) orelse panic()` compiles to
`try { return f(s); } catch { return panic(); }` with no `isBubble`
check, while other `orelse`s check it. Since the panic replaces
whatever was thrown, a bug in the user's callback (or a stack overflow)
reports itself as Temper's "panic", with the original lost.

Expected failures are also slow, because each bubble captures a stack:

| 20,000 inputs that aren't URLs (Node 24, 5 runs, ms) | |
|---|---|
| Hrefine `Url.parse(u) === null` | 59–76 |
| the same, `Error.stackTraceLimit = 0` | 22–24 |
| built-in `URL.parse(u) === null` | 2.4–2.6 |
| built-in `new URL(u)` in `try` | 53–55 |

### What JS users expect

From the platform, as Node 24 printed them: misuse throws `TypeError`
or `RangeError` with a message (`TypeError: Reduce of empty array with
no initial value`); bad input throws a specific class
(`SyntaxError: Expected property name or '}' in JSON at position 1`;
`new URL("setup.html")` throws `TypeError: Invalid URL` with `code:
'ERR_INVALID_URL'`); and newer APIs offer a non-throwing twin
(`URL.parse` returns `null`), which is exactly Hrefine's `Url.parse` /
`parseUrl` pair. Libraries (from memory: axios's `AxiosError`, zod's
`ZodError`) throw their own `Error` subclasses with a `name`, a
message, and since ES2022 a `cause` (`new Error("outer", { cause })`
works on every runtime here). Tests match on the class and the
message, so an empty message gives them nothing to match.

### Options and ties to #164

[#164's JS translation](../../164-exceptions/tom/claude-translations/js.md)
proposes library-named `Error` subclasses (`class WherewithError
extends Error`, `SqlProblem extends WherewithError`), `name` set as a
string literal so minified stacks still read `SqlProblem: …`, and
`cause`. This study supports it, with these additions:

- **Now, whatever #164 decides:** `orelse panic()` must rethrow
  non-bubbles, and a panic should carry what it replaced
  (`new Error("panic", { cause: e })`); bubbles get messages where the
  library has one; `FreezeMap`'s `TypeError`s get messages.
- **Misuse stays a `TypeError` or `RangeError`.** Out-of-range indexes
  could be a `RangeError` (today a plain `Error`); library failures get
  library classes, not built-in categories.
- **Keep the nullable twin.** `Url.parse` beside `parseUrl` matches
  `URL.parse` beside `new URL`; #164's declared failures shouldn't
  remove that shape.
- **Stack capture is the cost.** A bubble that an `orelse` catches
  inside the library never needs a stack; V8's
  `Error.captureStackTrace` or a non-`Error` internal signal, converted
  to a library `Error` only when it leaves the library, would make
  `Url.parse` on bad input several times cheaper. Bubbles caught by
  `orelse` today never reach users, so this is free to change.
- **Panics aren't caught by `orelse`** (good, already true for the
  `isBubble` form), and `Test.assertPanics` relies on panics being
  plain `Error`s; a panic class (`TemperPanic`?) would name Temper,
  which principle 1 rules out, so a plain `Error` with a message and
  `cause` is right.

## 5. Runtimes

The probe script (78 checks) printed identical output on Node 17.3,
18.12, and 24.22. Bun and Deno differ only in engine messages
(JavaScriptCore's `Attempted to assign to readonly property.`) and in
the `sort` row above. Every tour ran on each:

| Runtime | Tours (6) | Probe | `require` | Notes |
|---|---|---|---|---|
| Node 17.3, 18.12 | not run | same as 24 | `ERR_REQUIRE_ESM` | |
| Node 24.22 | all match | 78 checks | works | |
| Bun 1.4.5 | all match | engine messages differ | works | |
| Deno 2.9.8 | all match | `sort` only | works | reads `node_modules` with a `package.json` present |
| Chromium 153 | 5 match (esbuild bundle) | not run | — | Argmas's tour needs `process` |

Deno users increasingly expect packages on JSR, with TypeScript
sources; with `.d.ts` files, an npm package works through `npm:`
specifiers, so JSR can wait.

## 6. Speed and size

Microbenchmarks against hand-written JS doing the same work, 5 runs
after warm-up, ranges in ms over two sessions on a noisy shared machine:

| Case | Node generated | Node hand | Bun generated | Bun hand |
|---|---|---|---|---|
| Sum 1M floats in a list | 7.8–9.0 | 4.8–5.6 | 66–74 | 60–68 |
| Sum 1M ints through a callback | 7.9–9.2 | 7.2–11 | 68–77 | 122–127 |
| Count code points, 600K chars | 2.0–2.5 | 4.8–7.7 | 2.1–2.2 | 1.3 |
| 1M calls through `orelse` (none failing) | 2.9–3.5 | 1.3–1.5 | 1.0 | 1.0 |
| 1,000 failing calls (bubble caught) | 1.7–2.4 | — | 0.35–0.43 | — |
| Parse 20,000 URLs: Hrefine vs `URL` | 45–51 | 10–23 | 38–54 | 6.8–8.3 |

Deno matched Node within noise. The generated loops are close to
hand-written ones: indexing goes through `listedGet` (a bounds check
and a call, about 1.6 times a bare loop on V8), and code point counting
beats `for…of`. A `try` around a call costs little when nothing
throws; a throw costs about 2 µs, most of it the stack (section 4).
Hrefine parses at a quarter to half the speed of Node's C++ `URL`,
which is fair for pure JS.

**Size.** Generated `.internal.js` files run from 67 KB (Ordable; 16 KB
gzipped) to 388 KB (kelpto-md; 61 KB gzipped), with JSDoc types making
up a good part, plus the runtime (14 KB minified, 5.5 KB gzipped, as
bundled). Import time on Node 24: 5 ms for the runtime, then 4 to 14
ms per library. Generated code reads well; the noise is casts through
`unknown` where TypeScript can't see `type()`'s mixins (441 in
kelpto-md, 298 in Wherewith, none in Chromarite, Hrefine, or Ordable).

## Recommendations

**Quick wins** (none breaking):

1. Make editor types work at default settings: export `"."` from the
   root facade (or re-export from the internal file in `index.js`), so
   JS projects at depth 2 see the types.
2. Interfaces: abstract members as stub methods, not fields, so
   `class Circle extends Shape` works; type `type()`'s result so
   classes have their interfaces' members in TypeScript.
3. JSDoc: nullable parameters `T | null | undefined`; `Map` results as
   `ReadonlyMap<K, V>`; named fun interfaces as `@callback`; Temper's
   doc comments as JSDoc prose.
4. Errors: `orelse panic()` rethrows non-bubbles; panics carry `cause`;
   bubbles and `FreezeMap`'s `TypeError`s carry messages.
5. An inspect hook on `type()`'s base listing stored public properties,
   so `console.log` shows state on Node, Bun, and Deno.
6. `package.json`: a default `version` (or an error at build time),
   `"files"` without `test/`, `description`, `repository`, and
   `homepage` from the config, `"engines": { "node": ">=16" }` (or
   what CI tests), `"sideEffects": false`, and sibling dependencies on
   the same version range instead of `"*"`.
7. Source maps with paths inside the package and `sourcesContent`, or
   not shipped.
8. `/* @__PURE__ */` on `type(…)` heritage calls and on module-level
   `new` of statics.
9. The runtime: `filter` copies before freezing (bug 16, the most
   serious found); drop `// @ts-check` from shipped files or fix their
   35 strict errors; export `Pair` once, so TypeScript can construct it.
10. Module-level escapes only on bindings: the facade exports
    `from_ as from`, and so on, keeping the escaped names too for a
    release.

**Medium changes:**

11. Ship `.d.ts`, written by the backend from Temper's types (section
    1, option C), with `"types"` conditions in `"exports"`.
12. Accept `[key, value]` arrays and other iterables where `Pair`s and
    `Map`s go in, so no user imports `@temperlang/core`.
13. `map` and `filter` stop at the live length; getters typed `Listed`
    return a snapshot when the library holds a builder.
14. Bubbles caught inside the library skip stack capture.
15. Lazy module-level tables and statics, so bundles drop what a page
    doesn't use.
16. Publish `@temperlang/core` 0.7 before any library, and depend on it
    by range (`^0.7.0`), so libraries from different Temper releases
    share one runtime.

**Design questions for #676 and #164:**

17. **Failure classes** *(breaking for code matching `Bubble`)*: #164's
    library-named `Error` subclasses with `name`, `message`, and `cause`;
    misuse as `TypeError` and `RangeError`; the nullable twin kept.
18. **Member names** *(breaking)*: stop escaping keywords after a dot
    (`delete()`, `new`), as `notes/api-compat.md` declined to; at least
    make `static new(props)` and getters agree.
19. **The options-object factory's name:** `new`, `from`, or an
    options object to the constructor itself.
20. **Equality and display as API:** `eq` or `equals`; whether
    `toString`, the inspect hook, and `toJSON` are generated, and which
    properties they show, since users will rely on them.
21. **Positions in strings:** whether JS APIs report UTF-16 offsets
    (the library's choice, but #676 could give libraries a way to say
    so per backend).
22. **Callback mutation:** which result Temper promises when a
    collection changes during its own `reduceFrom`, `map`, `forEach`,
    or `sort` (JS, Lua, Python, and C++ all differ today).
23. **Is the runtime ever named?** With 2, 9, 12, and 17, JS users never
    import `@temperlang/core`.

## Bugs found

On Temper `13dc5669` (`temper 0.7.0-alpha.0.267`), Node 24.22, and
TypeScript 7.0.2 unless noted; `jprobe` is built from the Temper shown.

1. **Subclassing an interface breaks its default methods:** with
   `export interface Shape { public area(): Float64; public describe():
   String { "shape of area ${area().toString()}" } }`, JS's `class Circle
   extends Shape { area() { return 3; } }` gives `new Circle().describe()`
   → `TypeError: this.area is not a function`; the interface's
   `area = /** @type {any} */ (undefined);` field shadows the method.
   TypeScript reports `TS2425`.
2. **Implementing classes lack their interfaces' members in
   TypeScript:** with `export class Square(public side: Float64) extends
   Shape { … }`, `describeShape(new Square(2))` gives `TS2741: Property
   'describe' is missing in type 'Square'`, and `new
   Square(2).describe()` gives `TS2339`.
3. **Types silently become `any` in editors:** a `jsconfig.json` with
   `strict` and default settings accepts `maybe(true).toUpperCase()` and
   `new Point(1)`; through the facade subpath (`"jprobe/jprobe"`), both
   are reported. In a `tsconfig.json` the import is `TS7016`.
4. **Nullable parameters reject `undefined` in TypeScript:**
   `export let describe(x: String?): String { … }` is typed `x: string |
   null`; `describe(undefined)` gives `TS2345` but works.
5. **Frozen maps typed as writable:** `export let makeMap(): Map<String,
   Int> { new Map([new Pair("a", 1)]) }` is typed `Map<string, number>`;
   `makeMap().set("c", 3)` type-checks and throws `TypeError` with an
   empty message; `Map.prototype.set.call(m, "z", 9)` succeeds.
6. **The runtime's `Pair` is a type only in TypeScript:** `import { Pair }
   from "@temperlang/core"; new Pair("q", "a b")` gives `TS2693`
   (`mapped.js`'s `@typedef … Pair` clashes with `pair.js`'s class
   through `index.js`'s `export *`). Hrefine's `fromEntries([["q", "a
   b"]])` is accepted and fails later in `toString` (`Cannot read
   properties of undefined (reading 'length')`).
7. **`orelse panic()` swallows host errors:** `export let orPanic(s:
   String, f: fn (String): Int throws Bubble): Int { f(s) orelse panic()
   }` compiles to `catch { return panic(); }`; a callback throwing
   `TypeError("host bug")` surfaces as `Error: panic`, `cause`
   undefined.
8. **Public names escaped for runtime and test names:** `export let
   from(…)`, `empty()`, `it(…)`, `stringGet(…)`, and `console(…)` are
   exported as `from_`, `empty_`, `it_`, `stringGet_`, `console_`.
   Members: `export class Keywords(public new: Int, public class:
   String)` has getters `new_` and `class`, while `Keywords.new({ new:
   1, class: "c" })` takes `new`.
9. **Source maps point outside the package:** `sources` is
   `["../../../src/jprobe.temper.md"]` in the default layout and climbs
   to the builder's absolute home directory with `-o`; no
   `sourcesContent`.
10. **Unpackable packages, tests shipped:** five of the six libraries'
    `package.json` have no `version`, and `npm pack` fails with
    `Invalid package, must have name and version`; Argmas's pack
    includes `test/argmas.js` (264 KB); Kelpto's siblings depend on each
    other as `"*"`.
11. **Doc comments dropped:** `/** A point in the plane. */` before
    `export class Point` and before its getter produce no JSDoc prose.
12. **The runtime fails strict TypeScript builds:** importing
    `@temperlang/core` from a strict project with `allowJs` gives 35
    errors in `core.js`, `regex.js`, and `float.js`, whose `// @ts-check`
    turns checking on.
13. **`map` stores `undefined` when its callback shrinks the builder:**
    `listedMap(b, (x) => { listBuilderRemoveLast(b); return x; })` on
    `[1, 2, 3]` gives `[ 1, 2, undefined ]`.
14. **Bubbles have no message:** `positive(-1)`, `parseUrl("setup.html")`,
    and `parseInt("x")` all throw a `Bubble` whose message is `""`.
15. **Nothing tree-shakes:** `import { HostKind } from "hrefine"`
    bundles to 106,215 bytes against 107,515 for the whole library;
    `import { greet } from "jprobe"` keeps all seven classes, since
    `extends type()` is a call a bundler must keep.
16. **`filter` freezes its input:** `export let filterThenAdd(): Int {
    let b = new ListBuilder<Int>(); b.add(1); b.add(2); let kept =
    b.filter { (x: Int): Boolean => x > 0 }; b.add(3); kept.length }`
    throws `TypeError: Cannot add property 2, object is not
    extensible`; `keepAll(a)` (above) leaves the caller's `a` frozen.
    `listedFilter` ends with `Object.freeze(fullyFiltered)`, which is
    `ls` itself when nothing was dropped.
