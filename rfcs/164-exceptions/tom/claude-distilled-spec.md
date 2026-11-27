# Declared errors: distilled specification

By Claude Code (Claude Opus 5.5), 2026-11-27, for
[#164](https://github.com/temperlang/temper/issues/164). The rules the
`error-custom-kinds` branch implements, stated as they should have been
up front, with implementation details kept apart. Draft for Tom; names
("failure" vs "error") follow the planned rename to "error".

## Specification

### Errors

- **S1. Error types.** An error type is a class, or a sealed interface,
  under core's `Error`. Each library declares its own roots: sealed
  interfaces extending `Error` directly. Every other error type extends
  exactly one error type of its own library. Error types have no type
  parameters.
- **S2. Messages and causes.** Every error has `message: String` and
  `cause: Error?`. By default, the message is the type's name in words
  plus its public fields, and the cause is the error being handled where
  this one was thrown.
- **S3. Core's errors** are under core's root `CoreError`: `ParseError`
  (conversions), `MissingKey` (`Mapped.get`, `MapBuilder.remove`),
  `InvalidCodePoint`, and `BrokenPromise` (`await`).

### Throwing

- **S4. Declaring.** A function's result may say `throws E`, where `E`
  is an error type, a type parameter bound by `Error`, or `Never<…>`
  (can't fail). Only tests, std, and generator bodies may write
  `throws Error` itself.
- **S5. `throw e`** throws `e`, which must be an `Error`.
- **S6. What may fail:** `throw`, `await`, and calls of functions that
  throw. Each failing place's error type must be the function's declared
  one or a subtype; otherwise it's an error to handle or declare.
  Converting one error to another is only explicit, by `throw` in a
  handler.
- **S7. Exports** throw only exported error types.

### Handling

- **S8. `x orelse y`** handles any error `x` throws, giving `y`.
- **S9. `x catch (e) { … }`** binds the error, typed as the join of what
  `x` may throw, so a `when (e)` over a sealed root needs no `else`.
  `x catch { … }` is `orelse`.
- **S10. Errors of several libraries** join to core's `Error`, which only
  a handler takes.

### Panics

- **S11. Bugs panic, data errors are declared.** A condition that
  depends on data is a declared error; a program bug that's cheap to
  check panics: integer division by zero, failing `as`, index out of
  bounds. `Float64` division follows IEEE 754.
- **S12. Panics pass every handler** and end the program, or fail the
  test.

### Generic code

- **S13. Error parameters.** A type parameter used after `throws` is an
  error parameter, bounded by `Error`. It's solved per call from the
  arguments: a callback that can't fail gives `Never<Error>`, and the
  call can't fail. Arguments that throw different types give their
  join (S10). Core's callback methods (`map`, `filter`, `sort`, …) and
  std's regex `replace` are generic this way.

### Async and generators

- **S14. `await`** throws `BrokenPromise` when its promise is broken.
- **S15. Generators.** A generator body that may throw makes a
  `Generator<Y>`; one that can't makes a `SafeGenerator<Y>`.
  `Generator.next()` throws `Error`; `SafeGenerator.nextSafe()` can't
  fail. A generator body may declare `throws Error` to pass on an inner
  generator's error.

### Tests

- **S16.** A test may throw any error; an error nothing handles fails it,
  with its message and causes.

## Implementation notes

- **Representation:** errors are a result type in tmpl
  (`TypeData::Result`), kept after two checkpoints against a hidden
  `Result` class; Bubble's removal doesn't change that.
- **Backends:** exception hosts (Python, Java, JS, C#, Lua) throw host
  exceptions under each library root's host type, and erase error
  parameters from host signatures; Rust and C++ return
  `Result<T, E>`/`Expected<T, E>`, with an uninhabited type
  (`Infallible`, `core::Never`) for "can't fail" and "try" forms of
  core's callback methods.
- **Handlers:** a handler whose body can't run is dropped by a shared
  lowering; a function's result counts as a used value.
- **Promises:** `Promise<T, E>` was prototyped with core-only default
  type arguments and shelved: Temper has no default type arguments.

## Open

- `rethrows` as sugar for passing on a callback's error.
- `try` as a required propagation marker (today `try x` is `x`).
- `Promise<T, E>` and `Generator<Y, E>`, which need default type
  arguments, a language change of their own.
- Names: the "failure" to "error" rename.
