# Proposal: When to inline a call based on explicit function decorations

Author(s): Mike S.

Last updated: 2026-11-17

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/662

## Abstract

Our semantics around which calls can / must be inlined is a step towards user-space macros and is a thorny in `test("....") { ... }` macros.

When inlining boils down to `assert(true)`, the surrounding test block might not be exercising what the author intends on backends and might warrant a warning.
Developers should be able to learn a few rules of thumb to know how not to have things like complex test code boil down to `true` instead of exercising the translation via translated tests.

This will capture a more complete specifications of what is inlined and is a good step before we get into meta-programming and supporting versioning and backwards compatibility.

Lets capture use cases and thoughts on semantics of function definitions, calls, and what decorations to provide.

## Background



## Proposal


## Rationale


## Compatibility


## Implementation



## Testing and examples



## Documentation


## Effect on Backends

## Open Issues

