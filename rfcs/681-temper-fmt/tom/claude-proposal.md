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

## Proposal

### Spacing

- **One space** around operators, after `,` `;` and type or property
  `:`, and inside `{ }`.
- **No space** inside `( )` and `[ ]`, or between a called name and `(`.
- **Except** after `if`, `while`, `for`, `when`, `catch`, and `fn`,
  which take one: `if (ok)`, but `f(ok)`.
- Runs of spaces and tabs become one.

```temper
let x:Int=f( a ,b )+1;          // before
let x: Int = f(a, b) + 1;       // after
if(ok){go()}                    // before
if (ok) { go() }                // after
let p = {x:1, y :2};            // before
let p = { x: 1, y: 2 };         // after
```

- **Each operator's spacing lives in the parser's operator table,** next
  to the operator:

  | Spacing | Operators |
  |---|---|
  | One space around, or inside | `=>`, `->`, `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `^=`, `\|=`, `&&=`, `\|\|=`, `<<=`, `>>=`, `>>>=`, `??`, `\|\|`, `&&`, `==`, `!=`, `===`, `!==`, `=~`, `!~`, `<`, `<=`, `>`, `>=`, `\|`, `^`, `&` (infix), `<<`, `>>`, `>>>`, `+` (infix), `-` (infix), `*` (infix), `/`, `%`, `~` (infix), `**`, `{ }`, `\{ }` |
  | None around, after, or inside | `@`, `< >`, `++` (prefix), `--` (prefix), `+` (prefix), `-` (prefix), `!` (prefix), `~` (prefix), `&` (prefix), `*` (prefix), `...`, `.`, `?.`, `( )`, `[ ]`, `\`, `\( )`, `${ }` |
  | None before, one after | `;`, `,`, `:` (type) |
  | As written (a run becomes one space) | `;;;`, `;;`, `:` (marker), `given`, `return`, `throw`, `yield`, `of`, `:` (label), `case`, `orelse`, `extends`, `implements`, `forbids`, `supports`, `throws`, `in`, `instanceof`, `is`, `as`, `::`, `await`, `++` (postfix), `--` (postfix), `!` (postfix), `?`, `..`, `\u{ }`, `new` |

- Followers space as themselves (the `,` in `extends A, B`); an object
  literal's `:` spaces as a type's.
- **Space before `<` stays as written,** since it decides whether `<` is
  an angle bracket.
- **Interpolation is tight:** `${name}`, as in Kotlin, Python f-strings,
  and JavaScript. One spanning lines keeps its line breaks.
- **Quasi-quotes** space and lay out as their plain brackets do:
  `\(a + b)`, `\{ f(x) }`.
- **`\u{ }` in a string stays exactly as written:** it's string text, and
  a space there would be an error.

```temper
"hi, ${ name }, ${ f({ a: 1 }) }"   // before
"hi, ${name}, ${f({ a: 1 })}"       // after
```

### Indentation

- **Each bracket level indents two spaces.**
- **A continuation line indents two** from its statement's first line.
- **A line that starts a statement doesn't:** a `{ x }` block after a
  whole call `f(a)` (the line break ends the call), or a statement after
  a label (`outer:`).
- **A line starting with `;`, `;;`, or `,`** lines up with what it ends,
  as a close bracket lines up with its open bracket's line.

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

- **Four spaces** for two kinds of continuation, to stand apart from the
  body that follows:
  - **Headers** (class, interface, function, function literal, before
    the body's `{`), from the header's first line, including a comma
    between supertypes.
  - **Parentheses whose contents start on the `(` line,** as a
    condition's do. With a break right after `(`, contents start their
    own line and continue at two.
- Brackets opened on such a line indent from it; a header's body indents
  from the header's first line.
- **Structural, not keyed on `if` or `while`:** control flow is ordinary
  calls with trailing blocks in Temper, so the rule applies to every call.

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

### Blank lines and line endings

- Blank lines stay, but never more than one in a row, and none at a
  file's start (or a `.temper.md` code block's start and end).
- Trailing spaces go, after comments too.
- A file ends with one line break; a file of only space becomes empty.
- Line endings stay the file's own: in a CRLF file, added breaks are CRLF.

### Lists

- **Lists:** arguments, parameters, list and object literals, type
  arguments, grouping parentheses `(a + b)`, and indices `items[i]`.
- **The author's signals choose the layout:**

  | You write | Layout |
  |---|---|
  | no break after the open bracket | all on one line |
  | a break after the open bracket | items together on a line of their own |
  | a trailing comma | one item per line |

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

- **`fmt` never adds or removes a comma:** to rejoin a list, delete its
  trailing comma.
- **An item may span lines;** the next item starts where it ends.
- **Kept as written:** a list with a comment between items, a list of
  only literals (a data table), or one holding a multi-quoted string.

### What it never changes

- Line breaks outside lists.
- **Comments' text**, apart from trailing spaces.
  - A comment on its own line indents like the code around it, its lines
    moving together, unless that would cross the margin or one of its
    lines is tab-indented.
  - A `/** … */` with a star gutter has its `*`s one column past the `/`;
    without a gutter, `*` bullets move with the rest.
- **Strings.** A multi-quoted string's lines move with its first line,
  except tab-indented lines.
- **Prose in `.temper.md`:** only Temper code blocks change.

### Turning it off

- `// fmt: off` … `// fmt: on`, each on its own line, keeps everything
  between exactly as written (Black's and ruff's spelling).
- Without `// fmt: on`, the region ends where its enclosing brackets
  close, or at the end of the file or code block.
- Only those exact comments count (`//fmt: off` and `/* fmt: off */`
  don't); a stray `// fmt: on` is an ordinary comment.

```temper
// fmt: off
let sizes = [
  "small",   1,
  "large", 100,
];
// fmt: on
```

### Safety

- **Refuses, leaving the file as written:**
  - code that doesn't parse (with its error);
  - a carriage return without a line feed;
  - any result whose tokens, comments, or parse tree would differ.
- **One file's problem doesn't stop the rest:** it's reported, and
  formatting goes on.
- **Whole or nothing:** each file is written to a new file beside it,
  with its permissions, then swapped in. Hard-linked files, and files in
  directories that can't take a new file, are written in place. A
  read-only file is an error.

### What it skips

- Under a directory: `temper.out`, `temper.keep`, hidden directories, and
  what `.gitignore` and `.temperignore` list, as `build` does.
- **Symbolic links,** so a link can't make it write outside the tree; a
  link named on the command line formats its target.
- **`--ignorefile FILE`:** gitignore patterns for more to keep as written
  (golden inputs, code that fails to parse on purpose). Files named on
  the command line are formatted anyway.

```sh
temper fmt --check --ignorefile .fmtignore
```

### Tools

- **`temper fmt [--check] [--ignorefile FILE] [PATH]...`**
  - Formats the files named, or under the directories named (default:
    the current one).
  - Rewrites only files that change.
  - `--check` changes nothing, lists files needing formatting, and exits
    1 if any do (for CI).
- **Language server:** the same code formats a whole document or a range,
  so editor and command never disagree.
- **VS Code:** formats on save by default. Turn it off with
  `editor.formatOnSave: false` for `[temper]` and `[temper-markdown]`.
  Untrusted (Restricted Mode) workspaces don't run the extension.
- **Refusals in the editor** are shown, except a syntax error, which
  the diagnostics already show.

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

## Implementation

Done on [#692](https://github.com/temperlang/temper/pull/692):

- The formatter in the syntax crate, working on the parse's tokens.
- `temper fmt` with `--check` and `--ignorefile`.
- Language-server document and range formatting; format on save in VS
  Code.
- The repository formatted, with a CI check and an ignore file.
- A script that formats the docs' Temper examples.

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
