const std = @import("std");
const schema = @import("../schema.zig");
const dynamic = @import("../dynamic.zig");
const registry_mod = @import("../registry.zig");
const Reflection = @import("../reflect.zig").Reflection;

pub fn lastValue(message_value: *const dynamic.DynamicMessage, field: *const schema.FieldDescriptor) ?dynamic.Value {
    const field_value = message_value.getByNumber(field.number) orelse return null;
    if (field_value.values.items.len == 0) return null;
    return field_value.values.items[field_value.values.items.len - 1];
}

pub fn valueMatchesScalar(scalar: schema.ScalarType, value: dynamic.Value) bool {
    return switch (scalar) {
        .double => value == .double,
        .float => value == .float,
        .int32 => value == .int32,
        .int64 => value == .int64,
        .uint32 => value == .uint32,
        .uint64 => value == .uint64,
        .sint32 => value == .sint32,
        .sint64 => value == .sint64,
        .fixed32 => value == .fixed32,
        .fixed64 => value == .fixed64,
        .sfixed32 => value == .sfixed32,
        .sfixed64 => value == .sfixed64,
        .bool => value == .boolean,
        .string => value == .string,
        .bytes => value == .bytes,
    };
}

pub fn importKindCount(file: *const schema.FileDescriptor, kind: schema.Import.Kind) usize {
    var count: usize = 0;
    for (file.imports.items) |import| {
        if (import.kind == kind) count += 1;
    }
    return count;
}

pub fn importOfKindAt(file: *const schema.FileDescriptor, kind: schema.Import.Kind, index: usize) ?schema.Import {
    var seen: usize = 0;
    for (file.imports.items) |import| {
        if (import.kind != kind) continue;
        if (seen == index) return import;
        seen += 1;
    }
    return null;
}

pub fn messageDirectlyContainsField(message: *const schema.MessageDescriptor, target: *const schema.FieldDescriptor) bool {
    for (message.fields.items) |*field| {
        if (field == target) return true;
    }
    return false;
}

pub fn messageDirectlyContainsOneof(message: *const schema.MessageDescriptor, target: *const schema.OneofDescriptor) bool {
    for (message.oneofs.items) |*oneof| {
        if (oneof == target) return true;
    }
    return false;
}

pub fn messageDirectlyContainsExtensionRange(message: *const schema.MessageDescriptor, target: *const schema.ExtensionRange) bool {
    for (message.extension_ranges.items) |*range| {
        if (range == target) return true;
    }
    return false;
}

pub fn containingMessageForMessage(file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor) ?*const schema.MessageDescriptor {
    for (file.messages.items) |*message| {
        if (message == target) return null;
        if (containingMessageForMessageInMessage(message, target)) |parent| return parent;
    }
    return null;
}

pub fn containingMessageForMessageInMessage(parent: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor) ?*const schema.MessageDescriptor {
    for (parent.messages.items) |*nested| {
        if (nested == target) return parent;
        if (containingMessageForMessageInMessage(nested, target)) |ancestor| return ancestor;
    }
    return null;
}

pub fn containingMessageForEnum(file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor) ?*const schema.MessageDescriptor {
    for (file.enums.items) |*enum_desc| {
        if (enum_desc == target) return null;
    }
    for (file.messages.items) |*message| {
        if (containingMessageForEnumInMessage(message, target)) |parent| return parent;
    }
    return null;
}

pub fn containingMessageForEnumInMessage(parent: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor) ?*const schema.MessageDescriptor {
    for (parent.enums.items) |*enum_desc| {
        if (enum_desc == target) return parent;
    }
    for (parent.messages.items) |*nested| {
        if (containingMessageForEnumInMessage(nested, target)) |ancestor| return ancestor;
    }
    return null;
}

pub fn extensionScopeMessageInFile(file: *const schema.FileDescriptor, target: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (file.extensions.items) |*field| {
        if (field == target) return null;
    }
    for (file.messages.items) |*message| {
        if (extensionScopeMessageInMessage(message, target)) |scope| return scope;
    }
    return null;
}

pub fn extensionScopeMessageInMessage(message: *const schema.MessageDescriptor, target: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (message.extensions.items) |*field| {
        if (field == target) return message;
    }
    for (message.messages.items) |*nested| {
        if (extensionScopeMessageInMessage(nested, target)) |scope| return scope;
    }
    return null;
}

pub fn fieldLookupScope(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, buf: *[512]u8) ?[]const u8 {
    if (field.extendee != null) return extensionScope(file, field);
    return messageScope(file, current, buf) orelse if (file.package.len != 0) file.package else null;
}

pub fn extensionScope(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.full_name) |full_name| {
        const normalized = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
        if (std.mem.lastIndexOfScalar(u8, normalized, '.')) |idx| return normalized[0..idx];
        if (std.mem.startsWith(u8, full_name, ".")) return null;
    }
    return if (file.package.len != 0) file.package else null;
}

pub fn messageScope(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, buf: *[512]u8) ?[]const u8 {
    for (file.messages.items) |*msg_desc| {
        if (msg_desc == current) return formatMessageScope(file.package, msg_desc.name, buf);
        if (messageScopeInMessage(file.package, msg_desc.name, msg_desc, current, buf)) |path| return path;
    }
    return null;
}

pub fn messageScopeInMessage(package: []const u8, prefix: []const u8, scope_message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor, buf: *[512]u8) ?[]const u8 {
    for (scope_message.messages.items) |*nested| {
        var path_buf: [512]u8 = undefined;
        const nested_path = std.fmt.bufPrint(&path_buf, "{s}.{s}", .{ prefix, nested.name }) catch return null;
        if (nested == target) return formatMessageScope(package, nested_path, buf);
        if (messageScopeInMessage(package, nested_path, nested, target, buf)) |path| return path;
    }
    return null;
}

pub fn formatMessageScope(package: []const u8, path: []const u8, buf: *[512]u8) ?[]const u8 {
    if (package.len == 0) return std.fmt.bufPrint(buf, "{s}", .{path}) catch null;
    return std.fmt.bufPrint(buf, "{s}.{s}", .{ package, path }) catch null;
}

pub fn messageFullNameInFileAlloc(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor) std.mem.Allocator.Error!?[]u8 {
    for (file.messages.items) |*message_desc| {
        if (message_desc == target) return try qualifyFileSymbolAlloc(allocator, file, message_desc.name);
        if (try messageFullNameInMessageAlloc(allocator, file, message_desc.name, message_desc, target)) |full_name| return full_name;
    }
    return null;
}

pub fn messageFullNameInMessageAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    parent_path: []const u8,
    parent: *const schema.MessageDescriptor,
    target: *const schema.MessageDescriptor,
) std.mem.Allocator.Error!?[]u8 {
    for (parent.messages.items) |*nested| {
        const nested_path = try joinNameAlloc(allocator, parent_path, nested.name);
        defer allocator.free(nested_path);
        if (nested == target) return try qualifyFileSymbolAlloc(allocator, file, nested_path);
        if (try messageFullNameInMessageAlloc(allocator, file, nested_path, nested, target)) |full_name| return full_name;
    }
    return null;
}

pub fn enumFullNameInFileAlloc(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor) std.mem.Allocator.Error!?[]u8 {
    for (file.enums.items) |*enum_desc| {
        if (enum_desc == target) return try qualifyFileSymbolAlloc(allocator, file, enum_desc.name);
    }
    for (file.messages.items) |*message_desc| {
        if (try enumFullNameInMessageAlloc(allocator, file, message_desc.name, message_desc, target)) |full_name| return full_name;
    }
    return null;
}

pub fn enumFullNameInMessageAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    parent_path: []const u8,
    parent: *const schema.MessageDescriptor,
    target: *const schema.EnumDescriptor,
) std.mem.Allocator.Error!?[]u8 {
    for (parent.enums.items) |*enum_desc| {
        const enum_path = try joinNameAlloc(allocator, parent_path, enum_desc.name);
        defer allocator.free(enum_path);
        if (enum_desc == target) return try qualifyFileSymbolAlloc(allocator, file, enum_path);
    }
    for (parent.messages.items) |*nested| {
        const nested_path = try joinNameAlloc(allocator, parent_path, nested.name);
        defer allocator.free(nested_path);
        if (try enumFullNameInMessageAlloc(allocator, file, nested_path, nested, target)) |full_name| return full_name;
    }
    return null;
}

pub fn qualifyFileSymbolAlloc(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8) std.mem.Allocator.Error![]u8 {
    const absolute = std.mem.startsWith(u8, name, ".");
    const normalized = if (absolute) name[1..] else name;
    if (absolute or file.package.len == 0 or startsWithPackage(file.package, normalized)) return try allocator.dupe(u8, normalized);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ file.package, normalized });
}

pub fn startsWithPackage(package: []const u8, name: []const u8) bool {
    return name.len > package.len and
        std.mem.eql(u8, name[0..package.len], package) and
        name[package.len] == '.';
}

pub fn joinNameAlloc(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (prefix.len == 0) return try allocator.dupe(u8, name);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, name });
}

pub fn exerciseReflectionCleanup(allocator: std.mem.Allocator, registry: *const registry_mod.Registry) !void {
    const refl = Reflection.init(allocator, registry);
    var msg = try refl.newMessage("demo.Person");
    defer msg.deinit();

    try refl.setString(&msg, "name", "Zig");
    try refl.addString(&msg, "tags", "one");
    try refl.putStringInt32MapEntry(&msg, "counts", "red", 1);

    try std.testing.expectEqualStrings("Zig", try refl.getString(&msg, "name"));
    try std.testing.expectEqual(@as(usize, 1), try refl.repeatedLen(&msg, "tags"));
    try std.testing.expectEqual(@as(usize, 1), msg.get("counts").?.values.items.len);
}
