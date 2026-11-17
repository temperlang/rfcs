# Python

**Hand-written illustration, not generated or run.** The worked example
from [the README](README.md#the-example), as the Python backend might
emit it. Today the parser raises a bare `RuntimeError()`, and the reason
comes only from `select_problem`.

## Failure types

```python
# wherewith/_errors.py, re-exported from wherewith/__init__.py

class WherewithError(Exception):
    """Base of every failure Wherewith reports."""


class SqlProblem(WherewithError, ValueError):
    """SQL text that Wherewith can't parse."""

    def __init__(self, text: str, word: int, message: str | None = None) -> None:
        super().__init__(message if message is not None else f'{text} at word {word}')
        self.text = text
        self.word = word
```

- **Library base and category at once:** Python has multiple inheritance,
  so `SqlProblem` is both a `WherewithError` and a `ValueError` (from the
  failure's "invalid argument" category), as requests' `InvalidURL` is
  both a `RequestException` and a `ValueError`.
- **Message:** `str(e)` gives `expected a table at word 4`. Equality is
  identity, as for every Python exception.
- **Cause:** set as `__cause__`, so tracebacks show "The above exception
  was the direct cause of …".
- Pickling would need a generated `__reduce__`, since `args` holds only
  the message.

## Declared failures

Exceptions all the way through: propagation is Python's own, so the
generated rule has no markers, and a Temper `orelse` becomes
`try`/`except SqlProblem` (only the declared type, never `Exception`).

```python
class _Parser:
    def select(self) -> Select:
        self._keyword('SELECT')
        columns = [self._name('a column')]
        while self._peek() == ',':
            self._pos += 1
            columns.append(self._name('a column'))
        self._keyword('FROM')
        table = self._name('a table')
        if self._peek() is not None:
            raise self._problem('expected the end')
        return Select(tuple(columns), table)

    def _need(self, message: str) -> str:
        w = self._peek()
        if w is None:
            raise self._problem(message)
        return w

    def _problem(self, text: str) -> SqlProblem:
        word = self._pos + 1
        return SqlProblem(text, word, f'{text} at word {word}')


def parse_select(text: str) -> Select:
    """Parses `SELECT a, b FROM t`.

    Raises:
        SqlProblem: if the text isn't a select Wherewith understands.
    """
    return _Parser(text.split(' ')).select()
```

## Failures as values

Inside Temper, a result is the plain value or a `Failed` box (the cheapest
form [measured](../claude-explore/README.md#a-compiler-known-result-type-likely-cost)),
checked with `type(r) is Failed`. The value form lives in a private
submodule that other Temper libraries call; hosts get the raising form.

```python
# wherewith/_temper/parsing.py: value forms, for other Temper libraries
from temper_core import Failed   # internal; never in what hosts import


class _Parser:
    def select(self) -> 'Select | Failed[SqlProblem]':
        r = self._keyword('SELECT')
        if type(r) is Failed:
            return r
        first = self._name('a column')
        if type(first) is Failed:
            return first
        columns = [first]
        while self._peek() == ',':
            self._pos += 1
            more = self._name('a column')
            if type(more) is Failed:
                return more
            columns.append(more)
        # … FROM and the table the same way …
        if self._peek() is not None:
            return self._problem('expected the end')
        return Select(tuple(columns), table)

    def _problem(self, text: str) -> 'Failed[SqlProblem]':
        return Failed(SqlProblem(text, self._pos + 1))


def parse_select(text: str) -> 'Select | Failed[SqlProblem]':
    return _Parser(text.split(' ')).select()
```

```python
# wherewith/parsing.py: the raising form, the public API
from . import _temper


def parse_select(text: str) -> Select:
    """… Raises: SqlProblemError …"""
    r = _temper.parsing.parse_select(text)
    if type(r) is Failed:
        raise SqlProblemError(r.error) from None
    return r
```

**Which types can be failures (meeting point 6).** The values proposal
lets a result carry any type, so `SqlProblem` is an ordinary class (with
`text`, `word`, and a `__str__` from its Temper `toString()`), and the
raising form needs a separate exception that holds it:

```python
class SqlProblemError(WherewithError, ValueError):
    def __init__(self, problem: SqlProblem) -> None:
        super().__init__(str(problem))
        self.problem = problem
```

A failure of type `String` would raise `WherewithError(message)` itself.
Alternative: one `WherewithError` with a `.failure` attribute and no
per-type classes, which loses `except SqlProblemError`.

**Combined (the recommendation):** `SqlProblem` is declared as a failure
type, so it is generated as the exception class above (`SqlProblem(
WherewithError, ValueError)`), carried unraised inside `Failed`, and
raised directly by `parse_select`: one name, as under declared failures.
Constructing it is cheap, since Python attaches the traceback when it's
raised.

## Host caller

```python
from wherewith import parse_select, SqlProblem, WherewithError

try:
    select = parse_select('SELECT a FROM')
except SqlProblem as e:            # pure values: except SqlProblemError as e
    print(f'{e} (word {e.word})')  # pure values: e.problem.word
except WherewithError:
    ...                            # anything else from Wherewith
```

Prints `expected a table at word 4 (word 4)`. A caller that only knows
"bad input" can write `except ValueError`.
