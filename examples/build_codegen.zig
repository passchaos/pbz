const std = @import("std");
const person_pb = @import("person_pb");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var person = person_pb.demo.Person.init();
    defer person.deinit(allocator);

    person.id = 42;
    person.name = "build.zig";
    person.scores = try allocator.dupe(i32, &.{ 1, 2, 3 });
    try person.counts.put(allocator, "generated", 1);

    const bytes = try person.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var decoded = try person_pb.demo.Person.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);

    std.debug.assert(decoded.id == 42);
    std.debug.assert(std.mem.eql(u8, decoded.name, "build.zig"));
    std.debug.assert(decoded.counts.get("generated").? == 1);
}
