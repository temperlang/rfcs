# Example translations

What host code would get from the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)),
for meeting point 2 of [2026-11-17](../claude-meeting-2026-11-17.md): the
shared worked example written out as each backend might generate it,
under [declared failures](../claude-proposal-declared.md),
[failures as values](../claude-proposal-values.md), and the
[recommendation](../claude-recommendation.md)'s combined form. Drafted by
Claude, 2026-11-17.

**All code here is hand-written illustration**, not generated, compiled,
or run. It aims to be plausible and idiomatic, follows today's generated
naming where there is one, and notes alternatives where a choice is open.
Background on each language's error types:
[claude-error-types-survey.md](../claude-error-types-survey.md).

## The example

Wherewith's `select` rule, from
[claude-explore/wherewith-problems](../claude-explore/wherewith-problems/README.md),
as each proposal's worked example writes it: a recursive-descent parser
for `SELECT a, b FROM t` that fails with
`SqlProblem(text: String, word: Int)`. Host code calls
`parseSelect("SELECT a FROM")`, which fails with text "expected a table"
at word 4, and host message `expected a table at word 4`. The failure's
category is "invalid argument".

Three forms:

- **Declared failures:** `SqlProblem` is a declared failure type, raised
  with `throw` and propagated by marker; exception languages throw it all
  the way through.
- **Failures as values:** `select` returns a result; a result may carry
  any type, so `SqlProblem` is an ordinary class (its `toString()` gives
  the message). Exception languages get a generated throwing form at the
  exported function, which needs an exception type to throw: here a
  generated wrapper, `SqlProblemException` or `SqlProblemError`, holding
  the `SqlProblem`.
- **Combined (the recommendation):** values inside Temper, but the
  failure carried is a declared failure type, generated as the host's
  exception class. Host code sees what declared failures give it, plus a
  value form where the language has an idiom for one.

## Files

| File | Covers |
|---|---|
| [cpp.md](cpp.md) | C++: exceptions, or `std::expected` |
| [csharp.md](csharp.md) | C#: exceptions, and the Try-Parse pattern |
| [java.md](java.md) | Java: exceptions, checked and unchecked |
| [js.md](js.md) | JavaScript, with TypeScript callers |
| [lua.md](lua.md) | Lua: `error` and `pcall`, or `nil, failure` |
| [python.md](python.md) | Python: exceptions with a category by multiple inheritance |
| [rust.md](rust.md) | Rust: `Result`, the same under both |
| [go.md](go.md) | Go, as if it were a backend: `(value, error)`, the same under both |
| [c-and-zig.md](c-and-zig.md) | C and Zig, future backends, briefly |

## What users see

The call, and what host code checks for, from `parseSelect("SELECT a FROM")`:

| Language | Declared failures | Failures as values (any type) | Combined |
|---|---|---|---|
| C++ | `parseSelect` throws `SqlProblem : WherewithError : std::runtime_error` | `parseSelect` returns `std::expected<…, SqlProblem>`; throwing form by configuration | as values, with `SqlProblem` the exception class |
| C# | `ParseSelect` throws `SqlProblem : WherewithException` | `TryParseSelect(text, out select, out problem)` and `ParseSelect`, which throws `SqlProblemException` | both, with one type: `SqlProblem` from `TryParseSelect`, thrown by `ParseSelect` |
| Java | `parseSelect` throws `SqlProblem extends WherewithException` (unchecked, or checked by a library setting) | `parseSelect` throws `SqlProblemException`; value form in `wherewith.internal` | as declared |
| JS | `parseSelect` throws `SqlProblem extends WherewithError` | `parseSelect` throws `SqlProblemError`; value form in the internal module | as declared |
| Lua | `parseSelect` raises a `SqlProblem` table; `pcall` and check | `parseSelect` returns `nil, problem`; `assert(…)` raises | as values |
| Python | `parse_select` raises `SqlProblem(WherewithError, ValueError)` | `parse_select` raises `SqlProblemError`; value form in `_temper` | as declared |
| Rust | `Result<Select, SqlProblem>`, `SqlProblem: Error`, plus a crate `wherewith::Error` enum | the same | the same |
| Go | `(*Select, error)`; `errors.As` to `*SqlProblem` or `wherewith.Error` | the same | the same |
| C, Zig | status code or error set, with details out | the same | the same |

## What the translations show

1. **The proposals differ only where hosts use exceptions.** In Rust,
   Go, C, and Zig both generate the same API, since each language's idiom
   is already a failure value; declared failures are implemented there as
   values. Lua differs only in whether `parseSelect` raises or returns
   `nil, problem`. The real comparison is C++, C#, Java, JavaScript, and
   Python.
2. **Allowing any type as a failure costs host code a second name**
   (meeting point 6). Under values with any type, exception languages
   throw a wrapper (`SqlProblemException` holding a `SqlProblem`), Rust
   can't implement `std::error::Error` for a foreign type like `String`
   (the orphan rule), and Go needs a type with `Error()`. Declared failure
   types, in the declared proposal or the combined form, map one to one.
3. **A library base works in every language,** in its own form: a class
   (C++, C#, Java, JS, Python), an interface matched by `errors.As` (Go),
   a crate-level enum (Rust), a metatable (Lua), an enum prefix (C), an
   error set (Zig).
4. **A category alongside it works only in Python and Go** (multiple
   inheritance; `Is` methods). In C#, Java, JavaScript, and C++ the
   translations let the library base win, with the category as the
   base's own superclass when a library's failures all share one.
5. **Java's checked choice changes one line** of generated code (the
   base's superclass) and a lot of host code; unchecked is shown as the
   default, with a library-wide setting for checked.
6. **No Temper names in what users catch:** every failure type here is
   the library's. Temper still shows elsewhere: `temper::core::Str` in
   C++ signatures, `Arc<String>` and `ToArcString` in Rust, and the
   runtime's result type inside hidden value forms.
7. **Stack traces decide the combined form's cost** on Java and
   JavaScript, which capture one when an exception is constructed; .NET
   and Python capture it when thrown, so an unthrown exception object is
   just an allocation there.
8. **Names follow each host:** the generated base is `WherewithException`
   in C# and Java, `WherewithError` in C++, JavaScript, and Python,
   `Error` in Rust and Go packages; the author's `SqlProblem` keeps its
   name everywhere (C#'s CA1710 would prefer `SqlProblemException`; open).
