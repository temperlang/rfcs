# temper fmt: initial thoughts

By Claude Code (Claude Opus 5.5), 2026-11-20, for
[#681](https://github.com/temperlang/temper/issues/681). Suggestions
only; nothing here is decided.

## Why

One canonical layout for Temper source, applied by a tool, so code
review is about meaning, diffs stay small, and code written by people
and by AI looks the same. Go's `gofmt`, Rust's `rustfmt`, and Python's
Black show that a formatter with almost no options ends style debates
for a whole ecosystem.

## Shape

- **`temper fmt [paths]`** rewrites files in place; **`temper fmt
  --check`** changes nothing and exits nonzero, listing files that would
  change, for CI. Formatting is per invocation, so these flags fit the
  rule that command-line options are for ephemeral choices.
- **Language server:** document formatting through the same code, so
  editors and the command never disagree, **on by default on save** in
  the VS Code extension (users can turn it off). That sets a speed
  budget: formatting a typical file well under the time a save feels
  instant (tens of milliseconds), so it works from the syntax tree of
  the one file alone, with no typing, imports, or other files, and the
  language server reuses the parse it already keeps for the open
  document. A benchmark on the largest files in the standard library
  guards the budget.
- **Few or no options.** Line width, if anything. Every option splits
  the ecosystem's style; a project that wants something else can skip
  the tool.

## What it formats

- **Literate files:** in `.temper.md`, only the Temper code blocks change.
  Prose, headings, inert examples, and log blocks are left as written
  (a Markdown formatter is a separate tool). Indentation of the code
  blocks themselves stays as Markdown needs it.
- **Config files** (`config.temper.md`) like any other Temper.
- **Doc comments:** keep their text; maybe normalize the `/** … */`
  framing, never rewrap prose by default.

## Rules to settle

Start from the style the compiler's own libraries and docs already use,
so the first run changes as little as possible:

- indentation width and continuation indents;
- where line breaks go in long calls, argument lists, object literals,
  type parameter lists, and chains of method calls or operators;
- trailing commas in multi-line lists;
- blank lines: preserve single blank lines between statements, collapse
  runs, normalize around declarations;
- spacing around operators, colons in type annotations, and `=>`/`->`;
- trailing blocks (`f(x) { … }`) and `fn` literals;
- string literals are never changed (multi-quoted strings, escapes);
- import ordering: probably out of scope at first, since moving imports
  can change meaning if a later RFC makes order significant.

## Correctness

- **Never change meaning.** The parsed tree before and after formatting
  must be the same, apart from layout; the tool checks this itself and
  refuses to write if they differ (rustfmt and Black do similar checks).
- **Idempotent:** formatting formatted code changes nothing; a test runs
  every formatted file twice.
- **Comments are never lost or moved across code they belong to.** This
  is the hard part of every formatter; it needs a parse that keeps every
  token and comment (a lossless syntax tree), which the compiler's
  parser is close to already.
- **Code that doesn't parse** is left alone, with an error, rather than
  partly formatted.
- Tests: the compiler's own test programs, the standard library, and
  the docs' examples, formatted and checked for an unchanged tree and
  idempotence.

## Rollout

- Format the standard library and docs in one commit of its own, so
  history stays readable (and list that commit in a
  `.git-blame-ignore-revs` file).
- CI runs `temper fmt --check` on the compiler's Temper sources;
  libraries can opt in.
- Generated code isn't affected: backends lay out their own output.

## Related

- [#679](https://github.com/temperlang/temper/issues/679): library
  config, which `fmt` should handle like any Temper.
- [#677](https://github.com/temperlang/temper/issues/677): temper.keep;
  its recorded API files could use the same canonical layout, so diffs
  stay stable.
