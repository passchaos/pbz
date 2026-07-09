const std = @import("std");
const schema = @import("schema.zig");

pub const TypeKind = enum { message, enumeration };

pub const Error = std.mem.Allocator.Error || error{ DuplicateSymbol, InvalidExtensionDeclaration };

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

    pub fn addFile(self: *Registry, file: *const schema.FileDescriptor) Error!void {
        try self.validateNoTypeConflicts(file);
        try self.validateNoExtensionConflicts(file);
        try self.files.append(self.allocator, file);
        errdefer self.files.items.len -= 1;
        try self.validateExtensionDeclarations();
    }

    fn validateNoTypeConflicts(self: *const Registry, file: *const schema.FileDescriptor) Error!void {
        for (file.messages.items) |*message| try self.validateMessageType(file.package, message);
        for (file.enums.items) |*enumeration| {
            const full_name = try qualifiedTypeName(self.allocator, file.package, enumeration.name);
            defer self.allocator.free(full_name);
            if (self.findAbsolute(full_name) != null) return error.DuplicateSymbol;
        }
    }

    fn validateMessageType(self: *const Registry, prefix: []const u8, message: *const schema.MessageDescriptor) Error!void {
        const full_name = try qualifiedTypeName(self.allocator, prefix, message.name);
        defer self.allocator.free(full_name);
        if (self.findAbsolute(full_name) != null) return error.DuplicateSymbol;
        for (message.messages.items) |*nested| try self.validateMessageType(full_name, nested);
        for (message.enums.items) |*enumeration| {
            const enum_name = try qualifiedTypeName(self.allocator, full_name, enumeration.name);
            defer self.allocator.free(enum_name);
            if (self.findAbsolute(enum_name) != null) return error.DuplicateSymbol;
        }
    }

    fn validateNoExtensionConflicts(self: *const Registry, file: *const schema.FileDescriptor) Error!void {
        for (file.extensions.items) |*field| try self.validateExtensionConflict(file, field);
        for (file.messages.items) |*message| try self.validateMessageExtensionConflicts(file, message);
    }

    fn validateMessageExtensionConflicts(self: *const Registry, file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
        for (message.extensions.items) |*field| try self.validateExtensionConflict(file, field);
        for (message.messages.items) |*nested| try self.validateMessageExtensionConflicts(file, nested);
    }

    fn validateExtensionConflict(self: *const Registry, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) Error!void {
        const extendee = field.extendee orelse return;
        if (self.findExtension(extendee, field.number) != null) return error.DuplicateSymbol;
        for (self.files.items) |existing_file| {
            for (existing_file.extensions.items) |*existing| {
                if (extensionsConflictByName(file.package, field, existing_file.package, existing)) return error.DuplicateSymbol;
            }
            for (existing_file.messages.items) |*message| {
                if (extensionConflictsByNameInMessage(file.package, field, existing_file.package, message)) return error.DuplicateSymbol;
            }
        }
    }

    fn validateExtensionDeclarations(self: *const Registry) Error!void {
        for (self.files.items) |file| {
            for (file.messages.items) |*message| try self.validateMessageExtensionRangeDeclarations(message);
        }
        for (self.files.items) |file| {
            for (file.extensions.items) |*field| try self.validateExtensionAgainstDeclaration(field);
            for (file.messages.items) |*message| try self.validateMessageExtensionsAgainstDeclarations(message);
        }
    }

    fn validateMessageExtensionRangeDeclarations(self: *const Registry, message: *const schema.MessageDescriptor) Error!void {
        for (message.extension_ranges.items) |range| try validateExtensionRangeDeclarationSet(range);
        for (message.messages.items) |*nested| try self.validateMessageExtensionRangeDeclarations(nested);
    }

    fn validateMessageExtensionsAgainstDeclarations(self: *const Registry, message: *const schema.MessageDescriptor) Error!void {
        for (message.extensions.items) |*field| try self.validateExtensionAgainstDeclaration(field);
        for (message.messages.items) |*nested| try self.validateMessageExtensionsAgainstDeclarations(nested);
    }

    fn validateExtensionAgainstDeclaration(self: *const Registry, field: *const schema.FieldDescriptor) Error!void {
        const extendee_name = field.extendee orelse return;
        const extendee = self.findMessage(extendee_name, null) orelse return;
        for (extendee.extension_ranges.items) |range| {
            const end = range.end orelse std.math.maxInt(i64);
            if (field.number >= range.start and field.number < end) {
                try validateExtensionFieldDeclaration(field, range);
                return;
            }
        }
        return error.InvalidExtensionDeclaration;
    }

    pub fn findExtensionByName(self: *const Registry, extendee: []const u8, name: []const u8) ?*const schema.FieldDescriptor {
        const normalized = normalizeName(extendee);
        const normalized_name = normalizeName(name);
        for (self.files.items) |file| {
            for (file.extensions.items) |*field| {
                if (field.extendee != null and namesMatch(field.extendee.?, normalized) and schema.extensionNameMatches(file.package, field, normalized_name)) return field;
            }
            for (file.messages.items) |*message| {
                if (findExtensionByNameInMessage(file.package, message, normalized, normalized_name)) |field| return field;
            }
        }
        return null;
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

    pub fn findExtension(self: *const Registry, extendee: []const u8, number: @import("wire.zig").FieldNumber) ?*const schema.FieldDescriptor {
        const normalized = normalizeName(extendee);
        for (self.files.items) |file| {
            for (file.extensions.items) |*field| {
                if (field.number == number and field.extendee != null and namesMatch(field.extendee.?, normalized)) return field;
            }
            for (file.messages.items) |*message| {
                if (findExtensionInMessage(message, normalized, number)) |field| return field;
            }
        }
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

fn validateExtensionRangeDeclarationSet(range: schema.ExtensionRange) Error!void {
    if (range.declarations.items.len != 0 and range.verification == .unverified) return error.InvalidExtensionDeclaration;
    const end = range.end orelse std.math.maxInt(i64);
    for (range.declarations.items, 0..) |declaration, i| {
        if (declaration.number <= 0) return error.InvalidExtensionDeclaration;
        if (declaration.number < range.start or declaration.number >= end) return error.InvalidExtensionDeclaration;
        try validateExtensionDeclarationShape(declaration);
        for (range.declarations.items[i + 1 ..]) |other| {
            if (declaration.number == other.number) return error.InvalidExtensionDeclaration;
            if (declaration.full_name.len != 0 and other.full_name.len != 0 and std.mem.eql(u8, declaration.full_name, other.full_name)) return error.InvalidExtensionDeclaration;
        }
    }
}

fn validateExtensionDeclarationShape(declaration: schema.ExtensionDeclaration) Error!void {
    const has_full_name = declaration.full_name.len != 0;
    const has_type = declaration.type_name.len != 0;
    if (!has_full_name or !has_type) {
        if (has_full_name != has_type or !declaration.reserved) return error.InvalidExtensionDeclaration;
        return;
    }
    if (!schema.declarationSymbolIsQualified(declaration.full_name)) return error.InvalidExtensionDeclaration;
    if (!extensionDeclarationTypeNameValid(declaration.type_name)) return error.InvalidExtensionDeclaration;
}

fn extensionDeclarationTypeNameValid(type_name: []const u8) bool {
    return schema.declarationTypeNameIsScalar(type_name) or schema.declarationSymbolIsQualified(type_name);
}

fn validateExtensionFieldDeclaration(field: *const schema.FieldDescriptor, range: schema.ExtensionRange) Error!void {
    var matching_declaration: ?schema.ExtensionDeclaration = null;
    for (range.declarations.items) |declaration| {
        if (declaration.number == @as(i32, @intCast(field.number))) matching_declaration = declaration;
    }
    const declaration = matching_declaration orelse {
        if (range.verification == .declaration) return error.InvalidExtensionDeclaration;
        return;
    };
    if (declaration.reserved) return error.InvalidExtensionDeclaration;
    if (declaration.full_name.len != 0 and !namesMatch(declaration.full_name, schema.extensionFullName(field))) return error.InvalidExtensionDeclaration;
    if (declaration.repeated and field.cardinality != .repeated) return error.InvalidExtensionDeclaration;
    if (!declaration.repeated and field.cardinality == .repeated) return error.InvalidExtensionDeclaration;
    if (declaration.type_name.len != 0 and !extensionTypeMatches(field, declaration.type_name)) return error.InvalidExtensionDeclaration;
}

fn qualifiedTypeName(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (prefix.len == 0) return try allocator.dupe(u8, name);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, name });
}

fn findExtensionByNameInMessage(package: []const u8, message: *const schema.MessageDescriptor, extendee: []const u8, name: []const u8) ?*const schema.FieldDescriptor {
    for (message.extensions.items) |*field| {
        if (field.extendee != null and namesMatch(field.extendee.?, extendee) and schema.extensionNameMatches(package, field, name)) return field;
    }
    for (message.messages.items) |*nested| {
        if (findExtensionByNameInMessage(package, nested, extendee, name)) |field| return field;
    }
    return null;
}

fn findExtensionInMessage(message: *const schema.MessageDescriptor, extendee: []const u8, number: @import("wire.zig").FieldNumber) ?*const schema.FieldDescriptor {
    for (message.extensions.items) |*field| {
        if (field.number == number and field.extendee != null and namesMatch(field.extendee.?, extendee)) return field;
    }
    for (message.messages.items) |*nested| {
        if (findExtensionInMessage(nested, extendee, number)) |field| return field;
    }
    return null;
}

fn extensionsConflictByName(a_package: []const u8, a: *const schema.FieldDescriptor, b_package: []const u8, b: *const schema.FieldDescriptor) bool {
    const a_extendee = a.extendee orelse return false;
    const b_extendee = b.extendee orelse return false;
    return namesMatch(a_extendee, b_extendee) and schema.extensionSymbolsEqualWithPackages(a_package, a, b_package, b);
}

fn extensionConflictsByNameInMessage(field_package: []const u8, field: *const schema.FieldDescriptor, message_package: []const u8, message: *const schema.MessageDescriptor) bool {
    for (message.extensions.items) |*other| {
        if (extensionsConflictByName(field_package, field, message_package, other)) return true;
    }
    for (message.messages.items) |*nested| {
        if (extensionConflictsByNameInMessage(field_package, field, message_package, nested)) return true;
    }
    return false;
}

fn normalizeName(name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
}

fn namesMatch(a: []const u8, b: []const u8) bool {
    const na = normalizeName(a);
    const nb = normalizeName(b);
    return std.mem.eql(u8, na, nb) or std.mem.endsWith(u8, na, nb) or std.mem.endsWith(u8, nb, na);
}

fn extensionTypeMatches(field: *const schema.FieldDescriptor, declared_type: []const u8) bool {
    return switch (field.kind) {
        .message, .enumeration, .group => |type_name| namesMatch(declared_type, type_name),
        .scalar => |scalar| std.mem.eql(u8, declared_type, schema.scalarTypeName(scalar)),
        .map => false,
    };
}

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

test "registry finds extension fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
        \\message Scope { extend Host { optional string scoped_note = 101; } }
    );
    defer file.deinit();
    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const ext = registry.findExtension(".demo.Host", 100).?;
    try std.testing.expectEqualStrings("note", ext.name);
    const scoped = registry.findExtensionByName(".demo.Host", "demo.Scope.scoped_note").?;
    try std.testing.expectEqual(@as(@import("wire.zig").FieldNumber, 101), scoped.number);
    try std.testing.expectEqualStrings("demo.Scope.scoped_note", scoped.full_name.?);
}

test "registry rejects duplicate type symbols across files" {
    const allocator = std.testing.allocator;
    var first = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message User { message Profile {} }
    );
    defer first.deinit();
    var duplicate_message = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message User {}
    );
    defer duplicate_message.deinit();
    var duplicate_nested = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message User { enum Profile { UNKNOWN = 0; } }
    );
    defer duplicate_nested.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&first);
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_message));
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_nested));
}

test "registry rejects duplicate extension symbols across files" {
    const allocator = std.testing.allocator;
    var first = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
    );
    defer first.deinit();
    var duplicate_number = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend Host { optional int32 other = 100; }
    );
    defer duplicate_number.deinit();
    var duplicate_name = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend Host { optional int32 note = 101; }
    );
    defer duplicate_name.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&first);
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_number));
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_name));
}

test "registry validates cross-file extension declarations" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" },
        \\    verification = DECLARATION
        \\  ];
        \\}
        \\message Ext {}
    );
    defer host.deinit();
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend Host { optional Ext ext = 100; }
    );
    defer extension.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try registry.addFile(&extension);

    var missing_declaration = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend Host { optional Ext other = 101; }
    );
    defer missing_declaration.deinit();
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&missing_declaration));
}

test "registry rejects cross-file extension declaration mismatches" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" repeated: true }
        \\  ];
        \\}
        \\message Ext {}
    );
    defer host.deinit();
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend Host { optional Ext ext = 100; }
    );
    defer extension.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&extension));
}

test "registry rejects invalid extension declarations" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to max [declaration = { number: 100 full_name: ".missing.type" }]; }
    ));
}
