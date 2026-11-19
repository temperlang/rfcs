# Temper libraries from a Rust user's point of view

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

## The question

Does a Temper library feel like a Rust crate to someone who writes Rust,
and what would make it more so?

**Short answer:** it builds, it's memory safe, it's `Send + Sync`, it's
clippy-clean apart from a few dozen rustc warnings, and the hot loops are
often as fast as hand-written Rust. But it reads as a port. Strings are
`Arc<String>`, lists `Arc<Vec<T>>`, and callbacks `Arc<dyn Fn + Send +
Sync>`, so callers wrap things by hand. No exported type implements
`Debug`, `Eq`, or `Hash`, so `assert_eq!`, `{:?}`, and `HashSet` fail.
Every failure prints "bubble". Implementing a Temper interface takes a
supertrait dance and a macro that only works on tuple structs. Mutable
objects lock every field separately, lose updates across threads anyway,
and deadlock in two `ListBuilder` cases found here; field updates are
tens of times slower than a plain field. Most fixes are additive. A few
are breaking, and those are design questions for this RFC and for
[#164](../../164-exceptions/README.md).

## How this was studied

- Built the six showcase libraries (Argmas, Chromarite, Hrefine, Kelpto,
  Ordable, and Wherewith) with Temper's compiler (`temper build -b rust`,
  temperlang/temper at `13dc5669`, runtime `0.7.0-alpha.0.265`), and
  compiled everything with Rust 1.85.0, the toolchain the generated
  crates' dependency policy targets. Nothing here needed a newer Rust.
  The crates declare `rust-version = "1.71.1"`, which wasn't installed,
  so that claim is untested here.
- Read each library's Rust tour, the Rust backend
  (`crates/temper-be-rust`), its runtime
  (`crates/temper-be-rust/runtime/temper-core`), and
  `notes/api-compat.md`, whose Rust items 3, 4, and 11 already propose
  some of what follows.
- Wrote a small probe library (about 90 lines of Temper: an interface
  with a default method, a fun interface, a class with `var` fields, a
  class holding a `ListBuilder`, lists, maps, nullables, defaults, and
  bubbles), and scratch crates that use it and the six libraries the way
  a Rust user would. Every snippet below was compiled or run, and output
  is quoted as printed.
- Rust conventions come from the
  [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/checklist.html)
  (cited by item, such as C-COMMON-TRAITS), std's docs, and well-known
  crates (`regex`, `serde_json`, `clap`, and `url`). Quotes from the
  guidelines and std were checked against their sources on GitHub;
  docs.rs didn't respond, so details of those crates are from their
  documented, long-stable behavior. Check them there before quoting
  further.
- Timings are from a shared, noisy machine. Ranges are the fastest and
  slowest of 15 timed runs (three processes of five each).

## 1. Implementing Temper interfaces from Rust

**Today.** An interface `Listener` becomes a trait `ListenerTrait` with
`AsAnyValue + AnyValueTrait + Send + Sync` supertraits and a
`clone_boxed` method, plus a handle `pub struct Listener(Arc<dyn
ListenerTrait>)` made by `Listener::new`. Argmas's tour shows the
working form, which needs its own explanation:

```rust
/// Types that implement a Temper interface wrap an `Arc`, and say which
/// interfaces they implement with `impl_any_value_trait!`.
#[derive(Clone)]
struct OsEnvironment(Arc<()>);

impl EnvironmentTrait for OsEnvironment {
    fn clone_boxed(&self) -> Environment {
        Environment::new(self.clone())
    }
    fn get(&self, name: Arc<String>) -> Option<Arc<String>> { … }
}

temper_core::impl_any_value_trait!(OsEnvironment, [Environment]);
```

The `Arc<()>` is there for the macro, which reads `self.0` as an `Arc`
for identity. What a Rust user writes first fails in three ways:

```
// struct Scaled { factor: i32 } with the macro:
error[E0609]: no field `0` on type `&Scaled`
17 | temper_core::impl_any_value_trait!(Scaled, [Listener]);

// Only `heard`, no macro:
error[E0277]: the trait bound `Plain: temper_core::AnyValueTrait` is not satisfied
   = note: `ListenerTrait` is a "sealed trait", because to implement it you also
     need to implement `temper_core::AnyValueTrait`, which is not accessible

// A closure for a one-method interface:
error[E0277]: the trait bound `{closure@…}: ListenerTrait` is not satisfied
6  |     c.bump(1, Listener::new(|n: i32| n * 2));
```

rustc calls the trait sealed, which is what a Rust user will believe,
since a sealed trait is the standard way to say "don't implement this"
(C-SEALED). And a listener with state needs `Arc<Mutex<…>>` inside its
own type, since methods take `&self` and the trait needs `Sync`. Kelpto's
`RenderSinkTrait`, with four callbacks that would naturally collect into
a `String`, is where this bites.

**What Rust users expect.** Implement a trait with only its own methods,
on any type, named fields included. Where a callback has one method, pass
a closure: `regex`'s `Replacer` is implemented for `FnMut(&Captures) ->
T`, and `clap`'s `TypedValueParser` for `Fn(&str) -> Result<T, E>`, so
`.value_parser(|s: &str| …)` just works. Conversions go through `From` /
`Into` (C-CONV-TRAITS), so a parameter taking `impl Into<Listener>`
accepts a user's type or a closure directly.

**Options.** I sketched B and C from the table below as generated code
beside today's (about 90 lines for `Listener`), and both compiled on
1.85.0; appendix A9 shows them and a user's code.

| Option | Gains | Costs |
|---|---|---|
| A. Keep `XTrait` + `clone_boxed` + macro, document the tuple-struct rule | No change | Every implementer learns Temper's runtime; error messages say "sealed" |
| B. A plain `Listen`-style trait with an adapter, `From<T> for X` (sketched) | Any type implements it; no macro, `Arc`, or `Clone` needed; additive | A second trait name per interface (`Listen` beside `ListenerTrait`); getting the user's value back gives `Arc<T>`, not `T` |
| C. `X::from_fn` and a blanket closure impl, for interfaces with one required method (sketched) | Closures work, like `regex` and `clap` | Only for one required method: Argmas's `Environment` and `Completer` and Kelpto's `RawHtmlHandler` and `RawHtmlRenderer` qualify; Argmas's `Checker` and Kelpto's `RenderSink` don't |
| D. Parameters take `impl Into<X>` instead of `X` | Callers pass their type or closure directly | Generic functions everywhere; changes signatures (callers passing `X` still compile) |
| E. A declarative macro, `listener!(MyType)` | Short for today's form | Still a macro to learn; B makes it unnecessary |
| F. `api-compat.md` item 4: one trait per interface, `pub type X = Arc<dyn XTrait>` | Fewer types; upcasts by `.into()` | Breaking; still needs B's adapter for `AnyValue`, unless casts move out of the trait |

B and C are additive and small. Naming B's trait is the design question:
`Listen`, `ListenerImpl`, or taking the plain name `Listener` for the
trait and renaming the handle (breaking). And for interfaces whose
methods mutate, a `&mut self` flavor would need a `Mutex` in the adapter
and must not be re-entered (section 2).

## 2. Locks and shared state

### Inventory

Counted in the six libraries' generated code, outside `#[cfg(test)]`:

| Library | `RwLock` fields | of which `i32`/`bool`/`usize` | Classes with them | String builders | List builders | `OnceLock` statics | `.unwrap()` on a lock |
|---|---|---|---|---|---|---|---|
| Argmas | 14 | 3 | 3 | 17 | 44 | 40 | 32 |
| Chromarite | 0 | 0 | 0 | 2 | 43 | 74 | 0 |
| Hrefine | 28 | 19 | 4 | 14 | 32 | 120 | 106 |
| kelpto-core | 0 | 0 | 0 | 5 | 17 | 17 | 0 |
| kelpto-html | 59 | 47 | 7 | 19 | 41 | 171 | 292 |
| kelpto-md | 58 | 53 | 10 | 57 | 98 | 123 | 196 |
| Ordable | 6 | 6 | 2 | 8 | 12 | 25 | 22 |
| Wherewith | 46 | 30 | 14 | 28 | 55 | 135 | 194 |
| **Total** | **212** | **159** | **41** | **151** | **342** | **705** | **847** |

What they are:

- **Mutable fields:** each `var` field is its own `RwLock`, read through
  a getter that takes the read lock and clones, and written by taking
  the write lock just to store. Wherewith's lexer has eleven
  (`state: RwLock<i32>`, `line: RwLock<i32>`, …). Three in four are
  scalars.
- **String builders:** `Arc<RwLock<String>>`, 135 of 151 created as
  `let` locals in a function, and passed to 21 helper functions by
  `Arc`. One kind is public: kelpto-core's `GreenNode::write_to(&self,
  out: Arc<RwLock<String>>)`.
- **List and map builders:** `temper_core::ListBuilder<T> =
  Arc<RwLock<Vec<T>>>`, 342 created, 118 held in fields.
- **Module state:** 705 `OnceLock` statics, read through
  `support::initialized`, an atomic load and a thread-local check. 348
  of them are `OnceLock<i32>` constants, such as kelpto-md's
  `TAB_STOP` and `TYPE_DOCUMENT`, which could be `const`. No module
  `var`s in these libraries.
- **No `Mutex`, no atomics** beyond the runtime's init flag.

### Re-entrancy

The backend's docs say no lock is held across a call: a field is read
under its lock, released, and written after the value is computed
(`translate/classes.rs`). That held up. A listener that calls back into
the `Counter` calling it, reading and writing `count`, runs fine.

The runtime breaks it in two places. `ListBuilder.sort` holds the
builder's write lock while calling the comparison, and `addAll` holds it
while reading the values added. On Linux both hang. std's `RwLock` docs
say only that `read` and `write` "might panic when called if the lock is
already held by the current thread"; neither outcome is something a
library should risk. A Rust comparison calling the sorted object's
`size` getter hangs, and so does pure Temper: `b.addAll(b)`, or a
comparison reading `b.length`. Appendix A2 has the cases, a runtime fix
(copy the values first, and sort a copy), and Python's behavior.

### Poisoning

Every lock access is `.unwrap()` (847 sites). After a panic while a lock
is held for writing, the value is poisoned and every later use panics.
Field writes never hold a lock across a call, so only builders are
exposed, again through `sort`: after a caught panic in a comparison,
`bag.size()` panics with `PoisonError`. That matches std's own types (a
`Mutex` poisoned by a panic stays poisoned), and
`temper_core::block_panics` documents it. A2's fix holds no lock during
the comparison, so a panic there no longer poisons. With no lock
held across calls, it would almost never happen. Ignoring poison
(`.unwrap_or_else(PoisonError::into_inner)`) is reasonable where every
write is a single store, since no invariant can be half-updated.

### Shared across threads, but not atomic

Every exported type is `Send + Sync`, which tells a Rust user it's safe
to share. It's memory safe, but each method is many critical sections,
not one. Four threads calling `Counter::add(1)` (Temper: `count += x`)
100,000 times each end near 300,000, not 400,000 (appendix A8).

The backend already holds one write lock for `count = count + 1` on a
module `var` (`translate.rs`), so concurrent updates aren't lost there;
class fields don't get the same treatment. Rust users expect one of two
things: `Sync` types whose `&self` methods are each atomic (`AtomicI32`,
`Mutex<T>`, `DashMap`), or owned types that are `!Sync` with interior
mutability (`Cell`, `RefCell`), leaving the choice of `Mutex` to them.
Temper objects are shared references, though, so the second shape
isn't open to them (appendix A15).

### Cost

10 million `count += 1` through `Counter::add`, against alternatives
(ms, release build, 15 runs):

| How | ms | per add |
|---|---|---|
| Generated (`RwLock` read, then `RwLock` write) | 437–1108 | 44–110 ns |
| std `RwLock`, read then write, by hand | 469–803 | |
| `parking_lot::RwLock`, read then write | 494–955 | |
| std `Mutex`, one lock per add | 218–484 | |
| `parking_lot::Mutex`, one lock per add | 227–794 | |
| `Rc<RefCell<i32>>` | 8–28 | about 1–3 ns |
| `AtomicI32`, `load` then `store`, `Relaxed` | 9–60 | |
| A plain `&mut` field | 8–45 | |

Since Rust 1.62, std's locks are futex-based on Linux, and
`parking_lot` was no faster here, so swapping lock crates wouldn't help.
What costs is taking two locks per update where none is needed.

String builders cost too: one million `sb.append(digit.toString())`
take 128–310 ms generated, against 52–223 ms for the same allocations
into a plain `String` (and 3–11 ms with `String::push(char)`).

### Options

| Option | Gains | Costs |
|---|---|---|
| Local builders that never escape as `let mut s = String::new()` (and `Vec`), helpers taking `&mut String` | Most of the 135 local string builders and many list builders lose their lock and `Arc`; no API change | An escape analysis in the backend (captured by a closure, stored, or returned means it escapes) |
| Scalar fields as atomics (`AtomicI32`, `AtomicBool`; `Acquire` loads, `Release` stores), and `x += e` as `fetch_add` | 159 of 212 locks gone; 5–50 times faster per access; no poisoning; `+=` stops losing updates (A8) | Other updates still not atomic across a method; `f64` needs `AtomicU64` with bit casts; `Int64` fine |
| One `Mutex` per object instead of a lock per field (`api-compat.md` item 4) | Fewer locks; a method could hold it to be atomic | Holding it across a call deadlocks on re-entry, as `sort` does now; std has no stable re-entrant mutex |
| Constants as `const` | 348 `OnceLock<i32>` reads become literals (24–79 ms vs 4–10 ms per 10M reads) | Only for literal values; others stay `OnceLock` |
| Ignore poison | A caught panic doesn't break the object forever | Hides a half-done write, if one is ever possible |
| A single-threaded cargo feature (`Rc`/`RefCell`, item 4's `temper_core::Shared`) | About 30 times faster updates in this test | Cargo features are additive and unified per build: if any crate in the graph turns it on, every Temper library becomes `!Send`, which breaks other crates that send them across threads. Better as the library author's choice at `temper build` time (a variant) than a feature |
| Mutable classes single-threaded (`Rc` with `Cell`/`RefCell` fields), immutable ones `Send + Sync` | Matches single-threaded Temper exactly, and fast | Breaking: `Rc` makes them `!Send`, so they can't cross threads even in a user's `Mutex` (A15); `Promise` and async machines would need rework |

The first four are invisible to users and safe to do now. The last two
are a design question, below.

## 3. API surface

### Parameters

Across the six libraries' roughly 1,900 public functions and methods:

| In parameters | Count |
|---|---|
| `impl ToArcString` | 282 |
| `impl temper_core::ToList<T>` | 95 |
| `Option<impl …>` (needs `None::<&str>`) | 44, in 34 functions |
| other `temper_core::` types (`Map`, `Listed`, …) | 115 |
| `Arc<dyn Fn(…) + Send + Sync>` | 6 |

Strings are mostly fine: `impl ToArcString` takes `&str`, `String`,
`Arc<String>`, and `char`, and the cost of converting `&str` is small
next to the work (1M `compare_smart` calls: 880–2037 ms from `&str`,
818–1584 ms from cloned `Arc`s). Each still allocates, where `&str` and
`impl AsRef<str>` wouldn't (C-CALLER-CONTROL).

The rest is where users stop. What the compiler said to things a Rust
user would write:

```
hrefine::parse_url("https://example.com/", None)
error[E0283]: type annotations needed
  = help: consider specifying the generic argument: `None::<T>`

ordable::sort_smart(vec!["img12", "img2"])
error[E0277]: the trait bound `Vec<&str>: temper_core::listed::ToList<Arc<String>>` is not satisfied

ordable::sort_smart(&["b", "a"][..])
error[E0277]: the trait bound `&[&str]: temper_core::listed::ToList<Arc<String>>` is not satisfied
  = help: the following other types implement trait `temper_core::listed::ToList<T>`: &[T; N], [T; N]

rprobe::score_all(words, |s| s.len() as i32)
error[E0282]: type annotations needed
  help: consider giving this closure parameter an explicit type
```

So the tours write helpers: Ordable's `fn list(items: &[&str]) ->
Vec<Arc<String>>`, Argmas's `fn s(text: &str) -> Arc<String>`, and
`Arc::new(|track: Track| Arc::new(track.title))` for a key function.
Callbacks must be `Send + Sync + 'static` even when called only during
the call, so a closure counting calls in a `Cell` fails (``Cell<i32>`
cannot be shared between threads safely``), where std's `sort_by_key`
takes any `FnMut`. Maps must be built as `temper_core::Map`.

**What Rust users expect.** `&str` or `impl AsRef<str>`, slices
(`&[T]`) or `impl IntoIterator<Item = impl Into<T>>`, `Option<&str>`
(plain `None` works), and `impl Fn(…)` or `impl FnMut(…)` borrowed for
the call. `regex::Regex::new(&str)`, `url::Url::parse(&str)`,
`url::Url::join(&self, &str)`, and `clap`'s `impl Into<Str>` and
`impl IntoIterator` arguments.

**Options.**

- `Option<impl ToArcString>` as `Option<&str>` (api-compat item 3).
  Compatible for callers who pass `Some("…")`; `None::<&str>` keeps
  compiling.
- `ToList<T>` implemented for `&[T]`, and for `Vec<&str>`, `&[&str]`,
  and `[&str; N]` when `T` is `Arc<String>`; or list parameters as
  `impl IntoIterator<Item = impl ToArcString>`. Additive in the runtime.
- Callbacks a function only calls during the call, which the compiler
  can see (not stored, not captured), as `&dyn Fn(…)` or `impl Fn(…)`
  with no `Send + Sync + 'static`. Breaking for callers who pass
  `Arc::new(…)`, unless the parameter is `impl Into<…>`.
- `From<HashMap<K, V>>` and `FromIterator<(K, V)>` for
  `temper_core::Map`.

### Returns

`Arc<String>` in 386 returns, `temper_core::List<T>` (an `Arc<Vec<T>>`)
in 126, and `temper_core::Result<T>` in 75. Through `Deref`,
`list.iter()`, `list[i]`, `list.len()`, and `&*list` all work, and
`s.as_str()` works for strings, so returns are mostly fine. Two gaps:
`for x in list` fails (``Arc<Vec<Arc<String>>>` is not an iterator``),
and lengths and indexes are `i32` (`Color::length()`), where Rust uses
`usize` and `len()`.

**Options.** Return `Arc<str>` (cheaper, still shared) or `String` where
nothing is shared, and a list newtype implementing `IntoIterator`,
`Deref<Target = [T]>`, `Debug`, and `PartialEq`. Both breaking in type,
mostly not in use.

### Constructors and builders

Classes have `X::new(…)`, as C-CTOR asks. Optional parameters are
positional `Option`s (`Order::new(None, Some(true), None, None)`), and
exported classes whose constructor takes two or more arguments get a
builder in a `builders` module, which has its own shape:

```rust
CommandSpecBuilder { name: s("pack") }.options().about(s("Pack files into archives.")).version(s("1.0.0")).build()
Command::new("pack").about("Pack files into archives.").version("1.0.0")  // clap
```

**What Rust users expect** (C-BUILDER): `X::builder(required…)` or a
`XBuilder::new(required…)`, setters taking `impl Into<…>`, and
`build()`. A struct literal with public fields for required values is
unusual, and `.options()` is a step nobody guesses.

**Options.** Add `X::builder(name)` returning today's `XOptions`
(additive), with setters taking `impl ToArcString` as constructors do.
`Default` and `X::default()` where every parameter is optional
(`Counter`, `Order`), instead of `#[allow(clippy::new_without_default)]`.

### Naming

Mostly right: snake_case functions and methods, `CamelCase` types,
getters without `get_` (C-GETTER), setters `set_x`, and keyword escapes
`r#ref` only in parameters, where callers never see them. Gaps:

- **Inherent methods named like std traits:** 35 types have `pub fn
  to_string(&self) -> Arc<String>` beside `Display`, so `x.to_string()`
  gives an `Arc<String>`, not a `String`. Wherewith's tour writes
  `v.to_string().to_string()`. 15 have an inherent `eq(&self, other: X)`.
  The generated `#[allow(clippy::should_implement_trait)]` hides it.
  Option: drop the inherent `to_string` where `Display` exists, and keep
  `eq` only via `PartialEq` (breaking in type only).
- **Module values as functions:** an exported `let` is a function,
  `kelpto_md::heading_kind()`, where Rust would use a `const` or an
  associated `const` (`Kind::HEADING`), at least for literal values.
- **`init_`**: Hrefine's `UrlSearchParams::new(init_)` escapes a name
  that isn't a Rust keyword. Harmless, but it shows in rustdoc.

### Common traits

Of the 160 exported types (structs at the crate root):

| Trait | Implemented by |
|---|---|
| `Clone` | 160 |
| `Display` | 34 (where Temper has `toString`) |
| `PartialEq` | 15 (where Temper has `==`) |
| `Deref` | 26 (interface handles, to `dyn XTrait`) |
| `Debug`, `Eq`, `Hash`, `Default`, `PartialOrd`, `From`, `IntoIterator`, `std::error::Error` | 0 |

So:

```
println!("{url:?}")
error[E0277]: `Url` doesn't implement `Debug`

assert_eq!(a, b)     // chromarite::Color
error[E0369]: binary operation `==` cannot be applied to type `Color`
error[E0277]: `Color` doesn't implement `Debug`

HashSet::new().insert(url)
error[E0277]: the trait bound `Url: Eq` is not satisfied
error[E0277]: the trait bound `Url: Hash` is not satisfied
```

C-COMMON-TRAITS asks crates to implement these eagerly, because the
orphan rule stops users from adding them: a user can't write `impl
Debug for hrefine::Url`. C-DEBUG asks for `Debug` on every public type,
and `assert_eq!` and `#[derive(Debug)]` on a user's own struct holding a
`Url` both need it. `url::Url` has `Debug`, `Clone`, `Eq`, `Ord`,
`Hash`, `Display`, and `FromStr`. C-DEREF says only smart pointers
should implement `Deref`; the interface handles nearly are one, so that
one is arguable.

**Options.**

- `Debug` everywhere, quick and non-breaking: the `Display` text where
  there is one (`Url("https://…")`), otherwise the type and its public
  properties, or `Color { .. }` via `finish_non_exhaustive`.
- `Eq` where `==` is Temper's `@auto("==")` structural equality of
  types whose fields are all `Eq`; `f64` fields rule it out (Chromarite).
- `Hash` needs a Temper-level hashing decision, since a Rust `Hash` must
  agree with `==`. A design question.
- `Default` for zero-argument constructors.
- `FromStr` and `TryFrom<&str>` for types with a `parse` that bubbles
  (`Color`, `Url`, `Identifier`), so `"red".parse::<Color>()` works.

### Errors

**Today.** A bubble is `temper_core::Error`, which implements
`std::error::Error + Send + Sync + Clone + Debug + Display`, so `?` into
`Box<dyn Error>` works, as Chromarite's tour does. But it carries no
message:

```
parse_url("not a url")       → Display "bubble", Debug Error(None), source None
Color::parse("not a color")  → bubble
Identifier::named("")        → bubble
fn main with ?               → main got: bubble
```

Wherewith's API works around it with a `…_problem` function beside each
fallible one (`template_problem`, `string_problem`), and its tour writes
`match … { Err(_) => println!("refused, {}", problem(…)) }`. The type is
Temper's, shared by every Temper library, so `Result<T,
temper_core::Error>` appears in users' own signatures (Wherewith's tour:
`fn main() -> temper_core::Result<()>`).

**What Rust users expect** (C-GOOD-ERR): an error type of the crate's own
(`regex::Error`, `serde_json::Error`, `url::ParseError`), a `Display`
message that is "lowercase without trailing punctuation, and typically
concise" (`url`'s "relative URL without a base"), `source()` for
causes, and often a kind (`serde_json::Error::classify`,
`url::ParseError`'s variants) for matching.

**Tie to #164.** The Rust translation in
[#164](../../164-exceptions/tom/claude-translations/rust.md) already
proposes library-named failure types with messages and a crate-level
`Error` enum with `From` impls. Rust's idiom is a failure value either
way, so both #164 proposals generate the same Rust. From this study:

- Before #164 lands, a message helps at once: `bubble()` sites in
  exported functions could pass the function's name, giving
  "`Color::parse` failed" instead of "bubble". Additive, since
  `Display` is all that changes.
- A per-crate `pub type Error = temper_core::Error` and `pub type
  Result<T>` re-export would let users write `chromarite::Result<T>`
  without naming `temper_core`, and become #164's enum later without
  another rename in users' code.
- `#[must_use]` comes with `Result`; good.

### Panics

`orelse panic()` panics with `explicit panic` and a position in
generated code (`Color::from_list(Space::srgb(), [1.0, 2.0])`: "panicked
at chromarite/src/mod.rs:1127:21: explicit panic"). List indexes out of
bounds give `index 15 out of bounds for length 3`, the flat index of a
matrix, not the one passed. C-FAILURE asks for a "# Panics" section in
the docs of functions that panic. Option: `panic!` with the Temper
function's name and, where known, the cause.

## 4. Crate packaging

**Today.** Each library is a crate with `src/lib.rs` (`mod r#mod; pub use
r#mod::*;`), `src/mod.rs`, `src/support/`, and a `src/main.rs` that runs
the tests:

```toml
[package]
name = "ordable"
version = "0.0.1"
license = "Apache-2.0 OR MIT"
edition = "2021"
rust-version = "1.71.1"

[dependencies]
temper-core = { path = "../temper-core", version = "=0.7.0-alpha.0.265" }

[dev-dependencies]
temper-std = { path = "../std", version = "0.7.0-alpha.0.265" }
```

Problems, in order of impact:

1. **Exact pins break users' builds.** `temper-core` pins `indexmap =
   "=2.11.4"`. A user crate depending on Ordable and on `indexmap =
   "2.12"`:

   ```
   error: failed to select a version for `indexmap`.
   versions that meet the requirements `^2.12` are: 2.14.2, 2.12.1
   previously selected package `indexmap v2.11.4`
       ... which satisfies dependency `indexmap = "=2.11.4"` of package `temper-core …`
   ```

   Anything in the graph that needs `indexmap` 2.12 or later, directly
   or through a dependency, can't use a Temper library. The same holds
   for `temper-std`'s `regex = "=1.12.2"` and `ureq = "=3.1.2"`, and for
   the libraries' own `temper-core = "=…"`, which stops two libraries
   built by different Temper versions from sharing a build.
   `api-compat.md` item 11 (ranges, MSRV 1.85, the MSRV-aware resolver)
   fixes exactly this.
2. **Two libraries' outputs can't be used together by path.** Each
   `temper build` writes its own `temper-core`, so a crate depending on
   two libraries' outputs fails:

   ```
   error: package collision in the lockfile: packages temper-core v0.7.0-alpha.0.265
   (…/argmas/rust/temper-core) and temper-core v0.7.0-alpha.0.265
   (…/chromarite/rust/temper-core) are different, but only one can be written
   to lockfile unambiguously
   ```

   Published crates would resolve to one registry `temper-core`, so this
   bites local development and monorepos; a `[patch]` section, or
   building into one shared output, works around it.
3. **A binary target that runs tests.** `src/main.rs` is
   `ordable::init(None).unwrap().run_all_blocking();`. `cargo install
   ordable` would install it, and it shows as a binary on docs.rs.
   Libraries don't ship one; tests belong in `cargo test`.
4. **Thin metadata.** No `description`, `repository`, `documentation`,
   `keywords`, `categories`, or `readme` (C-METADATA). `cargo package`
   warns: "manifest has no description, documentation, homepage or
   repository." `temper-core`'s own manifest has them.
5. **No features.** Fine today; `temper-std` already puts `net` behind
   a feature, the right model for optional I/O.

**Do users name `temper-core`?** Three of the six tours depend on it:
Argmas (`temper_core::cast`, `impl_any_value_trait!`), Kelpto
(`cast`), and Wherewith (`temper_core::Result`). Nobody names
`temper-std`. With section 1's adapter, a per-crate `Result`, and a
per-type `downcast` (or `TryFrom<ParseResult> for Args`), none would
need to, as #676's principle 3 asks.

**MSRV and edition.** `rust-version = "1.71.1"`, edition 2021. Nothing
in the output seemed to need newer; it wasn't tested on 1.71.1.
`api-compat.md` item 11 proposes 1.85 and edition 2024. One more reason
for 1.86+ later: trait upcasting would simplify interfaces (item 4).

**Warnings.** Built as path dependencies (as in a workspace, or the
tours), four of the six libraries warn, 37 warnings in all; crates.io
dependencies would have them capped:

| Library | Warnings | Kinds |
|---|---|---|
| Argmas | 6 | unused converted parameters, unused assignments |
| kelpto-md | 7 | unreachable expression, unused variables, unused assignment, fields never read |
| Ordable | 2 | unused assignments |
| Wherewith | 22 | unused variables, unused assignments, fields and methods never used |

The patterns are in "Bugs found" (item 7). Fixes: skip converting
unused parameters (and name them `_text`), declare `let unit_a: i32;`
where every path assigns before a read, and drop a value after a loop
that never ends normally. Clippy adds no warnings of its own (the
output carries 23 `#[allow(clippy::…)]`s and 4 `#[allow(dead_code)]`s).

**Docs.** No generated item has a doc comment except `init`. Running
`cargo doc` gives a list of names with signatures and no prose: nine
items for Ordable, twenty for Hrefine, and none of the libraries'
literate docs. That fails C-CRATE-DOC, C-EXAMPLE, and C-FAILURE.
Temper's IR keeps declarations' docs, so emitting `///` above exported
items, `//!` from the library's top-level prose, and "# Errors" for
functions that bubble is mostly plumbing. Rustdoc would then also run
code examples as doctests, if the libraries give Rust ones. For
docs.rs: metadata (above), a README, and the doc comments.

## 5. Speed and size

**Microbenchmarks**, release builds, against idiomatic hand-written
Rust (ms, 15 runs):

| Case | Generated | Hand-written |
|---|---|---|
| Sum 1M floats in a list | 2.0–3.0 | 1.9–4.1 (`iter().sum()`) |
| 10M `+=` on a class field | 437–1108 | 8–45 (`&mut`), 9–60 (atomic) |
| 1M appends to a string builder | 128–310 | 52–223 (same allocations), 3–11 (`push`) |
| 10M reads of a module constant | 24–79 | 4–10 (`const`) |
| 1M `compare_smart` from `&str` | 880–2037 | — |

Plain loops over lists compile to what hand-written Rust does: `while i
< len(&xs) { t += get(&xs, i) }` through `ListedTrait` inlines to the
same code as `iter().sum()`. The costs are locks and allocation: `Arc`
for each string, a lock per builder append, and two locks per field
update.

**Compile time,** a clean build of each library alone with
`temper-core` already built, two jobs, two runs:

| Library | Lines (non-test) | Dev | Release |
|---|---|---|---|
| Ordable | 11,921 | 1.1–1.9 s | 1.6–3.4 s |
| kelpto-core | 2,646 | 1.4–2.7 s | 2.7–3.0 s |
| Chromarite | 4,860 | 2.3–3.4 s | 3.7–5.4 s |
| Hrefine | 70,523 | 3.2–4.6 s | 9.1–16.5 s |
| Argmas | 9,992 | 4.0–5.4 s | 8.4–9.3 s |
| Wherewith | 16,377 | 5.4–7.9 s | 17.2–17.7 s |
| kelpto-md | 18,540 | 5.3–11.2 s | 22.6–22.7 s |

Hrefine's lines are largely data tables, which compile fast. These are
ordinary times for crates of this size, and not a reason to change
anything.

**Binary size,** a release binary calling one entry point, stripped,
less a hello world's 363 KB: Ordable 139 KB, Chromarite 291 KB, Hrefine
537 KB, Wherewith 1,012 KB, and kelpto-md 1,126 KB. Reasonable for what
they do.

## Recommendations

**Quick wins** (none breaking):

1. `Debug` for every exported type (C-DEBUG): `Display` text where
   there is one, `Type { .. }` otherwise.
2. Fix the two `ListBuilder` deadlocks in the runtime: `add_all` and
   `splice` copy their values before taking the write lock, and `sort`
   sorts a copy and stores it, so no lock is held during a callback.
3. Fix the warnings: unused converted parameters, dead initial values,
   and unreachable trailing values.
4. Give bubbles a message, at least the exported function's name, and
   keep panics' causes.
5. Emit doc comments (`///`, `//!`, "# Errors", "# Panics"), and the
   package metadata from the library's config; drop `src/main.rs` from
   published crates.
6. Re-export `Result` and `Error` per crate (`ordable::Result<T>`), and
   export a typed `downcast`, so users never name `temper_core`.
7. `Default` for zero-argument constructors; `FromStr`/`TryFrom<&str>`
   where there's a bubbling `parse`.
8. `ToList` for slices, and for `&str` collections where the element is
   `Arc<String>`; `From<HashMap>` for `Map`.
9. Literal module constants as `const`; local builders that never
   escape as plain `String` and `Vec`; scalar `var` fields as atomics,
   with `+=` as `fetch_add`.

**Medium changes:**

10. Section 1's adapter trait and `From<T> for X`, plus `X::from_fn` and
    the closure impl for one-method interfaces *(additive)*.
11. `Option<&str>` instead of `Option<impl ToArcString>` (api-compat
    item 3) *(compatible for most callers)*.
12. Builders as `X::builder(required…)` with `impl Into` setters
    *(additive; the struct-literal form can stay)*.
13. Version ranges instead of exact pins, MSRV 1.85, edition 2024
    (api-compat item 11) *(changes the MSRV)*.
14. Drop inherent `to_string` and `eq` where `Display` and `PartialEq`
    exist *(breaking in return type)*.
15. Callbacks used only during a call as `impl Fn`/`&dyn Fn` without
    `Send + Sync + 'static` *(breaking for callers passing `Arc::new`)*.
16. `Eq` for structurally compared types without floats.

**Design questions for #676 and #164:**

17. **Thread model** *(breaking either way)*: today's types are `Sync`
    but their methods aren't atomic. Either one lock per object, held
    for a whole method (atomic, but re-entry deadlocks, so callbacks
    must not be called under it), or mutable classes single-threaded
    with `Rc` and `Cell` (exact and fast, but `!Send`, so not shareable
    even in a user's `Mutex`, and async needs rework). A single-threaded
    cargo feature doesn't fit, since features unify across the graph;
    a build-time variant chosen by the library author would.
18. **Interface trait naming** *(breaking if the plain name moves)*:
    keep `XTrait` and add `Listen`-style traits, or make the plain name
    the trait users implement and rename the handle.
19. **Strings and lists in signatures** *(breaking in types)*:
    `Arc<String>` and `Arc<Vec<T>>` versus `&str`/`Arc<str>`, slices,
    and a list newtype with `IntoIterator`. `Arc<str>` halves the
    indirection; a newtype could also carry `Debug`, `Eq`, and `Hash`.
20. **Errors** *(breaking)*: #164's library-named failure types and a
    per-crate `Error` enum, with `Display` messages in Rust's style and
    a kind to match on. Recommendation 6's re-export eases the move.
21. **Hashing:** `Hash` needs a Temper-level rule agreeing with `==`.
22. **Indexes and lengths as `usize`** at the boundary, versus Temper's
    `Int` everywhere: the same question as Lua's 0-based indexes, in
    another form.
23. **A Rust-idiomatic variant:** the backend already separates
    variants by data, the first being Kotlin-compatible
    (`crates/temper-be-rust/src/lib.rs`). The breaking items above
    could land together as a second variant, so existing users opt in
    once rather than migrating several times.

## Bugs found

On temperlang/temper `13dc5669`, Rust 1.85.0, Linux. `rprobe` and `sbs`
are built from the Temper shown above and excerpted in the appendix.

1. **`ListBuilder.addAll` of itself deadlocks:** `b.addAll(b)` hangs
   (`rprobe::doubled([1, 2])`): `add_all` holds the write lock while
   `with_vec` takes the read lock. `splice` does the same.
2. **`ListBuilder.sort` holds its write lock during the comparison:** a
   comparison reading `b.length` or calling `b.add(0)` hangs, as does
   one calling a Rust object's `size` getter. One that panics leaves
   the builder poisoned. A fix is in appendix A2.
3. **Class `var` updates lose writes across threads:** `count += x`
   becomes a read lock and a write lock; four threads adding 1 100,000
   times end near 300,000. Module `var`s are updated under one lock;
   fields aren't (A8).
4. **`impl_any_value_trait!` needs a tuple struct whose `.0` is an
   `Arc`,** undocumented (`error[E0609]: no field 0 on type &Scaled`).
5. **Exact pins conflict with users' dependencies:** Ordable beside
   `indexmap = "2.12"` fails to resolve (`=2.11.4` in `temper-core`).
6. **Two libraries' outputs can't be combined by path:** "package
   collision in the lockfile" for their identical `temper-core` copies.
7. **Warnings in generated code** (37 across four libraries): unused
   converted parameters, dead initial values, and an unreachable
   trailing value after an endless `loop`.
8. **Failures have no message:** `parse_url`, `Color::parse`, and
   `Identifier::named` failures all display `bubble`.
9. **Doc comments are dropped:** `/** … */` on an exported function
   gives no `///` (A3).

## Appendix: Side by side

Each entry pairs a recommendation above (by number) with code. A second
probe library, `sbs` (about 80 lines of Temper), was built with the same
compiler, and its output is quoted below as generated, trimmed. The
proposed Rust is a hand-written crate, `sbs2`, with the same names, as
the backend could generate it; it compiles on Rust 1.85.0 with no
warnings from rustc or clippy. One user crate calls both, and the
runtime fixes were made in a copy of `temper-core` and run under today's
generated `sbs`. Errors and output are quoted as printed. Each entry
ends with whether the change keeps Temper's semantics.

### A1. `Debug` (recommendation 1)

```rust
// Temper: export class Version(public major: Int, public minor: Int), with toString
// today: no Debug. println!("{:?}", v) and assert_eq!(v, w) both give
//   error[E0277]: `Version` doesn't implement `Debug`
// proposed: the Display text, or a class's plain fields where it has no toString
f.debug_tuple("Version").field(&self.to_string()).finish()        // in Version's fmt
f.debug_struct("Counter").field("count", &self.count()).finish()  // in Counter's
// user: println!("{c:?} {v:?}") → Counter { count: 400000 } Version("1.2")
```

**Semantics:** kept; it's additive. Read stored fields only, not
computed getters, which run arbitrary Temper code. As with
`#[derive(Debug)]`, a cycle through fields would recurse.

### A2. Builder deadlocks (recommendation 2)

```rust
// Temper: b.addAll(b)  /  b.sort { (a, c) => seen += b.length; a - c }
//         /  b.sort { (a, c) => b.add(0); a - c }
// today, in temper-core: the write lock is held while reading `values`,
// and while calling `compare`. All three hang (killed by timeout, exit 124).
let builder = RefCell::new(builder.write().unwrap());
values.with_vec(&|values| { builder.borrow_mut().splice(index..index, …); });
builder.write().unwrap().sort_by(|a, b| compare(a.clone(), b.clone()).cmp(&0));
// proposed: copy the values first; sort a copy with no lock held
let copied = RefCell::new(Vec::new());
values.to_listed().with_vec(&|values| copied.borrow_mut().extend_from_slice(values));
builder.write().unwrap().splice(index..index, copied.into_inner());

let mut items = builder.read().unwrap().clone();
let len = items.len();
items.sort_by(|a, b| compare(a.clone(), b.clone()).cmp(&0));
let mut stored = builder.write().unwrap();
if stored.len() != len { panic!("ListBuilder changed length during sort"); }
*stored = items;
// user, same generated code on the fixed runtime:
//   doubled([1, 2]) → [1, 2, 1, 2]; sort_peeking([3, 1, 2]) → 9;
//   sort_growing([3, 1, 2]) panics "ListBuilder changed length during sort"
```

**Semantics:** `addAll` of itself now matches Python's output (`(1, 2,
1, 2)`). What a comparison sees of the builder mid-sort was never
defined and already differs: here it sees the unsorted items (length 3
on each of 3 calls, so 9), while Python sees an empty list (0). Growing
the builder during a sort panics, as Python does (`ValueError: list
modified during sort`). A `set` during a sort (not run) would be lost; a
version counter in the builder would catch that too.

### A3. Warnings and doc comments (recommendations 3 and 5)

```rust
// Temper: /** Says yes. */ export let accepts(text: String): Boolean { true }
// today: the doc comment is dropped, and
pub fn accepts(text: impl ToArcString) -> bool {
    let text = text.to_arc_string();  // warning: unused variable: `text`
    true
}
// proposed
/// Says yes.
pub fn accepts(_text: impl ToArcString) -> bool { true }
```

**Semantics:** kept, since `to_arc_string` is a conversion with no
effects, and docs don't run. Call sites don't change; bubbling
functions add "# Errors", as `sbs2::Version::parse` does.

### A4. Failure messages and a crate `Result` (recommendations 4 and 6)

```rust
// Temper: public static parse(text: String): Version throws Bubble {
//   let parts = text.split("."); if (parts.length != 2) { bubble() } … toInt32() … }
// today
return Err(temper_core::Error::new());
// proposed: the explicit bubble names the function; causes pass through `?`
pub use temper_core::{Error, Result};
return Err(Error::with_optional_message(Some(Arc::new("Version::parse failed".to_string()))));
// user
fn main() -> sbs2::Result<()> { let v: Version = "1.2".parse()?; … }
// "1.2.3": today  Display bubble, Debug Error(None)
//          after  Display Version::parse failed, Debug Error(Some(MessageError("Version::parse failed")))
// "1.x":   both   Display invalid digit found in string (toInt32's cause, kept)
```

**Semantics:** kept. Temper code can't see a bubble's message, so only
Rust's `Display` and `Debug` change. `sbs2::Result` is the same type as
`temper_core::Result`, so existing signatures keep compiling.

### A5. `Default`, `FromStr`, and `TryFrom<&str>` (recommendation 7)

```rust
// today: Counter::default() → error[E0599]: no function or associated item named `default`
//        "1.2".parse::<Version>() → error[E0277]: the trait bound `Version: FromStr` is not satisfied
// proposed
impl Default for Counter { fn default() -> Counter { Counter::new() } }
impl std::str::FromStr for Version {  // and TryFrom<&str>, the same
    type Err = Error;
    fn from_str(s: &str) -> Result<Version> { Version::parse(s) }
}
// user: let c = Counter::default(); let v: Version = "1.2".parse()?;
```

**Semantics:** kept; each calls the existing constructor or `parse`.

### A6. Slices and maps into the runtime (recommendation 8)

```rust
// Temper: export let longest(words: List<String>): Int
// today: pub fn longest(words: impl temper_core::ToList<Arc<String>>) -> i32
//   longest(&["a", "bbb"][..]) → error[E0277]: the trait bound `&[&str]: ToList<Arc<String>>` is not satisfied
//   longest(["a", "bbb"])      → error[E0277]: … `[&str; 2]: ToList<Arc<String>>` …
// proposed, in temper-core only; generated code unchanged
impl<T: Clone> ToList<T> for &[T] { … }
impl ToList<Arc<String>> for &[&str] { … }   // and Vec<&str>, [&str; N]
impl<K, V> From<HashMap<K, V>> for Map<K, V> { … }
impl<K, V> FromIterator<(K, V)> for Map<K, V> { … }
// user: longest(&["a", "bbb"][..]), longest(["cc"]), longest(vec!["d"]) → 3 2 1
let m: Map<&str, i32> = [("x", 1), ("y", 2)].into_iter().collect();
```

**Semantics:** kept, with one note: a Temper `Map` keeps insertion
order, and one made from a `HashMap` gets the `HashMap`'s arbitrary
order. `FromIterator` keeps the caller's order.

### A7. Constants and local builders (recommendation 9)

```rust
// Temper: export let tabStop = 4;
// today
static TAB_STOP: OnceLock<i32> = OnceLock::new();  // set in init()
pub fn tab_stop() -> i32 { *crate::support::initialized(|| TAB_STOP.get()) }
// proposed: keep the function, add a const usable in const contexts and patterns
pub const TAB_STOP: i32 = 4;
pub fn tab_stop() -> i32 { TAB_STOP }

// Temper: let sb = new StringBuilder(); … sb.append((i % 10).toString()); … sb.toString()
// today
let sb = Arc::new(std::sync::RwLock::new(String::new()));
temper_core::string::builder::append(&sb, Arc::new(i.wrapping_rem(10).to_string()));
temper_core::string::builder::to_string(&sb)
// proposed, since sb never escapes
let mut sb = String::new();
sb.push_str(&i.wrapping_rem(10).to_string());
Arc::new(sb)
```

**Semantics:** the constant's value is the same, but today its first
read runs the library's init, every module's top-level code, and a
`const` doesn't; that matters only if top-level code has effects or can
fail. The builder change keeps semantics for builders that aren't
captured, stored, returned, or passed on (`digits(12)` →
`012345678901` both ways).

### A8. Atomic fields (recommendation 9)

```rust
// Temper: public var count: Int = 0; public add(x: Int): Void { count += x; }
// today
pub fn add(&self, x: i32) { *self.0.count.write().unwrap() = self.count().wrapping_add(x); }
// proposed: count: AtomicI32
pub fn add(&self, x: i32) { self.0.count.fetch_add(x, Ordering::AcqRel); }
pub fn count(&self) -> i32 { self.0.count.load(Ordering::Acquire) }
pub fn set_count(&self, value: i32) { self.0.count.store(value, Ordering::Release); }
// user: 4 threads, 100,000 add(1) each
//   today (two RwLocks)                       290,106–299,776 (9 runs)
//   atomics, load then store (same shape)     131,227–342,304 (10 runs)
//   fetch_add                                 400,000 (all 10 runs)
```

**Semantics:** in one thread, kept exactly; `fetch_add` wraps as
`wrapping_add` does. Across threads, the framing "atomics fix lost
updates" holds only for `fetch_add`: translating today's read-then-write
into atomics keeps it racy. Only `x += e` and `x -= e` with `e` not
touching the object map to one instruction. `count = count +
listener.heard(…)` must stay a load and a store, since a
compare-and-swap loop would call the listener again. And the orderings
must be `Acquire` and `Release`, not `Relaxed`: a lock gives acquire
and release, so `Relaxed` would let another thread see one field's new
value with another's old one. On x86 both cost the same.

### A9. Implementing interfaces (recommendations 10 and 18)

```rust
// Temper: export interface Listener { public heard(n: Int): Int; public describe(): String { "listener" } }
// today: ListenerTrait (with AsAnyValue + AnyValueTrait supertraits and clone_boxed),
//        a handle Listener(Arc<dyn ListenerTrait>), and impl_any_value_trait! (section 1)
// proposed, beside today's: a plain trait, an adapter, From, and closures
pub trait Listen: Send + Sync + 'static {
    fn heard(&self, n: i32) -> i32;
    fn describe(&self) -> Arc<String> { Arc::new("listener".to_string()) }
}
struct Adapter<T>(Arc<T>);  // ListenerTrait, AnyValueTrait, AsAnyValue for Adapter<T: Listen>
impl<T: Listen> From<T> for Listener {
    fn from(value: T) -> Listener { Listener::new(Adapter(Arc::new(value))) }
}
impl<F: Fn(i32) -> i32 + Send + Sync + 'static> Listen for F {
    fn heard(&self, n: i32) -> i32 { self(n) }
}
// and Listener::from_fn(f) and Listener::downcast::<T>() -> Option<Arc<T>>
// user
struct Scaled { factor: i32 }  // named fields, no Clone, Arc, or macro
impl Listen for Scaled { fn heard(&self, n: i32) -> i32 { n * self.factor } }
let l: Listener = Scaled { factor: 3 }.into();
l.heard(2); Listener::from_fn(|n| n + 1).heard(2); l.downcast::<Scaled>().map(|s| s.factor)
// → 6 3 Some(3)
```

The closure impl and users' own impls coexist, since `Fn` is a
fundamental trait, and `From<T> for Listener` doesn't clash with std's
`From<T> for T`, since `Listener` doesn't implement `Listen`. Methods
can then take `impl Into<Listener>`.

**Semantics:** kept. Identity is the adapter's `Arc`, so clones of one
`Listener` are the same object, as today. `downcast` gives `Arc<T>`,
not `T`.

### A10. Optional strings (recommendation 11)

```rust
// Temper: export let greet(name: String, greeting: String? = null): String
// today:    pub fn greet(name: impl ToArcString, greeting: Option<impl ToArcString>) -> Arc<String>
//   greet("Ann", None) → error[E0283]: type annotations needed; works as None::<&str>
// proposed: pub fn greet(name: impl ToArcString, greeting: Option<&str>) -> Arc<String>
// user: greet("Ann", None) and greet("Ann", Some("Hi")) compile
//   but greet("Ann", Some(String::from("Hi"))) and Some(Arc<String>) no longer do:
//   error[E0308]: mismatched types, expected `&str`
```

**Semantics:** kept. Callers passing `Some(s)` with a `String` or
`Arc<String>` must write `Some(&s)` or `s.as_deref()`.

### A11. Builders (recommendation 12)

```rust
// Temper: export class Greeter(public name: String, public punct: String = "!")
// today: in a `builders` module, with a struct literal, `options()`, and Arc<String> setters
sbs::builders::GreeterBuilder { name: Arc::new("Ann".into()) }
    .options().punct(Arc::new("?".into())).build()
// proposed, beside it
pub fn builder(name: impl ToArcString) -> GreeterBuilder { … }   // on Greeter
pub fn punct(mut self, punct: impl ToArcString) -> Self { … }   // on GreeterBuilder
// user
sbs2::Greeter::builder("Ann").punct("?").build().greeting()    // → Hello, Ann?
```

**Semantics:** kept; `build` calls the constructor. Today's setters take
`Arc<String>` where the constructor takes `impl ToArcString`.

### A12. `to_string` and `eq` (recommendation 14)

```rust
// today: inherent methods beside Display and PartialEq
pub fn to_string(&self) -> Arc<String> { … }
pub fn eq(&self, other: Version) -> bool { … }
//   let s: String = v.to_string() → error[E0308]: mismatched types, expected `String`
// proposed: only the traits
// user: let s: String = v.to_string();  v == w
//   but let s: Arc<String> = v.to_string() and v.eq(w) no longer compile
```

**Semantics:** kept; the text and the comparison are the same.

### A13. Callbacks used during the call (recommendation 15)

```rust
// Temper: export let countIf(xs: List<Int>, keep: fn (Int): Boolean): Int
// today:    keep: Arc<dyn Fn(i32) -> bool + Send + Sync>
//   count_if([1, 2], |x| x > 0)      → error[E0308]: mismatched types
//   a closure counting calls in a Cell → error[E0277]: `Cell<i32>` cannot be shared between threads safely
// proposed: pub fn count_if(xs: &[i32], keep: impl Fn(i32) -> bool) -> i32
// user
let calls = Cell::new(0);
count_if(&[1, 2, 3, 4], |x| { calls.set(calls.get() + 1); x % 2 == 0 })  // → 2, after 4 calls
//   count_if(&[1], Arc::new(|x: i32| x > 0)) → error[E0277]: expected a `Fn(i32)` closure, found `Arc<…>`
```

**Semantics:** kept, where the compiler can see the function only calls
the callback (no storing, capturing, or async use).

### A14. `Eq` and `Hash` (recommendations 16 and 21)

```rust
// Temper: @auto("==") export class Version(public major: Int, public minor: Int)
// today: PartialEq only. HashSet::new().insert(v) →
//   error[E0277]: the trait bound `Version: Eq` is not satisfied (and `Hash`)
// proposed
impl Eq for Version {}
impl Hash for Version {
    fn hash<H: Hasher>(&self, state: &mut H) { self.0.major.hash(state); self.0.minor.hash(state); }
}
// user: HashSet::from([v.clone(), Version::try_from("1.2")?]).len() → 1
```

**Semantics:** kept. For `@auto("==")` classes whose fields are all
`Eq` and `Hash`, hashing the same fields agrees with `==` by
construction, so this needs no Temper-level rule; recommendation 21
remains for hand-written `==`.

### A15. Single-threaded mutable classes (recommendation 17)

```rust
// proposed, as a variant of Counter
pub struct Counter(Rc<CounterStruct>);   // CounterStruct { count: Cell<i32> }
pub fn add(&self, x: i32) { self.0.count.set(self.count().wrapping_add(x)); }
// user, on one thread: fine. Across threads:
let c = local::Counter::new();
std::thread::spawn(move || c.add(1));
// error[E0277]: `Rc<local::CounterStruct>` cannot be sent between threads safely
let m = Arc::new(Mutex::new(local::Counter::new()));
std::thread::spawn(move || m.lock().unwrap().add(1));
// error[E0277]: `Rc<local::CounterStruct>` cannot be sent between threads safely
//   = help: within `sbs2::local::Counter`, the trait `Send` is not implemented for `Rc<…>`
```

**Semantics:** single-threaded Temper is matched exactly, with
`Cell` for scalars. A `RefCell` borrow must not be held across a call,
the rule today's field locks already follow, or re-entry would panic.
But the framing "users add a `Mutex` where they share" is wrong: an
object with Temper's reference semantics has aliases, so its handle
must be `Rc`, which is `!Send` as well as `!Sync`. A user's `Mutex`
can't make it cross threads. Such objects stay on the thread that made
them, so this option is single-threaded libraries, not "`!Sync`".

### A16. Lists out (recommendation 19)

```rust
// Temper: export let doubled(items: List<Int>): List<Int>
// today: -> temper_core::List<i32>, an Arc<Vec<i32>>
//   for x in doubled([1, 2]) → error[E0277]: `Arc<Vec<i32>>` is not an iterator
// proposed: a newtype with Deref<Target = [T]>, IntoIterator for &List<T>, Debug, Eq, and Hash
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct List<T>(Arc<Vec<T>>);
// user: for x in &doubled(&[1, 2]) { … } → 1 2 1 2; println!("{:?}", doubled(&[3])) → List([3, 3])
```

**Semantics:** kept for Temper; Rust's `==` on lists is structural,
Rust-side only.

### A17. `usize` at the boundary (recommendation 22)

```rust
// Temper: public get size(): Int { items.length }; public get(i: Int): Int { items[i] }
// today: size(&self) -> i32 and get(&self, i: i32); get(-1) panics: index -1 out of bounds …
// proposed: len(&self) -> usize, and usize in, checked into Temper's Int before the body
pub fn get(&self, i: usize) -> i32 {
    let Ok(i) = i32::try_from(i) else {
        panic!("index {i} out of bounds for length {}", self.len())
    };
    temper_core::ListedTrait::get(&self.items(), i)
}
// user: bag.get(5)          panics: index 5 out of bounds for length 1
//       bag.get(usize::MAX) panics: index 18446744073709551615 out of bounds for length 1
//       bag.get(-1)         error[E0600]: cannot apply unary operator `-` to type `usize`
```

**Semantics:** kept for every index in range, and out-of-range indexes
still panic, now with the caller's index. Lengths convert from Temper's
`Int` to `usize` without loss. But nothing in a Temper type says an
`Int` is an index: the backend can do this for `length` and indexing
on lists it knows, and needs an annotation elsewhere, or an `Int` that
may be `-1` would reject callers' `-1` at compile time.

### Not shown

Recommendation 13 changes `Cargo.toml` (`indexmap = "=2.11.4"` to
`"2.11.4"`), not code. Recommendation 20 is #164's translation, already
sketched there. Recommendation 23 packages the breaking entries (A10,
A12, A13, A15, A16, and A17) as one variant.
