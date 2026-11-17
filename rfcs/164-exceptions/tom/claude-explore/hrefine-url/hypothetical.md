# Hrefine URL checks: hypothetical versions

**None of the code on this page compiles today.** It shows how
[current](current/current.temper.md) and [values](values/values.temper.md)
would read under each design, with syntax invented for the comparison.
Only `parseRecord`'s failure paths and the entry points change, so
only those are shown.

## A with a propagation operator (hypothetical)

Postfix `?` returns a `Failed` from the enclosing function (converting
`Failed<Int, E>` to `Failed<Authority, E>`, since only `E` matters),
and otherwise unwraps the value. `Failed(e)` with no type arguments
assumes the compiler infers them from the return type.

```temper
// HYPOTHETICAL: postfix `?`, inferred type arguments.
let parseRecord(input: String, log: ErrorLog?): Result<Authority, ValidationError> {
  ...
  if (!isHostCode(c)) { return Failed(fatal(log, "host-invalid-code-point", at)); }
  ...
  let port = if (i < end) { parsePort(input, input.next(i), end, at + 1, log)? } else { -1 };
  Ok(new Authority(host.toString(), port))
}

public static parse(input: String): Authority? { parseRecord(input, null).valueOrNull }
```

The five-line `when` in today's runnable version becomes one
expression, and `var port` goes back to `let`.

## B: one declared failure type per function (hypothetical)

`ValidationError` becomes the thrown type. It's already a single class
with a name and position, so it needs no sealed variants; the names
are an open set taken from the URL Standard (`host-invalid-code-point`,
`port-out-of-range`, ...), which is how Hrefine keeps up with the
standard.

```temper
// HYPOTHETICAL: `throwable`, `throws E`, `throw`, `catch`.
export throwable class ValidationError(public name: String, public position: Int) { ... }

let parseRecord(input: String, log: ErrorLog?): Authority throws ValidationError {
  ...
  if (!isHostCode(c)) { throw fatal(log, "host-invalid-code-point", at); }
  ...
  let port = if (i < end) { parsePort(input, input.next(i), end, at + 1, log)! } else { -1 };
  new Authority(host.toString(), port)
}

export let parseAuthority(input: String): Authority throws ValidationError { parseRecord(input, null)! }
public static parse(input: String): Authority? { parseRecord(input, null) catch { null } }
export let checkAuthority(input: String): AuthorityCheck {
  let log = new ErrorLog();
  let found = parseRecord(input, log) catch { null };
  new AuthorityCheck(found, log.errors.toList())
}
```

Reads like today's code with `bubble()` replaced by `throw`. The
accumulated `errors` list stays a value under B too: those errors sit
next to a usable result and can't be thrown.

## C: declared error kinds, no details (hypothetical)

Kinds carry no fields, so the position is lost, and the open set of
names would have to become a closed list of kinds, one per name the
parser can stop on:

```temper
// HYPOTHETICAL: `error case`, `throws X, Y`, `try`, `catch`.
error case HostInvalidCodePoint;
error case HostMissing;
error case PortInvalid;
error case PortOutOfRange;

let parsePort(...): Int throws PortInvalid, PortOutOfRange { ... throw PortInvalid; ... }

let parseRecord(input: String, log: ErrorLog?): Authority
    throws HostInvalidCodePoint, HostMissing, PortInvalid, PortOutOfRange {
  ...
  if (!isHostCode(c)) { note(log, "host-invalid-code-point", at); throw HostInvalidCodePoint; }
  ...
  let port = if (i < end) { try parsePort(input, input.next(i), end, at + 1, log) } else { -1 };
  ...
}
```

Hrefine's parser has about 40 `bubble()` sites (12 in the URL parser,
22 in hosts, the rest in IDNA and Punycode) and notes 29 distinct
validation error names in the URL and host parsers. Each name a
function can stop on would be a kind in every `throws` list on the way
up, or the kinds would be coarser than the names. Positions still need the log,
so `checkAuthority` stays as it is.

## What host code would see

From `parseAuthority("example.com:8a")`, or `parseUrl` in Hrefine:

| Design | Python | Java | Rust |
|---|---|---|---|
| Today | `RuntimeError()`, no message; `except RuntimeError` also catches unrelated errors | `RuntimeException` with a null message | `Err(temper_core::Error(None))`, displayed as "bubble" |
| A, as runnable today | returns a `Failed` object whose `error` is `ValidationError('port-invalid', 13)`; nothing raised | returns `Result<Authority, ValidationError>`; caller uses `instanceof Failed` | returns a generated `Result_<Authority, ValidationError>` (an `Arc<dyn …>` with downcasts), not Rust's `Result` |
| A, with backend-aware translation (hypothetical) | raises `ValidationError` from a generated throwing form, or returns it from the value form | the same, `parseAuthority` and `parseAuthorityOrNull` say | `Result<Authority, ValidationError>` |
| B | raises the generated `ValidationError` (a subclass of `ValueError` if categories exist), with a message such as "port-invalid at 13" | throws `ValidationError extends RuntimeException` (or `IllegalArgumentException`) | `Result<Authority, ValidationError>` |
| C | raises a generated `PortInvalid` (or one class with a kind tag), no position | throws `PortInvalid` | `Err(Kind::PortInvalid)` |
