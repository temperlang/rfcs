# JavaScript

**Hand-written illustration, not generated or run.** The worked example
from [the README](README.md#the-example), as the JS backend might emit it,
with JSDoc types as today's output has. Today the parser throws `Error()`
with no message, the fallback `orelse` catches everything (panics
included), and the reason comes only from `selectProblem`.

## Failure types

```js
/** Base of every failure Wherewith reports. */
export class WherewithError extends Error {
  /** @param {string} message @param {{cause?: unknown}} [options] */
  constructor(message, options) {
    super(message, options);
    this.name = 'WherewithError';
  }
}

/** SQL text that Wherewith can't parse. */
export class SqlProblem extends WherewithError {
  /**
   * @param {string} text
   * @param {number} word
   * @param {string} [message]
   * @param {{cause?: unknown}} [options]
   */
  constructor(text, word, message = `${text} at word ${word}`, options) {
    super(message, options);
    this.name = 'SqlProblem';
    /** @readonly */ this.text = text;
    /** @readonly */ this.word = word;
  }
}
```

- **Library base or category:** one prototype chain, so `SqlProblem`
  extends `WherewithError` or a built-in category (`TypeError`,
  `RangeError`, or `SyntaxError`, which `JSON.parse` throws), not both.
  Shown: the library base.
- **`name`** is set as a string literal, so stacks and `String(e)` read
  `SqlProblem: expected a table at word 4` even after minification.
- **Message, cause, equality:** `message` and ES2022's `cause` option;
  equality is identity.
- **Stack trace:** V8 captures one when an `Error` is constructed, which
  is most of today's bubbling cost.

## Declared failures

```js
class Parser {
  /** @returns {Select} @throws {SqlProblem} */
  select() {
    this.#keyword('SELECT');
    const columns = [this.#name('a column')];
    while (this.#peek() === ',') {
      this.#pos += 1;
      columns.push(this.#name('a column'));
    }
    this.#keyword('FROM');
    const table = this.#name('a table');
    if (this.#peek() !== null) {
      throw this.#problem('expected the end');
    }
    return new Select(Object.freeze(columns), table);
  }

  /** @param {string} message @returns {string} */
  #need(message) {
    const w = this.#peek();
    if (w === null) throw this.#problem(message);
    return w;
  }

  /** @param {string} text */
  #problem(text) {
    const word = this.#pos + 1;
    return new SqlProblem(text, word, `${text} at word ${word}`);
  }
  // #keyword, #name, and #peek as in Temper
}

/**
 * @param {string} text
 * @returns {Select}
 * @throws {SqlProblem} if the text isn't a select Wherewith understands
 */
export function parseSelect(text) {
  return new Parser(text.split(' ')).select();
}
```

A Temper `orelse` becomes a `catch` that checks `e instanceof SqlProblem`
and rethrows anything else.

## Failures as values

The value form goes in the module hosts aren't pointed to (today's output
already has `wherewith.internal.js` beside `wherewith.js`). A result is
the plain value or a `Failed` object, checked with `instanceof`.

```js
// wherewith.internal.js: value forms, for other Temper libraries
import { Failed } from '@temperlang/core';   // internal; hosts never import it

class Parser {
  /** @returns {Select | Failed<SqlProblem>} */
  select() {
    const k = this.#keyword('SELECT');
    if (k instanceof Failed) return k;
    const first = this.#name('a column');
    if (first instanceof Failed) return first;
    const columns = [first];
    while (this.#peek() === ',') {
      this.#pos += 1;
      const more = this.#name('a column');
      if (more instanceof Failed) return more;
      columns.push(more);
    }
    // … FROM and the table the same way …
    if (this.#peek() !== null) return new Failed(new SqlProblem('expected the end', this.#pos + 1));
    return new Select(Object.freeze(columns), table);
  }
}

export function parseSelectValue(text) {
  return new Parser(text.split(' ')).select();
}
```

```js
// wherewith.js: the public API
/** @throws {SqlProblemError} */
export function parseSelect(text) {
  const r = parseSelectValue(text);
  if (r instanceof Failed) throw new SqlProblemError(r.error);
  return r;
}
```

**Which types can be failures (meeting point 6).** With any type allowed,
`SqlProblem` is a plain class (fields and `toString()`), and the
throwing form wraps it: `class SqlProblemError extends WherewithError`
with a `problem` property and the problem's text as `message`. A string
failure throws `WherewithError` with that message.

**Combined (the recommendation):** `SqlProblem` is the `Error` subclass
from [Failure types](#failure-types), and the value form carries it
unthrown. Constructing an `Error` captures a stack trace in V8, a cost
per failure that the values proposal otherwise avoids; the open choice
is to accept it, or to carry a plain object inside Temper and build the
`SqlProblem` at the boundary (which brings back two classes).

Alternative public value form: libraries like zod export `parse`
(throws) and `safeParse` (returns `{ success, data }` or
`{ success, error }`); a generated `safeParseSelect` would follow that
precedent, but isn't proposed by default.

## Host caller

```js
import { parseSelect, SqlProblem, WherewithError } from 'wherewith';

try {
  const select = parseSelect('SELECT a FROM');
} catch (e) {
  if (e instanceof SqlProblem) {            // pure values: SqlProblemError, e.problem.word
    console.error(`${e.message} (word ${e.word})`);
  } else if (e instanceof WherewithError) {
    // anything else from Wherewith
  } else {
    throw e;
  }
}
```

In TypeScript under `strict`, `e` is `unknown` until `instanceof`
narrows it; TypeScript has no way to declare what `parseSelect` throws
beyond the JSDoc `@throws`.
