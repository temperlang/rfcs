Common ground for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)):
decisions that both [declared failures](claude-proposal-declared.md) and
[failures as values](claude-proposal-values.md) need, and that can be
made before choosing between them. Drafted by Claude, 2026-11-17.
Evidence: [claude-findings.md](claude-findings.md) and
[claude-explore/](claude-explore/README.md). Syntax marked
**HYPOTHETICAL** doesn't compile today.

## `return`, `break`, and `continue` as expressions

Today `f() ?? return null` and `f() orelse return null` don't parse, so
propagating absence takes a hoisted `let` and an `if`, and hoisting one
call means hoisting everything evaluated before it
([explore](claude-explore/README.md#what-dropping-throws-bubble-would-take)).
Making all three expressions of type `Never` (as in Kotlin and Rust) is
useful under either proposal:

```temper
// HYPOTHETICAL
let tree = parseJson(text) ?? return null;
let n = s.toInt32() orelse continue;
```

## Which builtins panic

Of 596 `orelse`s in the surveyed libraries and std, 500 are
`orelse panic()`: on `as` downcasts (204), list or map reads (56),
`appendCodePoint` (40), `/` and `%` (14), `String.fromCodePoint` (6), and
conversions (1). Bubbles from indexing and division also spread
`throws Bubble` through 31 of Chromarite's 52 declarations
([findings §3](claude-findings.md#3-real-cases-in-public-libraries)).
Suggested split:

| Panic (bugs, avoidable by a cheap check) | Stay recoverable (where libraries recover) |
|---|---|
| Int `/` and `%` by zero; list access out of bounds (already panics by contract); `as` downcasts the author knows can't fail | `String.toInt32`, `toInt64`, `toFloat64`; `parseJson`; `Date.fromIsoString`; `as` on untrusted data |

Float64 division by zero needs its own decision: bubble everywhere, as
documented, or follow IEEE 754 (Infinity and NaN), as C++, C#, Java, JS,
and Lua already do. Narrowing conversions (`Int64.toInt32`), `appendCodePoint`, `Mapped.get`,
and how `as` tells a known-safe downcast from a check on untrusted data
are judgment calls, best settled one by one.

## What `orelse` catches

`orelse` (and `catch`, if added) handles only Temper failures declared by
the expression it covers. It never catches a panic, a host exception, a
stack overflow, or an out-of-bounds read. Today it catches far more on
five of seven backends: everything in C#, JS, and Lua, any
`RuntimeException` in Java, and any `Exception` in Python, so a host bug
inside a callback becomes the fallback value
([findings §1](claude-findings.md#host-exceptions-inside-callbacks)).
That needs one Temper failure type per backend that host code can also
catch selectively, and builtins raising it rather than `ValueError`,
`NumberFormatException`, or Lua strings.

## Precedence

Today `orelse` (4) and `??` (9) bind looser than `==`, so
`half(k) orelse 0 == 1` means `half(k) orelse (0 == 1)`, and the frontend
accepts the type mismatch
([explore](claude-explore/README.md#operator-precedence)). Either:

- move the default operators above comparison and equality and below
  arithmetic, at one shared level, as Kotlin's `?:`, Swift's `??`, and
  Zig's `orelse` are; or
- require parentheses where they mix with comparison or logical
  operators, as JavaScript does for `??` with `&&` and `||`.

Either way, the type checker should reject a fallback whose type doesn't
fit. A propagation operator, in either proposal, should bind at call
level (left to right with `.` and calls), not collide with `?.` (so not
postfix `?`), and say how it combines with `await`: Rust writes
`f().await?` so the awaited value's failure propagates. Postfix `!` reads
as "assert not null" to TypeScript, Kotlin, C#, and Swift users, which is
worth weighing.

## Lowering a local failure to a branch

Where a failure is raised and handled in one function, directly or after
inlining, the compiler can emit a plain branch instead of an exception.
No language change is needed. On C++, C#, Java, and JS it removes the
whole failure cost in parsing loops, from 2 times at 1 percent failures to
about 100 times at 90 percent; it's roughly neutral on Python and Lua
(Lua saves the closure and `pcall`), and Rust has it already
([findings §2](claude-findings.md#when-lowering-would-pay)). Under the
values proposal this is the normal case; under declared failures it's an
optimization.

## Panics per backend

A panic follows each backend's idiom (process exit in some, an exception
that's uncatchable by convention in others), and Temper gives no
guarantee that one is recoverable, so library code must not rely on
catching one. What the RFC pins down: `orelse` never catches a panic
(today it does on JS and Lua), and a panic's message reaches the user
(C++ prints none today and can lose earlier output).

## Panics in test runners

A test that panics is reported as a failed test with its message, and the
other tests still run. Today C# and C++ lose the whole run ("0 of N, N
not run"); interp, Java, Lua, Python, and Rust already report each test
on its own ([findings §1](claude-findings.md#panics-in-temper-test)).

## Compatibility of failure changes

Under either proposal, adding or changing the failure an exported
function can produce changes what host code catches or checks, in every
backend. The RFC should say which changes are compatible (probably adding
a variant is not, in languages with exhaustive matching) and record
host-visible names in `temper.keep`.

## Bugs to fix as part of the RFC work

From [findings §1](claude-findings.md#bugs-found), most touch what
`orelse` catches or how builtins fail, so they fit this work; any that
proves urgent can go first.

| # | Bug | Settled by |
|---|---|---|
| 1 | JS and Lua: `orelse` catches `panic()` | what `orelse` catches |
| 2 | Float64 `/` and `%` by zero don't bubble on five backends | which builtins panic |
| 3 | out-of-bounds list reads caught by `orelse` on six backends | what `orelse` catches |
| 4 | JS runtime: `listed.js` calls `bubble()` without importing it | which builtins panic (list access) |
| 5 | `String.toInt32` accepts different strings per backend | which builtins panic (recoverable ones must agree) |
| 6 | C++ loses console output on panic, and prints no reason | panics per backend |
| 7 | C# and C++ test runs report nothing for a panicking test | test runners |
| 8 | a bubbling `await` in an `async` block fails at translation | either proposal's async rules |
| 9 | bubbling generators aren't translated | either proposal's generator rules |
| 10 | a non-bubbling function passed as a bubbling `@fun interface` fails on Python | either proposal |
| 11 | JS: exported interface methods emitted as class fields | either proposal (host callbacks) |
| 12 | Lua builtins fail through incidental Lua errors | what `orelse` catches |

The explorations add a few more: the precedence trap above, a `when` over
a generic sealed interface not seen as exhaustive, and narrowing after
`if (r is Failed<…>) { return r; }` failing in backends
([explore, observations 10 and 11](claude-explore/README.md#observations)).
Turning the probes in findings §1 into a shared functional test would let
the RFC state current behavior as tested facts.
