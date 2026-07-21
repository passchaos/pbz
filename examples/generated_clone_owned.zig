const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

const demo = person_pb.demo;

fn audit(actor: []const u8, at_unix: i64) demo.Complex.Audit {
    var out = demo.Complex.Audit.init();
    out.actor = actor;
    out.at_unix = at_unix;
    return out;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generated cloneOwned should deep-copy arena/heap-owned slices, maps,
    // nested messages, oneof payloads, and raw unknown fields.  The clone must
    // survive source deinit and source mutation, matching ownership handoff
    // patterns expected from C++/Rust-style generated objects.
    var source = demo.Complex.init();
    source.id = 42;
    source.audit = try audit("source", 1).cloneOwned(allocator);
    const history = try allocator.alloc(demo.Complex.Audit, 1);
    history[0] = try audit("history", 2).cloneOwned(allocator);
    source.history = history;
    try source.audits.put(allocator, "latest", try audit("map", 3).cloneOwned(allocator));
    source.subject = .{ .audit_subject = try audit("oneof", 4).cloneOwned(allocator) };

    var raw = pbz.Writer.init(allocator);
    defer raw.deinit();
    try raw.writeString(100, "unknown");
    try source.appendUnknownRaw(allocator, raw.slice());

    var cloned = try source.cloneOwned(allocator);
    defer cloned.deinit(allocator);

    source.id = 0;
    if (source.audit) |*value| value.actor = "mutated";
    if (source.history.len != 0) @constCast(source.history)[0].actor = "mutated-history";
    if (source.audits.getPtr("latest")) |value| value.actor = "mutated-map";
    switch (source.subject) {
        .audit_subject => |*value| value.actor = "mutated-oneof",
        else => {},
    }
    source.clearUnknownFields(allocator);
    source.deinit(allocator);

    try std.testing.expectEqual(@as(i32, 42), cloned.id);
    try std.testing.expectEqualStrings("source", cloned.audit.?.actor);
    try std.testing.expectEqualStrings("history", cloned.history[0].actor);
    try std.testing.expectEqualStrings("map", cloned.audits.get("latest").?.actor);
    switch (cloned.subject) {
        .audit_subject => |value| try std.testing.expectEqualStrings("oneof", value.actor),
        else => return error.UnexpectedOneof,
    }
    try std.testing.expectEqual(@as(usize, 1), cloned.unknownFieldCount());
    try std.testing.expectEqualSlices(u8, raw.slice(), cloned.unknownFields()[0]);

    const encoded = try cloned.encodeInitialized(allocator);
    defer allocator.free(encoded);
    var decoded = try demo.Complex.decodeOwnedInitialized(allocator, encoded);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualStrings("source", decoded.audit.?.actor);
    try std.testing.expect(try decoded.hasUnknownFieldNumber(100));
}

comptime {
    _ = pbz;
}
