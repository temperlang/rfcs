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
