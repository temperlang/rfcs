(Based on the template for Golang's [design doc TEMPLATE.md](https://github.com/golang/proposal/blob/master/design/TEMPLATE.md), part of [Golang's change proposal process](https://github.com/golang/proposal/blob/master/README.md))

# Proposal: Memory Cycle Checker

Author(s): Mike S.

Last updated: 2026-11-10

Discussion at https://github.com/temperlang/temper/issue/NNNNN.

## Abstract

Temper needs to translate well to languages whose runtimes do not have automatic garbage collection that is sound in the face of reference cycles.

This proposal outlines a compile-time memory cycle checker: for each class definition written in Temper, can that type be used (worst case) to construct a memory cycle which would leak memory in a runtime that only supports reference-counting for garbage collection.

## Background

[ASAP](https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-908.pdf) covers a lot of topics in memory management.

_Cyclic Reference Counting with Permanent Objects_ by Lins et al. explains a limitation of simple reference counting.

![Diagram of three refcounted pointer cycle, rooted with 2 1 1 counts, and after the root is removed making the cycle unreachable with 1 1 1 counts but deallocation only happens on 0 counts](./refcount-cycles.png)

Languages like Python and Swift use reference counting extensively, and add affordances like Python's cycle collector, and in Swift's case, weak references and valgrind style tooling to detect leaks.


## Proposal

This proposal consists of these parts each of which has its own header below:

1. **`forbids` clause syntax**: extra syntax on type declarations including  `class`es, `interface`s, and type formal declarations.
1. **`class` cycle checks**: compile-time static checks for each `class` definition, the **class cycle checker**.
1. **`forbids` constraint checker**: compile-time checks on type bindings that they obey `forbids` clauses.
1. **A cycle test suite**: Including the examples below, a suite of test programs that fail and the error messages that should be produced along with similar programs that pass.
1. **Visualizations**: additions to the command line tool and in the REPL that aid in visualizing and repairing memory cycles by showing DOT graphs of how a memory cycle can be formed allowing quick identification of property chains and mutability that could change.
1. **Documentation**: documentation covering the rules in detail, motivation for target languages that don't have scanning GC, examples of what works and doesn't and how to change the one's that don't, and a coverage of topics like ownership, graph representation using façades.

## Rationale

Many programming languages have automatic garbage collection (GC). But that automatic garbage collection doesn't always deal well with cyclic data structures.  For example, C and C++ requires developers to pick one of a number of strategies to ensure deallocation: carefully pairing malloc and free instructions, associating allocations with block scopes during which the allocation is live, using a smart pointer type like a ref-counting pointer, allocating into an arena, etc. Python does use reference counting, but it has a secondary cycle collector that makes its memory management cycle-safe, but Python also relies on RAII-like patterns (resources held by a coroutine are freed on coroutine instance deallocation) that can be confused and delayed by reference cycles.

Simple reference counting semantics for Temper references is a sweet spot for high translatability. Without observable deallocation (no destructors with visible side-effects), target languages that assume scanning GC just work, and target languages that allow for reference counting can also be translated to.

And there is a style of programming, OCaml mostly immutable records, that is naturally acyclic.  Encouraging this style in Temper should mean that most code doesn't need to worry about memory management.  Those work because there is a natural ordering which allows proving absence of cycles: immutable members of an immutable record are older than the record.

This approach focuses the additional collection at mutable and generic types.  The more concrete the types, the more information the checker has to prove; types that layer well (this contains that but not vice versa) just work.

There are also a variety of fallback strategies if this proves hard to use:

- Scoped building idioms. Some mutable types like *ListBuilder* are mutable but short lived, so idioms like Kotlin `buildList { ... }` where the auto-allocated *ListBuilder* switches to a state where it is guaranteed always empty after control exits the `}`, can be exceptions to the rule.  The output *List* type needs to bpass the `forbids` constraint checker.
- Libraries for some apparently cyclic use cases like graphs based on adjacency tables.
- Weak references can allow for parent pointers in AST representations without breaking use cases where the root pointer is strong and not held by an AST.

## Compatibility

This change will probably break existing code that uses `interface`s in ways that would allow a new implementation of the `interface` to refer back to a thing that holds the interface.

For an effectively `@imu` type, often specifying that the interface is `@imu` may allow working around this, but in other cases, extra `forbids` relationships may allow working around problems.

## Implementation

https://github.com/temperlang/acyclic-types is an experimental implementation of the type definition cycle checker.

The `forbids` operator is already in the operator table.
`forbids` should be allowed in `interface` and `class` definitions and so needs its own space in *TypeDefinition*.

The REPL visualizations would benefit from a dependency on a command line image display library like [imgcatr](https://github.com/SilinMeng0510/imgcatr).  Generating a `.dot` file (perhaps a Graphviz out-grammar could help), invoking `dot -Tpng` and then catting the resulting binary could help with showing cycle-participant graphs (also defined in the experiment) in error messages and in the REPL.

Draft documentation below.


## Testing

Kinds of tests:

Memory cycle checking is exclusively a frontend concern, so stage tests that capture error messages suffice for testing the static checks.

Testing image output in the REPL is important. Having a mode where visualizations output the text of the DOT visualization (or other), and so check the input content work.  A single end-to-end REPL or `temper build` test that uses a headless shell and screenshots might suffice to give confidence that visualizations make it through to the person behind the keyboard.  For non-sighted users, the DOT visualization should be sparse enough to read.

### Example: Cons list variants

A simple cons-list that does not allow for cycles.

```ts
class Cons<T forbids Cons<T>>(
  public head: T,
  public tail: Cons<T>?,
) {}
```

A forbidden type since it violates `forbids Cons<T>`

```ts
Cons<Any>
```

Allowed types that obey `forbids Cons<T>`

```ts
Cons<String>
Cons<Cons<String>>
```


A variant of the cons-list that does allow for cycles as it misses the `forbids` clause.

```ts
class Cons<T>(
  public head: T,
  public tail: Cons<T>?,
) {}
```

If *X* is a constructed type like `class X(public var x: Cons<X>) {}` then this creates a cycle.

```mermaid
stateDiagram-v2
  Cons&lt;X&gt; --> X : .head
  X --> Cons&lt;X&gt; : .x
```

A variant of the cons-list that does allow for cycles as it allows for relinking tail.  There is no younger-than ordering principle.

```ts
class Cons<T forbids Cons<T>>(
  public head: T,
  public var tail: Cons<T>?,
) {}
```

Assuming there's some *X* that allows construction of a *Cons&lt;X&gt;*:

```mermaid
stateDiagram-v2
  Cons&lt;X&gt; --> Cons&lt;X&gt; : a.tail = a
```

TODO: layered classes, nesting sealed interfaces based on exhaustive analysis, etc.

### Implicit cycles via closure conversion can be a problem.

```ts
let outer(wantEven: Boolean, i: Int32): Fn(Int32): Boolean {
  // Two coreferential nested functions that close
  // over the same state.
  let isEven(j: Int32 = i): Boolean {
    j == 0 || isOdd(j - j.sign())
  }
  let isOdd(j: Int32 = i): Boolean {
    j != 0 && isEven(j - j.sign())
  }

  // Just a declaration that points to a function.
  // isEven and isOdd don't close over it, but if they
  // did, that'd be cyclic.
  var f = if (wantEven) { isEven } else { isOdd };

  f
}
```

JavaScript has a proper cycle-scanning garbage collector, but here's the
JS equivalent with [closure conversion] done to show which problems can
be avoided and which cannot.

Here's one way to do closure-conversion in JavaScript.

```ts
// Naive rewrite.
function outer(wantEven, i) {
  // Original functions renamed and with references to closed-over
  // state rewritten to point to an extra closureRecord input.
  function isEvenConverted(closureRecord, j = closureRecord.i) {
    return j === 0 || closureRecord.isOdd(j - Math.sign(j));
  }
  function isOddConverted(closureRecord, j = closureRecord.i) {
    return j !== 0 && closureRecord.isEven(j - Math.sign(j));
  }

  // Declare the original names, and a closure record.
  // Curry the converted functions with the shared record to
  // get function values that have the same signature and semantics
  // as the originals.
  const sharedClosureRecord =
    {
    };
  const isEven = isEvenConverted.bind(sharedClosureRecord);
  const isOdd = isOddConverted.bind(sharedClosureRecord);
  // Initialize the closure record.
  sharedClosureRecord.isEven = isEven;
  sharedClosureRecord.isOdd = isOdd;
  sharedClosureRecord.i = i;

  let f = wantEven ? isEven : isOdd;

  return f;
}
```

This rewrite preserves the semantics of the original, and achieves
the goal of closure conversion
(function values internally reference only top-levels and inputs),
but it leads to this object graph:

```mermaid
stateDiagram-v2
  isEven --> isEvenConverted : binding
  isEven --> sharedClosureRecord : curried
  isOdd --> isOddConverted : binding
  isOdd --> sharedClosureRecord : curried
  sharedClosureRecord --> isEven : .isEven
  sharedClosureRecord --> isOdd : .isOdd
  sharedClosureRecord --> i : .i
```

Notice the cycles: `isEven` points to `sharedClosureRecord` points back to `isEven`
and similarly for `isOdd`.

Here's an alternative, where named function declarations are not pre-computed
in `sharedClosureRecord`.  This approach is allowable in Temper because Temper
does not allow testing function reference identity; the fact that `isEven` bound
locally is not the same function value that `isOdd` calls recursively does not
matter to the semantics.  Function binding is side-effect free, so when and how
often it happens does not matter.

```patch
-// Naive rewrite.
+// Rewrite that allows coreferential named functions.
 function outer(wantEven, i) {
   // Original functions renamed and with references to closed-over
   // state rewritten to point to an extra closureRecord input.
   function isEvenConverted(closureRecord, j = closureRecord.i) {
     return j === 0 || closureRecord.isOdd(j - Math.sign(j));
   }
   function isOddConverted(closureRecord, j = closureRecord.i) {
     return j !== 0 && closureRecord.isEven(j - Math.sign(j));
   }

   // Declare the original names, and a closure record.
   // Curry the converted functions with the shared record to
   // get function values that have the same signature and semantics
   // as the originals.
   const sharedClosureRecord =
     {
+      get isEven() { return isEvenConverted.bind(sharedClosureRecord); };
+      get isOdd() { return isOddConverted.bind(sharedClosureRecord); };
     };
   const isEven = isEvenConverted.bind(sharedClosureRecord);
   const isOdd = isOddConverted.bind(sharedClosureRecord);
   // Initialize the closure record.
-  sharedClosureRecord.isEven = isEven;
-  sharedClosureRecord.isOdd = isOdd;
   sharedClosureRecord.i = i;

   let f = wantEven ? isEven : isOdd;

   return f;
 }
```

Changing binding named function declarations on demand leads to this object graph,
which lacks cycles.

```mermaid
stateDiagram-v2
  isEven --> isEvenConverted : binding
  isEven --> sharedClosureRecord : curried
  isOdd --> isOddConverted : binding
  isOdd --> sharedClosureRecord : curried
  sharedClosureRecord --> i : .i
```

But if `var f`, the conditional function pointer,
was referenced by a converted inner function, then we would be in trouble again.
In the case where `f` points to `isEven`, we have this diagram.

```mermaid
stateDiagram-v2
  isEven --> isEvenConverted : binding
  isEven --> sharedClosureRecord : curried
  isOdd --> isOddConverted : binding
  isOdd --> sharedClosureRecord : curried
  sharedClosureRecord --> i : .i
  sharedClosureRecord --> f : .f
  f --> isEven : assigned
```

Rule: any function that closes over a local variable whose type is
either a function type that accepts that function
(pre-closure-conversion), or a super-type (*AnyValue*, *AnyValue\?*,
or that function type nullable) must be forbidden.

Similarly, if a function's type is reachable via assignment to a class instance field.

```ts
class Box<T forbids Box<T>>(public t: T) {}

let outer(): Void {
  let box: Box<fn: Void>();

  let f(): Void {
    box.t();
  }

  box = new Box(f);

  f();
}
```

To check this, the best way is to simulate closure conversion with virtual, ad-hoc types.
`outer` includes a closure, so generate an ad-hoc class type for its closure record, and
another for each closure and turn the checkers loose on them.

```ts
class ClosureRecord#123(public box: Box<fn: Void>()) {}

class BoundFunction#124(public boundParam0: ClosureRecord#123) extends fn: Void {}
```

Now, the reasoning about what closure conversion could do becomes apparent,
and, since `class Box` forbids `<T>` from referring to `Box<T>`, the error analysis
should conclude that the responsibility for the problem is in the combination
of the closure record and the bound function, not in the definition of `Box`.

[closure conversion]: https://matt.might.net/articles/closure-conversion/

## Scope bounded exceptions to the rule

```ts
let combine<T forbids List<T>>(a: List<T>, b: List<T>): List<T> {
  buildList { (b) =>
    b.addAll(a);
    b.addAll(b);
  }
}
```

Here, the type formal `<T>` forbids `List<T>` but not `ListBuilder`.  The fact that
it uses a `ListBuilder` internally is an implementation detail that we might not
want to commit to forbidding, though, in this case, it's not problematic.

Can we use a `ListBuilder` or something equivalent internally?

What if we blessed certain classes as having a life-cycle where, if they progress
through their life-cycle, they are guaranteed not to participate in memory cycles.

Here's an example of how that might work in practice.

```ts
// After release, can point to nothing that might point back to it,
// and enters a zombie state where no new mutations can cause now
// back pointer paths.
interface PointsToNothingAfterRelease {
  release(): Void;
}


class LimitedTimeListBuilder<T> extends PointsToNothingAfterRelease {
  private released: Boolean = false;

  public add(el: T): Void {
    if (released) { return }
    ...
  }
  public addAll(els: Listed<T>): Void {
    if (released) { return }
    ...
  }

  public toList(): List<T> { ... }

  public release(): Void {
    // Flips bit so `add`s become no-ops.
    released = true;
    // Clears underlying content
    ...
  }
}

@inlineUnrealizedGoal
let buildList<T forbide List<T>>(f: Fn(LimitedTimeListBuilder<T>): Void): List<T> {
  let b = new LimitedTimeListBuilder<T>();
  let ls: List<T>;
//try {
  f(b);
  ls = b.toList();
//} finally {
  b.release();
//}
  ls
}
```

Note, this *buildList* idiom could be improved by following on an
initiative to add `this` as inputs to block lambdas.

When a local declaration has a type that is a sub-type of *PointsToNothingOnRelease*,
and it is const, and all paths downstream of its initializers lead to
a `.release()` of it (or of a variable that aliases it (possibly via `notNull(...)`))
then we can forego forbids-checking its type.  This doesn't solve the problem of
delegating building a list by passing the builder on.


## Documentation

TODO

## Open issues (if applicable)

Are images in error messages broadly acceptable, or should those be in interactive mode only?
