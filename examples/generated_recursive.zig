const std = @import("std");
const pbz = @import("pbz");
const recursive_pb = @import("generated/recursive.pb.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const Node = recursive_pb.demo.recursive.Node;

    var leaf = Node.init();
    defer leaf.deinit(allocator);
    const leaf_payload = try leaf.encode(allocator);
    defer allocator.free(leaf_payload);

    var root = Node.init();
    defer root.deinit(allocator);

    // Singular self-recursive fields cannot be stored by value in Zig; generated
    // code keeps their raw payload plus presence.
    root.child = leaf_payload;
    root.has_child = true;
    var decoded_child = try Node.decode(allocator, root.child);
    defer decoded_child.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), decoded_child.unknownFieldCount());

    var middle = Node.init();
    defer middle.deinit(allocator);
    const middle_children = try allocator.alloc(Node, 1);
    middle_children[0] = try leaf.cloneOwned(allocator);
    middle.children = middle_children;

    const root_children = try allocator.alloc(Node, 1);
    root_children[0] = try middle.cloneOwned(allocator);
    root.children = root_children;

    const encoded = try root.encode(allocator);
    defer allocator.free(encoded);
    var decoded = try Node.decode(allocator, encoded);
    defer decoded.deinit(allocator);
    try std.testing.expect(decoded.has_child);
    try std.testing.expectEqual(@as(usize, 1), decoded.children.len);

    var limited_reader = pbz.Reader.init(encoded);
    limited_reader.recursion_limit = 1;
    try std.testing.expectError(error.RecursionLimitExceeded, Node.decodeFromReader(allocator, &limited_reader));
}
