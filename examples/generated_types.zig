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
