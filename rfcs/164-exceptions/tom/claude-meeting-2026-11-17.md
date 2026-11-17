# Notes from Tom and Mike's meeting, 2026-11-17, with Claude's reading

## Tom and Mike's notes

As Tom took them at the meeting, some from Mike's statements or questions:

- remember to pretend golang in exception analysis
- make example translations
- consider checked and unchecked in java, not *required* in java
- library-specific exceptions
- hiding temper name from library users
- failure values connect to actual exception types on backends vs any old temper type?
- Are there widely used languages that use `throw` that constrain equality and stringification for throwable types?
- consider different naming for panicky vs bubbly vs nullable vs ...

## Claude's reading

Written afterward by Claude, to turn the list into work for the proposals
([declared](claude-proposal-declared.md), [values](claude-proposal-values.md),
[common ground](claude-common-ground.md), and
[recommendation](claude-recommendation.md)).

1. **Go as a target.** Every "what each backend generates" table should
   include Go as if it were a backend: `(value, err)` returns, `errors.Is`
   and `errors.As` for typed failures, and `panic`/`recover` for panics. Go
   is the strongest test of the values proposal and a hard case for
   declared failures, since it has no exceptions to map to.
2. **Example translations.** Tables summarize, but generated code shows
   what users would actually get. The shared worked example (Wherewith's
   `select` rule) should be written out as each backend would generate it,
   under both proposals, so the team can read real code side by side.
3. **Java, checked or unchecked.** Checked exceptions match Temper's own
   checking but are out of fashion and awkward with lambdas and streams;
   unchecked ones fit modern Java and Kotlin callers. Java doesn't require
   either. The proposals should state a default and whether a library can
   choose.
4. **Library-specific exceptions.** Each library could have one generated
   base type (`ArgmasError`, `WherewithError`) that all its failures
   extend, so host code can catch everything from one library, as Python
   code catches `requests.RequestException`. With single inheritance in
   Java and C#, that base and an idiomatic category base (such as
   `IllegalArgumentException`) can't both be superclasses; that needs a
   decision.
5. **No Temper name in what library users see.** Host-facing failure types
   belong to the library, never to Temper (no `TemperBubble`, no
   `temper_core.Failure` in what users catch). Today only C++ and Rust
   expose a catchable type for bubbling, and both are named after Temper,
   so this touches current output too.
6. **Which types can be failures.** The values proposal lets a result carry
   any type; Mike's design requires declared throwable types that map to
   exception classes. With any type allowed, the exception form wraps the
   value in a library exception that carries it; with only throwables, the
   mapping is direct but less flexible. Both proposals should state their
   answer and its effect on host code.
7. **Constraints other languages put on throwable types.** From memory, to
   be checked by a survey: stringification is usually required or provided
   (Rust's `std::error::Error` requires `Display` and `Debug`; Go's `error`
   requires `Error() string`; Java, C#, and Python get a message from their
   base class; C++'s `std::exception` has `what()`, though anything can be
   thrown; JavaScript can throw anything, with `Error.message` by
   convention), while equality is almost never constrained (identity by
   default in Java, C#, and Python; Rust and Swift don't require `Eq` or
   `Equatable` for errors). If the survey confirms it, Temper's failure
   types should always provide a message and need not define equality.
8. **Naming across failure styles.** Functions that panic, bubble, or
   return null for the same operation need one naming rule, for Temper's
   std and for generated host APIs alike, the same rule the boundary forms
   need. Precedents: Kotlin's `parse` and `parseOrNull`, C#'s `Parse` and
   `TryParse`, Swift's `try?` and `try!`, and Rust's `unwrap` and `expect`.
   This belongs in the common ground.

Follow-up work: a survey of error types across languages (point 7 and
more), the example translations (point 2), and updates to the proposals,
common ground, and recommendation for points 1, 3, 4, 5, 6, and 8.
