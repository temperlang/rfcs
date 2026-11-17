# Today: parsing and decoding bubble

Simplified from std's JSON module (`json/json.temper.md` in Temper's
`std`): `parseJson` builds a syntax tree and bubbles on bad syntax
(the parser finds a message, keeps it in the producer's `jsonError`,
and `parseJson` drops it: "TODO: if there is a syntax error, produce
it"); a `JsonAdapter<T>` decodes a tree into a value and bubbles when
the tree has the wrong shape, through `as` casts and the builtin
`toInt32`. Here JSON is cut down to integers, strings without escapes,
and arrays.

## Trees

    export sealed interface JsonSyntaxTree {}
    export class JsonNumericToken(public content: String) extends JsonSyntaxTree {
      public asInt32(): Int throws Bubble { content.toInt32() }
    }
    export class JsonString(public content: String) extends JsonSyntaxTree {}
    export class JsonArray(public elements: List<JsonSyntaxTree>) extends JsonSyntaxTree {}

## Parsing

    export let parseJson(sourceText: String): JsonSyntaxTree throws Bubble {
      let p = new JsonParser(sourceText);
      let tree = p.value();
      p.space();
      if (p.more) { p.fail("extra text after the value"); }
      tree
    }

    class JsonParser(private text: String) {
      private var i: StringIndex = String.begin;
      private var offset: Int = 0;
      public var jsonError: String? = null;

      public get more(): Boolean { text.hasIndex(i) }

      public value(): JsonSyntaxTree throws Bubble {
        space();
        if (!more) { fail("expected a value"); }
        let c = text[i];
        if (c == char'[') {
          step();
          let elements = new ListBuilder<JsonSyntaxTree>();
          space();
          if (more && text[i] == char']') { step(); return new JsonArray(elements.toList()); }
          while (true) {
            elements.add(value());
            space();
            if (!more) { fail("expected , or ]"); }
            let d = text[i];
            step();
            if (d == char']') { break; }
            if (d != char',') { fail("expected , or ]"); }
          }
          new JsonArray(elements.toList())
        } else if (c == char'"') {
          step();
          let start = i;
          while (more && text[i] != char'"') { step(); }
          if (!more) { fail("unclosed string"); }
          let s = text.slice(start, i);
          step();
          new JsonString(s)
        } else if (c == char'-' || (c >= char'0' && c <= char'9')) {
          let start = i;
          step();
          while (more && text[i] >= char'0' && text[i] <= char'9') { step(); }
          new JsonNumericToken(text.slice(start, i))
        } else {
          fail("unexpected character");
          bubble()
        }
      }

The message and offset are kept, then the bubble drops them.

      public fail(message: String): Void throws Bubble {
        jsonError = "${message} at ${offset.toString()}";
        bubble()
      }

      public space(): Void {
        while (more && text[i] == char' ') { step(); }
      }

      private step(): Void {
        i = text.next(i);
        offset += 1;
      }
    }

## Adapters

    export interface JsonAdapter<T> {
      public decodeFromJson(t: JsonSyntaxTree): T throws Bubble;
    }

    export class Int32JsonAdapter extends JsonAdapter<Int> {
      public decodeFromJson(t: JsonSyntaxTree): Int throws Bubble {
        (t as JsonNumericToken).asInt32()
      }
    }

    export class StringJsonAdapter extends JsonAdapter<String> {
      public decodeFromJson(t: JsonSyntaxTree): String throws Bubble {
        (t as JsonString).content
      }
    }

    export class ListJsonAdapter<T>(private adapterForT: JsonAdapter<T>) extends JsonAdapter<List<T>> {
      public decodeFromJson(t: JsonSyntaxTree): List<T> throws Bubble {
        let b = new ListBuilder<T>();
        for (let el of (t as JsonArray).elements) {
          b.add(adapterForT.decodeFromJson(el));
        }
        b.toList()
      }
    }

Text to value, the way a caller combines the two.

    export let decodeJson<T>(text: String, adapter: JsonAdapter<T>): T throws Bubble {
      adapter.decodeFromJson(parseJson(text))
    }

## Tests

    let ints = new ListJsonAdapter<List<Int>>(new ListJsonAdapter<Int>(new Int32JsonAdapter()));

    test("decodes") {
      let xs = decodeJson("[[1, 2], [], [-3]]", ints) orelse panic();
      assert(xs.length == 3 && xs[0][1] == 2 && xs[2][0] == -3);
      let names = decodeJson("[\"a\", \"b\"]", new ListJsonAdapter<String>(new StringJsonAdapter())) orelse panic();
      assert(names[1] == "b");
    }

    test("fails without saying why or where") {
      // Bad syntax, a wrong type deep inside, and an Int32 overflow all
      // look the same to the caller.
      assert((do { decodeJson("[[1, 2], [3", ints); "ok" } orelse "failed") == "failed");
      assert((do { decodeJson("[[1, 2], [\"3\"]]", ints); "ok" } orelse "failed") == "failed");
      assert((do { decodeJson("[[1, 2], [99999999999]]", ints); "ok" } orelse "failed") == "failed");
    }

    test("the parser had a message") {
      let p = new JsonParser("[1, 2");
      let parsed = do { p.value(); true } orelse false;
      assert(!parsed);
      assert(p.jsonError == "expected , or ] at 5");
    }
