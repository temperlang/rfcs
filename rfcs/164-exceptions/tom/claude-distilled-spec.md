# Declared errors: distilled specification

By Claude Code (Claude Opus 5.5), 2026-11-27, for
[#164](https://github.com/temperlang/temper/issues/164). The rules the
`error-custom-kinds` branch implements, stated as they should have been
up front, with implementation details kept apart. Draft for Tom; names
("failure" vs "error") follow the planned rename to "error".

## Specification

### Errors

- **S1. Error types.** Each library's error types form a tree under its
  own sealed roots, which extend core's `Error`. Core's are under
  `CoreError`: `ParseError` (conversions), `MissingKey` (`Mapped.get`,
  `MapBuilder.remove`), `InvalidCodePoint`, `BrokenPromise` (`await`), and
  `BrokenGenerator` (a generator's `next()`).
- **S2. Every error has** `message: String` and `cause: Error?`.

### Throwing

- **S3. Declaring.** A function's result may say `throws E`, where `E`
  is an error type, a type parameter bound by `Error`, or `Never<…>`
  (can't fail). Only tests and std may write `throws Error` itself; an error nothing handles fails its test, with
  its message and causes.
- **S4. `throw e`** throws `e`, which must be an `Error`.
- **S5. What may fail:** `throw`, `await`, and calls of functions that
  throw. Each failing place's error type must be the function's declared
  one or a subtype; otherwise it's an error to handle or declare.
  Converting one error to another is only explicit, by `throw` in a
  handler.

### Handling

- **S6. `x orelse y`** handles any error `x` throws, giving `y`.
- **S7. `x catch (e) { … }`** binds the error, typed as the join of what
  `x` may throw, so a `when (e)` over a sealed root needs no `else`.
  There's no `catch` without a binding: `orelse` is that.
- **S8. Errors of several libraries** join to core's `Error`, which only
  a handler takes.

### Panics

- **S9. Bugs panic, data errors are declared.** A condition that
  depends on data is a declared error; a program bug that's cheap to
  check panics: integer division by zero, failing `as`, index out of
  bounds. `Float64` division follows IEEE 754.
- **S10. Panics pass every handler** and end the program, or fail the
  test.

### Generic code

- **S11. Error parameters.** A type parameter used after `throws` is an
  error parameter, bounded by `Error`. It's solved per call from the
  arguments: a callback that can't fail gives `Never<Error>`, and the
  call can't fail. Arguments that throw different types give their
  join (S8). Core's callback methods (`map`, `filter`, `sort`, …) and
  std's regex `replace` are generic this way.

### Async and generators

- **S12. `await`** throws `BrokenPromise` when its promise is broken.
- **S13. Generators.** A generator body that may throw makes a
  `Generator<Y>`; one that can't makes a `SafeGenerator<Y>`.
  `Generator.next()` throws `BrokenGenerator`, whose `cause` is the
  error the body threw, and the generator is done;
  `SafeGenerator.nextSafe()` can't fail. `BrokenGenerator` is core's,
  under `CoreError`, so a body passing on an inner generator's error
  declares it as any other.

## Implementation notes

- **Why S1's tree:** each root becomes a host exception class (or error
  type), so error types have single inheritance and no type parameters,
  as host exception classes must. Exports throw only exported types by
  the general rule for exports. The default message is the type's name
  in words plus its public fields; the default cause is the error being
  handled where this one was thrown.
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

## Alternatives

- **Keep `Bubble`, demoted** to an ordinary core error with no detail
  (`bubble()` throws one): existing `throws Bubble` code keeps working,
  and the special cases still go. Not proposed: it keeps a detail-free
  error anyone can throw, and the proposal is to remove it.

## Open

- `rethrows` as sugar for passing on a callback's error.
- `try` as a required propagation marker (today `try x` is `x`).
- `Promise<T, E>` and `Generator<Y, E>`, which need default type
  arguments, a language change of their own. Source compatible if the
  defaults are today's errors (`E = BrokenPromise`, `E = BrokenGenerator`)
  and `E` is never inferred where it isn't written: a generator literal
  whose body throws `MyError` stays a `Generator<Y>` (throwing
  `BrokenGenerator`) unless the type wanted names its `E`.
- Names: the "failure" to "error" rename.
- **Where `Error` itself reaches hosts** (cross-library joins, and
  `throws Error` if it's ever allowed more widely): hosts shouldn't see
  a Temper type for "any error", but each backend's common error type
  where it has one: `Exception` (Python, C#), `RuntimeException`
  (Java), `Error` (JS), `Box<dyn std::error::Error>` or similar (Rust),
  `std::exception` (C++), and error values (Lua).
