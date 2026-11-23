# Proposal: Flat options

Author(s): Mike S.

Last updated: 2026-11-23

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/684

## Abstract

Temper needs to translate nullable types both to languages that represent a lack of a value with a singleton like `null`, and to languages that use option types.
The two agree, except when options nest.

This proposal sorts type formals into three kinds based on their upper bounds: those agnostic as to whether they bind to a nullable type, those that are nullable, and those that are not.
Static checks on type formals, and on how they're used, keep Temper code from needing nested options.

## Background

Optionality is important in programming languages.
It allows saying "I haven't computed this yet, but I might," or, for an input to a function, "I don't have this kind of input, make do without."
It also affects outputs: a function can say "normally I'd be able to give you something, but for the combination of inputs you gave me, or because of some externality, I don't have a result for you."

In Temper, an optional type has a question mark at the end, and the keyword `null` represents a lack of something.
`Foo?` admits all the values that `Foo` admits, and also the special value `null`, which can be differentiated from the other values: `someFoo != null`.
A temporary whose type is `String?` can be assigned a `String`, the result of an expression whose type is `String` or `String?`, or `null`.

The languages we need to translate to fall into two camps.

Some use `null` or a similar singleton to represent a lack.
JavaScript has `null`, and also `undefined`.  They have slightly more nuance, but it shouldn't matter since JavaScript libraries and programs tend not to be consistent about which they use.
Java has `null`, C has `NULL`, and Go has `nil`.
In all of these there's a singleton value, and you just don't use that if you actually have something usable.

The more functional languages have option types: OCaml's `'a option`, Rust's `Option<T>`, and Java's `Optional<T>`, bolted on rather late.
An option type is a discriminated union, typically with two variants.
`None` is like `null`: there's nothing there, and the `None` value holds nothing.
`Some` holds a value: a string option is either `None` or `Some` of a string.

Temper has some *optioning backends*, where a nullable type translates to an option type: Rust, C# (strangely), and eventually OCaml.
C# has `null`, but doesn't allow its use with type parameters that can bind to both value and reference types.
(Swift calls its nullable types option types, but that seems to be marketing.)

For many things, it's not hard to take code that uses one and switch to the other, but there is a semantic gap: nested options.
A `string option option` in OCaml, or an `Option<Option<String>>` in Rust, distinguishes `None`, where the outer option is `None`, from `Some(None)`, where there is something, but that something is `None`.
With a singleton, both are `null`.

Type parameters are the tricky part.
Without this proposal, any type parameter can bind to anything within its upper bounds, including nullable types.

```ts
let firstOrNull<T>(ls: List<T>): T? {
  if (ls.isEmpty) { null } else { ls[0] }
}

let ls: List<String?> = [null];
firstOrNull(ls); // Is this `None` or `Some(None)`?
```

Translated to Rust, `firstOrNull` returns an `Option<Option<String>>` here: `Some(None)`, which is distinguishable from the `None` for an empty list.
Translated to JavaScript, both are `null`.

For a type parameter `T`, an optioning backend needs to know:

- Is `T` an option type?  Do we need to pack an option when passing a value into a `T`, or unpack one when the return type is `T`?
- Could the type `T?` introduce a nested option type?
- Can a `T` be `null`?  We want to avoid asking `.is_some()` when the value's representation is not statically known to be an option.

### Goals

**Support optioning languages** by translating nullable types even where there's no `null` value, or where, as in C#, it can't be used with type parameters that bind to both value and reference types.

Provide **flexible container types** like `List<String>` and `List<String?>`, for bundling results and for intermediate computations.

Provide **consistent semantics for null checks**: `x == null`.  Specifically, avoid option nesting that would lead `Some(None)` to be spuriously recognized as distinct from `null`/`None`.

Clarify **which subtype-like relationships are translatable**.  Temper uses a number of type relationships related to subtyping.  What restrictions do we need to put on them, and which cause translation problems?

## Proposal

### Three kinds of type formals

Every type formal definition must fall into one of three cases:

1. **Agnostic**: the type formal has no `extends` clause.
   It may bind to a nullable type or to a non-nullable type.
   On a backend like Rust, it might bind to a Rust option type or to a type that is not an option type.
   Temper's `List<String>` could be a Rust `Vec<String>`, but `List<String?>` would be a `Vec<Option<String>>`.
2. **Nullable**: the `extends` clause is non-empty, and all of its upper bounds are nullable.
   An upper bound is nullable when it is a question mark type, or when it's a reference to a type formal that is itself nullable by these rules.
3. **Non-nullable**: the `extends` clause is non-empty, and every upper bound is non-nullable.
   An upper bound is non-nullable when it's a reference to a type formal that is non-nullable by these rules, or when it is not a reference to a type formal and does not have a question mark.

This needs no new syntax.  The `extends` clauses are enough, as long as we do not infer an *AnyValue* upper bound for a type formal without an explicit one, and make it illegal to mix nullable and non-nullable upper bounds.

Below, `T` names an agnostic type formal, `U` a non-nullable one, and `V` a nullable one.

- Values of an agnostic type could be `null`, so it does not make sense to call methods on them.
- `U?` is a distinct, usable type.
  You can call methods on values of type `U` based on its upper bounds.
- `V` translates to an option type on optioning backends, and it makes sense to ask whether a `V` is `null`.
  Inside an `if (myV != null)` context, we could allow `myV.method()` based on its upper bounds with nullity erased, because it's safe to unwrap the option on optioning backends.

A capital letter inside angle brackets, `<X>`, refers to a type parameter declaration.
A single capital letter name without the angle brackets, `X`, denotes a use of that declared type in the signature or body of the declaring type or function.

Since a type parameter can have a previously declared type parameter as an upper bound:

| Declaration | Kind of `W` | Because |
| ---- | ---- | ---- |
| `<W>` | agnostic | `W` has no upper bounds |
| `<W extends AnyValue>` | non-nullable | the upper bound is not nullable |
| `<W extends AnyValue?>` | nullable | the upper bound is nullable |
| `<V extends AnyValue?, W extends V>` | nullable | `W`'s upper bound is nullable |
| `<U extends AnyValue, W extends U>` | non-nullable | `W`'s upper bound is not nullable |
| `<T, W extends T>` | unclear; see *Open Issues* | `W`'s upper bound is neither nullable nor non-nullable |

### Static checks on type formal definitions

There are two main ways a type formal definition could fail to fall into one of those cases.

The upper bounds could mix nullable and non-nullable types.
The error message for that just needs to say "pick a lane."

```ts
let f<T extends Foo & Bar?>(x: T): Void { ... } // ERROR: pick a lane
```

The type formal could have an upper bound that is a reference to a type formal that transitively refers back to the first: `T extends U` and `U extends T`.
It's not clear whether `T` is nullable until we know whether `U` is, and vice versa.
It may be difficult in practice to write that, since `U` is not in scope at `T extends U`, but weirder things have happened in compilers.
In general, cyclicity in `extends` clauses is something we want to reject early because other analyses might not terminate if we don't come down hard on it.

### Rules

With `T` agnostic, `U` non-nullable, and `V` nullable:

1. No asking if a `T` is `null`.
   Assuming erasure at some level, we can't translate that.
   If the actual binding is not a nullable type, the answer is always no, but we can't turn that into instructions.
2. `T?` is an illegal type, since it could lead to nested option types.
   Often it would not, but sometimes it does, and that's the thing we've got to avoid.
   This rules out `firstOrNull<T>` above; its `<T>` would have to be non-nullable.
3. No binding a nullable type to a non-nullable type formal.  This includes `T` and `V`.
4. No asking if a `U` is `null`, but it's ok to ask if a `U?` is `null`.
5. `V?` is a semantic no-op: `V` already is nullable.
   It could be banned as a type or treated as equivalent to `V`.
6. Binding `T` to a nullable type formal is illegal, since it's not clear when to insert option wrapping and unwrapping instructions.
7. Given a contravariant, non-nullable definition like `<in X extends AnyValue>`, binding `X` to a nullable type formal is illegal, since option types are covariant on their type parameter.

To make clear what's not prohibited by the rules:

- `U`, `U?`, and `V` can bind to an agnostic type formal.
- `U?` can bind to a nullable type formal.  A contravariant `U` cannot.
- Any agnostic type formal reference can bind to another agnostic type formal.
- Any non-nullable type formal reference can bind to another non-nullable type formal.
- Any nullable type formal reference can bind to another nullable type formal.
- Any concrete type can bind to an agnostic type formal, e.g. `String` and `String?`.
- Any non-nullable concrete type can bind to a non-nullable type formal, e.g. `String`.
- Any nullable concrete type can bind to a nullable type formal, e.g. `String?`.

### Agnostic type formals

Consider `List<T>` translated to Rust.
`List` corresponds to Rust's vector type, and a vector can hold options or non-options.
That doesn't matter to our translations or connections of `List`'s methods; they can give you the thing at index three regardless of whether it's an option.
So `List`'s `<T>` is agnostic about whether what we're storing is an option on a backend that uses them.

```ts
let listOf2<T>(a: T, b: T): List<T> { [a, b] }
```

The optioning Rust backend doesn't need to care whether a `T` is an option.

```rust
fn list_of_2<T>(a: T, b: T) -> Vec<T> { vec![a, b] }
```

### Non-nullable type formals

`firstOrNull` works with a non-nullable type formal.
It uses `U?` as a distinct type for its return type.

```ts
let firstOrNull<U extends AnyValue>(ls: List<U>): U? {
  if (ls.isEmpty) { null } else { ls[0] }
}
```

Converting a `U` to a `U?` needs a wrapping instruction.

```rust
fn first_or_null<U: Clone>(ls: &Vec<U>) -> Option<U> {
  if ls.is_empty() { None } else { Some(ls[0].clone()) }
}
```

### Nullable type formals

A nullable type formal binds only to nullable types, so on a backend that uses options to represent nullable types, its representation is always an option.
Code can ask whether a value of its type is `null`, cast away nullity, and do all those things.

The use case is basically anywhere we want to check whether something is present, and maybe supply a default.
For example, our optional input scheme represents missing inputs as `null`, which lets us substitute the result of evaluating the input's default expression.

```ts
let eitherOr<V extends AnyValue?>(a: V, b: V): V {
  if (a != null) { a } else { b }
}
eitherOr<String?>(null, "${f()}");
eitherOr("${f()}", "${g()}");
```

On Rust, the type parameter binds to the un-optioned type.

```rust
fn either_or<V>(a: Option<V>, b: Option<V>) -> Option<V> {
  if a.is_some() { a } else { b }
}
either_or::<String>(None, Some(...));
either_or::<String>(Some(...), Some(...)).unwrap();
```

Where a non-nullable type would bind to a nullable type formal, we need to insert wrapping and unwrapping instructions, or just have inference promote the binding to the nullable type, as for the second call above.
Our implicit cast detection should handle that.

### Example: first non-null element

Here's an extension function with both a nullable and a non-nullable type formal.
It is not a method of `List`; `List`'s `<T>` is agnostic.

```ts
@extension("firstNonNull")
let firstNonNull<U extends AnyValue, T extends U?>(ls: List<T>): U throws Bubble {
  for (let el of ls) {
    if (el != null) {
      return el;
    }
  }
  bubble()
}
```

`U` has an upper bound of `AnyValue`, so it's non-nullable, and we want a non-nullable return type.
The list element type, `T`, has an upper bound of `U?`, clearly nullable.

It type checks under these rules.
Binding `List`'s agnostic `<T>` to a nullable `T` is fine.
We can ask whether elements are `null`, and once we know one isn't, safely cast away its nullity and return it as a `U`.

On a backend that uses option types, `T` is an `Option<U>`, and the check that the element is not `null` unpacks the option.

### Core and std types

Part of this is a breaking change.
We need to go over all of our existing std stubs and core template code and have them follow the new discipline as far as upper bounds.
Some methods might need to move out of our container types and become extension functions, like `firstNonNull` above, or a `List.getOrNull`, so that they can declare their own type formals with stricter bounds.

### Subtype-like relationships

#### Plain old subtyping

If `X <: X?`, then a translation of `X` to a language with subtypes should preserve the relationship: the translation of `X` should be a subtype of the translation of `X?`.

That's trivially not the case on optioning backends: `String <: String?`, but `String </: Option<String>`.

#### Assignable to

A *String* is not an *Option\<String>*, but it is assignable to one if we insert a wrapping instruction.

Assignable-to is used in static checks and in type inference.
For inferring types, we can treat `X?` as like a supertype of `X`, using `<~:` to mean assignable-to/subtype-ish, though we need to insert unpacking instructions later.

```ts
let foo: Foo = f();
let temporary;
let fooOrNull: Foo?;
temporary = foo;
fooOrNull = temporary;
```

To solve the type of *temporary*, it helps to know that *Foo <~: temporary's type <~: Foo?*, which makes sense when *Foo <~: Foo?*.

This assignable-to but not subtype-of relationship is exactly where we need to insert boxing and unboxing instructions.
The above has two valid translations on an optioning backend:

```ts
// Translation 1: temporary is an Option
let foo: Foo = f();
let temporary/*: Option<Foo>*/;
let fooOrNull: Option<Foo>;
temporary = Option.some(foo);
fooOrNull = temporary;

// Translation 2: temporary is not an Option
let foo: Foo = f();
let temporary/*: Foo*/;
let fooOrNull: Option<Foo>;
temporary = foo;
fooOrNull = Option.some(temporary);
```

Most type solvers prefer lower bounds to upper bounds where both are available, so translation 2 is more likely.

#### Signature narrowing in overrides

When a subtype overrides a method, can it widen input types and narrow output types?

```ts
interface I {
  public f(i: Int): String?;
}
class C extends I {
  public f(i: AnyValue?): String { "Hello" }
}
```

On Java, a non-optioning backend, that's fine, but we'd need to insert a bridge to widen Java `int`, a value type, to `@Nullable Object`, a reference type.

```java
interface I {
  @Nullable String f(int i);
}
class C implements I {
  @Override
  public @Nonnull String f(int i) {
    return f((Object) i);
  }
  public @Nonnull String f(@Nullable Object i) {
    ...
  }
}
```

On an optioning backend we run into the same subtype problem: an option is not a supertype of its type parameter.

```ts
interface I {
  f(i: Int): Option<String>;
}
class C extends I {
  public f(i: Option<AnyValue>): String { "Hello" }
}
```

Since *Int </: Option\<AnyValue>* and *String </: Option\<String>*, those signatures are not compatible between *I*'s declaration and its subtype *C*'s.
When a narrower return type like `SomeType` overrides a `SomeType?`, we can detect that using the same kind of signature adjustment checks we need for Java and C#.
Optioning backends that allow method overloading could bridge like the Java above, but how overloading works is very language specific and potentially creates other translation hazards.

TODO: draft a rule for signature narrowing.

#### Signature specialization

```ts
interface I<T extends AnyValue?> {
  f(): T;
}
class C(public x: String?) extends I<String?> {
  // The output type works because
  // I's <T> is String? in this context.
  public f(): String? { x }
}
```

The bindings table under *Testing and examples* goes through each of the three kinds of type formals on the left, against five kinds of bindings on the right.
By including type parameters among the bindings, it also covers when one type parameter can have another as an upper bound.

## Rationale

Nested options are the one place where translating between the two camps of languages has a semantic gap.
Ruling them out at type formal definitions, and where type formals are used, lets the `null` camp keep using its singleton and the option camp use options without either changing meaning.

The agnostic case exists so that containers like `List` don't need to care what they store.

An earlier sketch marked each type formal declaration as agnostic, non-nullable, or nullable with new syntax, and treated an unmarked `<W>` as non-nullable, inferring an implicit upper bound of *AnyValue*.
The `extends` clauses are sufficient to break type formals into the three kinds, so no new syntax is needed, and an empty `extends` clause is how to declare an agnostic one.

### `Void`, `Empty`, and `null`

Could Temper's *Void* type have *Unit* semantics while preserving the semantics and translatability of `x == null` where `x` could be `null`?

`null` and `void` are both singleton values.
*Unit* semantics allow zero-value-returning functions to have a result: a special, stateless, singleton "unit" value that is the output of any function called for its side effect.
That's important in generic programming; when every function has exactly one result, it's easier to use functions with higher-order functions.

In Java, `void` cannot bind to a type parameter, but the pseudo-reference-type `java.lang.Void` can.
Using a void-returning function-like type, e.g. *Runnable*, where a unary function like *Supplier\<Void>* is expected requires adapting it.

```java
Runnable r = () -> {};
Supplier<Void> s = () -> { r.run(); return null; };
```

Short answer: no, because many dynamic languages conflate the concepts of null and void.

- Python3 uses `None` for both.
- JavaScript uses `undefined` for `void`, and assigning distinct semantics to `null` and `undefined` makes for brittle library APIs.
- Lisps often treat the empty list, `nil`, as both.

If *Void* had *Unit* semantics, then `Void?` would be a mentionable type, and at runtime we'd need to distinguish the translation of `void` from the translation of `null`.
This Temper code would not preserve its semantics:

```ts
let f<T extends AnyValue>(x: T?, y: T?): Int {
  var n = 0;
  if (x != null) { n++ }
  if (y != null) { n++ }
  n
}
f(void, null) == 1
```

It would translate to Python3 as:

```py
def f[T](x: T | None, y: T | None) -> int:
    n = 0
    if (x is not None): n += 1
    if (y is not None): n += 1
    return n

f(None, None) == 1
```

So *Void* may not bind to type parameters.
Temper instead has a singleton *Empty* type, whose value, from `empty()`, is distinct from `null`.
*Empty* is like *Unit*, and translates to it on typed functional language backends.
A function that would be effectively *Void* can return *Empty* instead, so its return type can bind to a type parameter.
*Empty* is non-nullable, so `f(empty(), null) == 1` above, and `Empty?` is a flat option like any other.

## Compatibility

This will break existing code that writes `T?` for a `T` with no upper bounds, or that compares a value of such a type to `null`.

Std stubs and core template code need to follow the new discipline (see *Core and std types* above), which may move some methods into extension functions.

## Implementation

- `TypeFormal` upper bounds need to be able to be nullable, e.g. `AnyValue?`, and need to be `Type2`s, since a bound can be a reference to another type formal.
- Stop inferring an *AnyValue* upper bound for type formals without an explicit one.
- Classify each type formal definition as agnostic, nullable, or non-nullable, rejecting mixed bounds and cyclic `extends` clauses.
- Check type phrases like `T?`, `null` checks, casts that remove nullity, and type bindings against the classification.
- Go over std stubs and core templates, adjusting bounds and moving methods into extension functions where needed.

## Testing and examples

Tests should include, with the error messages expected:

- mixed nullable and non-nullable upper bounds fail with "pick a lane",
- cyclic `extends` clauses fail,
- `T?` for an agnostic `T` fails, as in `firstOrNull<T>` above,
- comparing a value of an agnostic type to `null` fails,
- each of the bindings in the table below, passing or failing as it says,
- `firstNonNull` passes, and on a backend with option types, unpacks options,
- `firstOrNull<U extends AnyValue>` passes, and `firstOrNull` of a `List<String?>` fails.

### Bindings

Each row is a type formal declaration on the left, like `I`'s `<T>` in `interface I<T> { f(): T; }`, and a binding for it on the right, like `Foo` in `class C extends I<Foo>`.

On the left, `<T>` is agnostic, `<U extends Bar>` is non-nullable, and `<V extends Bar?>` is nullable.

On the right:

- `Foo`: a non-nullable type.
- `Foo?`: a nullable type.
- `W`: a reference to a type parameter declared in the same or a narrower scope than the left parameter, like `class C<W> extends I<W>`.
  `<W>` is agnostic, `<W extends Foo>` non-nullable, and `<W extends Foo?>` nullable.

| Declared | Bound to | Verdict | On an optioning backend |
| ---- | ---- | ---- | ---- |
| `<T>` | `Foo` | OK | `I<Foo>` |
| `<T>` | `Foo?` | OK | `I<Option<Foo>>` |
| `<T>` | `W` from `<W>` | OK | `I<W>` |
| `<T>` | `W` from `<W extends Foo>` | OK | `I<W>` |
| `<T>` | `W` from `<W extends Foo?>` | OK | `I<Option<W>>`; the option shows up in the extends clause |
| `<U extends Bar>` | `Foo` | OK | `I<Foo>` |
| `<U extends Bar>` | `Foo?` | Banned | |
| `<U extends Bar>` | `W` from `<W>` | Banned | |
| `<U extends Bar>` | `W` from `<W extends Foo>` | OK | `I<W>` |
| `<U extends Bar>` | `W` from `<W extends Foo?>` | Banned | |
| `<V extends Bar?>` | `Foo` | Banned; just use `Foo?` | |
| `<V extends Bar?>` | `Foo?` | OK | `I<Foo>`, with `f(): Option<Foo>` |
| `<V extends Bar?>` | `W` from `<W>` | Banned | `f(): Option<W>` could nest |
| `<V extends Bar?>` | `W` from `<W extends Foo>` | OK with `W?` as the binding | `I<W>`, with `f(): Option<W>` |
| `<V extends Bar?>` | `W` from `<W extends Foo?>` | OK | `I<W>`, with `f(): Option<W>` |

For example, here's an agnostic `<T>` bound to a nullable `W`, and its translation.

```ts
interface I<T> {
  f(): T;
}
class C<W extends Foo?> extends I<W> {
  f(): W {...}
}

//----

interface I<T> {
  f(): T
}
class C<W extends Foo> extends I<Option<W>> {
  f(): Option<W> {...}
}
```

And a nullable `<V>` bound to `Foo?`, where `V` translates without the option.

```ts
interface I<V extends Bar?> {
  f(): V;
}
class C extends I<Foo?> {
  f(): Foo? {...}
}

//----

interface I<V extends Bar> {
  f(): Option<V>
}
class C extends I<Foo> { // No option here
  f(): Option<Foo> {...}
}
```

A nullable `<V>` bound to an agnostic `W` is banned because the translation can't say whether `f`'s output is a nested option.

```ts
interface I<V extends Bar?> {
  f(): V;
}
class C<W> extends I<W> {
  f(): W {...}
}

//----

interface I<V extends Bar> {
  f(): Option<V>
}
class C<W> extends I<W> {
  f(): Option<COULD_NEST> {...}
}
```

## Documentation

The reference documentation for type formals needs to explain the three kinds, with the background on nested options above, and explain how to fix "pick a lane" errors and uses of an agnostic type formal that need a nullable or non-nullable one.

## Effect on Backends

Backends whose target languages use a `null`-like singleton should not need changes.

Backends that use option types can rely on there being no nested options.
A nullable type formal's representation is always an option, and it binds to the un-optioned type; an agnostic one's is whatever it binds to.
Where a value is assigned across an assignable-to but not subtype-of relationship, the backend inserts wrapping or unwrapping instructions.

## Open Issues

### Type formals bounded by agnostic type formals

What kind is `W` in `<T, W extends T>`?
Its only upper bound is neither nullable nor non-nullable.
Either `W` is agnostic because its bound is, or it is an error.

### `V?` where `V` is nullable

Should `V?` for a nullable `V` be an error, a warning, or allowed since it means the same as `V`?

### Signature narrowing

See *Signature narrowing in overrides* above.
