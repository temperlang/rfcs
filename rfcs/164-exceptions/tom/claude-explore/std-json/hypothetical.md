# std JSON: hypothetical versions

**None of the code on this page compiles today.** It shows how
[current](current/current.temper.md) and [values](values/values.temper.md)
would read under each design, with syntax invented for the comparison.

## A with a propagation operator (hypothetical)

Postfix `?` returns a `Failed` from the enclosing function and
otherwise unwraps; here it also widens the error type when the
function's own is a supertype (`JsonSyntaxError` to `JsonProblem`), as
Rust's `?` does with `From`. `mapError` is a hypothetical std helper.

```temper
// HYPOTHETICAL: postfix `?`, widening, inferred type arguments, mapError.
export let decodeJson<T>(text: String, adapter: JsonAdapter<T>): Result<T, JsonProblem> {
  Ok(adapter.decodeFromJson(parseJson(text)?)?)
}

public decodeFromJson(t: JsonSyntaxTree): Result<List<T>, JsonShapeError> {
  if (!(t is JsonArray)) { return Failed(new JsonShapeError("", "an array")); }
  let b = new ListBuilder<T>();
  for (var i = 0; i < t.elements.length; i += 1) {
    b.add(adapterForT.decodeFromJson(t.elements[i])
      .mapError { e => new JsonShapeError("[${i.toString()}]${e.path}", e.expected) }?);
  }
  Ok(b.toList())
}

// In the parser's array loop:
elements.add(value()?);
```

`decodeJson` goes from 15 lines to 3; the parser's loop body from 4
lines to 1.

## B: one declared failure type per function (hypothetical)

```temper
// HYPOTHETICAL: `throwable`, `throws E`, `throw`, `!`, `catch`/`match`.
export sealed throwable interface JsonProblem { public get message(): String; }
export class JsonSyntaxError(public reason: String, public offset: Int) extends JsonProblem { ... }
export class JsonShapeError(public path: String, public expected: String) extends JsonProblem { ... }

export let parseJson(sourceText: String): JsonSyntaxTree throws JsonSyntaxError { ... }

export interface JsonAdapter<T> {
  public decodeFromJson(t: JsonSyntaxTree): T throws JsonShapeError;
}

public decodeFromJson(t: JsonSyntaxTree): List<T> throws JsonShapeError {
  let elements = (t as JsonArray) catch { throw new JsonShapeError("", "an array") };
  let b = new ListBuilder<T>();
  for (var i = 0; i < elements.length; i += 1) {
    b.add(adapterForT.decodeFromJson(elements[i]) catch (e) {
      throw new JsonShapeError("[${i.toString()}]${e.path}", e.expected)
    });
  }
  b.toList()
}

export let decodeJson<T>(text: String, adapter: JsonAdapter<T>): T throws JsonProblem {
  adapter.decodeFromJson(parseJson(text)!)!   // each `!` widens to JsonProblem
}

// A caller:
let xs = decodeJson(text, ints) catch (e) {
  match (e) {
    is JsonSyntaxError -> ...;
    is JsonShapeError -> ...;
  }
};
```

This is Mike's case of two failure modes meeting in one function,
solved with a sealed interface over both. It needs the two error types
to be declared together (or a third type wrapping both, if they came
from different libraries).

The std adapter interface is also implemented by generated code (the
`@json` decorator) and by host code, so the declared type is part of
every adapter's signature, in every language.

## C: declared error kinds, no details (hypothetical)

```temper
// HYPOTHETICAL: `error case`, `throws X, Y`, `try`.
error case JsonSyntax;
error case JsonShape;

export let parseJson(sourceText: String): JsonSyntaxTree throws JsonSyntax { ... }

export interface JsonAdapter<T> {
  public decodeFromJson(t: JsonSyntaxTree): T throws JsonShape;
}

export let decodeJson<T>(text: String, adapter: JsonAdapter<T>): T throws JsonSyntax, JsonShape {
  adapter.decodeFromJson(try parseJson(text))   // `try` on the inner call; the outer one?
}
```

A caller can tell bad syntax from a wrong shape, but not where either
is: the offset and path have nowhere to go, and `jsonError` stays a
side channel on the producer as today.

## What host code would see

From `decodeJson("[[1, 2], [\"3\"]]", ints)`:

| Design | Python | Java | Rust |
|---|---|---|---|
| Today | `RuntimeError()` (from the failed `as`), or a `ValueError` where `toInt32` fails | `RuntimeException`, or `NumberFormatException` | `Err(Error(None))`, or `Err(Error(Some(ParseIntError)))` |
| A, as runnable today | returns `Failed` whose `error` is a `JsonShapeError(path='[1][0]', expected='an Int32')` | `Result<List<List<Integer>>, JsonProblem>`; `instanceof` | generated `Result_` with `Arc<dyn>` downcasts |
| A, with backend-aware translation (hypothetical) | a value form returning the problem, and a throwing form raising `JsonShapeError` with message "at [1][0]: expected an Int32" | `decodeJson` throws, `tryDecodeJson` returns | `Result<Vec<Vec<i32>>, JsonProblem>` |
| B | raises `JsonShapeError` (subclass of a generated `JsonProblem`), message "at [1][0]: expected an Int32" | throws `JsonShapeError extends JsonProblem` | `Result<_, JsonProblem>` (an enum) |
| C | raises `JsonShape`, no message | throws `JsonShape` | `Err(Kind::JsonShape)` |
