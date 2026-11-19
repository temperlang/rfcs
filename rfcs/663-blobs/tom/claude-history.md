# From earlier design notes: bytes and buffers

Added by Claude, 2026-11-19, from the team's earlier design notes.
Background only; nothing here is decided.

- **Buffer orientation instead of a bytes type.** The earlier answer to
  "do we have a bytes type?" was no: processing was to read input
  buffers left to right and write output buffers left to right, because
  random access into strings is O(n) on some hosts depending on their
  native encoding.
- **Buffer kinds.** Read and write buffers of bytes, UTF-8, UTF-16, and
  UTF-32 code units (and numeric variants), backed by lists, string
  builders, or primitive arrays, with bulk copies between matching
  kinds.
- **Cursors and slices.** Immutable, comparable positions or (offset,
  length) slices, cheap to copy; `commit` promises not to reread or
  roll back past a point, which lets shared ring buffers release space
  and lets an HTTP response flush a prefix; `disavow` marks output as
  invalid after the fact.
- **Edge cases recorded:** appending a single byte to a UTF-8 buffer
  either isn't monotonic or reserves room for a whole code point;
  rolling back to just before an orphaned UTF-16 surrogate; whether a
  text buffer accepts any code point or only scalar values, and a flag
  noting when it had to substitute U+FFFD.
- **String views.** A later sketch gave strings views as bytes (as if
  UTF-8), UTF-16 code units, and code points, each a slice with `read`,
  `advance`, and `hasAtLeast`, implemented by host connections.
- **Prior art:** Thrift keeps a separate `binary` type beside UTF-8
  strings, added for Java interoperability.
