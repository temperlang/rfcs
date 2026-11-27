(Based on the template for Golang's [design doc TEMPLATE.md](https://github.com/golang/proposal/blob/master/design/TEMPLATE.md), part of [Golang's change proposal process](https://github.com/golang/proposal/blob/master/README.md))

# Proposal: Object spread and `@data`

Author(s): Tom P., drafted with Claude Code (Claude Opus 5.5)

Last updated: 2026-11-26

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/694 (split out
of [#686](https://github.com/temperlang/temper/issues/686)).

## Abstract

- **Spread:** `{ ...old, x: 3 }` copies an object with some properties
  changed.
- **`@data`:** a checked promise that a class is plain data, which
  spreads require.

## Background

- Copying an immutable object with one change means naming every
  property, so code grows with the class instead of the change:

  ```temper
  let moved = { class: Point, x: p.x + 1, y: p.y, label: p.label }; // today
  let moved = { ...p, x: p.x + 1 };                                  // proposed
  ```

- JavaScript, Rust (`..old`), C# (`with`), and Kotlin (`copy`) all have
  a form of this.

## Specification

Each rule names its tests: settle cases in the compiler's
`crates/temper-frontend/tests/settle/types.cases`, quoted by name, and
"spreads", the shared testkit program run on every backend.

### Spread

- **S1. Meaning.** `{ ...old, a: e1, b: e2 }` is the object literal of
  `old`'s class that gives every constructor parameter: `a` and `b` as
  written, the rest read from `old` by name. *Tests:* "a spread copies the
  properties it doesn't give"; spreads.
- **S2. Order.** `old` is evaluated once, before `e1`, then `e2`.
  *Tests:* spreads.
- **S3. Construction.** The class's constructor runs, so its checks apply.
  The copy is shallow:

  ```temper
  let b = { ...a, n: 1 }; b.items.add(5); // a.items has the 5 too
  ```

  *Tests:* spreads.
- **S4. Which spreads.** For now: exactly one spread, written first, of a
  value whose type is a `@data` class; that class is built. Anything else
  is an error. *Tests:* "spreads report what they can't copy", "a spread
  names its class only as old's", "a spread of a value whose type is
  unknown reports only why".
- **S5. Types.** The result is checked against the type wanted as the
  written-out literal would be, with the same messages. *Tests:* "a spread
  that doesn't fit the type wanted reports as its literal does".
- **S6. `orelse` in properties.** Any property's value may use `orelse`,
  not just the first one's:

  ```temper
  let f(): Int throws Bubble { bubble() }
  let q = { ...p, x: f() orelse -1 }; // q.x is -1; q.y is p.y
  ```

  *Tests:* parser cases (`edge-cases.cases`); REPL `basics.cases`.

### `@data`

- **S7. Properties.** Each constructor parameter is a property, public by
  default. There are no other properties. *Tests:* "@data classes keep to
  their rules", "@data properties are public by default".
- **S8. Construction.** No custom constructor. A `@data` object
  round-trips: constructing it from its own properties gives the same
  values. Passing `null` to a parameter with a default gives the
  default, so for a property that can hold null, any default must be
  `null`. A `var` can hold null if its type may (nullable, or a type
  parameter); any other property, only if its default may give null.
  *Tests:* "@data classes keep to their rules", "a @data property that
  can hold null has no default but null", "@data defaults that can't
  give null are fine".
- **S9. Everything else.** Methods (with explicit visibility),
  supertypes, and statics are allowed. *Tests:* "@data methods and hidden
  properties still need their visibility", "spreads with other decorators
  and shapes".
- **S10. Where.** Only on classes, and not on `@connected` ones. *Tests:*
  "@data applies only to classes".

Each broken rule is an error naming it:

```temper
@data class Point(x: Int, y: Int, label: String? = null) {
  public norm1(): Int { x + y }
}
@data class Box(x: Int) {
  public y: Int = 0; // error: @data class Box may declare only its constructor's properties and methods, not property y
}
```

## Implementation notes

Worked out while building it, on the `object-spread` branch.

- **Lowering (S1, S2):** `do { let spread#1 = old; new C(…) }` on every
  backend. A given value that's out of parameter order goes into a
  temporary first, so S2 holds.
- **tmpl marks (S1, S7, S8):** copies carry a `SPREAD_COPY` mark. Two
  validator rules check them:
  - **C4:** each mark copies its own class's field;
  - **C5:** a `@data` class's constructor only stores each parameter in
    its field.
- **Native copies (an optimization, never a change of meaning):** only
  for `@data` classes without `var`, since a given value could otherwise
  change `old` between reads.
  - **Rust:** struct update, `C(Arc::new(CStruct { a: e, ..(*old.0).clone() }))`,
    in the class's own module only; elsewhere, the constructor call.
  - **C++:** `std::make_shared<C>(*old)` and then field assignments.
  - **The rest:** the constructor call, which reads like a careful
    hand-written copy.
  - If a parameter has no same-named field, there's no native copy, just
    the constructor call.
- **Parser (S6):** a `:` after a comma in `{ }` binds like the first
  property's, but only in a list whose first entry is a property, a
  spread, or a one-word shorthand. That keeps `let x: Int, y: Int;`
  inside blocks a declaration. A comparison with main's parser over
  1,939 Temper files found only former parse errors changed.
- **Generic classes (S5):** a spread whose given values bind a type
  parameter two ways depends on the general fix for such calls on another
  branch; checked once both merge (t1143).
- **Backend fixes found by the shared tests:** Rust now ends `if` chains
  that end in a value or panic as tail values. Lua no longer assigns
  `error("panic")`.

## Rationale

- **Sugar for an object literal:** one meaning, one lowering, no new
  runtime. Invariants hold because the constructor runs.
- **`@data` required:** a spread reads properties by constructor
  parameter name, which is only reliable when the class promises its
  properties *are* its parameters. Alternatives:
  - **Any class with readable same-named properties:** structural and
    surprising (getters, renames). Deferred to #686, and relaxing to it
    later is backward compatible.
  - **No checks:** wrong copies on some classes.
- **Defaults (S8):** round-tripping is `@data`'s own promise, and
  spreads rely on it to give the same values as writing every property
  out from `old`.
- **Not `@connected` (S10):** Temper can't check that a host
  implementation keeps `@data`'s promise.
- **One spread, first:** several spreads, or spreads after properties,
  raise ordering and conflict questions; they can come later.
- **Rejected:**
  - generated `copy`/`with` methods, since they need named arguments,
    which Temper keeps to object literals;
  - per-property withers, which mean N generated methods and chained
    intermediate objects.

## Compatibility

- New syntax and a new decorator only; existing programs mean the same.
- Rust's output changed: `if` chains ending in a value or panic are now
  tail values (Wherewith's Rust output changed this way; its tests
  pass).

## Testing

- A shared `spreads` program on the interpreter and all seven backends:
  `this`, generics, sealed smart casts, `if` values, function literals,
  `orelse`, `await`.
- `@data` classes spread across modules and libraries.
- Settle, parser, REPL, and tmpl validator cases.
- A parse comparison with main over 1,939 Temper files: only former
  parse errors changed.
- Surveyed libraries' generated code compared before and after.

## Documentation

- `docs/language/builtins.md`: `@data` and spreads.
- Release notes, and the typing notes.

## Open issues

- **Several spreads,** or spreads after properties.
- **Building a different class** from a spread (`{ class: B, ...a }`).
- **Native host data shapes** for `@data`: records, dataclasses, and
  Python's `dataclasses.replace`.
- **Lua:** fast construction for trivial constructors (t1126), which
  would help spreads and object literals alike.
- **A spread changing a type argument** (`{ ...p, second: "s" }` for a
  `Two<Int>`): checked once the general fix for type parameters bound
  two ways lands.
