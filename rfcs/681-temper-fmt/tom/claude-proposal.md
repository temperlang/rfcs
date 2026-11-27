(Based on the template for Golang's [design doc TEMPLATE.md](https://github.com/golang/proposal/blob/master/design/TEMPLATE.md), part of [Golang's change proposal process](https://github.com/golang/proposal/blob/master/README.md))

# Proposal: `temper fmt`

Author(s): Tom P., drafted with Claude Code (Claude Opus 5.5)

Last updated: 2026-11-26

Status: Draft

Discussion at https://github.com/temperlang/temper/issues/681.
Implemented in [#692](https://github.com/temperlang/temper/pull/692).
The user reference is `docs/tools/fmt.md` there; the rules below match it.

## Abstract

`temper fmt` lays out Temper code in one standard style:

- **No options and no line width.** It sets spacing and indentation and
  keeps the author's line breaks.
- **Lists are the exception:** the author picks their layout with two
  signals, a line break after the open bracket and a trailing comma.
- **Safe:** it never changes what code means, and checks that before
  writing anything.
- **Everywhere:** the command line, CI (`--check`), and the language
  server, on save by default in VS Code.

## Background

- A formatter with almost no options ends style debates, keeps diffs to
  real changes, and makes code by people and by AI look alike (`gofmt`,
  `rustfmt`, Black).
- Temper libraries are read by people from many languages, and the
  generated code in seven backends is already consistently laid out.
- Formatters come in two families:
  - **Width-driven** (Black, Prettier, rustfmt): break lines to fit a
    width. Lines churn when names change length, and the width needs
    exceptions (data tables, magic trailing commas, opt-outs).
  - **Layout-keeping** (`gofmt`): keep line breaks, fix spacing and
    indentation. Small diffs; long lines are the author's to fix.
- This proposal is layout-keeping, borrowing one idea from the other
  family: list layout chosen by the author's line break and trailing
  comma.

## Specification

Each rule names its golden cases in the compiler's
`crates/temper-syntax/tests/fmt/` (`rules`, `fmt`, `lines`, `lists`,
`comments`, `edges`), by file.

### Meaning

- **S1. Meaning never changes.** Tokens, comments, and the parse tree
  are the same after formatting, and formatting again changes nothing.
  If either would fail, the file is left as written and reported. Code
  that doesn't parse is left as written. *Tests:* `fmt.rs` (every
  repository file, mutated inputs, formatting twice).

### Spacing

- **S2. Spacing comes from the operator table.** One space around an
  infix operator, none after a prefix one, one inside `{ }` and none
  inside `( )` and `[ ]`; one after `,`, `;`, and a type or property
  `:`; none between a called name and `(`, except after `if`, `while`,
  `for`, `when`, `catch`, and `fn`. Other tokens keep their spacing, a
  run of spaces and tabs becoming one. *Tests:* `rules`, `fmt`.

```temper
let x:Int=f( a ,b )+1;          // before
let x: Int = f(a, b) + 1;       // after
if(ok){go()}                    // before
if (ok) { go() }                // after
let p = {x:1, y :2};            // before
let p = { x: 1, y: 2 };         // after
```

| Spacing | Operators |
|---|---|
| One space around, or inside | `=>`, `->`, `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `^=`, `\|=`, `&&=`, `\|\|=`, `<<=`, `>>=`, `>>>=`, `??`, `\|\|`, `&&`, `==`, `!=`, `===`, `!==`, `=~`, `!~`, `<`, `<=`, `>`, `>=`, `\|`, `^`, `&` (infix), `<<`, `>>`, `>>>`, `+` (infix), `-` (infix), `*` (infix), `/`, `%`, `~` (infix), `**`, `{ }`, `\{ }` |
| None around, after, or inside | `@`, `< >`, `++` (prefix), `--` (prefix), `+` (prefix), `-` (prefix), `!` (prefix), `~` (prefix), `&` (prefix), `*` (prefix), `...`, `.`, `?.`, `( )`, `[ ]`, `\`, `\( )`, `${ }` |
| None before, one after | `;`, `,`, `:` (type) |
| As written (a run becomes one space) | `;;;`, `;;`, `:` (marker), `given`, `return`, `throw`, `yield`, `of`, `:` (label), `case`, `orelse`, `extends`, `implements`, `forbids`, `supports`, `throws`, `in`, `instanceof`, `is`, `as`, `::`, `await`, `++` (postfix), `--` (postfix), `!` (postfix), `?`, `..`, `\u{ }`, `new` |

- **S3. Interpolation is tight:** `${name}`, with no space just inside
  `${ }`. Quasi-quotes space as their plain brackets. *Tests:* `fmt`.

```temper
"hi, ${ name }, ${ f({ a: 1 }) }"   // before
"hi, ${name}, ${f({ a: 1 })}"       // after
```

### Lines

- **S4. Line breaks are the author's,** except inside lists (S7). Blank
  lines stay, but at most one in a row, and none at the start of a file
  or at a code block's edges. *Tests:* `lines`, `fmt`, `rules`.
- **S5. Indentation:** two spaces per bracket level, and two for a line
  continuing its statement. A line that starts a statement, or one
  starting with `;`, `;;`, or `,`, doesn't continue. *Tests:* `fmt`,
  `lines`.

```temper
let ready = loaded &&
            checked;     // before
let ready = loaded &&
  checked;               // after
outer:
  for (;;) { f() }       // before
outer:
for (;;) { f() }         // after
```

- **S6. Four spaces** for a continued header (before a body's `{`) and
  inside parentheses whose contents start on the `(` line. The rule is
  structural: the same for every call with a trailing block. *Tests:*
  `lines`.

```temper
let parse(text: String): Int
throws Bubble {          // before
  0
}
let parse(text: String): Int
    throws Bubble {      // after
  0
}
if (ready &&
  checked) {             // before
  go();
}
if (ready &&
    checked) {           // after
  go();
}
if (
  ready &&
    checked              // after, with a break after `(`
) {
  go();
}
```

### Lists

- **S7. The author picks a list's layout** (arguments, parameters, list
  and object literals, type arguments, grouping parentheses, indices):

  | You write | Layout |
  |---|---|
  | no break after the open bracket | all on one line |
  | a break after the open bracket | items together on a line of their own |
  | a trailing comma | one item per line |

  `fmt` never adds or removes a comma. An item may span lines; the next
  starts where it ends. *Tests:* `lists`.

```temper
f(a,
  b);        // before
f(a, b);     // after

f(
  a,
  b
);           // before
f(
  a, b
);           // after

f(a, b,);    // before
f(
  a,
  b,
);           // after
```

### What stays as written

- **S8. Text:** comments' text, strings (including `\u{ }` runs), and
  prose in `.temper.md` files. Only trailing spaces go, and a file ends
  with one line break. *Tests:* `fmt`, `rules`, `comments`.
- **S9. Comments move with the code:** a comment on its own line indents
  like the code after it, its lines together; a doc comment's star
  gutter lines up one column past the `/`. *Tests:* `comments`.

```temper
    /**
  * Adds one.
     *   - wraps at the top
  */
let inc(n: Int): Int { n + 1 }
```

becomes

```temper
/**
 * Adds one.
 *   - wraps at the top
 */
let inc(n: Int): Int { n + 1 }
```

- **S10. `// fmt: off` … `// fmt: on`** keeps lines exactly as written.
  Without `// fmt: on`, the region ends where its enclosing brackets
  close, or at the end of the file or code block. *Tests:* `comments`,
  `rules`.

```temper
// fmt: off
let sizes = [
  "small",   1,
  "large", 100,
];
// fmt: on
```

### Tools

- **S11. The same everywhere:** `temper fmt [PATH]...` formats files and
  directories; `--check` changes nothing and exits 1 if anything needs
  formatting; the language server formats documents and ranges with the
  same code, and VS Code formats on save by default. *Tests:* LSP tests,
  VS Code suite.

## Implementation notes

Worked out while building it, on
[#692](https://github.com/temperlang/temper/pull/692).

- **Tokens laid out by the tree (S1, S2, S5–S7):** the formatter
  rewrites only the space between the parse's tokens, so comments and
  layout survive, and reads the parse tree for structure: which
  operators are infix, where lists, headers, and statements begin and
  end. It never reprints code from the tree. It runs in linear time on
  one file's parse, with no typing or imports, so format on save is
  instant.
- **Exceptions to the rules,** each forced by a case:
  - **S2:** about 30 tokens keep their spacing as written: word operators
    (`orelse`, `is`, `as`, `extends`, …), postfix operators, `new`, and
    others no rule settles yet. Space before `<` always stays, since it
    decides whether `<` is an angle bracket.
  - **S7:** a list keeps its line breaks when it has a comment between
    items, holds only literals (a data table), or holds a multi-quoted
    string.
  - **S9:** a comment stays where it is when moving it would cross the
    margin or mix tabs and spaces. A multi-quoted string's tab-indented
    lines stay too.
- **Line endings:** a CRLF file stays CRLF. A carriage return without a
  line feed is refused, since editors and Temper disagree on it.
- **Writing files:** each is written whole or not at all, to a new file
  beside it with its permissions, then swapped in. Hard-linked files, and
  directories that can't take a new file, are written in place. A
  read-only file is an error. One file's problem doesn't stop the rest.
- **What directories skip:** `temper.out`, `temper.keep`, hidden
  directories, what `.gitignore` and `.temperignore` list, and symbolic
  links, so a link can't make `fmt` write outside. `--ignorefile FILE`
  adds gitignore patterns; files named on the command line are formatted
  anyway.
- **Editors:** refusals are shown, except syntax errors, which
  diagnostics already show. Untrusted workspaces don't run the
  extension. Format on save is turned off with VS Code's own
  `editor.formatOnSave`.
- **The operator table** lives with the parser's operators, and the docs'
  table is rendered from it, so neither drifts.
- **Adoption:** the repository was formatted in one commit, with a CI
  check, an ignore file, and a script that formats the docs' examples.

## Rationale

- **No width:** a width churns lines when names change and needs
  exceptions. Kept line breaks mean diffs show only the author's changes.
  Cost: long lines stay until the author breaks them.
- **Author-chosen list layouts:** two signals people already use, so
  `fmt` makes habits consistent instead of imposing new ones. The
  trailing comma matches Black's magic trailing comma and rustfmt.
- **Four-space continuations** keep a continued header or condition
  apart from its two-space body.
- **Spacing in the operator table:** a new operator is spaced with no
  formatter change, and the docs' table can't drift.
- **Tight interpolation** matches the languages users come from.
- **Safety over completeness:** refuse rather than risk a wrong rewrite.
- **Speed:** linear time, one file's parse only (no typing or imports),
  so format-on-save is instant; std formats in tens of milliseconds,
  process start included.

**Measured impact:** over the compiler's repository and six libraries
(about 93,000 lines of Temper), under 1% of lines change. The largest
groups:

- lists one item per line without a trailing comma, which now hug;
- lists with a trailing comma and several items per line, which now go
  one per line;
- continuations in conditions and headers moving from two to four spaces.

**Alternatives considered:**

- **Width-driven layout** (Wadler/Prettier documents): tried with 100
  columns; it rewrote far more lines and had to respect semicolon
  insertion at every break.
- **Four spaces keyed on `if`, `while`, `for`:** those are ordinary calls
  in Temper; the structural rule is simpler.
- **Reprinting from the syntax tree:** loses comments and layout the
  tree doesn't keep.
- **Options** (indent, width): every option splits an ecosystem's style.

### Answers to review questions (Mike)

| Question | Answer |
|---|---|
| Honor `.editorconfig`, even in an ancestor? | No: there are no options for it to set. Line endings already follow the file. |
| Long-line wrapping? | No (see "No width"); a width-driven engine was tried and dropped. |
| `<` spacing and lexing? | Space before `<` always stays as written. |
| Re-lex to check for no changes? | Yes, and more: tokens, comments, and parse tree are compared before writing. |
| A mode that fails when formatting isn't a no-op? | `--check`, used in this repository's CI. |
| Format only a diff's changed lines? | Not on the command line. The language server formats ranges. Open issue below. |

## Compatibility

- No language rules or generated code change.
- Adopting it is one formatting commit per repository. The compiler's
  repository formats its Temper sources, docs' examples, and tests, and
  checks them in CI (`.git-blame-ignore-revs` can hide that commit from
  blame).
- Output may change between Temper versions as rules are refined, as
  with any formatter; `--check` in CI shows when.

## Testing

- **Golden tests** for every rule.
- **Safety properties checked independently of `fmt`'s own check:**
  tokens, comments, and parse tree unchanged, and formatting is
  idempotent, over every Temper file in the repository.
- **Fuzzing:** randomly mutated inputs, with a new seed nightly.
- **Speed:** a test that formatting time grows linearly.
- **Editor:** language-server formatting tests, and VS Code tests for
  format on save.

## Documentation

- `docs/tools/fmt.md`: the user reference (rules, examples, and the
  operator spacing table, rendered from the parser's and checked by a
  test).
- Editor docs and the VS Code README: format on save and how to turn it
  off.
- Release notes: not yet; #692 should add an entry.

## Open issues

- **The rules' exceptions** (Implementation notes), worth deciding before
  1.0, since changing formatter output later churns everyone's diffs:
  - the tokens whose spacing stays as written: which could get a rule;
  - lists of only literals keeping their line breaks: a heuristic, where
    `// fmt: off` already covers data tables;
  - comments that don't move: whether tab-indented ones could.
- **Formatting only changed lines** (Mike): a `--diff` mode for PRs.
  Needs care where one change implies another (adding brackets).
- **Markdown prose** in `.temper.md` stays as written; whether `fmt`
  should call a Markdown formatter is open.
- **Doc-comment framing** beyond lining up `*`s (one-line vs multi-line,
  adding or removing stars).
- **Generated reference docs:** examples should come from core's literate
  sources and be formatted there.
- **Spaces inside `\u{ }`** (as `\u{48, 69}`) would be a language change;
  parked.
- **Import ordering** isn't touched, since order could become significant.
