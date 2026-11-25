# Thoughts from MVS

No blockers from me.

## Open issues

Should it pay attention to https://editorconfig.org/ ?
Even if it's in an ancestor of the workroot?


Should it do long line wrapping?
If so, do we have a candidate line breaking algorithm?
Ben had a favourite Haskell auto-formatter algo which I could
dig up.


Re spacing, remember that the `<` token has some special whitespace
requirements related to less-than / bracket disambiguation during lexing.


I wonder if `temper fmt` early on could re-lex to check that it produces
no changes.


Should there be a `temper fmt --report-only` mode where it returns
a non-zero status code when the formatting would not be a no-op?
That would allow using it as a merge requirement for PRs.


Should it optionally take a flag for a diff and only touch the chunks
specified in the diff?  That might allow only retouching lines that
are changed by a PR?  Probably would also need to take a strip-prefix
num.  If we're removing or introducing brackets, for example around
single block lambda parameters, then we would need to reflect the fact
that one token change depends on another so that the corresponding
changes can be both included or not-included based on any filtering.
