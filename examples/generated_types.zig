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

    const json = try decoded.jsonStringifyAllocWithOptions(allocator, .{
        .preserve_proto_field_names = true,
        .always_print_primitive_fields = true,
    });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"scores\":[10,20]") != null);

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
