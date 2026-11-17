# Case: Chromarite's internal `throws Bubble` chain

Chromarite, a Temper library, converts and mixes colors. Colors are
rows of channels in a `Matrix`, and `Matrix.get(i, j)` bubbles when
`j` is past the row's end. So everything that reads a matrix is
`throws Bubble` (52 lines in Chromarite declare it), and every public
method turns that back into a panic with `orelse panic()`, since an
index out of range there is Chromarite's own bug. Integer `%` and `/`,
and Float64 `/`, bubble on division by zero, so they get
`orelse panic()` too. Of all those failures, only parsing (`Color.parse`)
is one a caller causes with input.

Files:

- [current/current.temper.md](current/current.temper.md): today's code,
  simplified (runnable, with tests).
- [values/values.temper.md](values/values.temper.md): design A
  (runnable, with tests).
- [hypothetical.md](hypothetical.md): panicking arithmetic, and
  parsing under A, B, and C. **Not runnable.**

## How each design reads

```temper
// Today (runnable)
public get(i: Int, j: Int): Float64 throws Bubble {
  if (j >= ncols) { bubble() }
  values[i * ncols + j]
}
let inGamutRows(color: Color): List<Boolean> throws Bubble { ... color[i, 0] ... }
public inGamut(): List<Boolean> { inGamutRows(this) orelse panic() }

// A, B, and C alike: a bug panics, so nothing is declared
public get(i: Int, j: Int): Float64 {
  if (j < 0 || j >= ncols) { panic() }
  values[i * ncols + j]
}
let inGamutRows(color: Color): List<Boolean> { ... }
public inGamut(): List<Boolean> { inGamutRows(this) }
```

Parsing, the one real failure:

```temper
public static parse(text: String): Color throws Bubble { parseHex(text) }          // Today
public static parse(text: String): Color? { parseHex(text) }                       // A (runnable)
public static parse(text: String): Color throws InvalidColor { parseHex(text)! }   // B (HYPOTHETICAL)
public static parse(text: String): Color throws InvalidColor { try parseHex(text) } // C (HYPOTHETICAL)
```

## What host code sees

| | Python | Java | Rust |
|---|---|---|---|
| Today | `color.get(0, 3)` and `Color.parse("#08g")` both raise `RuntimeError` | both `RuntimeException` | both `Err(Error(None))` |
| A | `get` panics; `parse` returns `None` | `AssertionError`; `null` | `panic!`; `Option<Color>` |
| B, C | `get` panics; `parse` raises a generated `InvalidColor` | the same, thrown | `Result<Color, …>` |

## Notes

- **This case is about panics, not failure values.** Once a bug panics
  instead of bubbling, designs A, B, and C read the same, and the
  internal chain disappears: no `throws Bubble` outside the parser, and
  no `orelse panic()` in the public methods. Today a caller can even
  "handle" a bug: `c[0, 3] orelse -1.0` gives -1.0 (a test in
  [current](current/current.temper.md) shows it).
- **The remaining `orelse panic()` are on builtins.** `%`, `/`, and
  Float64 `/` bubble today, even `byte.toFloat64() / 255.0`. #164
  proposes making bug-like builtins panic; list indexing already does
  by contract. With both, only Chromarite's 21 parser declarations
  would remain, under any design.
- **A sentinel or a nullable inside hot code:** `hexDigit` in the A
  version returns -1 rather than `Int?`, since it's internal and runs
  per character; on the JVM an `Int?` boxes (the benchmark in
  [bench](../bench/README.md) shows boxing costs once nulls appear).
- Code lines: 78 today, 81 under A (a comment and a bounds check
  added); the difference is in declarations, not length.

## Precedence

Nothing here depends on a default or propagation operator once bugs
panic. Today's `((values.length % ncols) orelse panic()) != 0` needs
its parentheses: without them, `values.length % ncols orelse panic() !=
0` would mean `… orelse (panic() != 0)`.

Run: `temper test -w . -b interp -b py -b js` (or any other backends)
in a copy of this folder. `current` and `values` are separate libraries,
since the C++ backend puts all of a library's exports in one namespace
and both define the same names.
