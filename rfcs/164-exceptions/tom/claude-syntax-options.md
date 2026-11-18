# Syntax options for propagating and handling failures

By Claude, 2026-11-18, as input for the syntax question in
[claude-recommendation.md](claude-recommendation.md). Every snippet below
is **hypothetical syntax**; none of it parses today except option A. The
semantics question (first-class results, the middle ground, or in-flight
only) is separate; notes say where an option fits one better.

Each option shows the same six tasks:

1. **Propagate** a failure from one call.
2. **Propagate through a chain** of calls.
3. **Default** a failure to a value.
4. **Bind** the failure and match its variants.
5. **Hold** a result as a value (first-class results or the middle
   ground's capture).
6. **Default a null**, for comparison.

The examples use `name(...)`, `keyword(...)`, `parse(...)`, and `lookup(...)`
returning `T throws SqlProblem` (or `Result<T, SqlProblem>`), and
`findCached(...)` returning `T?`.

## A. Today

```temper
let n = name("a column");            // 1: propagates implicitly (the function is `throws Bubble`)
let c = lookup(s).column().type();   // 2: implicit through the chain
let n = name("a column") orelse "";  // 3
// 4: not possible; the failure can't be named
// 5: not possible
let x = findCached(k) ?? fallback;   // 6
```

Nothing marks where failures propagate; `orelse` binds looser than `==`.

## B. Per-call prefix `try`, infix `catch` (Zig)

```temper
let n = try name("a column");                           // 1
let c = try (try (try lookup(s)).column()).type();     // 2
let n = name("a column") orelse "";                     // 3
let n = name("a column") catch (e) { when (e) {         // 4
  is MissingValue -> "";
  is UnknownWord -> panic();
} };
let r = capture name("a column");                       // 5 (middle ground)
let x = findCached(k) ?? fallback;                      // 6
```

Precise (each failing call marked) but chains nest; `catch` as an infix
operator is unusual outside Zig.

## C. Expression-wide `try` (Swift), infix `catch`

```temper
let n = try name("a column");                           // 1
let c = try lookup(s).column().type();                  // 2: one try covers every call in the expression
let n = name("a column") orelse "";                     // 3
let n = name("a column") catch (e) { when (e) { … } };  // 4
let r = try? name("a column");                          // 5: Swift's try? gives an optional; a result-giving
                                                        //    variant would suit the middle ground's capture
let x = findCached(k) ?? fallback;                      // 6
```

One marker per expression that can fail: light, and still visible in
review, but it doesn't say which call in the expression fails.

## D. Postfix keyword `.try` (in the style of Rust's `.await`)

```temper
let n = name("a column").try;                           // 1
let c = lookup(s).try.column().try.type().try;          // 2
let n = name("a column") orelse "";                     // 3
let n = name("a column") catch (e) { when (e) { … } };  // 4
let r = name("a column").capture;                       // 5
let x = findCached(k) ?? fallback;                      // 6
```

Precise and chains left to right; a keyword, so no clash with `?.`, but
unfamiliar, and noisy where every call can fail.

## E. Keep `orelse`, add a binding and `return` as an expression

```temper
let n = name("a column") orelse (e) return e;           // 1 (or a later shorthand)
let c = lookup(s) orelse (e) return e;                  // 2: one call at a time
let t = c.column() orelse (e) return e;
let n = name("a column") orelse "";                     // 3
let n = name("a column") orelse (e) when (e) { … };     // 4
let r = capture name("a column");                       // 5
let x = findCached(k) ?? return null;                   // 6, now also able to return
```

The smallest change from today and the least to migrate; propagation is
wordy until a shorthand exists, and `orelse` keeps its looser-than-`==`
precedence unless that changes too.

## F. Block `try`/`catch` expression (Kotlin, Scala)

```temper
let n = try { name("a column") } catch (e: SqlProblem) { "" };   // 3
let n = try {                                                    // 4
  name("a column")
} catch (e: MissingValue) {
  ""
} catch (e: UnknownWord) {
  panic()
};
// 1 and 2 still need a propagation marker from another option
```

Familiar to Java, Kotlin, C#, and Scala users; heavy for the common
one-call default, and it covers only handling, not propagation.

## G. Methods on first-class results (Kotlin's `runCatching`, Rust's combinators)

```temper
let n = name("a column").getOrElse { "" };                       // 3
let n = name("a column").recover { e -> when (e) { … } };        // 4
let r = name("a column");                                        // 5: it's already a value
let c = lookup(s).andThen { it.column() }.andThen { it.type() }; // 2
// 1 still needs an operator to stay readable
```

Fits first-class results only; library methods instead of syntax, with
no language change for handling, but chains of lambdas are harder to
read than direct calls.

## Binding the failure

An infix handler that binds the failure in parentheses, `f() catch (e) …`
or `f() orelse (e) …`, would be ambiguous if a parenthesized fallback
could follow it too: in `f() catch (fallback)`, is `fallback` a value or
a name for the failure? The examples above split the two jobs between
two words, each following a rule Temper already has:

- **`orelse` is an expression operator and never binds,** as today:
  `f() orelse 0`, `f() orelse (a + b) * c`, `f() orelse do { … }`.
  Parentheses after it are always a parenthesized expression.
- **`catch` is a keyword clause shaped like `else`, so it always takes a
  block,** optionally after a binding: `f() catch { … }`, or
  `f() catch (e) { … }`. `catch (e) { … }` reads like `if (cond) { … }`,
  a parenthesized head and a braced body, so it follows the same brace
  rule, and `return`, `break`, and `continue` in the block refer to the
  enclosing function, as in an `if` block.

```temper
let n = f() orelse 0;                       // the common short default
let n = f() orelse (a + b) * c;             // any expression
let n = f() catch (e) { when (e) { … } };   // bind, then a block
let n = f() catch { log("failed"); 0 };     // a block without a binding
```

Two words instead of one, but no ambiguity and no new rules, and the
most common case stays as short as today. Zig likewise has both
(`catch` for failures, `orelse` for nulls), and Kotlin has `?:` beside
`try`/`catch`. A later decision could merge `orelse` with `??`, so one
operator gives defaults for both null and failure.

Considered and set aside: `catch (e) expr` without braces, which looks
like `if (cond) expr`, which Temper forbids; a `(_)` escape for
parenthesized fallbacks; binding with trailing-block syntax,
`f() catch { e => … }`, which looks like a function literal, so a reader
could expect `return` inside it to leave only the block; and Zig's
`catch |e| …` or a keyword form (`catch as e -> …`), each new to Temper.

## A full try/catch block

A Java-style `try { … } catch (e: X) { … }` would clash with a prefix
`try` that marks propagation (options B and C): `try { a(); b() }`
without a `catch` could mean either. Swift avoids this by spelling the
block `do { … } catch { … }`. Temper already has `do { … }` block
expressions, so the infix handler applied to one gives the full form
with nothing new: `do { a(); b() } catch (e) { when (e) { … } }`, with
several variants handled by `when` inside the one handler.

## Notes across options

- **Precedence:** whichever handling operator wins should bind tighter
  than `==`, `&&`, and `||`, so `x catch 0 == y` means `(x catch 0) == y`.
- **`try` as a word:** if `try` marks propagation, `tryX` as a naming
  convention for nullable variants (from the naming discussion) reads
  ambiguously; the two choices should be made together.
- **Syntax follows semantics:** exception-style words (`try`, `catch`)
  signal that failures aren't values to touch, which suits the middle
  ground; method-style handling (G) suits first-class results.
