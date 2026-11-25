# Explicit guarantees on functional type passing and use in scope

TODO: Put these in a proper format.

(Some initial thoughts dumped on Discord)

We've been pretty strict on defaults.  If you want to do something unusual with an referent, specify that on the declaration.

- `let` means `const` by default; explicitly say `var` if you want to reassign.
- `class` fields are `private` unless specified `public`.

Tom dropped some [notes about memory management](../659-memory-management/tom/claude-non-escaping-params.md), and one thing his notes point out is that only escaping closures need some extra checks.

I think Rust has some notations around whether a lambda is affine / linear.
Swift apparently has a notation on function inputs that can receive a lambda which say whether it might be stored and called after the function that receives it returns: `@escapes`.  The meaning of that might be a bit muddled if it's passed to a coroutine but I don't know enough about coros in Swift to say.
Kotlin contracts allow InvocationKind claims.

We could do something similar but there are degrees of strictness, and it could affect some of our guarding.

```ts
var x: Int32? = null;
f { x = 123 }
x.sign()
```

There, if `f` is known to be called at least once by `f` then we can conclude that x is not null at the point where we call its method.

Does classifying block lambdas at the callee appeal to people?
Here are some distinctions we could make:

- `@fnEscapes` means the function value passed could be called after the call completes, maybe even off-thread.
- `@calledMany` means the function can be called many time before the call completes.  This makes sense for inputs to `.map` and `.filter` calls.
- `@called` means the function is guaranteed to be called at least once.  This means that variables assigned inside the function are guaranteed to initialized after it assuming the function doesn't bubble.

If the default assumption for a block receiver is that the minimum number of calls is 0 and the maximum is 1, then `@called @calledMany` narrows it down to >= 1 calls.
