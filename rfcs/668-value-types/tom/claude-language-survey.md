# Language survey: hosting Temper value types (#668)

Date: 2026-11-18. Prepared with Claude Code (Claude Opus 5.5) for the "Efficient value types" RFC.

## Method

The idea being checked: a Temper value type is immutable, final, has no identity, gets generated structural `==` and hashing, and is not directly recursive. Each backend picks either a by-value struct or an ordinary immutable object. Plain-data value types (only fixed-size scalar fields) could also go in dense containers.

**Ranking:** the language list follows the TIOBE Index top 50 in late-2026 form. We could not fetch the November 2026 index from the sandbox, so the order comes from recent TIOBE lists, with stable entries filled in from IEEE Spectrum and RedMonk. The exact order doesn't change any verdict. **Skipped** as not general-purpose: SQL, PL/SQL, T-SQL, Scratch, assembly, LabVIEW, Ladder Logic, SAS, and VHDL/Verilog. Language-feature claims come from official docs as of late 2026. Version-status claims for Java Valhalla, JS Composites, OxCaml, and Mojo were checked against current sources on 2026-11-18 (linked in the table); other claims are from documentation as known, not re-fetched.

Verdicts: **by value** = real gain available; **object** = immutable object, no gain and no cost; **awkward** = the restrictions or the equality rules map poorly.

## Table

| # | Language | By-value types | Immutability | Identity / default `==` | Generated eq/hash | Dense storage | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | Python | No | Shallow: `@dataclass(frozen=True)`, `NamedTuple` | `is` exists; `==` default is identity | `dataclass(eq, frozen)` gives eq+hash | `array`, `struct`, `memoryview` (no numpy in std) | object |
| 2 | C++ | Yes: `struct`/class by value | `const` members (these block assignment); usually private + const accessors | `&a==&b` only by address; `==` must be written or `= default` (C++20) | `operator== = default`; hash hand-written | `std::vector<T>` contiguous | by value |
| 3 | C | Yes: `struct` | `const` fields (awkward); by convention | No objects; struct `==` not allowed | None; generate functions | Arrays of structs | by value |
| 4 | Java | Partial: Valhalla value classes ([JEP 401](https://openjdk.org/projects/valhalla/)) integrated as a preview for JDK 28 (Aug 2026; GA expected Mar 2027); not final in a GA JDK | `final` fields; `record` | `==` is reference (on records too) | `record` gives equals/hashCode | Primitive arrays; `ByteBuffer`; flattened arrays only with Valhalla | object (by value later) |
| 5 | C# | Yes: `struct` | `readonly struct`, `init` | `ReferenceEquals` for classes; structs have no identity | `record struct` / `readonly record struct` | `T[]`, `Span<T>` contiguous | by value |
| 6 | JavaScript | No: Records and Tuples withdrawn (2025); [Composites](https://github.com/tc39/proposal-composites) reached Stage 2 (Sept 2026): ordinary objects compared by `Composite.equal`, usable as Map/Set keys; not shipped | Shallow `Object.freeze` | `===` is identity | None | TypedArrays/`DataView` | object (dense via typed arrays) |
| 7 | Go | Yes: `struct` | None at the language level; unexported fields + methods | Structs have no identity; `==` is structural for comparable structs | `==` built in; maps key on comparable structs | `[]T` contiguous | by value |
| 8 | Visual Basic (.NET) | Yes: `Structure` | `ReadOnly` | `Is` for classes | No record syntax; generate | Arrays of structures | by value |
| 9 | Delphi/Object Pascal | Yes: `record` | No `readonly` fields; private + properties | Records have no identity; `=` needs an operator overload | Manual (`class operator Equal`) | Arrays of records | by value |
| 10 | Fortran | Yes: derived types | `intent(in)`, `parameter`; weak | No identity for values | Manual | Arrays of derived types | by value (little Temper interest) |
| 11 | Perl | No | `Readonly`/`constant`; weak | `==` compares numbers or refs | None (Moo/Moose help) | `pack` strings | object |
| 12 | R | No (S4/R5 objects; vectors) | Copy-on-modify value semantics | No user identity for lists; `identical()` | `identical()` deep | Atomic vectors (struct-of-arrays) | object |
| 13 | PHP | No | `readonly` props (8.1), `readonly class` (8.2) | `===` is identity, `==` field-wise | None (hash: no user hashing in arrays) | `pack`, SplFixedArray | awkward (no user hash keys) |
| 14 | Rust | Yes: `struct` | Immutable by default | No identity (only `ptr::eq`) | `#[derive(PartialEq, Eq, Hash, Clone, Copy)]` | `Vec<T>` contiguous | by value |
| 15 | MATLAB | Partial: `struct` arrays, value classes | Value classes copy; `SetAccess=immutable` | Value classes have no identity | `isequal` structural | Numeric arrays | object |
| 16 | Ada | Yes: `record` | `constant`, limited private types | No identity; `=` predefined, structural | `=` predefined; hash manual | Arrays of records | by value |
| 17 | Kotlin | Partial: `@JvmInline value class` takes one field only; multi-field waits on Valhalla (JDK 28 preview) | `val` | `===` exists; `==` calls equals | `data class` | Primitive arrays | object |
| 18 | Swift | Yes: `struct` | `let` properties | Structs have no identity (`===` only for classes) | Synthesized `Equatable`/`Hashable` | `Array<T>`, `ContiguousArray` | by value |
| 19 | Ruby | No | `Data.define` (3.2) is frozen, shallow | `equal?` identity; `Data` `==` structural | `Data`/`Struct` | `pack` strings | object |
| 20 | COBOL | Yes: group items | Weak | No objects (outside OO COBOL) | None | Tables (OCCURS) | awkward (no realistic backend) |
| 21 | Dart | No (extension types wrap one value, zero cost) | `final` fields, `const` constructors | `identical()` exists; `==` default identity | Records (positional/named) structural; classes manual | `typed_data` lists | object |
| 22 | Common Lisp | Partial: `defstruct` (implementation may inline) | `:read-only` slots | `eq` identity; `equalp` structural | `equalp`/`sxhash` for structs | Specialized arrays | object |
| 23 | Prolog | Terms are values | Immutable terms | No identity | Unification and `==` structural | None | object |
| 24 | Scala | Partial: `AnyVal` with one field; JVM limits | `val`, `case class` | `eq` identity; `==` calls equals | `case class` | Primitive arrays | object |
| 25 | Lua | No | None (metatable tricks) | Tables are identity; `__eq` metamethod | None; `__eq` ok, but tables as keys use identity | Strings/`string.pack`; LuaJIT FFI structs | awkward (map keys) |
| 26 | Julia | Yes: immutable `struct` held inline when isbits | `struct` is immutable by default | `===` on immutables is structural (egal) | `==` falls back to `===`; hash via egal | `Vector{T}` inline for isbits | by value |
| 27 | Haskell | Unboxed only with pragmas/`UNPACK` | Immutable throughout | No identity | `deriving (Eq, Ord)`; hashable via generics | `Data.Vector.Unboxed`/`Storable` | object (natural fit) |
| 28 | TypeScript | As JS | `readonly` (compile-time only) | As JS | None | As JS | object |
| 29 | Objective-C | Yes: C `struct` (no ARC object fields) | Immutable classes by convention | `==` is pointer; `isEqual:` | Manual `isEqual:`/`hash` | C arrays | object |
| 30 | Zig | Yes: `struct` (`extern`/`packed`) | `const` bindings; no per-field const | No identity; `std.meta.eql` | `std.meta.eql`, `std.hash.autoHash` | Slices, `MultiArrayList` | by value |
| 31 | Elixir | No (BEAM terms) | Immutable throughout | No identity | `==` structural on structs and maps; map keys structural | Binaries | object (natural fit) |
| 32 | Erlang | No (records are tuples) | Immutable throughout | No identity | Structural on terms | Binaries | object (natural fit) |
| 33 | F# | Yes: `[<Struct>]` records/unions | Immutable by default | Records structural; `obj.ReferenceEquals` | Records give structural eq+hash | .NET arrays of structs | by value |
| 34 | Clojure | No | Persistent data | `identical?`; `=` structural | `defrecord` | Primitive arrays | object |
| 35 | OCaml | Partial: unboxed float records/arrays; [OxCaml](https://oxcaml.org/documentation/unboxed-types/intro/) unboxed types in active development, not in mainline OCaml | Immutable fields by default | `==` physical, `=` structural | Polymorphic `=`/`Hashtbl.hash`; ppx_deriving | Float arrays, Bigarray | object |
| 36 | Groovy | No (JVM) | `@Immutable` | `is()` identity; `==` calls equals | `@EqualsAndHashCode`, records | JVM arrays | object |
| 37 | PowerShell | Via .NET structs only | Weak | .NET rules | None | .NET arrays | awkward (little Temper interest) |
| 38 | Bash/shell | No | No | No | No | No | awkward (not a target) |
| 39 | Nim | Yes: `object` (value) vs `ref object` | `let`; no per-field const | No identity for objects; `==` auto for objects | `==` generated; `hash` via `hashes` | `seq[T]` contiguous | by value |
| 40 | Crystal | Yes: `struct` | `getter`-only; `record` macro | Structs have no identity; `record` `==` structural | `record` macro / `def_equals_and_hash` | `Array(T)` / `Slice` | by value |
| 41 | D | Yes: `struct` | `immutable`/`const` (deep, transitive) | `is` for classes; struct `==` field-wise | `==` and `toHash` generated for structs | Arrays of structs | by value |
| 42 | Racket/Scheme | No | Immutable structs (Racket default) | `eq?` identity; `equal?` structural (`#:transparent`) | `equal?`/`equal-hash-code` | `bytes`, flvectors | object |
| 43 | Smalltalk (Pharo) | No | Immutability flag (`beReadOnlyObject`) | `==` identity; `=` user-defined | Manual | ByteArray etc. | object |
| 44 | Apex | No | `final` | `===` identity; `==` uses equals | Manual | No | object (little interest) |
| 45 | ABAP | Yes: structures | `READ-ONLY` attributes | Structures compare by value | Structure `=` built in | Internal tables | awkward (platform-bound) |
| 46 | Gleam | No (BEAM/JS) | Immutable | No identity on BEAM; structural `==` on both targets | Built in | BitArray | object (natural fit) |
| 47 | V | Yes: `struct` | Immutable by default (`mut` opt-in) | Structural `==` | `==` auto | Arrays of structs | by value |
| 48 | Mojo | Yes: `struct` (value semantics) | `@value` replaced by `@fieldwise_init` plus explicit `Copyable`/`Movable` traits (Mojo 25.4); syntax still evolving | No identity for structs | Traits; partial derivation | `List[T]` contiguous | by value |
| 49 | Solidity | Yes: `struct` (memory copies) | `immutable`/`constant` only for state vars | No objects | `keccak256(abi.encode(..))` by hand | Arrays of structs | awkward (gas costs, domain) |
| 50 | Hack | No (PHP-like) | `readonly` | Same as PHP | `shape`s structural | `vec` | object |

## Summary

**Counts:** by value 18 (C++, C, C#, Go, VB.NET, Delphi, Fortran, Rust, Ada, Swift, Julia, Zig, F#, Nim, Crystal, D, V, Mojo; plus Java and Kotlin once Valhalla ships, which the table counts as "object" for now). Immutable object 25 (including Java and Kotlin for now). Awkward 7 (PHP, COBOL, Lua, PowerShell, Bash, ABAP, Solidity).

**Biggest gains** among current and considered Temper backends: **C#** (`readonly record struct` gives every property in one line), **Rust** (`#[derive(Clone, Copy, PartialEq, Eq, Hash)]`), **Swift** (synthesized `Hashable`), **Go** (built-in structural `==`, structs as map keys), **C++/C/Zig** (contiguous `std::vector`/arrays), and later **Java/Kotlin** once Valhalla `value class` reaches a GA JDK. Until then Java gets records only, and `==` on records is still a reference comparison, so generated code must always call `equals`. Plain-data types in **JavaScript/TypeScript, Python, Lua, and Dart** gain only through typed-array or byte-buffer fallbacks, which are worth offering only for opt-in dense containers.

**Where the restrictions cause trouble:**
- **Lua:** `__eq` works, but table keys use identity. Value types as map keys need a generated key (interning or a string/tuple key) in the runtime. **PHP** is similar: array keys must be int or string, so maps keyed by value types need a hash-keyed wrapper. This matters only if value types may be map keys: Temper's `MapKey` is closed today (strings and numbers), so it's an opt-in extension the RFC can defer; if allowed, the runtime must supply hashing rather than rely on the host. Immutability itself is no problem in either language: Temper enforces it at compile time, and the host only stores fields (PHP even has `readonly` classes).
- **JS/Python/Ruby/Dart:** identity is always observable through the host (`===`, `is`). This is harmless if Temper simply never emits it, but interop code can still see it. The RFC should state that identity is unspecified across the boundary.
- **Default values and zeroing:** C#, Go, Zig, C, and Valhalla (null-restricted types) all produce zero-initialized structs (`default(T)`, zero values, `new T[n]`). Temper must either keep such defaults unreachable (no uninitialized arrays) or make an all-zero value valid for each type. Swift and Rust don't have this problem.
- **Big structs:** by-value copying cost grows with size, and C# and Swift guidance warns about large structs (roughly over 16 to 64 bytes). Let backends fall back to objects (or `in`/borrowed parameters) past a size threshold. The "copying and sharing are indistinguishable" rule already allows this.
- **Recursion ban:** this is needed by C, C++, C#, Go, Rust, Swift, Zig, and similar languages, where a by-value type can't contain itself. Indirect recursion through lists or maps is fine.

**Implications for the RFC:**
1. **Shallow (`@imu`-style) immutability is enough:** every by-value host gets deep value semantics from copying, and object hosts need only no-mutation-through-the-type. Fields that hold mutable objects would break structural hashing, so require field types to be value types, immutable built-ins, or explicitly accepted with identity-based equality on that field.
2. **Structural equality is universal enough:** every serious target either generates it (record/data class/derive/dataclass/synthesized) or can have it generated by Temper. Temper should always generate it itself and not depend on host defaults (Go's `==` panics on non-comparable fields; Java's `==` is a reference comparison).
3. **Float fields:** `==` on NaN or -0.0 differs across hosts (Go, Julia `===`, Rust `PartialEq` vs `Eq`). Pick one rule (likely bitwise or total order for hashing) and generate it.
4. **Dense containers** are a separate, opt-in feature. They are real wins where structs exist; elsewhere they need struct-of-arrays or typed arrays and should not block the core proposal.

**Key sources:** [C# record structs](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/record), [JEP 401: Value Classes and Objects](https://openjdk.org/jeps/401), [Swift Equatable/Hashable synthesis (SE-0185)](https://github.com/apple/swift-evolution/blob/main/proposals/0185-synthesize-equatable-hashable.md), [Rust derive](https://doc.rust-lang.org/reference/attributes/derive.html), [Go spec: comparison operators](https://go.dev/ref/spec#Comparison_operators), [Python dataclasses](https://docs.python.org/3/library/dataclasses.html), [Kotlin inline value classes](https://kotlinlang.org/docs/inline-classes.html), [Julia types (immutable composite types)](https://docs.julialang.org/en/v1/manual/types/), [TC39 Records & Tuples (withdrawn)](https://github.com/tc39/proposal-record-tuple), [PHP readonly classes](https://www.php.net/manual/en/language.oop5.properties.php#language.oop5.properties.readonly-properties).

\* Version status to re-check before the RFC is final: Valhalla JEP 401's preview status in JDK 26/27, the stage of the JS Composites proposal, OxCaml unboxed types, and Mojo syntax.
