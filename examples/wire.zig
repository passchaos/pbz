const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();

    try writer.writeInt32(1, 123);
    try writer.writeString(2, "zig");
    try writer.writeBool(3, true);

    var saw_id = false;
    var saw_name = false;
    var saw_active = false;
    var reader = pbz.Reader.init(writer.slice());
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => {
                try pbz.Reader.expectWireType(tag, .varint);
                std.debug.assert((try reader.readInt32()) == 123);
                saw_id = true;
            },
            2 => {
                try pbz.Reader.expectWireType(tag, .length_delimited);
                std.debug.assert(std.mem.eql(u8, try reader.readBytes(), "zig"));
                saw_name = true;
            },
            3 => {
                try pbz.Reader.expectWireType(tag, .varint);
                std.debug.assert(try reader.readBool());
                saw_active = true;
            },
            else => try reader.skipValue(tag),
        }
    }
    std.debug.assert(saw_id and saw_name and saw_active);
}
