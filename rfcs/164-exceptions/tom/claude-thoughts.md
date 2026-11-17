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
