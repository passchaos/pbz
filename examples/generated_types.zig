const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // This is the C++/Rust-style flow: import the generated Zig module and use
    // the generated concrete message type directly.
    var person = person_pb.Person.init();
    defer person.deinit(allocator);

    person.setField_id(7);
    person.setField_name("Zig");
    try person.appendField_scores(allocator, 10);
    try person.appendField_scores(allocator, 20);

    try person.appendField_counts(allocator, .{ .key = "red", .value = 1 });
    try person.appendField_counts(allocator, .{ .key = "red", .value = 2 }); // replaces red
    std.debug.assert(person.counts.len == 1);
    std.debug.assert(person.counts[0].value == 2);

    const bytes = try person.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var decoded = try person_pb.Person.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    std.debug.assert(decoded.getOrDefaultField_id() == 7);
    std.debug.assert(std.mem.eql(u8, decoded.getOrDefaultField_name(), "Zig"));

    const json = try decoded.jsonStringifyAllocWithOptions(allocator, .{
        .preserve_proto_field_names = true,
        .always_print_primitive_fields = true,
    });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"scores\":[10,20]") != null);

    var parsed = try person_pb.Person.parseText(allocator,
        \\id: 8
        \\name: "Text"
        \\scores: 30
        \\counts {
        \\  key: "blue"
        \\  value: 3
        \\}
    );
    defer parsed.deinit(allocator);
    std.debug.assert(parsed.getOrDefaultField_id() == 8);
}

// Keep the runtime import visibly used in the example even though the generated
// file itself imports pbz.
comptime {
    _ = pbz;
}
