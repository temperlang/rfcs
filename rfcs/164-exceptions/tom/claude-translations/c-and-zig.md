# C and Zig (future backends, briefly)

**Hand-written illustrations, not generated or run.** Neither backend
exists. Both languages return failures as values, so, as in Rust and Go,
the two proposals generate the same host API; the shapes follow
[claude-thoughts.md](../claude-thoughts.md#representations-beyond-the-current-backends):
a status code plus an extensible error struct in C, an error set plus an
optional diagnostics out-parameter in Zig. In both, every function that
can fail takes the out-parameter from its first version, since adding
one later breaks source and binary compatibility.

## C

```c
/* wherewith.h */
typedef enum wherewith_status {
    WHEREWITH_OK = 0,
    WHEREWITH_SQL_PROBLEM = 1,   /* one code per exported failure type */
} wherewith_status;

typedef struct wherewith_select wherewith_select;   /* opaque */
typedef struct wherewith_error wherewith_error;     /* opaque: kind, fields, message, cause */

/* On failure, sets *error (if error isn't NULL); free it with wherewith_error_free. */
wherewith_status wherewith_parse_select(
    const char *text, size_t text_len,
    wherewith_select **out, wherewith_error **error);

const char *wherewith_error_message(const wherewith_error *e);   /* "expected a table at word 4" */
const wherewith_error *wherewith_error_cause(const wherewith_error *e);
const char *wherewith_sql_problem_text(const wherewith_error *e);
int32_t wherewith_sql_problem_word(const wherewith_error *e);
void wherewith_error_free(wherewith_error *e);
```

Library base: the `wherewith_` prefix and the `wherewith_status` enum.
Equality is of codes, as in C generally. Host caller:

```c
wherewith_select *select = NULL;
wherewith_error *error = NULL;
if (wherewith_parse_select(sql, strlen(sql), &select, &error) == WHEREWITH_SQL_PROBLEM) {
    fprintf(stderr, "%s (word %d)\n",
            wherewith_error_message(error), (int) wherewith_sql_problem_word(error));
    wherewith_error_free(error);
}
```

## Zig

```zig
pub const Error = error{SqlProblem};   // one code per exported failure type

/// Filled in on failure when the caller passes one; fields per failure type.
pub const Diagnostics = struct {
    message: []const u8 = "",
    failure: union(enum) {
        none,
        sql_problem: struct { text: []const u8, word: i32 },
    } = .none,
};

/// Parses `SELECT a, b FROM t`.
pub fn parseSelect(
    allocator: std.mem.Allocator,
    text: []const u8,
    diagnostics: ?*Diagnostics,
) (Error || std.mem.Allocator.Error)!Select { … }
```

Zig's error sets carry no data by design; the diagnostics parameter is
the standard library's own pattern for details (as `std.json` uses).
Equality is of codes, and `switch` over the set is exhaustive. Allocation
failure is a Zig error, not a panic, which Temper's semantics would need
to allow for. Host caller:

```zig
var diag: wherewith.Diagnostics = .{};
const select = wherewith.parseSelect(gpa, sql, &diag) catch |err| switch (err) {
    error.SqlProblem => {
        std.debug.print("{s} (word {d})\n", .{ diag.message, diag.failure.sql_problem.word });
        return;
    },
    error.OutOfMemory => return err,
};
```

**Which types can be failures (meeting point 6).** Any type works in
both, since each failure becomes a code plus fields; a `String` failure
is a code with only a message.
