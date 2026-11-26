# Object building, destructuring, and pattern matching: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-24, for
[#686](https://github.com/temperlang/temper/issues/686). Suggestions
only; nothing here is decided. See also
[#297](https://github.com/temperlang/temper/issues/297) (struct
splatting).

## Where things are

- **Object literals** already build classes, including classes with
  custom or private constructors: `{ x: 1, y: 2 }` takes its class from
  the expected type, or `{ class: P, x: 1, y: 2 }` names it.
- **Shallow destructuring** works: `let { n, p } = q;`.
- **Nested destructuring** doesn't: `let { p: { x }, n } = q;` is a
  malformed declaration.
- **Spreading** doesn't parse: `{ a: 1, ...other }`.
- **`when`** matches values and types, not shapes.

## One family of features

These share syntax and semantics, so they're best designed together.

1. **Deep destructuring:** `let { p: { x, y }, n } = q;`, with renames
   (`{ p: { x: px } }`) and maybe defaults for nullable fields
   (`{ label = "" }`).
2. **Deep punning in object literals:** `{ a.b }` meaning `{ b: a.b }`,
   so `{ q.p.x, q.n }` builds `{ x: q.p.x, n: q.n }`.
3. **Spreading:** `{ ...old, x: 2 }` builds a new object from an old one
   with overrides, the common "copy with one change" that today needs a
   hand-written wither per field.
4. **Patterns in `when`:** destructuring patterns with type tests and
   maybe guards, exhaustive over sealed types:

   ```temper
   // Hypothetical.
   when (shape) {
     is Circle { r } -> PI * r * r;
     is Rect { w, h } if w == h -> w * w;
     is Rect { w, h } -> w * h;
   }
   ```

## Questions to settle

- **Spreading and constructors.** A spread must not bypass a class's
  invariants. Simplest: a spread is sugar for an object literal of the
  same class with every field named, so it goes through the same
  constructor path as `{ … }` does today; private constructors then
  limit spreads to code that may construct the class. What about fields
  that aren't constructor parameters, or private fields?
- **Which class a spread builds.** The spread source's class, unless the
  expected type or a `class:` says otherwise? Spreading across classes
  (same field names) is convenient but easy to get wrong; leaving it out
  at first seems wise.
- **Punning depth and conflicts.** `{ a.b, c.b }` names `b` twice: an
  error. Does punning take the last segment only?
- **Patterns and nulls.** How patterns treat nullable fields, and how
  this fits the flat-options rules
  ([#684](https://github.com/temperlang/temper/issues/684)).
- **Patterns and failures.** The declared-failures proposal
  ([#164](https://github.com/temperlang/temper/issues/164)) uses
  `when (e)` over sealed failure types; patterns should work the same
  way there.
- **Named construction generally.** Long positional constructors are a
  readability problem; object literals already give names. Should named
  construction become the recommended style (an editor hint, see
  [#687](https://github.com/temperlang/temper/issues/687)), and how do
  hosts without named arguments call it (builders)?

## Translation

Every feature desugars to field reads, temporaries, constructor calls,
and type tests, so every backend can support it. But many hosts have
native forms that read much better:

| Backend | Destructuring | Spread | Patterns |
|---|---|---|---|
| JS | `const { p: { x } } = q` | `{ ...old, x: 2 }` (plain objects only) | none (chains) |
| Python | none for objects | `dataclasses.replace(old, x=2)` | `match` with class patterns |
| Rust | `let Q { p: P { x, .. }, .. } = q` | `Q { x: 2, ..old }` | `match` |
| C# | deconstruction | `old with { X = 2 }` (records) | `switch` patterns |
| Java | record patterns | none (copy constructor) | `switch` patterns (21+) |
| C++, Lua | none | none | none |

So: desugar early for correctness, but keep enough information (or
recognize the desugared shapes) for backends with native forms to emit
them ("resugaring"), so generated code looks hand-written where it can.

## Suggested order

1. Deep destructuring in `let` (small, self-contained).
2. Spreading, through the existing constructor path.
3. Punning.
4. Patterns in `when`, after the flat-options and failures work settle
   what patterns must handle.

## Deferred from object spread (#694), 2026-11-26

[#694](https://github.com/temperlang/temper/issues/694) adds spread in a
deliberately narrow form: `{ ...old, a: e }`, one spread, written first,
and only for `@data` classes (every constructor parameter a public
property and nothing else, no custom constructor, no default but
`null`; `var` properties allowed unless `@imu`; methods allowed). The
broader options it set aside belong here, with the rest of object
building, since they can only loosen #694's rules (code valid under
#694 stays valid):

- **Structural spread** (the "option 2" discussed for #694): any source
  whose public properties are all constructor parameters of the target
  may be spread, so a spread is a property bag feeding named arguments,
  as object literals already are; this allows spreading across classes
  (a DTO into a domain class) and classes without `@data`.
- **Several spreads,** later ones winning, with only each property's
  final provider read; and spreads after explicit properties.
- **Loosening `@data`:** custom constructors (validation), private
  properties (spreads only inside the class), defaults other than
  `null` (which then interact with null meaning "use the default").
- **Native host data shapes** for `@data` classes (C# and Java records,
  Python dataclasses, Rust structs with visible fields and derived
  traits), with value equality, copying, and printing; reconcile with
  `@auto("==")` and `@imu`.
- **Native copying across modules** in Rust (fields visible to the
  crate) and on other backends as their class shapes allow.

### Host data shapes: settings that keep host code working

If `@data` classes later get native host data shapes, each must keep
today's host-visible behavior, so adopting them breaks no host code:

- **`@data` doesn't imply `==`.** Temper doesn't guarantee every type has
  `==` (function values, non-`Equatable` interfaces), so equality stays
  `@auto("==")`'s, added explicitly.
- **Python:** `@dataclass(eq=False, repr=False, slots=True)`.
  `eq=True` (the default) would switch `==` from identity to value
  equality and make instances unhashable unless frozen, breaking hosts
  that key dictionaries or sets by them; with `@auto("==")`, its own
  `__eq__` and `__hash__` stay. `repr=False` keeps today's printing.
  `frozen=True` would change the exception on writes; leave it out. What
  this adds (`dataclasses.fields`, `asdict`, `replace`, `match` patterns)
  is additive.
- **JS:** public data properties instead of private fields and getters,
  so a native copy can be `Object.assign(Object.create(proto), old,
  changes)`. To keep a later switch back to accessors compatible, a
  property that isn't `var` must be non-writable from the start
  (`Object.defineProperty` with `writable: false`, or `Object.freeze` for
  `@imu` classes), so no host code can come to rely on assigning it;
  reads work the same either way. JSDoc `@readonly` tells TypeScript.
