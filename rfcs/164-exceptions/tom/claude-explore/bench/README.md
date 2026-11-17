# Benchmark: the cost of failing, today and as values

How much a failure costs per backend, with today's `bubble()` and
`orelse`, with a nullable return, and with a result type written as
user code (design A as it can be written today). Back to
[the overview](../README.md).

## What runs

[src/failbench.temper.md](src/failbench.temper.md): a loop over `n`
inputs where a cheap step (`x * 3 + 1`) fails for F of them, spread
evenly through each block of 1000. Each failure counts as 0.
Successful values run from 1 to 3001, so most are outside the JVM's
cache of small `Integer`s (-128 to 127): a nullable `Int` on the JVM
allocates unless the JIT removes the box.

| Variant | The step | The caller |
|---|---|---|
| bubble | `Int throws Bubble`, `bubble()` | `stepBubble(x) orelse 0` |
| null | `Int?`, `return null` | `stepNull(x) ?? 0` |
| result | `Result<Int, Bad>`: `new Ok(...)` or `new Failed(new Bad(x))` | `when (r) { is Ok -> r.value; else -> 0 }` |
| long (Java only, hand-written) | a `long`, with `Long.MIN_VALUE` for null | `v == NONE ? 0 : (int) v` |

`long` stands for what a compiler could do with a nullable `Int`
returned by an internal function: a primitive with an out-of-range
sentinel, so nothing is boxed. It's written by hand in the Java
harness ([hosts/java/Bench.java](hosts/java/Bench.java)).

Each runs at depth 1 (the step fails, its caller handles it) and depth
5 (the failure passes up 4 more functions, each adding 1 on success;
the result variant makes a new `Ok` at each level and passes a
`Failed` up as it is). F is 0, 0.1, 1, and 10 percent. Inputs are
computed in the loop, not read from a list, so list access, which
differs a lot between backends, doesn't hide the cost of failing. A
test checks all variants give the same sums.

## How it was run

- tempest's `temper` 0.7.0-alpha on Linux x86-64: g++ 13.3 (`-O2`),
  .NET 6.0 (Release), OpenJDK 21, Node 24, Lua 5.4.6, CPython 3.12,
  and Rust 1.99 (`--release`). "interp" is tempest's interpreter.
- Host harnesses in [hosts/](hosts/) call the exported runners. Each
  backend, failure rate, and variant runs in a fresh process, so a JIT's
  profile from one doesn't shape the next. Warm-up runs (2 to 10), then
  7 timed runs; the median is taken. n = 200,000 for C++, C#, Java, JS,
  and Rust, and 50,000 for Lua and Python.
- interp has no clock, so each variant runs as a small library with
  `temper run -b interp`, timed from outside: 5 passes over 100,000
  inputs, less the time of a run with no passes; 7 such pairs, median.
- Two extra modes limit inlining, so a nullable `Int` really crosses
  calls, as it does where functions are too big to inline or are called
  through interfaces: **Java, steps not inlined** (HotSpot told not to
  inline the step functions and the four levels above them, generated
  and hand-written alike) and **C#, no inlining**
  (`DOTNET_JitNoInline=1`).
- Three rounds, back to back; each cell is the range of the three
  rounds' medians. The ratio columns divide by `null` within each round,
  which cancels noise shared by a round.
- **Two runs.** Run 1 (rates 0, 1, and 10 percent; failures spread per
  block of 100 rather than 1000) had the machine to itself. Run 2 (the
  code as it is now, adding 0.1 percent, the `long` variant, and the
  no-inlining modes) shared the machine with other jobs, so its absolute
  numbers spread widely; read its ratio columns. The two runs agree
  where they overlap.

To reproduce, from this folder: `temper build` (or
`temper test -b BACKEND`), then `uv run hosts/run.py BACKEND` (also
`java-noinline` and `csharp-noinline`), and
`uv run hosts/summarize.py results/run-*.txt`. Raw output is in
[results/](results/) (run 2, without Java),
[results/java/](results/java/) (run 2's Java rerun), and
[results/quiet/](results/quiet/) (run 1, rates converted to per mille).

## Run 1: all backends, quiet machine

ns per item.

#### Depth 1 (fails and is handled in the caller)

| Backend | F | bubble | null | result | bubble / null | result / null |
|---|---|---|---|---|---|---|
| interp | 0% | 1306-1353 | 1348-1407 | 2043-2145 | 0.9-1.0x | 1.5-1.6x |
|  | 1% | 1342-1656 | 1402-1676 | 2111-2158 | 1.0x | 1.3-1.5x |
|  | 10% | 1333-1434 | 1360-1414 | 2079-2287 | 1.0x | 1.5-1.6x |
| C++ | 0% | 2.1-2.4 | 2.0-2.1 | 86-97 | 1.0-1.2x | 41-48x |
|  | 1% | 13 | 2.1-2.2 | 77-89 | 5.9-6.1x | 35-40x |
|  | 10% | 116-128 | 2.1-2.7 | 80-84 | 48-58x | 30-40x |
| C# | 0% | 7.2-7.3 | 9.5-14 | 27-32 | 0.5-0.8x | 2.2-3.4x |
|  | 1% | 105-126 | 9.7-10 | 28-32 | 11-13x | 2.9-3.2x |
|  | 10% | 1073-1174 | 11-13 | 33-36 | 81-107x | 2.5-3.2x |
| Java | 0% | 2.7 | 2.6-3.0 | 3.1-4.2 | 0.9-1.0x | 1.2-1.6x |
|  | 1% | 11 | 3.8-6.2 | 12-14 | 1.8-2.9x | 1.9-3.6x |
|  | 10% | 62-69 | 3.7-5.5 | 13-17 | 11-18x | 2.4-4.2x |
| JS | 0% | 10-11 | 11-15 | 14-16 | 0.8-1.0x | 1.0-1.4x |
|  | 1% | 29-32 | 12-16 | 15-16 | 2.0-2.5x | 1.0-1.3x |
|  | 10% | 198-220 | 12-17 | 15-16 | 13-18x | 0.9-1.4x |
| Lua | 0% | 970-1187 | 730-1620 | 1479-1817 | 0.6-1.3x | 0.9-2.1x |
|  | 1% | 996-1112 | 771-916 | 1490-1779 | 1.2-1.3x | 1.8-2.0x |
|  | 10% | 901-1096 | 790-819 | 1592-1904 | 1.1-1.3x | 2.0-2.3x |
| Python | 0% | 1123-1337 | 1182-1233 | 1462-1525 | 1.0-1.1x | 1.2-1.3x |
|  | 1% | 1161-1269 | 1128-1274 | 1476-1530 | 1.0x | 1.2-1.3x |
|  | 10% | 1161-1280 | 1064-1246 | 1362-1742 | 0.9-1.2x | 1.2-1.5x |
| Rust | 0% | 1.3 | 1.3-1.4 | 172-191 | 0.9-1.0x | 132-139x |
|  | 1% | 1.3 | 1.3 | 173-178 | 1.0x | 133-137x |
|  | 10% | 1.2-1.7 | 1.3 | 176-202 | 0.9-1.3x | 135-155x |

#### Depth 5 (fails, then passes up 4 more calls)

| Backend | F | bubble | null | result | bubble / null | result / null |
|---|---|---|---|---|---|---|
| interp | 0% | 2273-2370 | 3025-3120 | 6349-6677 | 0.8x | 2.1-2.2x |
|  | 1% | 2318-2364 | 3073-3557 | 6406-7363 | 0.7-0.8x | 2.1x |
|  | 10% | 2268-2394 | 3093-3196 | 6430-6614 | 0.7-0.8x | 2.0-2.1x |
| C++ | 0% | 2.0-2.8 | 2.3-3.3 | 387-407 | 0.6-1.2x | 120-177x |
|  | 1% | 13-14 | 2.2-2.6 | 399-450 | 5.0-6.3x | 159-205x |
|  | 10% | 110-130 | 2.1-4.3 | 398-416 | 30-57x | 97-198x |
| C# | 0% | 7.0-7.1 | 49-66 | 126-133 | 0.1x | 2.0-2.6x |
|  | 1% | 108-111 | 49-56 | 124-138 | 1.9-2.3x | 2.2-2.7x |
|  | 10% | 1070-1160 | 46-48 | 120-248 | 22-25x | 2.5-5.3x |
| Java | 0% | 2.6-4.9 | 2.7-3.2 | 4.8-5.0 | 1.0-1.5x | 1.6-1.8x |
|  | 1% | 12-19 | 8.1-9.6 | 26-49 | 1.3-2.3x | 2.7-6.0x |
|  | 10% | 70-80 | 8.2-8.4 | 21-42 | 8.5-9.5x | 2.6-5.2x |
| JS | 0% | 11-18 | 17-18 | 28-33 | 0.6-1.0x | 1.6-1.8x |
|  | 1% | 34-35 | 17-18 | 33-37 | 1.9-2.0x | 1.9-2.1x |
|  | 10% | 242-280 | 18-19 | 34-38 | 13-15x | 1.8-2.0x |
| Lua | 0% | 1286-2366 | 1293-2091 | 5020-5265 | 1.0-1.1x | 2.5-3.9x |
|  | 1% | 1287-1416 | 1325-1458 | 4824-5657 | 0.9-1.0x | 3.6-3.9x |
|  | 10% | 1273-1394 | 1274-1420 | 4751-4814 | 1.0x | 3.4-3.7x |
| Python | 0% | 1774-1996 | 1756-1985 | 3227-3548 | 0.9-1.1x | 1.7-2.0x |
|  | 1% | 1808-2150 | 1886-2251 | 3320-3562 | 0.8-1.1x | 1.5-1.8x |
|  | 10% | 1868-2027 | 1850-2089 | 2888-4063 | 0.9-1.0x | 1.6-2.1x |
| Rust | 0% | 1.3-1.6 | 1.3-1.5 | 888-931 | 1.0-1.1x | 620-706x |
|  | 1% | 1.2-1.6 | 1.3-1.5 | 867-893 | 0.9-1.1x | 596-680x |
|  | 10% | 1.2-1.4 | 1.3-1.9 | 848-874 | 0.7-1.0x | 460-663x |

## Run 2: Java and C#, boxing and inlining

ns per item. The Java rows come from a separate three-round rerun with
the machine to itself (the first attempt ran a correctness check with
failures before timing, which put nulls into the JIT's profile for the
0 percent runs). The other backends' run 2 numbers are in the raw
results and agree with run 1 in shape.

#### Depth 1 (fails and is handled in the caller)

| Backend | F | bubble | null | result | bubble / null | result / null |
|---|---|---|---|---|---|---|
| C# | 0% | 18-24 | 12-16 | 31-64 | 1.2-1.9x | 2.1-5.1x |
|  | 0.1% | 21-36 | 7.5-12 | 28-52 | 2.5-4.8x | 3.7-4.5x |
|  | 1% | 115-241 | 7.3-12 | 29-56 | 15-20x | 3.2-4.6x |
|  | 10% | 1201-3429 | 7.9-18 | 33-69 | 86-189x | 2.5-4.2x |
| C#, no inlining | 0% | 10-16 | 7.1-26 | 27-63 | 0.6-1.9x | 2.4-3.8x |
|  | 0.1% | 21-36 | 6.8-14 | 29-75 | 2.5-3.6x | 3.8-5.2x |
|  | 1% | 120-206 | 7.3-11 | 30-44 | 16-19x | 4.0-6.0x |
|  | 10% | 1322-1872 | 9.0-41 | 31-109 | 41-147x | 2.7-3.4x |

Java, with the hand-written `long` variant:

| Backend | F | bubble | null | result | long | bubble / null | result / null | long / null |
|---|---|---|---|---|---|---|---|---|
| Java | 0% | 2.3-4.0 | 2.2-2.5 | 2.8-4.8 | 2.4-4.1 | 1.0-1.6x | 1.3-1.9x | 1.0-1.6x |
|  | 0.1% | 3.2-4.8 | 3.2-3.5 | 12 | 2.2-3.6 | 1.0-1.5x | 3.5-3.7x | 0.7-1.1x |
|  | 1% | 12-18 | 3.3-4.4 | 13-16 | 2.4-2.5 | 3.2-4.1x | 3.5-4.6x | 0.5-0.7x |
|  | 10% | 61-72 | 3.5-5.7 | 11-13 | 3.0-3.7 | 11-21x | 2.1-3.3x | 0.6-0.9x |
| Java, steps not inlined | 0% | 3.6-4.0 | 3.8-5.0 | 15-19 | 3.4-3.7 | 0.7-0.9x | 3.2-3.9x | 0.7-0.9x |
|  | 0.1% | 4.7-7.2 | 4.4-4.6 | 14-19 | 3.9-4.2 | 1.0-1.6x | 3.2-4.1x | 0.8-0.9x |
|  | 1% | 15-18 | 4.3-8.8 | 13-16 | 3.5-4.9 | 2.0-3.5x | 1.8-3.1x | 0.6-1.0x |
|  | 10% | 90-96 | 3.8-7.1 | 13-17 | 3.7-3.9 | 14-25x | 2.3-3.5x | 0.5-1.0x |

#### Depth 5 (fails, then passes up 4 more calls)

| Backend | F | bubble | null | result | bubble / null | result / null |
|---|---|---|---|---|---|---|
| C# | 0% | 8.8-15 | 51-98 | 108-168 | 0.1-0.3x | 1.6-2.1x |
|  | 0.1% | 21-39 | 47-112 | 138-170 | 0.4x | 1.5-3.0x |
|  | 1% | 104-229 | 51-108 | 124-189 | 2.0-2.3x | 1.8-2.5x |
|  | 10% | 1225-1798 | 55-96 | 133-213 | 19-23x | 2.2-2.8x |
| C#, no inlining | 0% | 9.2-22 | 54-118 | 125-172 | 0.2x | 1.5-2.9x |
|  | 0.1% | 20-32 | 54-99 | 125-141 | 0.3-0.4x | 1.4-2.6x |
|  | 1% | 123-199 | 60-96 | 141-208 | 1.3-2.7x | 1.5-2.9x |
|  | 10% | 1424-1595 | 50-83 | 138-257 | 17-32x | 2.7-3.1x |

Java, with the hand-written `long` variant:

| Backend | F | bubble | null | result | long | bubble / null | result / null | long / null |
|---|---|---|---|---|---|---|---|---|
| Java | 0% | 2.3-3.4 | 2.4-3.6 | 4.2-4.7 | 2.3-3.4 | 0.9-1.0x | 1.2-2.0x | 0.6-1.4x |
|  | 0.1% | 3.2-3.8 | 12-14 | 27-71 | 2.3-3.5 | 0.2-0.3x | 2.2-5.2x | 0.2-0.3x |
|  | 1% | 13-20 | 9.1-12 | 26-45 | 2.3-2.5 | 1.1-2.2x | 2.8-4.4x | 0.2-0.3x |
|  | 10% | 72-76 | 7.9-8.5 | 24-35 | 2.5-3.0 | 8.5-9.5x | 3.1-4.1x | 0.3-0.4x |
| Java, steps not inlined | 0% | 9.6-11 | 15-17 | 28-44 | 10-11 | 0.6-0.7x | 1.7-2.6x | 0.6-0.7x |
|  | 0.1% | 12-14 | 17-26 | 27-46 | 12-17 | 0.5-0.8x | 1.0-2.3x | 0.5-0.9x |
|  | 1% | 25-29 | 14-25 | 24-41 | 11-12 | 1.2-2.0x | 1.7-1.9x | 0.5-0.8x |
|  | 10% | 148-217 | 15-30 | 25-34 | 12-18 | 7-10x | 1.1-1.9x | 0.4-1.2x |

## What it shows

- **Nullable returns cost about nothing over today's success path on
  most backends, and nothing extra per failure.** The exceptions are
  the two managed runtimes:
  - **JVM:** a nullable `Int` is a boxed `Integer`, and the values
    here are outside its small-value cache. If a null never occurs on a
    path, the JIT removes the boxes and `null` costs the same as
    `bubble` (2.4-3.6 against 2.3-3.4 ns at depth 5, no failures). Once
    nulls do occur, the boxes stay: at 0.1 percent failures, depth 5,
    `null` takes 12-14 ns against bubbling's 3.2-3.8, about 3.5 to 4
    times as long, so there bubbling is cheaper. Bubbling becomes the
    dearer one between 0.1 and 1 percent (at 1 percent, 13-20 against
    9-12), and is 8.5 to 9.5 times dearer at 10 percent. With the steps
    not inlined, `null` costs 1.5 times bubbling even with no failures
    (15-17 against 10-11). At depth 1, inlining hides all of this.
    The hand-written `long` sentinel costs 2.3 to 3.5 ns at every rate
    and depth when inlined (10 to 18 not inlined, like bubbling with no
    failures): what lowering an internal function's `Int?` to a
    primitive could save, both against boxing and against exceptions.
  - **.NET 6:** `int?` is a struct, so nothing is allocated, yet five
    levels of `int?` returns cost 50 to 110 ns per item against 9 to 22
    for bubbling (0.1 to 0.4 times), with or without inlining, in both
    runs. Bubbling is cheaper until failures pass about 0.1 to 1
    percent; then a .NET exception costs about 10 µs each (86 to 189
    times `null` at 10 percent, depth 1).
- **Today's bubble is free until it fails, then expensive where it is
  an exception:** in run 1 at 10 percent failures, depth 1, C# runs 81
  to 107 times slower than null, C++ 48 to 58 times, JS and Java 11 to
  18 times; at 1 percent, 2 to 13 times. On Python, Lua, interp, and
  Rust a failure costs about the same as a null, since the generated
  code around it dominates (Python, Lua, interp) or a bubble is already
  a return value (Rust).
- **The user-defined result type costs an allocation per call, and
  more where its generated form is heavy:**
  - On the JVM, JS, and Python, about 1.0 to 1.6 times null on the
    success path at depth 1, and 1.6 to 2 times at depth 5 (a new `Ok`
    per level). With failures, it beats bubbling on the JVM, JS, and
    C#: at 10 percent, depth 1, Java 13-17 ns against 62-69, JS 15-16
    against 198-220, C# 33-36 against 1073-1174 (run 1).
  - On interp and Lua, 1.5 to 2.3 times null at depth 1, and 2 to 3.9
    times at depth 5.
  - On C++ and Rust it is far dearer than either alternative: 80 to 97
    ns per item in C++ (a `shared_ptr` allocation and two
    `dynamic_cast`s per check) and about 175 ns in Rust (an
    `Arc<dyn …>`, and `is`/`cast` helpers that clone the value), rising
    to 400 and 900 ns at depth 5. That is the cost of today's
    translation of user-defined sealed classes, not of results as such:
    Rust's `bubble` variant already *is* a native `Result` (with an
    optional cause), at 1.3 ns per item.
- **On interp, bubbling beats null checks at depth** (0.7 to 0.8
  times), since an explicit `if (v == null) { return null; }` per
  level costs more in a tree-walking interpreter than implicit
  propagation.

## Caveats

- The step is tiny, so the failure mechanism dominates; in real code
  (the parse loops in [claude-findings.md](../../claude-findings.md))
  each item does more, and all ratios shrink.
- The result variant measures design A *as writable today*. Design A as
  proposed would let each backend pick the representation (a native
  `Result` in Rust, a primitive with a sentinel or a reused instance
  elsewhere, a nullable where the error has no data), which wasn't
  measured here except through the Rust proxy and the Java `long`
  variant.
- Python and Lua numbers move by up to about 2 times between rounds,
  and everything in run 2 moves more (see the ranges); compare within a
  row, and use the ratio columns.
