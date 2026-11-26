# Docs follow-ups from core cleanup

By Claude Code (Claude Opus 5.5), 2026-11-26, for
[#689](https://github.com/temperlang/temper/issues/689). Notes for the
proposal: what core cleanup
([#688](https://github.com/temperlang/temper/pull/688), RFC 671) already
did for docs, and what it left for this proposal. Suggestions only.

## Already done in #688

- **Core is literate Markdown,** a file per topic, the source for every
  builtin's docs.
- **The prose doc rule:** a declaration's doc runs from the first
  top-level paragraph naming it to the declaration, keeping paragraphs,
  lists, block quotes, example code, and link definitions. A `/** … */`
  before a declaration takes precedence.
- **Builtins have declarations:** values, functions, and macros (`true`,
  `if`, `orelse`, …) get bodiless `@connected` declarations, so hover,
  signature help, and REPL `help(…)` work by declaration, with no
  snippet ids.
- **Examples are checked in CI:** core's, std's, and `docs/` examples run
  as marked. `temper inert` blocks are checked when marked ✅ or ❌.
- **Known exceptions:** 18 after #688 (10 I10, 3 I20, 4 I23, 1 I25 in
  `docs/inconsistencies.md`), so the proposal's "fourteen" is stale.

## Left for this proposal

| Section here | Follow-up |
|---|---|
| Declaration fragments | **One doc pipeline.** `/** */` comments and prose docs reach analysis by different paths (`comment_doc` and `core_comment_doc` beside `DocString`), with special cases for core. One doc model for both, from any library, before analysis. |
| Declaration fragments | **A convention:** prose for top-level declarations, `/** */` for members. Unwritten today, and core mixes the two in places. |
| Checked examples | **An `example` fence** (or another marker), so `temper inert` stops meaning both "not part of this file" and "a checked example". |
| Checked examples | **Match real diagnostics only:** the checker fails a ✅ block whose output contains " error" anywhere. Moving the checker into `temper` fixes this naturally. |
| Fragment markers, fragment links | **`⎀` insertions and `[snippet/…]` links** show as raw text today (hover strips them, nothing else does). Fragments replace them. |
| Materialized inclusions, the site publisher | **`builtins.md` and `types.md` are hand-kept copies** of what core's files now say. Generate them from core, or retire them. |
| REPL help by fragment name | Builtins already resolve by declaration; fragment names could reuse declaration paths rather than a second id scheme. |

## Not planned for #688

None of the above blocks #688. It deliberately stops at the prose rule
and checked examples, so that this proposal can design the pipeline
once.
