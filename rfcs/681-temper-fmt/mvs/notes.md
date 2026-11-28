# Thoughts from MVS

No blockers from me.

## Open issues

Should it pay attention to https://editorconfig.org/ ?
Even if it's in an ancestor of the workroot?

tjp: The current direction is that it's not needed. We recognize line ends
automatically. We always use utf8, don't we? We don't configure line lengths
currently, and we have a standard indentation amount.


Should it do long line wrapping?
If so, do we have a candidate line breaking algorithm?
Ben had a favourite Haskell auto-formatter algo which I could
dig up.

tjp: Currently we don't, so that people can choose their lines in most cases.
Part of me *would* like this, and we'd want a default, but I also sort of like
not having to choose. I haven't looked up the thing Ben might have liked, but
from my own experience, I like how black wraps lines, if we went this direction.
We could also explore. And we don't want to change fmt rules after 1.0, but
maybe we could do the current plan for now, over nothing, and see if we want to
do further adjustments before 1.0 later. I think enforcing lengths can make
things more uniform and sometimes easier to read, and maybe if we do want to
enforce, doing this in advance might avoid violence against peoples' expected
long lines later. And we do wrap on lists already in some cases. (Separately, on
lists, I've wondered if we should be clever enough to recognize consistent
number of items per line for automatic table layout/alignment, but I'm unsure if
that's maybe too clever.) I asked Claude to review my replies, and it points out
that we did a census on this and found some churn on existing code. Maybe we
should put this one in as is and then make a separate effort on line length only
to see how we feel about that separately?


Re spacing, remember that the `<` token has some special whitespace
requirements related to less-than / bracket disambiguation during lexing.

tjp: I think this is already under consideration, but we can review to be sure.
Claude says yes handled that that there's already a golden on it. We can look
for that in review.


I wonder if `temper fmt` early on could re-lex to check that it produces
no changes.

tjp: This could be a safety check, yeah. If fast enough, maybe worth it. Claude
says this already done. And we during review, we can also check that it's in the
spec.


Should there be a `temper fmt --report-only` mode where it returns
a non-zero status code when the formatting would not be a no-op?
That would allow using it as a merge requirement for PRs.

tjp: If we don't have this already, I agree. Claude says this already exists as
`--check`. I just having a million things in my head, so I didn't remember for
sure, and I replied without reviewing anything.


Should it optionally take a flag for a diff and only touch the chunks
specified in the diff?  That might allow only retouching lines that
are changed by a PR?  Probably would also need to take a strip-prefix
num.  If we're removing or introducing brackets, for example around
single block lambda parameters, then we would need to reflect the fact
that one token change depends on another so that the corresponding
changes can be both included or not-included based on any filtering.

tjp: I'm having trouble thinking through the strip-prefix num. On diffs, my own
bias is to avoid this. If fmt is fast and also enforced early, I'd rather just
work whole files. And it still wouldn't be hard to test only full files in a
diff, say for gigantic monorepos in worlds where people usually only rebuild
subprojects, anyway. Claude agrees with me at the moment that we shouldn't worry
about this, but you might still have a different opinion.