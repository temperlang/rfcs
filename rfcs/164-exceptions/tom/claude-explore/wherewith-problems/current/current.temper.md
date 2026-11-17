# Today: a bubble, and a `…Problem` twin that says why

Simplified from Wherewith (`src/core.temper.md` and
`src/common-expressions.temper.md`). Each operation that can fail
bubbles, and has a twin that returns the reason as a string, because
"none of the exceptions carries a message". Quoting checks its twin
first; the parser records the first message in a field before it
bubbles, and the public twin reads that field.

## Quoting names

    export class Dialect(
      public name: String,
      private nameQuote: Int,
      private maxNameCodePoints: Int,
    ) {
      public static sqlite: Dialect = doPure { new Dialect("sqlite", char'"', 0) }
      public static mysql: Dialect = doPure { new Dialect("mysql", char'`', 64) }

`quoteName` quotes a name, or bubbles if `nameProblem` finds one.

      public quoteName(name: String): String throws Bubble {
        if (nameProblem(name) != null) { bubble() }
        let quote = String.fromCodePoint(nameQuote) orelse panic();
        "${quote}${name.split(quote).join("${quote}${quote}") { (s: String): String => s }}${quote}"
      }

`nameProblem` says why a name can't be quoted, or is null if it can.

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

A name every dialect takes, checked once.

    export class Identifier {
      public name: String;
      private constructor(name: String) { this.name = name; }

      public static named(name: String): Identifier throws Bubble {
        if (identifierProblem(name) != null) { bubble() }
        new Identifier(name)
      }
    }

    export let identifierProblem(name: String): String? {
      Dialect.sqlite.nameProblem(name) ?? Dialect.mysql.nameProblem(name)
    }

## A small parser

`SELECT a, b FROM t`, and nothing more, by recursive descent over
words, as Wherewith's parser does over its tokens. The first problem
found wins; it's computed with its position, stored, and then the
bubble drops it, so `selectProblem` parses again to read it.

    export class Select(public columns: List<String>, public table: String) {}

    export let parseSelect(text: String): Select throws Bubble {
      new Parser(text.split(" ")).select()
    }

    export let selectProblem(text: String): String? {
      let p = new Parser(text.split(" "));
      do { p.select(); null } orelse p.problem
    }

    class Parser(private words: List<String>) {
      public var problem: String? = null;
      private var pos: Int = 0;

      public select(): Select throws Bubble {
        keyword("SELECT");
        let columns = new ListBuilder<String>();
        columns.add(name("a column"));
        while (peek() == ",") {
          pos += 1;
          columns.add(name("a column"));
        }
        keyword("FROM");
        let table = name("a table");
        if (peek() != null) { report("expected the end"); bubble() }
        new Select(columns.toList(), table)
      }

      private keyword(word: String): Void throws Bubble {
        let w = need("expected ${word}");
        if (w != word) { report("expected ${word}"); bubble() }
        pos += 1;
      }

      private name(what: String): String throws Bubble {
        let w = need("expected ${what}");
        if (w == "," || w == "SELECT" || w == "FROM") { report("expected ${what}"); bubble() }
        pos += 1;
        w
      }

`need` gives the next word, or bubbles with a message at the end.

      private need(message: String): String throws Bubble {
        let w = peek();
        if (w != null) { return w; }
        report(message);
        bubble()
      }

      private peek(): String? {
        if (pos < words.length && words[pos] != "") { words[pos] } else { null }
      }

      private report(message: String): Void {
        if (problem == null) { problem = "${message} at word ${(pos + 1).toString()}"; }
      }
    }

## Tests

    let longName(n: Int): String {
      let sb = new StringBuilder();
      for (var i = 0; i < n; i += 1) { sb.append("a"); }
      sb.toString()
    }

    test("quoting") {
      assert((Dialect.sqlite.quoteName("a\"b") orelse "") == "\"a\"\"b\"");
      assert((Dialect.sqlite.quoteName("") orelse "failed") == "failed");
      assert(Dialect.sqlite.nameProblem("") == "empty name");
      assert((Identifier.named("orders") orelse panic()).name == "orders");
      assert(identifierProblem(longName(65)) == "name longer than 64 characters");
    }

    test("parsing") {
      let s = parseSelect("SELECT a , b FROM t") orelse panic();
      assert(s.columns.length == 2 && s.table == "t");
      assert((do { parseSelect("SELECT a FROM"); "parsed" } orelse "failed") == "failed");
      assert(selectProblem("SELECT a FROM") == "expected a table at word 4");
      assert(selectProblem("SELECT , FROM t") == "expected a column at word 2");
      assert(selectProblem("SELECT a FROM t u") == "expected the end at word 5");
      assert(selectProblem("SELECT a , b FROM t") == null);
    }
