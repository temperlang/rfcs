# Proposal: Top level definitions

Author(s): Mike S.

Last updated: 2026-11-17

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/666

## Abstract

Top-level `var`s are something that maybe we want to support in the
REPL, but top-level mutable state (including reassignable `var`s and
mutable values on `const` declarations) allows race-conditions and
unsynchronized data corruption hazards in a way that mutable local
variables and mutable values available to a single thread do not.

Temper has `@imu` as the basis for some checks around thread-safety: no
writer exclusion needed when not writable. But there are valid use
cases for top-level declarations: atomic integer boxes, thread-safe
caches of immutable keys and values like memo-tables.

A developer who is used to JavaScript and Python style, where you
rarely if ever worry about locking, should be steered away from unsafe
top-level mutable state by useful compiler diagnostics.

## Background


## Proposal


## Rationale


## Compatibility


## Implementation



## Testing and examples



## Documentation


## Effect on Backends


## Open Issues

