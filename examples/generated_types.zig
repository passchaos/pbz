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
    person.counts = try allocator.dupe(person_pb.demo.Person.countsEntry, &.{
        .{ .key = "red", .value = 1 },
    });

    // Map replacement semantics are still available through decode/merge paths;
    // direct field assignment stays ordinary Zig struct assignment.
    var other = person_pb.demo.Person.init();
    defer other.deinit(allocator);
    other.counts = try allocator.dupe(person_pb.demo.Person.countsEntry, &.{
        .{ .key = "red", .value = 2 },
    });
    try person.mergeFrom(allocator, other);
    std.debug.assert(person.counts.len == 1);
    std.debug.assert(person.counts[0].value == 2);

    const bytes = try person.encodeInitialized(allocator);
    defer allocator.free(bytes);

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
