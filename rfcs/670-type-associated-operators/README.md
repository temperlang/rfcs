# Proposal: type associated operations that survive generics

Author(s): Mike S.

Last updated: 2026-11-18

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

TODO: talk about traits and how they allow for layering on behavior, and allowing for conditional behaviour: a list type that can stringify itself if it has a way to stringify an element.

TODO: recall Temper extension functions




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

See open questions when the type binding is a class or interface type with type actuals that might need to be passed as supporters to the `static supporter` method for the class or interface type definition.


## Rationale


## Compatibility


## Implementation



## Testing and examples



## Documentation


## Effect on Backends

## Open Issues

Can we have the `static supporter` method take supporters for type parameters that have support requirements and auto-wire those too?

Do we need to be able to give names to groups of meta interfaces?
`meta interface EquivalenceAndToString<T> extends Equivalence<T> & ToString<T>`
That would allow `static supporter` to receive a single argument at most that supports all of a type parameters's supports requirements.  Is that helpful?
