# Flat options: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-23, for
[#684](https://github.com/temperlang/temper/issues/684). Suggestions
only; nothing here is decided.

## Summary

- The break is small. Across the new compiler's core and std and six
  Temper libraries, 61 type formals in 50 declarations, 7 `T?` uses on
  an unbounded `T` need fixing, all in 5 declarations, plus 1 nullable
  binding to a non-nullable formal. There are no null checks on a bare
  `T`, mixed bounds, `<T, W extends T>`, or nullable bounds anywhere.
- The bug is real today. `firstOrNull<T>` on a `List<String?>` holding
  `[null]` gives `null` in Python and `Some(None)` in Rust, and a null
  check on a bare `T` doesn't compile in C#.
- Suggested: make `<W extends T>` an error for now, treat `V?` as `V`
  with a hint, keep the current rule that overrides match exactly, and
  lower nullable formals in tmpl to a non-nullable formal used as `V?`,
  so that backends never handle nested options.

## Impact census

Counted from source with a script and checked by hand. "Core" and "std"
are the new compiler's `lib/core` and `lib/std` as of this date. Bindings
that inference picks are not counted. Only written-out type arguments
are.

| Where | Declarations | Agnostic | Non-nullable | Nullable | Needs a change |
|---|---|---|---|---|---|
| core | 26 | 20 | 17 | 0 | none in core itself |
| std | 4 | 4 | 0 | 0 | `OrNullJsonAdapter<T>`, and net's `Promise<String?>` |
| Argmas | 17 | 17 | 0 | 0 | 4 seeds, 4 more by propagation |
| Chromarite | 1 | 1 | 0 | 0 | none |
| Ordable | 2 | 2 | 0 | 0 | none |
| Hrefine, Kelpto, Wherewith | 0 | 0 | 0 | 0 | none |
| total | 50 | 44 | 17 | 0 | 9 formals, 1 type argument |

The compiler's functional test cases add 29 more declarations (26
agnostic and 5 non-nullable formals), with no sites that would break.

Core's 17 non-nullable formals are explicit `extends AnyValue`, on
`Equatable`, `MapKey`, the generator types, `Promise`, and
`PromiseBuilder`, and `K extends MapKey<K>` on the map types.
Everything else in core, including `List`, `Listed`, `ListBuilder`,
`Deque`, `Pair`, map values, `listedMap`, and `Never`, is already
agnostic in form. It is also agnostic in use: none of it writes `T?` or
compares a `T` to null.

**Breaks, by rule:**

- **`T?` on an agnostic `T` (rule 2): 7 uses.**
  - std's `OrNullJsonAdapter<T>`: 3 uses (`extends JsonAdapter<T?>`, and
    `encodeToJson` and `decodeFromJson`). This is the RFC's example in
    real code: an `OrNullJsonAdapter<String?>` couldn't tell JSON `null`
    from a missing value on Rust. The `@json` code that the compiler
    generates binds it only to non-null types, so `T extends AnyValue`
    is a fix that callers don't see.
  - Argmas: 4 uses (`MaybeArg.read`, `MaybeValue.read`, `Value`'s
    `fallback`, and `getMaybe`). The fix is `T extends AnyValue` on
    those, and then by rule 3 also on `option`, `optionOr`, `required`,
    and `positional`, which construct `MaybeValue<T>` and `Value<T>`.
    `ValueType<T>`, `Arg<T>`, `Values<T>`, and the rest stay agnostic.
    Argmas's docs already say that type parameters can't stand for
    nullable types, so the rule matches its intent.
- **Null checks on an agnostic `T` (rule 1): 0.** The only checks are on
  `T?` values (`OrNullJsonAdapter`'s `x == null` and Argmas's
  `fallback ?? panic()`), and the fixes above cover them.
- **Nullable bindings to non-nullable formals (rule 3): 1 written out.**
  std net's `bodyContent(): Promise<String?>`. A compiler test also has
  `new PromiseBuilder<String?>()`. Suggestion: make `Promise`'s and
  `PromiseBuilder`'s `R` agnostic. Neither uses `R?`, and a promise of a
  maybe-absent body is natural. The generator types could be agnostic
  for the same reason.
- **Mixed bounds, cycles, `<T, W extends T>`, and `extends AnyValue?`:
  0 each.**

**How the new compiler treats `<T>` today:** as `<T extends AnyValue>`.
`type_param_type` and `declared_bound` in frontend typing use `AnyValue`
when no bound is given. `fits_bound` then lets a nullable type fit an
`AnyValue` bound, to match Kotlin Temper. So today `<T>` and
`<T extends AnyValue>` are the same, and both accept `String?`. The
frontend accepts `<V extends AnyValue?>`, but tmpl's validator rejects
it ("AnyValue? can't be a bound", rule T5), so nullable formals don't
work yet on any backend.

**What the Rust and C# backends do with `T?` today.** Probe: the
RFC's `firstOrNull<T>`, an `isNull<T>(x: T)` that returns `x == null`,
and `firstOrNull` called with a `List<String?>` holding `[null]` and
with an empty one.

```rust
pub fn first_or_null<T: Clone + Send + Sync + 'static>(ls: impl temper_core::ToList<T>) -> Option<T> {
    let ls = ls.to_list();
    if temper_core::ListedTrait::is_empty(&ls) { None } else { Some(temper_core::ListedTrait::get(&ls, 0)) }
}
pub fn is_null<T: Clone + Send + Sync + 'static>(x: T) -> bool {
    Some(x.clone()).is_none()
}
```

```csharp
public static Optional<T> FirstOrNull<T>(IReadOnlyList<T> ls)
{ if (ls.Count == 0) { return Optional<T>.None; } else { return ls[0]; } }
public static bool IsNull<T>(T x) { return !x.HasValue; }
// call site: string? a = Optional.OrNull<string>(FirstOrNull(ls));
```

- **Rust nests.** `T` binds `Option<Arc<String>>`, so the result is
  `Option<Option<…>>`, and `[null]` gives `Some(None)`, which is not
  null. `isNull` on a bare `T` wraps the value and is always false. A
  demo that counts the nulls it finds scored 10 in Rust and 111 in
  Python, so the two backends disagree. (One `isNull(None)` call needed
  a type annotation by hand before the Rust would compile.)
- **C# flattens by accident.** `Optional<T>`'s implicit conversion maps
  `null` to `None`, so `firstOrNull` matches Python. `IsNull<T>`
  doesn't compile, though (CS1061, `T` has no `HasValue`).

## Interactions

**Optional parameters.** tmpl types a parameter with a default as `T?`,
where null means "use the default". On an agnostic `T`, that is the
banned `T?` in disguise. Probe: `withDefault<T>(x: T, y: T = x)` called
as `withDefault<String?>("a", s)` with `s` null:

- Python returns `"a"`: the explicit null is taken as missing.
- Rust doesn't compile, because it wants `Option<Option<…>>`.
- C# doesn't compile (CS1750, `Optional<T> y = null`). That failure is
  separate from this RFC but shows up in the same place.

Suggestion: a default on a parameter of agnostic type is an error. Ask
for `T extends AnyValue`, where `T?` is flat and "null means the
default" is well defined. None of the code counted above has one. Also
document that a nullable parameter with a default can't be given an
explicit null, which is today's semantics everywhere.

**RFC 164's declared failures.** The middle ground keeps a result type
internal (`T throws E` as `Result<T, E>`), and results can't be held.
Points that touch this RFC:

- `Result<Option<T>, E>` is not a nested option, so `T? throws E` is
  fine.
- `f() orelse null` and `x ?? null`, for an `f` returning an agnostic
  `T`, infer `T?`. They should report the same error as writing `T?`,
  with a message that points at the `orelse`. Today
  `tryOrNull<T>(f): T?` lowers in Rust to
  `Ok(Some(f()?)).unwrap_or(None)`, which nests for a nullable `T`.
- RFC 164 relies on "`R` never binds a result, since results aren't
  `AnyValue`". Once agnostic formals have no implicit `AnyValue` bound,
  their implicit range should be stated as "any value type, nullable
  or not". That still excludes `Void`, results, and a bare `Null`, so
  RFC 164's rule keeps working. The frontend's `unify` already skips
  `Never`, `Null`, and `Void`.
- RFC 164's option 0 (no failures) moves more APIs to `R?`. That makes
  `extends AnyValue` more common in generic code, so the error message
  and the quick fix matter more.

**`Never<T>`, `Void`, and `Empty`.** `Never<@out T>` is agnostic and
fine: `Never<Foo?>` used as a `Foo?` is still flat. `Void` already can't
bind a type parameter. `Empty` is a non-nullable class, so `Empty?` is
flat. The RFC's argument against `Void` having unit semantics holds.

**Invariance.** The new compiler treats type parameters as invariant
(team decision 2026-10-28). The frontend doesn't yet report what only
Kotlin's variance accepts. That leniency now fails later: returning a
`List<String>` as a `List<String?>`, or a `fn (): String` as a
`fn (): String?`, passes the frontend but fails tmpl's validator (T3,
"is List<String>, but should be List<String?>") on every backend. On
an optioning backend, either conversion would need a copy or a wrapper.
Suggestions: say in the RFC that assignable-to (`X <~: X?`) applies only
at the top level and never through type arguments. Then rule 7 is moot
while type parameters stay invariant. Have the frontend report
`C<X>` as `C<X?>` instead of leaving it to tmpl.

**C#.** The C# backend writes `T?` for a type parameter `T` as the
runtime's `Optional<T>`, because `T` might be a value type. Possible
improvements under this RFC:

- emit `where U : notnull` for non-nullable formals, which helps
  nullable reference type warnings at no cost;
- where a formal's bound is a Temper class or interface that no core
  value type implements, emit `where U : class` and use a plain `U?`
  instead of `Optional<U>`, which is friendlier for host callers;
- for nullable formals, bind the un-optioned type and write
  `Optional<V>`, as the RFC's Rust examples do.

**Rust.** The generated code already bounds every type parameter by
`Clone + Send + Sync + 'static`, so `Some(x.clone())` wrapping needs
nothing new. An `Option<Arc<_>>` is the size of a pointer, so flat
options cost nothing at run time. The point of the RFC is meaning, not
speed.

## Positions on the open issues

**`<T, W extends T>`: make it an error for now.** It appears nowhere in
the code counted above. The new compiler can't check it yet: a bound
that is a type parameter is left unknown, and the probe
`pairUp<T, W extends T>(a: T, b: W): List<T> { [a, b] }` fails in tmpl
(T3, `List<AnyValue>` where `List<T>` was wanted). Making `W` agnostic
would also allow binding `T = String?` and `W = String`, where `W`'s
values need wrapping when used as `T`. The type system can't see that
wrap, since `W` is "a subtype of `T`". If a use appears, allow it later
with `W` agnostic and a wrap at that subtype edge. Allowing it later is
a compatible change, while banning it later would break code.

**`V?` for a nullable `V`: allowed, with a hint that it's redundant.**
It means the same as `V`, and code that edits types (adding `?` to a
return type, for example) shouldn't have to know which kind a formal
is. tmpl normalizes it away, since its types already never nest
`Nullable`. Making it an error buys nothing.

**Signature narrowing in overrides: keep exact matching.** The new
compiler already requires an override's signature to match exactly,
after substituting type arguments. It rejects `f(): String` for
`f(): String?` and `f(): Dog` for `f(): Animal`, with Kotlin's "should
be … to correctly override" message. Draft rule:

> An override's parameter and return types must equal the overridden
> member's, after substituting the supertype's type arguments,
> including nullability. A nullable formal `V` bound to `Foo?` counts
> as `Foo?`. To give a narrower result, add a separate member.

A bridge could relax this later. tmpl would emit the override as a
wrapper that applies `AsNullable` around a private implementation.
That shape works on every backend, including those without
overloading, but it waits until real code asks for it.

## Implementation notes for the new compiler

**Frontend typing:**

- Store a kind per formal (agnostic, non-nullable, or nullable) next to
  `Types::bounds`. Compute it once when bounds are evaluated, following
  type-parameter bounds with an on-stack set to report cycles.
  `set_bound` currently drops bounds that are type parameters (it sets
  them to `UNKNOWN`) for the same reason, and could report cycles
  instead.
- Stop putting in `AnyValue` for a missing bound (`type_param_type`,
  `declared_bound`, `core_type_formals`). Remove `fits_bound`'s special
  case that lets a nullable type fit `AnyValue`. Agnostic formals then
  accept any type, non-nullable formals reject `X?`, and nullable
  formals take `X` as `X?`. That last one is a promotion, which `unify`
  already does when it joins `Dog` and `Dog?`.
- Checks: in `eval_type`, `Nullable(Param)` of an agnostic formal is an
  error. The null-fact conditions (`== null`, `!= null`, `??`, and `is`
  on an agnostic expression) are errors. So is `Types::join` producing
  `T?` from `T` and null, which covers `orelse null` and `if … else
  null`. Report the bindings in the RFC's table at the existing bound
  checks (`check_generic_call` and the type-argument check). Report
  mixed bounds as "pick a lane".
- Inference fallback: an unbound formal currently binds to its bound
  (a literal's result binds to `AnyValue`). Keep `AnyValue` for
  agnostic formals, and use the nullable form only if a null was seen.

**tmpl: lower nullable formals once.** Write `<V extends Foo?>` as
`<V extends Foo>` and every use of `V` as `V?`. A binding `Foo?`
becomes `Foo`, with `AsNullable` where a `Foo` value meets a `V`.
Then:

- tmpl's existing invariant, that `Nullable` never wraps a nullable
  type, covers formals too, and `AsNullable`, `NonNull`, `IsNull`, and
  `Coalesce` already make every wrap and unwrap explicit;
- the validator's T5 can keep "a bound is a class or interface" once
  `?` is moved off the bound;
- no backend handles nested options or works out where to insert
  wrapping. Null-singleton backends print `V?` exactly as they print
  any `T?`;
- `V?` is `V` by construction.

Add a validator rule that `Nullable(TypeParam p)` appears only for a
non-nullable `p`. That catches any frontend gap before a backend sees
it.

**Tests** that complement the RFC's list:

- `firstOrNull` on `[null]` and `[]` gives the same answers on every
  backend (the probe above, as a cross-backend functional test);
- `f() orelse null` and `if (c) { x } else { null }` on an agnostic `T`
  are rejected, with the message pointing at the `orelse` or `if`;
- a default on a parameter of agnostic type is rejected, and one on a
  non-nullable `U` passes on Rust and C#;
- `OrNullJsonAdapter<String?>` is rejected, and the generated `@json`
  adapters still pass;
- `Promise<String?>` passes once `R` is agnostic;
- `List<String>` as `List<String?>` is reported by the frontend, not
  by tmpl;
- overrides that differ only in nullability are rejected (a test that
  pins today's behavior);
- a nullable formal bound to a non-null concrete type is promoted, and
  Rust emits `either_or::<String>` with `Some(…)` at the argument;
- the validator rejects a `Nullable(TypeParam)` of an agnostic formal
  (a negative tmpl test).

## Migration

- **Size:** 9 formals gain `extends AnyValue` (1 in std, 8 in Argmas),
  and 2 core formals (`Promise`'s and `PromiseBuilder`'s `R`) lose
  theirs. The other five libraries need nothing.
- **Automatic fix:** possible and simple. Start from each agnostic
  formal whose scope writes `T?` or null-checks a `T`, and add
  `extends AnyValue`. Then repeat: any agnostic formal bound to a formal
  that is now non-nullable also gets it. That reproduces the Argmas fix
  exactly (4 seeds, 4 propagated). The fix needs a person only where a
  call site binds a nullable type to a formal that is now non-nullable.
  None of those appear in the counted code. An editor quick fix for the
  error ("add `extends AnyValue` to `T`") covers most of it.
- **Staging:** the counted code is small and beta, so one change can
  update core, std, and the libraries and make these errors right away.
  A warning period helps only for outside users. If there are any, one
  release of warnings with the quick fix is enough.
