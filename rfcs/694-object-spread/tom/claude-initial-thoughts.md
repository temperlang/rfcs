# Object spread: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-25, for
[#694](https://github.com/temperlang/temper/issues/694), split out of
[#686](https://github.com/temperlang/temper/issues/686) (object
building). Suggestions only; nothing here is decided.

## The problem

Making a changed copy of an immutable object today means naming every
property, so the code grows with the class rather than with the change:

```temper
// Today: one changed property, every property written.
let moved = { class: Point, x: p.x + 1, y: p.y, z: p.z, label: p.label };
```

```temper
// Proposed: only the change.
let moved = { ...p, x: p.x + 1 };
```

## Proposed meaning

A spread is sugar for an object literal of the same class with every
property named, so it goes through the same constructor path as
`{ … }` does today. Concretely, `{ ...old, a: e1, b: e2 }`:

1. Evaluates `old` once, then `e1`, `e2` in order.
2. Builds the class with each constructor parameter given by the
   explicit property of that name if there is one, else by `old`'s
   property of that name.
3. Gives the same result as writing every property out.

Consequences, all from "it's just an object literal":

- **Invariants hold:** the constructor runs, so a class's checks and
  private constructors apply. A spread of a class with a private
  constructor works only where `new` of it would.
- **Defaults:** a parameter with a default takes `old`'s value, not
  the default, since `old` has one.
- **Derived properties** (getters with no constructor parameter) aren't
  copied; the constructor computes them again.
- **Shallow:** properties are copied by reference, as an object literal
  would pass them.

## Questions to settle

- **Which class is built.** Simplest: `old`'s static type must be a
  class, and that class is built, unless a `class:` key or the expected
  type says otherwise. A spread from an interface type is an error at
  first (it would need a run-time class choice).
- **Readable properties.** Each copied property must be readable where
  the spread is written (private ones only inside the class). A
  constructor parameter with no readable property of the same name is
  an error naming it.
- **One spread, first.** Start with exactly one spread, written first;
  several spreads (`{ ...a, ...b }`) and spreads after explicit
  properties can come later if wanted, since they raise ordering and
  conflict questions.
- **Across classes.** `{ class: B, ...a }` with B's parameters read
  from an `A` is convenient but easy to get wrong; leave it out at
  first (an error unless the classes are the same).
- **Mutable classes.** Same meaning (a new object, shallow); not limited
  to `@imu`, though that's the main use.
- **Syntax.** `...x` inside `{ }`, as JavaScript, Kotlin's proposals,
  and Rust's `..x` (Rust writes it last). Check the parser has room for
  `...` there (it's used for rest parameters in function types).

## Translation

Desugaring to a constructor call is correct on every backend, and
that's the first step. Some hosts have native forms that read better,
for a later "resugaring" pass:

| Backend | Native form |
|---|---|
| Rust | `Point { x: 2, ..old }` (struct update; needs fields visible) |
| C# | `old with { X = 2 }` (records only) |
| Python | `dataclasses.replace(old, x=2)` (dataclasses only) |
| JS | `{ ...old, x: 2 }` (plain objects only, not classes) |
| Java, C++, Lua | none: a constructor call |

Since generated classes aren't records or dataclasses on most backends,
the desugared constructor call is what most output will be, which is
fine: it's what a careful hand-written copy does.

## Cost

One temporary for `old`, plus the constructor call every object literal
makes; reading N unchanged properties is inherent. No runtime support.

## Alternatives

- **Generated `with`/`copy` methods** (Kotlin's `copy(x = 2)`): needs
  named arguments, which Temper keeps to object literals; spread fits
  the object-literal style it already has.
- **Withers per property** (`p.withX(2)`): linear in changed
  properties, but chained calls build intermediate objects and every
  class needs N generated methods.

## Keeping it small

One syntax form, one desugaring, no new runtime. The rest of #686
(deep destructuring, punning, patterns) stays separate.

## `@data` (Tom, 2026-11-26)

A minimal `@data` class decorator in this proposal: a checked promise
that the class is plain data (its constructor only stores its
parameters; no `var` fields; no custom getters or setters for its
fields; no nullable parameter with a non-null default), with an error
naming any rule broken. Helper methods are fine. Rules stay
conservative for now: when in doubt, a class isn't `@data`. Spreads of
`@data` classes may be translated to a host's native copy (Rust's
struct update; C++'s copy and assign; maybe Lua) as an optimization
some backends apply; that's not part of the language's meaning. Native
host data shapes (records, dataclasses) for `@data` classes are left to
a possible later RFC.
