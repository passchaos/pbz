const std = @import("std");
const schema = @import("schema.zig");

pub const TypeKind = enum { message, enumeration };

pub const TypeRef = union(TypeKind) {
    message: *const schema.MessageDescriptor,
    enumeration: *const schema.EnumDescriptor,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayList(*const schema.FileDescriptor) = .empty,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        self.files.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addFile(self: *Registry, file: *const schema.FileDescriptor) std.mem.Allocator.Error!void {
        try self.files.append(self.allocator, file);
    }

    pub fn findMessage(self: *const Registry, name: []const u8, scope: ?[]const u8) ?*const schema.MessageDescriptor {
        if (self.findType(name, scope)) |type_ref| switch (type_ref) {
            .message => |message| return message,
            .enumeration => return null,
        };
        return null;
    }

    pub fn findEnum(self: *const Registry, name: []const u8, scope: ?[]const u8) ?*const schema.EnumDescriptor {
        if (self.findType(name, scope)) |type_ref| switch (type_ref) {
            .message => return null,
            .enumeration => |enumeration| return enumeration,
        };
        return null;
    }

    pub fn findType(self: *const Registry, name: []const u8, scope: ?[]const u8) ?TypeRef {
        if (std.mem.startsWith(u8, name, ".")) return self.findAbsolute(name[1..]);
        if (scope) |scope_name| {
            var current = scope_name;
            while (true) {
                var buf: [512]u8 = undefined;
                if (current.len + 1 + name.len <= buf.len) {
                    const candidate = std.fmt.bufPrint(&buf, "{s}.{s}", .{ current, name }) catch unreachable;
                    if (self.findAbsolute(candidate)) |found| return found;
                }
                if (std.mem.lastIndexOfScalar(u8, current, '.')) |idx| {
                    current = current[0..idx];
                } else break;
            }
        }
        return self.findAbsolute(name) orelse self.findByLeaf(name);
    }

    fn findAbsolute(self: *const Registry, full_name: []const u8) ?TypeRef {
        const normalized = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
        for (self.files.items) |file| {
            if (file.package.len != 0) {
                if (std.mem.startsWith(u8, normalized, file.package) and normalized.len > file.package.len and normalized[file.package.len] == '.') {
                    const rest = normalized[file.package.len + 1 ..];
                    if (findInFile(file, rest)) |found| return found;
                }
            }
            if (findInFile(file, normalized)) |found| return found;
        }
        return null;
    }

    fn findByLeaf(self: *const Registry, leaf: []const u8) ?TypeRef {
        for (self.files.items) |file| {
            for (file.messages.items) |*message| {
                if (findInMessageByLeaf(message, leaf)) |found| return found;
            }
            for (file.enums.items) |*enumeration| {
                if (std.mem.eql(u8, enumeration.name, leaf)) return .{ .enumeration = enumeration };
            }
        }
        return null;
    }
};

fn findInFile(file: *const schema.FileDescriptor, relative_name: []const u8) ?TypeRef {
    if (relative_name.len == 0) return null;
    const head, const tail = splitFirst(relative_name);
    for (file.messages.items) |*message| {
        if (std.mem.eql(u8, message.name, head)) {
            if (tail.len == 0) return .{ .message = message };
            return findInMessage(message, tail);
        }
    }
    if (tail.len == 0) {
        for (file.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, head)) return .{ .enumeration = enumeration };
        }
    }
    return null;
}

fn findInMessage(message: *const schema.MessageDescriptor, relative_name: []const u8) ?TypeRef {
    const head, const tail = splitFirst(relative_name);
    for (message.messages.items) |*nested| {
        if (std.mem.eql(u8, nested.name, head)) {
            if (tail.len == 0) return .{ .message = nested };
            return findInMessage(nested, tail);
        }
    }
    if (tail.len == 0) {
        for (message.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, head)) return .{ .enumeration = enumeration };
        }
    }
    return null;
}

fn findInMessageByLeaf(message: *const schema.MessageDescriptor, leaf: []const u8) ?TypeRef {
    if (std.mem.eql(u8, message.name, leaf)) return .{ .message = message };
    for (message.messages.items) |*nested| {
        if (findInMessageByLeaf(nested, leaf)) |found| return found;
    }
    for (message.enums.items) |*enumeration| {
        if (std.mem.eql(u8, enumeration.name, leaf)) return .{ .enumeration = enumeration };
    }
    return null;
}

fn splitFirst(name: []const u8) struct { []const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, name, '.')) |idx| return .{ name[0..idx], name[idx + 1 ..] };
    return .{ name, "" };
}

test "registry resolves absolute relative nested and imported types" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.common;
        \\message User { message Profile { string name = 1; } enum Role { UNKNOWN = 0; ADMIN = 1; } }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.app;
        \\import "common.proto";
        \\message Request { demo.common.User user = 1; .demo.common.User.Profile profile = 2; }
    );
    defer app.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    try std.testing.expect(registry.findMessage(".demo.common.User", null) != null);
    try std.testing.expect(registry.findMessage("User.Profile", "demo.common") != null);
    try std.testing.expect(registry.findEnum("Role", "demo.common.User") != null);
    try std.testing.expect(registry.findMessage("Request", "demo.app") != null);
    try std.testing.expect(registry.findMessage("demo.common.User", "demo.app.Request") != null);
}
