# Temper libraries from a C++ user's point of view

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

## The question

Does a Temper library look and behave like a C++ library to someone who
writes C++, and what would make it more so? And since the C++ backend
has a long list of open items, which of them belong together, and which
need an RFC?

**Short answer:** generated C++ compiles cleanly on g++ 12 to 14 from
C++14 to C++23, is warning-free under strict flags, and calls read
plainly: `Color::parse("red")->toCss()`, lambdas for callbacks, and
`std::vector` behind every list. But the translation doesn't try to
make anything immutable or to hide anything. Every field is a public
data member, private ones included; every module value and static is
a public, writable slot; private constructors are public `make`s; and
lists the library keeps are the caller's to change. The headers declare
115 internal classes beside the public ones (52 of Wherewith's 72), and
name `temper::core` 1,872 times. A failure is a `TemperBubble` whose
message is "bubble", a panic ends the process (losing buffered output),
and nothing builds under `-fno-exceptions`. Five runtime functions read
freed or out-of-range memory when a callback changes the list being
walked. The generated CMake builds, but installs and exports nothing,
and building a library with it also builds its tests and a demo `main`.
Most of the immutability and visibility work, and the error model, is
breaking, which makes them the core of a C++ backend revamp RFC; the
memory-safety fixes and most packaging fixes can land now.

## How this was studied

- Built the six showcase libraries (Argmas, Chromarite, Hrefine,
  Kelpto, Ordable, and Wherewith) with Temper's compiler (`temper build
  -b cpp`, temperlang/temper at `13dc5669`), and compiled them with
  g++ 12, 13, and 14 at `-std=c++14` through `-std=c++23`. No clang++ or
  MSVC was available here; CI covers both (below).
- Wrote a probe library (about 120 lines of Temper: immutable and
  mutable classes, a private field, a private constructor, a static, a
  module list, an interface with a default method, a fun interface, a
  generic class, nullables, defaults, bubbles, panics, and builders
  changed during callbacks), and small C++ programs that use it and the
  libraries as a C++ user would, through the generated CMake
  (`add_subdirectory`, as Argmas's tour does). Every snippet below was
  compiled and run, and output is quoted as printed.
- Read each library's C++ tour, the C++ backend
  (`crates/temper-be-cpp`), its runtime
  (`crates/temper-be-cpp/runtime/temper-core`),
  `docs/internals/detail/06-backends.md` (C++'s warning policy), and
  `notes/api-compat.md`, whose C++ section and items 2 and 9 already
  touch some of this. Chromarite's `demos/immutable` checks the same
  question from every language and was the starting point.
- Conventions come from the
  [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)
  (titles quoted from the live page) and from well-known libraries:
  {fmt}, nlohmann/json, and Abseil. Of their sites only fmt.dev
  responded; cppreference, cmake.org, abseil.io, and the nlohmann/json
  docs were unreachable from here, so what those libraries and CMake do
  is from their long-stable, documented behavior, worth checking at the
  source before quoting further.
- Counts are by script over the headers with their `#ifdef
  TEMPER_TESTS` parts removed. Private fields are matched by name
  against the Temper source, so those counts are approximate (a name
  private in one class counts wherever it appears).

## 1. Immutability

### Today

A Temper class becomes a `struct` used through `std::shared_ptr`. All of
it is public: fields as data members (beside `get_x()` accessors),
statics in a nested `temper_statics` struct, and module values in a
`temper_globals` namespace. The probe's `Point` has no `var` fields, so
it's immutable in Temper:

```cpp
struct Point : public std::enable_shared_from_this<Point> {
  struct temper_statics {
    static temper::core::GlobalSlot<std::shared_ptr<Point>> origin;
  };
  double x;
  double y;
  static std::shared_ptr<Point> const & origin();
  static std::shared_ptr<Point> make(double x, double y);
  double get_x() const;
  // get_y, get_length, and scaled, all const
};
```

What a C++ user can change, all compiled without a warning, with what
the library then reports:

```cpp
auto p = cprobe::Point::make(3, 4);
p->x = 30;                               // immutable class: p->get_length() is 30.2655
cprobe::Point::origin()->x = 1;          // the static's object: origin.x is 1
auto c = cprobe::Counter::make();
c->secret = -100;                        // `private var secret`: c->get_peek() is -100
auto t = cprobe::Ticket::make(999);      // `private constructor`: ticket 999
cprobe::fixedList()->at(0) = "changed";  // module's `let fixed`: fixedFirst() is "changed"
```

Accessors return `std::shared_ptr<T> const &`, so `Space::srgb() =
Space::oklch()` is refused, but the slot behind it isn't, and nor is a
module's shared data:

```cpp
chromarite::Space::temper_statics::srgb.value = chromarite::Space::oklch();
std::cout << chromarite::Space::srgb()->get_name();        // oklch
auto& messages = argmas::englishMessages();                 // a Map, const &
messages->data[messages->order.at(0)] = "hijacked";        // every Command's help
```

Lists passed in stay shared with the caller, so a value the library
computed from one goes stale. The probe's `Window` takes a
`List<Int>` and stores its length:

```cpp
auto items = std::make_shared<std::vector<int32_t>>(std::vector<int32_t>{1, 2, 3});
auto w = cprobe::Window::make(items);
items->push_back(100);      // w->sum() is still 6; w->get_items() has 4
w->count = 4;               // w->sum() is now 106
items->clear();             // w->last(): "index 3 out of bounds for length 0", abort
```

Chromarite builds its colors the same way (`Color::fromList` keeps the
caller's vector inside its `Matrix`), and its `demos/immutable` records
C++ as changing four of six attempts: `color-field`, `space-field`,
`channel-list`, and `alpha-list`. Elsewhere, only Lua (all seven), Python
(statics), and JS (`defineProperty`) let changes through.

Counted across the eight generated libraries (Kelpto's three and the
other five):

| Library | Structs | Data members | of them private in Temper, or on internal types | Public writable slots (statics and module values) | Non-`const` member functions |
|---|---|---|---|---|---|
| Argmas | 47 | 131 | about 70 | 39 | 92 |
| Chromarite | 7 | 22 | about 15 | 19 | 22 |
| Hrefine | 16 | 87 | about 64 | 19 | 45 |
| kelpto-core | 12 | 33 | about 12 | 1 | 10 |
| kelpto-html | 40 | 172 | about 119 | 47 | 134 |
| kelpto-md | 70 | 224 | about 191 | 83 | 132 |
| Ordable | 3 | 12 | about 7 | 4 | 8 |
| Wherewith | 72 | 253 | about 239 | 11 | 292 |
| **Total** | **267** | **934** | **about 717** | **223** | **735** |

Every one of the 934 data members is writable, and so is each of the 223
slots. `const` on member functions follows what the body does with
`this`, not the type's mutability: a method that hands `this` on as a
`shared_ptr` (`return self;` in `Color::toSpace`) isn't `const`, so 22 of
Chromarite's methods aren't, though nothing in Chromarite changes after
construction. And a `var` field's getter isn't `const` either
(`int32_t get_count();`). So a `std::shared_ptr<Color const>` can't
call `toSpace`, `lighten`, or `toCss`.

### What C++ users expect

The Core Guidelines are direct: "Con.1: By default, make objects
immutable", "Con.2: By default, make member functions `const`",
"Con.4: Use `const` to define objects with values that do not change
after construction", "C.2: Use `class` if the class has an invariant;
use `struct` if the data members can vary independently", "C.8: Use
`class` rather than `struct` if any member is non-public", and "C.9:
Minimize exposure of members" ("Minimize the chance of unintended
access"). A C++ user reads `struct` with public members as plain data
anyone may set, so today's headers say "change me", the opposite of
what the Temper source says.

Value types (`std::string`, `std::chrono::duration`) get immutability
from copying; shared objects get it from `const`: a
`std::shared_ptr<T const>`, or a class whose state is private with only
`const` accessors. A list returned for reading is a `const&` or a span,
never a writable shared vector.

### Options

| Option | Gains | Costs |
|---|---|---|
| A. Keep public members; document "don't write fields" | No change | Contradicts every C++ convention; the library's invariants are the user's to keep |
| B. Private data, `const` getters (already generated), `class` keyword | Fields can't be written; names unchanged for getter users | Breaking for code reading `p->x` (they'd write `p->get_x()`); needs `friend` or accessors for the library's own cross-class access (below) |
| C. B plus `const` on every method of a class without `var` fields, and `shared_ptr<T const>` for immutable classes in signatures | The type says it's immutable, as Con.1 asks | `this` escaping needs `shared_ptr<T const>` too, so the runtime's `borrow_this` and generated `self` change; casts between `T` and `T const` pointers in generic code |
| D. Lists as `shared_ptr<std::vector<T> const>` for `List`, plain `shared_ptr<std::vector<T>>` only for `ListBuilder` | Returned lists can't be written; `List` and `ListBuilder` finally differ in C++ | Breaking in every signature; a caller can still pass its own writable vector and keep it, since `T` converts to `T const` |
| E. Copy a `List` argument the library stores (constructors and setters only) | No aliasing of the caller's vector, as `Window` shows | A copy per stored list, even when the caller never changes it |
| F. Statics and module values: private slots, accessors only | Nothing outside the init writes them | Template bodies in headers read slots directly today, so they need an accessor or an internal header (section 2) |

Whatever hides the fields should keep a way for the library's own
code to copy an object and set a few fields: object spread
([#694](https://github.com/temperlang/temper/issues/694)) can then
translate `{ ...old, size: 3 }` on a class whose constructor only stores
its parameters as a copy plus one assignment, rather than a call naming
every field. With B, that's a private copy constructor and field writes
reached through the same `friend` or passkey the library already needs
for cross-class access; const fields would rule it out, which is one
more reason for B's private data over `const` members.

**Recommendation:** B, C, D, and F together, in the revamp RFC
(they're breaking, and changing signatures once is better than four
times). E is a judgment call: Temper's own docs say a `Listed` argument
"shouldn't be modified concurrently, although it might be modified
after the end of the call, so receivers *shouldn't* keep any references
to a `Listed` parameter" unless they account for changes
(`lib/core/core.temper`), yet Chromarite keeps one, as most libraries
would. Copying only where a constructor or setter stores a `List`
argument is cheap next to building the object, and makes stored lists
safe in every backend that shares them (C++, Lua); it's a cross-backend
decision rather than a C++ one.

Cross-class access inside a library (one class reading another's
private field, which Temper allows within a module) can use generated
accessors in a `detail` namespace or `friend` declarations. Per #676's
principle 2, these shouldn't show in the documented API.

Is immutability a promise across backends, or best effort? Chromarite's
demo treats it as a promise, and Java, C#, and Rust keep it. C++ can
keep it within the language's rules (a determined user can always
`const_cast`), which is what C++ users mean by immutable.

## 2. Hiding internals

### Today

Each library has one header per module, `<lib>/init.hpp` for the root,
which includes `<temper-core/core.hpp>` and declares, in one namespace
per library:

| Library | Structs | of them non-exported Temper classes | `temper::core` mentions | Distinct `temper::core` names |
|---|---|---|---|---|
| Argmas | 47 | 18 | 671 | 11 |
| Chromarite | 7 | 4 | 33 | 2 |
| Hrefine | 16 | 4 | 198 | 4 |
| kelpto-core | 12 | 1 | 36 | 5 |
| kelpto-html | 40 | 8 | 301 | 5 |
| kelpto-md | 70 | 27 | 317 | 5 |
| Ordable | 3 | 1 | 39 | 4 |
| Wherewith | 72 | 52 | 277 | 4 |
| **Total** | **267** | **115** | **1,872** | |

- **Internal classes.** Wherewith's SQL lexer, parser, AST, and
  printers (`SqlLexer`, `CommonParser`, `SelectStatement`, `BinaryExpr`,
  and 48 more) sit in `wherewith/init.hpp` beside its 20 exported
  types; Chromarite's `Matrix`, `Blend`, `CssToken`, and `CssArgs`
  likewise. All can be made and used:
  `chromarite::Matrix::make(2, values)` compiles.
- **Private constructors** are public `static make(...)`s:
  `chromarite::Space::make("mine", 3, nullptr)` makes a space the
  Temper source says can't exist ("conversions are defined for exactly
  the spaces below").
- **Template bodies** (Argmas's 40 templates, Ordable's 2) are in the
  header, so it shows the library's implementation and the runtime's
  internals: Argmas's header uses `temper::core::panic`, `to_base`,
  `ListBuilder`, `Int`, and `TemperBubble`.
- **Runtime types in signatures:** `temper::core::Str` everywhere,
  `NullableParam<T>` (144 times in Argmas), and every `Map` as
  `std::shared_ptr<temper::core::Mapped::Ordered<K, V>>`, a struct with
  public `order` and `data` members that users iterate directly.
- **Storage:** `temper_statics` and `temper_globals` (section 1), plus
  `void global_init_init()`, with a comment telling users it's
  optional.
- **The runtime itself** is 30 headers that every user translation unit
  includes in full: `core.hpp` pulls in `<regex>`, `<thread>`,
  `<fstream>`, `<iostream>`, `<map>`, and `<deque>`, about 100,000
  preprocessed lines and 2.8 s (Ordable) to 4.5 s (Wherewith) for an
  empty `main` that includes one library header, at `-O0`.
- **Fun interfaces** are emitted as an abstract `struct Scorer` with
  `apply`, while parameters take `std::function<int32_t(Str)>`, so the
  struct is never used.

### What C++ users expect

Public headers declare the API; implementation goes in `.cpp` files, in
`private:` sections, or in a namespace marked as internal by name:
{fmt}'s `fmt::detail`, nlohmann/json's `nlohmann::detail`, and Abseil's
`absl::<thing>_internal` namespaces, which Abseil's compatibility
guidelines tell users not to depend on. Header-only libraries can't
avoid showing internals, so the naming convention is the contract.
Helpers used only in one `.cpp` get internal linkage (an unnamed
namespace or `static`), so they can't clash with or be called from
other translation units. And headers include what their declarations
need, not the whole runtime.

### Options

| Option | Gains | Costs |
|---|---|---|
| A. `private:` for private fields, private constructors as private `make` (with a passkey for `make_shared`) | Enforced by the compiler; the cheapest real fix | Classes that read each other's privates need `friend`s; tests (`TEMPER_TESTS`) need access too |
| B. Non-exported classes and functions into `<lib>::detail` | The usual convention; no build changes | Still visible, still in every user TU's parse; only a name says "internal" |
| C. Non-exported code not needed by any header into the `.cpp`, in an unnamed namespace | Truly hidden; smaller headers, faster user builds; no symbol clashes between libraries | Templates and inline bodies in headers that use it force it back to B; the translator must compute what headers need (it already decides what's in headers, for templates) |
| D. A private header per module (`<lib>/detail/init.hpp`) for what templates need, the public header only for exports | Users include only the API | Two headers per module; the private one still ships, since public templates include it |
| E. Pimpl for exported classes | ABI stability; hidden fields | A second allocation and indirection per object, on top of `shared_ptr`'s; little gain for generated code that's rebuilt from source anyway |
| F. Runtime: split `core.hpp`, include only what's used; regex, net, promises, and dates only where a library uses them | Cuts most of the 100,000 lines from user TUs | A dependency map in the translator (it knows what each module uses) |
| G. C++20 modules: an `export module <lib>;` interface unit per library, exporting only the API | Real hiding with no naming tricks; faster rebuilds | Needs CMake 3.28+ (`FILE_SET CXX_MODULES`) and recent compilers (GCC 14, Clang 16 or later, recent MSVC; check each, since support differs in header units and `import std`); headers must stay for C++14 to C++17 users, so it's an addition, not a replacement |

**Recommendation:** A and C first (they're what C++ users assume, and C
shrinks headers); B for what templates force into headers; F as a
non-breaking speed fix any time. G later, generated beside headers from
the same tree, once the version-adaptive work (section 6) settles how
one output serves several standards. E isn't worth its cost here.

What's "public" for #676: exported Temper declarations only. `make`,
getters, and the library's own namespace stay; `temper_statics`,
`temper_globals`, `global_init_*`, non-exported classes, and runtime
helper types go behind `detail` or out of headers.

## 3. Values, ownership, and the types in signatures

### Objects

Every object is `std::shared_ptr<T>` made by `T::make(...)`, and every
class derives from `std::enable_shared_from_this`. Passing is cheap
(`std::shared_ptr<T> const &` parameters, no count bump), which matches
the Core Guidelines' "R.36: Take a `const shared_ptr<widget>&`
parameter to express that it might retain a reference count to the
object", and Temper's semantics (objects are shared references,
compared by identity unless they define `==`). But the struct is also an
ordinary value type, so C++ allows what Temper doesn't:

```cpp
chromarite::Color c;                                          // no constructor runs
chromarite::Color copy = *chromarite::Color::parse("red");   // copies, sharing its lists
```

Both compile without a warning under `-Wall -Wextra`. And implementing an
interface works only through `std::make_shared`, which nothing says:

```cpp
struct Circle : cprobe::Shape {
  double r;
  explicit Circle(double r) : r(r) {}
  double area() const override { return 3 * r * r; }
};
cprobe::describeShape(std::make_shared<Circle>(1.0));   // "shape of area 3.0"
Circle onStack(2.0);
onStack.describe();   // terminate called after throwing an instance of 'std::bad_weak_ptr'
```

`describe` is the interface's default method, and its body starts with
`shared_from_this()`. On C++14 that's undefined behavior rather than an
exception.

**Equality.** `@operator("==")` becomes a method `eq`, and no type has
`operator==` or `operator<<`. So `a == b` compiles and compares
pointers, `*a == *b` doesn't compile, and `std::cout << *color` doesn't
either:

```cpp
auto a = Color::parse("red")->toSpace(Space::oklch());
auto b = Color::parse("#ff0000")->toSpace(Space::oklch());
a == b                        // false: two objects
Space::srgb()->eq(Space::srgb())   // true
```

**Options:** delete copy and default construction (private
constructor with a passkey for `make_shared`); generate
`operator==` (and `!=` before C++20) for types with `@operator("==")`,
and `operator<<` from `toString`; and say in docs that users' interface
implementations need `std::make_shared` (or make `describe`'s
`shared_from_this` safe with a raw `this` where the body doesn't let it
escape). Values as values (no `shared_ptr` for small immutable classes
like `Point`) would be the bigger change; it depends on the
[structs](../../664-structs/README.md) and value-types proposals, and
would be a later step.

### Lists and maps

A `List<T>` and a `ListBuilder<T>` are both
`std::shared_ptr<std::vector<T>>`, which reads well (`->size()`,
`->at(i)`, `for (auto& x : *list)`) but loses the difference between
them (section 1, option D). Calling the library needs
`std::make_shared<std::vector<T>>(...)` for every list argument, which
the tours spell out each time or wrap in a helper.

A range-for over a list a call returns dangles before C++23, because the
`shared_ptr` temporary dies before the loop starts. Kelpto's tour warns
about it ("a range-for over `*f()` would outlive the shared_ptr that
`f()` returns"). With Chromarite:

```cpp
for (auto const& s : *Color::parse("red")->toHex()) { ... }
```

segfaults at `-O0`, and AddressSanitizer reports `heap-use-after-free`
in `std::vector<temper::core::Str>::begin()`. C++23 (P2718) extends the
temporary's life, but g++ 14 at `-std=c++23` doesn't implement it yet:
the same loop still gives `heap-use-after-free` there.
Returning `std::vector<T>` by value (moved, so no copy), or a `const&`
to a vector the object owns, avoids the trap. That's another reason for
option D's redesign.

A `Map<K, V>` is `std::shared_ptr<temper::core::Mapped::Ordered<K, V>>`,
a `std::vector<K> order` beside a `std::map<K, V> data`, both public:
users iterate `m->order` and look up `m->data.at(k)`. Lookups are
O(log n), removal O(n), and `Mapped.toMap` on a `Map` copies both,
where JS, Lua, Rust, and the interpreter return it unchanged.
**Options:** a library-facing `Map` class (begin/end over pairs in
insertion order, `find`, `at`, `size`, `contains`), hiding the two
containers; `toMap` returning the same map; and later an
`std::unordered_map` or an insertion-ordered hash map for speed.

### Strings

`temper::core::Str` is good C++: immutable, shared by count, never null,
with `std::string`'s read-only members, implicit conversion from
`std::string` and `char const*`, and to `std::string` and (C++17)
`std::string_view`. So `std::string css = color->toCss()->at(0);` just
works. The costs are the name (`Str`, under `temper::core`, in every
signature) and a hidden pitfall: a `std::vector<Str>` doesn't convert to
`std::vector<std::string>`, so tours copy element by element (Kelpto's
and Chromarite's `join` helpers). **Options:** alias it into the library
(`hrefine::String`), rename it `String` to match Temper, and accept
`std::string_view` where a function only reads.

### Nullability

Two forms: a nullable object is a null `shared_ptr`; a nullable `Int`,
`Float64`, `Boolean`, or `String` is `temper::core::NullableParam<T>`
with public `value` and `has_value` members, also used for results:

```cpp
auto m = cprobe::maybe(false);   // NullableParam<Str>
m.has_value                      // false; no operator bool, no *, no value_or
cprobe::describe(nullptr);       // parameters take nullptr or a value
```

Its implicit `operator T()` throws `TemperBubble("accessing null
NullableParam")` when empty. C++ users expect `std::optional<T>` for
this, with `has_value()`, `operator bool`, `*`, and `value_or`.
**Options:** `std::optional<T>` on C++17 and later, with a
same-interface fallback on C++14 (the version-adaptive aliases in
section 6); keep a null `shared_ptr` for objects, as C++ users already
do.

### Callbacks

Function parameters are `std::function<R(A...)> const &`, so lambdas
pass directly: `applyTwice([](int32_t x) { return x * 3; }, 2)` gives
18. That's what users expect. Two small leaks: string arguments are
`Str` by value (`std::function<int32_t(Str)>`), so a lambda taking
`std::string const&` works only through conversion, and the unused
`struct Scorer` (section 2).

## 4. Errors and panics

### Today

| What happens | What the C++ user sees |
|---|---|
| A bubble, caught as `std::exception` | `what()` is `"bubble"` |
| A bubble, uncaught | `terminate called after throwing an instance of 'temper::core::TemperBubble'` / `what():  bubble`, exit 134 |
| Output before an uncaught bubble, stdout a pipe or file | Lost: the probe printed `before` and logged a line, and neither reached the file |
| `Map.get` on a missing key | `TemperBubble("key not found")` |
| A panic (`orelse panic()`) | `panic` on stderr, then `terminate called after throwing an instance of 'temper::core::TemperBubble'` / `what():  bubble`, exit 134 |
| `catch (...)` around a panicking call | Doesn't run: panics call `std::terminate` |
| A map changed during `forEach` (section 5) | `std::out_of_range` (`map::at`), which `orelse` doesn't catch |
| Building with `-fno-exceptions` | Fails at `#include` of any library header: `exception handling disabled, use '-fexceptions' to enable` (`base_types.hpp`) and four `'...' handler must be the last handler` errors (`string.hpp`) |

The panic row is the most confusing: `needsPositive(-1)` is
`positive(n) orelse panic()`, so the panic runs inside the `catch` that
`orelse` became, and `std::terminate` reports the bubble being handled
as if it were the cause. Panics flush `std::cout` first (good); an
uncaught bubble doesn't, since nothing runs before `std::terminate`.

Tours catch `TemperBubble const &` (Hrefine, Kelpto, Wherewith), so
users already name a runtime type to catch a library's failures, which
#676's principle 3 rules out.

### What C++ users expect

The Core Guidelines' "I.10: Use exceptions to signal a failure to
perform a required task" and "E.14: Use purpose-designed user-defined
types as exceptions (not built-in types)": a library-named type,
derived from `std::exception` (or `std::runtime_error`), with a useful
`what()`. nlohmann/json is the usual model: `nlohmann::json::exception`
derives from `std::exception`, its subclasses (`parse_error`,
`type_error`, …) carry an id, and messages read like
`[json.exception.parse_error.101] parse error at line 1, column 1: …`.

The guidelines also cover code that can't throw ("E.25: If you can't
throw exceptions, simulate RAII for resource management", "E.27: If you
can't throw exceptions, use error codes systematically"), and many
codebases build with `-fno-exceptions` (games, embedded, and large
companies' style guides). Libraries that serve them make exceptions
optional: nlohmann/json defines `JSON_NOEXCEPTION`, under which its
throws become `std::abort()` (or a user's `JSON_THROW_USER`), and {fmt}
has `FMT_EXCEPTIONS`. Error-returning APIs use `std::expected<T, E>`
(C++23) or one of its long-standing equivalents (`tl::expected`,
`absl::StatusOr<T>`).

### Options

| Option | Gains | Costs |
|---|---|---|
| A. Keep `TemperBubble`, give it a message (at least the function's name and the failure's reason) | Not breaking; tours keep working | Users still name `temper::core` |
| B. A library-named failure type (`wherewith::Error`, deriving from `std::runtime_error`), thrown in place of `TemperBubble` | E.14; `catch (wherewith::Error const&)` | Every library needs its own type, and `orelse` must still catch any library's failure (a shared base under a library alias does it) |
| C. Results as `expected<T, Failure>`, with `temper::expected` as a shim below C++23 and an alias for `std::expected` from C++23 | One API for both camps: `.value()` throws (`bad_expected_access`) for those who want exceptions; works under `-fno-exceptions` | Breaking for every failing function's signature; Temper code inside the library needs the same lowering (no `try` anywhere) |
| D. A per-build error style (`temper build -b cpp` setting: throwing or `expected`), each output clean, not `#if`'d | Both camps, natively | Two shapes of the same library; signatures differ between them, so a dependency built one way must match its users |
| E. Panics through a hook (abort by default), never `std::terminate` from inside a `catch`, with the panic's message and location first | Honest crash reports | None to speak of |
| F. Flush output before any terminate (a terminate handler set by the runtime, or flushing in the bubble's constructor when uncaught is likely) | No lost output | A global handler is a policy the app may want to own; flushing in the runtime's `main` (tests and demos) covers most uses |

**Tie to #164.** The current C++ translation proposal there
([cpp.md](../../164-exceptions/tom/claude-translations/cpp.md)) already
sketches `std::expected<std::shared_ptr<Select>, SqlProblem>` with a
throwing form for users who want one. This study adds three points:
`-fno-exceptions` users can't include a single header today, so
whichever form is chosen, the runtime's own failures (bounds,
`NullableParam`, `Map.get`) need the same treatment; failure types need
a `what()` that says something; and panics must never look like
bubbles. **Recommendation:** E and F and A's message now (not
breaking); B and C in the revamp, with C the default if #164 settles on
failures as values, since one `expected`-returning function serves both
camps and no second API is generated.

## 5. Memory safety

### Changing a builder during a callback

`List::reduceFrom` in the runtime is a range-for over `*list` calling
`fn(acc, elem)`, and the callback may grow the vector. From Temper:

```
export let growDuringReduce(): Int {
  let b = new ListBuilder<Int>();
  b.add(1); b.add(2);
  b.reduceFrom(0) { (acc: Int, x: Int): Int =>
    if (b.length < 4) { b.add(9) }
    acc * 10 + x
  }
}
```

Core's own body (`reduceFromIndex`, which loops to the live length)
gives 1299; the interpreter, JS, Lua, Python, and Rust give 12 (they
iterate a snapshot); C# throws; C++ gave 125819 in one run and 16 here,
because `push_back` reallocated the vector and the loop kept reading the
freed storage:

```
==811543==ERROR: AddressSanitizer: heap-use-after-free on address 0x502000000034
READ of size 4 at 0x502000000034 thread T0
    #0 in reduceFrom<int, int, cprobe::growDuringReduce()::<lambda(int32_t, int32_t)> > temper-core/list.hpp:238
    #1 in cprobe::growDuringReduce() cprobe/init.cpp:257
freed by thread T0 here:
    ...
    #5 in std::vector<int>::push_back(int const&) stl_vector.h:1292
    #6 in temper::core::ListBuilder::add<int>(...) temper-core/list_builder.hpp:21
```

The other runtime functions with the same shape, each checked:

| Function | Callback that changes the list or map | Result |
|---|---|---|
| `List::reduceFrom` | grows it | heap-use-after-free (above) |
| `ListBuilder::sort` | comparison grows it | heap-use-after-free inside `std::stable_sort` (`__move_merge_adaptive_backward`) |
| `List::map` | shrinks it (`b.removeLast()`) | reads past the end: ASan `container-overflow` with `-D_GLIBCXX_SANITIZE_VECTOR`, silently 3 elements otherwise |
| `Mapped::forEach` | removes a later key | `std::out_of_range` from `map::at`, past `orelse` |
| `Mapped::forEach` | adds keys | grows `order` under its own range-for; stops after one entry here by luck (comparing invalidated iterators) |
| `List::forEach`, `filter`, `join` (with a function), `Mapped::toListWith` | same patterns | same code shape, not run separately |
| `List::reduce` | shrinks it | indexes `(*list)[i]` past the end with a size read before the loop |

Generated code itself is safe here: its loops index to a length read
first and go through the bounds-checked `List::get`, so a list shrinking
under them panics with "index 3 out of bounds", as the `Window` example
shows. Only the runtime's range-for loops are exposed. Note that a user's
callback can trigger the same thing from outside, when a library
function maps over a list the user also holds and the callback changes
it.

**Fix:** loop by index to the live length through a checked read, which
is what core's `reduceFromIndex` body says (1299), or snapshot the vector
first (12, matching most backends). Either is memory safe; which to pick
is a cross-backend contract question (core's docs say a `Listed`
"shouldn't be modified concurrently"), but C++ should be fixed first,
with either, since today it's undefined behavior. For maps, iterate a
copy of `order`, and use `find` rather than `at`. For `sort`, sort a
copy and assign it back (the Rust study suggests the same for its
`sort` deadlock).

### Other ways to reach undefined behavior

A range-for over a returned list before C++23, an interface implemented
on the stack (section 3), a default-constructed object (`chromarite::Color
c;`, whose methods dereference its null members), and reading
`temper_statics::x.value` before the module's init has constructed it.
The first is the user's to avoid, though the API invites it; the others
go away with private constructors and private slots (sections 1 and 2).

## 6. Packaging and builds

### CMake

Each library gets a `CMakeLists.txt` (C++14, CMake 3.10) with
`add_library(chromarite init.cpp)`, its parent directory as a `PUBLIC`
include directory, an `add_executable(chromarite-main main.cpp)`, and,
when `std` is beside it, `add_subdirectory(../std)` (guarded by `if(NOT
TARGET std)`) and an `add_executable(chromarite-test test.cpp
init.cpp)`.

Using two libraries from a user's project with `add_subdirectory`, as
Argmas's tour does, works, and builds nine targets for a one-file app:
`argmas`, `chromarite`, `app`, `argmas-main`, `chromarite-main`, `std`,
`std-main`, `argmas-test`, and `chromarite-test` (each test target
compiling the library's `init.cpp` again). Five of the six tours avoid
the generated CMake and glob the sources into their own target instead.

What's missing, against what C++ users expect from a CMake package
({fmt}'s docs show the usual set: `find_package(fmt)`, the `fmt::fmt`
target, `FetchContent`, and a header-only variant):

- **No `install()` or export,** so no `find_package(chromarite)` and no
  `chromarite::chromarite` alias. `notes/api-compat.md` proposes exactly
  this ("A CMake package first"); nothing implements it yet.
- **Unprefixed targets:** `std`, `<lib>-main`, and `<lib>-test` are
  global target names, so a user's own `std` target or two Temper
  outputs of different versions clash (the `if(NOT TARGET std)` guard
  silently takes the first). A library named `all` fails outright:
  `The target name "all" is reserved or not valid for certain CMake
  features`.
- **Demos and tests in `all`:** they should be off unless the library is
  the top-level project (`PROJECT_IS_TOP_LEVEL`, CMake 3.21, or a
  `<LIB>_BUILD_TESTS` option).
- **Not `SYSTEM`:** the include directory is ordinary, so runtime headers
  warn in users' builds. Under `-Wall -Wextra -Wpedantic -Wshadow
  -Wconversion -Wsign-conversion -Wold-style-cast -Wuseless-cast
  -Wfloat-equal`, including the probe's header gives 39 warnings from
  `temper-core` (18 `-Wsign-conversion` in `string.hpp`, 8
  `-Wfloat-equal`, 5 `-Wshadow`, 4 `-Wuseless-cast`, and others). The
  backend's own tests mark the runtime as a system directory for this
  reason (06-backends.md); generated CMake should too.
- **One runtime copy per output:** each `temper build` writes its own
  `temper-core`, and nothing stops two different versions' headers
  meeting in one program, an ODR violation with no diagnostic. A
  `temper-core` target (an `INTERFACE` library with a version check)
  shared by all Temper libraries fixes that.

### Standards and compilers

The floor is C++14 (`CMAKE_CXX_STANDARD 14`), with C++17 and C++20
features behind `__cplusplus` (`std::string_view` conversions,
`co_await` for promises). Chromarite compiled with no errors or
warnings under `-Wall -Wextra` on g++ 12 at C++14, g++ 13 at C++17, and
g++ 14 at C++20 and C++23. CI compiles all generated C++ in its tests
under strict flags with g++ 12 and 14 and clang++ on every push, and
weekly with Apple clang and MSVC through CMake (`nightly.yml`), so the
portability claim is tested, if not with these six libraries.

One gap: Wherewith still fails `g++-14 -O3 -Wnull-dereference -Werror`,
a GCC false positive in libstdc++'s `shared_ptr` copy inlined from
`Str`'s copy constructor, in `Query::joined` (`init.cpp:9091`, `core::Str
s = string;`).

The version-adaptive design proposed for the revamp: stable names in the
library's API (`hrefine::Optional<T>`, `hrefine::List<T>`) that are the
standard types themselves on newer standards (`std::optional` from
C++17, `std::expected` from C++23) and a same-interface fallback below,
so client code compiles unchanged across `-std=` settings and values
pass freely to code using the standard types. The rule needed: one
library is built under one standard, and its users must use the same or
a newer one consistently, since an alias that changes meaning between
translation units is an ODR violation. Tests should build the same
client under several `-std=` settings.

### Compile time and size

Each library's `init.cpp` alone, g++ 13, `-O2 -std=c++17`, one job,
one run on a shared machine (so treat as rough):

| Library | Header lines (non-test) | `init.cpp` lines | Compile | Object size |
|---|---|---|---|---|
| Ordable | 96 | 2,888 | 4.4 s | 284 KB |
| kelpto-core | 202 | 1,660 | 7.4 s | 625 KB |
| Chromarite | 175 | 3,971 | 8.7 s | 724 KB |
| Argmas | 1,055 | 10,220 | 18.9 s | 1.5 MB |
| Wherewith | 1,212 | 17,954 | 29.0 s | 2.4 MB |
| kelpto-html | 875 | 8,430 | 33.6 s | 1.8 MB |
| Hrefine | 390 | 12,249 | 39.1 s | 1.7 MB |
| kelpto-md | 1,310 | 14,285 | 63.3 s | 2.6 MB |

Peak memory reached about 770 MB (kelpto-md). One translation unit per
module puts a whole library in one compiler process, so builds don't
parallelize; splitting large modules' bodies across several `.cpp` files
would. Each user source file that includes a library header pays the
2.8 to 4.5 s noted in section 2, which matters more to users than the
library's own build; trimming `core.hpp` (section 2, option F) is the
cheapest large win.

### Source locations

No generated file has `#line` directives, so compiler errors, debuggers,
and sanitizer traces (as in section 5) point at `init.cpp`, not the
Temper source. Kotlin Temper wrote `.map` files for every backend;
this compiler writes source maps only for JS. Since the C++ output is readable,
`#line` should be opt-in (a build option), so errors in generated code
can still be read there.

## 7. Naming and API idioms

| Today | What C++ users expect | Suggestion |
|---|---|---|
| `T::make(...)` as the only factory | `make_shared`-style factories are common; `T::create` too | Keep `make` (api-compat keeps it); but `make` and `shared_from_this` are reserved for *every* name, so a parameter named `make` prints as `make_` (`Str shout(Str const & make_)`). Reserve them as members only |
| Fields `x` and getters `get_x()` side by side | Either accessors (`x()` in the standard library's style, or `get_x()`) or public fields, not both | Keep `get_x()` (Kotlin-compatible), make fields private (section 1) |
| Temper's camelCase methods (`fromListWithAlpha`) with snake_case accessors (`get_width`) | One style per library; the standard library is snake_case, many libraries camelCase | Keep Temper's names (#676's principle: names belong to the library); the `get_`/`set_` prefix is the only mix, and it's established |
| `eq` and `toString` methods | `operator==` and `operator<<` | Generate the operators (section 3); keep the methods |
| Optional parameters as overloads plus `NullableParam<T>` (`greet(name)`, `greet(name, Str("Hi"))`) | Default arguments, or overloads | Fine as is; `std::optional` once available (section 3) |
| Long positional factories (`FlagSpec::make("verbose", "v", "…", nullptr, nullptr, true)`, commented in Argmas's tour) | Designated initializers (C++20) on an options struct, or a builder | The `Props` aggregate design: a struct the user fills by name, from C++20 with designated initializers |
| Lists as `shared_ptr<vector>`; range-for over `*list` | Range-for over the object; `std::span` (C++20) parameters | Section 3, option D |
| Generators support range-for | Same | Good as is |
| Generic interface methods take `T` by value (`virtual Str label(T l) const`); overrides take `Str` by value | Overrides of a template's virtual must match its signature; `T const &` for indirect types is the usual choice | Use a `Param<T>` slot (`T const &` for `shared_ptr`, `std::function`, and `Str`), as Kotlin Temper's output does and the runtime's `Param` already defines; host classes overriding such methods then use `Str const &` |

Two translation gaps came up, both errors at build time rather than bad
output: a generic function defined in a header that writes a module
variable fails with `not yet in the C++ backend: a template in a header
that takes its module's lock` (the lock would need an `extern`,
library-unique name in the header), and `@json` on generic types fails
because C++ can't call a generic class's static members without type
arguments. Both should be fixed with the visibility work, since both
are about what a header may name.

## Recommendations

**Quick wins** (not breaking; any time):

1. Fix the runtime's loops over lists and maps that call callbacks
   (section 5): `reduceFrom`, `reduce`, `map`, `filter`, `forEach`,
   `join`, `sort`, `Mapped::forEach`, and `toListWith`. Memory safe now;
   decide snapshot or live length across backends after.
2. Panics: never `std::terminate` from inside a `catch`; print the panic
   (with a location when there is one) and abort through the hook.
   Flush `std::cout` before an uncaught bubble ends the process (the
   generated `main` and test runner, at least).
3. Give bubbles messages: the function and reason, and the runtime's own
   (`Map.get`'s key).
4. CMake: `install()` and `export()` with a `<lib>::<lib>` alias and a
   package config for `find_package`; `SYSTEM` include directories; tests
   and `-main` only when top level or asked for; prefixed target names
   (`temper-std`), and a check that rejects reserved names (`all`).
5. Split `core.hpp` so user TUs include only what the library uses.
6. Reserve `make` and `shared_from_this` as member names only.
7. `operator==` and `operator<<` beside `eq` and `toString`.
8. `Mapped.toMap` returns the same map.
9. Close the Wherewith `-Wnull-dereference` gap at `-O3` on g++ 14.
10. Update the tours to use the generated CMake once 4 lands.

**Medium** (some breaking for unusual code; could land before the
revamp):

11. `private:` for private fields and constructors (passkey `make`),
    `detail` for non-exported classes, and non-exported code out of
    headers where no template needs it.
12. Delete copying and default construction of object types.
13. Override slots as `Param<T>` for type parameters in virtuals.
14. `#line` directives behind a build option.
15. The module lock for header templates, and `@json` on generic types.

**Breaking** (the revamp RFC):

16. **Immutability:** fields private behind `const` getters;
    `const` methods for every class without `var` fields; immutable
    classes as `shared_ptr<T const>`; private statics and module values.
17. **Collections:** `List<T>` distinct from `ListBuilder<T>` (read-only
    for the former), lists returned so that range-for can't dangle, and
    a `Map` type with iterators instead of `Mapped::Ordered`'s internals.
18. **Library-owned names:** aliases for every runtime type a signature
    shows (`hrefine::String`), `Str` renamed `String`, and nothing in the
    API requiring `temper::core`.
19. **Errors:** library-named failure types deriving from
    `std::runtime_error`, `expected`-returning functions per #164, an
    exception-free build that compiles under `-fno-exceptions`, and the
    runtime's own failures in the same style.
20. **Standards:** stable aliases (`Optional`, `Expected`, `List`) that
    are the standard types on newer standards; the floor (C++14 or
    C++17); C++20 modules as an addition.
21. **Memory model:** where values could be values (small immutable
    classes) rather than `shared_ptr`, after the structs and value-types
    proposals.

### Themed changes

- **C++ safety** (1, 2, 9): one bounded change, with ASan and
  `_GLIBCXX_SANITIZE_VECTOR` tests for each function, run in the
  sanitized CI job that already exists.
- **C++ packaging** (4, 5, 10, and a shared `temper-core` target): one
  change, tested by a CMake project that uses two libraries through
  `find_package` after `cmake --install`, and by measuring a user TU's
  include cost before and after.
- **C++ messages and operators** (3, 6, 7, 8): small, mostly additive.
- **C++ visibility** (11 to 15): headers shrink; checked by compiling
  each tour unchanged, plus a negative test (a program that touches a
  private field must fail to compile), as Chromarite's
  `demos/immutable` does.
- **The revamp** (16 to 21), behind an RFC, landing as one new output
  shape rather than a series of breaks.

### Outline for a C++ backend revamp RFC

1. **Goals:** C++ that a C++ user would write: immutable where Temper
   is, nothing internal in headers, no runtime names in the API, usable
   with and without exceptions, packaged for `find_package`.
2. **Non-goals:** ABI stability across Temper versions; pimpl; a
   non-CMake build system as the primary one (vcpkg and Conan build on
   CMake).
3. **The object model:** `class` with private state, `make` as the
   factory, no copies, `shared_ptr<T const>` for immutable classes,
   identity and `operator==`.
4. **Collections:** `List`, `ListBuilder`, `Map`, `MapBuilder` as
   library-facing types (or `std` types with `const`), iteration rules,
   and the cross-backend contract for changes during callbacks.
5. **Names:** library aliases, `String`, what stays in `temper::core`,
   `detail` and internal linkage, reserved names.
6. **Errors:** the default style (`expected` or throwing), the
   exception-free build, failure types and messages, panics (recoverable
   at all in C++? through which hook?), ties to #164.
7. **Standards and toolchains:** the floor, the alias set, ODR rules for
   mixing, modules, and the compiler matrix (g++, clang++, MSVC, Apple
   clang) each library is tested on.
8. **Packaging:** targets, install and export, one shared runtime,
   versions.
9. **Compatibility:** which of today's API survives (getters, `make`,
   namespaces), how users migrate, and whether the old shape stays as a
   variant for a while, as the Rust backend's variants allow.
10. **Open questions:** values as values; source maps by default or not;
    how Kotlin Temper's C++ output compatibility is weighed.

Items 1 to 15 don't need an RFC: they're fixes and conventions. Items 11
and 12 change what compiles for code that relied on internals, which
api-compat's rules allow as fixes, but they're worth announcing.

## Bugs found

On temperlang/temper `13dc5669`, g++ 13 unless noted, Linux. `cprobe`
is built from the Temper shown.

1. **`reduceFrom` reads freed memory when the callback grows the
   builder:** `let b = new ListBuilder<Int>(); b.add(1); b.add(2);
   b.reduceFrom(0) { (acc: Int, x: Int): Int => if (b.length < 4) {
   b.add(9) } acc * 10 + x }` returns garbage (16, or 125819), and
   ASan reports `heap-use-after-free` at `list.hpp:238`.
2. **`ListBuilder.sort` reads freed memory when the comparison grows the
   builder:** `b.sort { (a: Int, c: Int): Int => if (b.length < 40) {
   b.add(0); } a - c }` on `[3, 1, 2]`; ASan `heap-use-after-free` in
   `std::stable_sort`'s merge.
3. **`List.map` reads past the end when the callback shrinks the
   builder:** `b.map { (x: Int): Int => b.removeLast(); x }.length` on
   `[1, 2, 3]` gives 3; ASan `container-overflow` at `list.hpp:130`
   with `-D_GLIBCXX_SANITIZE_VECTOR`. `List::reduce` indexes the same
   way with a stale size.
4. **`Map.forEach` leaks `std::out_of_range`:** on a `MapBuilder` of
   `a`, `b`, `c`, a callback doing `if (m.has("c")) { m.remove("c")
   orelse void; }` ends with `terminate called after throwing an
   instance of 'std::out_of_range'` / `what(): map::at`, which no
   `orelse` catches.
5. **A panic reports itself as a bubble:** `export let needsPositive(n:
   Int): Int { positive(n) orelse panic() }` with `positive` bubbling;
   `needsPositive(-1)` prints `panic`, then `terminate called after
   throwing an instance of 'temper::core::TemperBubble'` / `what():
   bubble`, because the panic's `std::terminate` runs inside the
   `catch` that `orelse` became.
6. **Output lost on an uncaught bubble:** `std::cout << "before";
   cprobe::say("logged"); cprobe::positive(-1);` with stdout redirected
   to a file leaves the file empty.
7. **No header compiles under `-fno-exceptions`:** `#include
   "cprobe/init.hpp"` alone gives `exception handling disabled`
   (`base_types.hpp:199`) and four `'...' handler must be the last
   handler for its try block` (`string.hpp:367`, `397`, `424`, `454`,
   where `-fno-exceptions` turns the `catch (const TemperBubble&)` and
   `catch (const std::exception&)` pairs of the number parsers into
   catch-alls).
8. **Private members and constructors are public:** `private var
   secret: Int` is a public `int32_t secret;`; `private constructor`
   gives a public `make` (`chromarite::Space::make("mine", 3,
   nullptr)`).
9. **Statics and module values are writable around their accessors:**
   `chromarite::Space::temper_statics::srgb.value =
   chromarite::Space::oklch();` makes `Space::srgb()->get_name()`
   `oklch`; `argmas::englishMessages()->data[key] = "hijacked"` changes
   every command's text.
10. **`const` doesn't follow immutability:** methods of immutable
    classes that pass `this` on (`Color::toSpace`, `lighten`, `toCss`)
    aren't `const`, so they can't be called through
    `shared_ptr<Color const>`.
11. **Default interface methods crash on stack objects:** a C++ class
    implementing `Shape` (with `describe() { "shape of area …" }` as a
    default), made on the stack, throws `std::bad_weak_ptr` from
    `describe()` (C++17; undefined on C++14).
12. **Generated CMake doesn't fit users' builds:** `add_subdirectory`
    of two libraries builds `<lib>-main`, `<lib>-test`, `std`, and
    `std-main` as part of `all`; a library named `all` fails (`The target
    name "all" is reserved`); and the include directory isn't `SYSTEM`,
    so the runtime gives 39 warnings in users' strict builds (section 6).
13. **Wherewith fails `-Wnull-dereference` at `-O3` on g++ 14:**
    `potential null pointer dereference` in `atomicity.h`, inlined from
    `Str`'s copy constructor in `Query::joined`.
14. **`make` is reserved for every name, not only members:** `export let
    shout(make: String): String { make }` declares `Str shout(Str const
    & make_)`.
15. **Overrides of generic virtuals take indirect types by value:**
    `interface Labeled<T> { public label(l: T): String; }` and `class
    Tag extends Labeled<String>` give `virtual Str label(T l) const` and
    `Str label(Str l) const override`, unlike `Param<T>`'s `Str const &`.
16. **`Mapped.toMap` copies a `Map`:** `mapped.hpp`'s `toMap` copies
    both containers where other backends return the same map.
