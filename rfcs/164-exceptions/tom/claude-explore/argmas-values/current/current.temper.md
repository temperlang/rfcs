# Today: value types bubble, argument errors are values

Simplified from Argmas (`src/values.temper.md`, `src/command.temper.md`,
and `src/parse.temper.md`), keeping the shapes that matter here: a
value type's `parse` bubbles; the parser asks whether text parses with
`do { ...; true } orelse false`, and reads values later with
`orelse panic()`; and mistakes in the arguments are `ArgError` values,
never bubbles.

## Value types

    export interface ValueType<T> {
      public get expected(): String;
      public parse(text: String): T throws Bubble;
    }

`ints` checks the text itself (sign, ASCII digits, range), so every
backend agrees on the edges, and only then calls the builtin `toInt32`.

    export let ints: ValueType<Int> = new IntType();

    class IntType extends ValueType<Int> {
      public get expected(): String { "an integer" }
      public parse(text: String): Int throws Bubble {
        integerText(text, "2147483647", "2147483648").toInt32()
      }
    }

    let integerText(text: String, most: String, mostNegative: String): String throws Bubble {
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
          bubble();
        }
      }
      if (!seenDigit) { bubble() }
      let magnitude = digits.toString();
      if (magnitude.isEmpty) { return "0"; }
      if (!atMost(magnitude, if (negative) { mostNegative } else { most })) { bubble() }
      if (negative) { "-${magnitude}" } else { magnitude }
    }

    let atMost(digits: String, limit: String): Boolean {
      let length = digits.countBetween(String.begin, digits.end);
      let limitLength = limit.countBetween(String.begin, limit.end);
      if (length != limitLength) { return length < limitLength; }
      digits <= limit
    }

`choices` takes one of a fixed list.

    export let choices(allowed: List<String>): ValueType<String> { new ChoiceType(allowed) }

    class ChoiceType(private allowed: List<String>) extends ValueType<String> {
      public get expected(): String { "one of ${allowed.join(", ") { (s: String): String => s }}" }
      public parse(text: String): String throws Bubble {
        for (let s of allowed) {
          if (s == text) { return s; }
        }
        bubble()
      }
    }

## Options and the parser

An option erases its value's type behind a `Checker`, as Argmas's
`Param` does, so the parser can hold options of different types.

    export interface Checker {
      public accepts(text: String): Boolean;
      public get expected(): String;
    }

    class TypeChecker<T>(private type: ValueType<T>) extends Checker {
      public accepts(text: String): Boolean {
        do { type.parse(text); true } orelse false
      }
      public get expected(): String { type.expected }
    }

    export class Opt(public name: String, public checker: Checker) {}

    export let option<T>(name: String, type: ValueType<T>): Opt {
      new Opt(name, new TypeChecker<T>(type))
    }

The outcome of parsing, as Argmas's `ParseResult`: the values, or the
first mistake, with its kind and a one-line message.

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

`--name value` and `--name=value`, nothing else. The first mistake
wins.

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

Values were checked while parsing, so reading one parses it again and
asserts it can't fail, as Argmas's handles do.

    export let read<T>(args: Args, name: String, type: ValueType<T>): T? {
      let text = args.text(name);
      if (text == null) { return null; }
      type.parse(text) orelse panic()
    }

## Tests

    let messageOf(r: ParseResult): String {
      when (r) {
        is ArgError -> r.message;
        else -> "no error";
      }
    }

    let level = option("level", ints);
    let mode = option("mode", choices(["fast", "slow"]));

    test("ints") {
      assert((ints.parse("42") orelse -1) == 42);
      assert((ints.parse("-007") orelse -1) == -7);
      assert((ints.parse("2147483647") orelse -1) == 2147483647);
      assert((ints.parse("-2147483648") orelse 0) == -2147483647 - 1);
      assert((ints.parse("2147483648") orelse -1) == -1);
      assert((ints.parse("1_000") orelse -1) == -1);
      assert((ints.parse("") orelse -1) == -1);
      assert((ints.parse("-") orelse -1) == -1);
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
