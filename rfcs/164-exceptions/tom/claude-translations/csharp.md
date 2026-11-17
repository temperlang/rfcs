# C#

**Hand-written illustration, not generated or run.** The worked example
from [the README](README.md#the-example), as the C# backend might emit it.
Today the parser throws a bare exception with no message, the
fallback `orelse` catches every exception, and the reason comes only
from `SelectProblem`.

## Failure types

```csharp
namespace Wherewith;

/// <summary>Base of every failure Wherewith reports.</summary>
public abstract class WherewithException : Exception
{
    protected WherewithException(string? message, Exception? innerException)
        : base(message, innerException) { }
}

/// <summary>SQL text that Wherewith can't parse.</summary>
public sealed class SqlProblem : WherewithException
{
    public SqlProblem(string text, int word, string? message = null, Exception? innerException = null)
        : base(message ?? $"{text} at word {word}", innerException)
    {
        Text = text;
        Word = word;
    }

    public string Text { get; }
    public int Word { get; }
}
```

- **Library base or category:** one base class, so `SqlProblem` extends
  `WherewithException` or `ArgumentException`, not both. Shown: the
  library base, as `System.Text.Json.JsonException` extends `Exception`
  rather than `FormatException`. A library whose failures all share one
  category could root its base there. An interface (`IWherewithException`)
  can't be caught directly, only through a filter:
  `catch (Exception e) when (e is IWherewithException)`.
- **Names:** .NET's rule CA1710 expects exception types to end in
  `Exception`. The generated base follows it; the author's `SqlProblem`
  keeps its name here (alternative: generate `SqlProblemException`).
- **Message, cause, equality:** `Message` and `InnerException` from
  `Exception`; equality stays reference equality.
- **Stack trace:** .NET fills it in when the exception is thrown, not
  when it's constructed, so an unthrown `SqlProblem` costs one
  allocation.

## Declared failures

```csharp
internal sealed class Parser
{
    public Select Select()
    {
        Keyword("SELECT");
        var columns = new List<string> { Name("a column") };
        while (Peek() == ",")
        {
            pos += 1;
            columns.Add(Name("a column"));
        }
        Keyword("FROM");
        var table = Name("a table");
        if (Peek() != null)
        {
            throw Problem("expected the end");
        }
        return new Select(columns.AsReadOnly(), table);
    }

    private string Need(string message) => Peek() ?? throw Problem(message);

    private SqlProblem Problem(string text)
    {
        var word = pos + 1;
        return new SqlProblem(text, word, $"{text} at word {word}");
    }
    // Keyword, Name, and Peek as in Temper
}

public static class WherewithGlobal
{
    /// <exception cref="SqlProblem">The text isn't a select Wherewith understands.</exception>
    public static Select ParseSelect(string text) =>
        new Parser(text.Split(' ')).Select();
}
```

A Temper `orelse` becomes `catch (SqlProblem)`, not today's bare `catch`.

## Failures as values

C# has a public value-form idiom already: .NET's Try-Parse pattern
(`int.Parse` throws, `int.TryParse` returns `bool` with an `out` value).
So both forms are public API, and other Temper libraries call the `Try`
form. Inside, results are a `readonly struct` (the cheapest form
[measured](../claude-explore/README.md#a-compiler-known-result-type-likely-cost),
far cheaper than today's bubbling).

```csharp
internal sealed class Parser
{
    public Result<Select, SqlProblem> Select()
    {
        var k = Keyword("SELECT");
        if (k.IsFailed) return k.Failure;
        var first = Name("a column");
        if (first.IsFailed) return first.Failure;
        var columns = new List<string> { first.Value };
        while (Peek() == ",")
        {
            pos += 1;
            var more = Name("a column");
            if (more.IsFailed) return more.Failure;
            columns.Add(more.Value);
        }
        // … FROM and the table the same way …
        if (Peek() != null) return new SqlProblem("expected the end", pos + 1);
        return new Select(columns.AsReadOnly(), table);
    }
}

public static class WherewithGlobal
{
    public static bool TryParseSelect(
        string text,
        [NotNullWhen(true)] out Select? select,
        [NotNullWhen(false)] out SqlProblem? problem)
    {
        var r = new Parser(text.Split(' ')).Select();
        select = r.IsFailed ? null : r.Value;
        problem = r.IsFailed ? r.Failure : null;
        return !r.IsFailed;
    }

    /// <exception cref="SqlProblemException">…</exception>
    public static Select ParseSelect(string text) =>
        TryParseSelect(text, out var select, out var problem)
            ? select
            : throw new SqlProblemException(problem);
}
```

(`Result<T, E>` converts implicitly from `T` and from `E` in this sketch;
it's `internal` to the runtime and never in public signatures.)

**Which types can be failures (meeting point 6).** With any type allowed,
`SqlProblem` is a plain class, and `ParseSelect` throws a generated
`SqlProblemException : WherewithException` with a `Problem` property; a
`string` failure throws `WherewithException` with that message. .NET's
own `TryParse` methods have one `out` parameter; the second (`problem`)
is an extension of the pattern. An overload with only `out select` can
match the classic shape.

**Combined (the recommendation):** `SqlProblem` is the exception class
from [Failure types](#failure-types). `TryParseSelect` hands it out
unthrown (cheap, since .NET captures the trace on throw), and
`ParseSelect` throws it directly: `: throw problem`. One type for both
forms.

## Host caller

```csharp
if (WherewithGlobal.TryParseSelect(sql, out var select, out var problem))
{
    Use(select);
}
else
{
    Console.Error.WriteLine($"{problem.Message} (word {problem.Word})");
}

try
{
    var s = WherewithGlobal.ParseSelect(sql);
}
catch (SqlProblem e) when (e.Word > 1)   // pure values: SqlProblemException, e.Problem.Word
{
    Console.Error.WriteLine(e.Message);
}
catch (WherewithException)
{
    // anything else from Wherewith
}
```

Under declared failures only `ParseSelect` exists, unless the author
writes a `TryParseSelect` in Temper (see the
[naming rule](../claude-common-ground.md#naming-across-failure-styles)).
