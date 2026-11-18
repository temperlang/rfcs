Detail moved out of the **declared failures** sketch
([claude-proposal-declared.md](claude-proposal-declared.md)) to keep it
short, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-17. Syntax marked **HYPOTHETICAL** doesn't
compile today.

## Pass-through and capture

The sketch's
[refinement](claude-proposal-declared.md#refinement-pass-through-and-capture)
in more detail. Throughout, failure objects (a caught `SqlProblem` with
its fields, message, and cause) are ordinary values: they can be bound,
stored, passed, put in lists, compared by their fields, and thrown again.
What stays in flight by default is the result, the success-or-failure
union.

**Typing pass-through.** Since each function declares at most one failure
type, pass-through is a failure-type parameter inferred from the function
argument at each call: `E` when the argument fails with `E`, and `Never`
when it can't fail, so the call needs no marker. Swift began with untyped
`rethrows`, and Swift 6 added typed `throws(E)` with generic error types,
which expresses the same thing precisely; Temper can start typed.

**The body's rule.** A pass-through function may call a given function
and propagate its failure. It may not store the result, return it as a
value, or give it to another function except one that passes it through
too. Storing a given function to call later (a lazy value, a cache, a
task) is outside the rule: that code captures, or declares its own
failure type.

**Capture.** `capture { … }` (spelling illustrative) evaluates its block
and gives `Ok(value)` or `Failed(failure)` as an ordinary `Result<T, E>`,
which generic code then handles with no restriction. A held `Failed` can
be propagated again, raising the same failure object. Async blocks and
generators can capture internally, so `await` rethrows a captured failure
and a promise or generator carries its failure type.

**Representation.** On exception backends, pass-through needs nothing:
the failure simply propagates through the generic function. On value
backends it's a generic error parameter (Rust's
`fn map<T, U, E>(…) -> Result<Vec<U>, E>`, with an uninhabited `E` when
nothing fails, which the compiler removes). Capture is the only place the
JVM materializes `Ok(value)` or `Failed(sameObject)`, the held-result
rule of the
[values sketch](claude-proposal-values.md#semantics-and-representation-are-separate-choices);
C# and C++ use their value types there.

**Open questions:**

- Spelling of pass-through (`throws passed` below, Swift's `rethrows`, or
  a named failure parameter) and of `capture`.
- Two given functions with different failure types, such as a comparator
  and a key function: require one, or combine them into a sealed type.
- Whether the body may handle a passed failure with `orelse`, which
  holds nothing.
- Whether a `@fun interface` can declare pass-through for its method.

## Migration in detail

`throws Bubble` stays valid: it's the failure type with no fields, so the
286 declarations (87 public, 199 internal) in the surveyed libraries and
std compile unchanged at first, and host code keeps catching an exception
([counts](claude-explore/README.md#what-dropping-throws-bubble-would-take)).
Libraries then move to declared types where they want reasons: about 70
exported members across five libraries, mostly parse and validate entry
points ([findings §3](claude-findings.md#3-real-cases-in-public-libraries)).
Moving builtins to panic removes most of the rest, for example 31 of
Chromarite's 52.

Explicit propagation, which Tom's and Mike's notes both lean toward,
needs a marker at the [630 calls](claude-common-ground.md#propagation-markers)
that propagate implicitly today; 68 of Wherewith's become `throw`s.
Where `forEach` or a similar helper is inlined today so `bubble()` can
escape it, pass-through keeps the same code working without inlining.

## Cost in detail

- **Success path:** free on every backend but Lua, where each `orelse`
  builds a closure and `pcall` (5 to 10 percent)
  ([findings §2](claude-findings.md#2-speed)).
- **Each failure:** an exception where it is one today: about 2 µs in C++,
  15 to 19 µs in C#, 0.8 µs in Java, 3 µs in JS, and 0.3 µs in Lua and
  Python; nothing in Rust. At 1 percent failures, C#, Java, and JS loops
  take about twice as long as a nullable version, and at 10 percent 11 to
  107 times on C++, C#, Java, and JS
  ([bench](claude-explore/bench/README.md)). Building a message adds to
  this: Java's `toInt32`, which formats one, costs about twice a bare
  bubble.
- **Mitigations:** lowering a `throw` and its handler in one function to a
  branch ([common ground](claude-common-ground.md#lowering-a-local-failure-to-a-branch));
  throwing without a stack trace (Java's `writableStackTrace=false`, a
  plain object in JS), at 0.1 to 0.5 times today's bubbling cost (no help
  on .NET 6); and failure values inside a library with a throw only at
  exported functions, where a compiler-known result costs about what a
  nullable does ([hand-written forms](claude-explore/README.md#a-compiler-known-result-type-likely-cost)).
  Under the refinement, code that expects many failures can also
  `capture` and work on held results.

**On real libraries** ([estimates](claude-explore/estimates/README.md)):
Kelpto and Wherewith throw no failures on valid input, so declared
failures cost about nothing there, except Lua's `pcall` per executed
`orelse` (1 to 6%, removed if bug-like builtins panic). One failure in an
invalid Wherewith query unwinds 25 frames and adds an estimated 15 to
300% to that query on C++, C#, and Java, which matters for tools that
mostly see invalid input.

## Other open questions

- The name of the sealed type generated for `throws X, Y`, and how a case
  from another library joins it (wrapped as a variant, or converted).
- Whether propagation may convert implicitly between unrelated failure
  types, or only by explicit `rethrowAs`.
- Whether a failure type can derive its host message from its fields,
  rather than taking a message argument.
- Whether categories are worth keeping, given that only Python and Go
  can show one beside the library base
  ([common ground](claude-common-ground.md#host-facing-failure-types)).
