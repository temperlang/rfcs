# Layout structs and value types

By Claude, 2026-11-18, as input for this RFC. Nothing here is decided;
all syntax is hypothetical. Value types themselves now have their own
RFC, [668](../../668-value-types/tom/claude-value-types.md)
([#668](https://github.com/temperlang/temper/issues/668)); this note
keeps what concerns layout.

## Layout structs as a subset?

One possible shape: a layout struct is a value type whose fields are
fixed-size scalars (`Int32`, `Float64`, fixed-width integers if Temper
gains them), other layout structs, or fixed-length arrays, with a
declared byte order and packing. Then:

- C, C++, Rust, C#, Go, and Swift get real `struct`s with matching
  layout (`#[repr(C)]`, `[StructLayout]`), readable straight from a
  blob where alignment allows.
- JavaScript, Java, Python, and Lua get ordinary objects plus generated
  read and write methods over `DataView`, `ByteBuffer`,
  `struct`/`memoryview`, and `string.pack`.

**Why they might not share a solution:**

- Layout cares about bytes (order, padding, alignment, fixed widths);
  value types care about semantics (immutability, identity). A
  general value type may hold strings and lists, which have no fixed
  layout.
- Binary formats often need variable-length parts, versioning, and
  validation that a struct type alone doesn't express; a schema or
  codec library (in Temper) might serve them better than a language
  feature.
- Mutation in place in a buffer (a view over bytes) is useful for
  binary work but contradicts value semantics.

So value types could come first as the semantic base, with layout
either built on them or kept separate as views or codecs over blobs.

## Open questions

- Fixed-width integer types for layout (`UInt8`, `Int16`, …) and how
  they map where hosts lack them (JavaScript, Lua).
- Endianness and alignment defaults for layout structs.
- Whether layout structs require value semantics, or whether mutable
  views over blobs are a separate feature.

