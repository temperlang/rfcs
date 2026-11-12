Claude's reaction to the memory cycle checker proposal, at Tom's request.

## What's strong

- The ordering principle is sound: immutable members can only point to
  older objects, so cycles need mutation. tempest's
  [notes/acyclic.md](https://github.com/temperlang/tempest/blob/main/notes/acyclic.md)
  reached the same idea independently ("cycles need mutation or a leaked
  `this`"), which is encouraging.
- It delivers a long-standing promise: the memory tutorial already says
  cycle-building code "will cause compiler errors in the future", and
  `forbids` looks like what temper issue #5's "does not reference" bounds
  were after.
- It starts from an experimental implementation (acyclic-types) and plans
  a test suite of failing and passing programs.

## Gaps worth covering

1. **`this` escaping during construction.** An immutable object can still
   join a cycle if `this` leaks from its constructor before its fields are
   set. The team's rule that `this` isn't used in a constructor until every
   field is set covers this; the proposal should say it relies on that rule.
2. **Closures and function types.** A field holding a function or a fun
   interface value can capture its owner. The Compatibility section mentions
   interfaces, but closures are the commonest accidental cycle and deserve
   explicit rules and examples.
3. **How noisy it is.** A worst-case check at each class definition may flag
   every generic class with a mutable field of its type parameter (`class
   Box<T>(public var value: T)`), making `forbids` boilerplate. Before
   accepting, run the experimental checker over std and the public Temper
   libraries (Chromarite, Hrefine, Kelpto, Ordable, Wherewith) and count the
   errors, so "will probably break existing code" becomes a number.
4. **std's own types.** Say how `ListBuilder`, `MapBuilder`, generators,
   promises, and `AnyValue` are annotated or exempted. The scoped-building
   idea (`buildList`) is good but needs its exact rule.
5. **Weak references as a fallback.** Most backends have them, but they make
   deallocation observable, which the rationale's "no observable
   deallocation" property relies on avoiding. Worth a sentence on how that's
   reconciled.
6. **Visualizations.** Make text the primary form: a DOT or Mermaid
   description of the cycle, which works in CI logs, the language server,
   screen readers, and the playground (which already renders Mermaid).
   Images could be interactive-only and opt-in, which answers the open
   question. An image-display dependency in the CLI seems heavy given how
   terminal image support varies.
7. **Implementation target.** The Implementation section names Kotlin's
   structures (`TypeDefinition`). With tempest replacing the Kotlin
   compiler, it should target tempest, whose acyclic.md has a sketch of the
   check and open questions to reconcile with this proposal.

## Follow-up answers

### The `this` rule in tempest

Half of it is in place. Until every field is set, `this` can't be used
at all (`ThisBeforeFieldsSet`, in tempest's `typing/fields_first.rs`).
`this` escaping the constructor after that, by being stored, passed, or
captured, isn't checked yet. For cycles, the first half plus the graph
check may be enough: once fields are set, an object's immutable fields
can't change, so storing `this` anywhere that leads back to it needs a
mutable reference, which the graph check reports. Worth confirming with
tests before relying on it.

### Weak references by backend

All seven current backends have something: JS `WeakRef`, Python
`weakref`, Java and C# `WeakReference`, C++ `weak_ptr`, and Rust `Weak`.
Lua has weak tables but no single weak-reference object, so it would need
emulating. The gaps are future targets (C99 has none) and behavior: under
tracing GC a weak reference clears at some unpredictable time, under
reference counting at once, so the same program could behave differently
per backend. Suggestion: keep weak references out of the core design, or
offer them later as an explicit opt-in std type.

### Closures

1. **Only stored closures matter.** A block passed to `map` and not kept
   adds no edge. As with Swift's `@escaping`, only a closure stored in a
   field, list, or map creates one. That removes most of the noise.
2. **Check where it's stored, with its actual captures.** When a closure
   is stored in a field, it's an error only if a captured value's type can
   lead back to that field's owner through a mutable edge. That's precise
   and local, where treating every fun interface field as reaching
   anything would reject nearly all of them.
3. **Suggest the usual fix in the error:** pass the owner as an argument
   (`handler(event, owner)`) instead of capturing it, the closure version
   of passing context down.

### How this lines up with tempest's acyclic notes

[notes/acyclic.md](https://github.com/temperlang/tempest/blob/main/notes/acyclic.md)
already covers the principle; a "may reference" graph with edges for
fields, list and map elements, and captured variables, where interfaces
reach every implementation; errors at the mutable edge, found by strongly
connected components; `forbids` checked where generics are instantiated;
the `this` rule; and starting as warnings until the rules are agreed. Its
open questions are top types and open interfaces, closures, core's
builders, `forbids` details, and actionable error messages.

Only this proposal has visualizations, weak references, scoped building
(`buildList`), and the test-suite and documentation plans. The two
complement each other.

### Measuring the noise

A trial applied the rules by hand, with the strictest reading wherever
this proposal and tempest's notes differ, to two public Temper libraries,
editing them as an author would to pass a pretend checker:

- **Wherewith** (77 types): no reports. It has no generic classes, its
  exported interfaces are sealed, its trees are immutable, and it stores
  no closures.
- **Kelpto** (142 types): two reports.
  - **One real:** block nodes kept their children in a
    `ListBuilder<BlockData>` while each child pointed to its parent, a real
    cycle per block, so today's C++ and Rust translations leak each parse's
    block tree. Keeping children as ids fixes it, compiles today, and
    passes Kelpto's tests.
  - **One noise:** a write-once `var` field reaching an open `@fun`
    interface, "fixed" with a `forbids` on the interface.

A third library, private and built on heavily generic, abstract code (96
types, 15 generic with 29 type parameters), had 12 reports and no real
cycle in its own use. It needed 9 `forbids` and a marker interface, and
one case the rules can't express: objects of one type that nest strictly
inward at run time, each holding a fresh inner one. Five reports guard
cycles that only outside code could build, through public setters.
Neither relaxation below (write-once fields, inferred `forbids Owner`)
removes any of them. Six of its seven bounds exist only because of
builders that are never stored and always end in `toList()`.

Suggestions from the trials:

1. Treat a `var` assigned only before its object escapes as part of
   construction (issue #7's `late`), so write-once fields count as
   immutable edges. That was the only source of noise.
2. Infer or default `forbids Owner` for function-typed fields reached by a
   mutable edge, so errors land on the user's closure that captures the
   owner, not on every implementation.
3. When a builder holds its own type, have the error suggest keeping ids
   instead; that was the real case here.
4. Spell out what core declares: `ListBuilder` and `MapBuilder` bounds,
   `List` and `Map` as immutable edges, `Listed` and `Mapped` as possibly
   mutable, and whether sealed and unexported interfaces count as closed.
5. **Scoped builders as a rule** (the proposal's own fallback): a builder
   never stored or returned, ending in `toList()`, is checked only through
   the immutable list it makes. In the generic library, that alone removes
   six of seven bounds.
6. **Implied bounds:** callers shouldn't restate a callee's `forbids`
   bound; the generic library wrote one long bound six times.
7. **Erased targets:** let `forbids SomeGeneric` mean every instantiation,
   so authors don't need marker interfaces.
8. **Bounds shouldn't expose private fields:** the bound that type-checked
   named a private `ListBuilder` field's element type, an implementation
   detail in a public signature. An owner bound could cover builders the
   owner never lets out.
9. **Public setters:** with only private visibility, frameworks must expose
   setters that let users close loops the library never would. Say so,
   and document the pattern of stateless strategies with state passed
   along immutably.
10. **Open questions to settle:** whether a sealed interface with an
    exported, unsealed subinterface is open; whether `@imu` interfaces
    count as closed; and where `forbids` goes relative to `extends` in a
    bound (`T extends Event forbids X`).
11. **Show the capability pattern as the recommended shape for host
    services:** open interfaces the host supplies once (a clock, a
    randomness source, a session store), held in fields set by the
    constructor, with immutable records and stores holding copies. In a
    rerun of the generic library with 41 more types (web sessions,
    throttling, another SQL dialect), it passed with no annotations, and
    the new dialect needed no new `forbids`; only the public-setter cost
    in suggestion 9 grew, by one more accumulator.
12. **Still unmeasured:** std and core (builders, generators, promises) are
    the real stress test, then Hrefine, whose implementation of Kelpto's
    open `UrlCheck` would be the first open interface crossing libraries.

## Closure conversion

On Mike's section "Implicit cycles via closure conversion can be a
problem".

### Already how tempest generates code

Building the `isEven`/`isOdd` example with tempest, its Rust and C++
output put the captured state in one shared group value (`IsEvenGroup`,
the closure record), with the two functions as methods that call each
other directly (`self.is_odd(…)`), so the record holds no function
values. Each function value is made from the group where it's needed
(Rust's `Arc::new(move |a0| group.is_even(a0))`, a C++ `std::function`
lambda over the group). The object graph has no cycle, as in the second
diagram. So the key claim is implemented, not only sketched: since
Temper code can't compare functions' identity, making function values on
demand is free, and mutually recursive local functions, the commonest
case, never need flagging.

### What's strong

- **One checker:** modeling closure records and bound functions as
  ad-hoc classes lets the same cycle check reason about closures, with
  nothing closure-specific, and gives "check the actual captures where
  the closure is stored" for free.
- **Errors land in the right place:** in the `Box` example the problem
  is the closure plus the assignment, not `Box`'s definition.
- **It fits nominal fun interfaces:** a bound function is a class
  implementing the function's interface.

### Suggestions

1. **Only variables changed after capture.** As written, the rule flags
   capturing any local whose type is the function's type or a supertype
   (`AnyValue?`), which is type-based and noisy. Cycles need mutation: a
   captured local set before the closure exists and never reassigned
   can't point back to it, as immutable fields only point to older
   objects. So only `var`s, and `let`s assigned after the capture (as
   `box` is), reassigned after the closure is created, need checking.
2. **Only stored closures matter.** A closure passed to `map` and dropped
   adds no lasting edge. With ad-hoc classes, that holds if a bound
   function is an edge only where it's stored: in a field, a captured
   variable, or a collection. Worth saying explicitly.
3. **Keep the virtual types out of messages.** Report in source terms,
   never `ClosureRecord#123`: "`f` captures `box`, and `box.t` holds `f`
   (assigned at line N), a cycle under reference counting", with the
   usual fix: pass `box` as an argument instead of capturing it.
4. **The cost of making functions on demand.** Each use of a local
   function as a value allocates one; direct calls within the group
   don't (tempest makes them plain method calls). Worth a sentence.
5. **Which targets need it.** The risk is real for reference-counted
   targets: C++ (`shared_ptr`), Rust (`Arc`), and later Swift or C. JS,
   Java, C#, Python (with its cycle collector), and Lua collect cycles.
   The check still belongs in the frontend for every target, as a
   language rule, but the motivation can name these.
6. **The example:** `let box: Box<fn: Void>();` reads like a typo for a
   declaration that `box = new Box(f)` assigns later.

## Small fixes

- The discussion link: `issue/NNNNN` should be `issues/` once there's a
  number.
- "bpass" should be "pass".
- "the one's that don't" should be "the ones that don't".
