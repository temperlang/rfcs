# Case: Hrefine URL parsing and validation errors

Hrefine, a Temper library, implements the WHATWG URL Standard. The
standard's parser either returns a URL or "failure", and along the way
notes *validation errors*, most of which don't stop parsing (browsers
accept the URL) but say what was off. Hrefine has three entry points:

- `parseUrl` bubbles where the standard says failure, as JavaScript's
  `new URL()` throws;
- `Url.parse` gives null instead;
- `checkUrl` gives a `UrlCheck`: the URL or null, and every validation
  error (name and position) in order. The parser notes them in an
  `ErrorLog` only when `checkUrl` passes one, so `parseUrl` stays fast.

Hrefine's docs give the reason for `checkUrl`: "Failures say nothing,
in every language: a bare `RuntimeError` (Python), `Error` (JS),
`RuntimeException` (Java), ... Catching them catches unrelated errors
too."

The excerpt here parses just an authority (`host:port`), which keeps
the same shapes: a non-fatal error (spaces at the ends), fatal errors
in the host and the port, a helper (`parsePort`) whose failure passes
up, and the three entry points.

Files:

- [current/current.temper.md](current/current.temper.md): today's code,
  simplified (runnable, with tests).
- [values/values.temper.md](values/values.temper.md) and
  [values/result.temper.md](values/result.temper.md): design A
  (runnable, with tests).
- [hypothetical.md](hypothetical.md): A with a propagation operator,
  B, and C. **Not runnable.**

## How each design reads

A fatal error in the port, and passing it up:

```temper
// Today (runnable)
note(log, "port-invalid", at + digits);
bubble();
...
let port = if (i < end) { parsePort(input, input.next(i), end, at + 1, log) } else { -1 };

// A, runnable today
return new Failed<Int, ValidationError>(fatal(log, "port-invalid", at + digits));
...
var port = -1;
if (i < end) {
  let parsed = parsePort(input, input.next(i), end, at + 1, log);
  when (parsed) {
    is Ok<Int, ValidationError> -> port = parsed.value;
    is Failed<Int, ValidationError> -> return new Failed<Authority, ValidationError>(parsed.error);
    else -> panic();
  }
}

// A with a propagation operator (HYPOTHETICAL)
return Failed(fatal(log, "port-invalid", at + digits));
...
let port = if (i < end) { parsePort(input, input.next(i), end, at + 1, log)? } else { -1 };

// B (HYPOTHETICAL)
throw fatal(log, "port-invalid", at + digits);
...
let port = if (i < end) { parsePort(...)! } else { -1 };

// C (HYPOTHETICAL)
note(log, "port-invalid", at + digits);
throw PortInvalid;
...
let port = if (i < end) { try parsePort(...) } else { -1 };
```

## What host code sees

From a failed parse (`"example.com:8a"`):

| | Python | Java | Rust |
|---|---|---|---|
| Today | `RuntimeError()`, no message | `RuntimeException`, null message | `Err(Error(None))` |
| A, runnable | a `Failed` whose `error` is `ValidationError("port-invalid", 13)` | `Result<Authority, ValidationError>` | a generated `Result_` type (`Arc<dyn …>` with downcasts), not Rust's `Result` |
| B | a generated `ValidationError` exception with a message | the same, as a `RuntimeException` subclass | `Result<Authority, ValidationError>` |
| C | a generated `PortInvalid`, no position | the same | `Err(Kind::PortInvalid)` |

More in [hypothetical.md](hypothetical.md#what-host-code-would-see).

## Notes

- **Every design keeps `checkUrl`'s list.** Non-fatal validation errors
  sit next to a usable URL, so they can't be the failure; a list (or a
  log) is needed under A, B, and C alike.
- **A and B give `parseUrl` its reason for free.** The parser already
  knows the error's name and position where it bubbles; under A it
  returns it, under B throws it. Today only a caller who asks for the
  whole log learns why. Under A the cost on success is nothing extra
  (the failure object is made only when failing).
- **C fits less well here:** the names form an open set from the
  standard (29 distinct ones in the URL and host parsers), not a few
  kinds, and kinds can't carry the position.
- **Without a propagation operator, A is longer:** 101 code lines
  against 86 (plus the 3-line result type), mostly the `when` blocks
  and explicit type arguments. Passing a failure up from a function
  with a different value type (`Result<Int, …>` to
  `Result<Authority, …>`) needs a new `Failed`, since a user-defined
  type can't express "a failure of any `T`".
- **Today's tempest quirks met on the way** (tested on tempest only):
  a `when` over a generic sealed interface's classes isn't seen as
  exhaustive, so each needs `else -> panic()`; and after
  `if (r is Failed<…>) { return r; }`, the frontend accepts `r.value`
  but backends then fail with "an expression of unknown type", so the
  runnable code uses `when` instead.
- **Positions:** `fatal` notes the error in the log and returns it, so
  `checkAuthority`'s list and the returned failure agree.

## Precedence

- `Authority.parse(" example.com ")?.host == "example.com"` is fine
  (`?.` binds tightest), but `Authority.parse(s)?.port ?? -1 == 80`
  would mean `… ?? (-1 == 80)`: `??` (precedence 9) is below `==` (12),
  and tempest accepts the mismatched types (see the
  [overview](../README.md#operator-precedence)).
- With a postfix propagation operator, `parsePort(...)?` must bind
  tighter than any binary operator, so `parsePort(...)? + 1` adds to the
  port, not to the result; `?` at today's postfix precedence (23, just
  below `.` and calls) does that.

Run: `temper test -w . -b interp -b py -b js` (or any other backends)
in a copy of this folder. `current` and `values` are separate libraries,
since the C++ backend puts all of a library's exports in one namespace
and both define the same names.
