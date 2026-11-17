# Today: bubbles from indexing and arithmetic, panics at the API

Simplified from Chromarite (`src/matrix.temper.md`, `src/gamut.temper.md`,
`src/color.temper.md`, and `src/rgb.temper.md`). A `Matrix` holds rows
of channels; reading past a row's end bubbles, so everything that reads
a matrix is `throws Bubble`, and each public method turns that into a
panic, since an index out of range there is Chromarite's own bug.
Integer `%` and `/` bubble on division by zero, so they get
`orelse panic()` too. Only parsing is a failure a caller can cause.

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

      public get(i: Int, j: Int): Float64 throws Bubble {
        if (j >= ncols) { bubble() }
        values[i * ncols + j]
      }

      public toList(): List<Float64> { values }
    }

    let times(a: Matrix, b: Matrix): Matrix throws Bubble {
      if (a.ncols != b.nrows) { bubble() }
      let out = new ListBuilder<Float64>();
      for (var i = 0; i < a.nrows; i += 1) {
        for (var k = 0; k < b.ncols; k += 1) {
          var sum = 0.0;
          for (var j = 0; j < a.ncols; j += 1) {
            sum += (a[i, j] * b[j, k]) orelse panic();
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

      public get(i: Int, j: Int): Float64 throws Bubble { rows[i, j] }

      public static fromList(values: List<Float64>): Color { new Color(values) }

      public inGamut(): List<Boolean> { inGamutRows(this) orelse panic() }

      public scaled(factor: Float64): Color {
        new Color((times(rows, new Matrix(3, [factor, 0.0, 0.0, 0.0, factor, 0.0, 0.0, 0.0, factor])) orelse panic()).toList())
      }

      public static parse(text: String): Color throws Bubble { parseHex(text) }
    }

Internal, and `throws Bubble` only because `rows[i, 0]` can.

    let inGamutRows(color: Color): List<Boolean> throws Bubble {
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

`#rgb` or `#rrggbb`. Anything else bubbles: the one recoverable failure.

    let parseHex(text: String): Color throws Bubble {
      let digits = new ListBuilder<Int>();
      var i = String.begin;
      if (text.hasIndex(i) && text[i] == char'#') { i = text.next(i); }
      for (; text.hasIndex(i); i = text.next(i)) {
        digits.add(hexDigit(text[i]));
      }
      let count = digits.length;
      if (count != 3 && count != 6) { bubble() }
      let channels = new ListBuilder<Float64>();
      for (var c = 0; c < 3; c += 1) {
        let byte = if (count == 3) { digits[c] * 17 } else { digits[2 * c] * 16 + digits[2 * c + 1] };
        channels.add(byte.toFloat64() / 255.0);
      }
      Color.fromList(channels.toList())
    }

    let hexDigit(codePoint: Int): Int throws Bubble {
      if (codePoint >= char'0' && codePoint <= char'9') {
        codePoint - char'0'
      } else if (codePoint >= char'A' && codePoint <= char'F') {
        codePoint - char'A' + 10
      } else if (codePoint >= char'a' && codePoint <= char'f') {
        codePoint - char'a' + 10
      } else {
        bubble()
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
      let c = Color.parse("#0080ff") orelse panic();
      let blue = c[0, 2] == 1.0;
      assert(blue);
      assert((do { Color.parse("#08f"); true } orelse false));
      assert(!(do { Color.parse("#08g"); true } orelse false));
      assert(!(do { Color.parse("#0080"); true } orelse false));
    }

Out-of-range reads bubble rather than panic, so a caller can "handle"
a bug:

    test("a bug as a fallback value") {
      let c = Color.fromList([0.5, 0.5, 0.5]);
      let fallback = (c[0, 3] orelse -1.0) == -1.0;
      assert(fallback);
    }
