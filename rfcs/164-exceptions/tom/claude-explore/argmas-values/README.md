# Case: Argmas value types and argument errors

Argmas, a Temper library, parses command-line
arguments. Two of its failure paths:

- **Value types** (`ints`, `floats`, `choices([...])`, and any type a
  program writes, in Temper or in its host language) turn an argument's
  text into a value. `parse` bubbles when the text means no value. The
  parser asks "does it parse?" with `do { type.parse(text); true }
  orelse false` and later reads the value again with `orelse panic()`.
  Argmas writes the error message itself, from the type's `expected`
  ("expected an integer"), so it never needs a reason from `parse`.
- **Argument errors** are already values: `parse` returns a sealed
  `ParseResult` that is `Args`, `Output` (help, version), or
  `ArgError(kind, message)`. Argmas's docs: "Mistakes are values, not
  exceptions, with a suggestion when there's a near miss."

Files:

- [current/current.temper.md](current/current.temper.md): today's code,
  simplified (runnable, with tests).
- [values/values.temper.md](values/values.temper.md): design A
  (runnable, with tests).
- [hypothetical.md](hypothetical.md): design A with a propagation
  operator, design B, and design C. **Not runnable.**

## How each design reads

`IntType.parse`, the value-type conversion:

```temper
// Today (runnable)
public parse(text: String): Int throws Bubble {
  integerText(text, "2147483647", "2147483648").toInt32()
}

// A, runnable today
public parse(text: String): Int? {
  let digits = integerText(text, "2147483647", "2147483648");
  if (digits == null) { return null; }
  digits.toInt32() orelse null          // the builtin still bubbles today
}

// A with a propagation operator (HYPOTHETICAL)
public parse(text: String): Int? { integerText(text, "2147483647", "2147483648")?.toInt32() }

// B (HYPOTHETICAL): one declared failure type
public parse(text: String): Int throws InvalidText { integerText(...)!.toInt32()! }

// C (HYPOTHETICAL): declared kinds
public parse(text: String): Int throws InvalidText {
  let digits = try integerText(...);
  digits.toInt32() catch { throw InvalidText }
}
```

The checker, which asks whether text parses:

```temper
do { type.parse(text); true } orelse false     // Today
type.parse(text) != null                       // A
```

## What host code sees

Value types matter most here, because programs implement `ValueType`
in their own language. Today a Python implementation signals "no
value" by raising any `Exception` (and Argmas's `orelse` would also
turn a bug in it, such as a `KeyError`, into "invalid value"); Java,
any `RuntimeException`; Rust, an `Err(temper_core::Error)`. Under A it
returns `None`, `null`, or `None` (`Option`), which every language
reads the same way and which can't be confused with a bug. Under B and
C it raises or returns a generated failure type. The table in
[hypothetical.md](hypothetical.md#what-host-code-would-see) has the
details.

`ArgError` is returned in every design, since Argmas reports one
mistake together with the command's usage and keeps parsing to see if
help was asked for.

## Notes

- **Nullable is enough here.** Argmas never needs to know why a type
  rejected text, so design A's simplest tier (absence) fits, and it
  removes both the `do { ...; true } orelse false` idiom and the
  reliance on `orelse` catching whatever a host implementation throws.
  Line count is unchanged (125 code lines both ways).
- **Argmas's own result type already is design A's "failure with a
  reason":** a library-specific sealed type with three outcomes. A
  generic `Ok`/`Failed` wouldn't replace it; a standard result type
  would be for functions with one success and one failure.
- **B could make `ArgError` thrown** (a sealed type of variants with
  fields), but the parser would still record the first mistake in a
  field and throw at the end, so the change is only at the boundary.
  **C can't replace `ArgError`**: kinds carry no message or suggestion.
- **Generic `T?` works:** `parse(text): T?` in a generic interface is
  fine, though Temper's type parameters can't themselves be nullable
  (Argmas notes this for its handles), so a value type for an optional
  value isn't expressible either way.
- **C# can't compile it today:** with `parse(text): T?` in the generic
  interface, tempest's C# backend declares `Optional<T> Parse(string)`
  in `IValueType<T>` but `int? Parse(string)` in `IntType`, and C#
  rejects the implementation (CS0738). The `values` library passes on
  the other seven backends; `current` passes on all eight. A gap to fix
  before nullable returns in generic interfaces can be relied on.
- **Builtins:** `toInt32` bubbles, so even design A code needs
  `orelse null` until parse-like builtins return nullable.

## Precedence

- Today `do { type.parse(text); true } orelse false` is safe because
  of the braces. Written without them, `orelse` (precedence 4) is below
  `==` (12): `type.parse(text) orelse 0 == 1` means
  `type.parse(text) orelse (0 == 1)`, and tempest's type checker
  accepts it (see the [overview](../README.md#operator-precedence)).
- `??` has the same trap: `ints.parse(t) ?? 0 == 1` is
  `ints.parse(t) ?? (0 == 1)`. The tests here parenthesize:
  `(ints.parse("42") ?? -1) == 42`.
- `?.` already exists, so a postfix `?` for propagation followed by a
  call reads as a null-safe call; harmless for nullables, wrong for
  results.

Run: `temper test -w . -b interp -b py -b js` (or any other backends)
in a copy of this folder. `current` and `values` are separate libraries,
since the C++ backend puts all of a library's exports in one namespace
and both define the same names.
