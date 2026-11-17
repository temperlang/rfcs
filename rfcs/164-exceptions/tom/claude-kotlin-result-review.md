**How Kotlin Temper represents failures today**, and how that relates to
the failure-handling RFC
([temperlang/temper#164](https://github.com/temperlang/temper/issues/164))
sketches: [declared failures](claude-proposal-declared.md),
[failures as values](claude-proposal-values.md),
[common ground](claude-common-ground.md), and the
[recommendation](claude-recommendation.md). Drafted by Claude, 2026-11-17,
from temperlang/temper `main` at `69f1a5b0` and tempest's working branch.
Paths are relative to each repository.

## Summary

Mike's 2026 work made `Result` the single internal fact about failure:
a call can fail exactly when its callee's return type is
`Result<Pass, Bubble>`, which is what `T throws Bubble` means. Results
are deliberately **second-class**. Temper code can't name, store, or
pass one, so every result is checked right at the call that produced it.
That keeps one IR serving two lowerings: Rust (and the experimental
`be-cppv`) get real result values, and Java, C#, JS, Python, Lua, and C++
get exceptions. This is "representation separate from semantics", but
with a narrower semantics than the values proposal. Failures are
values only between a call and the check that follows it.

## 1. Mike's commits (since June 2026)

| Commit | Date | What changed |
|---|---|---|
| `10e893c6`, merged as `d5e5a364` (#474) | 08-12, 09-11 | **Removes `hs` (handler scope)** as the failure primitive. "Failure is based on whether a callee has a declared *Result* return type." Rewrites *MakeResultsExplicit* and *Weaver* over block structure. *Typer* now strips `Bubble` from call results itself. 377 files changed |
| `c9a6e9c8`, `c941e0a2`, `d86198d8` | 08-14 | *MaximalPaths* and control-flow simplification find bubble edges from type information, and tell "sometimes bubbles" from "always bubbles" |
| `05d0a54b` | 08-24 | **Rebuilds TmpL translation of bubbly calls in result style**: `BubbleBranchStrategy.IfHandlerScopeVar`/`CatchBubble` become `Results`/`Exceptions`. Adds `AdjustForBubbles.kt`, `BubblyCall.kt`, `OrElseJumpLabels.kt`, and `ResultHelperFnPlaceholders.kt` |
| `f7d50912` | 08-31 | Records Typer confusion with `null` on the right of `orelse` (an `or-else-null` stage test) |
| `7b27eec4`, `ccb42d62`, `311fbe69`, `d84820ac`, `eb39f53e`, `7b0f972a` | 09-03 to 09-09 | Rust follow-ups: avoid re-wrapping results, use non-bubbly `assertAs` for safe casts, retype returned `Err`s, add `repack_err_result` |
| `9eb8509b` | 09-07 | **Each TmpL expression gets two types**: `passType` (what exception backends use) and `type` (the result type, for result backends) |
| `e9ff0d25` (#501) | 09-24 | Pseudo-code writes `T throws Bubble` instead of `T \| Bubble` |
| `50c23bc0` | 10-19 | Disables the `canBubble`/`doesBubble` check (a `// HACK` early return in `TypeChecker.checkFun`) until *Type2* can tell "returns `Bubble`" from "`Result<Never<…>, Bubble>`" |
| `d4fd96cd`, `26f6c1b9`, `67a7b3e9`, `ac5e2a1f`, `8548949c`, `7b8741fc` (#648) | 10-28 to 11-04 | Pull `Never`-typed calls into temporaries. In exception mode, assigning `panic()` becomes a `ThrowStatement`. Fixes for declared `Never` returns, plus a fix to stop pulling `error()` calls into temporaries |
| `3652110a` | 10-29 | `TmpLBackendTest` defaults to result mode |

The `Result` type, its `anyValueSuper = false`, and the TmpL grammar's
"results are not first class" all date from the public import
(`8591a63b`, 2025-12-26). The 2026 work made `Result` the only path,
removing the parallel `hs`/`fail#` machinery. Rust already used values,
through handler-scope flags.

## 2. The representation

- **Types.** `Result` is a well-known shape with a pass type and one or
  more failure types (`fundamentals/.../type/WellKnownTypes.kt`;
  `MkType2.result`). It isn't a subtype of `AnyValue`, and
  `TypeDisambiguateMacro.kt`'s `extendsAnyValueExempt` exempts it like
  `Void` and `Invalid`. So no type parameter can bind to it, and no
  variable can hold one. *Typer* applies `excludeBubble` to `return__N`
  locals ("cannot hold a Bubble because that is not a real value").
- **`bubble()` and `panic()`** (`value/NullaryNeverFn.kt`). `bubble`
  returns `Result<Never<T>, Bubble>`. `panic` returns `Never<T>` and has
  `callMayFailPerSe = false`.
- **`orelse`** is `ControlFlow.OrElse`: a labeled `orClause`, which a
  failure leaves by `break`, and an `elseClause`.
- **Lowering** (`be/.../tmpl/`). *GenerateCodeStage* hoists each
  bubbling call into a statement. `adjustForBubbles` then rewrites it to
  `let r = f(); if (!isOkResult(r)) { exit }` followed by
  `x = unpackOkResult(r)`. The exit is `break orelse#N` inside an
  `orelse`, `return repackErrResult(r)` in a function, or
  `ModuleInitFailed` at module level. `PreTranslated.Return` packs
  successes with `packOkResult`. In exception mode none of this happens:
  `orelse` becomes `TmpL.TryStatement`, and `bubble()` becomes
  `ThrowStatement` (`TmpLControlFlow.kt`, `TmpLTranslator.kt`).
- **Per backend** (each `*SupportNetwork.bubbleStrategy`). Each backend
  maps the four result helpers to `null` ("using Exceptions not
  Results") except Rust.

| Backend | Strategy | `bubble()` | `orelse` catches | `panic()` | Host sees |
|---|---|---|---|---|---|
| Java | Exceptions | `new RuntimeException()` (`Core.bubble`) | `RuntimeException` | same as bubble | unchecked exception, plain return type |
| C# | Exceptions | `throw new Exception()` | everything | same as bubble | exception |
| JS | Exceptions | runtime `bubble()` | everything | same as bubble | exception |
| Python | Exceptions | `RuntimeError()` | `Exception` | same as bubble | exception |
| Lua | Exceptions | `error(bubble_object)`, `pcall` | everything | same as bubble | error |
| C++ | Exceptions | `throw TemperBubble` | `TemperBubble` only | `std::terminate()` | exception |
| Rust | Results | `return Err(Error)` | `is_ok()` and labeled blocks | `panic!()` | `temper_core::Result<T>` |

Conversion happens **everywhere, not at a boundary**. Each internal call
uses the same form host code sees. C# and Lua still have `TODO()` for
`BubbleSentinel` and `ModuleInitFailed`, so moving them to results is not
free.

## 3. Mike's stated motivation

- `d5e5a364`: `hs` insertion before typing made "many non-failing
  operations" look fallible and needed costly *CleanupTemporaries*.
  Typing failure through `Result` fixes that.
- `tmpL.out-grammar`, `ResultType`: results "are not first class"
  so that "backends are not required to represent ad-hoc discriminated
  unions", and extra failure types must convert to the first.
- `9eb8509b`: "Exceptioning backends really only care about passing
  types … resulting backends need, at judicious places, access to
  result type info."
- [mike-thoughts.md](mike-thoughts.md) (2026-09-11): "Now that result
  types have settled". It argues for one failure type per function,
  "highly convertible" throwables, and against union `Result`s.
- No commit cites #163, #164, or a HackMD Result proposal. The only
  HackMD links in the tree are unrelated (`env/InterpMode.kt` and
  `lexer/TokenCluster.kt`).

## 4. Tom's question: did Mike deliberately keep results out of Temper code?

**Yes. The code says so directly, though the stated reason is broader
than exception backends.** Evidence:

- `Result` is excluded from `AnyValue`.
- The grammar comment quoted above.
- `excludeBubble` on return locals.
- `AdjustForBubbles`'s "non-first-class result value".
- The rule that bubbling calls are hoisted so none nest.

The grammar names ad-hoc unions as the reason. Nothing in the code or
commits says outright that this is to spare exception backends a result
type. But the `Exceptions` strategy only works because results are never
held: a result that never outlives its check is exactly a throw and a
catch. So Tom's reading matches the design's effect, though not the
reason it states.

**Cleaner where results stay at call sites:**

- One IR and one lowering give both strategies.
- Hosts get plain return types and exceptions with no runtime result
  class.
- Propagation is a local, mechanical rewrite that a type already
  justifies.

**Messier wherever failure meets abstraction.** That is where the
implementation's workarounds are:

- **Generics and function types.** A `T` can't carry a failure, so
  there is no failure polymorphism.
  - `TypeChecker.checkFun` has a TODO saying the compiler can't yet tell
    `fn <T>(f: fn (): T): T { f() }` apart from a version whose
    callback may fail.
  - Core's `forEach` takes its block as an `@inlineUnrealizedGoal`, so
    `bubble()` inside it propagates only because it is inlined.
  - std's `asInt64Safe` twin exists because an override can't drop
    `throws Bubble`.
  - Common-ground bug 10: a non-bubbling function passed as a bubbling
    `@fun interface` fails on Python.
- **Type-system special cases.**
  - `50c23bc0`'s HACK: the compiler can't tell "returns `Bubble`" from
    `Result<Never, Bubble>`.
  - `bubble()` and `panic()` need separate `Never<Void>` signatures.
  - `orelse null` confuses *Typer* (`f7d50912`).
  - TmpL needs two types per expression (`9eb8509b`), with a run of
    retyping fixes after it (`7b27eec4`, `eb39f53e`, `88088e65`
    "name a type's principal, not its Result wrapper").
- **Async and generators.**
  - `getPromiseResultSync` returns a hidden `Result<Y, Bubble>`.
  - `CoroutineConverter.kt` types a void bubble as
    `Result<Void, Boolean>`.
  - Generators split into `Generator` and `SafeGenerator`.
  - Bubbling `await` in `async`, and bubbling generators, are still
    common-ground bugs 8 and 9.
  - Each spot needs a special case, because a user can't hold the
    failure as a value.
- **User code.** Libraries that want a reason build their own result
  classes (Argmas's `ParseResult`, Hrefine's `UrlCheck`). Those don't
  work with `orelse`, so there are two failure worlds.

## 5. Relation to the proposals

**Values proposal.** Kotlin already has the internals the values
proposal assumes:

- a compiler-known `Result` type
- a branch-based lowering
- a per-call `passType`/`type` split, which is the hook for "each
  backend picks its representation"

The difference is first-classness. The values proposal lets a result
bind `T`, live in variables, and be returned. Needed changes:

- Drop `anyValueSuper = false`.
- Let *Typer* stop excluding results from locals.
- Teach `adjustForBubbles` that a call whose result is stored skips the
  check.
- Give exception backends a real result representation for held values.
  They can keep throw and try where a result is checked immediately,
  which is still the common case.
- Move host-facing conversion from "everywhere" to generated boundary
  forms.

That combination is the recommendation's design.

**Declared proposal.** Kotlin's current shape fits it more directly.
`ResultType` already allows several failure types, which Mike now wants
reduced to one. Needed changes:

- Per-library exception classes instead of bare `RuntimeException`,
  `Exception`, and `RuntimeError`.
- Typed catches instead of today's catch-alls.
- A failure object that `orelse`'s handler can bind. Today the lowering
  discards it: Java's catch variable is the ignored identifier.
- Message and cause.

**Both proposals** need the common-ground fix that `panic` stops
mapping to `bubble`: today `BuiltinOperatorId.Panic` shares bubble's
helper in the Java, C#, JS, Python, and Lua support networks.

**Lessons worth citing in the RFC:**

1. Typing failure through the return type removed whole IR passes
   (`d5e5a364`). Both proposals should keep failure in the type, not in
   control-flow markers.
2. Second-class results cost every later generic feature a special case
   (§4). If the RFC keeps results second-class (declared), it should
   say how failure crosses function types, generics, `await`, and
   generators. If it makes them first-class (values), most of those
   special cases go away.
3. Rust's result-mode output is cheap (`is_ok()`, `unwrap()`, and
   labeled blocks), but noisy (`.clone().clone()`, and
   `cast(panic!()).unwrap()` in `RustBackendTest.castGeneric`). In
   `TmpLControlFlow.translateRef`, a bare `panic()` statement takes the
   same `FreeFailure` path as `bubble()`. In result mode inside a
   bubbling function, that may return `Err` rather than panic, which
   is worth a test.
4. Stale comments mention the old strategy names (`RustTranslator.kt`:
   "Rust uses IfHandlerScopeVar, not CatchBubble").

## 6. Tempest today

Tempest has **no `Result` type in tmpl**:

- **Signatures.** Bubbling is a `bubbles: bool` on signatures and
  function types (`temper-tmpl/src/builder.rs`), written `throws Bubble`.
- **Call nodes.** A `MAY_BUBBLE` flag sits on call-like nodes and on
  `As` and `Await` (`nodes.rs`, `schema.rs`), shown as `^` in text.
- **`orelse`.** `OrElse` is an expression node. `Bubble` and `Panic`
  are separate nodes.
- **Strategy.** Each translator picks results or exceptions today. The
  profile's `Failure: Exceptions | Results` choice
  (`notes/tmpl/profiles.md`) has no pass yet.
- **Rust** uses `?`, `'ok`/`'orelse` labeled blocks, or a closure
  (`temper-be-rust/src/translate/nullables.rs`).
- **Exception backends** use `try`.
- **Panics are already kept apart from `orelse`** in Java
  (`AssertionError` outside `catch (RuntimeException)`), Python
  (`BaseException` outside `except Exception`), C# (`FailFast`), and
  C++ (catch `TemperBubble` only). JS keeps Kotlin's catch-all.

So tempest is closer to the declared proposal's model: an effect flag,
not a value. A values design would add a first-class result type to
tmpl's type table. It would also make the profile's `Failure` choice a
real lowering pass, rather than leave it to each translator.
