# Formal verification: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-20, for
[#680](https://github.com/temperlang/temper/issues/680). Suggestions
only; nothing here is decided.

## What could be verified

Three different things, with very different costs:

1. **Properties of Temper libraries** (an encoder preserves order, a
   parser round-trips, a function never fails on valid input).
   Feasible: Temper is small, statically typed, and structured, with no
   shared-memory threads or pointer arithmetic, which is the profile
   verifiers handle well.
2. **The language itself** (typing is sound, "nullable until narrowed"
   holds, the cycle checker's guarantee holds). Feasible in parts, as a
   mechanized core calculus; [RFC 659](../../659-memory-management/README.md)
   already has an experimental Lean mechanization of parts of the cycle
   checker.
3. **The compiler** (every translation to every backend preserves
   meaning). A full proof is impractical: it's compiler-verification
   scale for each of seven targets, and each target's semantics
   (floating point, integer wrapping, strings, runtimes) would need
   formalizing too. Testing gives most of the practical assurance here.

## Tiers, cheapest first

- **Property-based tests.** Generators for std types, shrinking, and
  seeds, run by `temper test` on every backend. The same properties are
  the specs a verifier would later check.
- **Contracts in Temper.** Preconditions, postconditions, loop
  invariants, and termination measures, written as decorators or a small
  annotation syntax. Backends ignore them, or check them at run time in
  debug and test builds; they also document intent.
- **A verification backend.** Translate core's typed IR, with its
  contracts, to an existing verifier (Dafny, Why3, F*, or Lean) and let
  it prove them. Generated code for users still comes from the usual
  backends, so verification never costs idiomatic output.
- **A mechanized core calculus** in Lean, extending the cycle-checker
  work: typing soundness for the core, failures, `Never`, and nullable
  narrowing.
- **For the compiler:** differential testing (every backend must match
  the interpreter; the shared test programs and core-body checks already
  do this), fuzzing with generated programs through all backends, and
  translation validation for small, critical pieces.

## Dafny

Dafny is the closest existing language to Temper in shape: one source
compiled to several languages (C#, Java, JavaScript, Go, and Python,
with Rust added more recently; check current targets), with a runtime
library per target. Its center is verification: `requires`, `ensures`,
`invariant`, and `decreases` are checked at compile time by an SMT
solver, with ghost code that never reaches the output. It is used to
write libraries shipped to several languages, the AWS Encryption SDK
and the Cedar authorization engine being the well-known cases.

Its generated APIs expose Dafny's own runtime types (sequences, maps),
so idiomatic host APIs need an extra layer; Smithy-Dafny generates
wrappers from Smithy models for that. Temper treats idiomatic host APIs
as part of the language's job
([#676](https://github.com/temperlang/temper/issues/676)).

How Temper could relate to it:

- **Borrow its vocabulary.** If Temper's contracts use the same concepts
  (`requires`, `ensures`, `invariant`, `decreases`, pure functions for
  specs), translating to Dafny is direct and users who know Dafny feel at
  home.
- **Use it as a verification backend.** Temper code with contracts
  translated to Dafny for checking, while the regular backends generate
  the shipped code. This gets Dafny's prover without asking users to
  write Dafny.
- **Be clear about the difference.** Dafny optimizes for proofs; Temper
  optimizes for idiomatic libraries in every language. Contracts would
  give Temper an assurance story without changing that center.

## Questions

- **Spec language.** What can contracts call: only pure Temper
  functions? Quantifiers? How are specs kept out of generated code (the
  equivalent of ghost code)?
- **Which verifier.** Dafny is closest in shape and has the most
  automation; Lean fits the language-level proofs already under way;
  Why3 targets several provers. One translation target first.
- **Failures and effects.** How contracts describe bubbling (and its
  successor from RFC 164), panics, and effects (RFC 674); pure,
  effect-free functions are the easiest to verify, which fits the
  libraries' "pure Temper first" direction.
- **Floating point and integer wrapping.** Verifiers model these
  differently from hosts; contracts on `Float64` code need care.
- **Runtime checking.** Whether contracts become assertions in debug or
  test builds on every backend, which is useful even without proofs.

## Related

- Property-based testing (planned): the first tier.
- [RFC 659](../../659-memory-management/README.md): the Lean
  mechanization of the cycle checker.
- [#673](https://github.com/temperlang/temper/issues/673): negative
  testing.
- [#674](https://github.com/temperlang/temper/issues/674): pluggable
  effects, for keeping verified code pure.
- [#164](https://github.com/temperlang/temper/issues/164): failure
  handling, which contracts must describe.
