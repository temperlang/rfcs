(Based on the template for Golang's [design doc TEMPLATE.md](https://github.com/golang/proposal/blob/master/design/TEMPLATE.md), part of [Golang's change proposal process](https://github.com/golang/proposal/blob/master/README.md))

# Proposal: `temper fmt`

Author(s): draft by Claude Code (Claude Opus 5.5), for Tom P. and the team

Last updated: 2026-11-24

Discussion at https://github.com/temperlang/temper/issues/681.

**This is a draft written by Claude for Tom and the team to react to,**
not a decision. It follows the [initial thoughts](claude-initial-thoughts.md)
in this folder and the choices Tom made while reviewing trial
reformats between 2026-11-20 and 2026-11-24. The Temper compiler's
`temper-fmt` branch implements all of it. The rules below are the same
as that branch's user page, `docs/tools/fmt.md`, which stays the
reference once merged; this proposal adds why, and what was left out.

## Abstract

`temper fmt` lays out Temper code in one standard style, from the
command line and from the language server, on save by default in VS
Code. It has no options and no line width: it sets spacing and
indentation and keeps the author's line breaks, except in bracketed
lists, whose layout the author picks with two signals: a line break
after the open bracket, and a trailing comma. It never changes what
code means, and checks that it didn't before writing anything.

## Background

A formatter with almost no options ends style debates for an
ecosystem, keeps diffs to what changed, and makes code written by
people and by AI look the same. Go's `gofmt`, Rust's `rustfmt`, and
Python's Black showed this. Temper has a particular reason to want it:
its libraries are read by people from many languages, and generated
code in seven backends already has a consistent layout, so the source
should too.

Formatters split into two families:

- **Width-driven** (Black, Prettier, rustfmt): pick line breaks to fit
  a width. Lines are rewritten whenever a name's length changes, and
  the width needs exceptions where it's wrong (data tables, "magic"
  trailing commas, opt-out comments).
- **Layout-keeping** (gofmt): keep the author's line breaks and fix
  spacing and indentation. Diffs stay small; long lines are the
  author's to fix.

This proposal is layout-keeping, with one idea borrowed from the other
family: in lists, the author's line break and trailing comma choose
among the three layouts people already write.

## Proposal

### Spacing

One space goes around operators, after commas, semicolons, and colons
in types and object literals, and inside `{ }`; none goes inside `( )`
and `[ ]`, or between a called name and `(`. Runs of spaces and tabs
become one.

```temper
let x:Int=f( a ,b )+1;          // before
let x: Int = f(a, b) + 1;       // after
if(ok){go()}                    // before
if (ok) { go() }                // after
let p = {x:1, y :2};            // before
let p = { x: 1, y: 2 };         // after
```

No space goes just inside a string's `${ }`, as in Kotlin, Python's
f-strings, and JavaScript's template literals; one over several lines
keeps its line breaks.

```temper
"hi, ${ name }, ${ f({ a: 1 }) }"   // before
"hi, ${name}, ${f({ a: 1 })}"       // after
```

### Indentation and continuations

Each bracket level indents two spaces.

```temper
if (ok) {
go();       // before
}
if (ok) {
  go();     // after
}
```

A line that continues a statement indents two spaces from the
statement's first line. One that starts a statement doesn't, as a
`{ x }` block on the line after a whole call `f(a)` does (the line break
ends the call, so the block isn't its argument), or the statement on the
line after a label (`outer:`). A line starting with `;`, `;;`, or `,`,
as after a multi-quoted string, lines up with the statement or item it
ends, as a close bracket lines up with its open bracket's line.

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

Two kinds of continuation line indent four spaces instead, to stand
apart from what follows:

- In a header (a class's, interface's, function's, or function
  literal's, before the `{` of its body), from the line the header
  starts on. A comma between supertypes (`extends A,` then `B` on the
  next line) continues the header too.
- In parentheses whose contents start on the `(` line, as a
  condition's do, from that line. With a line break right after the
  `(`, the contents start a line of their own, and their continuations
  indent two from it, as above.

Brackets opened on such a line indent their contents from it, but a
header's body indents from the header's first line.

```temper
let parse(text: String): Int
throws Bubble {          // before
  0
}
let parse(text: String): Int
    throws Bubble {      // after
  0
}
run(fn (x: Int): Int
    throws Bubble {      // after, in brackets too
  x
});
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

The parenthesis rule is structural, not keyed on `if` or `while`:
control flow in Temper is ordinary calls with trailing blocks, so the
rule applies to every call alike.

### Blank lines

Blank lines stay as you wrote them, but never more than one in a row
(at a `.temper.md` code block's start and end too), and none at the
start of a file. Trailing spaces go, after comments too, and a file
ends with one line break, unless it has nothing but space: then it's
empty. A file's line breaks stay its own: in a file
with CRLF line breaks, the ones `fmt` adds are CRLF too.

```temper
let a = 1;


let b = 2;   // before: two blank lines

let a = 1;

let b = 2;   // after: one
```

### Lists

Lists are arguments, parameters, list and object literals, and type
arguments. Grouping parentheses, as in `(a + b)`, are lists too, of one
item, as is an index in brackets, as in `items[i]`. Your line breaks and trailing comma choose their layout:

- No line break after the open bracket: all on one line.
- A line break after the open bracket: the items together on one line
  of their own.
- A trailing comma: one item per line.

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

`fmt` never adds or removes a comma, so to put a list back on one line,
delete its trailing comma. An item may span lines; the next item starts
on the line it ends.

```temper
foo(fn {
  body();
},
  b);        // before
foo(fn {
  body();
}, b);       // after
```

A list with a comment between items, only literals (a table of data), or
a multi-quoted string as an item keeps its line breaks.

### What it never changes

- Line breaks outside lists.
- Comments' text, apart from trailing spaces. A comment on its own line
  indents like the code around it, its lines moving together, unless
  that would take one left of the margin, or one of its lines is
  indented with tabs (moving would mix tabs and spaces): then it stays
  where it is. A doc comment over several lines, `/** ... */`, with a
  star gutter (every line after the first that isn't blank starts with
  `*`, the closing `*/` too) has its `*` lines one column past the `/`,
  with what follows each `*` as written. In one without a gutter, lines
  starting with `*`, such as bullets, move with the rest.
- Strings. A multi-quoted string's lines move with the line it starts
  on, but lines indented with tabs stay as written.
- Prose in `.temper.md` files: only Temper code blocks change.

### Turning it off

Lines between a `// fmt: off` and a `// fmt: on`, each a comment on a
line of its own, stay exactly as written, as for a table aligned in
columns; the two comments indent like any other. Without a `// fmt: on`,
the region ends where the brackets around it close (the end of its
block), or at the end of the file or, in `.temper.md`, of its code
block. Only those exact comments count: `//fmt: off` and
`/* fmt: off */` don't, and a `// fmt: on` with no region to end is an
ordinary comment.

```temper
// fmt: off
let sizes = [
  "small",   1,
  "large", 100,
];
// fmt: on
```

This is Black's and ruff's spelling with Temper's comment.

### What it refuses

Code that doesn't parse is left as written, with an error, as is a
file with a carriage return not followed by a line feed (a line break to
some editors but not to Temper; `fmt` takes `\n` and `\r\n`). `fmt`
also checks its own work: if formatting would change a file's tokens,
comments, or parse tree, it leaves the file alone and says so. A bug
that stops formatting a file costs only that file: `fmt` reports it and
goes on.

Each file is written whole or not at all: the formatted text goes to a
new file beside it, with its permissions, which then replaces it. A
file with other hard links is written in place instead, so they all
see the change, as is one in a directory where no file can be added. A
read-only file is an error.

### What it leaves out

Under a directory, `fmt` skips `temper.out`, `temper.keep`, hidden
directories, and what `.gitignore` and `.temperignore` files list, as
`build` does. It skips symbolic links too, to files as to directories,
so a link in a checkout can't make it write outside; a link named on
the command line formats the file it links to.

To keep more as written, such as a golden test's input or code that
doesn't parse on purpose, list it in a file of gitignore patterns and
name it with `--ignorefile`. A directory named that it lists is skipped
too (but not its own directory, where its patterns start); a file named
on the command line is formatted all the same. For a check in CI, with
this `.fmtignore`:

```gitignore
# Golden inputs, kept as written
tests/inputs/
# Code that doesn't parse, on purpose
/examples/errors.temper.md
```

```sh
temper fmt --check --ignorefile .fmtignore
```

### Tools

- **`temper fmt [--check] [--ignorefile FILE] [PATH]...`** formats the
  files named, or under the directories named (the current one by
  default), skipping what `build` skips and symbolic links, as above,
  and rewriting only files that change, each whole or not at all.
  `--check` changes nothing, lists the files that need formatting, and
  exits with 1 if any do, for CI.
- **The language server** formats with the same code, a whole document
  or the lines of a range, so the editor and the command never
  disagree. The VS Code extension formats on save by default; to turn
  that off, set the standard `editor.formatOnSave` to `false` for
  `[temper]` (and `[temper-markdown]`, for `.temper.md` files). In
  Restricted Mode, for a workspace you haven't trusted, the extension
  doesn't run, so neither does formatting.
- **When it refuses a file** in an editor, it leaves it as written and
  says why, except for code that doesn't parse, whose syntax error
  already shows as a diagnostic: saving mid-edit shouldn't pop up a
  message the squiggle already gives.

## Rationale

- **No width.** A width rewrites lines whenever names change length,
  and needs exceptions where it's wrong. Keeping line breaks means a
  formatted file's diff shows only what the author changed. The cost:
  long lines stay long until the author breaks them, which is the
  author's call.
- **The author picks list layouts,** with two signals people already
  use (a break after the bracket, a trailing comma), so `fmt` makes
  existing habits consistent instead of imposing new ones. A trailing
  comma's "one per line" meaning matches Black's magic trailing comma
  and rustfmt's handling.
- **Four-space continuations in headers and conditions** keep a
  continued signature or condition visually apart from the body that
  follows at two spaces. Making the parenthesis rule structural keeps
  it to one sentence and treats user functions with trailing blocks
  like built-in control flow.
- **Tight interpolation** (`${x}`) matches the languages Temper users
  come from.
- **Safety over completeness.** `fmt` compares tokens, comments, and
  the parse tree before writing, and refuses rather than risk a wrong
  rewrite. Tests check the same properties independently of `fmt`'s
  own check, over every Temper file in the repository and over
  randomly mutated inputs, with a new random seed nightly.
- **Speed.** Formatting runs in time linear in the input and works from
  one file's parse alone, with no typing or imports, so formatting on
  save is instant: the standard library's files format in tens of
  milliseconds, process start included.

### Measured impact

Over the compiler's repository and six libraries (about 93,000 lines
of Temper), adopting these rules changes under 1% of lines. The biggest
groups: lists written one item per line without a trailing comma, which
now hug; lists with a trailing comma written several items per line,
which now go one per line; and continuation lines in conditions and
headers moving from two spaces to four.

### Alternatives considered

- **A width-driven layout engine** (Wadler/Prettier-style documents).
  Tried in an early version with a 100-column width; dropped for the
  author's choices, since it rewrote far more lines and would have to
  respect semicolon insertion at every break.
- **Keying four-space continuations on `if`, `while`, and `for`.**
  Dropped: those are ordinary calls in Temper, so a structural rule
  is simpler and consistent.
- **Reprinting from the syntax tree.** Loses comments and layout the
  tree doesn't keep; working on the parse's tokens avoids that.
- **Options** (indent width, line width). None: every option splits an
  ecosystem's style.

## Compatibility

`fmt` changes no language rules and no generated code. Adopting it is a
one-time formatting commit per repository; the compiler's repository
formats its Temper sources, docs' examples, and tests, and checks them
in CI. Libraries can opt in the same way. Formatter output may change
between Temper versions as rules are refined, as with every formatter;
`--check` in CI shows when.

## Implementation

On the compiler's `temper-fmt` branch: the formatter in the syntax
crate, the `fmt` command, language-server formatting with on-save in
VS Code, a CI check over the repository with an ignore file, a script
that formats the docs' Temper examples, golden tests for every rule,
and the safety and fuzz tests described above.

## Open issues

- **Markdown prose** in `.temper.md` files is left exactly as written.
  Formatting it (rewrapping, list markers, emphasis) is a Markdown
  formatter's job; whether `fmt` should call one is left out of this
  proposal.
- **Doc-comment framing** beyond lining up the `*` column (one-line
  versus multi-line form, adding or removing stars) is left out.
- **Generated reference docs.** Examples in the docs' reference pages
  should come from core's literate sources and be formatted there, with
  `// fmt: off` where hand alignment matters, rather than formatted as
  copies.
- **Import ordering** isn't touched, since a later change could make
  order significant.
