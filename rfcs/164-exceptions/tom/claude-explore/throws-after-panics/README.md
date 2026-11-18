# Failure labels after bug-like builtins panic

If the builtins whose failures are bugs panicked instead of bubbling,
how many functions would still need a failure label (`throws Bubble`),
and how many of those are exported, not private? The second question is
the one that matters for inferring labels on private code. Drafted by
Claude, 2026-11-18, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
It covers the same sources as the
[no-failures audit](../../claude-option-no-failures-audit.md): Argmas,
Chromarite, Hrefine, Kelpto, Ordable, Wherewith, and tempest's
`lib/core` and `lib/std`, as of 2026-11-18, without test files.

## Model

- **These panic instead of bubbling:** `as` downcasts; list and map
  reads (`list[i]`, `Mapped.get`, plus `MapBuilder.remove`, treated
  like a read); Int `/` and `%` (Float64 division follows IEEE and
  doesn't fail); code points (`String.fromCodePoint(s)`,
  `StringBuilder.appendCodePoint`); and the narrowing conversions that
  are cheap range checks (`Int64.toInt32`, `Int64.toFloat64`,
  `Float64.toInt32`, `Float64.toInt64`).
- **These stay fallible:** parsing numbers from strings
  (`String.toInt32`, `toInt64`, `toFloat64`), JSON parsing, regex,
  promises and `await`, std/net, dates from strings, and
  `Generator.next`.
- A library's own `bubble()` stays a bubble. The variant column treats
  the six `bubble()`s that the audit found bug-like (Chromarite's
  index and size checks, std's misused JSON producer and test bail-out)
  as panics too.
- A function **needs a label** if, after the change, it can still fail
  through something it doesn't handle with `orelse`. That something is
  a `bubble()`, a builtin that stays fallible, or a call to a function
  that still needs a label. This is computed as a least fixpoint over
  the call graph. `orelse panic()` and `orelse x` both count as
  handled. An abstract interface method needs a label if any of its
  implementations does, or if hosts may implement it (an exported,
  unsealed interface: Argmas's `ValueType`, std's `JsonAdapter`, core's
  `Generator`).

## Method

[analyze.py](analyze.py) tokenizes the Temper code (indented blocks in
`.temper.md`, bare fences, and `.temper`) and finds each declaration
with its class, `export`, and `public`/`private`. In each body it finds
the failure sources that no `orelse` covers. It resolves calls by name,
arity, and receiver (a bare call goes to the same class first, and
`Class.f()` to that class). Where several candidates remain and the
choice changes the outcome, I read the code and recorded the target in
`RESOLVE`: 25 sites in labeled functions and 55 in `orelse` operands,
all listed in [results/summary.md](results/summary.md). Without those
choices, the total after the change lies between 228 (optimistic: the
call fails only if every same-named function does) and 256
(pessimistic: any of them). "Exported" means public API: an
`export let`, or a non-private member of an exported class or
interface. It matches the audit's 89 host-facing declarations library
by library.

```
uv run analyze.py ROOT results
uv run xcheck.py ../bench/markers/results/sites.tsv results/functions.tsv results/edges.tsv
```

Here, ROOT holds the checkouts side by side, as for the audit's
`scan.py`. The results are [functions.tsv](results/functions.tsv) (every
labeled function, with its status in each mode and why it stays),
[orelse.tsv](results/orelse.tsv) (every `orelse`, and whether its
operand still fails), [edges.tsv](results/edges.tsv),
[summary.md](results/summary.md), and [xcheck.txt](results/xcheck.txt).

**Checks:**

- A seeded sample of 20 labeled functions (seed 164, listed in
  `summary.md`), read by hand, from Chromarite, Wherewith, Kelpto,
  Hrefine, Argmas, std, and core: all 20 match.
- The call edges agree with the propagation sites that the
  [markers count](../bench/markers/) took from tempest's type-checked
  Rust output. Of 201 functions with failing callees, 185 have the
  same callee names. The other 16 differ only in naming (`toInt` and
  `toInt32`), in Int conversions that the name match finds and
  `RESOLVE` rules out (Rust has no site there either), or in map reads,
  which this scan leaves out of the edges.
- The scan finds 289 labeled functions, as the audit does (plus the
  same three labeled function types, which aren't counted).

## Results

| Library | Labeled today (exported / private) | Labeled after | Private after, only via calls | After, if bug-like `bubble()`s panic too | `orelse panic()` that go |
|---|---|---|---|---|---|
| Argmas | 8 (1 / 7) | 7 (1 / 6) | 0 | 7 (1 / 6) | 12 of 15 |
| Chromarite | 52 (3 / 49) | 38 (3 / 35) | 16 | 21 (1 / 20) | 33 of 67 |
| Hrefine | 24 (10 / 14) | 23 (10 / 13) | 2 | 23 (10 / 13) | 3 of 91 |
| Kelpto | 49 (25 / 24) | 49 (25 / 24) | 4 | 49 (25 / 24) | 216 of 293 |
| Ordable | 0 | 0 | 0 | 0 | 13 of 13 |
| Wherewith | 104 (7 / 97) | 104 (7 / 97) | 68 | 104 (7 / 97) | 6 of 9 |
| std | 37 (29 / 8) | 25 (19 / 6) | 4 | 20 (15 / 5) | 12 of 12 |
| core | 15 (14 / 1) | 6 (5 / 1) | 0 | 6 (5 / 1) | 1 of 1 |
| **All** | **289 (89 / 200)** | **252 (70 / 182)** | **94** | **230 (64 / 166)** | **296 of 501** |

"Only via calls" counts the private functions that still need a label
but contain no `bubble()` and no call to a fallible builtin: their
label comes only from a function they call. Inference on private code
would fill in all 182 private labels. These 94 are the ones where the
author writes nothing that fails at all.

## Findings

- **Panicking builtins remove few labels: 289 become 252.** Most labels
  exist because a library rejects its own input with `bubble()`:
  Wherewith's SQL parser and checker, Hrefine's URL parser, Kelpto's
  editing checks, Argmas's value parsers, and Chromarite's CSS parser.
  Others call builtins that stay fallible, such as number parsing,
  JSON, regex, and dates. The 37 labels that go are core's nine
  bug-like builtins, twelve in std, fourteen in Chromarite, Hrefine's
  `punycodeAdapt` (division only), and one Argmas override.
- **Inference on private code is where the savings are.** After the
  change, 182 of the 252 labels are on private functions. With
  inference, authors would write 70, a quarter of today's 289; in the
  variant, 64. Exported labels fall from 89 to 70, almost all of the
  drop in core and std; the rest are real input failures that callers
  need to see.
- **Wherewith is the heavy case.** All 104 labels stay, and 97 are
  private: the parser (`CommonParser` 24, `StatementParser` 20) and the
  checker (`CommonChecker` 17, `StatementChecker` 29, `NameCases` 7).
  Of those 97, 68 are labeled only via calls, including all 29 in
  `StatementChecker` and 16 of 17 in `CommonChecker`, which fail
  through `fail(message, at)`. Its 7 exported entry points (`quoteName`,
  `quoteString`, `Identifier.named`, `Query.checked`, `render`,
  `renderedParts`, `QueryBuilder.build`) bubble directly. With
  inference, Wherewith would write 7 labels instead of 104.
- **Chromarite depends on its own bug-like `bubble()`s.** Its matrix
  index and size checks (`Matrix.get`, `matrixRow`, `times`, and
  `Color.alphaAt`) are explicit `bubble()`s, so under the strict model
  38 of 52 labels stay. If those four become panics too, 21 stay, all
  in color parsing (CSS and hex). This is close to the audit's 22.
- **`orelse panic()`: 296 of 501 go**, 163 of the 213 outside tests.
  If the bug-like `bubble()`s become panics too, 329 go (the audit
  estimated 328). The `orelse panic()`s that stay guard calls that can
  still fail. Of Hrefine's 88 that stay, 83 are in tests that parse
  known-good URLs. Outside tests and Chromarite, 16 stay, each one an
  assertion that trusted input parses. Also, 17 of the 95 other `orelse` fallbacks
  can no longer be reached, such as Wherewith's division after a zero
  check.
- **The model turns some intended failures into panics.** Seven
  functions lose their label only because input checks become panics:
  - `as` on JSON input: `propertyValueOrBubble`, and the `Boolean` and
    `String` adapters.
  - A map read of an unknown color name: Chromarite's `parseNamed`.
  - Narrowing a parsed JSON number: `JsonFloat64.asInt32` and
    `asInt64`, and `JsonInt64.asInt32`.

  Their authors would switch to `is`, `has`, or range checks plus
  `bubble()`, and keep the labels.
- **Overrides:** 12 implementations can't fail but override an
  interface method that stays labeled, such as `JsonInt32.asInt32 {
  content }` and Argmas's `StringType.parse`. They're counted as
  unlabeled, which holds only if an override may drop its parent's
  label.
- **Three labels aren't needed even today:** Chromarite's `adjustLch`,
  `lchIn`, and `assertConvertColors` call nothing that fails.

## Limits

- The scan has no types. Name resolution is checked by hand where it
  matters, and against the Rust output, but a call that is wrong for
  other reasons could still slip through.
- **Function values:** only std's `TestFun` is a labeled function type.
  Its two call sites are already handled. A trailing block's sources
  count toward the function that encloses it.
- **Tests:** functions in test files and in-file `test` blocks aren't
  counted. The `orelse` counts include in-file tests, as the audit's
  do.
- **Model choices that are open questions:** `MapBuilder.remove`
  panicking like a read, `Int64.toFloat64` counting as a range check,
  and `Generator.next` staying fallible.
