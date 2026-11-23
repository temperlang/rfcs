# Proposal: type associated operations that survive generics

Author(s): Mike S.

Last updated: 2026-11-23

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/670

## Abstract

Temper needs static dispatch for type dependent operations that can propagate through generics.

On Perl 5 and PHP, there is no clear distinction between ints and booleans.
But we need some generic operations like stringification to have consistent semantics.

```ts
let someInts = [0, 1];
let someBools = [false, true];
// Those two lists have the same representation on Perl 5 and PHP.

console.log("someInts=${ someInts }, someBools=${ someBools }");
//! logs "someInts=[0, 1], someBools=[false, true]"
```

On some target languages, it's not even obvious that `"1"` is distinct from 1 or true.

Allowing a generic operation like list stringification to depend on the statically known list element type would be good.

This proposal outlines an approach to trait-like dispatch of
operations that lowers to things we already know how to translate,
without the kind of code-size increases that implicit monomorphization
could lead to.

## Background

*Traits* are a way of dispatching method calls based on types.
Unlike virtual tables, there's no choosing which function body to execute
at runtime; the decision is made at compile time based on type information,
possibly including the actual types of type parameters.

Trait-based dispatch gets complicated when it happens from a generic function.
For example, a generic list stringification function has a type parameter
for the list element type, but stringifying boolean elements requires dispatching differently than stringifying integer elements even if both are represented as words.

Typically, that kind of dispatch based on an type parameters actual type binding requires *monomorphization*: making a copy of each generic function for each actual type parameterization in the program.  For example, if there were calls to stringify an int list and a boolean list in the program, the compiler generates instructions separately for two instantiations of the list stringification function.  One instantiation calls directly into an int stringification function to stringify elements and the other into a boolean stringification function.

This obviates the need for a virtual table associated with values: since the correct version of the function that knows the element types are ints directly calls int stringification, the int values do not need to point to a table that relates the abstract stringification operation to the int stringification function.

Monomorphization has downsides though: it can lead to large code sizes.  And some Temper targets (cough JavaScript) are shipped as source over the web so translated code size needs to be kept small.

There's another way to do trait-based dispatch though: reifying the groups of generic operations as needed as values.  This could be thought of as passing a virtual table around but separately from the values that would normally point to it, but as shown below, it lowers nicely to existing mechanisms: interfaces, classes, and statics.  It also, unlike splitting objects from vtables, only affects generic operations that need to do generic dispatch on traits.

----

Another nice property of traits is that they allow for well-typed, contingent behaviour.  For example, Java's approach to list stringification assumes that all values support stringification, but with Rust traits, you can specify that a List (Rust vector) is stringifiable when its element type is stringifiable.

Java's `java.lang.Object` type supports a few blessed generic operations: stringifying, equivalence testing, hashing, and async locking/signalling.  It does not support blessing an additional generic operation like comparison meaning there's no way to write a generic list comparison operator in Java that doesn't do potentially unsafe casts at runtime (to java.util.Comparable) or take another reifying input (java.util.Comparator).

Temper needs to allow for flexible type connections, which is much easier when most types do not inherit type requirements from a catchall abstract super-type like `java.lang.Object`.

Temper has extension functions and operations, functions that can be used as if they were methods but which are not defined by the type's author as part of the type.
This means you can define a function like `List.toString` separately from the List class and outside the scope of its `<T>` type parameter with a type parameter that has additional bounds.

```ts
@operation("toString")
let listToString<T supports Stringification<T>>(
  ls: List<T>,
  // elementStringifier reifies the element trait
  elementStringifier: Stringification<T> supports T,
): String {
  ...
}
```

It is a goal of this proposal to allow generic operations that benefit from trait-like dispatch and well-typed contingent behaviour via extensions.


## Proposal

Allow declaring a kind of type dependent operation independent of any
instance.

Here, we define three type-dependent operations: equivalence predicates, stringification, and getting an external identifier for the type.
The first two take instances; the dispatch is not dependent on instances, but the result is.
The third one is type-dependent and does not depend on an instance.  Instance-agnostic operations are useful when creating instances; you shouldn't need to have an instance of a type on hand to perform an operation that deserializes an instance from bytes received over the wire.

```ts
meta interface Equivalence<T> { equal(a: T, b: T): Boolean }

meta interface Stringification<T> { stringifyTo(a: T, out: StringBuilder): Void  }

meta interface ByteUnpacking<T> { unpackFromBytes(blobSlice: BlobSlice): T throws Bubble }
```

A `meta` interface is just an interface but it can also be used in `supports` clauses.

Allow a type definition to declare that it supports an operation using an infix `supports` word that a.

```ts
class C supports Equivalence<C> & Stringification<C> & ByteUnpacking<T> {
  ...
}
```

Add checks that a type definition does support it by having a `static` corresponding to each method in the meta interface.

```ts
class C supports Equivalence<C> & Stringification<C> & ByteUnpacking<C> {
  public static equals(a: C, b: C): Boolean { true }
  public static stringifyTo(a: C, out: StringBuilder): Void { out.append("C") }
  public static unpackFromBytes(blobSlice: BlobSlice): C throws Bubble { new C() }
}
```

When that check unpasses, the compiler can auto-create a support shim that `extends` the interfaces, and allow retrieving a supporter via a synthesized static method.

```ts
class C supports Equivalence<C> & Stringification<C> & ByteUnpacking<C> {
  ...

  // Synthesized method
  public static supporter(): CSupporter { new CSupporter() }
}

// Synthesized class delegates to static methods
class CSupporter extends Equivalence<C> & Stringification<C> & ByteUnpacking<C> {
  public equals(a: C, b: C): Boolean { C.equals(a, b) }
  public stringifyTo(a: C, out: StringBuilder): Void { C.stringifyTo(a, out) }
  public unpackFromBytes(blobSlice: BlobSlice): C throws Bubble { C.unpackFromBytes(blobSlice) }
}
```

Once there's a way to retrieve a supporter instance, we can allow extension functions to support generic behaviour.

```ts
@extension("toString")
let stringifyList<T supports Stringification<T>>(
  ls: List<T>,
  elementStringifier: Stringification<T> supports T,
): String {
  let sb = new StringBuilder();
  var sawOne = false;

  sb.append("[");
  for (let el of ls) {
    if (sawOne) {
      sb.append(", ");
    } else {
      sawOne = true;
    }
    elementStringifier.stringifyTo(el, sb);
  }
  sb.append("]");

  sb.toString()
}
```

The noteworthy piece here is that the type parameter `<T>` is declared as supporting `Stringification<T>`, and the `elementStringifier` of that supported type also declares that it `supports T`, effectively reifying the supported operations of its type bindings.

Inputs that reify supporters in this way are optional as far as the typer is concerned because we will fill them in later.  Real optional arguments need to be nullable, but these do not.

Here's a call to that extension, and how it gets rewritten.  Assume that `Int32 supports Stringification<Int32>` in the usual way.

```ts
//// Initial code

let ls: List<Int32> = [1, 2, 3];
console.log(ls.toString());

//// After typing and extension relinking

// After type information is available we infer type parameters and rewrite
// extensions to directly point to the extension.

let ls: List<Int32> = [1, 2, 3];
console.log(stringifyList<Int32>(ls));

//// After adding optional/implied parameters

// We still need to fill in the missing parameters.
// For real optional parameters, we fill in `null` but for supporting params,
// we wire in the supporter.
console.log(stringifyList<Int32>(ls, Int32.supporter()));
```

If the supported type parameter binds to a concrete type, like *Int32*, we just
get the supporter from the type.

If it's a reference to a type parameter, there needs to be an input in scope
that reifies the type parameter so we can just pass it through.
Below, we have one function with a type parameter that supports some `Foo` meta interface
and another that it calls into.  Because `<U>` in the delegating call binds to `<T>`, and `y supports U` and in the scope where we need an input for `y` we have `x supports T`, we can just pass `x` as the input for `y`.

```ts
let delegates<T supports Foo>(t: T, x: Foo supports T): Void {
  delegatedTo(t);  // with inserted parameters, is delegatedTo<T>(t, x)
}

let delegatedTo<U supports Foo>(u: U, y: Foo supports U): Void {
  // uses u with y
}
```

### Nesting supports requirements

Some use cases might require supporters to delegate to other supporters.
For example, an unpacker might depend on the type unpacked, and might
delegate unpacking a field whose type depends on a generic parameter to an
unpacker for that type.

```ts
meta interface Unpacker<T> {
  unpackFromBytes(offsetBefore: Int32, blob: Blob): UnpackedAndOffsetAfter<T>;
}
```

Unpacking a List might require unpacking elements, so a supporter for a `List<Foo>` might benefit from being passed a supporter for `Foo`.

Here's a type with two type parameters, each with its own supports clause.

```ts
class C<T supports Stringification<T>, U supports Comparison<U>>
    supports Stringification<C<T, U>> & Comparison<C<T, U>> {
  public t: T; // Stringifying a C stringifies its t
  public u: U; // Comparing two Cs compares their u's
  ...
}
```

Stringifying a `C` needs a stringifier for whatever `T` binds to, and comparing two `C`s needs a comparator for whatever `U` binds to.
That's reasonable and straightforward.

The problem is that no one static supporter method can return a supporter that extends both meta interfaces.
That supporter has to delegate to supporters for `T` and `U`, so it needs both as inputs.
But a context that only stringifies may have threaded through a stringifier for `T` and no comparator for `U`, or vice versa.

### Supporters and intersection types

Reifying supports clauses would be a lot easier if there were a translatable way to write a type that is the intersection of interface types.
Most nominal type systems don't allow that.
Java has intersection types internally in its type inference engine, but every type that you can mention in Java source, by writing characters that specify it, is a class type, an interface type, a primitive type, or `void`.
There's no way to say "a value of abstract type *A* that is also of abstract type *B*, so you can use all the API elements of both."

Supports clauses are basically intersections.
An input like `elementStringifier: Stringification<T> supports T` says that at runtime the value is effectively the intersection of the interfaces in `<T>`'s supports clauses.
They're meta interfaces, but when reifying, the distinction between meta interfaces and interfaces doesn't matter: the value can be used as any of them.
That works because there is a single name to hang the hat on: the type parameter that has the supports clauses.

Synthesized supporter methods for a generic type have no such name.
So we explode out the combinations of delegate supporters a caller might have on hand.
For `C` above, there are three supporter classes:

- one that `extends Stringification<C<T, U>>` and takes a `Stringification<T>` delegate,
- one that `extends Comparison<C<T, U>>` and takes a `Comparison<U>` delegate,
- and one that extends both and takes both delegates.

Each has a corresponding static supporter method.
These classes are cheap: no state beyond their delegates, just behavior.
Naming them is annoying, but in practice, the explosion probably doesn't lead to a huge number of types.

To generate supporters for a type declaration:

1. Filter its type parameters down to those with supports clauses.
   The others need corresponding type parameters on the supporter methods, but no corresponding inputs.
2. For each combination of filtered type parameters, generate a supporter class and a supporter method that takes delegate supporters for that combination.
   The supporter extends those of the type's meta interfaces whose requirements the delegates satisfy.

When generating a call to a supporter method, the compiler picks the method for the combination of delegates the call needs, as in the third case under *Testing and examples*.

It would be nice to keep supporter classes close to the vest; they feel like implementation details, and exporting them blows up the namespace of whatever exports `C`.
Intersection types would allow that, but we don't have them.
The overexport is probably not a big problem though: the supporters only need to be visible to code that can mention `C`.

Supporter method names need to not collide and need to be stable across builds.
Kotlin's approach to optional parameters, generating overloads, doesn't help since overloads don't have distinct names.
Instead, mangle the supporter name with the indices of the type parameters it expects delegate supporters for, e.g. `supporter_0` and `supporter_1` for the single delegate cases above and `supporter_0_1` for both.
There's a basic presumption that additive changes don't break things.
Type parameters are always kind of awkward there, but this is stable as long as type parameters aren't deleted.
Adding one at the end keeps existing names; inserting one before others shifts their indices like a deletion would.

## Rationale

TODO: why this is better than alternatives.
RTTI won't work.  Many languages don't make important distinctions at runtime (int vs boolean examples above), and/or erase type parameters, or there's no instance to check the RTTI of (see unpackign example above).

## Compatibility

TODO: Will require changes to std and core which might break existing code.

TODO: Generic operations that do `==` or `<` or stringification might change but probably not a source of frequent breakage.

## Implementation

TODO: Static checks on supports clauses.  Generate suport classes.  Changing optionality to allow for either `null` passing or auto-forwarding of supporters.

## Testing and examples

TODO: need checks for the case where a callee needs a supporter but there is none in scope.

TODO: need check for the case where there is a supporter in scope but it is not marked with what it supports.

TODO: need check for the case where a class supports two meta interfaces and has two type parameters each used by one and there are three calls that need to create supporters with supporting delegates and one needs to forward a supporter that delegates to the first type parameter's actual binding, another that delegates to the second's, and another that delegates to both.

## Documentation

TODO: A new section on supports clauses and pointers to it from existing class/interface docs.  Documentation for core meta interfaces like Stringification, Equatable

## Effect on Backends

TODO: Low backend requirements since it lowers to just classes and interfaces that we already have translation paths for.

## Open Issues

Do we even need to mark interfaces used in supports clauses with a `meta` keyword or should we just allow any interface type in a supports clause?

Can we have the `static supporter` method take supporters for type parameters that have support requirements and auto-wire those too?
See *Supporters and intersection types* above for one way: a supporter method per combination of delegate supporters.

Do we need to be able to give names to groups of meta interfaces?
`meta interface EquivalenceAndToString<T> extends Equivalence<T> & ToString<T>`
That would allow `static supporter` to receive a single argument at most that supports all of a type parameters's supports requirements.  Is that helpful?
A named group is a way to give an intersection a name, which might also give some synthesized supporters a type to return besides an exploded-out supporter class.
