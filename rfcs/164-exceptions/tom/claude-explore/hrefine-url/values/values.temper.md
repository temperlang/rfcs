# Design A: a failure says why, and validation errors stay a list

The same parser as [current](../current/current.temper.md), with design
A's rules. A fatal error is the parser's result: `Failed` carrying the
`ValidationError` that stopped it, whether or not anyone asked for a
log. Non-fatal errors still go in the log, since they sit next to a
usable result, and `checkAuthority` still collects them.

## Validation errors

    export class ValidationError(
      public name: String,
      public position: Int,
    ) {
      public toString(): String { "${name} at ${position.toString()}" }
    }

    class ErrorLog {
      public errors: ListBuilder<ValidationError> = new ListBuilder<ValidationError>();
    }

    let note(log: ErrorLog?, name: String, position: Int): Void {
      if (log != null) { log.errors.add(new ValidationError(name, position)); }
    }

A fatal error: noted in the log like the others, and returned.

    let fatal(log: ErrorLog?, name: String, position: Int): ValidationError {
      let error = new ValidationError(name, position);
      if (log != null) { log.errors.add(error); }
      error
    }

## The parser

    export class Authority(public host: String, public port: Int) {
      public toString(): String {
        if (port < 0) { host } else { "${host}:${port.toString()}" }
      }

`Authority.parse` stays nullable: a caller who asks for null doesn't
want the reason.

      public static parse(input: String): Authority? {
        let r = parseRecord(input, null);
        when (r) {
          is Ok<Authority, ValidationError> -> r.value;
          else -> null;
        }
      }
    }

`parseAuthority` no longer bubbles; its failure says which validation
error stopped it and where, without the cost of a log.

    export let parseAuthority(input: String): Result<Authority, ValidationError> {
      parseRecord(input, null)
    }

    export class AuthorityCheck(
      public authority: Authority?,
      public errors: List<ValidationError>,
    ) {}

    export let checkAuthority(input: String): AuthorityCheck {
      let log = new ErrorLog();
      let r = parseRecord(input, log);
      let found: Authority? = when (r) {
        is Ok<Authority, ValidationError> -> r.value;
        else -> null;
      };
      new AuthorityCheck(found, log.errors.toList())
    }

Each `bubble()` became `return new Failed(...)`. Propagating
`parsePort`'s failure takes a `when` and a new `Failed`, since its `T`
is `Int`, not `Authority`; with a propagation operator (hypothetical)
it would be `parsePort(...)?`.

    let parseRecord(input: String, log: ErrorLog?): Result<Authority, ValidationError> {
      var start = String.begin;
      var end = input.end;
      var skipped = 0;
      while (input.hasIndex(start) && input[start] == char' ') {
        start = input.next(start);
        skipped += 1;
      }
      while (end > start && input[input.prev(end)] == char' ') { end = input.prev(end); }
      if (skipped > 0 || end < input.end) { note(log, "invalid-URL-unit", 0); }
      let host = new StringBuilder();
      var at = skipped;
      var i = start;
      while (i < end && input[i] != char':') {
        let c = input[i];
        if (!isHostCode(c)) {
          return new Failed<Authority, ValidationError>(fatal(log, "host-invalid-code-point", at));
        }
        host.appendCodePoint(c) orelse panic();
        i = input.next(i);
        at += 1;
      }
      if (host.toString().isEmpty) {
        return new Failed<Authority, ValidationError>(fatal(log, "host-missing", at));
      }
      var port = -1;
      if (i < end) {
        let parsed = parsePort(input, input.next(i), end, at + 1, log);
        when (parsed) {
          is Ok<Int, ValidationError> -> port = parsed.value;
          is Failed<Int, ValidationError> -> return new Failed<Authority, ValidationError>(parsed.error);
          else -> panic();
        }
      }
      new Ok<Authority, ValidationError>(new Authority(host.toString(), port))
    }

    let parsePort(input: String, from: StringIndex, end: StringIndex, at: Int, log: ErrorLog?): Result<Int, ValidationError> {
      var value = 0;
      var digits = 0;
      for (var i = from; i < end; i = input.next(i)) {
        let c = input[i];
        if (c < char'0' || c > char'9') {
          return new Failed<Int, ValidationError>(fatal(log, "port-invalid", at + digits));
        }
        value = value * 10 + c - char'0';
        if (value > 65535) {
          return new Failed<Int, ValidationError>(fatal(log, "port-out-of-range", at));
        }
        digits += 1;
      }
      new Ok<Int, ValidationError>(if (digits == 0) { -1 } else { value })
    }

    let isHostCode(c: Int): Boolean {
      (c >= char'a' && c <= char'z') || (c >= char'A' && c <= char'Z') ||
        (c >= char'0' && c <= char'9') || c == char'.' || c == char'-'
    }

## Tests

    let describe(r: Result<Authority, ValidationError>): String {
      when (r) {
        is Ok<Authority, ValidationError> -> r.value.toString();
        is Failed<Authority, ValidationError> -> "failed: ${r.error.toString()}";
        else -> panic();
      }
    }

    test("parses") {
      assert(describe(parseAuthority("example.com:8080")) == "example.com:8080");
      assert(Authority.parse("example.com")?.port == -1);
      assert(Authority.parse(" example.com ")?.host == "example.com");
    }

    test("a failure says why, without a log") {
      assert(describe(parseAuthority("exa mple.com")) == "failed: host-invalid-code-point at 3");
      assert(describe(parseAuthority("example.com:99999")) == "failed: port-out-of-range at 12");
      assert(describe(parseAuthority(":80")) == "failed: host-missing at 0");
      assert(describe(parseAuthority("example.com:8a")) == "failed: port-invalid at 13");
      assert(Authority.parse("exa mple.com") == null);
    }

    test("checkAuthority as before") {
      let ok = checkAuthority(" example.com:80");
      assert(ok.authority?.port == 80);
      assert(ok.errors.join(", ") { (e: ValidationError): String => e.toString() } == "invalid-URL-unit at 0");
      let bad = checkAuthority(" example.com:8a");
      assert(bad.authority == null);
      assert(bad.errors.join(", ") { (e: ValidationError): String => e.toString() } ==
        "invalid-URL-unit at 0, port-invalid at 14");
    }
