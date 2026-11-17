# Rust

**Hand-written illustration, not generated or run.** The worked example
from [the README](README.md#the-example), as the Rust backend might emit
it, with strings as `Arc<String>` and parameters as `impl ToArcString`,
as today. Today the parser returns `temper_core::Result<T>`, whose error
is `temper_core::Error(None)`: a Temper-named type, with no reason; the
reason comes only from `select_problem`.

## Failure types

```rust
/// SQL text that Wherewith can't parse.
#[derive(Clone, Debug)]
pub struct SqlProblem {
    text: Arc<String>,
    word: i32,
    message: Arc<String>,
    source: Option<Arc<dyn std::error::Error + Send + Sync>>,
}

impl SqlProblem {
    pub fn new(text: impl ToArcString, word: i32) -> SqlProblem { … }
    pub fn text(&self) -> Arc<String> { self.text.clone() }
    pub fn word(&self) -> i32 { self.word }
}

impl std::fmt::Display for SqlProblem {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)          // "expected a table at word 4"
    }
}

impl std::error::Error for SqlProblem {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.source.as_deref().map(|e| e as _)
    }
}

/// Every failure Wherewith reports.
#[derive(Clone, Debug)]
#[non_exhaustive]
pub enum Error {
    SqlProblem(SqlProblem),
    // … one variant per exported failure type
}

impl From<SqlProblem> for Error { … }
impl std::fmt::Display for Error { … }
impl std::error::Error for Error { … }
```

- **Library base:** Rust has no inheritance; the idiom is a crate-level
  `Error` enum (`wherewith::Error`, as `serde_json::Error` and
  `std::io::Error` name theirs) with a `From` conversion from each
  failure type, so host code can `?` any Wherewith failure into one
  type. Functions still return their specific type, so callers lose
  nothing by default.
- **Category:** no general standard to join (`std::io::ErrorKind` is for
  I/O); nothing generated.
- **Required:** `Display` and `Debug`, from `std::error::Error`; `Send`,
  `Sync`, and `'static`, per the Rust API Guidelines (C-GOOD-ERR), so
  `Box<dyn Error + Send + Sync>` and `anyhow` take it. `PartialEq` isn't
  derived, as `std::io::Error` doesn't implement it either.
- **A sealed failure type** (`throws X, Y`, or a sealed interface as `E`)
  becomes an enum of variants, and is `#[non_exhaustive]` only if the RFC
  says adding a variant is compatible.

## Both proposals

Rust's native idiom *is* a failure value, so both proposals generate the
same code, as today's backend already does for `throws Bubble`:

```rust
impl Parser {
    pub fn select(&mut self) -> Result<Select, SqlProblem> {
        self.keyword("SELECT")?;
        let mut columns = vec![self.name("a column")?];
        while self.peek().as_deref().map(String::as_str) == Some(",") {
            self.pos += 1;
            columns.push(self.name("a column")?);
        }
        self.keyword("FROM")?;
        let table = self.name("a table")?;
        if self.peek().is_some() {
            return Err(self.problem("expected the end"));
        }
        Ok(Select::new(columns, table))
    }

    fn need(&self, message: &str) -> Result<Arc<String>, SqlProblem> {
        self.peek().ok_or_else(|| self.problem(message))
    }

    fn problem(&self, text: &str) -> SqlProblem {
        SqlProblem::new(text, self.pos + 1)   // message "{text} at word {word}"
    }
}

/// Parses `SELECT a, b FROM t`.
///
/// # Errors
///
/// [`SqlProblem`] if the text isn't a select Wherewith understands.
pub fn parse_select(text: impl ToArcString) -> Result<Select, SqlProblem> {
    Parser::new(text).select()
}
```

The only difference is in Temper source: a marker or `throw` under
declared failures, `?` or `return Failed(…)` under values. Rust has no
throwing form to generate; a host that wants a panic writes `.unwrap()`
or `.expect("…")`.

**Which types can be failures (meeting point 6).** Under values with any
type allowed, a failure of a type the library doesn't define (a
`String`, or a type from another crate) can't get an
`impl std::error::Error`, since Rust's orphan rule forbids implementing a
foreign trait for a foreign type, so the generated function would return
`Result<T, Arc<String>>`, which `?` can't convert into
`Box<dyn Error>`. Either the backend wraps it in a generated newtype, or
exported failure types must be the library's own, which is what declared
failures and the combined form require anyway.

## Host caller

```rust
match wherewith::parse_select("SELECT a FROM") {
    Ok(select) => use_select(select),
    Err(problem) => eprintln!("{problem} (word {})", problem.word()),
}

fn load(sql: &str) -> Result<Select, Box<dyn std::error::Error + Send + Sync>> {
    Ok(wherewith::parse_select(sql)?)
}

fn load_all(sqls: &[&str]) -> Result<Vec<Select>, wherewith::Error> {
    sqls.iter().map(|s| Ok(wherewith::parse_select(*s)?)).collect()
}
```
