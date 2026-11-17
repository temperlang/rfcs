[Comments from Mike on Discord](https://discord.com/channels/1108828567439163503/1217225408752124005/1548123451569737829),
on 2026/09/11.

# Exceptional Shower Thoughts

Now that result types have settled, thinking through some of the semantics for result typing, translation, and connection on backends.

I think we can get consistent semantics for result dispatch.

And I think the way to do it is to bite the bullet and go with single failure types for functions/methods.

First, a bit on Java style checked exceptions and why they're a bad model.

Second, a bit on exception hierarchies and the hopelessness of matching
target language's.

Third, the actual semantics.  Spolier: we probably need to limit our
failure types to something that is declared *Throwable* but that
doesn't necessarily need to correspond to a *Throwable* type.

Fourth, where we can go with more try/catch like syntax.

Finally, strategies for connecting.

## Java checked exceptions are the wrong model for us.

Java allows multiple exception types:

```java
void foo() throws ThisException, ThatException, TheOtherException { ... }
```

I'd speculated about some way of packing multiple failure types into a *Result*:
`Result<ThisException, ThatException, TheOtherException>`.

This is basically union types by another name.  And union types are really hard to translate.
They're also hard to reason about in the type solver.
TypeScript aside, most languages don't have ad-hoc unions.
You either lose precision by taking a common super type, or you fall back to ad-hoc types which are also hard to translate.

I think the better path for Temper is to just commit to *Result* types and make those as easy to use as possible.

With our `sealed interface`s we can allow for a lot of this: `throws MySealedExceptionType` and then allow `match` as a way to dispatch exceptions in `catch` clauses.

So the ergonomics of a single exception type are not terrible.

The real limitation comes in when an API designer wants to allow two failure modes some of which are defined elsewhere.

```ts
let readConfiiguration(...): Config throws IOException, FileMalformedException
```

Having some synactic sugar for creating a sealed interface that wraps them might help.
OCaml backtick unions come to mind.
And I don't think poor ergonomics for this particular use case is the end of the world.

## Connecting exception hierarchies in std is hopeless

In Java and Python, there's an *ArithmeticException* (or -*Errro*) which is a supertype of the division by zero exception.

But JavaScript has no such distinction.  `1n / 0n` in JavaScript raises the same *RangeError* used for out of bounds reads, analogous to *IndexOutOfBoundsException* in Java.

I don't think we can support arbitrary `is` checks for exception types.  In the case where a throwable bound is not a sealed interface we should not attempt to support in-Temper RTTI tests on exceptions.

We should focus on allowing connecting user-declared types in Temper but laave most of our builtin and std exception hierarchy very simple.
Where we can't we should try `... orelse rethrowAs<DesiredExceptionType>()`

## Semantics of single throwable type

I think the sweet spot between translatability and flexibility is **highly convertible exceptions**.

A valid *Throwable* type is one that is declared as such and which has a factory that takes:

- optionally a string
- optionally another throwable
- does not throw in its constructor

and which does not necessarily allow reading either of those constructor inputs.  Conversion to a string should be opaque for most of our builtin and std throwable types.

Given any throwable type, we can convert it to another, and that may be opaque.

So we can have semantically neutral inputs (could just be ignored by types they connect to) but which allows for chaining and storing messages.
But the actual semantics are entirely up to the backend languages.

That has a very small footprint for resulting backends but leaves a lot of flexibility for backends where chaining and diagnostic messages are idiomatic.

This also allows for auto-conversion of one exception type to another either implicitly (if we want to go in that direction) or via something like an explicit but short "please propagate up" operator like Rust's postfix `?`.

## Moving to `catch`

I still think the style of programming we want to encourage is fairly coarse grained error handling, but for user-defined failure types internal to a system where the types need not connect, `sealed interface`s are a great way.  Some kind of `catch` with `match` semantics might provide nice syntactic sugar that allows for convenient fine-grained error handling.

We would need to distinguish between `catch` for a single type and catch with coverage for variants.

## Other notes from Mike copied from the conversation

Go does have type switches, but last time I checked they didn't have a lot for coverage checks.

I think the sweet spot is non-hierarchical exceptions that might connect, and sealed interfaces for internal use with well-defined consistent semantics.

Like if Temper code is failing over to other Temper code, we should get semantic consistency.
