# Design A: bugs panic, parsing gives null

The same code as [current](../current/current.temper.md), with design
A's rules. Reading past a row's end is a bug, so `Matrix.get` panics
instead of bubbling, as list indexing already does by contract; with
that, no internal function needs `throws Bubble`, and the public
methods lose their `orelse panic()`. Parsing is the one real failure,
and gives null. (The same change fits designs B and C: neither has a
failure to declare here. See [hypothetical](../hypothetical.md).)

Integer `%` and `/`, and Float64 `/`, still bubble on division by zero
today, so they keep `orelse panic()`; if builtins like these panicked
instead (#164's proposal), those would go too.

## Matrix

    class Matrix(
      public ncols: Int,
      private values: List<Float64>,
    ) {
      public nrows: Int = do {
        if (ncols <= 0) { panic() }
        if (((values.length % ncols) orelse panic()) != 0) { panic() }
        (values.length / ncols) orelse panic()
      };

      public get(i: Int, j: Int): Float64 {
        if (j < 0 || j >= ncols) { panic() }
        values[i * ncols + j]
      }

      public toList(): List<Float64> { values }
    }

    let times(a: Matrix, b: Matrix): Matrix {
      if (a.ncols != b.nrows) { panic() }
      let out = new ListBuilder<Float64>();
      for (var i = 0; i < a.nrows; i += 1) {
        for (var k = 0; k < b.ncols; k += 1) {
          var sum = 0.0;
          for (var j = 0; j < a.ncols; j += 1) {
            sum += a[i, j] * b[j, k];
          }
          out.add(sum);
        }
      }
      new Matrix(b.ncols, out.toList())
    }

## Color

    export class Color {
      private rows: Matrix;

The constructor takes plain values: the C# backend makes private
constructors public, and C# then rejects an internal type in a public
signature.

      private constructor(values: List<Float64>) { this.rows = new Matrix(3, values); }

      public get length(): Int { rows.nrows }

      public get(i: Int, j: Int): Float64 { rows[i, j] }

      public static fromList(values: List<Float64>): Color { new Color(values) }

      public inGamut(): List<Boolean> { inGamutRows(this) }

      public scaled(factor: Float64): Color {
        new Color(times(rows, new Matrix(3, [factor, 0.0, 0.0, 0.0, factor, 0.0, 0.0, 0.0, factor])).toList())
      }

Null for text that isn't a color. A CSS parser could say why (a
`Result` with a reason, as in the other cases), but for colors most
callers want a fallback: `Color.parse(text) ?? black`.

      public static parse(text: String): Color? { parseHex(text) }
    }

    let inGamutRows(color: Color): List<Boolean> {
      let builder = new ListBuilder<Boolean>();
      for (var i = 0; i < color.length; i += 1) {
        builder.add(inUnitCube(color[i, 0], color[i, 1], color[i, 2]));
      }
      builder.toList()
    }

    let inUnitCube(x: Float64, y: Float64, z: Float64): Boolean {
      x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0 && z >= 0.0 && z <= 1.0
    }

## Parsing

`hexDigit` gives -1 for a code point that isn't a hex digit, a sentinel
rather than null, since it's internal and called per character.
Returning `Int?` would read as well; on the JVM it would box.

    let parseHex(text: String): Color? {
      let digits = new ListBuilder<Int>();
      var i = String.begin;
      if (text.hasIndex(i) && text[i] == char'#') { i = text.next(i); }
      for (; text.hasIndex(i); i = text.next(i)) {
        let d = hexDigit(text[i]);
        if (d < 0) { return null; }
        digits.add(d);
      }
      let count = digits.length;
      if (count != 3 && count != 6) { return null; }
      let channels = new ListBuilder<Float64>();
      for (var c = 0; c < 3; c += 1) {
        let byte = if (count == 3) { digits[c] * 17 } else { digits[2 * c] * 16 + digits[2 * c + 1] };
        // Float64 `/` bubbles today (by the docs), even by 255.0.
        channels.add((byte.toFloat64() / 255.0) orelse panic());
      }
      Color.fromList(channels.toList())
    }

    let hexDigit(codePoint: Int): Int {
      if (codePoint >= char'0' && codePoint <= char'9') {
        codePoint - char'0'
      } else if (codePoint >= char'A' && codePoint <= char'F') {
        codePoint - char'A' + 10
      } else if (codePoint >= char'a' && codePoint <= char'f') {
        codePoint - char'a' + 10
      } else {
        -1
      }
    }

## Tests

    test("gamut") {
      let c = Color.fromList([0.5, 0.5, 0.5, 1.2, 0.0, 0.0]);
      let inside = c.inGamut();
      assert(inside[0] && !inside[1]);
      assert(!c.scaled(3.0).inGamut()[0]);
    }

    test("parse") {
      let c = Color.parse("#0080ff");
      assert(c != null && c[0, 2] == 1.0);
      assert(Color.parse("#08f") != null);
      assert(Color.parse("#08g") == null);
      assert(Color.parse("#0080") == null);
    }
