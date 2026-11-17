Survey: **how widely used languages define and handle error types**, for
the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)),
answering point 7 of [the 2026-11-17 meeting](claude-meeting-2026-11-17.md).
Drafted by Claude, 2026-11-17, from each language's official documentation
(named under [Sources](#sources)); nothing here was fetched or run, and
uncertain points say so.

## What an error is

| Language | What can be thrown or returned | Required base | Message | Cause | Stack trace |
|---|---|---|---|---|---|
| Java | `throw`: only `Throwable` subclasses | the class `Throwable`; a `catch` type must be a class, so interfaces can't be caught, and a generic class can't extend `Throwable` (JLS §8.1.2) | `getMessage()`, may be null | `getCause()` | captured at construction; the protected 4-argument constructor (Java 7) can turn it off |
| Kotlin | `throw`: only `Throwable` subclasses | `Throwable` (the JVM's); generic subclasses rejected, as in Java | `message`, nullable | `cause` | as Java |
| C# | `throw`: only `System.Exception` and subclasses (error CS0155; `catch` the same) | the class `Exception` | `Message`; a default text if none is given | `InnerException` | filled in as the exception is thrown and unwinds, not at construction |
| Python | `raise`: only `BaseException` instances or subclasses | `BaseException`; the docs say user exceptions should derive from `Exception` | `str(e)`, from `args` | `__cause__` (`raise … from …`); `__context__` set implicitly | `__traceback__`, attached when raised |
| JavaScript, TypeScript | `throw`: any value | none; `Error` by convention | `message` on `Error` | `cause` option (ES2022) | `stack`, not in the standard but in every engine; V8 captures it at construction |
| C++ | `throw`: any complete, copyable or movable, non-abstract object type, `int` included | none; `std::exception` by convention, and C++ Core Guidelines E.14 asks for purpose-built types | `virtual what() const noexcept` | `std::nested_exception`, `std::throw_with_nested` (C++11) | none attached; C++23's `std::stacktrace` is separate |
| Rust | returned: `Result<T, E>`, `E` any type | none for `Result`; `std::error::Error` for interoperable errors (`Box<dyn Error>`, `?` conversion) | `Error` requires `Display` and `Debug` | `source()`, default `None` | none in the trait; `std::backtrace::Backtrace` is captured explicitly |
| Go | returned: by convention a last result of type `error` | the interface `error` | `Error() string`, its only method | `Unwrap() error` or `Unwrap() []error`; `fmt.Errorf("%w")` | none |
| Swift | `throw`: any type conforming to `Error` | the protocol `Error`, which has no requirements | none required; `localizedDescription` through Foundation | none standard (Foundation's `NSError` has an underlying-error key) | none; the Swift book says a `throw` performs about like a `return` |
| Lua | `error(v)`: any value | none | strings by convention (with a position prefix); a table may define `__tostring` | none | `debug.traceback`, from an `xpcall` handler |
| Zig | returned: error unions `E!T`, where `E` is an error set | error sets only: named codes with no payload, by design | `@errorName(e)` gives the code's name | none | error return traces in Debug and ReleaseSafe builds |
| C | returned status codes, or `errno` (thread-local since C11) | none | `strerror(errno)` | none | none |

## How callers handle errors

| Language | Checked by the compiler | Selective handling | Panic-like |
|---|---|---|---|
| Java | `Exception` subclasses outside `RuntimeException` must be caught or declared (JLS §11.1.1); `RuntimeException` and `Error` are unchecked | `catch` by class, multi-catch `A \| B` | `Error` subclasses (`AssertionError`, `OutOfMemoryError`), unchecked and not caught by convention |
| Kotlin | no checked exceptions; `@Throws` declares them for Java callers | `catch` by class; `runCatching` gives a `Result<T>` holding a `Throwable` | `error()`, `check()`, `require()` throw ordinary exceptions; no separate panic |
| C# | no | `catch` by class, with filters `when (…)` (C# 6) | `Environment.FailFast`; a stack overflow ends the process |
| Python | no | `except` by class or tuple; `except*` for exception groups (3.11) | `SystemExit` and `KeyboardInterrupt` derive from `BaseException` directly, so `except Exception` lets them pass |
| JS, TS | no; TypeScript has no throws clause and types a caught value as `unknown` under `strict` (4.4) | one `catch`, then `instanceof`, `name`, or Node's `code` strings | none in the language |
| C++ | no; `noexcept`, whose violation calls `std::terminate` | `catch` by type, derived to base; `catch (...)` | `std::terminate`, `std::abort`, `assert`; many codebases turn exceptions off (the Google C++ Style Guide forbids them) |
| Rust | `Result` is `#[must_use]`; `?` converts with `From` | `match` on enum variants; `downcast_ref` on `dyn Error` | `panic!`, `unwrap`, `expect`; `catch_unwind` exists, documented as not for general try/catch |
| Go | no; linters flag ignored errors | `errors.Is` (equality with a sentinel, or an `Is` method) and `errors.As` (a type, including an interface) | `panic` and `recover`; `Must…` functions (`regexp.MustCompile`) panic |
| Swift | `throws` and `try` are required; untyped by default, typed `throws(E)` since Swift 6 (SE-0413) | `catch` with patterns (`catch let e as ParseError`) | `fatalError`, `precondition`, `try!`; not catchable |
| Lua | no | `pcall` or `xpcall`, then inspect the value | none separate |
| Zig | yes: an error union must be handled (`try`, `catch`), and `switch` over an error set is exhaustive | `catch \|e\| switch (e)` | `@panic`, `unreachable` (checked in safe modes) |
| C | no | compare codes | `abort`, `assert` |

Hierarchies: Java, Kotlin, C#, Python, JavaScript, and C++ catch by class,
so a library base class (`requests.RequestException`, Jackson's
`JacksonException`, `System.Text.Json.JsonException`) catches everything
a library throws. Python can add a standard category by multiple
inheritance (requests' `InvalidURL` extends both `RequestException` and
`ValueError`); Java, C#, and JavaScript have single inheritance and can't
catch interfaces, and in C++ two `std::exception` bases make
`catch (std::exception const&)` ambiguous, so it doesn't match. Go gets
both through `errors.As` with an interface and an `Is` method matching
several targets. The JDK itself chose a library base over a category:
`java.time.DateTimeException` extends `RuntimeException`, not
`IllegalArgumentException`, and `JsonException` in .NET extends
`Exception`, not `FormatException`.

Names: Java and C# exception classes end in `Exception` (C#'s analyzer
rule CA1710 enforces it); Python's PEP 8 and tutorial use `Error`, as do
JavaScript's built-ins; Rust and Go name a package's error type `Error`
(`std::io::Error`, `serde_json::Error`) and Go names sentinels `Err…`
(`io.EOF` aside), since the package qualifies the name.

## Mike's question

*Do widely used languages that use `throw` constrain equality and
stringification for throwable types?*

**Equality: no.** None of Java, Kotlin, C#, Python, JavaScript, C++, or
Swift requires a thrown type to define equality or hashing, and none uses
it to choose a handler: handlers match by type, or by a filter the caller
writes. Equality defaults to identity (`Throwable`, `Exception`, and
`BaseException` don't override it; two `ValueError("x")` aren't equal),
and Swift's `Error` doesn't refine `Equatable`. Rust doesn't require
`PartialEq` for `std::error::Error`, and `std::io::Error` doesn't
implement it. Equality shows up only for **error codes**: Go's sentinels
(`err == io.EOF`, or `errors.Is`), C++'s `std::error_code`, Zig's error
sets, and C's status codes. Each compares a kind, never a payload.

**Stringification: provided, rarely required.** In Java, Kotlin, C#, and
Python the required base class always has a message slot, which may be
empty or null; nothing forces a useful one. JavaScript and C++ can throw
anything, so nothing is required, though `Error.message` and `what()` are
universal by convention. Swift requires nothing. The two languages that
*do* require it don't use `throw`: Go's `error` is only `Error() string`,
and Rust's `std::error::Error` requires `Display` (plus `Debug`).

Hashing is required nowhere. Serialization is incidental: every Java
`Throwable` is `Serializable`; .NET's legacy exception serialization
constructors were made obsolete in .NET 8 (SYSLIB0051, as far as I
recall); a Python exception pickles from its `args`, so a subclass whose
`__init__` takes other arguments needs `__reduce__`; JavaScript's
`structuredClone` copies `Error` objects.

## Implications for Temper

- **Always give hosts a message.** Every target has a slot for one, and
  Go and Rust require it. Generate it from the failure's fields when the
  author gives none (`expected a table at word 4`), following Rust's
  convention of short lowercase text without trailing punctuation, which
  reads well in every host.
- **Don't require equality or hashing** of failure types. No host needs
  them; matching is by type or variant, which sealed failure types give
  directly. A failure that also wants value equality can declare it as any
  class does.
- **Map causes to each host's slot** (`getCause`, `InnerException`,
  `__cause__`, `cause`, `source()`, `Unwrap()`, nested exceptions in C++).
- **Library base types work everywhere,** but as a class in Java and C#
  (interfaces can't be caught), and alone in Java, C#, JavaScript, and C++
  (one superclass chain). Only Python and Go can also carry a standard
  category.
- **Failure types should be non-generic** where they become JVM exceptions;
  Java and Kotlin forbid generic `Throwable` subclasses.
- **Stack traces cost differently:** the JVM and V8 capture one when an
  exception object is constructed, .NET and Python when it is thrown.
  Creating exception objects as values inside Temper is cheap on .NET and
  Python but not, by default, on Java and JavaScript.
- **Follow host naming** for generated types: `…Exception` in Java and
  C#, `…Error` in Python and JavaScript, `Error` inside a Rust or Go
  package.

## Sources

Java: *The Java Language Specification* (§8.1.2, §11.1.1, §14.20) and the
`java.lang.Throwable` API docs. Kotlin: Kotlin docs, "Exceptions". C#:
Microsoft Learn, "Best practices for exceptions", the Framework Design
Guidelines ("Exceptions", including the Try-Parse pattern), and code
analysis rules CA1710 and CA1032. Python: *The Python Tutorial* §8 and
*The Python Standard Library*, "Built-in Exceptions"; PEP 8. JavaScript:
the ECMAScript specification (`Error`, `AggregateError`, `cause`), MDN,
and the TypeScript 4.4 release notes. C++: the C++ standard [except],
cppreference, the C++ Core Guidelines (E section), and the Google C++
Style Guide. Rust: *The Rust Programming Language* ch. 9, the
`std::error::Error` and `std::panic::catch_unwind` docs, and the Rust API
Guidelines (C-GOOD-ERR). Go: the language spec, the `errors` package
docs, and the Go blog's "Working with Errors in Go 1.13" and "Errors are
values". Swift: *The Swift Programming Language*, "Error Handling", and
SE-0413. Lua: *Lua 5.4 Reference Manual* §2.3 and §6.1. Zig: the Zig
language reference, "Errors". C: ISO C11 §7.5.
