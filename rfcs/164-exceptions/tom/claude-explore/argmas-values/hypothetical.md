# Argmas values: hypothetical versions

**None of the code on this page compiles today.** It shows how the
runnable code in [current](current/current.temper.md) and
[values](values/values.temper.md) would read under each design, with
syntax invented for the comparison. Only the parts that change are
shown.

## A with a propagation operator (hypothetical)

Postfix `?` here means: if the value is null (or a `Failed`), return it
from the enclosing function; otherwise unwrap it. Builtins that parse
return null instead of bubbling (`toInt32` here).

```temper
// HYPOTHETICAL: postfix `?` and a nullable toInt32.
public parse(text: String): Int? {
  integerText(text, "2147483647", "2147483648")?.toInt32()
}
```

Saves three lines in `IntType.parse` (`let`, `if (… == null) { return
null; }`, `orelse null`). Elsewhere in this case, nothing propagates
through more than one call, so the operator matters little here.

Note the spelling: `?.` is already Temper's null-safe call, so
`integerText(...)?.toInt32()` above is today's operator, which for a
nullable happens to mean the same as "propagate, then call". For a
`Result` it wouldn't: a postfix `?` followed by a method call would
lex as `?.`. See the precedence notes in the [overview](../README.md).

## B: one declared failure type per function (hypothetical)

Mike's shape: `throws E`, where `E` is one type, usually a sealed
interface; each failure type's constructor takes an optional message
and cause, which Temper code doesn't read back.

A value type fails with a reason the type itself chooses. Argmas would
still write the message from `expected`, so the reason adds little:

```temper
// HYPOTHETICAL: `throws E`, `throwable`, `throw`, `catch`.
export throwable class InvalidText(public text: String) {}

export interface ValueType<T> {
  public get expected(): String;
  public parse(text: String): T throws InvalidText;
}

class IntType extends ValueType<Int> {
  public parse(text: String): Int throws InvalidText {
    // `!` converts integerText's failure, and toInt32's, to InvalidText.
    integerText(text, "2147483647", "2147483648")!.toInt32()!
  }
}

class TypeChecker<T>(private type: ValueType<T>) extends Checker {
  public accepts(text: String): Boolean {
    do { type.parse(text); true } catch { false }
  }
}
```

The parser's result could split into a return value and a thrown
failure. `ParseResult` has three outcomes, two of them successes
(`Args`, and `Output` for help and version), so the return type stays
a sealed type:

```temper
// HYPOTHETICAL.
export sealed throwable interface ArgError {
  public get message(): String;
}
export class UnknownOption(public option: String, public suggestion: String?) extends ArgError { ... }
export class MissingValue(public option: String) extends ArgError { ... }
export class InvalidValue(public option: String, public text: String, public expected: String) extends ArgError { ... }

export sealed interface Parsed {}          // Args | Output
export let parseArgs(options: List<Opt>, argv: List<String>): Parsed throws ArgError { ... }

// A caller:
let parsed = parseArgs(options, argv) catch (e) {
  match (e) {
    is UnknownOption -> ...;
    is MissingValue -> ...;
    is InvalidValue -> ...;
  }
};
```

Closest runnable equivalent: [values](values/values.temper.md), where
`ArgError` is a value in the sealed `ParseResult`. Argmas reports only
the first mistake and keeps parsing to find help and version requests
(which win over errors), so the parser body would still record the
error in a field and throw at the end: the throw replaces only the
final `return`.

## C: declared error kinds, no details (hypothetical)

Tom's shape: `error case X;`, `throws X, Y`, explicit `try` or `!` to
propagate, and no details on the error.

```temper
// HYPOTHETICAL: `error case`, `throws X`, `try`, `catch`.
error case InvalidText;

export interface ValueType<T> {
  public get expected(): String;
  public parse(text: String): T throws InvalidText;
}

class IntType extends ValueType<Int> {
  public parse(text: String): Int throws InvalidText {
    let digits = try integerText(text, "2147483647", "2147483648");
    digits.toInt32() catch { throw InvalidText }   // toInt32's own kind isn't declared here
  }
}

class TypeChecker<T>(private type: ValueType<T>) extends Checker {
  public accepts(text: String): Boolean { (try type.parse(text) catch { null }) != null }
}
```

Argument errors need a message (and Argmas gives a suggestion such as
"did you mean --verbose?"), which kinds can't carry, so `ArgError`
stays a value as today; kinds could only mirror `ErrorKind`:

```temper
// HYPOTHETICAL.
error case UnknownOption;
error case MissingValue;
error case InvalidValue;
export let parseArgs(options: List<Opt>, argv: List<String>): Args
  throws UnknownOption, MissingValue, InvalidValue { ... }
// ...but then the message and the command for the usage line must go
// somewhere else, so ParseResult stays.
```

## What host code would see

| Design | Python | Java | Rust |
|---|---|---|---|
| Today | a host `ValueType` raises any `Exception` (`orelse` catches them all, bugs included); `ArgError` is a returned object | throws any `RuntimeException`; `ArgError` returned | returns `Err(temper_core::Error)`; `ArgError` returned |
| A | `parse` returns `int \| None`; `ArgError` returned | returns `@Nullable Integer`; `ArgError` returned | `Option<i32>`; `ArgError` returned |
| B | a host `ValueType` raises the generated `InvalidText`, and Argmas's `catch` sees only that; `parse_args` raises an `ArgError` subclass | throws `InvalidText`; catch `ArgError` or one variant | `Result<i32, InvalidText>`; `Result<Parsed, ArgError>` with an enum |
| C | raises a generated `InvalidText` class (or a tag on one shared class) | throws a generated class | `Result<i32, Kind>` where `Kind` is an enum of declared kinds |
