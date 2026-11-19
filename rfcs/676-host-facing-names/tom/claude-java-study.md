# Temper libraries from a Java user's point of view

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

## The question

Does a Temper library look and behave like a Java library to someone
who writes Java (or Kotlin on the JVM), and what would make it more so?

**Short answer:** the runtime behavior is the best of any backend
studied so far, and the API shape is a little dated. Generated code
compiles cleanly under `javac -Xlint:all` on JDK 17 and 21, all six
tours print their expected output, lists are `java.util.List`, maps are
`java.util.Map`, pairs are `Map.Entry`, callbacks are
`java.util.function` types that take lambdas and method references,
interfaces take lambdas too, optional parameters become overloads plus
a `Builder`, `orelse` catches only Temper's own failures, and hot loops
run as fast as hand-written Java. No tour imports anything from
`temper.*`. What a Java user trips on: no class has `equals` or `hashCode`
and most have no `toString` (15 have an `eq` method instead), so values
can't go in a `HashSet` or be compared in tests; lists passed in are
kept by reference, so an immutable object changes when the caller's
list does; failures are a `temper.core.Bubble` with no message and *no
stack trace*, so an uncaught one prints only `Exception in thread
"main" temper.core.Bubble`; panics are `AssertionError`s; nullness is
`@temper.core.Nullable`, which Kotlin doesn't recognize; doc
comments are dropped (javadoc's doclint reports 39 to 1,015 warnings per
library, nearly all missing comments); and the POMs can't be published to Maven Central or even
built by a stock Maven setup. Four compiler bugs stand out: a property
named `class` or a method named `wait` or `notify` makes uncompilable
Java, a class named `<Lib>Global` silently replaces the module's
functions, some public statics come out non-`final` (Kelpto's
`SanitizerPolicy.standard` can be reassigned by any code in the JVM),
and a map literal's `javac` time grows steeply with its size. Most fixes
are small and additive; equality, records, and error types are design
questions for this RFC and [#164](../../164-exceptions/README.md).

## How this was studied

- Built the six showcase libraries (Argmas, Chromarite, Hrefine,
  Kelpto, Ordable, and Wherewith) with Temper's compiler (`temper build
  -b java`; `temper 0.7.0-alpha.0.267` at `13dc5669`, a release build
  whose working tree also had uncommitted JS backend and docs changes,
  none in the Java backend), and ran each library's Java tour (plain
  `javac` and `java`, as the tours' Gradle files do): all six match their
  `expected.txt`, and Argmas's examples match `examples.txt`. Wherewith's
  example also ran through its own Gradle 9.0.0 build, on JDK 21 and 17.
- Wrote a probe library (about 230 lines of Temper: nullables,
  defaults, `Int` and `Int64`, lists and maps in and out, a class that
  keeps a list, builders held by classes, `@auto("==")`, getters and a
  `var`, statics, a generic class and function, a sealed interface,
  keyword-named members, a fun interface, an interface with a default
  method, bubbles and panics, and builders changed during their own
  callbacks), plus small ones for names and statics, and Java programs
  that use them and the libraries as a Java user would. Every snippet
  below was run; output is quoted as printed.
- Toolchains: Temurin JDK 21.0.4, 17.0.7, and 8u372; Maven 3.9.9
  (offline, against a copy of a local repository); Gradle 9.0.0.
  No Kotlin compiler was available, so Kotlin claims are from memory and
  marked so.
- Read the Java backend (`crates/temper-be-java`, especially `lib.rs`,
  `names.rs`, and `translate/classes.rs`), its runtime
  (`crates/temper-be-java/runtime/temper-core`), `docs/backends/README.md`,
  `notes/api-compat.md` (its Java section and proposals 6 and 10),
  [#164's Java translation](../../164-exceptions/tom/claude-translations/java.md),
  and the sibling studies for [Lua](claude-lua-study.md),
  [Rust](claude-rust-study.md), [C++](claude-cpp-study.md),
  [Python](claude-python-study.md), and [JS](claude-js-study.md).
- docs.oracle.com, openjdk.org, and central.sonatype.org weren't
  reachable from here. JDK API docs are quoted from the JDK 21 sources'
  doc comments (`lib/src.zip`), which are what those pages render.
  *Effective Java* (3rd edition, "EJ" below), Guava, and Maven
  Central's rules are cited from memory, marked as such, by item number
  where it helps.
- Timings are from a shared, noisy machine: ranges are the fastest and
  slowest of 5 timed runs after 2 seconds of warm-up, over two
  processes.

## 1. Nullability

### Today

Nullable types are boxed and annotated with the runtime's own
`@temper.core.Nullable` (`TYPE_USE`, class retention), including inside
generics; non-null types carry nothing:

```java
public static @Nullable String maybe(boolean b)
public static @Nullable Integer maybeInt(boolean b)
public static int incOr(@Nullable Integer n)
public static List<@Nullable String> nullables()
public static String greet(String name, @Nullable String greeting)   // optional
public static String greet(String name)
```

Null-returning results are ordinary Java `null`s, and nullable
parameters take `null`. Non-null parameters aren't checked, so a `null`
either flows on or fails deep inside:

```text
greet(null)              => Hello, null
listLength(null)         => NullPointerException: Cannot invoke "java.util.List.size()" because "<parameter1>" is null
int i = maybeInt(false)  => NullPointerException: Cannot invoke "java.lang.Integer.intValue()" because the return value of "jvprobe.JvprobeGlobal.maybeInt(boolean)" is null
```

No `Optional` appears anywhere in the six libraries' APIs.

### What Java users expect

- **Null returns are normal**, with annotations. `Map.get` returns
  `null`; Guava's `Ints.tryParse` returns a `@CheckForNull Integer`
  (from memory). The JDK's own guidance limits `Optional` to returns:
  "`Optional` is primarily intended for use as a method return type
  where there is a clear need to represent "no result," and where using
  `null` is likely to cause errors" (`java.util.Optional`'s `@apiNote`).
  EJ item 55 ("return optionals judiciously") agrees, and warns against
  `Optional` parameters and `Optional<Integer>` (use `OptionalInt`).
  So Hrefine's `@Nullable Url Url.parse(String)` beside the throwing
  `parseUrl` is an ordinary Java shape, as is `@Nullable Integer
  getPortNumber()`.
- **Parameters are checked.** EJ item 49: check parameters for validity,
  usually `Objects.requireNonNull(x, "x")` at the top of public
  methods, so the failure names the argument and happens at the call.
- **Annotations tools understand.** IntelliJ, NullAway, Error Prone, and
  the Checker Framework read annotations by name, and the ecosystem has
  been converging on [JSpecify](https://jspecify.dev/) 1.0
  (`org.jspecify.annotations.Nullable` plus `@NullMarked` on a package,
  so unannotated types mean non-null). From memory: IntelliJ and
  NullAway accept any annotation whose simple name is `Nullable`, so
  `@temper.core.Nullable` probably works there; Kotlin doesn't.

### Kotlin

From memory, not checked here (no Kotlin compiler was available):
Kotlin reads nullability only from a fixed list of annotation packages
(JetBrains', Android's, JSR-305's `javax.annotation`, the Checker
Framework's, Eclipse's, Lombok's, RxJava's, and JSpecify's), so a
`@temper.core.Nullable String` is the platform type `String!`: Kotlin
code may treat it as non-null, and `Url.parse(x).href` compiles and
throws `NullPointerException` at run time. Every non-null type is a
platform type too. With JSpecify's `@NullMarked` on each package and its
`@Nullable` on nullable types, Kotlin 2 sees `Url?` and `String`
exactly, and reports misuse as errors.

### Options

| Option | Gains | Costs |
|---|---|---|
| A. Keep `@temper.core.Nullable` | Nothing to change | Kotlin sees platform types; Temper's name in every signature |
| B. JSpecify `@Nullable` and `@NullMarked` (a 3 KB annotations jar, Apache-2.0) | Kotlin, IntelliJ, NullAway, and Checker Framework all read it; non-null becomes explicit | A dependency in every library's POM; class-retention annotations still need the jar at compile time only |
| C. `Optional<T>` / `OptionalInt` for nullable returns | Unmissable at the call site | Breaking; allocation per call; `Optional` in fields and parameters is discouraged |
| D. `Objects.requireNonNull` on non-null reference parameters of public methods | Failures name the argument, at the call | A check per argument (negligible after JIT) |

Recommended: B and D, keeping `@temper.core.Nullable` beside JSpecify's
for a release if anything reads it. Not C.

## 2. Values

### `equals`, `hashCode`, and `toString`

**Today.** Across the six libraries' 180 public types:

| Method | Classes defining it |
|---|---|
| `toString()` (from Temper's `toString`) | 35 |
| `eq(Other)` (from `@auto("==")` or an `eq` method) | 15 |
| `equals(Object)` | 0 |
| `hashCode()` | 0 |
| `compareTo` / `Comparable` | 0 |

So equality is identity everywhere Java looks:

```text
new Point(3, 4)                       => (3.0, 4.0)            (has toString)
p.equals(new Point(3, 4))             => false
new Labeled("a", 2, "n")              => jvprobe.Labeled@60e53b93
JvprobeGlobal.check(2)                => jvprobe.Ok@355da254
Tag.red.eq(Tag.red)                   => true                   (@auto("=="))
new HashSet<>(List.of(boxed("s"), boxed("s"))).size()   => 2
```

`assertEquals(expected, actual)` in a user's JUnit test, `List.contains`,
`Map` keys, `distinct()` in a stream, and AssertJ's
`isEqualTo` all go through `equals`, so none of them sees Temper's `eq`.
A Temper method that happens to be named `equals` is worse: `public
equals(other: Hasher): Boolean` becomes `public boolean equals(Hasher
other)`, an overload beside `Object.equals`, the classic mistake EJ item
10 warns about, and the probe's `Hasher` also overrides `hashCode`, so
the two disagree.

**What Java users expect.** `Object.equals`'s contract and EJ items
10 to 12: value classes override `equals` and `hashCode` together, and
every class overrides `toString` with what a debugger or log should
show. Records (Java 16, [JEP 395]) generate all three from the
components: `record Point(double x, double y)` prints `Point[x=3.0,
y=4.0]`. Libraries without records use the same contract by hand, or
generate it (AutoValue, Immutables, Lombok's `@Value`, from memory).

**Options.**

- **`@auto("==")` classes:** generate `equals(Object)` and `hashCode()`
  from the same fields as `eq`, with `@Override`, keeping `eq` for
  compatibility. Additive, and what the Python study proposed for
  `__hash__`. A hand-written `eq` (Hrefine's `Url`, by `href`) gets
  `equals` delegating to it, but `hashCode` needs a Temper `hash` to
  stay consistent; until Temper has one, leave such classes on identity
  rather than risk breaking `HashMap`.
- **`toString`:** for classes without a Temper `toString`, a generated
  `Name[field=value, …]` over public constructor properties, as records
  print. Additive, but the format becomes something users parse, so it
  should be decided once for all backends (the JS and Python studies
  raise the same question).
- **`@Override`** on generated `toString` (and the new methods), so a
  later signature change is a compile error, not a silent overload.
- **A Temper method named `equals` or `hashCode`** should either be
  escaped or required to have Java's signature; today it produces the
  overload trap.

### Records

**Today.** A class is `public final class` with `public final` fields
*and* JavaBeans getters (`p.x` and `p.getX()`, `isUpperFirst()` for
Booleans), plus `setX` for `var`s. `notes/api-compat.md` keeps the
field-plus-getter pair deliberately.

A record would replace `getX()` with `x()`, drop the public fields, and
need a canonical constructor; Temper classes also have computed getters,
private state, constructor bodies, and `var`s. So records fit only
classes with exactly their constructor properties, no `var`, and no
other state, a rule that flips a class's whole API when a private field
is added. **Recommendation:** no records for now; get the behavior
(`equals`, `hashCode`, `toString`) without the shape. Revisit for a
`@value`-style Temper annotation if [#668](../../668-value-types/tom/claude-value-types.md)
brings one, with the shape decided once.

### Enum-like classes

Hrefine's `HostKind`, Ordable's `Casing`, and others are classes with
`public static final` instances in lowercase (`HostKind.domain`,
`Casing.ignored`). They compare with `==` (the tour says so) and print
their names, but a `switch` can't use them, there's no `values()`, and
`EnumSet` and `EnumMap` don't apply. Java users would expect `enum
HostKind { DOMAIN, IPV4, … }` (EJ item 34). Temper has no enum yet, so
this is for whatever Temper adds; a Java `enum` with lowercase
constants is legal if the names must match other backends.

### Immutability and aliasing

**Today.** Fields of non-`var` properties are `final`; Temper's `List`
results are unmodifiable (`fixedList().add("z")` and
`makeMap().put("z", 1)` throw `UnsupportedOperationException`, message
`null`), and `List.of` copies are used where elements are non-null.
Three holes:

- **Lists passed in are kept by reference.** `Window(List<Int>)`
  stores the caller's list:

  ```java
  List<Integer> xs = new ArrayList<>(List.of(1, 2, 3));
  Window w = new Window(xs);
  xs.set(0, 100);
  w.sum()                 // 105; w.items is [100, 2, 3]; w.getItems() == xs
  xs.clear();
  w.sum()                 // AssertionError: index 0 out of bounds for length 0
  ```

  EJ item 50 ("make defensive copies when needed") is about exactly
  this. The runtime already has `Core.listedToList`, which returns
  Temper-made unmodifiable lists as they are and copies anything else.
  Two refinements: it trusts any `Collections.unmodifiableList` view, so
  `listedToList(Collections.unmodifiableList(mine))` still changes when
  `mine` does (checked), and it copies `List.of` results, which are
  truly immutable (checked: `listedToList(List.of(1, 2)) != it`).
- **Builders the library holds leak.** A getter typed `Listed` or
  `ListBuilder` that returns a class's own builder hands out the
  `ArrayList` itself: `bag.getBuilder().add("sneaky")` changes
  `bag.getItems()`, and `holder.getLive().add(null)` puts a `null` into
  a `List<String>`. Java's signature says `List<String>`, so users can't
  tell a live builder from a snapshot.
- **Some public statics aren't `final`** (bug 3): Kelpto's
  `SanitizerPolicy.standard`, `github`, and `textOnly`, and
  `HtmlTokenizer.html`, are `public static` without `final`, because
  their initializers run in the module's static block:

  ```java
  SanitizerPolicy.standard = SanitizerPolicy.textOnly;      // compiles
  KelptoHtmlGlobal.sanitizeHtml("<b onclick=x>hi</b><script>evil()</script>").getHtml()
  // before: <b>hi</b>    after: hi
  SanitizerPolicy.standard = null;
  // NullPointerException: Cannot invoke "kelpto_html.SanitizerPolicy.allowsElement(String)" because "<parameter5>" is null
  ```

  Any code in the JVM can change what every caller's default sanitizer
  does. EJ item 15: public static fields should be final constants.

**Options.** Convert stored `List` parameters with `listedToList` at
public entry points (and make it recognize `List.of`'s classes but not
`unmodifiableList` views of unknown lists); return snapshots or
`Collections.unmodifiableList` views from getters that expose a held
builder; make every public static `final`, initializing it through a
private static method or holder class when its initializer needs the
module.

### Numbers and strings

`Int` is `int` and `Int64` is `long`, both wrapping as Java's do
(`addInts(Integer.MAX_VALUE, 1)` is `-2147483648`), which is exactly
what Java users expect; this is the one backend where Temper's integer
semantics are the host's own. Strings are `String`, and Temper's string
index is a UTF-16 offset, so positions line up with `substring`, and
code points are right (`firstCodePoint("😀x")` is 128512,
`codePoints("😀x")` is 2). A lone surrogate panics with `AssertionError:
panic` in `reverseOf`, the same divergence the Python study noted.

## 3. API shape

### Module functions: `…Global`

**Today.** Each module's top-level functions and values are statics of
`public final class <Last>Global` (`hrefine.HrefineGlobal.parseUrl`),
beside a `public final class <Last>Main` with a `main` that initializes
the module, which is also the jar's `Main-Class`. Tours use static
imports, so the class name appears only there:

```java
import static hrefine.HrefineGlobal.parseUrl;
import static ordable.OrdableGlobal.sortSmart;
```

**What Java users expect.** Utility classes named for what they hold:
the JDK's `Objects`, `Collections`, `Files`; Guava's `Lists`,
`Strings`, `Ints`; and libraries' own facade, `org.jsoup.Jsoup.parse(…)`
(from memory), which is exactly the `blah.Blah` shape the initial
thoughts propose. Nobody names a class `Global`, and a runnable `Main`
in a library jar is unexpected: `java -jar hrefine-0.0.1.jar` runs and
does nothing visible.

**Two clashes the rename must handle** (both checked today with
`Global`):

- **A user class named like the module class wins silently** (bug 2):
  a module `jvnames` with `export let jvnames(): Int { 1 }` and `export
  class JvnamesGlobal {}` writes one `JvnamesGlobal.java`, the class,
  and the function is gone from the output, with no error. With
  `blah.Blah`, `export class Jvnames` would do the same unless the ban
  in the initial thoughts' option 1 is enforced.
- **Members named like the getters:** a Temper method `getX()` on a
  class with a property `x` is `error: method getX() is already defined
  in class Getters` (bug 1).

**Recommendation:** option 1 of the initial thoughts (`hrefine.Hrefine`,
with a type named like its module made an error), plus: an error, not
an overwrite, whenever two generated Java names collide; and the
`…Main` class and `Main-Class` only for programs, not libraries (or
package-private).

### Packages

Packages are the library's name (`hrefine`), or snake_case for
hyphenated ones (`kelpto_core`, `kelpto_md`, `kelpto_html`). The JLS's
naming convention, and Maven Central's namespace rule (from memory),
expect a reverse domain (`dev.temperlang.hrefine`, or the publisher's).
`javaPackage` and `javaGroup` in the config already allow it; none of
the six sets them. Kelpto's packages would read better as subpackages
of one root (`kelpto.md`, `kelpto.html`), the same question the Python
and Lua studies raise about multi-library names.

### Constructors, factories, and builders

**Today.** Public constructors; optional parameters become telescoping
overloads taking boxed `@Nullable` types; classes with two or more
constructor parameters also get a `static final class Builder`:

```java
new Labeled("a")                                    // weight 1, note null
new Labeled("a", 2, "n")
new Labeled.Builder().label("b").note("n").build()  // weight 1
new Point.Builder().x(1).build()   // IllegalStateException: Missing required fields: y
```

That's EJ item 2's own form (`new NutritionFacts.Builder(240,
8).calories(100).build()`) and reads well. Gaps: required parameters
aren't the Builder's constructor arguments, so missing ones fail at
`build()` rather than at compile time; 113 of the 180 public types have
a `Builder`, including data classes where nobody would use one; and
keyword-named properties give `new_(…)` and `default_(…)` setters.
Static factories (EJ item 1) appear only where the Temper author wrote
them (`Color.parse`, `Url.parse`), which is right.

### Getters and names

`getX()`/`isX()` getters match JavaBeans, so Jackson, JSP-style
expression languages, and IDE templates all work, and the Hrefine tour
notes it relies on this ("username() and password() are methods, not
getters, … so Jackson leaves them out"). Name escaping:

- **Keywords** get `_`: `new_`, `default_`, `class_`; members and
  module functions named `to` and `with` become `to_()` and `with_()`,
  though those are only restricted words in `module-info.java`
  (`notes/api-compat.md` proposal 6 already says to stop).
- **`Object`'s final methods aren't escaped** (bug 1): a property named
  `class` makes `public String getClass()`, and methods named `wait` or
  `notify` make `public void wait()`; each is `error: getClass() in Cls
  cannot override getClass() in Object; overridden method is final`. A
  library with such a name can't be built for Java at all.

### Callbacks and interfaces

**Today.** Function types become `java.util.function` types with
primitive specializations (`IntUnaryOperator`, `ToIntFunction<String>`,
`DoubleUnaryOperator`), and `@fun` interfaces disappear into them, so
lambdas and method references just work:

```java
applyTwice(x -> x * 3, 2)                      // 18
scoreAll(List.of("ab", "c"), String::length)   // 3
describeShape(() -> 2.5)                       // "shape of area 2.5": Shape has one abstract method
totalArea(List.of(new Square(2), () -> 1.0))   // 5.0
```

Temper interfaces are Java interfaces with `default` methods, so Java
and Kotlin classes implement them directly, and single-method ones take
lambdas (they aren't marked `@FunctionalInterface`, which is
documentation only). Generated classes are `final` (EJ item 19's
"design for inheritance or else prohibit it"). This is the cleanest
interface story of any backend studied.

Two gaps: a `sealed interface` in Temper is a plain `interface` in Java,
so users can implement `Result` and break the library's exhaustive
`is` checks; Java 17's `sealed … permits Ok, Err` says exactly what
Temper means and lets Java 21's pattern `switch` check exhaustiveness.
And classes that a Java user would pass as standard interfaces don't
implement them: Ordable's `Order` has `int compare(String, String)` but
isn't a `Comparator<String>` (users write `order::compare`, and lose
`reversed()` and `thenComparing`), and no class is `Iterable` or
`Comparable`. A way for a library to say "this class is a host
`Comparator`" belongs to #676's naming mechanism; guessing from method
names is better left out.

### Generics and wildcards

Temper's `List<T>` is a read-only `java.util.List<T>` without
wildcards, so Java's invariance shows:

```text
totalArea(List<Square>)             error: incompatible types: List<Square> cannot be converted to List<Shape>
lengths(List<ArrayList<Integer>>)   error: incompatible types: List<ArrayList<Integer>> cannot be converted to List<List<Integer>>
listLength(Set.of("a"))             error: incompatible types: Collection<String> cannot be converted to List<String>
```

EJ item 31 ("use bounded wildcards to increase API flexibility",
producer-extends): a parameter the method only reads should be
`List<? extends Shape>`. Since Temper's `List` (unlike `ListBuilder`)
is read-only, `? extends` on `List` and `Map` value parameters is safe,
additive for callers, and changes nothing in Temper's own type rules,
which stay invariant by design. `Map` parameters accept any `Map`
(`TreeMap`, `HashMap`) already. Pairs going in are `List<Entry<String,
String>>`, so `Map.entry("q", "a b")` works, as Hrefine's tour shows,
but a `List<SimpleEntry<…>>` doesn't, for the same reason.

### Streams and iteration

Lists and maps are the JDK's, so `.stream()`, for-each, and collectors
work on every result, and generators are `Iterable`. No library class
is iterable itself; that waits on a Temper iteration protocol. No
varargs appear in APIs, which is fine now that `List.of(…)` is idiomatic.

## 4. Errors

### Today

| What happens | What the Java user sees |
|---|---|
| `positive(-1)` (bubbles), caught | `temper.core.Bubble`, `getMessage()` `null`, `getStackTrace().length` 0 |
| the same, uncaught | `Exception in thread "main" temper.core.Bubble`, and nothing else |
| `parseUrl("setup.html")`, `Color.parse("nope")`, `Dialect.postgres.quoteString("a\0b")` | `temper.core.Bubble`, no message |
| `parse64("x")` | `Bubble: For input string: "x"`, with the `NumberFormatException` as cause |
| `needsPositive(-1)` (`orelse panic()`) | `java.lang.AssertionError: panic`, cause `null` |
| `nth(List.of("a"), 5)` | `AssertionError: index 5 out of bounds for length 1` |
| `orPanic` with a callback throwing `IllegalStateException("host bug")` | `IllegalStateException: host bug`, passed through (right; JS's study found this swallowed) |
| `orPanic` with a callback throwing `new Bubble("bad input")` | `AssertionError: panic`, the message lost |
| `makeMap().put("z", 1)` | `UnsupportedOperationException`, message `null` |

`Bubble` is `RuntimeException` with `writableStackTrace` false (its
doc: "without a stack trace, which bubbles that are handled don't
need"). That makes failing calls cheap (section 7: 10,000 caught
bubbles in 0.05 ms, against 5 ms for an `IllegalArgumentException`),
and `orelse` catches only `Bubble`, so host exceptions pass through,
unlike JS. But it's the only failure a Java user sees from a library,
and when one escapes, nothing says where it came from; a user debugging
`Exception in thread "main" temper.core.Bubble` has no frame, no
message, and no library name. (#164's Java translation describes
today's failure as "a bare `RuntimeException` with a null message" and
says the backend "still supports Java 8"; both are now out of date.)

Panics are `AssertionError`s, thrown explicitly, so `-ea` doesn't
matter. As an `Error`, a panic passes `catch (Exception e)`, which is
what panics are for, kills the thread that runs it, and is captured by
an `ExecutorService`'s `Future`. One surprise: in a user's JUnit test, a
library panic is reported as a test *failure* (JUnit treats
`AssertionError` as an assertion that didn't hold), not as an error,
which reads as the user's assertion failing. The index panic also drops
the JDK's `IndexOutOfBoundsException` it caught.

### What Java users expect

From the JDK and EJ items 69 to 77 (from memory): unchecked exceptions
for programming errors and most library failures; standard types where
they fit (`IllegalArgumentException` for bad input, `IllegalStateException`,
`IndexOutOfBoundsException`, `UnsupportedOperationException`; EJ item
72); library-specific types where callers need to tell failures apart
(`java.time.format.DateTimeParseException` carries the text and an
error index; Jackson's `JsonProcessingException` carries a location);
a detail message that captures the failure (item 75); and exception
translation at the abstraction boundary (item 73). A stack trace is
assumed; stackless exceptions exist in the JDK only as internal,
preallocated signals.

### Options and ties to #164

- **Now, whatever #164 decides:** give bubbles messages where the
  runtime or library knows one (most runtime bubbles do: the key for
  `mappedGet`, the text for parses); `orelse panic()` panics with the
  bubble as cause (`new AssertionError("panic", bubble)`, Java 7+), so
  a callback's `Bubble("bad input")` isn't lost; the index panic keeps
  the JDK's exception as its cause.
- **Stack traces:** keep bubbles stackless *inside* the library, where
  `orelse` handles them, but give users a trace when one escapes. Without
  #164 that means either a stack for every bubble (measured cost: about
  0.5 µs per failure at this depth) or one only on request
  (`-Dtemper.bubbleStacks=true`, a debugging switch nobody will know
  about). With #164's library-named exceptions thrown at the public
  boundary, internal bubbles stay cheap and the thrown
  `HrefineException` has a normal stack.
- **#164's library-named types** fit Java well, as its translation
  shows (`WherewithException extends RuntimeException`, subclasses with
  fields and messages). This study adds: keep the `@Nullable` twin
  (`Url.parse` beside `parseUrl`, like `Ints.tryParse` beside
  `Integer.parseInt`); list the unchecked types in `throws` clauses and
  `@throws` (EJ item 74), so IDEs show them; and leave panics as
  unnamed `Error`s, since users shouldn't catch them.

## 5. Packaging

### What `temper build` writes

The library POM, abridged (Hrefine; the others differ only by name):

```xml
<groupId>hrefine</groupId>
<artifactId>hrefine</artifactId>
<version>0.0.1</version>
<name>hrefine</name>
<description>hrefine</description>
<licenses><license><name>Apache-2.0 OR MIT</name></license></licenses>
<dependency>dev.temperlang:temper-core:0.7.0-alpha.0.267 (compile)</dependency>
<dependency>dev.temperlang:temper-std:0.7.0-alpha.0.267 (test)</dependency>
<dependency>org.junit.jupiter:junit-jupiter:5.9.2 (test)</dependency>
plugins: central-publishing 0.8.0 (autoPublish), source, javadoc (failOnError false,
  doclint -missing), gpg (in verify), compiler (release 17), jar (Main-Class
  hrefine.HrefineMain), exec, surefire
```

and the runtime's POM targets Java 8 (`source`/`target` 8, plus
`maven-toolchains-plugin` requiring a JDK 8 toolchain), with full
Central metadata (`url`, `developers`, `scm`).

### Building it with stock Maven

From `temper.out/java`, offline, in order:

| Step | Result |
|---|---|
| `mvn package` in `temper-core` | `No toolchain matched from 2 found for type jdk` … `jdk [ version='8' ]`: needs a `toolchains.xml` declaring version `8` exactly; one declaring `1.8` (the usual spelling, and what this machine had) doesn't match |
| with a toolchain declaring `8`, `mvn install` | `Cannot run program "gpg"`: signing runs in `verify` for every build |
| with `-Dgpg.skip` | builds; javadoc prints 100 warnings (javadoc's cap) for the runtime |
| `std`, then `hrefine`, with both flags | builds: `hrefine-0.0.1.jar` (104 KB), `-sources` (62 KB), `-javadoc` (161 KB) |

So a Java user who receives `temper.out` and types `mvn install` fails
twice before anything compiles. Release-only steps (toolchains, gpg,
Central's plugin with `autoPublish`) belong in a `release` profile
(the usual Maven layout; Central's own guide puts signing there, from
memory).

### Maven Central readiness

Central's requirements, from memory (the page wasn't reachable):
`groupId` in a namespace the publisher has verified (a reverse domain
or `io.github.<user>`), `name`, `description`, `url`, `licenses`,
`developers`, and `scm`, sources and Javadoc jars, GPG signatures, and
checksums. Against the six libraries' POMs:

| Requirement | Library POMs today |
|---|---|
| verified `groupId` | `hrefine`, `argmas`, … (bare names; `javaGroup` unset) |
| `description` | the library's name repeated, though every config has a prose summary |
| `url`, `developers`, `scm` | missing (written only if the config sets `homepage`, `authors`, or `repository`; none does) |
| `licenses` | one entry named `Apache-2.0 OR MIT`, no URL; the usual form is two `<license>` entries with URLs |
| sources and Javadoc jars | yes |
| signing | yes, but the gpg plugin's configuration is `<id>${gpg.keyname}</id>` twice, which isn't a parameter the plugin has; the runtime's POM uses `keyname` and `passphraseServerId` (bug 6) |

The runtime and std (`dev.temperlang`) are fine; libraries need a
`groupId` the author owns and the config's prose as description.

### Java versions and dependencies

Libraries compile with `--release 17`, as `docs/backends/README.md`
says, and use `List.of`; checked, three of them also compile with
`--release 11`, and none with `--release 8` (72 to 100 `cannot find
symbol` errors each). Only the runtime targets 8, a leftover from Kotlin
Temper; moving it to the libraries' level drops the toolchain
requirement, the first build failure above, at no cost to anyone who
can use the libraries.

Runtime and std versions are exact pins. Maven resolves conflicts
nearest-wins (Gradle, highest-wins), so two libraries built by different
Temper versions quietly share one runtime, with whatever binary
incompatibility lies between them. A runtime API kept stable within a
minor version, and libraries declaring the lowest compatible version,
is the usual answer; shading the runtime into each jar would duplicate
classes instead.

### JPMS

No `module-info.class` and no `Automatic-Module-Name`; the jars become
automatic modules named from their file names (`hrefine`,
`temper.core`, `temper.std`), and a modular user program with `requires
hrefine;` compiled and ran (checked). The derived names depend on the
jar's file name, which build tools may change. Adding
`Automatic-Module-Name` to each manifest is a one-line, non-breaking
step; a real `module-info` (exporting the library's packages, `requires
transitive temper.core`) can follow once packages are settled, since
hyphenated libraries' `kelpto_core` names would then be frozen.

## 6. Javadoc

**Today.** No doc comments are emitted: Temper's `/** … */` comments
and the libraries' literate prose are both dropped (`/** A labeled
thing, with optional parts. */` on the probe's class gives a bare
`public final class Labeled`). javadoc over each library's own sources
(JDK 21, runtime and std on the source path):

| Library | Files | `-Xdoclint:all` warnings | errors | with `-missing` |
|---|---|---|---|---|
| Argmas | 49 | 455 (443 "no comment") | 0 | 0 |
| Chromarite | 9 | 76 | 0 | 0 |
| Hrefine | 18 | 172 | 0 | 0 |
| Kelpto (four libraries) | 138 | 1,015 (989 "no comment") | 0 | 0 |
| Ordable | 5 | 39 | 0 | 0 |
| Wherewith | 76 | 167 | 0 | 0 |

The remaining warnings are "use of default constructor, which does not
provide a comment" (40 in all). The generated POM hides all of this
with `doclint -missing` and `failOnError false`, so the published
`-javadoc.jar` is signatures only. IDE hovers show the same. EJ item 56:
document every exported API element.

**Option.** Emit each declaration's doc as Javadoc, with `@param` from
Temper's parameter docs and `{@code n}` for Temper's `[n]` references,
and a `package-info.java` from the library's summary. The output already
passes doclint apart from missing comments, so emitting comments turns
this table's left column toward zero without new errors.

## 7. Speed, size, and startup

Generated code against idiomatic hand-written Java, ms (JDK 21):

| Case | Generated | Hand-written |
|---|---|---|
| Sum 1M floats in a `List<Double>` | 2.0–2.4 | 1.9–2.3 (indexed loop) |
| Sum 1M ints through a callback | 1.7–2.0 | 1.7–2.2 (`stream().mapToInt(f).sum()`) |
| 1M calls through `orelse`, none failing | 0.21–0.23 | — |
| 10,000 failing calls, caught | 0.05–0.06 (stackless `Bubble`) | 4.7–5.1 (`IllegalArgumentException`) |
| Parse 20,000 URLs | 34–59 (Hrefine `Url.parse`) | 11–13 (`new URI(u).normalize()`) |

The JIT erases the translation's overhead: `Core.listGet` (a `try`
around `List.get`) and the boxed `List<Double>` cost the same as
hand-written code over the same boxed list. The URL row compares unlike
work (`URI` follows RFC 3986 and does no WHATWG normalization or IDNA),
so it only shows scale. Of the backends studied so far, Java's
output costs least relative to the host.

**Size.** Jars as `javac` builds them: runtime 39 KB (45 KB from
Maven), std 68 KB; Ordable 35 KB, Chromarite 40 KB, Hrefine 92 KB,
Argmas 103 KB, Wherewith 181 KB, and Kelpto's four 6 KB (facade), 44 KB
(core), 117 KB (HTML), and 174 KB (Markdown).

**Startup.** `java Hello` takes 26–28 ms here; the tours run in 89–146
ms, nearly all class loading. The first `Url.parse` takes 17–18 ms
(Hrefine's module statics initializing), the first
`Color.parse` 4 ms. Fine for servers; noticeable for Argmas's command
line tools, where lazy tables would help as in the JS study.

### javac on map literals

A map literal compiles to one expression:

```java
commonWords = Core.mapConstructor(List.of(new SimpleImmutableEntry<>("all", tokenKeyword),
    new SimpleImmutableEntry<>("and", tokenKeyword), … /* 75 entries */));
```

with a diamond in every entry inside a generic varargs call inside a
generic call, so javac solves one inference problem over every entry at
once. Its time grows steeply with the entry count (one class holding
only the literal, `int` values, seconds):

| Entries | JDK 17.0.7 | JDK 21.0.4 |
|---|---|---|
| 40 | 1.4 | 1.5 |
| 60 | 3.7 | 4.0 |
| 77 | 8.5 | 8.5–8.9 |
| 100 | 22.4 | 21.9 |
| 150 (`String` values) | — | 106–118 |
| 77, explicit `<String, Integer>` on each entry | 0.5 | 0.5 |
| 77, one `put` per entry | 0.5 | 0.5 |

Wherewith's own 75-entry `commonWords` is most of its 11-second
compile. A CI run on a newer JDK 21 update failed once on this line
with `inference variable K has incompatible bounds`, while the same
file compiled in the same run's other step. That failure didn't
reproduce here: clean with JDK 17.0.7 and 21.0.4, under plain `javac`
with `-Xlint:all`, under Gradle 9.0.0 (on both JDKs, its `-nowarn`
and encoding flags as the demos set them), with 64 MB to 1.5 GB heaps,
and with 256 and 512 KB thread stacks. Whatever the trigger, explicit type
arguments make the problem trivial for javac (17 times faster at 77
entries) and remove the inference that failed (bug 5).

## Cross-backend patterns, checked for Java

The five cases from the JS study (`b` a builder changed by the callback
walking it):

| Case | Java | JS (Node 24) | Python | Lua 5.4 | C++ |
|---|---|---|---|---|---|
| `reduceFrom` that grows `b` | 1299 (live) | 12 | 1299 | 12 | heap-use-after-free |
| `map` that shrinks `b`, length | `ConcurrentModificationException` | 3 | 2 | 2 | 3, reading past the end |
| `forEach` on a map, adding keys | **1**: stops after the first key, silently | 30 | `RuntimeError` | 30 | stops early by luck |
| `forEach` on a map, removing a later key | `ConcurrentModificationException` | 3 | `RuntimeError` | 3 | `std::out_of_range` |
| `sort` whose comparison grows `b` | `ConcurrentModificationException` | 7 | `ValueError` | 8 | heap-use-after-free |

Java is memory safe and mostly fails loudly with the JDK's own
exception, which, being neither a `Bubble` nor an `AssertionError`,
passes `orelse` and `Test.assertPanics` alike. The map-adding case is
the worst: `LinkedHashMap`'s iterator had already found no next entry
before the callback added one, so the walk ends after one key and
reports nothing. Whatever contract Temper settles on (live length, or
a panic), Java's runtime can meet it by checking `modCount`-style
changes itself, as its collections already half do.

| Pattern (from the earlier studies) | Java today |
|---|---|
| Failures without a message | Same, and without a stack trace (section 4) |
| `orelse panic()` swallowing host errors (JS) | No: only `Bubble` is caught |
| Runtime names in user code | None in the six tours; `temper.core.Bubble` to catch precisely; `@temper.core.Nullable` in signatures |
| Lists passed in kept by reference | Yes (section 2) |
| Returned lists aliasing library state | Only builders returned as `Listed`; `List` results are unmodifiable |
| Exact runtime pins | Same; Maven's nearest-wins hides the conflict |
| Docs dropped | Same |
| Values without equality, hashing, or a debug form | `eq` on 15 classes; `equals`/`hashCode` on none; `toString` on 35 |
| Names clashing with host members | Yes: `getClass`, `wait`, `notify`, and `getX` beside `x` don't compile |

## Recommendations

**Quick wins** (not breaking):

1. Escape or reject member names that clash with `Object`'s final
   methods (`getClass`, `wait`, `notify`, `notifyAll`) and with
   generated getters; report any two generated Java names that collide
   (`<Lib>Global`, `<Lib>Main`, getters) as an error rather than
   overwriting a file.
2. Make every public static `final` (initialize through a private
   static method or holder class), so Kelpto's sanitizer policies can't
   be reassigned.
3. Explicit type arguments in map literals
   (`new SimpleImmutableEntry<String, Integer>(…)`), or one `put` per
   entry for long ones.
4. `equals(Object)` and `hashCode()` for `@auto("==")` classes, from
   `eq`'s fields; `@Override` on `toString` and these.
5. Failures: messages on runtime bubbles; `orelse panic()` and the
   index panic keep their cause.
6. Maven: toolchains, gpg, and Central's plugin in a `release` profile;
   the runtime at Java 11 or 17 like libraries, without a toolchain;
   fix the gpg plugin's duplicated `<id>`; `description` from the
   config's prose; two license entries with URLs; `Automatic-Module-Name`
   in each manifest; no `Main-Class` for libraries.
7. Javadoc from Temper's doc comments and literate prose, and a
   `package-info.java`; then turn on doclint's missing-comment check for
   libraries that are fully documented.
8. `Objects.requireNonNull` on non-null reference parameters of public
   methods and constructors.
9. `listedToList` recognizes `List.of`'s classes, and stops trusting
   `unmodifiableList` views it didn't make.

**Medium changes:**

10. JSpecify's `@Nullable` and `@NullMarked`, so Kotlin sees `T?` and
    `T` instead of platform types (a new dependency; keep
    `@temper.core.Nullable` beside it for a release).
11. Copy stored `List` parameters at public entry points
    (`listedToList`), and return snapshots or unmodifiable views from
    getters that expose a held builder.
12. `? extends T` for read-only `List` and `Map` parameters, and on
    `Entry` in `List<Entry<K, V>>`.
13. `sealed … permits` for Temper's sealed interfaces.
14. Generated `toString` for classes without one, in a format decided
    across backends.
15. Bubbles that escape get a stack trace (or wait for #164's boundary
    types); bubbles handled inside stay stackless.
16. Lazy module tables, for command-line startup.

**Design questions for #676 and #164:**

17. **Module class name** *(breaking)*: `hrefine.Hrefine` with the
    initial thoughts' option 1 (a type named like its module is an
    error), checked against every generated name.
18. **Packages and coordinates** *(breaking)*: a reverse-domain default
    or required `javaPackage`/`javaGroup` before publishing; one root
    package with subpackages for multi-library projects
    (`kelpto.md`).
19. **Library-named failure types** *(breaking for `catch (Bubble …)`)*:
    #164's `WherewithException extends RuntimeException`, in `throws`
    clauses and `@throws`, with messages and stacks; the `@Nullable` twin
    kept.
20. **Panics as `AssertionError`:** keep (catch-proof, but reported by
    JUnit as assertion failures) or a dedicated `Error` subclass.
21. **Records, enums, and host interfaces:** whether Temper value
    classes (#668) become records, Temper enums become Java `enum`s, and
    how a library declares that a class implements `Comparator`,
    `Iterable`, or `Comparable` on Java; all API-shaping, so decided
    once.
22. **Keyword escapes** *(breaking)*: drop the `_` on `to` and `with`
    (api-compat proposal 6), and decide `new_`/`default_` builder
    setters.
23. **Callback mutation:** which result Temper promises when a
    collection changes during its own callback; Java needs a check only
    for map iteration to stop failing silently.
24. **Runtime versions:** exact pins or ranges, given Maven's
    nearest-wins resolution.

## Bugs found

On Temper `13dc5669` (`temper 0.7.0-alpha.0.267`), JDK 21.0.4 unless
noted. Each repro is the whole Temper module, in a library with a
`config.temper.md` naming it.

1. **Host member names produce uncompilable Java:**
   `export class Cls(public class: String) {}` gives `public String
   getClass()`: `error: getClass() in Cls cannot override getClass() in
   Object; overridden method is final`. `export class Waiter { public
   wait(): Void {} public notify(): Int { 1 } }` gives the same for
   `wait()` and `notify()`. `export class Getters(public x: Int) {
   public getX(): Int { x + 1 } }` gives `error: method getX() is
   already defined in class Getters`.
2. **A class named like the module class silently replaces it:** module
   `jvnames` with `export let jvnames(): Int { 1 }` and `export class
   JvnamesGlobal {}` builds without error, and the output's
   `JvnamesGlobal.java` holds only the class; `jvnames()` is gone.
3. **Public statics initialized from module state aren't `final`:**
   `let suffix = "!"; export class Policy { public name: String;
   private constructor(name: String) { this.name = name; } public
   static strict: Policy = Policy.named("strict"); private static
   named(n: String): Policy { new Policy("${n}${suffix}") } }` gives
   `public static Policy strict;`, assignable by users. In Kelpto,
   `SanitizerPolicy.standard = SanitizerPolicy.textOnly` changes what
   `sanitizeHtml(text)` keeps, and `= null` makes it throw
   `NullPointerException`.
4. **Escaping bubbles have no stack trace or message:** with `export
   let positive(n: Int): Int throws Bubble { if (n <= 0) { bubble() }
   n }`, calling `positive(-1)` from `main` prints only `Exception in
   thread "main" temper.core.Bubble` (`Bubble` is built with
   `writableStackTrace` false). Hrefine's `parseUrl("setup.html")` and
   Chromarite's `Color.parse("nope")` print the same.
5. **javac's time on map literals grows steeply:** a static map literal
   of `n` entries, emitted as `Core.mapConstructor(List.of(new
   SimpleImmutableEntry<>(…), …))`, takes 1.4 s to compile at 40
   entries, 8.5 s at 77, 22 s at 100, and 106–118 s at 150, on JDK 17
   and 21; 0.5 s with explicit type arguments. A CI run's
   `inference variable K has incompatible bounds` on Wherewith's
   75-entry literal didn't reproduce here.
6. **The library POM's gpg configuration is malformed:** every library
   POM has `<configuration><id>${gpg.keyname}</id><id>${gpg.keyname}</id></configuration>`
   for `maven-gpg-plugin`, which has no `id` parameter; the runtime's POM
   uses `<keyname>` and `<passphraseServerId>`.
7. **Stock Maven can't build `temper.out/java`:** `mvn install` in
   `temper-core` fails with `No toolchain matched … jdk [ version='8' ]`
   unless `toolchains.xml` declares version `8` (not `1.8`), then with
   `Cannot run program "gpg"` unless `-Dgpg.skip`.
8. **Map iteration that adds keys stops silently:** the `forEach` case
   in the cross-backend table returns 1 (30 in JS and Lua).
9. **Panics drop what they replace:** `f(s) orelse panic()` with a
   callback throwing `new Bubble("bad input")` gives `AssertionError:
   panic`, cause `null`; the index panic drops the JDK's
   `IndexOutOfBoundsException`.
10. **Stored lists alias the caller's** (`Window`, section 2), and
    `Core.listedToList` keeps any `Collections.unmodifiableList` view.
11. **Doc comments dropped:** `/** A labeled thing, with optional
    parts. */ export class Labeled(…)` produces no Javadoc.
12. **A Temper `equals` overloads instead of overriding:** `export class
    Hasher(public n: Int) { public hashCode(): Int { n } public
    equals(other: Hasher): Boolean { n == other.n } }` gives
    `equals(Hasher)` beside `Object.equals`, with `hashCode()`
    overriding `Object`'s.

[JEP 395]: https://openjdk.org/jeps/395
