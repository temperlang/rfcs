Claude's initial thoughts on Temper's failure handling (`bubble`, `throws
Bubble`, `orelse`, `panic`), as input for an RFC on
[temperlang/temper#164](https://github.com/temperlang/temper/issues/164),
2026-11-17. Not a proposal yet; a list of what works, what strains, and what
to find out first.

## What works well

- **Failure is part of a function's type.** `throws Bubble` must be declared,
  and a caller must handle it (`orelse`) or declare it too. Like Swift's
  `throws`, it's checked without Java's weight: nothing fails silently, and
  there's no hierarchy of exception types to manage.
- **Bubble carries no payload,** so it translates cheaply: each backend can
  use its natural mechanism (exceptions in C#, Java, JavaScript, and Python;
  return values in Rust; whatever fits in C++ and Lua) without carrying a
  class hierarchy across languages.
- **`panic` is separate** from recoverable failure: the split Rust, Go, and
  Swift settled on, which keeps "this can fail" meaningful.
- **`orelse` is an expression,** so the common case stays short:
  `s.toInt() orelse 0`.

## Where it strains

1. **No reason comes with a failure.** A caller learns that an operation
   failed, not why. Libraries that need reasons build their own result
   values instead: Argmas returns parse errors as values, and parsers and
   validators generally do the same. So Temper code ends up with two error
   styles, `throws Bubble` for "it failed" and hand-made result classes for
   "here's what went wrong".
2. **What host code sees.** A Python, Java, or C# program calling a Temper
   library gets a generic failure from a bubbling call, without a type to
   catch selectively or a message saying which operation failed and why.
   For libraries meant to be used from every language, that's the first
   thing their users meet when something goes wrong.
3. **Cost on backends where bubbling is an exception.** Throwing is slow on
   the JVM, .NET, Python, and JavaScript. Code like `toInt() orelse …` in a
   parsing loop pays for an exception on every miss. Where the `bubble` and
   its `orelse` end up in one function (directly, or after inlining), the
   compiler could lower them to a plain branch; worth measuring before
   deciding anything in the language. The same could apply to private and
   internal functions, returning a failure value instead of throwing, but
   then exported functions must turn it back into the host's exception at
   the boundary, since that's the API host code expects. Whether that's
   faster overall depends on how often failures happen and how deep they
   travel internally, so it needs measuring per backend, not assuming.
4. **Which builtins bubble.** Division by zero bubbles, Float64 division by
   zero too, and so do conversions such as `Int64.toInt32`. That pushes
   `orelse` into arithmetic code where a failure would really be a bug, which
   is #164's point about converting more builtins to `panic`. The docs
   already carry the question (`Int64.toInt32`: "Should this panic
   instead?").
5. **Edges that aren't pinned down,** each probably handled a little
   differently per backend today:
   - bubbling across `await` and out of generators;
   - whether host code can catch a `panic`, and whether test frameworks
     report it as a failure or a crash;
   - host exceptions raised inside connected functions: do they become a
     Bubble, a panic, or pass through unchanged?
   - typing gaps around `Bubble` itself
     ([#108](https://github.com/temperlang/temper/issues/108),
     [#109](https://github.com/temperlang/temper/issues/109)) and backend
     bugs with functions ending in `panic()` or `bubble()`
     ([#203](https://github.com/temperlang/temper/issues/203),
     [#536](https://github.com/temperlang/temper/issues/536)).

## Directions to weigh

- **Keep `throws Bubble` as is, add a standard result type to std** for
  failures with reasons. Smallest change; leaves two styles, but makes the
  second one shared rather than per library.
- **Typed failures, as Swift 6's `throws(E)`:** a function declares the type
  of value it fails with (`throws ParseError`), `orelse` can see it, and
  `throws Bubble` stays as the no-payload case. Each backend maps a typed
  failure to its idiom: an exception class carrying the value in C#, Java,
  JavaScript, and Python, `Result<T, E>` in Rust, an error value in Lua, and
  a choice for C++ (exceptions, or `std::expected` where available). This
  covers both points 1 and 2, at the cost of more translation work.
- **#164's direction,** explicit kinds you can only catch if declared, with
  no details or hierarchies, plus more builtins panicking: close to typed
  failures without payloads. Whether payloads are wanted is probably the
  main question to settle.
- **Independent of the above:** the branch lowering in point 3, and moving
  bug-like builtin failures to `panic` (point 4), can each be decided on
  their own.

Whichever way, the representation per backend should be chosen with what
host code sees in mind, since that's API: exception type names, messages,
and how a host program tells Temper's failures from its own.

## Before deciding

1. **A behavior table across backends,** as a shared test: bubble and panic
   inside and across functions, across `await`, out of generators, through
   connected functions, and what a host caller catches (type and message)
   in each language. Cheap, likely to find bugs, and it states the current
   semantics precisely.
2. **Measure point 3:** `orelse` on a failing conversion in a loop, per
   backend.
3. **Collect real cases** from existing Temper libraries: where they bubble,
   where they built their own result values instead, and what their users
   in each language would want to catch. Those cases are the test of any
   design.

[#163](https://github.com/temperlang/temper/issues/163) (closed) surveys how
each language could represent Bubble and panic, and is good background for
the representation question.

## Comparing Tom's and Mike's notes

Added the same day, after reading [tom-thoughts.md](tom-thoughts.md) (the
#164 proposal, 2024) and [mike-thoughts.md](mike-thoughts.md) (2026-09).
Findings from the behavior table, measurements, and library survey will be
cited here once they're in.

### Evidence so far

From [claude-findings.md](claude-findings.md):

- **Messages are what libraries miss most.** Four of six public libraries
  built a second error channel (Argmas's `ArgError`, Hrefine's `UrlCheck`,
  Wherewith's problem strings, Kelpto's error lists); Hrefine and Wherewith
  say it's because a bubble carries no message. Both a single declared
  failure type and declared kinds fit the cases surveyed, so the evidence
  doesn't choose between Tom's and Mike's shapes. Accumulated errors (many
  problems from one call) stay return values under any design.
- **Most `orelse` today is an assertion:** roughly 85 to 95% are
  `orelse panic()` on division, `%`, downcasts, and similar, which supports
  moving those builtins to `panic`.
- **Today's behavior is less consistent than the design implies:** `orelse`
  catches far more than Temper failures on five of seven backends (host
  exceptions, stack overflows, out-of-bounds reads become the fallback
  value); `panic` ranges from killing the process (C#, C++) to being caught
  by `orelse` (JS, Lua); host code mostly catches the most general exception
  type, with no message. Twelve bugs are listed with repros; several can be
  fixed before any language change.
- **Cost:** on the success path `orelse` is free except in Lua. A failure
  costs about 0.3 to 19 µs depending on backend, so at 1% failures C#,
  Java, and JS loops take about twice as long, and at 10% several times
  longer, than a null-returning version. Throwing without a stack trace is
  3 to 30 times cheaper where the runtime allows it (not .NET 6). Failure
  values inside a library with exceptions only at exported functions pay
  off only when failures cross many frames first; lowering a `bubble` and
  `orelse` that meet in one function to a branch is the cheap, safe win.

### Where they agree

- **Failures are declared and explicit,** with no automatic propagation:
  Tom sketches `try f()` or `f()!`, Mike something like Rust's postfix `?`.
- **No hierarchies, and no attempt to mirror host languages' own.** Tom:
  only error kinds declared in Temper are visible to Temper; host standard
  exceptions are panics. Mike: no type checks on builtin exceptions, and a
  very simple std.
- **Panics are for programmer errors;** more builtins should panic; errors
  are for exceptional cases, not common branching (nullables cover those).
- **Coarse handling is the style to encourage,** with finer handling
  available where a library wants it.

### Where they differ, and how they might combine

1. **Several error kinds per function (Tom) or exactly one failure type
   (Mike).** Mike's reason is real: unions are hard to translate and hard
   for the type solver. Tom's use cases, different failures from one
   function and forwarding another library's failures, are covered in
   Mike's design by a sealed interface for the variants and conversion with
   a cause for forwarding. Tom's `error case Baddie` declarations could be
   the sugar Mike asks for: declaring cases builds the sealed type. One type
   at the type level, several cases in the syntax.
2. **Details.** Tom: none, or a best-effort message. Mike: every throwable's
   factory takes an optional message and an optional cause, which Temper
   code can't necessarily read back. That's a good middle ground: host code
   gets messages and chained causes, which is what Python, Java, and C#
   users look for, while Temper's semantics don't depend on them.
3. **Host types.** Tom: Temper sees only its own errors. Mike: user-declared
   throwables may be connected to host exception types, with
   `orelse rethrowAs<T>()` for conversion. Compatible: host exceptions stay
   invisible to Temper unless connected to a declared type on purpose.
4. **Syntax:** `orelse(e)` and `try`/`catch` (Tom), `catch` with `match`
   coverage over sealed variants (Mike), `!` or `?` for propagation. The
   least settled part, and the least important to settle first.

### Further comments

- **Can Temper code read the fields of a caught user-defined failure?** If a
  sealed variant is an ordinary class (`MissingValue(option)`), reading its
  fields is what lets libraries use failures instead of hand-made result
  values. Mike's opacity seems aimed at message and cause, not at user
  fields. Suggested: user-declared fields readable, message and cause
  opaque; the RFC should say so explicitly either way.
- **What host code catches is API, and should be specified per backend.**
  For example, each declared failure type becomes an exception class named
  after the Temper type, and a sealed type's variants become subclasses of
  one generated base, so host code can catch one variant or all of them.
  That's a one-level hierarchy that exists only in host code, consistent
  with "no hierarchies" in Temper. Lua needs a tag field (as Tom noted);
  Rust, a `Result` with an enum; C++, exceptions or `std::expected` by
  configuration.
- **Stack traces are much of the cost** behind the concern that errors are
  expensive. The JVM can throw without capturing one, JavaScript can throw a
  plain object, and Python can reuse an instance; .NET has no cheap option.
  Mike's opaque design leaves each backend free to choose, possibly by
  configuration (cheap in production, traces in tests). To be measured.
- **Keeping cost down inside a library:** failures that stay internal to
  a library (private functions, or a `bubble` caught in the same function
  after inlining) could be values rather than thrown exceptions, converted to
  the host's exception at exported functions. Whether that wins depends on
  failure rates and depth; to be measured, not assumed.
- **`throws Bubble` as the no-detail case.** Existing code should keep
  working: `throws Bubble` becomes the failure type with nothing declared,
  and migration to declared types happens library by library. The RFC needs
  a section on this, and on what `orelse` without a binding means for typed
  failures (likely: catch anything the expression declares).
- **Async and generators:** a failure crossing `await` or leaving a
  generator should keep its type. Each backend's promise and iterator
  machinery handles this differently, so it belongs in the behavior table.
- **Order of decisions:** semantics first (single type, sealed variants,
  readable fields, opaque message and cause, what hosts catch, which
  builtins panic), then representation per backend, then syntax chosen by
  rewriting real library code in each candidate.

### Representations beyond the current backends

Readable failure fields and Mike's message and cause don't block languages
without exceptions; each has its own pattern for "kind plus details":

- **Zig:** error sets are codes with no data (`error.MissingValue`), by
  design. The standard library's idiom for details is a diagnostics
  out-parameter (as `std.json` does). A Temper function failing with
  `MissingValue(option)` could return `ArgError!T` for the kind and fill
  an optional `*Diagnostics` the caller passes in with the fields, message,
  and cause; `try` and `catch` stay idiomatic, and callers that don't care
  pass nothing. Temper-to-Temper calls inside generated code could return
  a tagged union instead.
- **C:** the GLib `GError**` pattern: return a status code (zero for
  success, one code per variant), the value through an out-pointer, and an
  error struct with kind, fields, message, and cause that the caller frees.
  An allocation per failure, acceptable for exceptional cases.
- **Out-parameters and compatibility.** Adding an out-parameter to an
  existing function later breaks source and binary compatibility in C and
  Zig, unlike adding an optional parameter in languages with defaults. So
  any function that can fail should have its diagnostics parameter from
  its first version, even when it fails without details (a `throws Bubble`
  function would still take a nullable diagnostics pointer), and the
  diagnostics struct should be opaque and extensible (accessor functions,
  or a size or version field), so details can grow without changing
  signatures. The alternative, an errno-style "last error" per thread or
  context, avoids the parameter but is fragile with async code and
  callbacks. More broadly, adding or changing a declared failure type on an
  exported function is a compatibility change in every backend where it's
  visible (a checked failure in Temper, a new exception type to catch, a
  new error code); the RFC should say which failure changes are compatible.

### Connecting to existing host exception types

User-space connected types can't yet name an existing backend type, only
define new ones. Three levels are possible:

1. **Identity:** the Temper type is the host's `ValueError` or
   `IllegalArgumentException`. Constructors, fields, and catching would
   have to map onto each host class's own API, and host exceptions would
   become visible to Temper code, against "only Temper-declared failures
   are visible". Hard, and not needed yet.
2. **Subclassing:** each generated failure class extends an idiomatic host
   base (`class MissingValue(ValueError)` in Python, `extends
   IllegalArgumentException` in Java, `: ArgumentException` in C#,
   `extends TypeError` in JavaScript). Temper's semantics don't change, and
   host code catches the failure as it would any invalid argument. Cheap
   and useful.
3. **None:** today, where generated classes extend only a Temper base.

For level 2, rather than naming host classes per backend in Temper source,
a few meaning categories (invalid argument, not found, I/O failure,
unsupported, invalid state) could decorate a declared failure type, with
each backend mapping a category to its idiomatic base and ignoring ones it
has no good base for. Library source stays backend-neutral, and each
backend owns its mapping.

### Panics, as Tom currently sees it

Panics may differ by backend, as long as each is that backend's idiomatic
panic (process exit in some, an uncatchable-by-convention error in others).
Temper libraries get no guarantee that a panic is recoverable, so library
code must not rely on catching one. What the RFC can still pin down: a
panic is never caught by `orelse` (today it is on JavaScript and Lua), and
test runners report a panicking test as a failure with its message rather
than losing the run's results.

### Current bugs

The bugs in the findings are best fixed as part of the RFC's work, since
most touch what `orelse` catches or which builtins fail how, unless one
proves urgent.

## Failures as values: a fuller sketch

Written after Tom's note that he sometimes regrets mapping failures to
exceptions in exception-based backends, and wonders whether nullables plus
explicit error types would be simpler. Mike's original aim was failure
handling that's idiomatic and fast inside Temper, not only for rare errors.

### What exists today

- **Propagating null takes a statement:** `let h = half(n) ?? return null;`
  doesn't parse in either compiler (`return` isn't an expression, and the
  same goes for `orelse return null`). Narrowing does work, identically on
  all eight backends:

  ```temper
  let h = half(n);
  if (h == null) { return null }
  half(h) // h is Int here
  ```

- **A result type can already be written in user code** as a sealed
  interface with two classes, and matched with `when`. What's missing is
  propagation sugar and backend-aware translation.

### The idea

Failure inside Temper is an ordinary value; each backend translates that
value into its own idiom at the edges, the same way Temper already turns
`Int`, `String`, and `List` into each language's own types.

1. **Absence:** `T?`, as today.
2. **Failure with a reason:** a small generic result type, `Ok<T>` or
   `Failed<E>` (names to be decided), with `E` any type, typically a
   library's sealed interface of variants with readable fields (Mike's
   sealed variants, Tom's declared kinds as sugar for them), plus Mike's
   optional message and cause if wanted.
3. **Bugs:** `panic`, idiomatic per backend, never caught by Temper code.
4. **One propagation operator** for both: if the value is null or failed,
   return it from the enclosing function, otherwise unwrap it. Something
   like a postfix `?` or `orelse return`, compiling to a plain branch.
   `??` stays the way to supply a default.
5. **`throws Bubble` becomes a special case:** a function that "bubbles"
   returns a failure with no details. `f() orelse x` reads like `f() ?? x`.
   That makes migration mechanical, and makes the two concepts one.

The appeal: no control flow besides `return`, so the cost, `await`,
generators, what `orelse` catches, and stack-trace questions mostly go
away; C, Zig, Rust, and Go get their own idioms naturally (status codes,
error unions, `Result`, `(value, err)`); and libraries' existing hand-made
error values become the normal style rather than a workaround.

### Core or std

**Core,** if the propagation operator and backend translation know about
the result type, as Swift's compiler knows `Optional` and Rust's `?` knows
`Result`. Std works only if the type stays an ordinary library type with no
sugar or special translation, and then most of the benefit is lost. A
minimal core type, with conveniences (mapping, combining, collecting many
failures) in std.

### Exported functions and Temper callers

Exported functions are called both by host code and by other Temper
libraries, so the boundary has to tell them apart:

- **Temper callers always use the value form,** across libraries too: the
  compiler generates the call, so library B calls library A's
  value-returning function directly, with no exception anywhere.
- **Host callers in exception-based languages can also get an idiomatic
  throwing form,** generated alongside the value form when a library asks
  for it (by decoration or configuration), raising an exception named
  after the failure type with its message (and, per the earlier
  categories, subclassing an idiomatic host base). Which form gets the
  plain name in each language is API and needs a rule: for example C#'s
  `Parse` and `TryParse`, or Java's `parse` and `parseOrNull`. Whichever
  rule, it belongs in `temper.keep`'s compatibility tracking.
- **Host code calling into Temper callbacks** (host implementations of
  Temper interfaces) that fail would return failure values too; a host
  exception thrown there is a panic from Temper's point of view.

The cost of exceptions is then paid only when a failure crosses into host
code, which the measurements found to be the cheap case.

### Is there a unifying principle?

Possibly this: **failure is data inside Temper, and an idiom outside it.**
Inside, everything is a value checked by the type system, cheap, and the
same on every backend, which is Mike's goal. At the edge each backend
presents that value the way its language expects, which is Tom's goal.
Absence (`T?`), failure with a reason (the result type), and failure
without one (today's Bubble) are the same idea at three levels of detail,
handled by the same two operators (default and propagate). Panics are the
one thing outside the model, deliberately.

### Risks and open points

- **Allocation:** a result value may allocate (and later be collected)
  where a nullable doesn't, but a thrown exception allocates too, usually
  more, with its stack trace. The difference is the success path: a
  wrapped success (`Ok(value)`) can allocate on every call, where an
  exception costs nothing until something fails. Ways to keep success
  free: no wrapper at all for failures without details (nullables);
  structs or value types where the backend has them (Rust's `Result`, C#
  structs, C++'s `std::expected`, Zig's error unions); in dynamic
  languages, returning the plain value on success and a failure object
  only on failure; and on the JVM and in V8, short-lived wrappers are often
  removed by escape analysis. Measure against today's bubbling and against
  nullables before deciding.
- **Nullable primitives on the JVM:** `Int?` is a boxed `Integer` in
  Java, which allocates for values outside the small cached range, while
  an `int` return with a rare exception allocates nothing on success. So
  for `Int?`, `Int64?`, and `Float64?` returns, nullables can cost more
  than exceptions on the JVM when failures are rare. Other backends don't
  have this problem (`int?` in C# and `std::optional<int>` in C++ are
  values; Rust's `Option<i32>` too; Python, JavaScript, and Lua box
  everything anyway). Possible mitigations in generated Java: escape
  analysis after inlining often removes the box; internal (non-exported)
  functions returning `Int32?` could return a `long` with an out-of-range
  value meaning null, with no allocation; and exported functions keep
  `Integer` (or `OptionalInt`) as their API. Worth including in the
  measurements.
- **Absent and failed together:** `Result<T?, E>` covers a successful null,
  but nested optionals need care in backends without them (Java, C#).
- **Ergonomics** depend on the propagation operator; without it, deep call
  chains get noisy.
- **Precedence:** today `orelse` binds looser than `==`, so
  `assert(x orelse 0i64 == y)` parses as `x orelse (0i64 == y)`, and the
  type mismatch that follows isn't caught by the type checker, only by a
  backend. Whatever operators the RFC settles on, the default operator
  should bind tighter than comparisons, as Kotlin's `?:` does (C#'s and
  JavaScript's `??` bind looser than `==`, the same trap), and a postfix
  propagation operator should bind like a method call, so `a.f()?.g()` and
  `x ?? 0 == y` read the way they look. Mixing `??` with `&&` and `||`
  without parentheses could be an error, as JavaScript makes it.
- **Migration** of `throws Bubble` code and of builtins, and which builtins
  return nullable, a result, or panic.
- **Host idiom without wrappers:** if a library doesn't ask for throwing
  forms, Python, Java, and C# users get `None`, `null`, or a result
  object. Acceptable for many APIs, unusual for some.

Explorations of real library code under these designs are in
[claude-explore/](claude-explore/).

### Value and exception forms at exported functions

If a failure-carrying result translates to an exception for host callers,
does each exported function need both forms generated? Mostly yes, but
cheaply, and not always both as public API:

- **The value form must exist in generated code,** because other Temper
  libraries call it: a call from library B to library A compiles to a call
  of A's generated package in the same host language. It can be public but
  marked as not for host callers where the language allows (a `_temper`
  submodule in Python, an `internal` package in Java,
  `[EditorBrowsable(Never)]` in C#, `#[doc(hidden)]` in Rust).
- **The exception form is a thin wrapper:** call the value form; on
  failure, raise the failure's exception type with its message. The logic
  isn't duplicated, only a few lines per exported function.
- **Absence and failure differ here:** a function returning `T?` means
  absence, which stays `null`/`None` in every host (as `Map.get` does), so
  it gets no exception form. Only functions returning the result type get
  one. The author's choice between `T?` and a result is the signal.
- **Per-backend policy, following each language's idiom:**
  - C#: both public, as .NET's `Parse` and `TryParse`;
  - Java, Python, JavaScript: the throwing form as the API, the value form
    hidden;
  - Rust: `Result` only; Zig: an error union; C: a status code; Go:
    `(value, err)`;
  - Lua: `nil, message`, its own multiple-return idiom, with no wrapper.
- **Names and policy are API,** so they belong in `temper.keep`, and a
  library may want to override the default per function (by decoration),
  for example to keep a hot exported function exception-free.
