# Connecting host types, and moving `Deque` and `DenseBitVector` to std

By Claude Code (Claude Opus 5.5), 2026-11-23, for
[#671](https://github.com/temperlang/temper/issues/671) and
[#30](https://github.com/temperlang/temper/issues/30), following Tom's
direction: types the host supplies should be marked `@connected`, and
`Deque` and `DenseBitVector` should move from core to std. Nothing here
is decided; syntax is hypothetical where marked.

## Summary

- Seven core types are host-supplied on some backend but not
  `@connected`: `Pair`, `Deque`, `DenseBitVector`, `Listed`, `Mapped`,
  `SafeGenerator`, and `Console`. Mark them all.
- Adopt Kotlin Temper's rule that `is` and `as` can't target a connected
  type unless it's `@mayDowncastTo(true)` or reached through sealed
  supertypes. Without the rule, marking types changes nothing.
- Move `Deque` and `DenseBitVector` to one std module,
  `std/collections`, connected there to the same host types as today.
- Keep `is DenseBitVector` and `is Pair` working with
  `@mayDowncastTo(true)`, after two small runtime fixes (C++ and Rust)
  so every backend can tell them apart. `Deque<T>` can't be targeted
  anyway, because of its type argument.
- Make it a clean break, with an error that names the import to add.

## Background: `@connected` and `is`

Kotlin Temper decides whether `x is T` and `x as T` are allowed in this
order:

1. `@mayDowncastTo(false)` on `T` refuses the check, and
   `@mayDowncastTo(true)` allows it.
2. Otherwise, if `T` is `@connected`, the check is refused unless a
   chain of sealed supertypes leads from the static type to `T`. Two
   Temper types may connect to the same host type, so the host can't
   always tell them apart.
3. Separately, a check that would introduce an invariant type argument
   is refused: `x is Deque<Int>` from `AnyValue` can't be checked at run
   time. Covariant (`@out`) arguments aren't checked, so
   `x is Pair<String, Int>` is allowed.

The new compiler has rules 1 and 3. A class-level `@connected` changes
neither typing nor output yet, so the "gap (connected)" rows in its
core capabilities table (`StringBuilder`, `Promise`, and others) allow
checks that Kotlin refuses.

## Host-supplied types that aren't connected

Each backend's type tables and runtimes were checked against every class
and interface core exports.

| Type | Host types | `is` today | Proposal |
| --- | --- | --- | --- |
| `Pair<K, V>` | Java `Map.Entry`, C# `KeyValuePair<K, V>`, Rust tuple `(K, V)`, runtime classes elsewhere | allowed | `@connected @mayDowncastTo(true)`, after the C++ and Rust fixes below |
| `Deque<T>` | Java `Deque`, C# `Queue<T>`, Python `collections.deque`, C++ `std::deque`, Rust `VecDeque` | refused (type argument) | `@connected`, in std |
| `DenseBitVector` | Java `BitSet`, C# `BitArray`, C++ `std::vector<bool>`, runtime classes elsewhere | allowed | `@connected @mayDowncastTo(true)`, in std, after the C++ and Rust fixes |
| `Listed<T>` | Java `List`, C# `IReadOnlyList`, Python `Sequence`, JS and Lua arrays | refused (type argument) | `@connected` |
| `Mapped<K, V>` | Java `Map`, C# `IReadOnlyDictionary`, Python `Mapping`, JS `Map`, Lua tables | refused (type argument) | `@connected` |
| `SafeGenerator<T>` | the same host type as `Generator` on C#, Java, JS, Lua, and Python | not translated yet | `@connected`; this correctly refuses `g is SafeGenerator<T>` from a `Generator<T>` |
| `Console` | Java and C++ runtime consoles, C# `ILoggingConsole`, Python `LoggingConsole` | can't be named yet | `@connected` |

`Pair`'s `key` and `value` are host accessors as well (Java `getKey()`,
C# `.Key`, Rust `.0`), but core declares them as plain fields that
backends special-case. Declaring them as `@connected` getters would
leave that knowledge in core's declarations, where the other connected
members already are.

These were left out:

- `MapKey` has no values of its own on any host. It only becomes a
  bound: `Eq + Hash` in Rust, and nothing elsewhere.
- `AnyValue`, `Null`, `Void`, `Bubble`, `Never`, `Function`,
  `GeneratorFn`, `Equatable`, `Invalid`, `Problem`, and `Type` are
  language types. Backends translate them structurally, not as library
  classes. `Null` already has `@mayDowncastTo(true)`.

Every other host-supplied type is already connected: `Boolean`, the
numbers, `String`, `StringBuilder`, the string indices, the lists and
maps, `Empty`, generators and their results, and promises.

For working code, marking `Listed`, `Mapped`, `SafeGenerator`, and
`Console` changes nothing. The checks are already refused, untranslated,
or impossible to write. Adopting the connected rule refuses only what
Kotlin Temper already refused.

## Moving `Deque` and `DenseBitVector` to std

### Where

Put both in one std module, `std/collections`:

```temper
// Hypothetical.
let { Deque, DenseBitVector } = import("std/collections");
```

One module fits where hosts keep these types: `java.util`, Python's
`collections`, Rust's `std::collections`, and .NET's
`System.Collections`. It needs only one import and leaves room for
later collections. Separate modules (`std/deque`, `std/bits`) would cost
more imports and add nothing at this size.

### Host types and `is`, by backend

`Deque`:

| Backend | Host type today | Recommended | Can the host type be tested? |
| --- | --- | --- | --- |
| C++ | `shared_ptr<std::deque<T>>` | keep | yes once it's an `AnyValue`, which it isn't today |
| C# | `Queue<T>` | keep while the API is first-in, first-out | yes, including `T` |
| Java | `java.util.Deque` (`ArrayDeque`, or `LinkedList` for nullable items) | keep | yes, with `T` erased; any host `LinkedList` also passes |
| JS | an array with a hidden counter | a runtime class | no: a `ListBuilder` is an array too |
| Lua | a runtime table tagged `Deque` | keep | yes |
| Python | `collections.deque` | keep | yes, with `T` erased |
| Rust | `Arc<RwLock<VecDeque<T>>>` | keep, plus an `AnyValue` implementation | yes once it's an `AnyValue`, including `T` |

`is Deque<T>` stays refused by the type-argument rule, before and after
the move. Recommended: `@connected` alone, with no `@mayDowncastTo`.
The JS and Rust gaps matter only if that rule is ever loosened.

`DenseBitVector`:

| Backend | Host type today | Recommended | Can the host type be tested? |
| --- | --- | --- | --- |
| C++ | `shared_ptr<std::vector<bool>>` | a runtime class of its own | no: `ListBuilder<Boolean>` has the same type |
| C# | `BitArray`, which runtime helpers grow | keep | yes |
| Java | `java.util.BitSet` | keep | yes |
| JS | the runtime class (`Uint8Array`) | keep | yes |
| Lua | a runtime table tagged `DenseBitVector` | keep | yes |
| Python | the runtime class (`bytearray`) | keep: an `int` is immutable, and a bare `bytearray` could clash with a future bytes type | yes |
| Rust | `temper_core::DenseBitVector` (`Vec<u32>` chunks) | keep, with no third-party crate | yes once it's an `AnyValue`, which it isn't today |

What happens with `is` today: the casts test for core's classes passes
on C#, Java, JS, Lua, and Python. C++ and Rust don't run it. On those
two backends, neither `Pair` nor the bit vector can become an
`AnyValue`, so the generated checks wouldn't compile there (by reading
the runtimes; not compiled).

Recommended: give `DenseBitVector` (and `Pair`)
`@mayDowncastTo(true)` together with the two runtime fixes. C++ needs
its own bit vector class that derives from its `AnyValue` base, and its
`Pair` needs to derive from that base too. Rust needs `AnyValue`
implementations for both. If the fixes slip, leave `@mayDowncastTo` out
for now. `is DenseBitVector` is then refused, which is a break from
Kotlin Temper, but no library surveyed uses it.

### What changes

- **Core** drops both classes and their docs. The compiler's list of
  builtin type names drops both names.
- **Std** gains `std/collections` with both classes and their docs. Each
  gets a pure Temper body, so `--no-connected` and the interpreter need
  no special cases. `DenseBitVector` has one already. `Deque` would use
  a `ListBuilder` and a head index that compacts as it goes.
- **Frontend:** the builtin name list, core member tables, the
  interpreter's built-in deque and bit vector values and their `is`
  cases, and the core capabilities test rows, which move to a std check.
- **Backends:** connection keys change from `core.type Deque…` to
  `std/collections.type Deque…` in every backend's tables, and so do
  each backend's type special cases. Runtime code can stay where it is:
  C++, JS, Lua, and Python already keep std support in their core
  runtimes, and Java needs none. C# and Rust can move their helpers to
  their std runtimes later, in a separate change.
- **Generated code** keeps the same host types, so host-facing APIs
  (a Java method taking a `java.util.Deque`, for example) don't change.
- **Docs:** the tutorial's builtin types page (which already says these
  types might move), the core capabilities notes, and the Kotlin
  differences.

### Migration and Kotlin compatibility

- **Source:** users add the import. An unresolved `Deque` or
  `DenseBitVector` gets a targeted error: "`Deque` is in std now; add
  `let { Deque } = import("std/collections");`". The error is keyed on
  the unresolved name, so nothing is reserved, and a user's own
  `class Deque` works, and now no longer shadows a builtin.
- **Kotlin-era code** used both types from core without an import, and
  Kotlin Temper has no `std/collections`, so one source file can't build
  unchanged under both compilers. Since Kotlin Temper is being replaced,
  libraries change once, at the switch. The alternatives aren't worth
  it:
  - Core can't keep deprecated exports, because std depends on core.
    That would take duplicate declarations or compiler aliasing.
  - Adding `std/collections` to Kotlin Temper would mean more work on a
    compiler being retired.
- **Host side:** no change (see above).

## Tests

- Funtests: the deque and dense bit vector cases import
  `std/collections`, and so does the Myers diff library, which uses both
  types.
- Split the casts test for core's classes. `Pair` stays. The bit vector
  checks move to a std case. C++ and Rust join once their runtimes can
  box these types.
- Frontend cases:
  - an unresolved `Deque` gives the hint
  - `x is Deque<Int>` from `AnyValue` is refused
  - with the connected rule, `x is StringBuilder` is refused and
    `r is DoneResult<T>` from a `GeneratorResult<T>` is allowed, as in
    Kotlin Temper
  - `g is SafeGenerator<T>` from a `Generator<T>` is refused
- Settle `DenseBitVector.set` with a negative index, which backends
  handle differently today, and test it on every backend. Recommended:
  `get` returns `false` and `set` panics. That matches core's Temper
  body and most hosts.

## Open questions

1. **The module's name:** `std/collections`, or one module per type.
   Recommended: `std/collections`.
2. **`Deque` is really a queue.** Its API is `add`, `isEmpty`, and
   `removeFirst`. It could grow `addFirst`, `removeLast`, `first`,
   `last`, and `length` before 1.0, but that would push C# from
   `Queue<T>` to `LinkedList<T>` or a runtime ring buffer. Recommended:
   keep the name and API, and add operations only when someone needs
   them.
3. **Erased `Pair` arguments.** On every backend but C#, a
   `Pair<Int, String>` passes `is Pair<String, Int>`, so the narrowed
   `key` has the wrong type. Options:
   - refuse explicit arguments in a check from `AnyValue`, unless they
     are the parameters' bounds
   - warn instead of refusing
   - accept the hole and document it, as Kotlin Temper did

   Recommended: refuse. The check on `Pair`'s type stays allowed.
4. **Renames while moving** (`BitSet`, `Queue`). Recommended: none.
   Renames cost every user, and the current names are clear enough.
5. **Where the runtime code lives** on C# and Rust (core or std
   runtime). Recommended: leave it in place in the move, and decide
   separately.
