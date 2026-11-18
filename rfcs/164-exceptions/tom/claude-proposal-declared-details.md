Detail moved out of the **declared failures** sketch
([claude-proposal-declared.md](claude-proposal-declared.md)) to keep it
short, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-17. Syntax marked **HYPOTHETICAL** doesn't
compile today.

<a id="pass-through-and-capture"></a>

## Generic failure parameters

The sketch's
[refinement](claude-proposal-declared.md#refinement-generic-failure-parameters)
in more detail. Throughout, failure objects (a caught `SqlProblem` with
its fields, message, and cause) are ordinary values: they can be bound,
stored, passed, put in lists, compared by their fields, and thrown again.
What can't be held is the result, the success-or-failure union.

**Results inside the compiler.** In the frontend's typing and in tmpl,
`T throws E` is an ordinary generic type `Result<T, E>`, as Kotlin
Temper's `Result<T, Bubble>` is today, so substitution, inference, and
lowering treat it like any generic type. `Result` isn't a subtype of
`AnyValue`, so no variable, field, or ordinary type parameter can have a
result type, and Temper source can't name it.

**Typing.** A failure parameter is an ordinary type parameter bounded by
the root every declared failure type extends: `E extends Failure`
(`Failure` for now), written or implied by its use after `throws`. A
function type without `throws` means `throws Never<Failure>`, which
under Temper's `Never<T>` rules is a subtype of `Failure` only and has
no values: a failure that can't happen. Inference fills `E` at each call
from the argument, so `map(xs, fn (x: Int): Int { x * 2 })` needs no
marker, while a callback that throws `SqlProblem` makes the call need
one. A function type that can't fail is also accepted where one that
throws a concrete failure type is expected, which fixes a non-failing
function passed as a failing `@fun interface`. An alternative to
`Never<Failure>` is a dedicated empty sealed failure type, like Rust's
`std::convert::Infallible`; the root needs a name either way.

**The body's rule.** A function generic over `E` may call its callback
and propagate the failure (`!` here, `try` in the proposal) or handle it
(`orelse`, or `catch`, binding the failure object). It can't store a
result, because results can't be held anywhere; that is the only rule,
so no effect system is needed. Storing a callback to call later (a lazy
value, a cache, a task) is fine; calling it later propagates or handles
as usual.

**Why generic `E` is safe for hosts.** Exported failure types stay
sealed and non-generic. A failure parameter is instantiated at each use
with a concrete declared failure type or `Never<Failure>`, so every
failure that reaches a host is of a concrete type.

**Representation.** On exception backends, failure parameters need
nothing: the failure propagates through the erased generic function. On
value backends `E` is a generic error parameter (Rust's
`fn map<T, R, E>(…) -> Result<Vec<R>, E>`, with an uninhabited error
type for `Never<Failure>`; C++ templates over `E`), or erased to the
host's error type (Go's `error`, a status code in C). Handlers inside
generic code can't name one library's type, so on hosts without
generic catch they need a marker every library base carries, or a type
witness.

**Capture, deferred.** An earlier draft had `capture { … }` turning a
failure into a held `Result<T, E>`, with async blocks and generators
capturing internally. The first version leaves it out: code that needs
an outcome stores the failure object, and promises hold async failures,
which `await` rethrows. It can be added later if real code shows the
need.

**Open questions:**

- Spelling of failure parameters, and whether the bound is written.
- Two callbacks with different failure types, such as a comparator and
  a key function: require one `E`, or a declared sealed type wrapping
  both.
- How promise and generator types name their failure type.

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
escape it, a failure parameter keeps the same code working without
inlining.

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
