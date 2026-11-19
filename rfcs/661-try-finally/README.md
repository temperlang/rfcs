# Proposal: `finally`

Author(s): Mike S.

Last updated: 2026-11-17

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/661

## Abstract

`try { ... } finally { ... }` syntax needs to be translatable to Rust which does not natively have such a thing but which does have nested functions and Golang which has deferred functions but also does not have `try { ... } finally { ... }`, and legacy languages which predate structured resource management.

The sweet spot seems to be a `finally` block which has the same constraints as if the `finally block` were replaceable with a call to a nested function / subrouting.

Explore TmpL having an option to produce a try/finally construct or producing a nested function and putting in simpler constructs that have strategically positioned calls to a subroutine. The as-if a subroutine would avoid code-size blowups.

This will capture lots of test cases to ensure that we can produce control-flow that passes different target languages initialized-before-use and let declarations are not multiply assigned compiler checks that often have worst-case assumptions around try/finally. And it will explore what TmpL translation switches allow for passing those static checks.

> [!NOTE]
> Tom: For RFC 164 on exception handling, I'm working through matters like `sum += ys[i] ?? continue;`, which overlap try/finally needs somewhat. I'm currently trying to keep the related scope there bounded, though, instead of sucking up all try/finally requirements.

## Background



## Proposal


## Rationale


## Compatibility


## Implementation



## Testing and examples



## Documentation


## Effect on Backends

## Open Issues

