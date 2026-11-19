# Temper libraries from a Python user's point of view

By Claude Code (Claude Opus 5.5), 2026-11-19, for
[#676](https://github.com/temperlang/temper/issues/676). Suggestions
only; nothing here is decided.

## The question

Does a Temper library look and behave like a Python library to someone
who writes Python, and what would make it more so?

**Short answer:** closer than any other backend studied so far. Names
are snake_case, getters are properties, constructors take keywords,
lists come back as tuples and maps as read-only `mappingproxy`s,
callbacks are plain callables, interfaces are ABCs that Python classes
subclass, and every public signature is fully annotated: a typed user
program over all six libraries is clean under pyright and mypy strict.
Where it falls short: the packages don't ship `py.typed`, so once
installed, mypy sees nothing and pyright strict complains; functions
take no keyword arguments; no class has a `__repr__` or a `__hash__`,
so the 15 classes with `__eq__` can't go in a set or be dict keys; lists
passed in are kept by reference, so an "immutable" `Color` changes
when the caller's list does; failures are an empty `temper_core.Bubble`,
which since yesterday is no longer the `RuntimeError` the tours and
`notes/api-compat.md` promise, so three of the six tours now crash; and
`import temper_core` costs about 45 ms, half of it for HTTP modules no
library here uses. Most fixes are additive and small; the error types
and `Pair` are design questions for this RFC and
[#164](../../164-exceptions/README.md).

## How this was studied

- Built the six showcase libraries (Argmas, Chromarite, Hrefine,
  Kelpto, Ordable, and Wherewith) with Temper's compiler (`temper build
  -b py`, temperlang/temper at `13dc5669`, runtime `0.7.0.dev267`), and
  ran each library's Python tour against them. Chromarite's and
  Ordable's match their expected output; Argmas's matched for the
  command line tried; Hrefine's, Kelpto's, and Wherewith's crash
  (section 4).
- Wrote a probe library (about 170 lines of Temper: defaults,
  nullables, maps, lists kept in fields, `@auto("==")`, interfaces,
  generics, a sealed interface, bubbles, panics, `Int64`, strings, and
  builders changed during callbacks), and Python programs that use it
  and the six libraries as a Python user would. Every snippet below was
  run, and output is quoted as printed.
- Type-checked user code with pyright 1.1.414 and mypy 2.4.0, strict,
  at Python 3.11, against the source (as CI's
  `.github/ci-tools/check_library_py.py` does) and against wheels built
  with `uv build` and installed, as users get them.
- Read the Python backend (`crates/temper-be-py`), its runtime
  (`crates/temper-be-py/runtime/temper-core/temper_core/__init__.py`),
  `docs/backends/README.md`, `notes/api-compat.md` (its Python section),
  and `notes/tmpl/surface.md` (protocol hooks).
- Ran everything on CPython 3.12.3. Python 3.11, the declared floor,
  wasn't installed and couldn't be downloaded here, so 3.11 claims rest
  on the checkers' `--python-version 3.11` and on parsing every
  generated file with `ast.parse(feature_version=(3, 11))`.
- Conventions are quoted from PEPs and docs.python.org, fetched live
  (PEPs 8, 257, 440, 561, 570, 621, and 639; the data model,
  exceptions, and dataclasses pages). typing.readthedocs.io,
  packaging.python.org, and docs.astral.sh weren't reachable, so uv's
  behavior below is from running it (uv 0.9.21), not its docs.
- Timings are from a shared, noisy machine: ranges are the fastest and
  slowest of 10 timed runs (two processes of five).

## 1. Typing for users

### `py.typed`

**Today.** The runtime ships `temper_core/py.typed`; no library does.
Installed from a wheel, mypy skips the library entirely and every name
from it is `Any`:

```
user_typed.py:4: error: Skipping analyzing "pprobe": module is installed,
  but missing library stubs or py.typed marker  [import-untyped]
user_typed.py:37: error: Class cannot subclass "Shape" (has type "Any")  [misc]
Found 2 errors in 1 file
```

The same file against the source finds the five real mistakes in it
(a keyword argument, an unchecked `None`, a `dict` for a `Map`, a write
to a read-only property, and `append` on a returned tuple). pyright
strict still infers from the installed source but reports
`Stub file not found for "pprobe" (reportMissingTypeStubs)` on each
import. Copying the package and adding an empty `py.typed` was enough:
mypy then reported the same five errors as from source, and pyright
dropped the two stub errors.

**What Python users expect.** [PEP 561](https://peps.python.org/pep-0561/):
"Package maintainers who wish to support type checking of their code
MUST add a marker file named py.typed to their package supporting
typing." Typed libraries such as attrs, pydantic, and httpx ship it.

**Option.** Write `py.typed` into every library package. hatchling
includes it without configuration. Free and not breaking.

### Annotation quality

**Today.** Good. In the six libraries' public functions, methods, and
properties, no signature contains `Any`, and none names a private type
(Kelpto's show public `kelpto_core` types under import aliases such as
`_RedNode`, which editors resolve). A typed user program that declares
an Argmas command, implements its `Environment` interface, matches on
the `ParseResult`, parses a URL, converts a color, sorts, builds a
query, and walks a Markdown document's headings is clean under both
checkers in strict mode:

```
0 errors, 0 warnings, 0 informations      (pyright --strict)
Success: no issues found in 1 source file (mypy --strict)
```

Inside the libraries, CI's ratchet allows a few errors that users never see:
mypy's `no-any-return` 4 times in Chromarite (from `**`); pyright's
`reportUnusedVariable` 3 times in Hrefine, `reportUnnecessaryComparison`
or `reportUnnecessaryIsInstance` 4 times in Wherewith and once in
kelpto-md, and 402 `reportUnknown*` (plus one unused variable) in
kelpto-html, from locals pyright can't infer through `while` loops. Wherewith's baseline
allows 6 and Kelpto's sample tests' 1 where they now have 4 and 0, so
both can drop.

### Maps in parameters

A `Map<K, V>` parameter is annotated `MappingProxyType[K, V]`, so the
`dict` a Python user has fails the check, though it works at runtime:

```
error: Argument of type "dict[str, int]" cannot be assigned to parameter
  "m" of type "MappingProxyType[str, int]" in function "map_get"
```

A `Mapped` parameter is `Mapping[K, V]` (Argmas's `set_messages`), which
takes either. **Option:** annotate `Map` parameters `Mapping[K, V]` too;
results can stay `MappingProxyType`. Not breaking.

### Optional parameters and `None`

**Today.** `greet(name: str, greeting: str | None = None, /)`; `None`,
passed or omitted, means the default, as Temper's rule says. `help()`
shows `= None`, not the default the docs would mention (`"Hello"`).
Nullable results are `T | None`, real `None`s, so `if u is not None`
narrows in both checkers. This is the part every other study had to
work around, and Python gets it right. Generics are right too:
`Generic[T]` with module-level `TypeVar`s (3.12's `class Box[T]` would
need a 3.12 floor), so `boxed("s").value.upper()` checks.

**Option** (small, not breaking): when the default is a literal, also
say it in the docstring (section 7). Printing it as the default value
would change the meaning of an explicit `None`.

### Interfaces: ABCs or Protocols

**Today.** An interface is `class Shape(metaclass=ABCMeta)` with
`@abstractmethod`s and its default methods as ordinary methods. Python
subclasses work and get the defaults; a missing method fails as Python
does (`Can't instantiate abstract class Half without an implementation
for abstract method 'area'`). A class with the same methods but no base
works at runtime (`describe_shape(Duck())` gives `duck`) and fails the
checkers (`"Duck" is not assignable to "Shape"`). Fun interfaces
(`@fun`) are just `Callable[[str], int]`, not exported at all, so
`score_all(["ab", "c"], len)` is 3: exactly what a Python user wants.

**What Python users expect.** Both forms are common. ABCs for
frameworks with shared behavior (`collections.abc.Mapping` gives
`get`, `keys`, and `__contains__` to subclasses); `typing.Protocol`
([PEP 544](https://peps.python.org/pep-0544/)) where only the shape
matters. A Protocol's default methods reach only explicit subclasses,
and `isinstance` needs `@runtime_checkable`, which checks only that
the names exist.

**Options.** (a) Keep ABCs: nominal, like Java and C#, and generated
code's `isinstance` tests for sealed types stay exact. (b) Protocols for
interfaces with no default members and no `isinstance` use, such as
Argmas's `Environment`: a `dict`-backed object or `os.environ` wrapper
would then pass without a base. Additive in effect, but each interface
switches between forms as defaults are added, which is a surprising
API change. Recommendation: keep (a).

## 2. Values

### `__repr__`, `__eq__`, and `__hash__`

**Today.** Across the six libraries' 162 public classes:

| Dunder | Classes defining it |
|---|---|
| `__str__` (from `toString`) | 34 |
| `__eq__` (from `@auto("==")` or an `eq` method) | 15 |
| `__hash__` | 0 |
| `__repr__` | 0 |

So:

```python
>>> Color.parse("#ff8000")
<chromarite.chromarite.Color object at 0x79d94d174cc0>
>>> str(Tag.red)        # no toString
'<pprobe.pprobe.Tag object at 0x7f103e0355d0>'
>>> {Space.srgb}
TypeError: unhashable type: 'Space'
>>> {parse_url("https://e.com/"): 1}
TypeError: unhashable type: 'Url'
```

**What Python users expect.** The data model: "A class that overrides
`__eq__()` and does not define `__hash__()` will have its `__hash__()`
implicitly set to None." And for `__repr__`: "If at all possible, this
should look like a valid Python expression that could be used to
recreate an object with the same value … If this is not possible, a
string of the form `<...some useful description...>` should be
returned." The standard library does this for values:
`Fraction(1, 3)`, `IPv6Address('::1')`, and `urlsplit`'s
`SplitResult(scheme='https', netloc='a', path='/b', query='',
fragment='')`, which is hashable. `dataclasses` and attrs generate
`__repr__` and `__eq__` from fields, and `__hash__` too when frozen.

**Options.**

- `__hash__` for `@auto("==")` classes from the same fields as `__eq__`
  (they're immutable in practice: Temper has no setters for them).
  For a hand-written `eq` (Hrefine's `Url`, by `href`), only a Temper
  `hash` method could say what to hash; until Temper has one (the
  `Hash` protocol in `notes/tmpl/surface.md` is "once Temper has
  hashing"), leave them unhashable, which is honest.
- `__repr__` from constructor properties, `Tag(name='red')`, for
  `@auto("==")` classes; and for the rest the `<…>` form with the
  `toString` when there is one, `<Point (1.0, 2.0)>`. `notes/tmpl/surface.md`
  leaves this to "an idiomatic variant"; it's additive, so the first
  variant could take it too.

Why not `@dataclass(frozen=True, slots=True)`, which gives all of
these and `__match_args__`? Temper classes have computed properties,
constructor bodies, private fields, and `var` setters, and frozen
dataclasses assign through `object.__setattr__`, which is slower.
Generating the few dunders directly keeps today's shape. Copying and
pickling already work, through `__slots__`.

### Immutability

**Today.** Properties without setters refuse writes (`property 'x' of
'Point' object has no setter`), `__slots__` refuses new attributes,
returned lists are tuples and maps `mappingproxy`s, and a
`ListBuilder` comes back as the library's own `list`, as Temper means
it to. Writing `p._x` works, which is Python's convention for
private names. Chromarite's `demos/immutable` records statics as the
two remaining "changed" attempts (`Space.srgb = Space.oklch`
succeeds): class attributes are plain attributes, and a metaclass
`__setattr__` to stop it would cost every class a metaclass. Python
users don't expect class attributes to be locked; `typing.Final` can't
express a class attribute assigned after the class body, as these are.

**But lists passed in are kept by reference.** The library stores the
caller's `list` and later returns it:

```python
vals = [1.0, 0.5, 0.0]
c = Color.from_list(Space.srgb, vals)
print(c.to_css(), c.to_list() is vals)   # ('rgb(255 127.5 0)',) True
vals[0] = 0.0
print(c.to_css())                        # ('rgb(0 127.5 0)',)
vals.extend([0.0, 0.0, 1.0])
print(c.length)                          # 1: the row count was computed once
c.to_list().append(9.0)                  # works, on the caller's list
```

In the probe, `Window(xs)` keeps `count = len(xs)`; after
`xs.clear()`, `w.sum()` raises `BaseException('index 0 out of bounds
for length 0')`. The demo misses this because it passes a list literal.
Python users don't expect defensive copies everywhere (dataclasses
don't copy), but they do expect an immutable value to stay put, and
Temper's `List` type promises it.

**Option.** Where an exported constructor or function stores a `List`
parameter (a field, a module value, a closure that outlives the call),
convert it with the runtime's `listed_to_list`, which returns a tuple
unchanged and copies anything else. Callers passing tuples, and every
call inside the library, pay nothing. The same pattern appears in Lua
(returned lists alias library state) and C++ (writable shared
vectors).

### Lists, maps, and `Pair`

Lists and maps already map to what Python users have: `Sequence[T]` in
(a `list` or `tuple`; a generator or set is a type error, and at runtime
`object of type 'generator' has no len()`), tuples out; `Mapping` or
`MappingProxyType` in, `mappingproxy` out (a missing key is Python's
own `KeyError('z')`). Indexes are Temper's: `nth(["a"], -1)` panics
rather than reading from the end, which is right for a port of the same
logic, and documented by the panic's message.

`Pair` is the exception. Hrefine's `UrlSearchParams.from_entries` takes
`Sequence[Pair[str, str]]`, so its tour does `from temper_core import
Pair`, naming the runtime, which #676's principle 3 rules out. A Python
user would pass `[("q", "a b"), ("page", "2")]`. And `Pair` has no
`__repr__`, `__eq__`, or `__iter__` (so `k, v = pair` fails), and its
indexing method is misspelled, `__subscript__` for `__getitem__`
(`Pair("k", 1)[0]` gives `'Pair' object is not subscriptable`).

**Options.** (a) Fix `__getitem__` and add `__iter__`, `__repr__`, and
`__eq__` (additive). (b) Translate `Pair<K, V>` as `tuple[K, V]`
everywhere (breaking for `.key` and `.value` users, but what every
Python mapping API does: `dict.items()`). (c) A generic `NamedTuple`
`Pair(key, value)` (3.11 allows generic NamedTuples): `.key`, `.value`,
unpacking, and indexing all work, and a real tuple goes into anything
that takes one, but a checker still rejects a plain tuple where `Pair`
is expected. (c) is the compatible middle; (b) is the most Pythonic.

### Int and Int64

**Today.** `Int` is 32-bit with wraparound, through the runtime's
`int_add`, `int_mul`, and friends; `Int64` the same at 64 bits.
Arguments aren't checked, and only Temper arithmetic wraps:

```python
add_ints(2**31 - 1, 1)                     # -2147483648
add_ints(2**40, 0)                          # 0
add_ints(1.5, 1)                            # 2.5 (an "Int")
apply_twice(lambda x: x * 2**20, 2**15)     # 36028797018963968, never wrapped
c.count = 2**40; c.increment(); c.count    # 1
add64(2**63 - 1, 1)                         # -9223372036854775808
parse64("9223372036854775808")              # raises temper_core.Bubble
```

**What Python users expect.** `int` has no bounds; where a C size
matters, the standard library checks: `array('i', [2**31])` raises
`OverflowError: signed integer is greater than maximum`, and
`struct.pack('<i', 2**31)` raises `struct.error: 'i' format requires
-2147483648 <= number <= 2147483647`. Silent wrapping is what a Python
user would least expect. `bool` is an `int` (`add_ints(True, True)` is
2), and that's normal.

**Options.** (a) Check `Int` parameters and settable `Int` properties
at exported entry points (`-2**31 <= n < 2**31`, one comparison each),
raising `OverflowError` with the parameter's name; internal calls skip
it. Callback results would need the same check where they enter Temper
arithmetic. (b) Document the 32-bit range in each signature's
docstring. (a) changes behavior only for inputs that are wrong today.

`Float64` parameters take `int`s, as PEP 484's numeric tower allows, and
then compute with them: `square(3)` returns the `int` 9 though annotated
`float`. Harmless almost always (`float64_to_string` still prints
`9.0`), so no change is proposed.

### Strings

Python's `str` is a sequence of code points, and the Python backend's
`StringIndex` is a code point offset, so positions in Hrefine's errors
(`port-out-of-range at 20`) are exactly `text[20]`, a natural fit. One
gap: Python strings can hold lone surrogates (from `os.fsdecode` of
undecodable bytes, with `surrogateescape`), which Temper's own code
point functions refuse:

```python
code_points("\ud800")                 # 1
reverse_of("\ud800")                  # BaseException: panic (appendCodePoint refuses it)
parse_url("https://a/\ud800x").href   # 'https://a/%ED%A0%80x'
```

Browsers convert URL input to a USVString first, giving
`https://a/%EF%BF%BDx` (Node's `new URL` does). Hrefine's JS output
gives `%ED%A0%80` too, so it's a Hrefine bug on both backends, from
the same missing conversion. Python's own stance is to refuse:
`"\ud800".encode("utf-8")` raises `UnicodeEncodeError`. Libraries that
take text from outside can replace or refuse; Temper itself could check
at exported entry points, at a scan per string argument. Worth
deciding across backends (JS strings have the same lone surrogates).

## 3. API shape

### Naming

snake_case for functions, methods, and properties, `CapWords` for
classes, a leading `_` for everything not exported, `__all__` in every
module, and a trailing `_` for keywords (`Splice.from_`), all as
[PEP 8](https://peps.python.org/pep-0008/) says. Two quirks:

- A member named for a builtin that class bodies use in annotations
  gets a `_` (Argmas's `MessageTable.list_`), since a method named
  `list` would hide `list` in later annotations of the same class. A
  sound reason; only one public name is affected.
- Soft keywords (`match`, `case`, `type`, `_`) are escaped as members
  too, though Python allows them as attribute names (`re.Pattern.match`,
  `dataclasses.Field.type`). Std's `Regex.match_` is the visible case.
  Dropping the escape for members would rename it, so it's a breaking
  change for std's Python users only.

### Keyword arguments

**Today.** Constructors take keywords (`Order(upper_first=True)`,
Argmas's `CommandSpec(name="pack", about=…)`), which the tours lean on.
Every function and method is positional-only:

```python
>>> greet("Bob", greeting="Hi")
TypeError: greet() got some positional-only arguments passed as keyword arguments: 'greeting'
>>> c.mix(Color.parse("blue"), amount=0.5, space=Space.oklab)
TypeError: Color.mix() got some positional-only arguments passed as keyword arguments: 'amount, space'
>>> Url.parse("a", base="https://e.com/")
TypeError: Url.parse() got some positional-only arguments passed as keyword arguments: 'base'
```

`notes/api-compat.md` chose this so that "parameter names aren't API",
which is [PEP 570](https://peps.python.org/pep-0570/)'s stated benefit:
"Library authors would have the flexibility to change the name of
positional-only parameters without breaking callers."

**What Python users expect.** Positional-only for the obvious first
arguments and keywords for options. `sorted(iterable, /, *, key=None,
reverse=False)` is the model; `json.dumps(obj, *, skipkeys=False, …)`
and requests' `requests.get(url, params=None, **kwargs)` the same
idea. Calls like `c.mix(other, 0.5, Space.oklab)` read poorly, and an
optional parameter can only be reached by passing every one before it
(`None` for each).

**Options.**

| Option | Gains | Costs |
|---|---|---|
| A. Keep positional-only | Names free to change | Unidiomatic for options |
| B. Move `/` to just before the first optional parameter | Optional parameters by keyword; required ones stay free; not breaking | Optional parameter names become API (recorded like constructor names) |
| C. Also make optional parameters keyword-only (`*`) | Exactly `sorted`'s shape | Breaks callers that pass them positionally |
| D. Keywords for every parameter | Simplest rule | Every name becomes API, including `x` and `s` |

B is the recommendation. It's additive, and it matches what callers
need, since required arguments are rarely the confusing ones.

### Properties, methods, constructors

Getters are `@property`s, `var`s get setters, and static factories
are `@staticmethod`s (`Color.parse`), as Python users expect.
`to_string()` beside `__str__` and `eq()` beside `__eq__` are harmless
leftovers kept for compatibility (`keep_method` in
`notes/tmpl/surface.md`). A private Temper constructor is still a
public `__init__` (`Tag("green")` makes a tag the library never
defined); Python can't hide one, so that's low priority, though
`@typing.final` on generated classes would let checkers flag
subclassing, as Java's `final` does.

### Iteration, containers, and `match`

**Today.** No generated class is iterable or sized. `UrlSearchParams`,
whose JavaScript namesake is iterable, gives
`'UrlSearchParams' object is not iterable` for `list(sp)` and for
`"a" in sp`; `len(Color.parse("red"))` fails where `color.length`
works. Temper has no iteration protocol yet; `notes/tmpl/surface.md`
lists `Iterate`, `Index`, and `Hash` as protocols "later".

`match` works with keyword patterns (`case Ok(value=v):`, and Argmas's
tour uses `case Args():`), but positional patterns fail:
`case Ok(v):` gives `TypeError: Ok() accepts 0 positional sub-patterns
(1 given)`. The data model's `__match_args__` "can be assigned a tuple
of strings", which dataclasses set from fields by default.

**Options.** `__match_args__` from each class's constructor properties
(additive, one line per class). Map the `Iterate` and `Index` protocols
to `__iter__`, `__len__`, and `__getitem__` when Temper adds them;
guessing from a `length` getter would be the kind of heuristic that's
better left out.

No library here holds a resource, so context managers have nothing to
map to; async (`TemperFuture`) wasn't studied.

### Callbacks changing what they walk

The other studies changed a builder during its own callback. Python is
memory safe in every case, but answers differently by function, and
two cases raise Python's own errors rather than a Temper panic:

| Probe | Python | Why |
|---|---|---|
| `reduceFrom` growing the builder | 1299 | `functools.reduce` iterates the live list |
| `map` shrinking it | 2 | `tuple(f(x) for x in lst)` stops at the new end |
| `MapBuilder.forEach` adding keys | `RuntimeError: dictionary changed size during iteration` | `dict.items()` |
| `sort` whose comparison grows it | `ValueError: list modified during sort` | `list.sort` |

1299 is what core's `reduceFromIndex` body gives; the
[C++ study](claude-cpp-study.md) lists Python with the backends giving
12 from a snapshot, which isn't what this build does. Whatever the
cross-backend contract becomes, Python's runtime can meet it cheaply
(iterate `tuple(lst)` for a snapshot, or index to the live length), and
`forEach` and `sort` should then raise the same panic as other
backends rather than these two host errors, which `orelse` passes and
`except Exception` catches.

## 4. Errors

### Today

| What happens | What the Python user sees |
|---|---|
| `parse_url("setup.html")`, uncaught | a traceback through four private frames, ending `temper_core.Bubble` |
| `str(e)` for that failure | `''` |
| `except RuntimeError:` around it | doesn't catch (since `e2f74f93`, 2026-11-18) |
| `except Exception:` around it | catches |
| `Color.from_list(Space.srgb, [1.0, 0.0])` | `BaseException: panic` |
| `nth(["a"], 5)` | `BaseException: index 5 out of bounds for length 1` |
| `needs_positive(0)` (`positive(n) orelse panic()`) | the `Bubble` traceback, "During handling of the above exception, another exception occurred:", then `BaseException: panic` |
| `parse_url(42)` | `TypeError: object of type 'int' has no len()`, from inside |
| `make_map()["z"]` | `KeyError: 'z'` |

Tracebacks are the strong point: each frame shows a line of readable
generated Python, so a user can see where a failure started, even
without a message.

**`Bubble` stopped being a `RuntimeError`.** Commit `e2f74f93` made
`orelse` catch only the runtime's new `class Bubble(Exception)`, where
failures were a bare `RuntimeError()` before. Catching only Temper's
failures is right, but the base class changed too, and
`notes/api-compat.md` still says "failure is `RuntimeError`" and lists
exception types under **Keep**. Hrefine's, Kelpto's, and Wherewith's
tours catch `RuntimeError` and now end in tracebacks:

```
  File "…/wherewith/wherewith.py", line 283, in quote_string
    raise _Bubble()
temper_core.Bubble
```

`class Bubble(RuntimeError)` keeps both properties. #164's
[Python translation](../../164-exceptions/tom/claude-translations/python.md)
also describes the old `RuntimeError()` as today's.

**Panics are bare `BaseException`s.** That's defensible:
[PEP 8](https://peps.python.org/pep-0008/) says "Direct inheritance from
BaseException is reserved for exceptions where catching them is almost
always the wrong thing to do", which is a panic. In practice, `unittest`
records one as an error and moves on, a `ThreadPoolExecutor` future
re-raises it from `result()`, and in asyncio it passes `except
Exception` and escapes `asyncio.run`, so a server that catches
`Exception` per request goes down with it. But a bare `BaseException`
can't be caught by name without catching `KeyboardInterrupt` and
`SystemExit` too, and the exceptions page says BaseException "is not
meant to be directly inherited by user-defined classes"; a raised
instance of it is rarer still. The message is mostly `panic`, and the
bubble that caused it shows only as context.

### What Python users expect

A library-named hierarchy, with standard bases for categories:
requests' `InvalidURL` is both a `RequestException` and a `ValueError`,
and `json.JSONDecodeError` is a `ValueError` with `msg`, `pos`, and
`lineno`. Messages say what went wrong:

```
JSONDecodeError: Expecting property name enclosed in double quotes: line 1 column 2 (char 1)
ValueError: 'x' does not appear to be an IPv4 or IPv6 address
ValueError: Invalid IPv6 URL        (urlsplit("http://[::1"))
```

### Options and #164

- **Now:** `Bubble(RuntimeError)`; give bubbles a message where the
  runtime knows one (as `int_div`'s "division by zero" already does,
  and `mapped_get` could give the key); a named `temper_core.Panic`
  subclass of `BaseException`, with the panic's message and its cause
  as `__cause__` (`raise Panic(...) from e`), so `block_panics` and
  tests can catch it by name.
- **With #164:** library-named failure types, as its Python translation
  sketches (`WherewithError(Exception)`, `SqlProblem(WherewithError,
  ValueError)`), re-exported by the library, so users never import
  `temper_core` to catch. Python needs no `Result` form: exceptions are
  the language's way, and its translation already says so.
- **Panics' base:** keep `BaseException` (PEP 8's case) or use
  `Exception` so servers survive them. C++'s panics end the process; Python's are catchable either way, so `BaseException` is
  closest, but it's a question for #164's panic section.

## 5. Packaging

### The generated `pyproject.toml`

```toml
[project]
name = "argmas"
version = "0.1.0"
description = ""
readme = {text = "n/a", content-type = "text/plain"}
requires-python = ">=3.11"
license = { text = "Apache-2.0 OR MIT" }
authors = [  ]

dependencies = [
    "temper-core==0.7.0.dev267"
]

[dependency-groups]
test = [
    "temper-std==0.7.0.dev267"
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

Good: [PEP 621](https://peps.python.org/pep-0621/) metadata, a
standard build backend ([PEP 517](https://peps.python.org/pep-0517/),
[518](https://peps.python.org/pep-0518/)), std only in a
[PEP 735](https://peps.python.org/pep-0735/) test group, editable
installs ([PEP 660](https://peps.python.org/pep-0660/), as the tours
use), and wheels holding only the package (2.5 KB for `kelpto` to 56 KB
for `kelpto_md`; `temper_core` 17.6 KB). Gaps:

1. **No `py.typed`** (section 1).
2. **Thin metadata.** `description` is empty and the readme `n/a`,
   though each library's config has a prose summary; no classifiers
   (`Programming Language :: Python :: 3.11`, `Typing :: Typed`); no
   URLs unless the config names them. `license = { text = … }` is the
   form [PEP 639](https://peps.python.org/pep-0639/) calls "legacy
   deprecated"; `license = "Apache-2.0 OR MIT"` with `license-files` is
   current, and hatchling supports it.
3. **Exact runtime pins.** Libraries built by different Temper versions
   can't share an environment. Chromarite (built at `dev267`) beside a
   build of Argmas from `dev239`:

   ```
   And because argmas==0.0.1 depends on temper-core==0.7.0.dev239 and only
   argmas==0.0.1 is available, we can conclude that all versions of argmas
   and all versions of chromarite are incompatible.
   ```

   A range (`temper-core>=0.7.0.dev267,<0.8`) lets one runtime serve
   both, if the runtime keeps compatible within it.
4. **uv won't install a library pinned to a `.dev` runtime.** `uv pip
   install --find-links dist chromarite` fails with "`temper-core` was
   requested with a pre-release marker (e.g.,
   temper-core==0.7.0.dev267), but pre-releases weren't enabled";
   uv allows pre-releases only for packages named in the user's own
   requirements. [PEP 440](https://peps.python.org/pep-0440/) says
   resolvers SHOULD "accept remotely available pre-releases for version
   specifiers where there is no final or post release that satisfies
   the version specifier", which an exact `.dev` pin is (pip's
   documented rule allows it; not run here). The tours avoid it by
   listing `temper-core` themselves; a final runtime release avoids it
   for everyone.
5. **`temper-core`'s `pyproject.toml`** has Poetry-style `packages`
   and `include` keys under `[project]`, not PEP 621 fields; hatchling
   ignores them, and the wheel is right anyway.

### Module layout

A library is a package whose `__init__.py` star-imports one module of
the same name (`pprobe/pprobe.py`), so `from pprobe import Point` works,
but `Point.__module__` is `pprobe.pprobe`, which reprs and docs show.
Setting `__module__` to the package on exported classes and functions is
a common touch (NumPy does it) and free. Kelpto ships four
distributions with four top-level imports (`kelpto`, `kelpto_core`,
`kelpto_md`, and `kelpto_html`); Python users would expect `kelpto.md`
and `kelpto.html` subpackages, the same dotted-name question the
[Lua study](claude-lua-study.md) raises for `kelpto-md`.

### Import time

`python -X importtime`, five runs each (cumulative, ms):

| Import | Time |
|---|---|
| `temper_core` | 43–61 |
| `ordable`, `argmas`, `wherewith`, `hrefine`, `chromarite` | 45–78, nearly all `temper_core` |
| `kelpto` (with `kelpto_md`, `kelpto_html`, `kelpto_core`) | 62–68 |
| `hrefine`, with `http.client` and `urllib` imported only when used | 21 |

Of `temper_core`'s time, `http.client` takes 16 ms (with `email` and
`ssl`), `logging` 12 ms, and `urllib.*` about 6 ms, all for `std_net_send`
and `LoggingConsole`; each library's own module takes 0.5 to 4 ms once
compiled (kelpto_core 7 ms). As whole processes: `python -c pass` 10–14 ms, `import hrefine`
59–70 ms (33–36 ms with the HTTP imports moved into `std_net_send`), and
`import json, re, dataclasses` 27–30 ms. Startup is what command-line
tools, Argmas's purpose, are judged by. A first import without `.pyc`
files adds 20 to 70 ms more (Hrefine 80–89 ms, kelpto_md 125–133 ms),
and uv doesn't compile bytecode at install unless asked.

### Python versions

`requires-python = ">=3.11"`, but only 3.12 runs anywhere (CI's
toolchain installs it); the checkers check at 3.11. The generated code
parses even at 3.9's grammar, and no 3.12 feature turned up in it or the
runtime. A CI matrix of 3.11 and the newest release would make the
claim tested; 3.11, 3.13, and 3.14 weren't available here.

## 6. Speed

The probe and libraries against idiomatic hand-written Python doing the
same work (ms):

| Case | Generated | Hand-written | Note |
|---|---|---|---|
| Sum 1M floats in a list | 139–237 | 28–32 (`for`), 6 (`sum`) | |
| Sum 1M ints through a callback | 217–327 | 63–71 | `sum(f(x) for x in xs)` |
| 1M calls with `orelse` | 178–271 | 53–81 | `try`/`except ValueError` around a function that raises |
| Reverse 600k code points | 200–241 | under 1 | `s[::-1]`; Temper builds code point by code point |
| Natural sort of 20k names | 534–653 | 31–42 | Ordable also handles Unicode digits, case, and accents; a `re.split` key doesn't |
| Parse 10k URLs | 441–524 | 26–34 | `urlsplit` doesn't validate, normalize, or do IDNA |

The last two compare unlike work and only show scale. The first three
are the translation's own cost. From the generated code:

```python
while i < len(xs):
    t = t + _list_get(xs, i)   # a call, a sign check, and a try
    i = _int_add(i, 1)         # a call and a range check
```

Lowering it by hand, step by step (ms):

| Variant | Time |
|---|---|
| As generated | 158–232 |
| `i += 1` where the range rules out overflow | 90–128 |
| and `xs[i]` where the index is known in range | 40–75 |
| `for x in xs`, for `for … of` over a `List` | 15–40 |

So `_int_add` and `_list_get` each cost about as much as the loop's real
work. `notes/output-speed.md` already plans plain arithmetic where
ranges rule out overflow; for Python, add inlined indexing where the
index is known in range, and `for x in xs` for `for … of` over a `List`
(a tuple can't change underneath it). `orelse` itself is cheap in
Python: `try` costs nothing until something raises.

## 7. Docs and editors

**Today.** No generated module, class, or function has a docstring: 0
in all six libraries. Prose in the libraries' `.temper.md` files and
`/** … */` comments are both dropped (a `/** Adds one to [n]. */` on an
exported function gives none). `help(Point)` shows only signatures:

```
class Point(builtins.object)
 |  Point(x: float, y: float) -> None
 |  __init__(self, /, x: float, y: float) -> None
 |      Initialize self.  See help(type(self)) for accurate signature.
 |  scaled(self, k: float, /) -> 'Point'
 |  Readonly properties defined here:
 |  length
```

Editors show the same: full types, no prose.

**What Python users expect.** [PEP 257](https://peps.python.org/pep-0257/):
"All modules should normally have docstrings, and all functions and
classes exported by a module should also have docstrings." Pylance,
pyright's hovers, `help()`, Sphinx's autodoc, and pdoc all read them.

**Option.** Emit each declaration's doc (the IR keeps it, `temper-tmpl`'s
`doc` field) as a docstring, in plain prose, with Temper's `[n]`
references as `` `n` ``. A docstring on the package's `__init__.py`
from the library's config summary, too. Additive; size grows by the
docs' size.

## Cross-backend patterns, checked for Python

| Pattern (from the Lua, Rust, and C++ studies) | Python today |
|---|---|
| Failures without a message | Same: `str(e)` is `''` for every library failure |
| Runtime names in user code | `temper_core.Bubble` to catch precisely, `temper_core.Pair` for Hrefine's `from_entries` |
| Returned lists aliasing library state | No: tuples. But lists passed in are kept (section 2) |
| Changing a builder inside its own callback | Memory safe; live iteration, plus two host errors (section 3) |
| Exact runtime pins | Same, plus uv's pre-release rule |
| Docs dropped | Same |
| Values without equality, hashing, or a debug form | `__eq__` on 15 classes, `__hash__` and `__repr__` on none |

## Recommendations

**Quick wins** (not breaking):

1. Ship `py.typed` in every library package.
2. Make `Bubble` a `RuntimeError` again, as api-compat promises, which
   fixes three tours; then give runtime bubbles messages.
3. `__hash__` for `@auto("==")` classes, from the same fields.
4. `__repr__`: constructor form for `@auto("==")` classes, `<Name …>`
   with the `toString` for others.
5. Fix `Pair`: `__getitem__` (today misspelled `__subscript__`),
   `__iter__`, `__repr__`, and `__eq__`.
6. Import `http.client` and `urllib` inside `std_net_send`: imports take
   about half the time.
7. Annotate `Map` parameters as `Mapping[K, V]`.
8. `__match_args__` from constructor properties.
9. Docstrings from doc comments, and the package docstring from the
   config summary.
10. Metadata: description and readme from the config, `Typing :: Typed`
    and version classifiers, PEP 639's `license = "…"`; drop the
    non-PEP-621 keys from `temper-core`'s file.
11. Lower CI's Python baseline for Wherewith (6 to 4) and Kelpto's
    sample tests (1 to 0), as the ratchet asks.

**Medium changes:**

12. Allow keywords for optional parameters (option B, section 3); their
    names become API, recorded with constructors'.
13. Keep lists passed to exported entry points as tuples
    (`listed_to_list`) where the library stores them.
14. A named `Panic(BaseException)` carrying the message and the cause.
15. Check `Int` and `Int64` arguments' ranges at exported entry points,
    raising `OverflowError` *(changes behavior only for wrong input)*.
16. Plain arithmetic, inlined indexing, and `for x in xs` where Temper
    knows they're safe.
17. Version ranges for `temper-core`; a CI matrix of 3.11 and the newest
    Python.
18. `__module__` set to the package on exported names; `@typing.final`
    on generated classes.
19. Raise one panic, as other backends do, when a callback changes a
    map or a sort's list, once the cross-backend contract is settled.

**Design questions for #676 and #164:**

20. **Library-named failure types** *(breaking for `except Bubble`)*:
    #164's `LibError(Exception)` with categories like `ValueError`,
    re-exported so users never import `temper_core`.
21. **Panics' base class:** `BaseException` (PEP 8's rule; servers die
    with them) or `Exception` (servers survive; panics become
    catchable by accident).
22. **`Pair`** *(breaking for (b))*: a `NamedTuple` (compatible) or
    plain `tuple[K, V]` (most Pythonic).
23. **Escaping soft keywords as members** *(breaking for std's
    `Regex.match_`)*: Python allows `obj.match`; only keywords need `_`.
24. **Lone surrogates at the boundary:** refuse, replace, or pass
    through, decided with JS, which has the same strings.
25. **Iteration and container protocols:** map `Iterate` and `Index`,
    once Temper has them, to `__iter__`, `__len__`, and `__getitem__`.
26. **Kelpto-style multi-library packages:** subpackages (`kelpto.md`)
    rather than sibling top-level imports, decided with Lua's dotted
    names.
27. **Is `temper_core` ever named?** With 2, 20, and 22, no Python user
    of these six libraries would need to.

## Bugs found

On temperlang/temper `13dc5669`, CPython 3.12.3, Linux. `pprobe` is
built from the Temper shown.

1. **`Bubble` is no longer a `RuntimeError`:** since `e2f74f93`,
   `class Bubble(Exception)`. Hrefine's tour ends at
   `parse_url("setup.html")` in `except RuntimeError:` with a
   traceback ending `temper_core.Bubble`; Kelpto's at
   `edited.headings[0].with_level(7)`; Wherewith's at
   `Dialect.postgres.quote_string("a\0b")`. `notes/api-compat.md` says
   failures are `RuntimeError` and keeps exception types.
2. **Libraries don't ship `py.typed`:** `uv build` a library, install
   the wheel, and `mypy --strict` reports `module is installed, but
   missing library stubs or py.typed marker [import-untyped]` and treats
   the library as `Any`; pyright strict reports `reportMissingTypeStubs`.
3. **`__eq__` without `__hash__` makes values unhashable:** `{Space.srgb}`,
   `{Tag.red}` for `@auto("==") export class Tag { public name: String;
   … }`, and `{parse_url("https://e.com/")}` all raise `TypeError:
   unhashable type`. 15 classes in the six libraries.
4. **`Pair.__subscript__` should be `__getitem__`:**
   `temper_core.Pair("k", 1)[0]` raises `TypeError: 'Pair' object is
   not subscriptable`.
5. **Lists passed in are kept, so immutable values change:** `vals =
   [1.0, 0.5, 0.0]; c = Color.from_list(Space.srgb, vals); vals[0] =
   0.0` changes `c.to_css()`; `c.to_list() is vals`. With `export class
   Window { public items: List<Int>; public count: Int; … }`,
   `Window(xs)` then `xs.clear()` makes `w.sum()` panic.
6. **Changing a builder in its callback raises host errors:**
   `m.forEach { (k, v) => m.set("${k}x", v) }` on a `MapBuilder` raises
   `RuntimeError: dictionary changed size during iteration`;
   `b.sort { (a, c) => b.add(0); a - c }` raises `ValueError: list
   modified during sort`. (Memory safe; not panics, so they pass
   `orelse`.)
7. **Hrefine encodes lone surrogates as WTF-8:**
   `parse_url("https://a/\ud800x").href` is `https://a/%ED%A0%80x` in
   Python and JS; the URL Standard's USVString conversion gives
   `https://a/%EF%BF%BDx`, as Node's `URL` does.
8. **uv can't install a library pinned to a `.dev` runtime:**
   `uv pip install --find-links dist chromarite` fails: "pre-releases
   weren't enabled". Works when the user names `temper-core` too; pip's
   documented PEP 440 rule should accept it (not run).
9. **Doc comments are dropped:** `/** Adds one to [n]. */ export let
   inc(n: Int): Int` gives `def inc(n: int, /) -> int:` with no
   docstring.
10. **`int` arguments wrap silently:** `export let addInts(a: Int, b:
    Int): Int { a + b }`; `add_ints(2**40, 0)` is `0` and
    `add_ints(1.5, 1)` is `2.5`.
