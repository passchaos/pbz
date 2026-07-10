const std = @import("std");
const schema = @import("schema.zig");

pub const TypeKind = enum { message, enumeration };

pub const Error = std.mem.Allocator.Error || error{ DuplicateSymbol, InvalidExtensionDeclaration, InvalidFieldType };

pub const max_import_chain_depth = 32;

pub const TypeRef = union(TypeKind) {
    message: *const schema.MessageDescriptor,
    enumeration: *const schema.EnumDescriptor,
};

pub const ImportChain = struct {
    paths: [max_import_chain_depth][]const u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const ImportChain) []const []const u8 {
        return self.paths[0..self.len];
    }
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

    pub fn validateLoadedFiles(self: *const Registry) Error!void {
        try self.validateLoadedFileNames();
        try self.validateLoadedTypeConflicts();
        try self.validateLoadedExtensionConflicts();
        try self.validateExtensionDeclarations();
        try self.validateAllFileReferences();
    }

    fn validateLoadedFileNames(self: *const Registry) Error!void {
        for (self.files.items, 0..) |file, i| {
            if (file.name.len == 0) continue;
            for (self.files.items[i + 1 ..]) |other| {
                if (other.name.len != 0 and std.mem.eql(u8, file.name, other.name)) return error.DuplicateSymbol;
            }
        }
    }

    fn validateLoadedTypeConflicts(self: *const Registry) Error!void {
        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();
        var owned_names: std.ArrayList([]u8) = .empty;
        defer {
            for (owned_names.items) |name| self.allocator.free(name);
            owned_names.deinit(self.allocator);
        }
        for (self.files.items) |file| {
            for (file.messages.items) |*message| try self.validateLoadedMessageType(&seen, &owned_names, file.package, message);
            for (file.enums.items) |*enumeration| {
                const full_name = try qualifiedTypeName(self.allocator, file.package, enumeration.name);
                _ = try self.putLoadedTypeName(&seen, &owned_names, full_name);
            }
        }
    }

    fn validateLoadedMessageType(self: *const Registry, seen: *std.StringHashMap(void), owned_names: *std.ArrayList([]u8), prefix: []const u8, message: *const schema.MessageDescriptor) Error!void {
        const full_name = try qualifiedTypeName(self.allocator, prefix, message.name);
        const stored_name = try self.putLoadedTypeName(seen, owned_names, full_name);
        for (message.messages.items) |*nested| try self.validateLoadedMessageType(seen, owned_names, stored_name, nested);
        for (message.enums.items) |*enumeration| {
            const enum_name = try qualifiedTypeName(self.allocator, stored_name, enumeration.name);
            _ = try self.putLoadedTypeName(seen, owned_names, enum_name);
        }
    }

    fn putLoadedTypeName(self: *const Registry, seen: *std.StringHashMap(void), owned_names: *std.ArrayList([]u8), full_name: []u8) Error![]const u8 {
        if (seen.contains(full_name)) {
            self.allocator.free(full_name);
            return error.DuplicateSymbol;
        }
        try owned_names.append(self.allocator, full_name);
        errdefer _ = owned_names.pop();
        try seen.put(full_name, {});
        return full_name;
    }

    const ExtensionRef = struct {
        file: *const schema.FileDescriptor,
        field: *const schema.FieldDescriptor,
    };

    fn validateLoadedExtensionConflicts(self: *const Registry) Error!void {
        var extensions: std.ArrayList(ExtensionRef) = .empty;
        defer extensions.deinit(self.allocator);
        for (self.files.items) |file| {
            for (file.extensions.items) |*field| try extensions.append(self.allocator, .{ .file = file, .field = field });
            for (file.messages.items) |*message| try self.collectLoadedMessageExtensionRefs(file, message, &extensions);
        }
        for (extensions.items, 0..) |extension, i| {
            for (extensions.items[i + 1 ..]) |other| {
                if (extensionsConflictResolved(self, extension.file, extension.field, other.file, other.field)) return error.DuplicateSymbol;
            }
        }
    }

    fn collectLoadedMessageExtensionRefs(self: *const Registry, file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, output: *std.ArrayList(ExtensionRef)) Error!void {
        for (message.extensions.items) |*field| try output.append(self.allocator, .{ .file = file, .field = field });
        for (message.messages.items) |*nested| try self.collectLoadedMessageExtensionRefs(file, nested, output);
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
        var extensions: std.ArrayList(*const schema.FieldDescriptor) = .empty;
        defer extensions.deinit(self.allocator);
        try collectFileExtensions(self.allocator, file, &extensions);
        for (extensions.items, 0..) |field, i| {
            for (extensions.items[i + 1 ..]) |other| {
                if (extensionsConflictResolved(self, file, field, file, other)) return error.DuplicateSymbol;
            }
        }
        for (file.extensions.items) |*field| try self.validateExtensionConflict(file, field);
        for (file.messages.items) |*message| try self.validateMessageExtensionConflicts(file, message);
    }

    fn validateMessageExtensionConflicts(self: *const Registry, file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
        for (message.extensions.items) |*field| try self.validateExtensionConflict(file, field);
        for (message.messages.items) |*nested| try self.validateMessageExtensionConflicts(file, nested);
    }

    fn validateExtensionConflict(self: *const Registry, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) Error!void {
        for (self.files.items) |existing_file| {
            for (existing_file.extensions.items) |*existing| {
                if (extensionsConflictResolved(self, file, field, existing_file, existing)) return error.DuplicateSymbol;
            }
            for (existing_file.messages.items) |*message| {
                if (extensionConflictsInMessageResolved(self, file, field, existing_file, message)) return error.DuplicateSymbol;
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
        const owner = self.fileContainingExtension(field) orelse return error.InvalidExtensionDeclaration;
        const extendee = self.findMessageVisible(owner, extendee_name, null) orelse {
            if (isCustomOptionExtendee(extendee_name)) return;
            return error.InvalidExtensionDeclaration;
        };
        for (extendee.extension_ranges.items) |range| {
            const end = range.end orelse std.math.maxInt(i64);
            if (field.number >= range.start and field.number < end) {
                try validateExtensionFieldDeclaration(field, range);
                try validateMessageSetExtensionShape(field, extendee);
                return;
            }
        }
        return error.InvalidExtensionDeclaration;
    }

    pub fn findExtensionByName(self: *const Registry, extendee: []const u8, name: []const u8) ?*const schema.FieldDescriptor {
        if (self.findMessage(extendee, null)) |message| return self.findExtensionByNameForMessage(message, name);
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

    pub fn findExtensionByNameForMessage(self: *const Registry, message: *const schema.MessageDescriptor, name: []const u8) ?*const schema.FieldDescriptor {
        const normalized_name = normalizeName(name);
        for (self.files.items) |file| {
            for (file.extensions.items) |*field| {
                if (self.extensionNameTargetsMessage(file, field, message, normalized_name)) return field;
            }
            for (file.messages.items) |*scope| {
                if (self.findExtensionByNameForMessageInScope(file, scope, message, normalized_name)) |field| return field;
            }
        }
        return null;
    }

    fn findExtensionByNameForMessageInScope(self: *const Registry, file: *const schema.FileDescriptor, scope: *const schema.MessageDescriptor, message: *const schema.MessageDescriptor, name: []const u8) ?*const schema.FieldDescriptor {
        for (scope.extensions.items) |*field| {
            if (self.extensionNameTargetsMessage(file, field, message, name)) return field;
        }
        for (scope.messages.items) |*nested| {
            if (self.findExtensionByNameForMessageInScope(file, nested, message, name)) |field| return field;
        }
        return null;
    }

    fn extensionNameTargetsMessage(self: *const Registry, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, message: *const schema.MessageDescriptor, name: []const u8) bool {
        if (!schema.extensionNameMatches(file.package, field, name)) return false;
        const extendee = field.extendee orelse return false;
        const owner = self.fileContainingExtension(field) orelse return false;
        const resolved = self.findMessageVisible(owner, extendee, null) orelse return false;
        return resolved == message;
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
        if (self.findMessage(extendee, null)) |message| return self.findExtensionForMessage(message, number);
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

    pub fn findExtensionForMessage(self: *const Registry, message: *const schema.MessageDescriptor, number: @import("wire.zig").FieldNumber) ?*const schema.FieldDescriptor {
        for (self.files.items) |file| {
            for (file.extensions.items) |*field| {
                if (self.extensionTargetsMessage(field, message, number)) return field;
            }
            for (file.messages.items) |*scope| {
                if (self.findExtensionForMessageInScope(scope, message, number)) |field| return field;
            }
        }
        return null;
    }

    fn findExtensionForMessageInScope(self: *const Registry, scope: *const schema.MessageDescriptor, message: *const schema.MessageDescriptor, number: @import("wire.zig").FieldNumber) ?*const schema.FieldDescriptor {
        for (scope.extensions.items) |*field| {
            if (self.extensionTargetsMessage(field, message, number)) return field;
        }
        for (scope.messages.items) |*nested| {
            if (self.findExtensionForMessageInScope(nested, message, number)) |field| return field;
        }
        return null;
    }

    fn extensionTargetsMessage(self: *const Registry, field: *const schema.FieldDescriptor, message: *const schema.MessageDescriptor, number: @import("wire.zig").FieldNumber) bool {
        if (field.number != number) return false;
        const extendee = field.extendee orelse return false;
        const owner = self.fileContainingExtension(field) orelse return false;
        const resolved = self.findMessageVisible(owner, extendee, null) orelse return false;
        return resolved == message;
    }

    pub fn findMessageVisible(self: *const Registry, from_file: *const schema.FileDescriptor, name: []const u8, scope: ?[]const u8) ?*const schema.MessageDescriptor {
        if (self.findTypeVisible(from_file, name, scope)) |type_ref| switch (type_ref) {
            .message => |message| return message,
            .enumeration => return null,
        };
        return null;
    }

    pub fn findEnumVisible(self: *const Registry, from_file: *const schema.FileDescriptor, name: []const u8, scope: ?[]const u8) ?*const schema.EnumDescriptor {
        if (self.findTypeVisible(from_file, name, scope)) |type_ref| switch (type_ref) {
            .message => return null,
            .enumeration => |enumeration| return enumeration,
        };
        return null;
    }

    pub fn fileCanSee(self: *const Registry, from: *const schema.FileDescriptor, to: *const schema.FileDescriptor) bool {
        return sameFile(from, to) or self.importChain(from, to) != null;
    }

    pub fn fileContainingMessage(self: *const Registry, target: *const schema.MessageDescriptor) ?*const schema.FileDescriptor {
        for (self.files.items) |file| {
            if (fileContainsMessage(file, target)) return file;
        }
        return null;
    }

    pub fn fileContainingEnum(self: *const Registry, target: *const schema.EnumDescriptor) ?*const schema.FileDescriptor {
        for (self.files.items) |file| {
            if (fileContainsEnum(file, target)) return file;
        }
        return null;
    }

    pub fn fileContainingExtension(self: *const Registry, target: *const schema.FieldDescriptor) ?*const schema.FileDescriptor {
        for (self.files.items) |file| {
            for (file.extensions.items) |*field| {
                if (field == target) return file;
            }
            for (file.messages.items) |*message| {
                if (messageContainsExtension(message, target)) return file;
            }
        }
        return null;
    }

    pub fn validateAllFileReferences(self: *const Registry) Error!void {
        for (self.files.items) |file| try self.validateFileReferences(file);
    }

    pub fn validateFileReferences(self: *const Registry, file: *const schema.FileDescriptor) Error!void {
        for (file.messages.items) |*message| {
            const scope = try qualifiedTypeName(self.allocator, file.package, message.name);
            defer self.allocator.free(scope);
            try self.validateMessageReferences(file, message, scope);
        }
        for (file.extensions.items) |*field| try self.validateFieldTypeReference(file, field, file.package);
    }

    fn validateMessageReferences(self: *const Registry, file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, scope: []const u8) Error!void {
        for (message.fields.items) |*field| try self.validateFieldTypeReference(file, field, scope);
        for (message.extensions.items) |*field| try self.validateFieldTypeReference(file, field, scope);
        for (message.messages.items) |*nested| {
            const nested_scope = try qualifiedTypeName(self.allocator, scope, nested.name);
            defer self.allocator.free(nested_scope);
            try self.validateMessageReferences(file, nested, nested_scope);
        }
    }

    fn validateFieldTypeReference(self: *const Registry, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scope: []const u8) Error!void {
        if (field.extendee) |extendee_name| {
            if (self.findMessageVisible(file, extendee_name, null) == null and !isCustomOptionExtendee(extendee_name)) return error.InvalidFieldType;
        }
        try self.validateKindTypeReference(file, field.kind, scope);
        try self.validateImportedEnumDefault(file, field, scope);
    }

    fn validateKindTypeReference(self: *const Registry, file: *const schema.FileDescriptor, kind: schema.FieldKind, scope: []const u8) Error!void {
        switch (kind) {
            .scalar => {},
            .message => |name| {
                if (self.findMessageVisible(file, name, scope) == null and self.findEnumVisible(file, name, scope) == null) {
                    if (file.missing_weak_imports.items.len != 0 and self.findType(name, scope) == null) return;
                    return error.InvalidFieldType;
                }
            },
            .enumeration => |name| {
                if (self.findEnumVisible(file, name, scope) == null) return error.InvalidFieldType;
            },
            .group => |name| {
                if (self.findMessageVisible(file, name, scope) == null) return error.InvalidFieldType;
            },
            .map => |map_type| try self.validateKindTypeReference(file, map_type.value.*, scope),
        }
    }

    fn validateImportedEnumDefault(self: *const Registry, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scope: []const u8) Error!void {
        const value = field.default_value orelse return;
        const enum_name = switch (field.kind) {
            .enumeration => |name| name,
            .message => |name| name,
            else => return,
        };
        if (field.kind == .message) {
            if (self.findMessageVisible(file, enum_name, scope) != null) return error.InvalidFieldType;
        }
        const enumeration = self.findEnumVisible(file, enum_name, scope) orelse return error.InvalidFieldType;
        if (!enumDefaultMatches(enumeration, value)) return error.InvalidFieldType;
    }

    pub fn findFile(self: *const Registry, path: []const u8) ?*const schema.FileDescriptor {
        for (self.files.items) |file| {
            if (std.mem.eql(u8, file.name, path)) return file;
        }
        return null;
    }

    pub fn importChain(self: *const Registry, from: *const schema.FileDescriptor, to: *const schema.FileDescriptor) ?ImportChain {
        if (sameFile(from, to)) return .{};
        for (from.imports.items) |import| {
            if (import.kind == .option) continue;
            const imported = self.findFile(import.path) orelse continue;
            if (sameFile(imported, to)) return oneStepImportChain(import.path);
            if (self.publicImportChainFrom(imported, to, 1)) |tail| {
                return prependImportPath(import.path, tail);
            }
        }
        return null;
    }

    fn publicImportChainFrom(self: *const Registry, from: *const schema.FileDescriptor, to: *const schema.FileDescriptor, depth: usize) ?ImportChain {
        if (depth >= max_import_chain_depth) return null;
        for (from.imports.items) |import| {
            if (import.kind != .public) continue;
            const imported = self.findFile(import.path) orelse continue;
            if (sameFile(imported, to)) return oneStepImportChain(import.path);
            if (self.publicImportChainFrom(imported, to, depth + 1)) |tail| {
                return prependImportPath(import.path, tail);
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

    pub fn findTypeVisible(self: *const Registry, from_file: *const schema.FileDescriptor, name: []const u8, scope: ?[]const u8) ?TypeRef {
        if (std.mem.startsWith(u8, name, ".")) return self.findAbsoluteVisible(from_file, name[1..]);
        if (scope) |scope_name| {
            var current = scope_name;
            while (true) {
                var buf: [512]u8 = undefined;
                if (current.len + 1 + name.len <= buf.len) {
                    const candidate = std.fmt.bufPrint(&buf, "{s}.{s}", .{ current, name }) catch unreachable;
                    if (self.findAbsoluteVisible(from_file, candidate)) |found| return found;
                }
                if (std.mem.lastIndexOfScalar(u8, current, '.')) |idx| {
                    current = current[0..idx];
                } else break;
            }
        }
        return self.findAbsoluteVisible(from_file, name) orelse self.findByLeafVisible(from_file, name);
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

    fn findAbsoluteVisible(self: *const Registry, from_file: *const schema.FileDescriptor, full_name: []const u8) ?TypeRef {
        const normalized = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
        for (self.files.items) |file| {
            if (!self.fileCanSee(from_file, file)) continue;
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

    fn findByLeafVisible(self: *const Registry, from_file: *const schema.FileDescriptor, leaf: []const u8) ?TypeRef {
        for (self.files.items) |file| {
            if (!self.fileCanSee(from_file, file)) continue;
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

fn sameFile(a: *const schema.FileDescriptor, b: *const schema.FileDescriptor) bool {
    if (a == b) return true;
    if (a.name.len != 0 and b.name.len != 0 and std.mem.eql(u8, a.name, b.name)) return true;
    return false;
}

fn fileContainsMessage(file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor) bool {
    for (file.messages.items) |*message| {
        if (message == target or messageContainsMessage(message, target)) return true;
    }
    return false;
}

fn collectFileExtensions(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, output: *std.ArrayList(*const schema.FieldDescriptor)) std.mem.Allocator.Error!void {
    for (file.extensions.items) |*field| try output.append(allocator, field);
    for (file.messages.items) |*message| try collectMessageExtensions(allocator, message, output);
}

fn collectMessageExtensions(allocator: std.mem.Allocator, message: *const schema.MessageDescriptor, output: *std.ArrayList(*const schema.FieldDescriptor)) std.mem.Allocator.Error!void {
    for (message.extensions.items) |*field| try output.append(allocator, field);
    for (message.messages.items) |*nested| try collectMessageExtensions(allocator, nested, output);
}

fn messageContainsMessage(message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor) bool {
    for (message.messages.items) |*nested| {
        if (nested == target or messageContainsMessage(nested, target)) return true;
    }
    return false;
}

fn fileContainsEnum(file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor) bool {
    for (file.enums.items) |*enumeration| {
        if (enumeration == target) return true;
    }
    for (file.messages.items) |*message| {
        if (messageContainsEnum(message, target)) return true;
    }
    return false;
}

fn messageContainsEnum(message: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor) bool {
    for (message.enums.items) |*enumeration| {
        if (enumeration == target) return true;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsEnum(nested, target)) return true;
    }
    return false;
}

fn messageContainsExtension(message: *const schema.MessageDescriptor, target: *const schema.FieldDescriptor) bool {
    for (message.extensions.items) |*field| {
        if (field == target) return true;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsExtension(nested, target)) return true;
    }
    return false;
}

fn isCustomOptionExtendee(name: []const u8) bool {
    const normalized = normalizeName(name);
    inline for (.{
        "google.protobuf.FileOptions",
        "google.protobuf.MessageOptions",
        "google.protobuf.FieldOptions",
        "google.protobuf.OneofOptions",
        "google.protobuf.EnumOptions",
        "google.protobuf.EnumValueOptions",
        "google.protobuf.ServiceOptions",
        "google.protobuf.MethodOptions",
        "google.protobuf.ExtensionRangeOptions",
    }) |option_name| {
        if (std.mem.eql(u8, normalized, option_name)) return true;
    }
    return false;
}

fn oneStepImportChain(path: []const u8) ImportChain {
    var chain = ImportChain{};
    chain.paths[0] = path;
    chain.len = 1;
    return chain;
}

fn prependImportPath(path: []const u8, tail: ImportChain) ?ImportChain {
    if (tail.len + 1 > max_import_chain_depth) return null;
    var chain = ImportChain{};
    chain.paths[0] = path;
    @memcpy(chain.paths[1..][0..tail.len], tail.paths[0..tail.len]);
    chain.len = tail.len + 1;
    return chain;
}

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
        if (range.verification == .declaration or range.declarations.items.len != 0) return error.InvalidExtensionDeclaration;
        return;
    };
    if (declaration.reserved) return error.InvalidExtensionDeclaration;
    if (declaration.full_name.len != 0 and !namesMatch(declaration.full_name, schema.extensionFullName(field))) return error.InvalidExtensionDeclaration;
    if (declaration.repeated and field.cardinality != .repeated) return error.InvalidExtensionDeclaration;
    if (!declaration.repeated and field.cardinality == .repeated) return error.InvalidExtensionDeclaration;
    if (declaration.type_name.len != 0 and !extensionTypeMatches(field, declaration.type_name)) return error.InvalidExtensionDeclaration;
}

fn validateMessageSetExtensionShape(field: *const schema.FieldDescriptor, extendee: *const schema.MessageDescriptor) Error!void {
    if (!extendee.messageSetWireFormat()) return;
    if (field.cardinality == .repeated or field.cardinality == .required) return error.InvalidExtensionDeclaration;
    switch (field.kind) {
        .message => {},
        else => return error.InvalidExtensionDeclaration,
    }
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

fn extensionsConflictResolved(registry: *const Registry, a_file: *const schema.FileDescriptor, a: *const schema.FieldDescriptor, b_file: *const schema.FileDescriptor, b: *const schema.FieldDescriptor) bool {
    if (!extensionsTargetSameMessage(registry, a_file, a, b_file, b)) return false;
    if (a.number == b.number) return true;
    return schema.extensionSymbolsEqualWithPackages(a_file.package, a, b_file.package, b);
}

fn extensionConflictsInMessageResolved(registry: *const Registry, field_file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, message_file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    for (message.extensions.items) |*other| {
        if (extensionsConflictResolved(registry, field_file, field, message_file, other)) return true;
    }
    for (message.messages.items) |*nested| {
        if (extensionConflictsInMessageResolved(registry, field_file, field, message_file, nested)) return true;
    }
    return false;
}

fn extensionsTargetSameMessage(registry: *const Registry, a_file: *const schema.FileDescriptor, a: *const schema.FieldDescriptor, b_file: *const schema.FileDescriptor, b: *const schema.FieldDescriptor) bool {
    const a_extendee = a.extendee orelse return false;
    const b_extendee = b.extendee orelse return false;
    const a_message = resolveExtensionExtendee(registry, a_file, a);
    const b_message = resolveExtensionExtendee(registry, b_file, b);
    if (a_message) |am| {
        if (b_message) |bm| return am == bm;
        return false;
    }
    if (b_message != null) return false;
    return namesMatch(a_extendee, b_extendee);
}

fn resolveExtensionExtendee(registry: *const Registry, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    const extendee = field.extendee orelse return null;
    if (file.findMessageDeep(extendee)) |message| return message;
    return registry.findMessageVisible(file, extendee, null);
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

fn enumHasNumber(enumeration: *const schema.EnumDescriptor, number: i32) bool {
    for (enumeration.values.items) |value| {
        if (value.number == number) return true;
    }
    return false;
}

fn enumDefaultMatches(enumeration: *const schema.EnumDescriptor, value: schema.OptionValue) bool {
    return switch (value) {
        .integer => |number| number >= std.math.minInt(i32) and number <= std.math.maxInt(i32) and enumHasNumber(enumeration, @intCast(number)),
        .unsigned_integer => |number| number <= std.math.maxInt(i32) and enumHasNumber(enumeration, @intCast(number)),
        .identifier, .string => |name| enumeration.findValue(name) != null,
        else => false,
    };
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

test "registry computes direct and public import chains" {
    const allocator = std.testing.allocator;
    var leaf = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.leaf;
        \\message User { optional string name = 1; }
    );
    defer leaf.deinit();
    leaf.name = "leaf.proto";
    var leaf2 = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.leaf2;
        \\message PrivateUser { optional string name = 1; }
    );
    defer leaf2.deinit();
    leaf2.name = "leaf2.proto";
    var bridge = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.bridge;
        \\import public "leaf.proto";
        \\message Bridge {}
    );
    defer bridge.deinit();
    bridge.name = "bridge.proto";
    var private_bridge = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.private_bridge;
        \\import "leaf2.proto";
        \\message PrivateBridge {}
    );
    defer private_bridge.deinit();
    private_bridge.name = "private.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "bridge.proto";
        \\import "private.proto";
        \\message App { optional demo.leaf.User user = 1; }
    );
    defer app.deinit();
    app.name = "app.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&leaf);
    try registry.addFile(&leaf2);
    try registry.addFile(&bridge);
    try registry.addFile(&private_bridge);
    try registry.addFile(&app);

    const direct = registry.importChain(&app, &bridge).?;
    try std.testing.expectEqual(@as(usize, 1), direct.len);
    try std.testing.expectEqualStrings("bridge.proto", direct.paths[0]);

    const public_chain = registry.importChain(&app, &leaf).?;
    try std.testing.expectEqual(@as(usize, 2), public_chain.len);
    try std.testing.expectEqualStrings("bridge.proto", public_chain.paths[0]);
    try std.testing.expectEqualStrings("leaf.proto", public_chain.paths[1]);

    try std.testing.expect(registry.importChain(&app, &leaf2) == null);
    try registry.validateAllFileReferences();

    var bad = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.bad;
        \\import "private.proto";
        \\message Bad { optional demo.leaf2.PrivateUser user = 1; }
    );
    defer bad.deinit();
    bad.name = "bad.proto";
    try registry.addFile(&bad);
    try std.testing.expectError(error.InvalidFieldType, registry.validateFileReferences(&bad));

    var missing = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.missing;
        \\message Bad { optional MissingType field = 1; }
    );
    defer missing.deinit();
    missing.name = "missing.proto";
    try registry.addFile(&missing);
    try std.testing.expectError(error.InvalidFieldType, registry.validateFileReferences(&missing));
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
    first.name = "host.proto";
    var duplicate_number = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional int32 other = 100; }
    );
    defer duplicate_number.deinit();
    var duplicate_name = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional int32 note = 101; }
    );
    defer duplicate_name.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&first);
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_number));
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_name));
}

test "registry rejects duplicate extension symbols within one file descriptor" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        file.package = "demo";
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "first", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        try file.extensions.append(allocator, .{ .name = "second", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        var registry = Registry.init(allocator);
        defer registry.deinit();
        try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&file));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        file.package = "demo";
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        try file.extensions.append(allocator, .{ .name = "tag", .number = 101, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        var registry = Registry.init(allocator);
        defer registry.deinit();
        try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&file));
    }
}

test "registry allows same extension numbers on different package extendees" {
    const allocator = std.testing.allocator;
    var a_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package a;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
    );
    defer a_file.deinit();
    a_file.name = "a.proto";
    var b_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package b;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional int32 note = 100; }
    );
    defer b_file.deinit();
    b_file.name = "b.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&a_file);
    try registry.addFile(&b_file);

    try std.testing.expectEqualStrings("note", registry.findExtension(".a.Host", 100).?.name);
    try std.testing.expectEqual(schema.ScalarType.string, registry.findExtension(".a.Host", 100).?.kind.scalar);
    try std.testing.expectEqual(schema.ScalarType.int32, registry.findExtension(".b.Host", 100).?.kind.scalar);
    try std.testing.expectEqual(schema.ScalarType.string, registry.findExtensionByName(".a.Host", "a.note").?.kind.scalar);
    try std.testing.expectEqual(schema.ScalarType.int32, registry.findExtensionByName(".b.Host", "b.note").?.kind.scalar);
}

test "registry validates extension extendee visibility" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\enum TargetEnum { UNKNOWN = 0; }
    );
    defer host.deinit();
    host.name = "host.proto";

    var missing_extendee = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend Missing { optional int32 tag = 100; }
    );
    defer missing_extendee.deinit();
    missing_extendee.name = "missing.proto";

    var enum_extendee = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend TargetEnum { optional int32 tag = 100; }
    );
    defer enum_extendee.deinit();
    enum_extendee.name = "enum.proto";

    var option_only = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2024";
        \\package option_only;
        \\import option "host.proto";
        \\extend demo.Host { int32 tag = 100; }
    );
    defer option_only.deinit();
    option_only.name = "option-only.proto";

    var custom_option = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\extend google.protobuf.MessageOptions { optional string note = 1000; }
    );
    defer custom_option.deinit();
    custom_option.name = "custom-option.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&missing_extendee));
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&enum_extendee));
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&option_only));
    try registry.addFile(&custom_option);
}

test "registry validates cross-file MessageSet extension shapes" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  option message_set_wire_format = true;
        \\  extensions 4 to max;
        \\}
    );
    defer host.deinit();
    host.name = "host.proto";
    var valid = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\message Ext {}
        \\extend Host { optional Ext ext = 100; }
    );
    defer valid.deinit();
    valid.name = "valid.proto";
    var scalar = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional int32 bad = 101; }
    );
    defer scalar.deinit();
    scalar.name = "scalar.proto";
    var repeated = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\message ExtRepeated {}
        \\extend Host { repeated ExtRepeated bad = 102; }
    );
    defer repeated.deinit();
    repeated.name = "repeated.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try registry.addFile(&valid);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&scalar));
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&repeated));
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
    host.name = "host.proto";
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional Ext ext = 100; }
    );
    defer extension.deinit();
    extension.name = "extension.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try registry.addFile(&extension);

    var missing_declaration = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional Ext other = 101; }
    );
    defer missing_declaration.deinit();
    missing_declaration.name = "missing-declaration.proto";
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&missing_declaration));
}

test "registry enforces declaration coverage when any declaration exists" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" }
        \\  ];
        \\}
        \\message Ext {}
    );
    defer host.deinit();
    host.name = "host.proto";
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional Ext other = 101; }
    );
    defer extension.deinit();
    extension.name = "extension.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&extension));
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
    host.name = "host.proto";
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional Ext ext = 100; }
    );
    defer extension.deinit();
    extension.name = "extension.proto";

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
