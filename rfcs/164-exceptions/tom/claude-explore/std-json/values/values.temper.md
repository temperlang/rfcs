# Design A: failures say what and where

The same code as [current](../current/current.temper.md), with design
A's rules. Parsing fails with a `JsonSyntaxError` (the message the
parser already had, and its offset); decoding fails with a
`JsonShapeError` that says where in the tree and what was expected.
`decodeJson`, which can fail either way, fails with their common sealed
interface, `JsonProblem`: one failure type per function, as in Mike's
notes, with the variants a caller can match.

## Problems

    export sealed interface JsonProblem {
      public get message(): String;
    }

    export class JsonSyntaxError(public reason: String, public offset: Int) extends JsonProblem {
      public get message(): String { "${reason} at ${offset.toString()}" }
    }

`path` is where in the tree, as `[1][0]`; empty for the top.

    export class JsonShapeError(public path: String, public expected: String) extends JsonProblem {
      public get message(): String {
        if (path == "") { "expected ${expected}" } else { "at ${path}: expected ${expected}" }
      }
    }

## Trees

`asInt32` becomes nullable: a numeric token that isn't an Int32 is
absence, and the adapter says why. The builtin `toInt32` bubbles today,
so it needs `orelse null`.

    export sealed interface JsonSyntaxTree {}
    export class JsonNumericToken(public content: String) extends JsonSyntaxTree {
      public asInt32(): Int? { content.toInt32() orelse null }
    }
    export class JsonString(public content: String) extends JsonSyntaxTree {}
    export class JsonArray(public elements: List<JsonSyntaxTree>) extends JsonSyntaxTree {}

## Parsing

    export let parseJson(sourceText: String): Result<JsonSyntaxTree, JsonSyntaxError> {
      let p = new JsonParser(sourceText);
      let tree = p.value();
      if (tree is Failed<JsonSyntaxTree, JsonSyntaxError>) { return tree; }
      p.space();
      if (p.more) { return p.fail("extra text after the value"); }
      tree
    }

    class JsonParser(private text: String) {
      private var i: StringIndex = String.begin;
      private var offset: Int = 0;

      public get more(): Boolean { text.hasIndex(i) }

The recursive call for each element is the one place a failure passes
up through the parser: one `if` here, or a `?` with a propagation
operator (hypothetical).

      public value(): Result<JsonSyntaxTree, JsonSyntaxError> {
        space();
        if (!more) { return fail("expected a value"); }
        let c = text[i];
        if (c == char'[') {
          step();
          let elements = new ListBuilder<JsonSyntaxTree>();
          space();
          if (more && text[i] == char']') { step(); return ok(new JsonArray(elements.toList())); }
          while (true) {
            let element = value();
            when (element) {
              is Ok<JsonSyntaxTree, JsonSyntaxError> -> elements.add(element.value);
              else -> return element;
            }
            space();
            if (!more) { return fail("expected , or ]"); }
            let d = text[i];
            step();
            if (d == char']') { break; }
            if (d != char',') { return fail("expected , or ]"); }
          }
          ok(new JsonArray(elements.toList()))
        } else if (c == char'"') {
          step();
          let start = i;
          while (more && text[i] != char'"') { step(); }
          if (!more) { return fail("unclosed string"); }
          let s = text.slice(start, i);
          step();
          ok(new JsonString(s))
        } else if (c == char'-' || (c >= char'0' && c <= char'9')) {
          let start = i;
          step();
          while (more && text[i] >= char'0' && text[i] <= char'9') { step(); }
          ok(new JsonNumericToken(text.slice(start, i)))
        } else {
          fail("unexpected character")
        }
      }

      public fail(message: String): Result<JsonSyntaxTree, JsonSyntaxError> {
        new Failed<JsonSyntaxTree, JsonSyntaxError>(new JsonSyntaxError(message, offset))
      }

      private ok(tree: JsonSyntaxTree): Result<JsonSyntaxTree, JsonSyntaxError> {
        new Ok<JsonSyntaxTree, JsonSyntaxError>(tree)
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

`as` bubbles today, so each cast became an `is` check that fails with
what was expected.

    export interface JsonAdapter<T> {
      public decodeFromJson(t: JsonSyntaxTree): Result<T, JsonShapeError>;
    }

    export class Int32JsonAdapter extends JsonAdapter<Int> {
      public decodeFromJson(t: JsonSyntaxTree): Result<Int, JsonShapeError> {
        let n = if (t is JsonNumericToken) { t.asInt32() } else { null };
        if (n == null) { return new Failed<Int, JsonShapeError>(new JsonShapeError("", "an Int32")); }
        new Ok<Int, JsonShapeError>(n)
      }
    }

    export class StringJsonAdapter extends JsonAdapter<String> {
      public decodeFromJson(t: JsonSyntaxTree): Result<String, JsonShapeError> {
        if (t is JsonString) { return new Ok<String, JsonShapeError>(t.content); }
        new Failed<String, JsonShapeError>(new JsonShapeError("", "a string"))
      }
    }

A failure inside an element gets the element's index put in front of
its path: context added on the way up, as a cause chain would.

    export class ListJsonAdapter<T>(private adapterForT: JsonAdapter<T>) extends JsonAdapter<List<T>> {
      public decodeFromJson(t: JsonSyntaxTree): Result<List<T>, JsonShapeError> {
        if (!(t is JsonArray)) {
          return new Failed<List<T>, JsonShapeError>(new JsonShapeError("", "an array"));
        }
        let elements = (t as JsonArray orelse panic()).elements;
        let b = new ListBuilder<T>();
        for (var i = 0; i < elements.length; i += 1) {
          let r = adapterForT.decodeFromJson(elements[i]);
          when (r) {
            is Ok<T, JsonShapeError> -> b.add(r.value);
            is Failed<T, JsonShapeError> -> return new Failed<List<T>, JsonShapeError>(
              new JsonShapeError("[${i.toString()}]${r.error.path}", r.error.expected)
            );
            else -> panic();
          }
        }
        new Ok<List<T>, JsonShapeError>(b.toList())
      }
    }

Two failure types meet here. Both are `JsonProblem`s, so the result
can say either, and a caller can match them; each needs a new `Failed`
of the wider type.

    export let decodeJson<T>(text: String, adapter: JsonAdapter<T>): Result<T, JsonProblem> {
      let tree = parseJson(text);
      when (tree) {
        is Ok<JsonSyntaxTree, JsonSyntaxError> -> do {
          let r = adapter.decodeFromJson(tree.value);
          when (r) {
            is Ok<T, JsonShapeError> -> new Ok<T, JsonProblem>(r.value);
            is Failed<T, JsonShapeError> -> new Failed<T, JsonProblem>(r.error);
            else -> panic();
          }
        }
        is Failed<JsonSyntaxTree, JsonSyntaxError> -> new Failed<T, JsonProblem>(tree.error);
        else -> panic();
      }
    }

## Tests

    let ints = new ListJsonAdapter<List<Int>>(new ListJsonAdapter<Int>(new Int32JsonAdapter()));

    let describe<T>(r: Result<T, JsonProblem>): String {
      when (r) {
        is Ok<T, JsonProblem> -> "ok";
        is Failed<T, JsonProblem> -> do {
          let e = r.error;
          let kind = when (e) {
            is JsonSyntaxError -> "syntax";
            is JsonShapeError -> "shape";
          };
          "${kind}: ${e.message}"
        }
        else -> panic();
      }
    }

    test("decodes") {
      let xs = decodeJson("[[1, 2], [], [-3]]", ints);
      when (xs) {
        is Ok<List<List<Int>>, JsonProblem> -> assert(xs.value.length == 3 && xs.value[2][0] == -3);
        else -> assert(false);
      }
    }

    test("says what and where") {
      assert(describe(decodeJson("[[1, 2], [3", ints)) == "syntax: expected , or ] at 11");
      assert(describe(decodeJson("[[1, 2], [\"3\"]]", ints)) == "shape: at [1][0]: expected an Int32");
      assert(describe(decodeJson("[[1, 2], [99999999999]]", ints)) == "shape: at [1][0]: expected an Int32");
      assert(describe(decodeJson("[1]", ints)) == "shape: at [0]: expected an array");
      assert(describe(decodeJson("[] x", ints)) == "syntax: extra text after the value at 3");
    }
