[Team discussion on naming things that panic or throw or whatever](https://hackmd.io/j2jOtO0qRBa83DZYmUyQPQ),
last updated on 2026/10/06. Most of this is Mike, but some is Tom or Shaw. And
it happens to miss the `tryWhatever` idea, which seems like a good option.


# Kinds of unsafety

The words "safe" and "unsafe" are vague.  As discussed on Discord, might be worth brainstorming for short terms that capture what we really mean so our documentation and APIs can communicate precise, usable information to Temper users.


## Some kinds

**Security issue**: incorrect use can lead to a security or privacy problems for end user(s).

**Secure foundation**: the item is safe in that it is a building block for code that does not suffer some class of security issues.

**Can bubble**: incorrect use can lead to a recoverable runtime failure, branching to an `orelse`'s right'.

**Can panic**: incorrect use can lead to an unrecoverable panic which might take down the larger program.

**Semantic ambiguity**: edge cases might lead to variant semantics on different backends.

## When to add an affix

If an affix disambiguates, include it: *OrNull* vs *OrEmpty* disambiguates.

If there is a safe alternative that is preferred, use a negative affix on the unsafe, occasional API.

Otherwise, don't add affixes to APIs you want/expect people to use.

## Synonyms & Antonyms

Brainstorming some synonyms for the kinds above, and negations like "cannot bubble":

### Security Issue / Foundation

- insecure

Antonyms

- secure
- trustworthy
- reliable

### Can Bubble

- checked
- or\<Alternative\>

Antonyms

- not bubbly
- not throwing
- sure (like you surely get a thing, even if nullable)
- definite (like you definitely get a thing, even if nullable)
- returns (something will be returtned, even if nullable)

### Can Panic

- unchecked
- panics
- crashing

### Semantic Ambiguity

- under-defined behaviour
- approximate
- ambiguous

### Contract enforcement is the responsibility of the caller

There's some documented or implicit contract that needs to hold.
That's not computationally checked.
Using this API in only in ways that leave that contract upheld is the responsibility of the caller.

- unchecked (ambiguous with panic?)
- unenforced
- risky

Antonyms

- checked
- enforced

For example, if there are safe APIs for specify an HttpResponse body by passing in a *SafeHtml* value then any API that allows passing in a raw string of HTML and a content-type header involves a contract that the HTML is safe to render in a browser, and the caller is responsible for ensuring that appropriate steps have been taken to avoid XSS, XSRF, and other security issues specific to the web platform.

## Affixes

Brainstorming how those synonyms can lead to affixes for method names.  Instead of just the "Safe-" prefix, maybe more precise prefixes and/or suffixes.

In bound are suffixes like -OrNull that specify precise behaviour instead of, for example bubbling or panicking.

- -NoThrow
- -Sure
- -Total

### Antonym affixes

If we label the "unsafe" things instead, we might get other affixes.

- -Maybe (like maybe you get a return value, except "maybe" typically aligns more with optionals in the nullable sense)
- -OrBubble
- -OrThrow
- -Throwing
- -Unsure
- -Partial
