# C++

**Hand-written illustration, not generated or run.** The worked example
from [the README](README.md#the-example), as the C++ backend might emit
it. Today the parser throws `temper::core::TemperBubble` (`what()` is
"bubble"), the only catchable type for a failure, and named after Temper;
the reason comes only from `selectProblem`. Strings are
`temper::core::Str` and objects `std::shared_ptr`, as today.

## Failure types

```cpp
namespace wherewith {

/// Base of every failure Wherewith reports.
class WherewithError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

/// SQL text that Wherewith can't parse.
class SqlProblem : public WherewithError {
public:
  SqlProblem(temper::core::Str text, int32_t word, std::string const & message)
      : WherewithError(message), text_(std::move(text)), word_(word) {}

  temper::core::Str const & text() const noexcept { return text_; }
  int32_t word() const noexcept { return word_; }

private:
  temper::core::Str text_;
  int32_t word_;
};

}  // namespace wherewith
```

- **Library base or category:** C++ allows two bases, but
  `SqlProblem : WherewithError, std::invalid_argument` would contain two
  `std::exception` subobjects, and `catch (std::exception const &)` then
  doesn't match it at all (an ambiguous base). So one chain: shown,
  `WherewithError : std::runtime_error`. A library whose failures share
  one category could root its base at `std::invalid_argument` instead.
  nlohmann/json is a close precedent: `json::exception` derives from
  `std::exception`, and its `parse_error` carries a `byte` position.
- **Message:** `what()`. **Cause:** thrown with `std::throw_with_nested`
  when the failure has one, so hosts can `std::rethrow_if_nested`.
- **Equality:** none, as for any C++ exception.
- **Temper names:** `TemperBubble` leaves what users catch, but
  `temper::core::Str` stays in signatures (here and throughout today's
  API); hiding it is a separate question.

## Declared failures

```cpp
namespace wherewith {

class Parser {
public:
  std::shared_ptr<Select> select() {
    keyword("SELECT");
    std::vector<temper::core::Str> columns{name("a column")};
    while (peek() == ",") {
      pos_ += 1;
      columns.push_back(name("a column"));
    }
    keyword("FROM");
    auto table = name("a table");
    if (peek()) {
      throw problem("expected the end");
    }
    return Select::make(std::move(columns), table);
  }

private:
  temper::core::Str need(temper::core::Str const & message) {
    auto w = peek();
    if (!w) throw problem(message);
    return *w;
  }

  SqlProblem problem(temper::core::Str const & text) {
    int32_t word = pos_ + 1;
    return SqlProblem(text, word, text + " at word " + std::to_string(word));
  }
  // keyword, name, and peek as in Temper
};

/// Throws SqlProblem if the text isn't a select Wherewith understands.
std::shared_ptr<Select> parseSelect(temper::core::Str const & text);

}  // namespace wherewith
```

A Temper `orelse` becomes `catch (SqlProblem const &)`.

## Failures as values

`std::expected<T, E>` (C++23) where the backend targets it, else a core
result struct of the same shape. Both proposals' tables leave C++'s
default host form open; the main option shown is the value form as the
API, with a throwing overload by configuration.

```cpp
namespace wherewith {

class Parser {
public:
  std::expected<std::shared_ptr<Select>, SqlProblem> select() {
    if (auto k = keyword("SELECT"); !k) return std::unexpected(std::move(k).error());
    auto first = name("a column");
    if (!first) return std::unexpected(std::move(first).error());
    std::vector<temper::core::Str> columns{*first};
    while (peek() == ",") {
      pos_ += 1;
      auto more = name("a column");
      if (!more) return std::unexpected(std::move(more).error());
      columns.push_back(*more);
    }
    // … FROM and the table the same way …
    if (peek()) return std::unexpected(problem("expected the end"));
    return Select::make(std::move(columns), *table);
  }
};

std::expected<std::shared_ptr<Select>, SqlProblem> parseSelect(temper::core::Str const & text);

}  // namespace wherewith
```

A host that wants an exception can call `.value()`, which throws
`std::bad_expected_access<SqlProblem>`, holding the problem as `error()`.
A generated throwing form would be a few lines over the value form; the
standard library's precedent for pairs is `std::filesystem`, where each
function throws and an overload taking `std::error_code&` doesn't.

**Which types can be failures (meeting point 6).** With any type allowed,
`SqlProblem` is a plain class (no `std::exception` base), which
`std::expected` holds just as well; only a throwing form needs an
exception type, a generated `SqlProblemError : WherewithError` holding
it. **Combined (the recommendation):** `SqlProblem` is the exception
class from [Failure types](#failure-types), held unthrown in
`std::expected` and thrown as itself by a throwing form. C++ captures no
stack trace, so constructing it costs only its fields and message.

## Host caller

```cpp
// Declared failures (or a throwing form under values):
try {
  auto select = wherewith::parseSelect("SELECT a FROM");
} catch (wherewith::SqlProblem const & e) {
  std::cerr << e.what() << " (word " << e.word() << ")\n";
} catch (wherewith::WherewithError const & e) {
  // anything else from Wherewith
}

// Failures as values:
auto select = wherewith::parseSelect("SELECT a FROM");
if (!select) {
  auto const & problem = select.error();
  std::cerr << problem.what() << " (word " << problem.word() << ")\n";
}
```
