# Proposal: What is the meaning of `this`!?

Author(s): Mike S.

Last updated: 2026-11-17

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/660

## Abstract

`this` has one meaning in method, constructor, getter/setter bodies, and property initializers.

It has another meaning inside `test("testname") { assert(...) }` blocks.

It'd be nice if we could have lambdas use `this` implicitly to enable idioms like the below, touched on in [RFC 659](../659-memory-management/README.md):

```
buildList {
  add(1)    // equivalent to this.add(1)
}
```

## Background

Bare words in program texts need to be resolved to references.  In the
examples above, `test` is a bare word that eventually resolves to a
reference to the `test` builtin, `assert` is a bareword that resolves
to `this.assert` based on the fact that there is a `this` type in
context whose type is `Test` from `std/testing`.  In the second
example, `buildList` and `add` are bare words that need similar
resolution.

In the old Kotlin-based Temper compiler, *DotHelper* allowed
suspending judgement over the meaning of some operations until type
information was available to disambiguate.

OO programming languages in the C++ / Java / JavaScript tradition often
use the pronoun `this` to refer to the current object.

Name masking is a thorny problem.  When block scopes nest, or names are
reused, a declaration can make a name in an outer scope unavailable.
`let x; ... do { let x; ... /* Outer x is masked */ }`.  To allow
referring to `this` from outer scopes, Java allows qualified-this
syntax: `TypeName.this` and Kotlin achieves something similar with `this@TypeName`.

Kotlin DSLs are remarkably effective at allowing block lambdas with
type-mediated resolution of bare names to properties and methods on multiple
`this` values defined in overlapping scopes to work together.
This allows bolting on structured (around block scopes) approaches to
any number of problems like building tree like values, exposing resources
that are reclaimed when control leaves a scope, and guaranteeing if-this-then-that
relationships based on entry into and out of scopes.

Extending structured programming and by-construction guarantees is
good for system health, and flexible yet consistent implicit `this`
member resolution from bare names is good.

Sound IDE refactorings to exisitng code that has multiple `this` values in play
benefit from being able to rewrite an implicit (bare name) use of a paricular
`this`'s member to use an explicit and possibly qualified member.

## Proposal

A lambda type can specify a type for a `this` parameter which must be the
first parameter, and must be marked as the `this` parameter explicitly.

TODO: explore the feasibility within Tempest of having the ready loop
quickly export at least the functional interface types' this parameters
for block lambdas early enough to help with bare name resolution.
This shouldn't need a full typing pass; knowing that `this` is a `ListBuilder`
of some unknown element type still allows realizing that `this` has an `add`
parameter even though it might not let you enumerate the applicable extension
methds.  So knowing which functional interface or some information about the
arrow type is useful.

TODO: allow for explicit `this` type declarations in lambda signatures.
IDE refactorings should be allowed to expand minimal lambda signatures into
explicit ones to aid in sound refactorings.  `{ x => ... }` might have an
implicit this parameter but `{ (this: Foo, x) => ... }` explicates that.

TODO: decide on a qualified this syntax.  Evaluate based on familiarity
to our likely user population.

## Rationale


## Compatibility


## Implementation



## Testing and examples



## Documentation


## Effect on Backends

Better, more flexible name resolution shouldn't affect existing backends.
Target languages that don't allow for disambiguating nested `this` still
allow for aliasing `this` which is uncontroversial because often there's
no way to reassign `this` within a stack frame.

In JavaScript, for example, `this` names are implicitly inserted for
every nested `function` declaration (though not for arrow lambdas), so
it is not unusual to see code like the below:

```js
function outer() {
  const outerThis = this;
  return function () {
    f(this, outerThis);
  }
}
```

## Open Issues

