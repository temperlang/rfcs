# Wherewith problems: hypothetical versions

**None of the code on this page compiles today.** It shows how
[current](current/current.temper.md) and [values](values/values.temper.md)
would read under each design, with syntax invented for the comparison.

## A with a propagation operator (hypothetical)

Postfix `?` returns a `Failed` from the enclosing function, whatever
its value type, and otherwise unwraps the value. `Ok(…)` and
`Failed(…)` take their type arguments from the return type.

```temper
// HYPOTHETICAL: postfix `?`, inferred type arguments, Result<Void, E>
// with a unit Ok().
public quoteName(name: String): Result<String, String> {
  let problem = nameProblem(name);
  if (problem != null) { return Failed(problem); }
  Ok("${quote}${...}${quote}")
}

public select(): Result<Select, String> {
  keyword("SELECT")?;
  let columns = new ListBuilder<String>();
  columns.add(name("a column")?);
  while (peek() == ",") {
    pos += 1;
    columns.add(name("a column")?);
  }
  keyword("FROM")?;
  let table = name("a table")?;
  if (peek() != null) { return problem("expected the end"); }
  Ok(new Select(columns.toList(), table))
}

private keyword(word: String): Result<Void, String> {
  if (need("expected ${word}")? != word) { return problem("expected ${word}"); }
  pos += 1;
  Ok()
}

private name(what: String): Result<String, String> {
  let w = need("expected ${what}")?;
  if (w == "," || w == "SELECT" || w == "FROM") { return problem("expected ${what}"); }
  pos += 1;
  Ok(w)
}
```

This is today's bubbling parser line for line, with `?` where a call
can fail, and the problem travelling with the failure: no `problem`
field, no `report`, and no `selectProblem` twin. Without the operator
(the runnable version), `select` grows from 13 lines to 31.

## B: one declared failure type per function (hypothetical)

```temper
// HYPOTHETICAL: `throwable`, `throws E`, `throw`, `!`, `catch`.
export throwable class Problem(public text: String) {}   // or a String message, opaque to Temper

public quoteName(name: String): String throws Problem {
  let problem = nameProblem(name);
  if (problem != null) { throw new Problem(problem); }
  "${quote}${...}${quote}"
}

public select(): Select throws Problem {
  keyword("SELECT")!;
  let columns = new ListBuilder<String>();
  columns.add(name("a column")!);
  while (peek() == ",") { pos += 1; columns.add(name("a column")!); }
  keyword("FROM")!;
  let table = name("a table")!;
  if (peek() != null) { throw problem("expected the end"); }
  new Select(columns.toList(), table)
}

// A Temper caller that wants the text:
let text = parseSelect(sql) catch (e) { e.text };
```

If the message is opaque to Temper code (Mike's suggestion for message
and cause), Temper callers can't show it, and Wherewith's own tests and
tour, which print the reason, would still need `selectProblem`. A field
the library declares (`text` here) avoids that.

## C: declared error kinds, no details (hypothetical)

```temper
// HYPOTHETICAL: `error case`, `throws X`, `try`.
error case InvalidName;
error case InvalidTemplate;

public quoteName(name: String): String throws InvalidName {
  if (nameProblem(name) != null) { throw InvalidName; }
  ...
}

public select(): Select throws InvalidTemplate {
  try keyword("SELECT");
  ...
}
```

Kinds don't carry the text, so the twins stay: `nameProblem`,
`selectProblem`, and the parser's `problem` field, exactly as today.
What C adds is a host type to catch (`InvalidName` rather than
`RuntimeError`).

## What host code would see

From `Dialect.sqlite.quoteName("")` and `parseSelect("SELECT a FROM")`:

| Design | Python | Java | Rust |
|---|---|---|---|
| Today | `RuntimeError()` with no message; the reason only from `name_problem` / `select_problem` | `RuntimeException`, null message; `nameProblem` | `Err(Error(None))`; `name_problem` |
| A, as runnable today | returns `Failed` with `error == "empty name"` | returns `Result<String, String>`; `instanceof Failed` | a generated `Result_<Arc<String>, Arc<String>>` |
| A, with backend-aware translation (hypothetical) | the value form returns the problem; a generated throwing form raises with the problem as message | the same, two forms | `Result<String, String>` |
| B | raises the generated `Problem`, message "empty name" | throws `Problem` with a message | `Result<String, Problem>` |
| C | raises `InvalidName`, no message; `name_problem` for the reason | throws `InvalidName` | `Err(Kind::InvalidName)` |
