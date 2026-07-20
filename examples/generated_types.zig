const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // C++/Rust-style flow: import the generated module and use the package
    // namespace plus concrete message type directly.
    var person = person_pb.demo.Person.init();
    defer person.deinit(allocator);

    person.id = 7;
    person.name = "Zig";
    person.scores = try allocator.dupe(i32, &.{ 10, 20 });
    try person.counts.put(allocator, "red", 1);

    // Map fields are generated as Zig map containers, matching C++/Rust/Go-style
    // typed map usage while retaining protobuf last-wins merge semantics.
    var other = person_pb.demo.Person.init();
    defer other.deinit(allocator);
    try other.counts.put(allocator, "red", 2);
    try person.mergeFrom(allocator, other);
    std.debug.assert(person.counts.count() == 1);
    std.debug.assert(person.counts.get("red").? == 2);

    // Packed fixed-width numeric fields expose zero-copy helpers when the
    // wire buffer can be inspected directly (little-endian targets).
    var signed_fixed = person_pb.demo.SFixedPacked.init();
    defer signed_fixed.deinit(allocator);
    signed_fixed.values = try allocator.dupe(i32, &.{ -7, 0, 42, -1024 });
    const signed_fixed_bytes = try signed_fixed.encode(allocator);
    defer allocator.free(signed_fixed_bytes);

    const signed_fixed_view = (try person_pb.demo.SFixedPacked.valuesPackedFixedView(signed_fixed_bytes)).?;
    std.debug.assert(signed_fixed_view.len == signed_fixed.values.len);
    for (signed_fixed_view, signed_fixed.values) |actual, expected| {
        std.debug.assert(actual == expected);
    }

    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.SFixedPacked.valuesPackedFixedSlices(&header, signed_fixed.values);
    std.debug.assert(std.mem.eql(u8, slices.header, signed_fixed_bytes[0..slices.header.len]));

    const bytes = try person.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var stack_buffer: [128]u8 = undefined;
    const stack_bytes = try person.encodeInto(&stack_buffer);
    std.debug.assert(std.mem.eql(u8, stack_bytes, bytes));
    const fast_stack_bytes = try person.encodeIntoAssumeCapacity(&stack_buffer);
    std.debug.assert(std.mem.eql(u8, fast_stack_bytes, bytes));

    var decoded = try person_pb.demo.Person.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    std.debug.assert(decoded.id == 7);
    std.debug.assert(std.mem.eql(u8, decoded.name, "Zig"));

    // Unknown fields preserve the exact source bytes. This deliberately uses a
    // non-canonical three-byte encoding for field 100's tag; callers that store
    // raw unknowns need the original byte sequence, not a normalized tag.
    const noncanonical_unknown = [_]u8{ 0xa0, 0x86, 0x00, 0x01 };
    var unknown_decoded = try person_pb.demo.Person.decode(allocator, &noncanonical_unknown);
    defer unknown_decoded.deinit(allocator);
    std.debug.assert(unknown_decoded.unknownFieldCount() == 1);
    std.debug.assert(std.mem.eql(u8, unknown_decoded.unknownFields()[0], &noncanonical_unknown));
    const unknown_roundtrip = try unknown_decoded.encode(allocator);
    defer allocator.free(unknown_roundtrip);
    std.debug.assert(std.mem.eql(u8, unknown_roundtrip, &noncanonical_unknown));

    const json = try decoded.jsonStringifyAllocWithOptions(allocator, .{
        .preserve_proto_field_names = true,
        .always_print_primitive_fields = true,
    });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"scores\":[10,20]") != null);

    // Protobuf JSON allows unquoted exponent spellings for integer tokens when
    // the represented value is integral and in range. Keeping this in the
    // public generated-type example guards the same compatibility surface that
    // C++ and Go protobuf expose for generated messages.
    var exponent_scalars = try person_pb.demo.ScalarMix.jsonParse(allocator,
        \\{"count":1.2345e4,"total":9.87654321e9,"delta":-3.21e2,"ids":[1e0,1.27e2,1.28e2]}
    );
    defer exponent_scalars.deinit(allocator);
    std.debug.assert(exponent_scalars.count == 12345);
    std.debug.assert(exponent_scalars.total == 9_876_543_210);
    std.debug.assert(exponent_scalars.delta == -321);
    std.debug.assert(std.mem.eql(u64, exponent_scalars.ids, &.{ 1, 127, 128 }));

    var parsed = try person_pb.demo.Person.parseText(allocator,
        \\id: 8
        \\name: "Text"
        \\scores: 30
        \\counts {
        \\  key: "blue"
        \\  value: 3
        \\}
    );
    defer parsed.deinit(allocator);
    std.debug.assert(parsed.id == 8);
}

// Keep the runtime import visibly used in the example even though the generated
// file itself imports pbz.
comptime {
    _ = pbz;
}
