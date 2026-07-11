const std = @import("std");
const pbz = @import("pbz");
const app_pb = @import("generated/imported_app.pb.zig");

const app = app_pb.demo.imports.app;
const common = app_pb.imports.imported_common_proto.demo.imports.common;
const Profile = common.Profile;

fn profile(id: i32, name: []const u8) Profile {
    var out = Profile.init();
    out.id = id;
    out.name = name;
    return out;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // The generated app module imports imported_common.pb.zig and exposes the
    // imported file under app_pb.imports.imported_common_proto.
    std.debug.assert(std.mem.eql(u8, app_pb.proto_package, "demo.imports.app"));
    std.debug.assert(std.mem.eql(u8, app_pb.imports.imported_common_proto_path, "imported_common.proto"));
    std.debug.assert(app.Request.primary_field.type_ref == Profile);
    std.debug.assert(app.Request.history_field.type_ref == Profile);
    std.debug.assert(app.Request.by_name_field.map_value_type_ref == Profile);
    std.debug.assert(app.Request.chosen_field.type_ref == Profile);

    var primary = profile(1, "primary");
    defer primary.deinit(allocator);
    var first = profile(2, "first");
    defer first.deinit(allocator);
    var old_named = profile(3, "old-named");
    defer old_named.deinit(allocator);
    var final_named = profile(4, "final-named");
    defer final_named.deinit(allocator);
    var chosen = profile(5, "chosen");
    defer chosen.deinit(allocator);

    var request = app.Request.init();
    defer request.deinit(allocator);
    request.primary = try primary.cloneOwned(allocator);

    const history = try allocator.alloc(Profile, 1);
    history[0] = try first.cloneOwned(allocator);
    request.history = history;

    // Direct struct fields stay natural Zig fields, while generated storage is
    // typed across imports for singular, repeated, map values, and oneof arms.
    try request.by_name.put(allocator, "selected", try old_named.cloneOwned(allocator));
    {
        var owned = try final_named.cloneOwned(allocator);
        errdefer owned.deinit(allocator);
        const old = try request.by_name.fetchPut(allocator, "selected", owned);
        if (old) |entry| {
            var old_value = entry.value;
            old_value.deinit(allocator);
        }
    }
    request.selected = .{ .chosen = try chosen.cloneOwned(allocator) };

    const bytes = try request.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var decoded = try app.Request.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    std.debug.assert(decoded.primary.?.id == 1);
    std.debug.assert(decoded.history.len == 1);
    std.debug.assert(std.mem.eql(u8, decoded.history[0].name, "first"));
    std.debug.assert(decoded.by_name.count() == 1);
    std.debug.assert(std.mem.eql(u8, (decoded.by_name.get("selected") orelse return error.MissingByName).name, "final-named"));
    switch (decoded.selected) {
        .chosen => |selected| std.debug.assert(std.mem.eql(u8, selected.name, "chosen")),
        else => return error.UnexpectedOneof,
    }

    const json = try decoded.jsonStringifyAllocWithOptions(allocator, .{ .preserve_proto_field_names = true });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"primary\":") != null);
    std.debug.assert(std.mem.indexOf(u8, json, "\"by_name\":") != null);
    std.debug.assert(std.mem.indexOf(u8, json, "\"chosen\":") != null);
    var json_roundtrip = try app.Request.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    std.debug.assert(json_roundtrip.by_name.count() == 1);
    std.debug.assert(std.mem.eql(u8, (json_roundtrip.by_name.get("selected") orelse return error.MissingByName).name, "final-named"));

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    std.debug.assert(std.mem.indexOf(u8, text, "primary {") != null);
    std.debug.assert(std.mem.indexOf(u8, text, "by_name {") != null);
    std.debug.assert(std.mem.indexOf(u8, text, "chosen {") != null);
    var text_roundtrip = try app.Request.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    switch (text_roundtrip.selected) {
        .chosen => |selected| std.debug.assert(selected.id == 5),
        else => return error.UnexpectedOneof,
    }
}

comptime {
    _ = pbz;
}
