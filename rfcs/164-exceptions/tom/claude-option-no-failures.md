**Option 0: no failure support,** for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
Drafted by Claude, 2026-11-18, from Tom's option of the same day, as a
third option beside [the proposal's middle ground](claude-proposal.md)
and [first-class results](claude-proposal-values.md). Neutral;
suggestions are labeled, and syntax marked **HYPOTHETICAL** doesn't
compile today. The site-by-site audit is in
[claude-option-no-failures-audit.md](claude-option-no-failures-audit.md).

## The option

Temper has only nullables and panics. No `throws`, no `bubble()`, no
`orelse`, no failure types, no `Result` type in core or std, and no way
to declare a failure that a backend would present as its host's
exception or error value.

- **Recoverable failure is absence,** `T?`, read with `??`.
- **Bugs are panics,** never caught by Temper code. Builtins whose
  failure is a bug (Int division by zero, failed downcasts, list and map
  reads) panic.
- **Libraries that want reasons define their own result types,** as
  Argmas, Hrefine, and Kelpto already do.
- **`return`, `break`, and `continue` become expressions,** so
  absence propagates in one line.

```temper
// HYPOTHETICAL: `return` as an expression.
let tree = parseJson(text) ?? return null;
let n = s.toInt32() ?? continue;
keyword("FROM") || return null;          // a check returning Boolean
```

Whether core or std must tell "no value" from "failed" was the open
question; the [audit](claude-option-no-failures-audit.md#core-and-std-domain-by-domain)
finds three places that do (maps with nullable values, promises and
std/net, JSON decoding), each with a narrower answer than a general
result type.

## What it removes

- **Language:** `throws`, `Bubble`, `bubble()`, `orelse`, and the
  question of how `orelse` and `??` relate. Nothing for the two RFC
  questions to decide: no results to hold, no propagation marker, no
  failure parameters.
- **Compilers:** tmpl's `bubbles` flag and `MAY_BUBBLE`, the internal
  `Result<T, Bubble>` typing and its second type per expression,
  per-backend failure lowering, generated handlers, and Kotlin Temper's
  special cases (the `checkFun` TODO, core's inlined `forEach`,
  `asInt64Safe`, [#108](https://github.com/temperlang/temper/issues/108),
  [#109](https://github.com/temperlang/temper/issues/109)).
- **Behavior bugs:** of the
  [twelve](claude-common-ground.md#bugs-to-fix-as-part-of-the-rfc-work),
  1, 3, 4, 8, 9, 10, and 12 dissolve (nothing is left to catch, or the
  builtin returns `null` or panics). Float64 division (2), which strings
  `toInt32` accepts (5), panic output and test runners (6, 7), and JS
  interface fields (11) remain.
- **Host mapping:** no generated failure classes, bases, messages,
  causes, or stack-trace policy. Hosts see `null`, `None`, `nil`, or
  `Option`, and panics.

## Evidence for

- **Most failure handling is already panics.** 501 of 596 `orelse`s are
  `orelse panic()`, and 328 of them disappear outright once downcasts,
  reads, division, and code points panic
  ([audit](claude-option-no-failures-audit.md#counts)). Most of
  Chromarite's failure exists only because of reads and division: 30
  of its 52 `throws Bubble` go.
- **Few real failure entry points.** Of 289 bubbling declarations, 164
  become `T?` mechanically and 62 `Boolean` given one convention for
  `Void`; only 12 need a reason (Wherewith's seven entry points, std's
  JSON parsing, Hrefine's policy builders), and 8 are ambiguous because
  `null` already means something
  ([every (d)](claude-option-no-failures-audit.md#every-d-null-already-means-something)).
- **Libraries already hand-roll result values.** Argmas's
  `ParseResult`, Hrefine's `UrlCheck` and `ErrorLog`, Kelpto's
  `HtmlParseError` lists, and Wherewith's `…Problem` twins and `problem`
  fields all exist because a bubble carries nothing
  ([findings §3](claude-findings.md#where-libraries-built-their-own-error-values-and-why)).
  Under option 0, those are simply the style.
- **Kelpto and Wherewith never fail on valid input**
  ([estimates](claude-explore/estimates/README.md)): failure there is
  rare, so its form costs nothing on their hot paths, and Lua loses the
  1 to 6 percent its `orelse` closures cost.
- **Adding failures later is additive; removing them breaks.** A
  language without `throws` can gain declared failures in a later
  version without breaking Temper code; one that ships them can't take
  them back.

## Costs

- **No idiomatic exceptions for hosts.** Tom's 2024 notes name this
  as the reason not to drop failure handling: "it's hard to represent
  this situation idiomatically in backends"
  ([tom-thoughts.md](tom-thoughts.md)). A Python, Java, or C# user of
  Wherewith gets `None` or `null` where the language's own libraries
  raise, and **a silent `null` fails far from its cause**: a
  `NullPointerException` or `AttributeError` three calls later, or a
  `Boolean` from Kelpto's `setLevel` that nobody checks. 89 exported
  declarations change what host code sees
  ([list](claude-option-no-failures-audit.md#every-e-what-host-users-see-change)).
- **Per-library result conventions.** Each library names its own
  result, check, and problem types, so host users learn one convention
  per library, and generic code can't treat them alike.
- **Verbose propagation, and a `Void` convention.** About 630 calls
  propagate implicitly today
  ([markers](claude-common-ground.md#propagation-markers)); each becomes
  `?? return null` or `|| return false`, the same count as the
  proposal's `try`, but without one shared form, and without
  `return` as an expression each needs a hoisted `let` and an `if`
  ([explore](claude-explore/README.md#what-dropping-throws-bubble-would-take)).
  The reason, where one exists, travels in a field beside the `null`.
- **std I/O needs its own types.** No broken promises means std/net, and
  any later file or process API, defines a status type per domain, and
  each backend's connected code maps host errors into it.
- **Nullable numbers cost on managed runtimes.** An `Int?` boxes on the
  JVM and is slow across calls on .NET 6, dearer than today's bubbling
  when failures are rare (below about 0.1 to 1 percent;
  [measurements](claude-explore/README.md#measurements)), unless
  backends lower internal nullables to sentinels.
- **Null can't say everything.** The 8 ambiguous sites need their own
  answers (a panicking `Map.get` plus `has`, a diagnostics sink for JSON
  decoding, no broken promises), and constructors can't return `null`
  (std's `Date` becomes a factory).

## Audit summary

From the [audit](claude-option-no-failures-audit.md), which has every
(c), (d), and (e) case:

| | Argmas | Chromarite | Hrefine | Kelpto | Ordable | Wherewith | std | core | All |
|---|---|---|---|---|---|---|---|---|---|
| `throws Bubble` declarations | 8 | 52 | 24 | 49 | 0 | 104 | 37 | 15 | 289 |
| (a) `T?` mechanically | 8 | 22 | 19 | 32 | 0 | 49 | 27 | 7 | 164 |
| (b) panic | 0 | 30 | 1 | 0 | 0 | 0 | 4 | 3 | 38 |
| (c) needs a result type | 0 | 0 | 3 | 0 | 0 | 7 | 2 | 0 | 12 |
| (d) null already meaningful | 0 | 0 | 0 | 0 | 0 | 4 | 2 | 2 | 8 |
| (f) other (62 `Void`, a constructor, generators, test runner) | 0 | 0 | 1 | 17 | 0 | 44 | 2 | 3 | 67 |
| (e) host-facing (overlaps the above) | 1 | 3 | 10 | 25 | 0 | 7 | 29 | 14 | 89 |
| `bubble()` calls | 9 | 28 | 46 | 48 | 0 | 59 | 7 | 1 | 198 |
| `orelse` (in tests) | 22 (0) | 74 (7) | 122 (104) | 322 (229) | 13 (0) | 23 (0) | 17 (0) | 3 (0) | 596 (340) |
| `orelse` that go (the operation panics) | 12 | 65 | 3 | 216 | 13 | 12 | 12 | 1 | 334 |

Core and std need "failed" apart from "no value" for maps whose values
may be null, promises (std/net's `bodyContent` is a `Promise<String?>`),
and JSON decoding through `OrNullJsonAdapter`; and want reasons for JSON
parsing and network errors. **Suggestions:** `Mapped.get` panics as list
reads do, beside `getOr` and a native `has`; promises can't be broken,
and std/net resolves to a `NetResponse` or `NetFailure`; JSON adapters
record problems in the `InterchangeContext` they already take; parsing
returns a std `JsonParseResult`. Number parsing, regex, and dates need
only `T?` (and a `Date.of` factory).

## Not proposed: errors at the host boundary

Option 0 shouldn't generate host exceptions or results from Temper's
result classes (Tom, 2026-11-27). That would bring back most of what
declared errors need: a contract the compiler recognizes, per-host
error types, messages, and names. Under option 0, host APIs return the
same result classes, nullables, and panics that Temper code sees.

## Collect, don't stop

**Suggestion,** for parsing and validation under any option: return a
result object holding the value, or a partial value, and a list of
problems, rather than stopping at the first one. Hrefine's validation
log, Kelpto's HTML errors (HTML parsing never fails), Argmas's error
values, and Wherewith's lexer, which stores problems as values, already
do. Error-tolerant formats need it, and tools (editors, linters,
form validators) want every diagnostic at once. Operations with one way to fail (number parsing, decoding one
value) lose little with `T?`.

## As a first phase

**Suggestion:** option 0 could be the first phase of the proposal
rather than an alternative to it. Ship what every option needs, all in
the [common ground](claude-common-ground.md): panicking builtins,
`return` as an expression, precedence, panics per backend, and
panic-tolerant test runners. Then stop adding `throws Bubble` code,
move libraries to `T?` and result values, and see whether they miss
declared failures. If they do, add the proposal's design later, which
is additive in the language. The libraries' host APIs would change
twice (exception, then `null`, then a declared failure), which their
beta status allows.

## Open questions

- Whether `throws Bubble` is removed or kept, deprecated, as the
  no-detail failure during a transition.
- Whether `Mapped.get` panics, and how `has` is implemented on each
  backend.
- How connected async APIs report failure without broken promises, and
  whether host promise rejections become panics or domain values.
- The `Void` convention (`Boolean`, or a library status type) and
  whether `|| return false` reads well enough.
