[Comments from Tom on GitHub](https://github.com/temperlang/temper/issues/164),
last edited 2024/10/22.

TLDR:

- Explicit error cases/kinds helps distinguish from panics
  - Can only catch declared cases
- Convert more builtin functions to panic instead of errors that Temper can handle
- Throws makes more sense than Result types for backends generally
  - Could be treated as syntax sugar for IR result types if those work better internally
  - Technically somewhat independent from the above major bullets

Said otherwise, I realized I basically landed on Java checked exceptions, except:
- More functional, like try/catch expressions in Kotlin
- No automatic propagation
- Some sugar
- You can only catch what's declared to throw
- No exception details or hierarchies

See also:

- #163 for some survey of current bubbling.
- [Discussion and proposal for Result types](https://hackmd.io/feFuw8X6Tcy53hQ_yCNqgg?view)
- [TypeScript refusal on explicit throws clauses](https://github.com/microsoft/TypeScript/issues/13219#issuecomment-1515037604) despite lots of interest
- At least some groups [strongly prefer explicit propagation](https://www.youtube.com/post/Ugkx7ycuG9J4PkLL1eGPvre-9VSHfl-7MiKF) over implicit

Goals:

- Distinguish declared errors from panics, even when both are represented as exception throwing
- Make both errors and panics as idiomatic in backends as possible
  - For all of error sum, error tuple, error code, & exception throwing languages
  - We could just remove special error handling entirely from Temper, but then it's hard to represent this situation idiomatically in backends
- We could just make every function capable of erroring, but that's not idiomatic in some backends
- Presume errors might be expensive on some backends, especially because stack traces
  - We've discussed getting fancy but maybe not needed
  - Use nullable or other options for providing common branching cases
  - Errors here are for unusual/exceptional situations that still might *sometimes* happen and need custom handling
- Panics are for programmer error, things that people can entirely avoid in relatively easy & inexpensive ways, like index out of bounds
- Support distinct error cases/kinds in a limited way
  - Convenient when different errors can happen in the same function
  - Convenient when willing to forward errors defined in a different library
  - No hierarchies

Also:

- Might make more sense to pretend throw in result sum languages than to pretend result sum in throw languages

Defining error kinds:

```ts
// No further details and no inheritance, because backends are diverse.
// Error values might need relocated to some top-level enum on some backends.
// On other backends, they'll be converted to classes.
// TODO Other syntax options?
// TODO Should we allow as values outside of bubbling or catching?
error case Baddie;
// let Something = error(); ???
```

Bubbling requires an error kind:

```ts
throw Baddie;
// or throw(Baddie) or bubble(Baddie) ???
```

You can only bubble what's declared:

```ts
let calcSomething(n: Int): Int throws Baddie {
  // TODO Explicit `try` or `!` or ... required to propagate, or do we automate?
  try checkRange(n);
  // Illegal without some handling because we don't throw Other.
  // TODO Do we auto wrap caught errors when throwing? Wrapping is best effort.
  // TODO Some explicit syntax for that? Or special syntax to avoid default wrapping?
  // somethingElse(somethingElse(n - 1) orelse(e) panic(e)) orelse(e) throw Baddie(e)
  somethingElse(somethingElse(n - 1) orelse panic()) orelse throw Baddie
}

let checkRange(n: Int) void throws Baddie {
  if (n < 0) {
    throw Baddie;
    // Would be illegal.
    // throw Other;
  }
}

let somethingElse(n: Int): Int throws Other {
  if (n == 0) {
    throw Other;
  }
  n + 1
}
```

Try sugar:

```ts
try doSomething(n);
// or maybe
doSomething(n)!;
// equivalent to
doSomething(n) orelse throw;
// or maybe we switch to `catch` since we don't want it *too* common and then
try doSomething(n);
// is equivalent to
try { doSomething(n) }
// is equivalent to
try { doSomething(n) } catch { throw; }
// is equivalent to
try { doSomething(n) } catch (e) { throw e; }
// is equivalent to
try { doSomething(n) } catch (e: <error kinds that are declared to be thrown in block>) { throw e; }
// And in the case of `catch` instead of `orelse`, things like this might also work, but we need curlies?:
try doSomething(n) catch { 0 }
// Orelse panic gets uglier with curles:
try doSomething(n) catch { panic() }
```

Explicit types on `orelse`?:

```ts
doSomething(n) orelse(e: Baddie | Other) 0
// or just catch as above
try doSomething(n) catch (e: Baddie | Other) { 0 }
```

Optional best effort case/kind hint for panic?

```ts
// Might or might not get specialized for some backends?
// Maybe message is more interesting?
panic(OutOfBounds);
panic("out of bounds: ${...}");
// Message on errors as best effort? Or don't get people's hopes up with any of this?
// Maybe better just to log message then throw plain?
throw MyError("my message");
```

More:

- These are checked exceptions in Java
- For Lua or similar, we'll need to include some tag field in exception objects
- Maybe prevent exposing error cases from temper-core, unless we can stabilize temper-core
- For exception languages, all standard exceptions are panics for Temper
- Alternatively said, only error cases defined in Temper are visible to Temper
