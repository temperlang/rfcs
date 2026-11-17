# Proposal: functional interfaces vs. arrow types

Author(s): Mike S.

Last updated: 2026-11-17

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/667

## Abstract

Functional interface types help avoid having to translate ad-hoc function types.

They also communicate intent. `Predicate<String>` is more self-documenting than `Fn (String): Boolean`.

Functional interfaces can also store useful metadata.  For example [`forbids` clauses](../659-memory-management/README.md) can appear on interfaces, so there's no need to separately specify them on arrow types.

But existing backends for targets that don't have arrow types do translate function types.

Are ad-hoc function types a problem in Tempest?
Are they a problem for target languages we have yet to encounter?

Should we keep arrow types, but capitalize the "fn" to "Fn" or something
similar to keep with our style convention that type names are
UpperCamel?

Or should we excise function types that appear lexically from existing code?

We need a decision.


## Background



## Proposal


## Rationale


## Compatibility


## Implementation



## Testing and examples



## Documentation


## Effect on Backends

## Open Issues

