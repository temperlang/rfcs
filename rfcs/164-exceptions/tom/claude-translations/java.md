# Java

**Hand-written illustration, not generated or run.** The worked example
from [the README](README.md#the-example), as the Java backend might emit
it, in Java 8 syntax (no records or sealed classes), since the backend
still supports Java 8. Today the parser throws a bare
`RuntimeException` with a null message, and the reason comes only from
`selectProblem`.

## Failure types

```java
package wherewith;

/** Base of every failure Wherewith reports. */
public abstract class WherewithException extends RuntimeException {
    protected WherewithException(String message, Throwable cause) {
        super(message, cause);
    }
}

/** SQL text that Wherewith can't parse. */
public final class SqlProblem extends WherewithException {
    public final String text;
    public final int word;

    public SqlProblem(String text, int word, String message, Throwable cause) {
        super(message != null ? message : text + " at word " + word, cause);
        this.text = text;
        this.word = word;
    }

    public SqlProblem(String text, int word) {
        this(text, word, null, null);
    }
}
```

- **Library base or category:** Java has one superclass, so `SqlProblem`
  can extend `WherewithException` or `IllegalArgumentException` (its
  category), not both, and a marker interface can't stand in, since
  `catch` takes only classes. Shown: the library base wins, as the JDK's
  own `java.time.DateTimeException extends RuntimeException`. If every
  failure a library declares shares one category, its base could extend
  that category instead (`WherewithException extends
  IllegalArgumentException`).
- **Message, cause, equality:** `getMessage()` and `getCause()` from
  `Throwable`; equality stays identity.
- **No generic failure types:** Java rejects a generic subclass of
  `Throwable`, so a failure type with type parameters can't be generated
  this way.

## Checked or unchecked (meeting point 3)

Shown above: **unchecked** (`extends RuntimeException`), which works with
lambdas and streams and matches Kotlin, where every exception is
unchecked. The generated signatures still list it, as Java allows for
unchecked exceptions, so it shows in IDEs and Javadoc:

```java
public static Select parseSelect(String text) throws SqlProblem { … }
```

**Checked**, by a library-wide setting, changes only the base:

```java
public abstract class WherewithException extends Exception { … }
```

Then every generated method that propagates must declare
`throws SqlProblem` (the compiler checks the generated code as Temper's
type checker did), and host code must catch or declare it, as below. One
setting per library, not per function, since all of a library's failures
share the base.

## Declared failures

```java
final class Parser {
    private final List<String> words;
    private int pos;

    Select select() throws SqlProblem {
        keyword("SELECT");
        List<String> columns = new ArrayList<>();
        columns.add(name("a column"));
        while (",".equals(peek())) {
            pos += 1;
            columns.add(name("a column"));
        }
        keyword("FROM");
        String table = name("a table");
        if (peek() != null) {
            throw problem("expected the end");
        }
        return new Select(Collections.unmodifiableList(columns), table);
    }

    private String need(String message) throws SqlProblem {
        String w = peek();
        if (w == null) {
            throw problem(message);
        }
        return w;
    }

    private SqlProblem problem(String text) {
        int word = pos + 1;
        return new SqlProblem(text, word, text + " at word " + word, null);
    }
    // keyword, name, and peek as in Temper
}

public final class WherewithGlobal {
    /** @throws SqlProblem if {@code text} isn't a select Wherewith understands */
    public static Select parseSelect(String text) throws SqlProblem {
        return new Parser(Arrays.asList(text.split(" ", -1))).select();
    }
}
```

A Temper `orelse` becomes `catch (SqlProblem e)`, never
`catch (RuntimeException e)` as today.

## Failures as values

The value form, for other Temper libraries, lives in a package hosts
aren't pointed to (`wherewith.internal`, unexported where the library is
a Java module). Results use a small final class from Temper's runtime,
which hosts never see in the public API.

```java
package wherewith.internal;

final class Parser {
    Result<Select, SqlProblem> select() {
        Result<Void, SqlProblem> k = keyword("SELECT");
        if (k.isFailed()) return k.retype();
        Result<String, SqlProblem> first = name("a column");
        if (first.isFailed()) return first.retype();
        List<String> columns = new ArrayList<>();
        columns.add(first.value());
        while (",".equals(peek())) {
            pos += 1;
            Result<String, SqlProblem> more = name("a column");
            if (more.isFailed()) return more.retype();
            columns.add(more.value());
        }
        // … FROM and the table the same way …
        if (peek() != null) return Result.failed(new SqlProblem(…));
        return Result.ok(new Select(Collections.unmodifiableList(columns), table));
    }
}
```

```java
package wherewith;

public final class WherewithGlobal {
    /** @throws SqlProblemException if {@code text} isn't a select Wherewith understands */
    public static Select parseSelect(String text) throws SqlProblemException {
        Result<Select, SqlProblem> r = wherewith.internal.Parsing.parseSelect(text);
        if (r.isFailed()) throw new SqlProblemException(r.failure());
        return r.value();
    }
}
```

**Which types can be failures (meeting point 6).** With any type allowed,
`SqlProblem` is a plain final class (fields, and `toString()` from
Temper), and the throwing form wraps it in a generated exception:

```java
public final class SqlProblemException extends WherewithException {
    public final SqlProblem problem;
    public SqlProblemException(SqlProblem problem) {
        super(problem.toString(), null);
        this.problem = problem;
    }
}
```

A failure of a type that can't be a class here (a `String`, a generic
class) is thrown as `WherewithException` with the value's text.

**Combined (the recommendation):** `SqlProblem` is declared as a failure,
so it's the exception class from [Failure types](#failure-types), and the
value form carries it unthrown. The JVM captures a stack trace when an
exception is constructed, which is most of today's bubbling cost, so the
value form constructs it without one (through a generated
non-public constructor that passes `writableStackTrace = false` up to
`Throwable`), and the throwing form throws a fresh copy
whose trace starts at the call from host code:

```java
if (r.isFailed()) {
    SqlProblem p = r.failure();
    throw new SqlProblem(p.text, p.word, p.getMessage(), p.getCause());
}
```

Host code then catches `SqlProblem`, as under declared failures.
Alternative: construct it with a trace and accept the cost per failure.

## Host caller

```java
try {
    Select select = WherewithGlobal.parseSelect("SELECT a FROM");
} catch (SqlProblem e) {                 // pure values: SqlProblemException, e.problem.word
    System.err.println(e.getMessage() + " (word " + e.word + ")");
} catch (WherewithException e) {
    // anything else from Wherewith
}
```

With checked failures, a method that doesn't catch must declare
`throws SqlProblem`, and a lambda can't call it directly:

```java
// Compiles with unchecked failures; with checked ones it needs a wrapper.
List<Select> selects = sqls.stream().map(WherewithGlobal::parseSelect).collect(toList());
```

`WherewithGlobal` is today's name for the class holding a library's
top-level functions; it names the library, not Temper.
