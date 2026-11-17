# Design A: the problem is the failure

The same code as [current](../current/current.temper.md), with design
A's rules: an operation that can fail returns `Ok` with its value or
`Failed` with the problem string, so the twins aren't needed to learn
why (`nameProblem` stays, as a check that builds nothing). The parser
returns its first problem instead of storing it.

`Failed<…, String>` keeps Wherewith's problems as plain strings; a
library could use a class with more fields as easily.

## Quoting names

    export class Dialect(
      public name: String,
      private nameQuote: Int,
      private maxNameCodePoints: Int,
    ) {
      public static sqlite: Dialect = doPure { new Dialect("sqlite", char'"', 0) }
      public static mysql: Dialect = doPure { new Dialect("mysql", char'`', 64) }

      public quoteName(name: String): Result<String, String> {
        let problem = nameProblem(name);
        if (problem != null) { return new Failed<String, String>(problem); }
        let quote = String.fromCodePoint(nameQuote) orelse panic();
        new Ok<String, String>(
          "${quote}${name.split(quote).join("${quote}${quote}") { (s: String): String => s }}${quote}"
        )
      }

      public nameProblem(name: String): String? {
        if (name.isEmpty) { return "empty name"; }
        var codePoints = 0;
        for (var i = String.begin; name.hasIndex(i); i = name.next(i)) {
          if (name[i] == 0) { return "NUL in name"; }
          codePoints += 1;
        }
        if (maxNameCodePoints > 0 && codePoints > maxNameCodePoints) {
          return "name longer than ${maxNameCodePoints.toString()} characters";
        }
        null
      }
    }

    export class Identifier {
      public name: String;
      private constructor(name: String) { this.name = name; }

      public static named(name: String): Result<Identifier, String> {
        let problem = identifierProblem(name);
        if (problem != null) { return new Failed<Identifier, String>(problem); }
        new Ok<Identifier, String>(new Identifier(name))
      }
    }

    export let identifierProblem(name: String): String? {
      Dialect.sqlite.nameProblem(name) ?? Dialect.mysql.nameProblem(name)
    }

## A small parser

Every parsing method returns a `Result`, and every call to one has to
check it and pass a failure up. Without a propagation operator that's
a `when` per call, and a new `Failed` wherever the value types differ
(a `Result<Boolean, …>` isn't a `Result<Select, …>`). The hypothetical
version, in [hypothetical](../hypothetical.md), puts a `?` after each
call instead.

    export class Select(public columns: List<String>, public table: String) {}

    export let parseSelect(text: String): Result<Select, String> {
      new Parser(text.split(" ")).select()
    }

    class Parser(private words: List<String>) {
      private var pos: Int = 0;

      public select(): Result<Select, String> {
        let k1 = keyword("SELECT");
        if (k1 is Failed<Boolean, String>) { return new Failed<Select, String>(k1.error); }
        let columns = new ListBuilder<String>();
        let first = name("a column");
        when (first) {
          is Ok<String, String> -> columns.add(first.value);
          is Failed<String, String> -> return new Failed<Select, String>(first.error);
          else -> panic();
        }
        while (peek() == ",") {
          pos += 1;
          let next = name("a column");
          when (next) {
            is Ok<String, String> -> columns.add(next.value);
            is Failed<String, String> -> return new Failed<Select, String>(next.error);
            else -> panic();
          }
        }
        let k2 = keyword("FROM");
        if (k2 is Failed<Boolean, String>) { return new Failed<Select, String>(k2.error); }
        let table = name("a table");
        when (table) {
          is Ok<String, String> -> do {
            if (peek() != null) { return problem("expected the end"); }
            new Ok<Select, String>(new Select(columns.toList(), table.value))
          }
          is Failed<String, String> -> new Failed<Select, String>(table.error);
          else -> panic();
        }
      }

A check with no value to give still needs one: `Result<Void, …>` is a
valid type, but there's no `Void` value to put in an `Ok`, so this
gives `true`.

      private keyword(word: String): Result<Boolean, String> {
        let w = need("expected ${word}");
        when (w) {
          is Ok<String, String> -> do {
            if (w.value != word) { return problem("expected ${word}"); }
            pos += 1;
            new Ok<Boolean, String>(true)
          }
          is Failed<String, String> -> new Failed<Boolean, String>(w.error);
          else -> panic();
        }
      }

      private name(what: String): Result<String, String> {
        let w = need("expected ${what}");
        when (w) {
          is Ok<String, String> -> do {
            let s = w.value;
            if (s == "," || s == "SELECT" || s == "FROM") { return problem("expected ${what}"); }
            pos += 1;
            w
          }
          else -> w;
        }
      }

      private need(message: String): Result<String, String> {
        let w = peek();
        if (w != null) { return new Ok<String, String>(w); }
        problem(message)
      }

      private peek(): String? {
        if (pos < words.length && words[pos] != "") { words[pos] } else { null }
      }

      private problem<T>(message: String): Failed<T, String> {
        new Failed<T, String>("${message} at word ${(pos + 1).toString()}")
      }
    }

## Tests

    let longName(n: Int): String {
      let sb = new StringBuilder();
      for (var i = 0; i < n; i += 1) { sb.append("a"); }
      sb.toString()
    }

    let problemOf<T>(r: Result<T, String>): String? {
      when (r) {
        is Failed<T, String> -> r.error;
        else -> null;
      }
    }

    test("quoting") {
      let quoted = Dialect.sqlite.quoteName("a\"b");
      assert(quoted is Ok<String, String> && quoted.value == "\"a\"\"b\"");
      assert(problemOf(Dialect.sqlite.quoteName("")) == "empty name");
      assert(problemOf(Identifier.named("orders")) == null);
      assert(problemOf(Identifier.named(longName(65))) == "name longer than 64 characters");
    }

    test("parsing") {
      let s = parseSelect("SELECT a , b FROM t");
      assert(s is Ok<Select, String> && s.value.columns.length == 2 && s.value.table == "t");
      assert(problemOf(parseSelect("SELECT a FROM")) == "expected a table at word 4");
      assert(problemOf(parseSelect("SELECT , FROM t")) == "expected a column at word 2");
      assert(problemOf(parseSelect("SELECT a FROM t u")) == "expected the end at word 5");
      assert(problemOf(parseSelect("FROM t")) == "expected SELECT at word 1");
    }
