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

## Proposal

### Spread

- `{ ...old, a: e1, b: e2 }` means the object literal of `old`'s class
  that gives every constructor parameter: those written, and the rest
  read from `old`.
- `old` is evaluated once, then `e1`, `e2` in order.
- The constructor runs, so a class's checks apply.
- The copy is shallow: a `ListBuilder` property is shared.

  ```temper
  let b = { ...a, n: 1 }; b.items.add(5); // a.items has the 5 too
  ```

- For now:
  - one spread, written first;
  - `old`'s type must be a `@data` class, and the same class is built.
- Any property's value may use `orelse`:

  ```temper
  let f(): Int throws Bubble { bubble() }
  let q = { ...p, x: f() orelse -1 }; // q.x is -1; q.y is p.y
  ```

### `@data`

A class marked `@data`:

- has each constructor parameter as a property, public by default (as
  interface members are);
- has no other properties and no custom constructor;
- has no defaults but `null`;
- may have methods (with explicit visibility), supertypes, and statics;
- is an error on a `let`, a function, or an `@connected` class.

Each broken rule is reported by name.

```temper
@data class Point(x: Int, y: Int, label: String? = null) {
  public norm1(): Int { x + y }
}
@data class Box(x: Int) {
  public y: Int = 0; // error: @data class Box may declare only its constructor's properties and methods, not property y
}
```

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

## Implementation

Done on the `object-spread` branch:

- **Every backend:** a spread lowers to
  `do { let spread#1 = old; new C(…) }`. tmpl marks the copies, and
  validator rules C4 and C5 check those marks and the plain-data promise.
- **Native copies,** an optimization only, for `@data` classes without
  `var`, since otherwise a given value could change `old` between reads:
  - **Rust:** struct update, `C(Arc::new(CStruct { a: e, ..(*old.0).clone() }))`,
    in the class's own module.
  - **C++:** `std::make_shared<C>(*old)` and then field assignments.
  - **Others:** the constructor call, which reads like a careful
    hand-written copy.

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
