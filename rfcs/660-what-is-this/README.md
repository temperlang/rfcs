# Proposal: What is the meaning of `this`!?

Author(s): Mike S.

Last updated: 2026-11-17

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/660

## Abstract

`this` has one meaning in method, constructor, getter/setter bodies, and property initializers.

It has another meaning inside `test("testname") { ... } blocks.`

It'd be nice if we could have lambdas use `this` implicitly to enable idioms like the below, touched on in [RFC 659](../659-memory-management/README.md):

```
buildList {
  add(1)    // equivalent to this.add(1)
}
```



## Background



## Proposal


## Rationale


## Compatibility


## Implementation



## Testing and examples



## Documentation


## Effect on Backends

## Open Issues

