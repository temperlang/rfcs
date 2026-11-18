Audit for [option 0, no failure support](claude-option-no-failures.md):
what every `throws Bubble` declaration, `bubble()`, and `orelse` in the
public Temper libraries and tempest's `lib/core` and `lib/std` would
become if Temper had only nullables and panics. Drafted by Claude,
2026-11-18, for the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164)).
The classification is a judgment, made by rules and by reading the
code; read the counts as estimates, and the per-site files as the
place to disagree.

## Method

The sources are the ones counted in
[claude-explore](claude-explore/README.md#what-dropping-throws-bubble-would-take):
Argmas, Chromarite, Hrefine, Kelpto, Ordable, and Wherewith, and
tempest's `lib/core` and `lib/std`, as of 2026-11-18, without files of
tests (`*-tests.temper.md`), but with the tests some libraries keep
inside their source files, which are counted separately where it
matters. Code is the indented Temper in `.temper.md` files, plus
std's regex module, which uses bare fenced blocks; comments are left
out.
[scan.py](claude-explore/no-failures-audit/scan.py) finds the sites and
[classify.py](claude-explore/no-failures-audit/classify.py) applies the
rules; every site, with its class and a note, is in
[results/](claude-explore/no-failures-audit/results/).

**Against the earlier counts:** 289 function declarations rather than
286, since the earlier scan missed std regex's three `find` methods,
which sit in fenced code, plus three function types (std's `TestFun` and
two slots in core's generator wrapper) left out of the tables below;
596 `orelse`s, as before, of which 501 are `orelse panic()` (500
before).

**Classes:**

- **(a) `T?`**, mechanically: `throws Bubble` becomes `T?`, `bubble()`
  becomes `return null`, `orelse x` becomes `?? x`. Includes internal
  functions whose reason already travels in a side channel (Wherewith's
  `problem` field, Hrefine's `ErrorLog`).
- **(b) A panic:** the failure is a bug a cheap check avoids
  (division, downcasts, list and map reads, invalid code points), so
  the declaration goes, or `orelse panic()` moves into the operation.
- **(c) A library-defined result type,** because callers need the
  reason.
- **(d) Ambiguous:** `null` is already a successful value.
- **(e) Host-facing:** an exported declaration, or one hosts implement,
  so Java, Python, and C# users see `null`, `None`, or `false` where
  they now catch an exception. This overlaps the other classes, so it's
  counted separately.
- **(f) Other:** `Void` functions, which have no value to make null and
  need a convention (return `Boolean`); a constructor; generators; and
  the test harness.

**Checked by hand:** a seeded random sample of 24 sites (8 declarations,
8 `bubble()`s, and 8 `orelse`s, from Argmas, Chromarite, Hrefine,
Kelpto, Wherewith, and core) matched the class the rules gave, and every
core and std declaration was classified by reading it. Known soft spots: which side of (a) and (b) Kelpto's
editing checks fall on (see the notes under Kelpto), and the Hrefine
policy builders, put under (c) but arguably (b).

## Counts

**Declarations** (functions, methods, and constructors with
`throws Bubble`):

| Library | Total | (a) `T?` | (b) panic | (c) result type | (d) ambiguous | (f) other | (e) host-facing |
|---|---|---|---|---|---|---|---|
| Argmas | 8 | 8 | 0 | 0 | 0 | 0 | 1 |
| Chromarite | 52 | 22 | 30 | 0 | 0 | 0 | 3 |
| Hrefine | 24 | 19 | 1 | 3 | 0 | 1 | 10 |
| Kelpto | 49 | 32 | 0 | 0 | 0 | 17 | 25 |
| Ordable | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Wherewith | 104 | 49 | 0 | 7 | 4 | 44 | 7 |
| std | 37 | 27 | 4 | 2 | 2 | 2 | 29 |
| core | 15 | 7 | 3 | 0 | 2 | 3 | 14 |
| **All** | **289** | **164** | **38** | **12** | **8** | **67** | **89** |

Of the 67 under (f), 62 are `Void` functions (Wherewith 44, Kelpto 17,
Hrefine 1), mechanical given one convention; the rest are std's `Date`
constructor and `runTest`, and core's three generator `next` methods.

**`bubble()` calls,** by the class of the function they're in:

| Library | Total | (a) `return null` | (b) `panic()` | (c) return a failure value | (d) | (f) `return false` |
|---|---|---|---|---|---|---|
| Argmas | 9 | 9 | 0 | 0 | 0 | 0 |
| Chromarite | 28 | 24 | 4 | 0 | 0 | 0 |
| Hrefine | 46 | 43 | 0 | 1 | 0 | 2 |
| Kelpto | 48 | 31 | 0 | 0 | 0 | 17 |
| Wherewith | 59 | 44 | 0 | 7 | 2 | 6 |
| std | 7 | 2 | 2 | 2 | 0 | 1 |
| core | 1 | 0 | 0 | 0 | 1 | 0 |
| **All** | **198** | **153** | **6** | **10** | **3** | **26** |

(Kelpto's three `as GreenNode orelse bubble()` count as (a): an `is`
check, then `return null`.)

**`orelse`:**

| Library | Total (in tests) | (b) the panic moves into the operation | (a) `?? x` or `?? panic()` | (d) | (f) |
|---|---|---|---|---|---|
| Argmas | 22 (0) | 12 | 8 | 0 | 2 |
| Chromarite | 74 (7) | 65 | 2 | 0 | 7 |
| Hrefine | 122 (104) | 3 | 119 | 0 | 0 |
| Kelpto | 322 (229) | 216 | 106 | 0 | 0 |
| Ordable | 13 (0) | 13 | 0 | 0 | 0 |
| Wherewith | 23 (0) | 12 | 10 | 0 | 1 |
| std | 17 (0) | 12 | 3 | 0 | 2 |
| core | 3 (0) | 1 | 0 | 2 | 0 |
| **All** | **596 (340)** | **334** | **248** | **2** | **12** |

The 501 `orelse panic()`s, by what they cover: `as` (204), library calls
that stay fallible (172, 155 of them in tests), `appendCodePoint` (38),
library calls and `do` blocks that fail only through reads or division
(48), `/` and `%` (16), list and map reads (16), `String.fromCodePoint`
(6), and a conversion (1). So 328 of them disappear once those builtins
panic, and 173 become `?? panic()`. Of the 95 other fallbacks, 6 are
Wherewith's division after a zero check (they go), 12 use a `Void` call
as a check (`do { f(); true } orelse false`, needing a `Boolean`), 2
are core's `getOr` and `has` (built on `Mapped.get`, so (d)), and the
rest become `?? x`.

**Outside tests,** 256 `orelse`s: 201 go (b), 48 become `?? x` or
`?? panic()` (a), 2 are (d), and 5 need a `Boolean` (f).

## Core and std, domain by domain

Where would core and std need to tell "no value" from "failed", and what
would each use instead? Everything here is a suggestion, labeled.

| Domain | Today | Null vs failure? | Under option 0 (suggestion) |
|---|---|---|---|
| Number parsing (`String.toInt32`, `toInt64`, `toFloat64`) | bubbles | no: a number is never null | `Int?`; backends must agree on which strings fail (bug 5) |
| Narrowing (`Int64.toInt32`, `toFloat64`; `Float64.toInt32`, `toInt64`) | bubbles | no | `T?`, or a panic for the cheap range checks (core's own TODO asks) |
| Code points (`fromCodePoint`, `fromCodePoints`, `appendCodePoint`) | bubbles | no | panic (44 of the 45 `orelse`s on them are `orelse panic()`); Wherewith's one `orelse "?"` checks first; decoders of untrusted text check validity, or a `…OrNull` |
| Int `/`, `%`; `as` | bubbles | no | panic; untrusted data is tested with `is` (std's JSON adapters use `as` on input today, so they change) |
| Float64 `/`, `%` | disagrees per backend (bug 2) | no | IEEE 754 Infinity and NaN, as five backends already do, or a panic; a decision either way |
| Maps (`Mapped.get`, `MapBuilder.remove`) | bubbles | **yes**: `V` is unbounded, so `Map<String, String?>` is legal and `V?` can't tell a missing key from a null value | `get` panics on a missing key, as list reads do; `getOr`, `has` (made native rather than built on `get`), and a `getOrNull` documented as ambiguous for nullable `V`, as Kotlin's `Map.get` is; `remove` likewise |
| Generators (`Generator.next`) | bubbles; not translated (bug 9) | no: `GeneratorResult` already tells a value from done | `next` can't fail; a generator that fails yields its own result values, or stops and records why in a field |
| Promises (`await`, `PromiseBuilder.breakPromise`) | a broken promise bubbles at `await`; translation fails (bug 8) | **yes**: `Promise<String?>` exists (std/net's `bodyContent`), so `await` giving `R?` would collapse "broken" into "resolved to null" | no broken promises in Temper: `breakPromise` goes, and async work that can fail resolves to a domain type; connected functions map host rejections into that type |
| Network (`NetRequest.send`, `NetResponse.bodyContent`) | `send` gives a broken promise for unsupported features and network errors | **yes**, as above | a std status type, for example `send(): Promise<NetOutcome>`, a sealed `NetResponse` or `NetFailure(message)`, as fetch distinguishes a response from a network error |
| JSON parsing (`parseJson`, `JsonSyntaxTreeProducer.toJsonSyntaxTree`) | bubbles; the message (`jsonError`) is dropped | no (JSON `null` is a `JsonNull` object, not Temper's `null`) | (c): a std result, such as `JsonParseResult(tree?, error?, offset)`, or `parseJson(): JsonSyntaxTree?` beside the producer's existing `jsonError` |
| JSON values (`propertyValueOrBubble`, `JsonNumeric.asInt32` and others) | bubbles | no | `T?`; `propertyValueOrNull` already exists, and `asInt64Safe`'s twin goes |
| JSON decoding (`JsonAdapter.decodeFromJson`) | bubbles | **yes**: `JsonAdapter<T>` admits a nullable `T`, and `OrNullJsonAdapter` returns `null` for JSON `null` | adapters report problems to the `InterchangeContext` they already take, collecting a path and message per problem, and return `T?`; a `null` with no problem recorded is a decoded `null` |
| `JsonProducer.toJsonString` | bubbles when the producer was used out of order | no | panic: a bug in the caller |
| Regex (`find`) | bubbles on no match | no | `Match?` |
| Dates (`Date(y, m, d)`, `Date.fromIsoString`, `Date.decodeFromJson`) | bubbles; the constructor too | no | `Date?` from a factory (`Date.of`), since a constructor can't return null, so host `new Date(…)` changes; or a panic for an impossible date |
| Testing (`assertHard`, `softFailToHard`, `bail`, `runTest`, `TestFun`) | a hard assertion bubbles; `runTest` catches it | not about null | hard assertions panic; test functions can't fail; runners must report a panicking test and keep going on every backend, which C# and C++ don't today (bug 7) |

So core and std need the distinction in three places: maps with
nullable values, promises (and std/net above them), and JSON decoding.
None needs a generic core result type; each has a narrower answer
(a panicking `get` plus `has`, no broken promises plus a domain type,
a diagnostics sink). Two domains want reasons, JSON parsing and
network I/O, and each can define its own type.

## Every (c): callers need the reason

| Library | Declaration | Note |
|---|---|---|
| Hrefine | `UrlPolicy.withHosts` | the bad entry is the reason; arguably a panic, since configuration mistakes are bugs |
| Hrefine | `UrlPolicy.withSubdomainsOf` | as above |
| Hrefine | `UrlPolicy.withPorts` | as above (a port outside 0 to 65,535) |
| Wherewith | `Dialect.quoteName` | `nameProblem` twin today |
| Wherewith | `Dialect.quoteString` | `stringProblem` twin today |
| Wherewith | `Identifier.named` | a name the dialects can't write |
| Wherewith | `Query.checked` | `templateProblem` today |
| Wherewith | `Query.render` | `renderProblem` twin today |
| Wherewith | `Query.renderedParts` | as `render`; used for nested queries |
| Wherewith | `QueryBuilder.build` | `templateProblem` today |
| std | `parseJson` | message and offset, dropped today |
| std | `JsonSyntaxTreeProducer.toJsonSyntaxTree` | holds the parse error (`jsonError`) |

Argmas, Hrefine's parsers, and Kelpto's HTML parser need no (c): they
already return their own result values (`ParseResult`, `UrlCheck`,
lists of `HtmlParseError`).

## Every (d): null already means something

| Library | Site | Note |
|---|---|---|
| core | `Mapped.get` | `V` may be nullable |
| core | `MapBuilder.remove` | as above |
| core | `Mapped.getOr`, `Mapped.has` (2 `orelse`s) | built on `get`; need a presence test of their own |
| std | `JsonAdapter.decodeFromJson` | `T` may be nullable |
| std | `OrNullJsonAdapter.decodeFromJson` | `null` is a decoded JSON `null` |
| std (no declaration) | `await`, `breakPromise`; `NetResponse.bodyContent: Promise<String?>` | resolved to `null` vs broken |
| Wherewith | `StatementParser.sourceAlias(): CommonName?` | `null` means no alias; a bubble a syntax error |
| Wherewith | `joined(): CommonJoin?` | `null` means no join |
| Wherewith | `joinedAt(t): CommonJoin?` | as above |
| Wherewith | `where(): CommonExpr?` | `null` means no `WHERE` |

Wherewith's four are internal and can return a sentinel or record the
problem in the parser's `problem` field and test it after a `null`.

## Every (e): what host users see change

Each of these throws today (a bare `RuntimeException`, `RuntimeError`,
`Exception`, or `Error`, per [findings §1](claude-findings.md#what-host-code-sees-from-an-exported-function)).
Under plain option 0, the (a) and (d) ones return `null`, `None`, or
`nil`; the (f) `Void` ones return `false`; the (b) ones panic (an
`Error` or `IllegalStateException` in Java, `AssertionError` in Python,
per [panics per backend](claude-common-ground.md#panics-per-backend));
the (c) ones return the library's result type.

| Library | Declaration | Class | Note |
|---|---|---|---|
| Argmas | `ValueType.parse` | a | hosts implement it: return `null` instead of throwing |
| Chromarite | `Color.get(i, j)` | b | a bad index panics |
| Chromarite | `Color.alphaAt(i)` | b | as above |
| Chromarite | `Color.parse` | a | `Color?` |
| Hrefine | `parseHost` | a | `Host?` |
| Hrefine | `domainToAscii` | a | `String?` |
| Hrefine | `UrlPolicy.withHosts`, `withSubdomainsOf`, `withPorts` | c | see (c) |
| Hrefine | `parseUrlSource` | a | `UrlSource?` |
| Hrefine | `parseUrl` | a | `Url?`; `checkUrl` already says why |
| Hrefine | `checkUrl` | a | fails only for a bad base, which could join its errors |
| Hrefine | `Url.resolve`, `Url.withHref` | a | `Url?` |
| Kelpto | `replaceAll`, `editAll` | a | `RedNode?` |
| Kelpto | `MarkdownBuilder.heading`, `orderedList` | f | `Boolean`, easy to ignore |
| Kelpto | `MarkdownBuilder.markdownBetween` | a | `String?` |
| Kelpto | `Heading.withLevel`; `Paragraph.withText`, `withContent`; `CodeBlock.withInfo`; `LinkReferenceDefinition.withDestination`; `FootnoteDefinition.withLabel`; `Link.withDestination`; `Image.withDestination`; `FootnoteReference.withLabel` | a | `MarkdownDocument?` (9 methods) |
| Kelpto | `MarkdownEditor.setText`, `setContent`, `setLevel`, `setInfo`, `setDestination`, `setLabel`, `insertBefore`, `insertAfter`, `replace`, `remove` | f | `Boolean` (10 methods), easy to ignore |
| Kelpto | `MarkdownEditor.toDocument` | a | `MarkdownDocument?` |
| Wherewith | `quoteName`, `quoteString`, `Identifier.named`, `Query.checked`, `render`, `renderedParts`, `QueryBuilder.build` | c | see (c) |
| std | `JsonObject.propertyValueOrBubble` | a | goes; `propertyValueOrNull` exists |
| std | `JsonNumeric.asInt32`, `asInt64`, `asFloat64`, and their implementations in `JsonInt32`, `JsonInt64`, `JsonFloat64`, `JsonNumericToken` | a | `T?` (15 methods) |
| std | `JsonTextProducer.toJsonString` | b | panics |
| std | `toJsonSyntaxTree`, `parseJson` | c | see (c) |
| std | `JsonAdapter.decodeFromJson`, `OrNullJsonAdapter.decodeFromJson` | d | hosts implement adapters; see (d) |
| std | `RegexNode.find`, `Regex.find` | a | `Match?` |
| std | `Date` constructor | f | becomes a factory |
| std | `Date.fromIsoString`, `Date.decodeFromJson` | a | `Date?` |
| std | `Test.assertHard`, `softFailToHard` | b | panic |
| std | `runTest` | f | needs panic-tolerant runners |
| core | `Generator.next`, `SafeGenerator.next` | f | can't fail |
| core | `String.fromCodePoint`, `fromCodePoints`, `StringBuilder.appendCodePoint` | b | panic |
| core | `String.toFloat64`, `toInt32`, `toInt64` | a | nullable; connected host code returns null instead of throwing |
| core | `Int64.toFloat64`, `toInt32`; `Float64.toInt32`, `toInt64` | a | as above |
| core | `Mapped.get`, `MapBuilder.remove` | d | see (d) |

That is 89 declarations: Argmas 1, Chromarite 3, Hrefine 10, Kelpto 25,
Wherewith 7, std 29, and core 14.

## Notes per library

- **Argmas:** all mechanical. `ValueType.parse` is the only host-facing
  one, and hosts implement it; Argmas turns its failure into its own
  `invalidValue` error. The two `do { type.parse(text); true } orelse
  false` checks become `!= null`.
- **Chromarite:** 30 of 52 declarations exist only because reads and
  division bubble; they and 65 of 74 `orelse`s go once those panic. The
  22 left are the CSS parser, which becomes `Color?`.
- **Hrefine:** the parser's reasons already travel in its `ErrorLog`,
  and `checkUrl` returns them, so `parseUrl` loses nothing by becoming
  `Url?`. 104 of its 122 `orelse`s are in tests.
- **Kelpto:** never fails on valid input; its bubbling functions are the
  editing API's checks. Some are caller bugs (a level outside 1 to 6, a
  view from another document), which a panic would fit; others depend
  on data (a label with a space, an edit that would reparse
  differently), which `null` fits. Counted here as (a) and (f); a
  closer reading would move some to (b).
- **Ordable:** nothing to change but 13 `orelse panic()`s on `/`, `%`,
  and `appendCodePoint`, which go.
- **Wherewith:** 97 internal declarations become `T?` or `Boolean`,
  with the message in the parser's and checker's `problem` fields as
  today; the 68 calls to `CommonChecker.fail(message, at)` become
  `return fail(…)` returning `null` or `false`. Its seven public entry
  points need a result type, or keep today's `…Problem` twins.
- **std:** as in the table above; 27 of 37 are mechanical.
- **core:** 7 of 15 become nullable, 3 panic, 2 are ambiguous (maps), and
  3 are generators.
