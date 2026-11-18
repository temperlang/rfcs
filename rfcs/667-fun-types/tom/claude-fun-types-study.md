# Fun types: a study of named and structural function types

Draft by Claude Code (Claude Opus 5.5), 2026-11-18. Suggestions only;
nothing here is decided. It supports [Mike's draft](../README.md) and
[#667](https://github.com/temperlang/temper/issues/667).

## Summary

- **Today, every backend erases fun interface names.** Kelpto's
  `CodeHighlighter` becomes `BiFunction<…>` in Java, `Func<…>` in C#,
  `std::function<…>` in C++, `Arc<dyn Fn(…)>` in Rust, and an arrow or
  `Callable` type in JS, Python, and Lua. So host APIs don't yet show
  the intent that names give, and bare types and named ones look alike
  to host users.
- **Explicit function types are rare and mostly generic.** In core,
  std, and six libraries there are 38 function types (25 in public
  APIs), with 22 distinct shapes, and none takes more than two
  arguments. Most fill generic slots (`transform`, `compare`, `key`),
  where a name like `Mapper` adds little. About six concepts deserve a
  domain name. There is one `@fun interface` (Kelpto's
  `CodeHighlighter`). Callers pass about 420 lambdas, nearly all of
  them target-typed block lambdas, so the choice mostly affects
  declarations, not calls.
- **The cost of nominal types is adapters between names that mean the
  same thing.** The code surveyed already forwards callback values to
  core: Ordable's `key` goes to `items.map(key)`, and Chromarite's
  `transform` goes to `values.map(transform)`. With one name per use,
  each of these needs a wrapper.
- **Tom's recommendation:** strictly nominal named fun interfaces, with
  a few role names in core (`Mapper`, `Predicate`, `Comparator`, …)
  mapped to host standard types, an explicit same-shape conversion
  (`Mapper(keySelector)`), and literals typed by their target
  ([details](#toms-recommendation-strictly-nominal-without-fnn),
  [counterarguments](#strongest-counterarguments)). An earlier
  suggestion with a generic `Fn0`–`Fn3` family is kept as an
  [alternative](#claudes-first-suggestion-an-alternative-considered).

## Where Temper is today

**Language.** `fn (A): R` is a structural function type, and it may
carry `throws` and type parameters (`fn<T> (T): List<T>`) or varargs
(`fn (...Int): Boolean`). `@fun interface Predicate<T>(x: T): Boolean;`
declares a functional interface: a single `apply` method, only
`AnyValue` as a supertype, no method type parameters, and no `is` or
`as`. Those rules let a backend emit either a nominal interface or a
plain function type ([types](https://temperlang.dev/), "Functional
interface"). Kotlin Temper's newer type system already models each bare
function type as a synthesized fun interface `Fn<I…, O>` per shape. A
top-level `let` can alias a type, as std's
`export let TestFun = fn (Test): Void throws Bubble;` does.

**Team context, not settled for this RFC.** An earlier team discussion
leaned toward named fun interfaces replacing bare function types, kept
strictly nominal, with function literals and function references
target-typed. Tempest follows that today: a `Pred` value isn't a
`Check` even when the signatures match, and the error suggests the
adapter `fn (y) { p(y) }`. A literal or a reference to a declared
function takes its interface from the type wanted. A literal with no
type wanted (`let f = fn (x: Int): Int { x + 1 }`) is an error, so a
tutorial example doesn't run. Bare `fn` types stay structural for the
functional tests.

**Backends.** Tempest's output for Kelpto's `CodeHighlighter`, as of
2026-11-17:

| Backend | `withCodeHighlighter(highlighter: CodeHighlighter)` becomes |
|---|---|
| C++ | `std::function<shared_ptr<vector<…>>(Str, Str)>`; an unused abstract `struct CodeHighlighter` is also emitted |
| C# | `Func<string, string, IReadOnlyList<HighlightSpan>?>` |
| Java | `java.util.function.BiFunction<String, String, @Nullable List<HighlightSpan>>` |
| JavaScript | JSDoc `(arg0: string, arg1: string) => readonly HighlightSpan[] \| null` |
| Lua | LuaLS `fun(arg0: string, arg1: string): …`; a `CodeHighlighter` class is also emitted |
| Python | `Callable[[str, str], Sequence[HighlightSpan] \| None]` |
| Rust | `Arc<dyn Fn(Arc<String>, Arc<String>) -> Option<List<HighlightSpan>> + Send + Sync>` |

Java picks a `java.util.function` interface by shape, so the type
depends on the primitives involved. A comparator `fn (T, T): Int`
becomes `ToIntBiFunction<T, T>` (not `java.util.Comparator`), or
`IntBinaryOperator` when `T` is `Int`. When no standard interface fits,
the backend synthesizes one per library under a name derived from the
shape. Hrefine's tests get
`hrefine.function.StringStringStringProcedure`, and the Java core
runtime carries 13 such interfaces of its own (`BooleanBiPredicate`,
`IntToObjReducer`, and others). Java signatures also omit wildcards
(`Function<T, String>`, where Java's own `Stream.map` takes
`Function<? super T, ? extends R>`).

So, to answer the draft's first question: ad hoc function types are no
implementation problem in tempest. Both forms work and translate the
same way. Their costs show up in design: unchosen names in Java, nowhere
for metadata to live, and no natural type for a literal with no target.

## Evidence from Temper code

Measured with [`claude-explore/count_fun_types.py`](claude-explore/count_fun_types.py)
on tempest's `lib/core` and `lib/std` and the sources of Argmas,
Chromarite, Hrefine, Kelpto, Ordable, and Wherewith. The full output,
listing every site, is in [`claude-explore/results.md`](claude-explore/results.md).

| Library | Fn types | API / internal / test | Shapes | Arity 0/1/2/3+ | `@fun` | Typed `fn` literals | Block lambdas (≈) |
|---|---:|---|---:|---|---:|---:|---:|
| core | 17 | 15 / 2 / 0 | 12 | 4/5/8/0 | 0 | 0 | 9 |
| std | 7 | 6 / 1 / 0 | 4 | 2/5/0/0 | 0 | 0 | 16 |
| Argmas | 0 | – | 0 | – | 0 | 0 | 15 |
| Chromarite | 4 | 2 / 2 / 0 | 3 | 0/3/1/0 | 0 | 0 | 72 |
| Hrefine | 0 | – | 0 | – | 0 | 0 | 22 |
| Kelpto | 0 | – | 0 | – | 1 | 0 | 70 |
| Ordable | 5 | 2 / 3 / 0 | 3 | 0/3/2/0 | 0 | 4 | 58 |
| Wherewith | 5 | 0 / 0 / 5 | 1 | 0/5/0/0 | 0 | 10 | 145 |
| **All** | **38** | **25 / 8 / 5** | **22** | **6/21/11/0** | **1** | **14** | **407** |

- **Shapes:** 22 distinct, 11 of them used once, and only one, `(T):
  String`, used in more than one library (core's `stringify` and
  Ordable's `key`, which have different meanings). No function type is
  generic in its own right: every type parameter belongs to the
  enclosing declaration.
- **Roles:** 11 mappers, 11 consumers (returning `Void`), 6 thunks, 4
  comparators, 3 reducers, 2 `(K, V): T`, and just one predicate
  (core's `filter`). `Predicate<String>`, the draft's example, is rare
  in real Temper code.
- **Generic or domain:** 23 of 38 slots, and 19 of 25 public ones,
  already carry a generic role in the parameter name (`transform`,
  `predicate`, `compare`, `accumulate`, `key`, `stringify`, `body`,
  `func`, `message`). For these, `Fn1<T, O>` or a core `Comparator<T>`
  says as much as a fresh name. Reviewed by hand, about six concepts
  deserve a domain name: core's generator body (4 sites), std's
  `TestFun` (already an alias) and the test reporter's `writeLine`
  sink, std regex's `format` (`(Match): String`, 3 sites, arguably
  generic), Chromarite's internal row builder, and Kelpto's
  `CodeHighlighter`. Wherewith's five test helpers share one
  `(QueryBuilder): Void`.
- **Arity:** at most 2 in every declared type. The only 3-argument
  function value found is a local function in Hrefine's tests, which
  Java turns into the synthesized `StringStringStringProcedure`.
- **Forwarding values:** among public callbacks, Ordable's
  `sortSmartByKey` passes its `key` to `Order.sortByKey`, which passes
  it to core's `items.map(key)`, and Chromarite's `Matrix.map` passes its
  `transform` to core's `values.map(transform)`. Under strictly nominal
  types with one name per use, each of these needs an adapter.
- **Callers:** about 407 block lambdas (counted as `=>`) and 14
  explicitly typed `fn` literals, against 38 type sites. Callers rarely
  write a function type, so target typing hides the choice from them.
- **Migration size:** whichever option wins, about 38 sites move.
  Migration cost isn't a reason to prefer one option over another.

## The options

**1. Only named fun interfaces, declared per use.**

```temper
@fun interface KeyFn<T>(item: T): String;
export let sortSmartByKey<T>(items: List<T>, key: KeyFn<T>): List<T> { … }
// Inside, core's `map` wants its own `Mapper<T, O>`:
//   items.map(key)                 // error: a KeyFn<T> isn't a Mapper<T, O>
//   items.map { x => key(x) }      // the adapter
```

Every function type gets a name, docs, and room for metadata. Java and
C# get real names instead of synthesized ones. The costs are naming
about 16 generic shapes that have no domain meaning, near-duplicates
across libraries (`KeyFn`, `Transform`, `Mapper`), and adapters wherever
values are forwarded. This is close to Java before Java 8 and to C#
before `Func`: C# 2 shipped `Predicate<T>`, `Comparison<T>`, and
`Converter<TIn, TOut>`, then .NET 3.5 added `Func` (and more `Action`s),
and the two families never interconvert.

**2. Ad hoc structural function types** (today's `fn (T): Boolean`).
Shapes need no ceremony, and values pass wherever the shapes match.
Hosts with function types map them directly. Java needs a name for every
shape, which today's backend picks itself (`StringStringStringProcedure`),
and those names become API that changes whenever the shape does.
Metadata (`throws E`, `forbids`, docs, parameter names) has to go into
the type syntax at every use. Variance is implied, since inputs are
contravariant and outputs covariant.

**3. Named only, plus generic `Fn0` to `Fn3` in core.** Domain concepts
get names. Small and one-off cases use `Fn1<T, String>`, which plays the
role that `Func`, Kotlin's `Function1`, and Scala's `Function1` play in
their languages. If bare syntax becomes sugar for `FnN`, this is also
the draft's "capitalize `fn`" variant: `fn (T): String` (or `Fn (T):
String`) would mean `Fn1<T, String>`, a nominal core type. That is
already how Kotlin Temper's type system models it.

**Hybrids.**

- **Structural compatibility between interfaces of the same shape**
  (any named interface converts to any other with the same signature)
  is, in effect, option 2 with names as documentation. Kotlin doesn't
  do this. Its SAM conversion applies to lambdas, not to values of
  another interface. Go doesn't do it implicitly either: a func literal
  (unnamed type) is assignable to a named func type, but two named
  types need an explicit, free conversion `B(a)`
  ([Go spec, assignability](https://go.dev/ref/spec#Assignability)).
- **Widening only to the anonymous family:** a named interface converts
  implicitly to the `FnN` of the same shape but never to another named
  interface. This half of Go's rule removes the forwarding adapters
  found above (`items.map(key)` works when `key: KeyFn<T>`) and keeps
  names meaningful between libraries.
- **Type aliases** (`let Predicate<T> = fn (T): Boolean`): names for
  documentation, with structural semantics. TypeScript, Python, Swift,
  Kotlin, Dart, C++ (`using`), Rust (`type`), and Lua (`---@alias`) all
  have aliases. Java has none, and C#'s are scoped to a file or project,
  so the name disappears in the two nominal hosts where it would matter
  most. Temper aliases are non-generic today.

## Host languages

| Host | Function types | Named function types | Lambda → named | Named value → other name of same shape | Parameter names kept | Arity |
|---|---|---|---|---|---|---|
| C++ | `std::function<R(A…)>`, templates/`std::invocable` | abstract class (lambdas don't convert); `using` alias | via alias only | alias: same type | no | variadic |
| C# | `Func<…>`, `Action<…>` | `delegate` types | yes, to any compatible delegate | no: `new Func<T,bool>(p)` or `p.Invoke` | yes (custom delegates) | `Func` up to 16 |
| Java | none | functional interfaces; `java.util.function` (43 interfaces, at most 2 arguments, primitive specializations) | yes, by target typing | no: `p::test` | yes | 2 in the JDK |
| JS / TS | `(x: T) => boolean` | aliases, call signatures (structural) | structural | yes | yes (TS requires them; documentation only) | – |
| Lua | plain functions; LuaLS `fun(x: T): boolean` | `---@alias` | structural | yes | yes | – |
| Python | `Callable[[T], bool]` | aliases; `Protocol` with `__call__` (structural) | structural | yes | `Protocol` only | – |
| Rust | closures implement `Fn`/`FnMut`/`FnOnce`; `impl Fn`, `dyn Fn`, `fn` pointers | trait plus blanket impl; `type` alias | automatic via blanket impl | via blanket impls | no | – |
| Go | `func(T) bool` | named func types (can have methods, like `http.HandlerFunc`) | yes | explicit conversion | documentation only | – |
| Swift | `(T) -> Bool` (`throws(E)`, `async`, `@Sendable` included) | `typealias` only; closures can't conform to protocols | via alias | yes | no (labels aren't part of function types) | parameter packs |
| Kotlin | `(T) -> Boolean` | `fun interface` (lambdas SAM-convert); `typealias` | yes | no | optional | 22, then `FunctionN` |
| Scala | `T => Boolean` (`Function1` to `Function22`) | SAM traits (since 2.12) | yes | no | – | Scala 3 lifted the 22 limit |
| Dart | `bool Function(T)` | `typedef` (alias) | structural | yes | optional | – |
| PHP | `callable`, `Closure` (no signature) | none (PHPStan docblocks) | – | – | – | – |
| Elixir | anonymous functions; typespec `(t -> boolean)` | `@type` alias | dynamic | – | – | – |

The pattern is that **nominal in Temper doesn't mean nominal in the
host.** Only Java, C#, Kotlin (`fun interface`), and a future C backend
(where a function pointer plus a context struct needs a `typedef`
anyway) can show a Temper name as a real type. Everywhere else, the best
mapping is the host's function type, with the name kept as an alias or
in docs. Temper checks the names, and host users mix them freely.

**By option:**

- **Idiomatic host API.** Generic callbacks are most idiomatic as the
  host's own types. In Java those are the `java.util.function` types and
  `Comparator`; in C#, `Func`/`Action` (LINQ's choice) and
  `Comparison<T>` for sorting; elsewhere, plain function types. Options
  2 and 3 do this for generic shapes. Option 1 gives Java and C# users a
  library-specific interface for every `map` argument. Domain concepts
  (`CodeHighlighter`) read better as named types in Java and C#.
- **Interop when host users pass lambdas** works in every host under
  every option, because Java, C#, and Kotlin target-type lambdas and the
  other hosts are structural. The friction is with **values** of host
  standard types. A Java `Comparator` (`String.CASE_INSENSITIVE_ORDER`)
  can't go where `ToIntBiFunction<String, String>` is wanted without
  `c::compare`. So mapping a few common roles to the host's standard
  types matters more for interop than how Temper itself names them.
- **Generated code size** doesn't decide anything. A named interface
  costs one small file in Java, one `delegate` line in C#, and an alias
  line or nothing elsewhere. Option 2 already generates per-library
  synthesized interfaces in Java, and the Java core runtime ships 13.
  Option 3 would put one shared family in each core runtime and drop the
  per-library synthesized names.

## Nominal pitfalls

- **Two libraries' `Predicate`s don't mix.** A `Predicate<T>` value from
  one library can't pass as another's, and core's `Fn1<T, Boolean>`
  isn't either of them. Literals and function references are
  target-typed, so only stored values need adapting. The code surveyed
  shows that forwarding stored values does happen, mainly into core.
- **Adapting** costs a wrapper `fn (x) { p(x) }`: an allocation and an
  indirect call on most backends. Backends could drop the wrapper where
  the host types coincide, which is common, since both names erase to
  the same host function type in all seven backends today, but only
  where the function's identity isn't observed.
- **One lambda, several interfaces.** A literal takes one target. Once
  it's stored as `A`, using it as `B` needs a wrapper, as in Java.
- **Core `Fn1` against a library's `Mapper`.** Without widening, a
  library choosing its own name pays an adapter whenever its value
  reaches a generic API, which pushes authors toward `Fn1` everywhere and
  undoes the intent argument. Widening named → `FnN` removes that
  pressure.
- **Mitigation** by target typing covers callers, who mostly write
  lambdas. Widening covers forwarding. Everything else is an explicit
  adapter with a clear error, as tempest already produces.

## Metadata on the type

- **Failure labels.** The [exceptions proposal](../../164-exceptions/tom/claude-proposal.md)
  puts a generic `E` on the interface (`Mapper<T, R, E extends Error>`),
  with `Never<Error>` for callbacks that can't fail
  ([note](claude-failure-labels.md)). Declaring `E` covariant (`out E`)
  makes a non-failing `Mapper<T, R, Never<Error>>` a subtype of
  `Mapper<T, R, E>` through ordinary variance, with no special rule. For
  `FnN`, either every arity carries `E` (`Fn1<A, R, E>`), which needs
  default type arguments to stay readable, or `fn (A): R throws E` sugar
  fills it in.
- **`forbids` clauses** ([RFC 659](../../659-memory-management/README.md))
  belong naturally on a named interface:
  `@fun interface Listener<T>(e: T): Void forbids Registry;`. On `FnN`
  they'd need use-site bounds or intersections, which is one reason to
  name a concept.
- **Purity and effects.** Today's markers (`GeneratorFn`, the `extends`
  clause on block lambdas) and host needs (Rust's `+ Send + Sync`,
  Swift's `@Sendable`) suggest letting `@fun` interfaces extend marker
  interfaces, which the current "only `AnyValue`" rule forbids.
- **Parameter names** appear in C# delegates, Java SAM methods, TS, Lua,
  Kotlin, and Python `Protocol`s, but not in Swift function types. Today
  JS and Lua get `arg0`, `arg1`. Named interfaces would carry real names.
  In C#, those names are API.
- **Variance.** Structural types are contravariant in inputs and
  covariant in outputs. A declared interface needs `in`/`out` (`@in` is
  deprecated), or a `Mapper<Animal, String>` won't fit where a
  `Mapper<Cat, String>` is wanted. Since a fun interface has exactly one
  method, its variance could be inferred safely. Java output should then
  use wildcards (`Function<? super T, ? extends R>`).
- **Documentation per interface** is the main gain of names: one place
  to explain a callback's contract (for example, "return null for no
  highlighting").

## Generics and arity

- **How many arities?** The evidence never exceeds 2, so `Fn0` to `Fn3`
  covers everything seen, with room to spare. Beyond that, a named
  interface is required, which nudges authors toward an object literal
  or a domain name. C# stops `Func` at 16 and tempest doesn't yet handle
  more. Kotlin and Scala capped at 22 and later lifted the cap. The JDK
  stops at 2.
- **`Void` results.** Eleven of the 38 return `Void`. C# splits
  `Func`/`Action` and Java splits `Function`/`Consumer`/`Runnable` for
  this reason. `Fn1<A, Void>` needs either a rule that allows `Void` as
  a type argument there, mapping to the host's action type, or a
  parallel family. This is an open question.
- **Varargs** (`fn (...Int): Boolean`) fit a named interface
  (`apply(...xs: Int)`), and C# custom delegates and Java SAMs can take
  them. `FnN` can't, so varargs callbacks need names. None were found.
- **Generic function types** (`fn<T> (T): List<T>`) can't be fun
  interfaces, which forbid method type parameters. None were found in
  real code.

## What the draft could add

Suggested sections and questions:

1. **The decision as options**, with the evidence above: the share of
   generic slots, the forwarding cases, and the migration size.
2. **Host naming of generated interfaces.** The case and package of
   names (`kelpto_md.CodeHighlighter`), the method name in Java (`apply`,
   or a host verb like `test` or `accept`), and whether hosts without
   nominal types get aliases (TS `type`, Python `type`/`Protocol`, Rust
   `type`, C++ `using`, LuaLS `---@alias`). Also stop emitting unused
   declarations, as C++ and Lua do now.
3. **Mapping to host standard interfaces** when the meaning matches, not
   only the shape: `Comparator<T>` to `java.util.Comparator` and C#
   `Comparison<T>`, `FnN` to `java.util.function` and `Func`/`Action`,
   including Java's primitive specializations (which make one Temper
   type map to different Java types per instantiation).
4. **Subtyping rules:** strictly nominal between named interfaces,
   widening to `FnN` or not, and how failure-free callbacks fit failing
   slots (variance on `E`).
5. **Variance** of fun interface type parameters: declared or inferred,
   and wildcards in Java output.
6. **Metadata:** `throws E`, `forbids`, marker supertypes (relaxing
   "only `AnyValue`"), parameter names, and docs.
7. **Arity and `Void`:** which `FnN` exist and how `Void` results map.
8. **Natural type of an untargeted literal.** With `FnN`,
   `let f = fn (x: Int): Int { x + 1 }` could simply be an
   `Fn1<Int, Int>`, as C# 10 gives lambdas a natural `Func`/`Action`
   type. That fixes the REPL, playground, and tutorial cases that error
   today.
9. **Compatibility and `temper.keep`:** a callback's host type is API.
   Changing `Fn1` to a named interface, or renaming either the interface
   or its parameters, breaks Java and C# users but not TS or Python
   ones. `temper.keep` should record each interface's name and host
   mapping.
10. **Migration** of the 38 existing sites and the functional tests:
    automatic if bare syntax becomes sugar for `FnN`, otherwise a quick
    fix.
11. **Error messages:** "a `KeyFn<T>` isn't a `Mapper<T, O>`; wrap it:
    `{ x => key(x) }`", plus a hint when a host-standard mapping exists.
12. **Hosts that need names**, for the draft's second question: C (a
    function pointer plus a context struct) and Zig need named types,
    and BEAM, Go, and Swift don't. Named interfaces in the source help
    the first group without hurting the second.

## Java naming, today and proposed

**Today** (tempest, matching Kotlin Temper), a function type or a `@fun`
interface becomes the `java.util.function` interface whose signature
fits by kinds (int, long, double, boolean, void, or object):
`IntUnaryOperator` for `fn (Int): Int`, `Predicate<T>` for
`fn (T): Boolean`, and `ToIntBiFunction<T, T>` for a comparator. That
match is by shape, not meaning, so a comparator is never
`java.util.Comparator`. Where nothing fits, the library gets its own
interface in its `<package>.function` package, named by concatenating
types: `Float64Float64Int32`, `StringStringStringProcedure`,
`Int32ListBuilderProcedure`, or `Nullary…` with no parameters. The
method is named for the result kind (`accept`, `test`, `applyAsInt`,
`apply`), and a clash adds a numeric suffix. Shapes with type
parameters that no standard interface fits, such as `fn (T, Int): Void`,
aren't supported yet in tempest. Kotlin maps that one to
`ObjectIntConsumer`, a misspelling of the JDK's
[`ObjIntConsumer`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/function/ObjIntConsumer.html).

**Assessment.** Standard interfaces where they fit are good. The
synthesized names are mechanical and carry no intent. They also belong
to each library, so two libraries' identical shapes aren't
interchangeable, and host code adapts between them with method
references. Matching shape before meaning loses `Comparator` and every
domain name, and generic shapes fail outright.

**Suggestion.** Named fun interfaces become real Java interfaces with
their own names, recorded as API in `temper.keep`. A named interface
maps to a host standard interface instead when the meaning matches, as
core's `Comparator<T>` would to `java.util.Comparator`. Ad hoc `fn`
types, as sugar for core's `Fn0` to `Fn3`, map to `java.util.function`
when an exact kind fits, and otherwise to one shared generic set rather
than per-library synthesized ones. That fixes interop and the generic
gap. The cost is boxing for primitive shapes the JDK doesn't cover;
specializations could be added later if measurements show a need.

## Keeping Temper's names out of host APIs

**The tension.** A shared generic set in the runtime (say
`temper.core.function.Fn2`) puts a Temper package name into library
signatures. A goal of Temper libraries is that host users never need to
know about or name Temper. The options:

- **Host standard types only where possible** (Java's
  `java.util.function`, C#'s `Func`/`Action`, Kotlin's function types),
  falling back to library-owned interfaces with meaningful names, taken
  from the named fun interface or generated from the parameter's role
  (`ReplaceFormat` for `replace`'s `format`), instead of concatenated
  types. No Temper names leak, but uncovered shapes are again per
  library and don't interoperate.
- **A neutral shared package**, not branded Temper. That gives one set
  everyone shares, but it's still a dependency host users have to name.
- **Accept the runtime package for rare fallbacks.** That's simplest.
  The evidence above shows few shapes outside the JDK's coverage, so
  host users would seldom see it.

The first option seems best for public signatures, with the third
acceptable for internals.

**Structural hosts.** Users should pass plain functions and see a named
interface's name only as an alias or in docs. Nominal hosts make the
name a real type, which costs adapting between names: C# lambdas
convert to any compatible delegate, but a `Predicate<T>` value needs
adapting to become a `Func<T, bool>`, and Java lambdas target any
functional interface, but an interface value needs `f::method` to
become another.

| Backend | Today, for a `@fun` interface | Suggested |
|---|---|---|
| C++ | erased to `std::function<…>`, plus an unused declaration | `using Predicate = std::function<bool(const T&)>` (template alias for generics), or a template parameter where speed matters; drop the unused declaration |
| C# | erased to `Func`/`Action` | a `delegate` named for the interface, so parameter names are kept; or the BCL type when the meaning matches (`Comparison<T>`) |
| Java | erased to a `java.util.function` or synthesized interface | a named interface, or the JDK one when the meaning matches (above) |
| JS | erased to an arrow type in JSDoc | a named, exported JSDoc `@callback Predicate` (with `@param`/`@returns`, so names and docs carry) or `@typedef {(value: T) => boolean} Predicate`, used by name in signatures; any function still works. tempest emits no `.d.ts` today; a `.d.ts` with `type Predicate<T> = (value: T) => boolean` is a possible later step |
| Lua | erased to a LuaLS `fun(…)` type, plus an unused declaration | `---@alias Predicate fun(value: T): boolean`, used in signatures |
| Python | erased to `Callable[…]` | an alias, `Predicate = Callable[[T], bool]`, or PEP 695 `type Predicate[T] = Callable[[T], bool]` (3.12+, so the old form while 3.11 is targeted) |
| Rust | erased to `Arc<dyn Fn(…) + Send + Sync>` | a `type` alias for the `Arc<dyn Fn>` form; or a public trait with a blanket impl, `trait Predicate<T>: Fn(&T) -> bool {}` plus `impl<T, F: Fn(&T) -> bool> Predicate<T> for F {}`, so any closure works (a `type` can't alias a trait bound, and `impl Fn(&T) -> bool` with docs is the alternative) |
| Go (future) | – | `type Predicate[T any] func(T) bool`, assignable from function literals |
| Swift (future) | – | `typealias Predicate<T> = (T) -> Bool` |

This ties to the earlier point about parameter names. They're API in C#
(named arguments on a delegate's `Invoke`) and in Swift, where function
types drop argument labels, so a `typealias` keeps the name but not the
labels. Changing them breaks callers there but not in structural hosts,
so `temper.keep` should record both the interface name and its parameter
names.

## Tom's recommendation: strictly nominal, without `FnN`

Tom's position, 2026-11-18, after reviewing the suggestion above:
named fun interfaces only, with no generic `Fn0`–`Fn3` family.

- **Core provides a few role names,** chosen by meaning and mapped to
  host standard types where they exist: `Mapper`, `Predicate`,
  `Comparator`, `Consumer`, `Supplier`, `Accumulator`, and perhaps
  the two map-entry forms (see the appendix). Libraries use these or
  declare their own.
- **An explicit conversion between same-shape names,** written like a
  constructor call, `Mapper(keySelector)`. The compiler generates the
  adapter per backend: a method reference in Java (`keySelector::apply`),
  a new delegate in C#, and nothing in JavaScript, Python, Lua, Rust,
  C++, or Go, where both are the same function value.
- **Function literals need a target type,** as in Java and C#: an
  argument position or `let f: Mapper<Int, Int> = fn …`. Without one,
  the error suggests a core name. `fn (A): R` syntax either goes away
  or is shorthand valid only where a target exists.

Reasons:

1. **Implicit conversion would hide allocations.** Converting one
   functional interface to another allocates an adapter in Java (and a
   delegate in C#, and Kotlin's SAM conversions allocate too); an
   explicit conversion keeps that cost visible.
2. **Forwarding is easy enough with an explicit conversion,** and
   obvious at the call site.
3. **No evidence of repeated conversions.** Only two forwarding sites
   exist (Ordable's `key` and Chromarite's `transform`, each passed
   once into core's `map`), and both disappear if libraries use core's
   role names. The whole codebase has one `@fun interface`.
4. **Unnamed function types aren't bulky in practice.** Shapes are short
   (`fn (T): Boolean` is about as long as `Predicate<T>`), and only 3
   of 22 shapes repeat more than twice. Names pay off most for long
   signatures with failure labels and `forbids` clauses, which names
   keep in one place.

## Draft core and std changes

[claude-explore/core-fun-types.patch](claude-explore/core-fun-types.patch)
drafts Tom's recommendation against tempest's `lib/` (a draft for
discussion, not applied):

- **core:** `Mapper`, `Predicate`, `Comparator`, `Accumulator`,
  `Consumer`, `Supplier`, `EntryMapper`, and `EntryConsumer`, exported,
  with docs; internal `GeneratorStep` (may bubble) and
  `SafeGeneratorStep`, mirroring `Generator` and `SafeGenerator`. Every
  `fn` type in core's API becomes one of them: `map` and `join` take a
  `Mapper`, `filter` a `Predicate`, `sort` and `sorted` a `Comparator`,
  the `reduce` family an `Accumulator`, the `forEach`s a `Consumer` or
  `EntryConsumer`, `toListWith` an `EntryMapper`.
- **std testing:** `assert`'s message is a `Supplier<String>`;
  `TestFun` becomes `@fun interface TestFun(test: Test): Void throws
  Bubble`, keeping its name; `reportTestResults` takes a
  `Consumer<String>`.
- **std regex:** a new `Replacer(match: Match): String` for `replace`.
- Nothing else in std has function types.
- These new core members are this RFC's to define; the broader core
  cleanup in [RFC 671](../../671-core-cleanup/tom/claude-core-cleanup.md)
  doesn't add them.

**Found while checking the draft:** generic `@fun interface`s (such as
`Mapper<T, R>`) run on the interpreter but tempest's translation stops
with "not yet in tmpl: a type parameter" (non-generic ones translate),
so supporting type parameters on fun interfaces is a prerequisite.

## Strongest counterarguments

- **Fragmentation across libraries.** Every library that names its own
  `KeySelector` or `Transform` creates a type others must convert to.
  .NET is the cautionary tale: `Predicate<T>`, `Converter<TIn, TOut>`,
  and `Comparison<T>` came first, then `Func`/`Action`, and APIs taking
  one can't take the other without adapting. Mitigation: core's role
  names as the strong default, and guidance to use them.
- **Host users holding host function values.** C# code with a
  `Func<int, int>` in hand, or Java code with a `java.util.function.Function`,
  must adapt it to a Temper-named delegate or interface. With a generic
  family mapped to the host's own types there is no friction.
  Mitigation: map each core role name to the host's standard type where
  one exists (Java `Predicate`, `Consumer`, `Supplier`, `Comparator`,
  `Function` for `Mapper`; C# `Func`/`Action` or `Predicate<T>`), so
  friction remains only for names libraries invent.
- **Ergonomics where nothing gives a target.** Scripts, the REPL,
  tutorials, and local helpers (`let double = fn …`) need an annotation
  that Kotlin, Swift, TypeScript, Rust, and Go infer. That's friction
  for newcomers, though Java and C# show it's learnable.
- **Role explosion over time.** Java's `java.util.function` grew to 43
  interfaces through roles times arities times primitive kinds. Temper
  has no primitive specializations to multiply, but roles times
  arities (`BiConsumer`, `BiPredicate`, …) still grow; a generic family
  stays flat.
- **Generic higher-order utilities.** `compose`, `memoize`, `retry`, or
  adapters written once for any shape need one version per role, where
  a generic family needs one per arity.
- **Migration.** The 38 existing `fn` types and every untargeted literal
  in tests and docs need names or annotations.

On balance these argue for core's role names being well chosen and
mapped to host standard types, not necessarily for `FnN`; the .NET and
host-interop points are the ones to weigh most.

## Claude's first suggestion (an alternative considered)

**Named fun interfaces for meaning, one small anonymous core family for
everything else, and widening from named to anonymous only.**

- `@fun interface` is how a library declares a function type that means
  something: docs, parameter names, `forbids`, a failure parameter, and
  a real type name in Java, C#, Kotlin, and C. Named interfaces stay
  strictly nominal among themselves.
- Core provides `Fn0` to `Fn3` (with failure and `Void` handling
  settled as above), plus `Comparator<T>` because hosts treat
  comparators specially. Bare `fn (A): R` syntax becomes sugar for the
  matching `FnN`, or is spelled `Fn (A): R` if the team wants the
  capital. Existing code then migrates for free, and untargeted literals
  get a natural type.
- A named interface value widens implicitly to the matching `FnN`, so
  forwarding into core and generic APIs needs no adapter. Conversions
  between named interfaces stay explicit.
- Backends map `FnN` to each host's own function types and standard
  interfaces, with one shared fallback set (not per-library names) for
  shapes those don't cover. Named interfaces map to host named types
  where those exist, and to an alias plus docs elsewhere, so host users
  pass plain functions and rarely see a Temper package name.

**The main tradeoff:** names give intent, documentation, a home for
metadata, and stable host API names, at the cost of adapters between
names that mean the same thing. The evidence says most callback slots
are generic and that values do get forwarded into core. One shared
anonymous family keeps that cost confined to the rare named-to-named
conversion, while still giving domain concepts the names Mike wants.
"Only named, per use" maximizes intent but makes about 16 generic shapes
into names and adapters. "Only structural" is simplest but leaves Java
with names nobody chose and leaves metadata nowhere to live.

## Appendix: a name for every function type (suggestion)

If every function type in core, std, and the six libraries had to be a
named fun interface, reusing a name wherever the meaning aligns, 13
names would cover the 22 shapes ([evidence](claude-explore/results.md)):

| Name | Shape | Uses today |
|---|---|---|
| `Mapper<T, R>` | `(T): R` | core `map`; Chromarite's `transform` (`Mapper<Float64, Float64>`, `Mapper<Listed<Float64>, T>`); core `joinToString`'s `stringify` (`Mapper<T, String>`) |
| `KeySelector<T, K>` | `(T): K` | Ordable's `key` (`KeySelector<T, String>`, `KeySelector<String, String>`); C#'s LINQ name |
| `Predicate<T>` | `(T): Boolean` | core `filter` |
| `Comparator<T>` | `(T, T): Int` | core `sort`/`sorted`; Ordable's `compare` (`Comparator<String>`) |
| `Accumulator<A, T>` | `(A, T): A` | core `reduceFrom`, `reduceFromIndex`; `reduce` takes `Accumulator<T, T>` |
| `Consumer<T>` | `(T): Void` | core `forEach`; `String.forEach` (`Consumer<Int>`); std's `writeLine` (`Consumer<String>`); Wherewith's test `build` (`Consumer<QueryBuilder>`) |
| `EntryMapper<K, V, R>` | `(K, V): R` | `Map.toListWith`, `toListBuilderWith` |
| `EntryConsumer<K, V>` | `(K, V): Void` | `Map.forEach` |
| `Supplier<T>` | `(): T` | std testing's `message` (`Supplier<String>`) |
| `GeneratorStep<Y>` | `(): GeneratorResult<Y>` (with or without a failure label) | core's generator functions |
| `Replacer` | `(Match): String` | std regex `replace`'s `format` |
| `TestBody` | `(Test): Void` with a failure label | std testing's `TestFun` |
| `CodeHighlighter` | `(String, String): List<HighlightSpan>?` | Kelpto (already named) |

Notes:

- Seven generic roles cover most uses. `Predicate`, `Comparator`,
  `Consumer`, and `Supplier` match Java's `java.util.function` and
  `java.util.Comparator`, and `Mapper` corresponds to Java's `Function`,
  so mapping to host standard interfaces would be natural.
- Only `GeneratorStep`, `Replacer`, `TestBody`, `CodeHighlighter`, and
  Chromarite's internal `(Listed<Float64>, ListBuilder<Float64>): Void`
  (which fills a builder from a row; better named locally, e.g.
  `RowFill`) need domain names, consistent with the estimate above.
- `KeySelector` versus `Mapper` is a judgment call: the same shape, but
  the name says the result is used to order or group. Folding it into
  `Mapper` leaves 12 names.
- `Function` is avoided as a name: it collides with JavaScript's
  built-in `Function` and Kotlin's function types.

## Sources

- Java: [`java.util.function`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/function/package-summary.html),
  [JLS §9.8 functional interfaces](https://docs.oracle.com/javase/specs/jls/se21/html/jls-9.html#jls-9.8)
- C#: [delegates](https://learn.microsoft.com/en-us/dotnet/csharp/programming-guide/delegates/),
  [`Func<T1,…,T16,TResult>`](https://learn.microsoft.com/en-us/dotnet/api/system.func-17),
  [natural type of a lambda](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/lambda-expressions#natural-type-of-a-lambda-expression)
- Kotlin: [function types](https://kotlinlang.org/docs/lambdas.html#function-types),
  [fun interfaces](https://kotlinlang.org/docs/fun-interfaces.html)
- Scala 3: [dropped limit 22](https://docs.scala-lang.org/scala3/reference/dropped-features/limit22.html)
- Rust: [`Fn`](https://doc.rust-lang.org/std/ops/trait.Fn.html),
  [closures](https://doc.rust-lang.org/book/ch13-01-closures.html)
- Go: [assignability](https://go.dev/ref/spec#Assignability),
  [`http.HandlerFunc`](https://pkg.go.dev/net/http#HandlerFunc)
- Swift: [function types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/types/#Function-Type)
- Python: [annotating callables](https://docs.python.org/3/library/typing.html#annotating-callable-objects),
  [PEP 695](https://peps.python.org/pep-0695/)
- Lua: [LuaLS annotations](https://luals.github.io/wiki/annotations/)
- TypeScript: [function type expressions](https://www.typescriptlang.org/docs/handbook/2/functions.html#function-type-expressions)
- C++: [`std::function`](https://en.cppreference.com/w/cpp/utility/functional/function)
- Dart: [typedefs](https://dart.dev/language/typedefs)
