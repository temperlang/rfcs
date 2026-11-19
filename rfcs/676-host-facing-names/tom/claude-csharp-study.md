# Temper libraries from a .NET user's point of view

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

## The question

Does a Temper library look and behave like a .NET library to someone
who writes C#, and what would make it more so?

**Short answer:** the surface is close to idiomatic, and the behavior
underneath has the most surprises of the managed backends. Generated
code compiles cleanly with nullable reference types on, and the
annotations are good: a user program that misuses a nullable result
gets the compiler warning it should. Names are PascalCase, interfaces
have the `I` prefix, getters are properties, optional parameters are
C# optional parameters, callbacks are `Func` and `Action` that take
lambdas, lists are `IReadOnlyList<T>` (covariant, so a `List<Square>`
passes where `IReadOnlyList<IShape>` is wanted), promises are
`Task<T>` that `await` just works on, generators are `IEnumerable<T>`
that LINQ reads, and every exported static is read-only. All six tours
print their expected output. What a .NET user trips on: no class
overrides `Equals` or `GetHashCode` (15 have an `Eq` method instead),
and none is `sealed`; lists passed in are kept by reference; the lists
Temper returns are `ImmutableList<T>`s, AVL trees, so passing one back
into a Temper loop costs 13 times what a `List<T>` costs; every failure
is an `Exception of type 'TemperLang.Core.Bubble' was thrown` with no
message, and a failing call costs about 10 µs because .NET exceptions
are slow (Hrefine's `Url.Parse` returns `null` for bad input at that
price, 750 times `Uri.TryCreate`'s); doc comments are dropped (1,684
CS1591 warnings across the six libraries); the packages say
`Package Description`; and `TemperLang.Std` drags MSTest and the test
platform, 4.6 MB with `testhost.dll`, into every program that uses it.
Five compiler and runtime bugs stand out: a class named
`<Lib>Global` or `Logging` silently replaces generated code, a
Temper `private constructor` is public in C#, generators can be
enumerated only once, a member named `getHashCode` hides
`object.GetHashCode` instead of overriding it, and `sort` silently drops
what its comparison added. Most fixes are additive; equality, error
types, and the module class name are design questions for this RFC and
[#164](../../164-exceptions/README.md).

## How this was studied

- Built the six showcase libraries (Argmas, Chromarite, Hrefine,
  Kelpto, Ordable, and Wherewith) with Temper's compiler (`temper build
  -b csharp`; `temper 0.7.0-alpha.0.267` at `13dc5669`, a release build
  whose working tree had uncommitted changes outside the C# backend),
  and ran each library's C# tour against the output, as the tours'
  `.csproj` files do: Chromarite's, Hrefine's, Kelpto's, Ordable's, and
  Wherewith's match their `expected.txt`, Wherewith's example matches
  its own, and Argmas's examples program matches `examples.txt`.
- Wrote a probe library (the [Java study](claude-java-study.md)'s,
  about 260 lines with async, generators, and pairs and maps in added),
  a names probe (classes named `<Lib>Global`, `Logging`, `Task`, and
  like their namespace; members named for `object`'s), and C# programs
  using them and the libraries as a .NET user would. Every snippet below
  was run; output is quoted as printed.
- Toolchain: the .NET 6.0.402 SDK and 6.0.10 runtime, the only ones
  installed, on Linux in a container. User projects set
  `<Nullable>enable</Nullable>`, and where noted
  `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`. Analyzer counts
  are the SDK's own Roslyn analyzers with `AnalysisMode` set to
  `AllEnabledByDefault` and `AnalysisLevel` 6.0. No NuGet package was
  added beyond the local cache.
- Read the C# backend (`crates/temper-be-csharp`, especially `lib.rs`,
  `names.rs`, and `translate.rs`), its runtime (`TemperLang.Core` under
  `runtime/temper-core`), `docs/backends/README.md`,
  `notes/api-compat.md` (its C# section and proposals 7 and 10),
  [#164's C# translation](../../164-exceptions/tom/claude-translations/csharp.md),
  [the initial thoughts](claude-initial-thoughts.md), and the sibling
  studies for [Lua](claude-lua-study.md), [Rust](claude-rust-study.md),
  [C++](claude-cpp-study.md), [Python](claude-python-study.md),
  [JS](claude-js-study.md), and [Java](claude-java-study.md).
- learn.microsoft.com wasn't reachable from here (connection refused).
  The Framework Design Guidelines ("FDG" below, the book and its
  learn.microsoft.com pages), analyzer rule texts beyond what the
  compiler printed, and .NET support dates are from memory, marked as
  such.
- Timings are from a shared, noisy machine: ranges are the fastest and
  slowest of 5 timed runs after a second of warm-up, over two
  processes.

## 1. Nullable reference types

### Today

Every library project sets `<Nullable>enable</Nullable>`, and the
generated code builds with no nullable warnings. Annotations follow
Temper's types exactly:

```csharp
public static string? Maybe(bool b)
public static int? MaybeInt(bool b)
public static int IncOr(int? n)
public static IReadOnlyList<string?> Nullables()
public static string Greet(string name, string? greeting = null)      // optional
public static string DefaultNum(int? n = null, string? s = null)       // n defaults to 5
public static Url? Parse(string input, string? baseUrl = null)          // Hrefine
```

A user program built with warnings as errors gets exactly the
diagnostics a .NET user expects:

```text
Program.cs(6,12): error CS8600: Converting null literal or possible null value to non-nullable type.   string s = Maybe(false);
Program.cs(7,9): error CS8602: Dereference of a possibly null reference.                            Maybe(true).Length
Program.cs(8,25): error CS8625: Cannot convert null literal to non-nullable reference type.           Greet(null)
Program.cs(9,9): error CS8600: Converting null literal or possible null value to non-nullable type.    Url u = Url.Parse("x");
Program.cs(11,19): error CS8602: Dereference of a possibly null reference.                           new Labeled("a").Note.Length
Program.cs(12,9): error CS0266: Cannot implicitly convert type 'int?' to 'int'.                      int i = MaybeInt(true);
```

Three gaps:

- **Nothing is checked at run time.** Nullable annotations are
  advice; a caller with nullable warnings off, or one using `!`, gets
  whatever follows: `Greet(null!)` returns `Hello, ` (string
  concatenation treats `null` as empty) and `ListLength(null!)` throws
  `NullReferenceException` from inside the library.
- **The runtime is nullable-oblivious.** `TemperLang.Core` doesn't
  enable the context (its `.csproj` has `<Nullable>` commented out with
  a TODO), so its public types say nothing: `new
  TemperLang.Core.Bubble(null)` compiles without a warning, and every
  build prints five `CS8632`, `CS8600`, and `CS8602` warnings from
  `Core.cs` and `Async.cs`.
- **`Optional<T>` for generic nullables.** C# can't write "nullable
  `T`" for an unconstrained `T` that means `int?` for value types, so
  the backend uses the runtime's own `TemperLang.Core.Optional<T>`
  struct. Argmas's `Args.GetMaybe<T>` returns one, and its tour must
  `using TemperLang.Core;` to call `.OrNull()`, the only tour of the six
  that names the runtime.

### What .NET users expect

From memory: the FDG and the nullable-reference-types docs expect
annotated public APIs (the BCL is fully annotated since .NET 5) and
`ArgumentNullException` for a `null` argument where `null` isn't
allowed, thrown at the call with the parameter's name
(`ArgumentNullException.ThrowIfNull(x)` since .NET 6). Analyzer CA1062
asks for exactly that, and fires 147 times across the six libraries.
For generic "maybe" results, .NET APIs use the `Try` pattern (`bool
TryGetValue(TKey key, [MaybeNullWhen(false)] out TValue value)`) or
constrain `T` (`where T : class` or `struct`), not an option type.

### Options

| Option | Gains | Costs |
|---|---|---|
| A. `ArgumentNullException.ThrowIfNull` on non-null reference parameters of public members | Failures name the argument, at the call; CA1062 clean | A check per argument (negligible) |
| B. Enable nullable in `TemperLang.Core` | Runtime types annotated; build warnings gone | Fix five warnings, annotate a small API |
| C. `bool TryGetMaybe<T>(IMaybeArg<T> arg, [MaybeNullWhen(false)] out T value)` beside `Optional<T>` results | The runtime leaves user code; idiomatic | Two members per generic nullable result |

All three are additive. Recommended: A, B, and C, keeping `Optional<T>`
results for a release.

## 2. Values

### `Equals`, `GetHashCode`, and `ToString`

**Today.** Across the six libraries' 180 public types (136 classes,
26 interfaces, and 18 static classes):

| Member | Classes defining it |
|---|---|
| `override string ToString()` (from Temper's `toString`) | 35 |
| `bool Eq(Other)` (from `@auto("==")` or an `eq` method) | 15 |
| `override bool Equals(object?)` | 0 |
| `override int GetHashCode()` | 0 |
| `IEquatable<T>`, `IComparable<T>` | 0 |

So equality is identity everywhere .NET looks:

```text
new Point(3, 4)                              => (3.0, 4.0)          (has ToString)
p.Equals(new Point(3, 4))                    => False
new Money(100, "EUR")                        => Csprobe.Money       (@auto("=="), no ToString)
m1.Eq(m2)                                    => True
m1.Equals(m2), m1 == m2                      => False, False
new HashSet<Money> { m1, m2 }.Count          => 2
Check(2)                                     => Csprobe.Ok
Boxed("s")                                   => Csprobe.Box`1[System.String]
ParseUrl("https://e.com/").Equals(ParseUrl("https://e.com/"))   => False
```

Test assertions (`Assert.AreEqual`, xUnit's `Assert.Equal`),
`Contains`, `Distinct()`, and dictionary keys all use `Equals` and
`GetHashCode`, so none sees `Eq`.

**What .NET users expect.** From memory, the FDG's equality guidance:
override `Equals` and `GetHashCode` together, implement `IEquatable<T>`
when overriding `Equals`, and override `ToString` with something
useful for debugging. CA1067 ("override `Equals` when implementing
`IEquatable`") and CA1815 enforce parts of it. Records (C# 9, .NET 5)
generate all of it from the components: `record Money(int Cents,
string Currency)` prints `Money { Cents = 100, Currency = EUR }`, and
`==` compares values. `System.Uri` is the BCL's model for an immutable
reference type with value equality: it overrides `Equals` and
`GetHashCode` and overloads `==`.

**Options.**

- **`@auto("==")` classes:** generate `Equals(object?)`,
  `GetHashCode()` (`HashCode.Combine` over the same fields), and
  `IEquatable<T>.Equals(T?)`, keeping `Eq`. Additive. A hand-written
  `eq` (Hrefine's `Url`, by `href`) gets `Equals` delegating to it only
  once Temper has a `hash` to pair with it, as the Java and Python
  studies say.
- **`==` and `!=` operators:** the FDG allow them on immutable
  reference types with value semantics (from memory), but tours already
  use `==` as identity (`url.HostKind != HostKind.Domain`), which still
  works for singletons. Leave them out; when in doubt, leave it out.
- **`ToString`** for classes without one, in a record-like `Money {
  Cents = 100, Currency = EUR }` form, decided across backends (the
  JS, Python, and Java studies ask the same).
- **A Temper member named `equals`, `getHashCode`, `getType`,
  `memberwiseClone`, or `finalize`** compiles today, with warnings,
  and does the wrong thing (bug 4, under "Names clashing with
  `object`" below).

### Records, `sealed`, and constructors

C# records fit more Temper classes than Java's do (they allow private
fields and other members), but `with` expressions would bypass
constructor bodies and the checks in them. **Recommendation:** records'
behavior without their shape for now; revisit with
[#668](../../668-value-types/tom/claude-value-types.md). Two smaller
gaps:

- **No class is `sealed`.** Temper classes can't be extended, and Java
  marks them `final`, but C# users can subclass them (`class MySquare :
  Square` compiles) and hide members with `new`. The FDG's rule is
  "DO NOT seal classes without having a good reason" (from memory),
  but a class that can't be extended safely, with no virtual members,
  is that reason; sealing also lets the JIT devirtualize. Adding
  `sealed` later breaks subclasses, so it's better done before 1.0.
- **A private constructor is public** (bug 2). `@auto("==") export
  class Tag { … private constructor(name: String) … }` gives `public
  Tag(string name)`, so `new Tag("green")` makes a tag the library never
  defined. Python can't hide one; C# can, with `private Tag(…)`.

`Deconstruct` would let `var (x, y) = point` work (today `error
CS1061: 'Point' does not contain a definition for 'Deconstruct'`); it's
additive, but its parameter order becomes API, so it's for the
records decision.

### Immutability and aliasing

**Today.** Fields are `private readonly`, properties of non-`var`
properties have only `get`, exported values are `public static
readonly` fields, and statics such as `Point.Origin` and Kelpto's
`SanitizerPolicy.Standard` are getter-only static properties, so the
Java backend's reassignable statics have no C# counterpart (api-compat
proposal 7 is done). Temper's `List` results refuse writes, even
through casts:

```text
((IList<string>)FixedList())[0] = "z"           => NotSupportedException: Collection is read-only.
((IDictionary<string,int>)MakeMap())["z"] = 1   => InvalidCastException: Unable to cast … ReadOnlyDictionaryWrapper`2 … to … IDictionary`2
MakeMap()["z"]                                  => KeyNotFoundException: The given key 'z' was not present in the dictionary.
```

Chromarite's `demos/immutable` records all seven attempts as refused
for C#, as for Java and Rust. Three holes remain:

- **Lists passed in are kept by reference.**

  ```csharp
  var xs = new List<int> { 1, 2, 3 };
  var w = new Window(xs);
  xs[0] = 100;
  w.Sum()                      // 105; ReferenceEquals(w.Items, xs) is True
  xs.Clear();
  w.Sum()                      // TemperLang.Core.Panic: index 0 out of bounds for length 0

  var vals = new List<double> { 1.0, 0.5, 0.0 };
  var c = Color.FromList(Space.Srgb, vals);    // ToCss(): rgb(255 127.5 0)
  vals[0] = 0.0;                                // ToCss(): rgb(0 127.5 0)
  ```

  `IReadOnlyList<T>` is a read-only *view*, not a promise that nobody
  else writes. The BCL copies where it stores (`new
  List<T>(collection)`; `ImmutableArray.CreateRange`), and so does the
  FDG's advice on collections (from memory: don't hand out or keep
  mutable internals).
- **Live views can be cast back.** A `Listed` getter returns
  `Listed.AsReadOnly(b)`, which returns a `List<T>` as itself:
  `((List<string>)h.Live).Add(null!)` puts a `null` into the library's
  `List<string>`. Wrapping in `ReadOnlyCollection<T>` always (one small
  allocation) closes it.
- **`ImmutableList<T>` results** are safe but slow to index (section 7).

**Option.** At public entry points that store a `List` parameter,
copy unless the list is one the runtime made (`ReadOnlyCollection` over
an array it owns, or an `ImmutableList`); always wrap views. Calls
inside the library pay nothing.

### Numbers and strings

`Int` is `int` and `Int64` is `long`, unchecked, as C# defaults
(`AddInts(int.MaxValue, 1)` is `-2147483648`); a user project with
`<CheckForOverflowUnderflow>` doesn't change the library's assembly.
Strings are `string`, and Temper's string index is a UTF-16 offset, so
positions match `Substring` (`FirstCodePoint("😀x")` is 128512,
`CodePoints("😀x")` is 2); a lone surrogate panics in `ReverseOf`, as
on Java. One surprise that isn't C#'s: Temper's `==` on `Float64`
orders `-0.0` before `0.0` (`IsZero(-0.0)` is `False`), as Temper's
builtins docs say, where C#'s `-0.0 == 0.0` is true.

## 3. API shape

### Module classes: `…Global`, and types named like namespaces

**Today.** Each module's top-level functions and values are members of
`public static class <Last>Global` in the module's namespace
(`Hrefine.HrefineGlobal.ParseUrl`). Tours use `using static`, so the
name appears once:

```csharp
using Hrefine;
using static Hrefine.HrefineGlobal;
```

Each library also gets a `public static class Logging` in a
`<Root>.Support` namespace, with `Init(ILoggerFactory)`.

**What .NET users expect.** From memory, the FDG's namespace page:
"DO NOT use the same name for a namespace and a type in that
namespace", because a bare name then means the namespace wherever it's
in scope; CA1724 flags it. Facades are named for what they do
(`File`, `Path`, `Math`, `JsonSerializer`, `Regex`), never `Global`.
Checked here:

```text
class Csnames2 in namespace Csnames2, used from namespace MyApp with `using Csnames2;`:
  error CS0118: 'Csnames2' is a namespace but is used like a type
  warning CA1724: The type name Csnames2 conflicts in whole or in part with the namespace name 'Csnames2'.
`using System.Text.RegularExpressions; using TemperLang.Std.Regex;` then `new Regex(…)`:
  error CS0104: 'Regex' is an ambiguous reference between 'TemperLang.Std.Regex.Regex' and 'System.Text.RegularExpressions.Regex'
```

CA1724 also fires today on every library's `Support.Logging` (against
`Microsoft.Extensions.Logging`), on Kelpto's `Text` (against
`System.Drawing.Text`), and on the runtime's own `TemperLang.Core.Core`.
It didn't fire on std's `TemperLang.Std.Regex.Regex`, though that type
has both problems above.

**Two clashes the rename must handle** (both checked today):

- **A user class named like the module class wins silently** (bug 1):
  a module `csnames` with `export let csnames(): Int { 1 }` and `export
  class CsnamesGlobal {}` builds without error, and `CsnamesGlobal.cs`
  holds only the class; `Csnames()`, `Later()`, `Fails()`, and every
  other module function are gone. The Java backend has the same bug.
- **A user class named `Logging`** is lost the same way: the library's
  `Logging.cs` (namespace `Csnames.Support`) and the class's (namespace
  `Csnames`) are the same file, and the support file wins. `Logging`
  is a likely name for a library type.

The backend does handle classes named `Task`, `List`, and
`Exception` (it qualifies its own uses from `global::`) and a member
named like its class (`Item_()`).

**Options.**

| Option | Gains | Costs |
|---|---|---|
| A. Keep `<Last>Global` | Nothing to change | Says "Temper" to every reader; collisions as above |
| B. A better default suffix: `HrefineFunctions`, or F#'s `HrefineModule` | Reads as .NET; no namespace clash | Breaking; still a made-up word |
| C. A library-chosen name per backend (#676's naming mechanism): `Hrefine.Urls`, `Wherewith.Sql`, `Ordable.Sorting` | What the best .NET facades look like | Each library must choose; recorded in temper.keep |

Recommendation: B as the default and C for libraries that choose,
with the initial thoughts' option 1 (no type named like its module)
also covering C#'s namespace names, plus an error, never an
overwrite, when two generated names land in one file. Move logging
setup off a type named `Logging` (`HrefineLogging.Init`, or an
`InitLogging` member of the module class).

### Names, properties, and optional parameters

PascalCase members, `I` on interfaces, camelCase parameters (API in C#,
since callers can name them, and never renamed), and keywords as
verbatim identifiers (`@default`), so callers write `Shout(delete: "x",
@default: "y")`. Getters are properties and `var`s get `set`; methods
stay methods, so Hrefine's `Username()` stays out of
`System.Text.Json` output, as its tour notes. Underscores (CA1707)
appear only where escapes do: `Replacement.Replacement_`, `Text.Text_`,
std's `IJsonProducer.Float64_Value`, and Chromarite's `Space.A98_Rgb`.
None is worth a break alone.

An optional parameter is nullable with a `null` default, and the real
default is applied in the body (75 parameters in the six libraries):

```csharp
public static string Greet(string name, string? greeting = null)        // "Hello"
public Labeled(string label, int? weight = null, string? note = null)   // weight 1
```

Named arguments work (`DefaultNum(s: "x")` is `5x`), and the sentinel
has one real advantage: C# bakes a default into the *caller's*
assembly, so a `null` keeps the real default in the library. The
costs: IntelliSense shows `= null`, not `= "Hello"`, and `int?` lets
callers pass `null` for an `Int`. The FDG (from memory) prefer
overloads in reusable libraries and allow optional parameters.
**Option:** keep the sentinel and state the real default in the XML
docs (section 6).

### Collections in and out

Results are `IReadOnlyList<T>` and `IReadOnlyDictionary<K, V>`, and
builders `IList<T>` and `IDictionary<K, V>`. Because `IReadOnlyList<out
T>` is covariant, C# accepts what Java rejects: `TotalArea(new
List<Square>())` compiles where the parameter is `IReadOnlyList<IShape>`,
as does `Lengths(List<List<int>>)`. LINQ works on every result. But
.NET's `IList<T>` doesn't extend `IReadOnlyList<T>`, so:

```text
IList<string> names = …; ListLength(names)
  error CS1503: Argument 1: cannot convert from 'IList<string>' to 'IReadOnlyList<string>'
ListLength(bag.Builder)            (a Temper ListBuilder, as Temper allows)
  error CS1503: … from 'IList<string>' to 'IReadOnlyList<string>'
MapSize(IDictionary<string, int>)  error CS1503
ListLength(new HashSet<string>())  error CS1503
```

`docs/backends/README.md` says "Temper generates overloads of functions
taking a `Listed` that accept any of `List`, `IList`, or
`IReadOnlyList`, and likewise for `Mapped`"; no overloads are generated
today (bug 7). Arrays, `List<T>`, and `ImmutableArray<T>` pass, which
covers most callers.

Pairs are `KeyValuePair<K, V>`, so `new("q", "a b")` and dictionaries'
own entries go straight in, as Hrefine's tour shows; this is the
backend where `Pair` fits best.

### Callbacks and interfaces

Function types are `Func<…>` and `Action<…>`, so lambdas and method
groups work (`ApplyTwice(x => x * 3, 2)` is 18), as the FDG advise
("DO use the new `Func<...>`, `Action<...>`, or `Expression<...>`
instead of custom delegates", from memory). A `@fun` interface's names
are lost: Kelpto's `CodeHighlighter(info: String, code: String)` is
`Func<string, string, IReadOnlyList<HighlightSpan>?>`, and nothing says
which string is the code. Named delegates would break callers holding a
`Func`; the XML docs can say it instead.

Temper interfaces are C# interfaces; a default method is a C# 8 default
interface member calling a `protected static …Default` helper, which
generated classes re-declare publicly. A user's class implementing only
`Area()` works through the interface (`DescribeShape(new Half())` gives
`shape of area 0.5`), but, as with any C# default member, not through
the class: `new Half().Describe()` is `error CS1061: 'Half' does not
contain a definition for 'Describe'`. That needs a line in docs, not a
change. Sealed interfaces aren't sealed (`class Mine : IResult { }`
compiles and breaks exhaustive `is` checks); C# has no sealed
interfaces, so a doc line is the proportionate fix there too.

### Generators, async, and extension methods

Generators are `IEnumerable<T>`, so `foreach` and LINQ work
(`Fibonacci().Take(8)` is `[0, 1, 1, 2, 3, 5, 8, 13]`), but a
generator can be walked only once, and walking it again continues
where the last walk stopped (bug 3):

```text
var fib = Fibonacci();
fib.Take(3) twice    => 0,1,1 / 2,3,5
```

.NET's iterator methods restart on each `GetEnumerator`, and LINQ code
routinely enumerates twice (`Any()` then `foreach`), so this gives
wrong answers silently. Restart where Temper allows, else throw on the
second `GetEnumerator`.

Temper's `Promise<T>` is `Task<T>`: `Later(21)` starts as
`WaitingForActivation` and `await` gives 42. The runtime runs async
blocks one at a time and refuses to block inside a turn rather than
deadlock. The Task-based Asynchronous Pattern (from memory) adds an
`Async` suffix (`LaterAsync`) and a `CancellationToken`; the suffix is a
naming rule for #676, and cancellation waits on Temper. None of the six
libraries has an async API yet.

No extension methods are generated, and none are needed. The
runtime's are public, though, so `using TemperLang.Core;` adds
`Add(item, index)`, `RemoveLast()`, `GetOr`, and others to every
`IList<T>` in the user's file; making them `internal` keeps them out of
IntelliSense.

## 4. Errors

### Today

| What happens | What the .NET user sees |
|---|---|
| `Positive(-1)` (bubbles) | `TemperLang.Core.Bubble: Exception of type 'TemperLang.Core.Bubble' was thrown.` |
| `ParseUrl("setup.html")`, `Color.Parse("nope")`, `Parse64("x")`, `Divide(1, 0)` | the same; a full stack trace, from `Core.Bubble[T]()` through the library's frames |
| `NeedsPositive(-1)` (`orelse panic()`) | `TemperLang.Core.Panic: panic`, no inner exception |
| `Nth(new[] { "a" }, 5)` | `TemperLang.Core.Panic: index 5 out of bounds for length 1` |
| `OrPanic` with a callback throwing `InvalidOperationException("host bug")` | `InvalidOperationException: host bug`, passed through |
| `OrPanic` with a callback throwing `new Bubble("bad input")` | `Panic: panic`, the message and cause lost |
| `MakeMap()["z"]` | `KeyNotFoundException: The given key 'z' was not present in the dictionary.` |
| a callback changing what it walks | `InvalidOperationException` or `ArgumentOutOfRangeException` (section 8) |

`Bubble` extends `Exception` directly and `Panic` is `sealed : Exception`.
The good parts: stack traces are real (unlike Java's stackless
bubbles), `orelse` catches only `Bubble`, so host exceptions pass, and
`Bubble(string message, Exception cause)` exists for `@connected` code.
The rest:

- **No message.** Every library failure prints the framework's
  placeholder text. Hrefine's tour comment says `ParseUrl` "throws a
  plain System.Exception"; it throws a `TemperLang.Core.Bubble`, a
  subclass, so the comment's advice still holds but its wording is
  off. #164's C# translation says "the fallback `orelse` catches every
  exception", which is no longer so.
- **Panics are `Exception`s,** so a user's `catch (Exception)` around a
  library call, the most common C# catch, also catches library bugs.
  .NET has no "don't catch this" base besides `Exception`; the BCL uses
  `InvalidOperationException` or `Debug.Fail`, and fails fast with
  `Environment.FailFast` where it must. As in Java and Python, the
  choice is #164's.
- **Cost.** .NET exceptions are expensive, and Temper's `orelse` is
  built on them: a caught bubble costs about 9 to 10 µs here (section
  7), so `Url.Parse`, which returns `null` by catching a bubble, costs
  10 µs per invalid URL.

### What .NET users expect

From memory, the FDG's exception chapter: "DO NOT throw
`System.Exception` or `System.SystemException`" (CA2201), "DO throw
`ArgumentException` or one of its subtypes if bad arguments are
passed", "DO create a new exception type only if callers need to handle
it differently", custom types end in `Exception` (CA1710), "DO provide
a rich and meaningful message", and "CONSIDER the Tester-Doer or
Try-Parse pattern for members that may throw exceptions in common
scenarios" (`int.TryParse`, `Uri.TryCreate`), precisely because of the
cost measured above. BCL parsers show the shape: `FormatException:
The input string 'x' was not in a correct format.` and
`System.Text.Json.JsonException` with `LineNumber` and
`BytePositionInLine`.

### Options and ties to #164

- **Now, whatever #164 decides:** messages on runtime bubbles where
  the runtime knows one (the text for parses, the key for map lookups,
  "division by zero"); `Panic` with the bubble as `InnerException` in
  `orelse panic()`, and with the caught exception in index panics.
  Additive.
- **#164's library-named types** fit .NET well, as its C# translation
  shows (`WherewithException : Exception`, `sealed SqlProblem`). This
  study adds: document them with `<exception cref="…">` (section 6), so
  IDE hovers list them; and keep the `null`-returning twins
  (`Url.Parse` beside `ParseUrl`) as the Try pattern, ideally as
  `bool TryParse(string, [NotNullWhen(true)] out Url? url)` beside them
  for .NET users.
- **Cheaper `orelse`:** where Temper code bubbles and catches inside one
  library, an internal non-throwing path (a status return the
  translator generates for functions only `orelse` calls, or #164's
  `Result` lowering) would take `Url.Parse`'s failure cost from 10 µs
  toward `Uri.TryCreate`'s 0.014 µs. This is backend work with no API
  change, but large; worth it mainly for parsers, which is what most of
  the showcase libraries are.
- **Panics:** a dedicated type is already there (`Panic`); whether it
  should stay an `Exception` is #164's panic question.

## 5. Packaging

### What `temper build` writes

Each library gets a `net6.0` project with `Nullable` on, `IsPackable`,
the config's license, a `ProjectReference` to the runtime's project,
and `InternalsVisibleTo` for its tests; only Argmas sets a version.
`dotnet pack` gives this `.nuspec`, with `warning NU5104: A stable
release of a package should not have a prerelease dependency`:

```xml
<id>Argmas</id>
<version>0.1.0</version>
<authors>Argmas</authors>
<license type="expression">Apache-2.0 OR MIT</license>
<description>Package Description</description>
<dependency id="TemperLang.Core" version="0.7.0-alpha.0.267" exclude="Build,Analyzers" />
```

### Against NuGet's expectations

From memory, NuGet's package authoring best practices and the .NET
open-source library guidance:

| Expectation | Today |
|---|---|
| `PackageId` the author owns (a prefix reserved on nuget.org, such as `TemperLang.`) | the bare library name, `Argmas`, `Hrefine`; `csharpRootNamespace` can change it, and none of the six sets it |
| `Version` | only Argmas; the others pack as NuGet's default `1.0.0` |
| `Authors`, `Description` | the package ID and `Package Description`, though every config has a prose summary |
| `PackageProjectUrl`, `RepositoryUrl`, `PackageReadmeFile`, `PackageTags` | none (written only if the config names a homepage or repository) |
| XML docs in the package (`GenerateDocumentationFile`) | no, and nothing to put in them (section 6) |
| Symbols (`.snupkg`) and Source Link | neither; Source Link is built into the .NET 8 SDK and later, not 6 (from memory) |
| Dependency versions | `TemperLang.Core` as a minimum (`>= 0.7.0-alpha.0.267`), which is NuGet's default and better than other backends' exact pins |

### `TemperLang.Std` ships the test framework

std's project references `MSTest.TestFramework` 3.1.1 and
`Microsoft.NET.Test.Sdk` 17.8.0 as ordinary dependencies, because
std's `testing` module throws MSTest's `AssertFailedException` (a
comment in `lib.rs` says so). The packed `.nuspec` lists both, the
package carries a `TemperLang.Std.runtimeconfig.json` (the test SDK
makes a library look like a test executable), and a four-line console
program using std's `Regex` gets this beside it (bug 5):

```text
Microsoft.TestPlatform.CommunicationUtilities.dll  Microsoft.TestPlatform.CrossPlatEngine.dll
Microsoft.VisualStudio.TestPlatform.ObjectModel.dll  Microsoft.VisualStudio.TestPlatform.TestFramework.dll
Microsoft.VisualStudio.CodeCoverage.Shim.dll  Newtonsoft.Json.dll  NuGet.Frameworks.dll  testhost.dll
cs/ de/ es/ fr/ it/ ja/ ko/ pl/ pt-BR/ ru/ tr/ zh-Hans/ zh-Hant/      4.6 MB in all
```

Moving `testing` (or just its MSTest link) into the tests' project, or
into a separate `TemperLang.Std.Testing` package, fixes it; libraries'
own tests already reference MSTest themselves.

### Target frameworks, dependencies, and trimming

- **`net6.0` only** (the runtime also builds Kotlin's leftover
  `net48`). A `net6.0` library loads on every later .NET, so this is
  about reach, not support, but .NET 6 left Microsoft's support in
  November 2024 and .NET 8 in November 2026 (from memory), so CI should
  test on a supported runtime, as the tours' `RollForward` already
  allows.
- **`netstandard2.0`** would reach .NET Framework and Unity, one of the
  largest C# audiences. Default interface members are the blocker
  (nullable attributes and `System.Collections.Immutable` come as small
  packages there); generating default bodies into implementing classes,
  as generated classes already do, would remove it. Worth a decision.
- **Logging pulls in six assemblies.** `TemperLang.Core` depends on
  `Microsoft.Extensions.Logging` 8.0.0, so every library brings six
  `Microsoft.Extensions.*` assemblies (about 390 KB). `ILoggerFactory`
  lives in `…Logging.Abstractions` (from memory), which alone may do.
- **No strong names.** .NET Core ignores them; .NET Framework users may
  need them, so this matters only with `netstandard2.0`.
- **Trimming:** Hrefine, std, and kelpto-md built with `IsTrimmable`,
  `EnableTrimAnalyzer`, and `EnableSingleFileAnalyzer` give no IL
  warnings, and the runtime uses no reflection beyond `GetType() ==
  typeof(…)`. The .NET 6 SDK has no AOT analyzer, so AOT wasn't
  checked. `IsTrimmable` in generated projects would tell users.

## 6. XML docs

**Today.** No doc comments are emitted: Temper's `/** … */` comments
and the libraries' literate prose are both dropped (`/** A labeled
thing, with optional parts. */ export class Labeled` gives a bare
`public class Labeled`). The only `///` comments in the six libraries
are the 3 in each copy of the `Logging` support file. With
`GenerateDocumentationFile` on, CS1591 ("Missing XML comment for
publicly visible type or member") counts:

| Library | Files | CS1591 |
|---|---|---|
| Argmas | 51 | 270 |
| Chromarite | 13 | 77 |
| Hrefine | 20 | 164 |
| Kelpto (four libraries) | 146 | 982 (23, 111, 534, and 314) |
| Ordable | 7 | 29 |
| Wherewith | 78 | 162 |
| std | 63 | 294 |

1,684 for the six libraries. IntelliSense, the Object Browser,
DocFX, and nuget.org's API pages all read the XML file, so today
they show signatures only. From memory, the FDG and CS1591's own
existence: every public member documented, with `<param>`,
`<returns>`, and `<exception>`.

**Option.** Emit each declaration's doc as `/// <summary>`, with
`<param>` from Temper's parameter docs, `<paramref>` or `<see
cref>` for Temper's `[n]` references, `<exception
cref="Bubble">` for `throws Bubble`, and the real default of an optional
parameter; set `GenerateDocumentationFile` in the library project so
the XML ships in the package. The generated code has no other doc
warnings, so this turns the table toward zero. Escape `<`, `>`, and
`&` in prose.

## 7. Speed and size

Generated code against idiomatic hand-written C# (ms, .NET 6.0.10,
Release):

| Case | Generated | Hand-written |
|---|---|---|
| Sum 1M doubles, `List<double>` passed in | 4.7–6.6 | 1.0–1.6 (`for` over the `List<double>`) |
| Sum 1M doubles, an `ImmutableList<double>` (what Temper returns) passed in | 65–77 | 23–26 (`foreach`) |
| Sum 1M ints through a callback | 3.9–4.7 | 1.4–1.8 (`for`), 6.1–7.3 (`Sum(f)`) |
| Filter 1M ints, keeping all | 20–56 (`ToImmutableList`) | 2.8–31 (`Where(…).ToList()`) |
| 1M calls through `orelse`, none failing | 1.0–6.1 | — |
| 10,000 failing calls, caught | 81–103 (`Bubble`) | 0.09–0.22 (`int.TryParse`) |
| 10,000 `Url.Parse("setup.html")` (null) | 105–122 | 0.13–0.14 (`Uri.TryCreate`) |
| Parse 20,000 URLs | 47–57 (Hrefine) | 13–18 (`new Uri(u)`) |

Three costs stand out:

- **`ImmutableList<T>` results.** `Listed.ToReadOnlyList` (every
  `toList()`, `map`, `filter`, and `sorted`) returns an
  `ImmutableList<T>`, a balanced tree whose indexer is O(log n) and
  cache-unfriendly. Temper code indexes lists in loops, so a list a
  Temper library returns, passed back into one, is 13 times slower to
  walk than a `List<T>`. A `ReadOnlyCollection<T>` over a fresh array
  is O(1), refuses writes the same way, and costs one copy, which
  `ToImmutableList` costs too.
- **Interface indexing.** Even over a `List<double>`, the generated
  loop (`Listed.Get` on an `IReadOnlyList<double>`) is 4 to 5 times the
  hand-written one: .NET 6 can't devirtualize the interface call.
  .NET 8's dynamic PGO (from memory) may close much of it; not measured.
- **Exceptions.** About 9 µs per caught bubble, a thousand times a
  `TryParse`. Section 4 has the options. Java's stackless bubbles cost
  0.005 µs each; .NET has no stackless exceptions, though newer
  runtimes made throwing cheaper (.NET 9, from memory).

The URL row compares unlike work (`Uri` follows RFC 3986 and does no
WHATWG normalization or IDNA), so it only shows scale.

**Size.** Release assemblies: runtime 42 KB, std 54 KB; Kelpto 9 KB
(facade), kelpto-core 64 KB, kelpto-html 109 KB, kelpto-md 139 KB;
Chromarite 52 KB, Ordable 55 KB, Argmas 89 KB, Wherewith 123 KB,
Hrefine 166 KB, plus the six `Microsoft.Extensions.*` assemblies
(about 390 KB) every library brings through the runtime.

**Startup.** The first `ParseUrl` takes 48–54 ms (JIT plus Hrefine's
static constructor) and the first `Color.Parse` 20–25 ms; a program
making just those calls runs in 122–153 ms. ReadyToRun would cut the
JIT share, and lazy module tables, as in the JS and Java studies, the
rest.

## 8. Cross-backend patterns, checked for C#

The five cases from the JS study (`b` a builder changed by the callback
walking it):

| Case | C# | Java | JS (Node 24) | Python | Lua 5.4 | C++ |
|---|---|---|---|---|---|---|
| `reduceFrom` that grows `b` | `InvalidOperationException: Collection was modified; enumeration operation may not execute.` | 1299 | 12 | 1299 | 12 | heap-use-after-free |
| `map` that shrinks `b`, length | `ArgumentOutOfRangeException: Index was out of range.` | `ConcurrentModificationException` | 3 | 2 | 2 | 3, reading past the end |
| `forEach` on a map, adding keys | `InvalidOperationException` (as above) | 1, silently | 30 | `RuntimeError` | 30 | stops early by luck |
| `forEach` on a map, removing a later key | `InvalidOperationException` | `ConcurrentModificationException` | 3 | `RuntimeError` | 3 | `std::out_of_range` |
| `sort` whose comparison grows `b`, length | **3**: the additions vanish | `ConcurrentModificationException` | 7 | `ValueError` | 8 | heap-use-after-free |

C# is memory safe and fails loudly in four cases, with .NET's own
exceptions, which pass `orelse` and `Test.assertPanics` alike. The
`sort` case is silent (bug 6): `Listed.Sort` sorts a copy, clears the
list, and adds the copy back, so whatever the comparison added is
dropped, and the result looks valid. Whatever contract Temper settles
on, the C# runtime can meet it by checking a version or the length
around the callback, as .NET's own enumerators do.

| Pattern (from the earlier studies) | C# today |
|---|---|
| Failures without a message | Same: `Exception of type 'TemperLang.Core.Bubble' was thrown.` (section 4) |
| `orelse panic()` swallowing host errors (JS) | No: only `Bubble` is caught, but the bubble's own message is dropped |
| Runtime names in user code | Argmas's tour imports `TemperLang.Core` for `Optional<T>.OrNull()`; `TemperLang.Core.Bubble` to catch precisely |
| Lists passed in kept by reference | Yes (section 2), and live views can be cast back to `List<T>` |
| Returned lists aliasing library state | No for `List` results (`ImmutableList`, `ReadOnlyCollection`); yes for builders returned as `ListBuilder`, as Temper means |
| Exact runtime pins | No: a NuGet minimum version |
| Docs dropped | Same (section 6) |
| Values without equality, hashing, or a debug form | `Eq` on 15 classes, `Equals`/`GetHashCode` on none, `ToString` on 35 |
| Generated names colliding | `<Lib>Global` and `Logging` classes silently replace generated files |
| Names clashing with host members | Compile with warnings and misbehave (below) |

### Names clashing with `object`

Unlike Java, where `getClass` makes uncompilable code, every case
compiles, with warnings a library author never sees (CS0114 for
`GetHashCode` and a module function `ToString`, CS0108 for `GetType` and
`MemberwiseClone`, CS0465 for `Finalize`), and then misbehaves. For
`class Obj(n)` with `getHashCode()` returning `n` and `equals(other:
Obj)` comparing `n`:

```text
((object)a).GetHashCode() == a.GetHashCode() => False
a.Equals(b), ((object)a).Equals(b)           => True, False
new HashSet<Obj> { a, b }.Count              => 2
a.GetType()                                  => obj      (a string)
```

Only `toString` is right: it becomes `public override string
ToString()`. The rest should be escaped, or required to have .NET's
signatures and become overrides, and generated builds should treat
CS0108 and CS0114 as errors.

## Recommendations

**Quick wins** (not breaking):

1. Report any two generated C# files or names that collide
   (`<Lib>Global`, `Logging.cs`, nested modules sharing a last name)
   as an error rather than overwriting one.
2. Escape or reject members named for `object`'s (`GetHashCode`,
   `GetType`, `MemberwiseClone`, `Finalize`, `Equals` with another
   signature), and module functions named `ToString` or `Equals`;
   treat CS0108 and CS0114 in generated code as errors.
3. Make a Temper `private constructor` `private` in C#.
4. Generators: restart on each `GetEnumerator`, or throw on a second.
5. Take MSTest and the test SDK out of `TemperLang.Std`'s dependencies
   (move `testing`'s MSTest link to the tests' project or a separate
   package).
6. `Equals(object?)`, `GetHashCode()`, and `IEquatable<T>` for
   `@auto("==")` classes, from `Eq`'s fields.
7. Failures: messages on runtime bubbles; `Panic` keeps its cause as
   `InnerException`.
8. XML docs from Temper's doc comments and prose, with
   `GenerateDocumentationFile` on, so the package ships them.
9. Package metadata from the config: `Description` from the prose
   summary, `Authors`, a version default other than `1.0.0`,
   `PackageReadmeFile`, repository URL, symbols; `IsTrimmable`.
10. `ArgumentNullException.ThrowIfNull` on non-null reference
    parameters of public members; nullable context on in
    `TemperLang.Core`.
11. Results as `ReadOnlyCollection<T>` over an array instead of
    `ImmutableList<T>`; always wrap live views.
12. Make `sort` refuse (or panic on) a comparison that changes the
    list, instead of dropping the change.
13. Docs: correct the overloads claim in `docs/backends/README.md`
    (or generate them, recommendation 15), api-compat's "exported
    `let`s are `public static` fields" (they're `static readonly`
    now), the Hrefine tour's "plain System.Exception" comment, and
    #164's C# translation's "catches every exception"; a line on
    default interface members needing a cast.

**Medium changes:**

14. Copy stored `List` parameters at public entry points unless the
    runtime made them.
15. Accept `IList<T>` and `IDictionary<K, V>` where Temper takes a
    `Listed` or `Mapped`, by overloads as the docs describe, so
    builders and `IList` variables pass.
16. `sealed` on generated classes *(breaking only for code that
    subclasses them, which Temper never meant to allow)*.
17. `TryGetMaybe`-style members beside `Optional<T>` results, so no
    user imports `TemperLang.Core`; runtime extension methods
    `internal`.
18. A non-throwing internal path for bubbles that are caught inside
    the library, so `Url.Parse`-style twins cost what `TryParse` does.
19. Depend on `Microsoft.Extensions.Logging.Abstractions` only, if it
    covers the runtime's needs; logging setup off a type named
    `Logging`.
20. Test on a supported .NET in CI; consider `netstandard2.0` for
    .NET Framework and Unity, which needs default interface members
    lowered into classes.

**Design questions for #676 and #164:**

21. **Module class name** *(breaking)*: a better default than
    `Global` (`HrefineFunctions` or `HrefineModule`), a library-chosen
    facade name (`Wherewith.Sql`) through #676's naming mechanism,
    recorded in temper.keep; and the initial thoughts' option 1
    extended so no type is named like its namespace (std's `Regex`
    renamed, which fixes `CS0104` beside `System.Text.RegularExpressions`).
22. **Library-named failure types** *(breaking for `catch (Bubble)`)*:
    #164's `WherewithException : Exception`, documented with
    `<exception cref>`, with messages; `Try…` twins for parsers.
23. **Panics:** stay `Exception` (caught by every `catch (Exception)`)
    or something callers can't catch by accident.
24. **Records, `Deconstruct`, and `==`:** whether Temper value classes
    (#668) become records, and with what shape, decided once for C#,
    Java, and Python.
25. **`Async` suffix** *(breaking for existing async APIs, of which the
    six libraries have none)*: a per-backend naming rule for functions
    returning `Promise`.
26. **Fun interfaces:** keep `Func` (FDG's advice) or emit named
    delegates that keep parameter names *(breaking for callers holding
    a `Func`)*.
27. **Callback mutation:** which result Temper promises when a
    collection changes during its own callback; C# needs only `sort` to
    stop failing silently.
28. **Package IDs:** whether libraries default to a prefix the
    publisher reserves on nuget.org, as Java needs a `groupId`.

## Bugs found

On Temper `13dc5669` (`temper 0.7.0-alpha.0.267`), .NET SDK 6.0.402,
Linux. Each repro is the whole Temper module, in a library with a
`config.temper.md` naming it.

1. **Classes named like generated files silently replace them:**
   library `csnames`, module `export let csnames(): Int { 1 } export
   class CsnamesGlobal {}` builds without error; `CsnamesGlobal.cs`
   holds only the class, and `Csnames()` and every other module
   function are gone. `export class Logging(public level: Int) {}` is
   lost the same way to the generated `Support.Logging` (both are
   `src/Logging.cs`).
2. **A private constructor is public:** `@auto("==") export class Tag {
   public name: String; private constructor(name: String) { this.name =
   name; } public static red: Tag = doPure { new Tag("red") } }` gives
   `public Tag(string name)`; `new Tag("green")` compiles in user code.
3. **Generators can be enumerated only once:** with `fibonacci()` from
   `crates/temper-be-testkit/programs/async-turns.temper.md`, `var fib
   = Fibonacci(); fib.Take(3)` gives `0,1,1` the first time and `2,3,5`
   the second.
4. **Members named for `object`'s hide instead of override:** `export
   class Obj(public n: Int) { public getHashCode(): Int { n } public
   equals(other: Obj): Boolean { n == other.n } public getType():
   String { "obj" } }` compiles with CS0114 and CS0108 warnings;
   `new HashSet<Obj> { new Obj(1), new Obj(1) }.Count` is 2, and
   `obj.GetType()` returns a `string`. A module function `toString()`
   gives a static `ToString()` hiding `object.ToString`.
5. **`TemperLang.Std` depends on MSTest and the test SDK:** its
   `.nuspec` lists `MSTest.TestFramework` 3.1.1 and
   `Microsoft.NET.Test.Sdk` 17.8.0, and a console program that only
   constructs a `TemperLang.Std.Regex.Regex` gets `testhost.dll`,
   `Newtonsoft.Json.dll`, the test platform, and 13 resource folders,
   4.6 MB in all.
6. **`sort` drops what its comparison adds:** `let b = new
   ListBuilder<Int>(); b.add(3); b.add(1); b.add(2); b.sort { (a: Int,
   c: Int): Int => if (b.length < 40) { b.add(0); } a - c }; b.length`
   is 3 (`Listed.Sort` sorts a copy, clears, and re-adds), where Java
   throws and JS and Lua keep the additions.
7. **No overloads for `IList` arguments, though the docs promise
   them:** `export let listLength(xs: List<String>): Int { xs.length }`
   gives only `ListLength(IReadOnlyList<string>)`, so passing an
   `IList<string>` or a Temper `ListBuilder` from C# is `error CS1503`;
   `docs/backends/README.md` says overloads accepting `List`, `IList`,
   or `IReadOnlyList` are generated.
8. **Bubbles have no message, and panics drop their cause:** `export
   let positive(n: Int): Int throws Bubble { if (n <= 0) { bubble() }
   n }` throws `Exception of type 'TemperLang.Core.Bubble' was thrown.`;
   `export let orPanic(s: String, f: fn (String): Int throws Bubble):
   Int { f(s) orelse panic() }` with a callback throwing `new
   Bubble("bad input")` gives `Panic: panic` with no `InnerException`.
9. **Stored lists alias the caller's:** `export class Window { public
   items: List<Int>; public count: Int; public constructor(items:
   List<Int>) { this.items = items; this.count = items.length; } … }`
   keeps the caller's `List<int>`; Chromarite's `Color.FromList` does
   too. A `Listed` getter over a builder returns the `List<T>` itself,
   so a cast can write to it.
10. **Doc comments dropped:** `/** A labeled thing, with optional
    parts. */ export class Labeled(…)` produces no `///` comment.
11. **The runtime isn't nullable-annotated:** `TemperLang.Core`'s
    project leaves `<Nullable>` off, so `new Bubble(null)` gets no
    warning, and every build prints five CS86xx warnings from
    `Core.cs` and `Async.cs`.
