# Chromarite internals: hypothetical versions

**None of the code on this page compiles today.** It shows how
[current](current/current.temper.md) and [values](values/values.temper.md)
would read under each design, with syntax invented for the comparison.

## All three designs, with panicking arithmetic (hypothetical)

Here the designs agree: an index out of range is Chromarite's own bug,
so it panics, and nothing is declared. What changes the code further
is a separate question, #164's proposal to make bug-like builtins
panic. If Int `%` and `/`, and Float64 `/`, panicked on division by
zero (or Float64 `/` followed IEEE 754, as five backends already do),
the remaining `orelse panic()`s go:

```temper
// HYPOTHETICAL: `%` and `/` panic (or give Infinity/NaN) rather than bubble.
public nrows: Int = do {
  if (ncols <= 0) { panic() }
  if (values.length % ncols != 0) { panic() }
  values.length / ncols
};

channels.add(byte.toFloat64() / 255.0);
```

## Parsing, per design (hypothetical)

```temper
// A with a propagation operator: hexDigit could return Int? and
// parseHex propagate with `?`.
let d = hexDigit(text[i])?;

// B: one declared failure type.
export throwable class InvalidColor(public text: String) {}
public static parse(text: String): Color throws InvalidColor { parseHex(text)! }

// C: a declared kind.
error case InvalidColor;
public static parse(text: String): Color throws InvalidColor { try parseHex(text) }
```

For B and C, `hexDigit` and `parseHex` would declare the same failure
(or convert at `parse`); Chromarite's CSS parser (`src/css.temper.md`)
has most of the 21 parsing functions on that path, each of which would carry
the declaration, as each carries `throws Bubble` today.

## Count

In Chromarite today, 52 lines declare `throws Bubble`: 21 in the CSS,
named-color, and hex parsers, and 31 elsewhere (matrix access, mixing,
gamut mapping, adjusting, conversions), which bubble because of
indexing, `%`, `/`, and internal size checks. Of the public members, `Color.parse` is the one
failure a caller causes with input; `Color.get` and `Color.alphaAt`
bubble for an index out of range. With indexing and arithmetic
panicking, only the parsers' 21 would still declare a failure, under
any of the designs.

## What host code would see

| Design | Python | Java | Rust |
|---|---|---|---|
| Today | `color.get(0, 3)` raises `RuntimeError`; `Color.parse("#08g")` raises `RuntimeError` | `RuntimeException` for both | `Err(Error(None))` for both |
| A | `get` panics (`BaseException('panic')` today); `Color.parse` returns `None` | `AssertionError`; `parse` returns `null` | `panic!`; `Option<Color>` |
| B | `get` panics; `parse` raises `InvalidColor` | `AssertionError`; throws `InvalidColor` | `panic!`; `Result<Color, InvalidColor>` |
| C | `get` panics; `parse` raises `InvalidColor`, no detail | the same | `Result<Color, Kind>` |
