# A Lean model of RFC 659's cycle checker

An experiment: model a micro language with the RFC's memory cycle checker,
search for counterexamples, and then try to prove that a program the
checker accepts can't make a cyclic object graph.

## Stages

0. **Bounded search** (`Cycles/Search.lean`, `Main.lean`).  An executable
   checker and heap semantics, and a search over every sequence of a few
   steps, on hand-written and random programs that pass the checker.
1. **Soundness without type formals** (`Cycles/Soundness.lean`).  Classes
   with early, set-once and `var` properties; sealed and non-sealed
   interfaces; *AnyValue*; and `forbids` clauses on classes and interfaces.
   **Proved:** `acyclic_of_passes` (`Cycles/Acyclic.lean`): in a
   well-formed program where every class passes the checker, no sequence
   of steps makes a cyclic object graph.  It uses only Lean's standard
   axioms (`#print axioms Cycles.acyclic_of_passes`).  Along the way:
   - `earlyPointsOlder`, `wellTyped`, `classesDeclared`: invariants by
     induction on steps;
   - `exists_nonEarly_of_cycle`: the birth order argument, that any pointer
     cycle goes through a non-early property;
   - `forbidsKept`: an object never reaches an object of a type its class
     forbids.  This is where Step V's fake-class edges are needed;
   - `walk`, `canBeA_path`, `not_always_of_path`: pointer paths map into a
     class's graph, and the "always" fixed point means what it should.

   **Proved:** `check_extend` (`Cycles/Extend.lean`), separate
   compilation: if `p` and `p ++ q` are well-formed and `q` declares only
   new names and extends only `p`'s non-sealed interfaces, each of `p`'s
   types passes in `p ++ q` exactly when it passes in `p`.  So a library
   that passes stays sound however later libraries use it.  The `ext`
   search mode tests the same thing.

   **Proved:** `check_converged` (`Cycles/Fuel.lean`): for a well-formed
   program, every fixed point converges within its fuel, so the checker's
   `converged` flag never fails.  Reachability only grows a duplicate-free
   list of nodes, and "always" only shrinks one.  `wellFormed` still
   requires `ancestors` to converge.
2. **Type formals** (`Cycles/Generic/`, `GenericMain.lean`), with
   `extends` and `forbids` bounds, on classes and interfaces.  So far an
   executable model and bounded search, not proofs.  Polymorphic recursion
   makes the graph fail to converge, so the checker rejects it.  See
   *Stage 2* below.
3. Widening, and the RFC's worklist algorithm rather than this model's
   simpler fixed points.

## Files

- `Cycles/Syntax.lean`: declarations, subtyping, `forbidsOf`, `mayBeA`.
- `Cycles/Subtyping.lean`: lemmas about `dedup`, `ancestors` and `forbidsOf`.
- `Cycles/Checker.lean`: drop-order graphs and Steps I–V.
- `Cycles/Semantics.lean`: heaps, the `new` and `set` steps, acyclicity.
- `Cycles/Search.lean`: the bounded search.
- `Cycles/Soundness.lean`: invariants and lemmas.
- `Cycles/Acyclic.lean`: `walk`, `forbidsKept`, `acyclic_of_passes`.
- `Cycles/Fuel.lean`: `check_converged`.
- `Cycles/Extend.lean`: `check_extend`, by comparing the two programs'
  graphs and fixed points by what they mean.
- `Cycles/Generic/Syntax.lean`: Stage 2's types, substitution, subtyping,
  unification of a class's type formals, `mayBeA`.
- `Cycles/Generic/Checker.lean`: graphs over mainType's type formals, Steps
  I–V, and the type phrase check (`phraseOk`).
- `Cycles/Generic/Semantics.lean`, `Cycles/Generic/Search.lean`: heaps of
  objects with ground types, and the bounded search.
- `Cycles/Generic/Random.lean`: random programs with type formals.
- `GenericMain.lean`: the `search2` executable.

## Running

Install Lean with [elan](https://github.com/leanprover/elan), then:

```sh
lake build
lake exe search             # 500 random programs, up to 3 steps, seed 1
lake exe search 5000 4 7    # trials, depth, seed
lake exe search 5000 4 7 old  # without Step V's fake-class edges
lake exe search 5000 5 7 new 5 4  # 5 classes and 4 interfaces
lake exe search 20000 5 7 ext     # separate compilation
lake exe search2 3000 3 7         # Stage 2: type formals
lake exe search2 3000 3 7 rfc     # without the fix below
```

The search is exponential in the depth.  20000 programs at depth 5 take
about a minute; depth 6 is only practical for a few hundred.  It also
reports how many rejected programs make cycles, as a check that it can
find them.

Runs so far found no cycle in an accepted program:

| Programs | Classes, interfaces | Steps | Accepted | Rejected programs with cycles |
|---|---|---|---|---|
| 20000 | 3, 2 | 5 | 2410 | 14106 of 17590 |
| 10000 | 4, 3 | 5 | 767 | 7409 of 9233 |
| 5000 | 5, 4 | 5 | 210 | 4025 of 4790 |
| 300 | 2, 2 | 6 | 70 | 158 of 230 |
| 10000, `old` | 4, 3 | 5 | 824 | 7376 of 9176 |

In `ext` mode, each passing program got a random extension of 2 classes and
1 interface.  No class's result changed, and no extension that passed made
a cycle: 2945 programs extended (1218 passing) with 3 classes and 2
interfaces, and 401 (153 passing) with 4 and 3, all at depth 5.

## How the model differs from Temper

- Set-once properties can be set at any time, not just while a constructor
  runs.  That allows more heaps, so a soundness proof still applies.
- A property can't be set if any property of its class with the same name
  is early, so the proofs don't depend on names being unique.
- Properties have no defaults; non-early properties start unset.
- Each fixed point is computed by iterating once per node rather than with
  worklists.

## Fake classes and `forbids`

Step V used to leave a gap.  It didn't look past fake classes, so if `class
C(public i: I?) forbids Z` and `I` is a non-sealed interface, some other
library's implementation of `I` could point to a `Z` without `C`'s check
noticing.  Step V now gives each fake class an edge to each type the main
class forbids, after Step IV so that they can't cause false cycles.  The
`openForbids` example in `Main.lean` checks with and without them
(`check`'s `fakeForbidsEdges`).

Without those edges, the search still found no cycles in programs the
checker accepted (20000 programs, up to 5 steps).  So the gap broke
`forbids` promises, but may not have allowed cycles; a soundness proof for
acyclicity alone might get by with a weaker invariant.

## Stage 2: type formals

Types are named types with arguments, *AnyValue*, or type formals; type
arguments are invariant.  A graph's nodes are types over mainType's type
formals.  A type formal's node has can-be-a edges to its `extends` bounds,
or to *AnyValue*.  A sealed interface's node has can-be-a edges to its
sub-types, found by matching their super-type's arguments, which is why
`wellFormed` requires a sub-type to pass each of its type formals to a
sealed super-type.

`<T forbids Y>` means `T` neither binds to nor points to a `Y`.  The type
phrase check (`phraseOk`) checks it for each type argument `A`:

- `A` isn't a subtype of `Y`;
- `mayBeA A Y` is false; and
- in a graph from `A`, built like a class's graph but with `A`'s own
  clauses counting, Step V finds no has-a edge that can point to a `Y`.

The checker uses the clause in two ways.  A type formal's node counts as
declaring `Y` for Step III and Step V.  And `mayBeA` knows that `T` can't
be bound to a subtype of `Y`, which is what makes the RFC's `C<T forbids
String>` example pass.  A run-time object is only made at a type that
passes the check, standing in for the type phrase checks on the code that
made it.

`mayBeA` finds the classes that could have both types as super-types by
unifying, with the class's type formals bound consistently.  Without that,
`Cell<Cell<Str>>` failed `Cell<T forbids Cell<T>>`, as if `Cell<Str>` could
be a `Cell<Cell<Str>>`.

### Other instantiations of mainType

The search found that the RFC's checker missed cycles through another
instantiation of the class being checked:

```ts
class C<T>(public var c: C<Str>?) {}

let c = new C<Str>(null);
c.c = c; // a cycle
```

`C`'s graph starts at `C<T>`, whose `.c` edge goes to a separate `C<Str>`
node with a `.c` edge to itself.  That loop doesn't pass through mainNode,
so Step IV didn't report it, and no other class's check sees it.  The
sufficiency argument maps a run-time cycle through a `C<A>` into `C`'s
graph with `T` bound to `A`.  The cycle starts at mainNode, but it can end
at any node that is `C<A>` under that binding, such as `C<Str>`.

The fix, in the model and the RFC: Step II gives each node that could be
mainType, for some binding of its type formals, a can-be-a edge to
mainNode, labelled with the binding (`C<Str>` to `C<T>`, `T = Str`).  Step
IV then finds such cycles like any other.  The edges only lead into
mainNode, which is never "always" forbidden, so they don't change Step III's
pruning or Step V.  `check`'s `instances := .rfc`, and the `rfc` search
mode, leave them out.  The `otherInstance` example in `GenericMain.lean`
shows the difference.

### Results

(Pending.)
