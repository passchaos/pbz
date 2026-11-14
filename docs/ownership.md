# pbz ownership model

pbz has no hidden global state and no garbage collector. Every API takes an
`std.mem.Allocator`, and the caller decides how long decoded data lives. This
document explains the two decode modes, the ownership APIs, and the lifetime
rules for generated and dynamic messages.

## Two decode modes

Generated messages expose two families of binary decode entry points:

| Mode | Entry points | Payload storage |
|---|---|---|
| Borrowed | `decode`, `decodeFromReader`, `decodeReuse` | `string`/`bytes` fields borrow slices of the input buffer; repeated scalar buffers are allocated from the caller allocator |
| Owned | `decodeOwned`, `decodeOwnedReuse`, `decodeOwnedInitialized` | string/bytes payloads are copied into a per-message arena; nested messages share the same arena |

Borrowed decode is the fastest path and is suitable when the input buffer
outlives the message (for example, a network frame kept alive for the request
lifetime). Owned decode is the safe default when the input is transient.

`decodeReuse` and `decodeOwnedReuse` reset and refill an existing message,
keeping previously allocated repeated-field buffers when the new payload fits.
`decodeKnownReuse` is a trusted same-schema fast path: the caller must pre-size
repeated buffers for the decoded element counts, and unknown or
schema-mismatched fields are **rejected** instead of preserved. Use `decode` /
`decodeReuse` when unknown-field preservation matters.

## Ownership API matrix

| API | Direction | Lifetime / rules |
|---|---|---|
| `adoptOwned(allocator)` | borrowed → owned | Converts a borrowed decode in place: allocates the message arena and copies all borrowed payloads into it |
| `adoptOwnedInto(allocator, owned_allocator)` | borrowed → owned | Same, but shares one arena across nested messages so a nested graph does not pay one arena allocation per message |
| `cloneOwned(allocator)` | borrowed/owned → owned | Deep clone into a new message whose payloads are owned; safe to hand to a long-lived allocator |
| `mergeFrom(other)` | merge | Deep-copies the source into the destination (ownership of the destination is preserved) |
| `deinit(allocator)` | teardown | Frees repeated buffers, map storage, unknown fields, and the message arena; `init()` values may be deinitialized safely |
| `clear(allocator)` | reset | Releases owned storage and resets the message to its `init()` state |
| `toDynamic` / `fromDynamic` | bridge | Converts between generated and dynamic representations; the dynamic value borrows descriptors from the provided `FileDescriptor`/`Registry` |

Arena rule: all owned payloads of a message graph, including nested message
payloads, are backed by the top-level message's arena. Keep the top-level
message alive while using nested messages, and do not `deinit` nested messages
individually.

## JSON ownership

- `jsonParse(allocator, text)` copies the input into the message arena and owns
  all parsed strings/bytes.
- `jsonParseValue(allocator, arena_allocator, value)` parses from an existing
  `pbz.json.Value` tree and borrows string slices from it. The caller must keep
  both the backing text and the arena alive for as long as the message is used.
- `jsonStringifyAlloc` returns an owned slice; `jsonStringify` writes into a
  caller-provided `std.Io.Writer`.

## Dynamic message ownership

`DynamicMessage.init(allocator, descriptor)` borrows the descriptor. The
`FileDescriptor` (or `Registry`) must outlive the message and any values cloned
from it. `DynamicMessage.deinit` releases field storage; `clone` deep-copies
into a new allocator.

## Recommended patterns

1. **Request-scoped arena.** Allocate a per-request `ArenaAllocator`, decode
   with `decodeOwned`, and free the arena once at the end. See
   `examples/ownership_patterns.zig`.
2. **Long-lived values.** Use `cloneOwned` (generated) or `clone` (dynamic) to
   move a value out of a request arena into a stable allocator.
3. **Hot loops.** Use `decodeReuse`/`decodeOwnedReuse` to keep repeated-field
   capacity, and `decodeKnownReuse` only when the schema is trusted and unknown
   fields are irrelevant.
4. **Zero-copy output.** Use `*FieldView`/`*BytesView`/`*StringView` and
   `*FieldSlices`/`*BytesSlices`/`*StringSlices` when the encoder output buffer
   can outlive the message, and `valuesPackedFixedView` /
   `valuesPackedIterator` for packed fixed-width scans.
