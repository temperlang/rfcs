# Today: parsing bubbles, validation errors are a side log

Simplified from Hrefine (`src/url.temper.md`): the URL Standard's
parser bubbles where the standard says "return failure", and notes
[validation errors](https://url.spec.whatwg.org/#validation-error) in
an `ErrorLog` only when `checkUrl` asks for them. Here the input is
just an authority, `host:port`, which keeps the same shapes: a
non-fatal error (spaces at the ends), fatal ones (a bad host code
point, a bad port), and the three public entry points (`parseUrl`
bubbles, `Url.parse` gives null, and `checkUrl` says why).

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

## The parser

    export class Authority(public host: String, public port: Int) {
      public toString(): String {
        if (port < 0) { host } else { "${host}:${port.toString()}" }
      }

      public static parse(input: String): Authority? { parseAuthority(input) orelse null }
    }

Bubbles where parsing fails, as `new URL()` throws.

    export let parseAuthority(input: String): Authority throws Bubble {
      parseRecord(input, null)
    }

What `checkAuthority` found: the authority or null, and every
validation error, fatal or not, in order.

    export class AuthorityCheck(
      public authority: Authority?,
      public errors: List<ValidationError>,
    ) {}

    export let checkAuthority(input: String): AuthorityCheck {
      let log = new ErrorLog();
      let found: Authority? = parseRecord(input, log) orelse null;
      new AuthorityCheck(found, log.errors.toList())
    }

The parser notes each error where the standard does, and bubbles for
the fatal ones. Without a log, a failure says nothing: the reason is
noted only when someone asked for it.

    let parseRecord(input: String, log: ErrorLog?): Authority throws Bubble {
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
          note(log, "host-invalid-code-point", at);
          bubble();
        }
        host.appendCodePoint(c) orelse panic();
        i = input.next(i);
        at += 1;
      }
      if (host.toString().isEmpty) {
        note(log, "host-missing", at);
        bubble();
      }
      let port = if (i < end) {
        parsePort(input, input.next(i), end, at + 1, log)
      } else {
        -1
      };
      new Authority(host.toString(), port)
    }

    let parsePort(input: String, from: StringIndex, end: StringIndex, at: Int, log: ErrorLog?): Int throws Bubble {
      var value = 0;
      var digits = 0;
      for (var i = from; i < end; i = input.next(i)) {
        let c = input[i];
        if (c < char'0' || c > char'9') {
          note(log, "port-invalid", at + digits);
          bubble();
        }
        value = value * 10 + c - char'0';
        if (value > 65535) {
          note(log, "port-out-of-range", at);
          bubble();
        }
        digits += 1;
      }
      if (digits == 0) { -1 } else { value }
    }

    let isHostCode(c: Int): Boolean {
      (c >= char'a' && c <= char'z') || (c >= char'A' && c <= char'Z') ||
        (c >= char'0' && c <= char'9') || c == char'.' || c == char'-'
    }

## Tests

    test("parses") {
      assert((parseAuthority("example.com:8080") orelse panic()).toString() == "example.com:8080");
      assert((parseAuthority("example.com") orelse panic()).port == -1);
      assert(Authority.parse(" example.com ")?.host == "example.com");
    }

    test("fails without saying why") {
      assert(Authority.parse("exa mple.com") == null);
      assert(Authority.parse("example.com:99999") == null);
      assert(Authority.parse(":80") == null);
      // A caller of parseAuthority learns only that it failed.
      let reason = do { parseAuthority("example.com:8a"); "parsed" } orelse "failed";
      assert(reason == "failed");
    }

    test("checkAuthority says why, and keeps going past non-fatal errors") {
      let ok = checkAuthority(" example.com:80");
      assert(ok.authority?.port == 80);
      assert(ok.errors.join(", ") { (e: ValidationError): String => e.toString() } == "invalid-URL-unit at 0");
      let bad = checkAuthority(" example.com:8a");
      assert(bad.authority == null);
      assert(bad.errors.join(", ") { (e: ValidationError): String => e.toString() } ==
        "invalid-URL-unit at 0, port-invalid at 14");
      let far = checkAuthority("example.com:99999");
      assert(far.errors[0].toString() == "port-out-of-range at 12");
    }
