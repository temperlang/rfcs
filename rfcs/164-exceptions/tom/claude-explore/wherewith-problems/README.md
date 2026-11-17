# Case: Wherewith's problem strings

Wherewith, a Temper library, builds SQL for several dialects. Each
operation that can fail bubbles, and has a twin that returns why as a
string: `quoteName` and `nameProblem`, `Identifier.named` and
`identifierProblem`, `build` and `templateProblem`, `render` and
`renderProblem`. Its tour says why: "none of the exceptions carries a
message". Inside its SQL parser, `need(message)` computes a message
with a position, stores it in a field, and bubbles; the bubble drops
it, and the twin reads the field.

The excerpt keeps both shapes: quoting with a `…Problem` twin, and a
small recursive-descent parser (`SELECT a, b FROM t`) with `need`.

Files:

- [current/current.temper.md](current/current.temper.md): today's code,
  simplified (runnable, with tests).
- [values/values.temper.md](values/values.temper.md) and
  [values/result.temper.md](values/result.temper.md): design A
  (runnable, with tests).
- [hypothetical.md](hypothetical.md): A with a propagation operator,
  B, and C. **Not runnable.**

## How each design reads

The parser's top rule:

```temper
// Today (runnable): 13 lines
public select(): Select throws Bubble {
  keyword("SELECT");
  let columns = new ListBuilder<String>();
  columns.add(name("a column"));
  while (peek() == ",") { pos += 1; columns.add(name("a column")); }
  keyword("FROM");
  let table = name("a table");
  if (peek() != null) { report("expected the end"); bubble() }
  new Select(columns.toList(), table)
}

// A, runnable today: 31 lines; each call is
let first = name("a column");
when (first) {
  is Ok<String, String> -> columns.add(first.value);
  is Failed<String, String> -> return new Failed<Select, String>(first.error);
  else -> panic();
}

// A with a propagation operator (HYPOTHETICAL): today's shape, plus `?`
keyword("SELECT")?;
columns.add(name("a column")?);
...
if (peek() != null) { return problem("expected the end"); }
Ok(new Select(columns.toList(), table))

// B (HYPOTHETICAL): today's shape, `!` per call, `throw problem(...)`
keyword("SELECT")!;
columns.add(name("a column")!);

// C (HYPOTHETICAL): today's shape, `try` per call, and the problem
// still stored in a field, since a kind can't carry it
try keyword("SELECT");
```

## What host code sees

From `Dialect.sqlite.quoteName("")`:

| | Python | Java | Rust |
|---|---|---|---|
| Today | `RuntimeError()`; why, from `name_problem` | `RuntimeException`, null message; `nameProblem` | `Err(Error(None))`; `name_problem` |
| A, runnable | a `Failed` with `error == "empty name"` | `Result<String, String>` | a generated `Result_` |
| B | a generated `Problem` exception, message "empty name" | the same | `Result<String, Problem>` |
| C | a generated `InvalidName`, no message; `name_problem` for why | the same | `Err(Kind::InvalidName)` |

## Notes

- **The twins exist only because the failure can't carry text.** Under
  A and B the reason travels with the failure, so `selectProblem` and
  the parser's `problem` field and `report` go; `nameProblem` can stay
  as a cheap check that builds nothing. Under C they all stay.
- **Recursive descent is where propagation syntax matters most.** Every
  rule calls others that can fail. Today's `throws Bubble` propagates
  implicitly (no marker at the call); B and C would add one marker per
  call (`!`, `try`); A without an operator more than doubles the rule
  (13 to 31 lines); A with `?` matches B.
- **Opaque messages would bring the twins back.** If a failure's message
  can't be read by Temper code (Mike's suggestion for message and
  cause), Wherewith's own tests and tour, which print the reason, still
  need a readable copy; a field the library declares avoids that.
- **No `Ok` for "nothing":** `Result<Void, …>` is a valid type, but
  there's no `Void` value to put in an `Ok`, so `keyword` returns
  `Result<Boolean, …>` with `true`. A built-in result type would need a
  unit success.
- **A generic helper works:** `problem<T>(message): Failed<T, String>`
  is inferred from the `return` it's in, which shortens each failure
  site.

## Precedence

- The parser compares `peek() == ","` and `peek() != null`; if `peek`
  were to fail rather than give null, `peek() orelse "" == ","` would
  mean `peek() orelse ("" == ",")`: `orelse` (precedence 4) is below
  `==` (12), and tempest accepts it (see the
  [overview](../README.md#operator-precedence)).
- A postfix propagation operator in `need("…")? != word` must bind
  tighter than `!=`; at today's postfix precedence (23) it does.

Run: `temper test -w . -b interp -b py -b js` (or any other backends)
in a copy of this folder. `current` and `values` are separate libraries,
since the C++ backend puts all of a library's exports in one namespace
and both define the same names.
