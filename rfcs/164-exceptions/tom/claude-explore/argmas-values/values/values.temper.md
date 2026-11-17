# Design A: absence as null, mistakes as values

The same code as [current](../current/current.temper.md), with design
A's rules: a value type's `parse` gives null for text that means no
value, since Argmas writes its own message from `expected` and needs no
reason from the type. `ArgError` was already a value and stays one.
Nothing here bubbles or uses `orelse`, except around the builtin
`toInt32`, which bubbles today.

## Value types

    export interface ValueType<T> {
      public get expected(): String;

The value the text means, or null when it means none.

      public parse(text: String): T?;
    }

    export let ints: ValueType<Int> = new IntType();

    class IntType extends ValueType<Int> {
      public get expected(): String { "an integer" }

Propagating null takes a statement today. With a propagation operator
(hypothetical, see [hypothetical](../hypothetical.md)) this would be
`integerText(text, ...)?.toInt32()` or `integerText(text, ...)?` on its
own line. The builtin bubbles today, so it needs `orelse null`; under
design A, builtins that parse would return null themselves.

      public parse(text: String): Int? {
        let digits = integerText(text, "2147483647", "2147483648");
        if (digits == null) { return null; }
        digits.toInt32() orelse null
      }
    }

    let integerText(text: String, most: String, mostNegative: String): String? {
      let digits = new StringBuilder();
      var negative = false;
      var seenDigit = false;
      for (var i = String.begin; text.hasIndex(i); i = text.next(i)) {
        let c = text[i];
        if (i == String.begin && (c == char'-' || c == char'+')) {
          negative = c == char'-';
        } else if (c >= char'0' && c <= char'9') {
          seenDigit = true;
          if (c != char'0' || digits.toString() != "") {
            digits.appendCodePoint(c) orelse panic();
          }
        } else {
          return null;
        }
      }
      if (!seenDigit) { return null; }
      let magnitude = digits.toString();
      if (magnitude.isEmpty) { return "0"; }
      if (!atMost(magnitude, if (negative) { mostNegative } else { most })) { return null; }
      if (negative) { "-${magnitude}" } else { magnitude }
    }

    let atMost(digits: String, limit: String): Boolean {
      let length = digits.countBetween(String.begin, digits.end);
      let limitLength = limit.countBetween(String.begin, limit.end);
      if (length != limitLength) { return length < limitLength; }
      digits <= limit
    }

    export let choices(allowed: List<String>): ValueType<String> { new ChoiceType(allowed) }

    class ChoiceType(private allowed: List<String>) extends ValueType<String> {
      public get expected(): String { "one of ${allowed.join(", ") { (s: String): String => s }}" }
      public parse(text: String): String? {
        for (let s of allowed) {
          if (s == text) { return s; }
        }
        null
      }
    }

## Options and the parser

`accepts` is now a null check, and reading asserts with `?? panic()`.

    export interface Checker {
      public accepts(text: String): Boolean;
      public get expected(): String;
    }

    class TypeChecker<T>(private type: ValueType<T>) extends Checker {
      public accepts(text: String): Boolean { type.parse(text) != null }
      public get expected(): String { type.expected }
    }

    export class Opt(public name: String, public checker: Checker) {}

    export let option<T>(name: String, type: ValueType<T>): Opt {
      new Opt(name, new TypeChecker<T>(type))
    }

The outcome, unchanged: Argmas's `ParseResult` is already design A's
"failure with a reason", as a library-specific sealed type with three
outcomes (Argmas also has `Output`, for help and version), so a generic
`Ok`/`Failed` wouldn't fit it better.

    export sealed interface ParseResult {}

    export class Args(public names: List<String>, public texts: List<String>) extends ParseResult {
      public text(name: String): String? {
        var found: String? = null;
        for (var i = 0; i < names.length; i += 1) {
          if (names[i] == name) { found = texts[i]; }
        }
        found
      }
    }

    export class ArgError(public kind: String, public message: String) extends ParseResult {
      public toString(): String { message }
    }

    export let parseArgs(options: List<Opt>, argv: List<String>): ParseResult {
      let names = new ListBuilder<String>();
      let texts = new ListBuilder<String>();
      var i = 0;
      while (i < argv.length) {
        let arg = argv[i];
        i += 1;
        if (!arg.hasAtLeast(String.begin, arg.end, 3) || arg[String.begin] != char'-') {
          return new ArgError("unexpectedArgument", "unexpected argument '${arg}'");
        }
        let body = arg.slice(arg.next(arg.next(String.begin)), arg.end);
        let eq = body.split("=");
        let name = eq[0];
        let opt = find(options, name);
        if (opt == null) {
          return new ArgError("unknownOption", "unknown option --${name}");
        }
        let text: String? = if (eq.length > 1) {
          eq.slice(1, eq.length).join("=") { (s: String): String => s }
        } else if (i < argv.length) {
          i += 1;
          argv[i - 1]
        } else {
          null
        };
        if (text == null) {
          return new ArgError("missingValue", "missing value for --${name}");
        }
        if (!opt.checker.accepts(text)) {
          return new ArgError("invalidValue",
            "invalid value '${text}' for --${name}: expected ${opt.checker.expected}");
        }
        names.add(name);
        texts.add(text);
      }
      new Args(names.toList(), texts.toList())
    }

    let find(options: List<Opt>, name: String): Opt? {
      for (let o of options) {
        if (o.name == name) { return o; }
      }
      null
    }

    export let read<T>(args: Args, name: String, type: ValueType<T>): T? {
      let text = args.text(name);
      if (text == null) { return null; }
      type.parse(text) ?? panic()
    }

## Tests

The same cases as today's, with `??` where today has `orelse`.

    let messageOf(r: ParseResult): String {
      when (r) {
        is ArgError -> r.message;
        else -> "no error";
      }
    }

    let level = option("level", ints);
    let mode = option("mode", choices(["fast", "slow"]));

    test("ints") {
      assert((ints.parse("42") ?? -1) == 42);
      assert((ints.parse("-007") ?? -1) == -7);
      assert((ints.parse("2147483647") ?? -1) == 2147483647);
      assert((ints.parse("-2147483648") ?? 0) == -2147483647 - 1);
      assert(ints.parse("2147483648") == null);
      assert(ints.parse("1_000") == null);
      assert(ints.parse("") == null);
      assert(ints.parse("-") == null);
    }

    test("parse and read") {
      let r = parseArgs([level, mode], ["--level", "3", "--mode=slow"]);
      if (r is Args) {
        assert(read(r, "level", ints) == 3);
        assert(read(r, "mode", choices(["fast", "slow"])) == "slow");
      } else {
        assert(false);
      }
    }

    test("argument errors") {
      let bad = parseArgs([level, mode], ["--level", "abc"]);
      assert(messageOf(bad) == "invalid value 'abc' for --level: expected an integer");
      let unknown = parseArgs([level], ["--lvl", "3"]);
      assert(messageOf(unknown) == "unknown option --lvl");
      let missing = parseArgs([level], ["--level"]);
      assert(messageOf(missing) == "missing value for --level");
      let choice = parseArgs([mode], ["--mode", "medium"]);
      assert(messageOf(choice) == "invalid value 'medium' for --mode: expected one of fast, slow");
    }

A program's own value type, as host code or Temper code would write it:
a port number, null outside 1 to 65535.

    class PortType extends ValueType<Int> {
      public get expected(): String { "a port from 1 to 65535" }
      public parse(text: String): Int? {
        let n = ints.parse(text);
        if (n == null || n < 1 || n > 65535) { return null; }
        n
      }
    }

    test("a program's own type") {
      let port = option("port", new PortType());
      assert(parseArgs([port], ["--port", "8080"]) is Args);
      assert(messageOf(parseArgs([port], ["--port", "0"])) ==
        "invalid value '0' for --port: expected a port from 1 to 65535");
    }
