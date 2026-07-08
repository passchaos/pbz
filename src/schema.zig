const std = @import("std");
const wire = @import("wire.zig");

pub const Syntax = enum {
    proto2,
    proto3,
    editions,

    pub fn defaultEdition(self: Syntax) Edition {
        return switch (self) {
            .proto2 => .proto2,
            .proto3 => .proto3,
            .editions => .edition_2023,
        };
    }
};

pub const Edition = enum(i32) {
    unknown = 0,
    legacy = 900,
    proto2 = 998,
    proto3 = 999,
    edition_2023 = 1000,
    edition_2024 = 1001,
    edition_2026 = 1002,
    unstable = 9999,
    max = 0x7fffffff,

    pub fn fromYear(year: []const u8) ?Edition {
        if (std.mem.eql(u8, year, "2023")) return .edition_2023;
        if (std.mem.eql(u8, year, "2024")) return .edition_2024;
        if (std.mem.eql(u8, year, "2026")) return .edition_2026;
        return null;
    }
};

pub const Cardinality = enum {
    implicit,
    optional,
    required,
    repeated,

    pub fn isSingular(self: Cardinality) bool {
        return self != .repeated;
    }
};

pub const ScalarType = enum {
    double,
    float,
    int32,
    int64,
    uint32,
    uint64,
    sint32,
    sint64,
    fixed32,
    fixed64,
    sfixed32,
    sfixed64,
    bool,
    string,
    bytes,

    pub fn fromName(name: []const u8) ?ScalarType {
        inline for (@typeInfo(ScalarType).@"enum".fields) |field| {
            if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn wireType(self: ScalarType) wire.WireType {
        return switch (self) {
            .double, .fixed64, .sfixed64 => .fixed64,
            .float, .fixed32, .sfixed32 => .fixed32,
            .string, .bytes => .length_delimited,
            else => .varint,
        };
    }

    pub fn packable(self: ScalarType) bool {
        return switch (self) {
            .string, .bytes => false,
            else => true,
        };
    }

    pub fn validMapKey(self: ScalarType) bool {
        return switch (self) {
            .double, .float, .bytes => false,
            else => true,
        };
    }
};

pub const FieldKind = union(enum) {
    scalar: ScalarType,
    message: []const u8,
    enumeration: []const u8,
    group: []const u8,
    map: MapType,

    pub fn wireType(self: FieldKind) wire.WireType {
        return switch (self) {
            .scalar => |scalar| scalar.wireType(),
            .message, .map => .length_delimited,
            .enumeration => .varint,
            .group => .start_group,
        };
    }

    pub fn packable(self: FieldKind) bool {
        return switch (self) {
            .scalar => |scalar| scalar.packable(),
            .enumeration => true,
            else => false,
        };
    }
};

pub const MapType = struct {
    key: ScalarType,
    value: *FieldKind,
};

pub const FieldOption = struct {
    name: []const u8,
    value: OptionValue,
};

pub const OptionValue = union(enum) {
    identifier: []const u8,
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    aggregate: []const u8,
};

pub const OptionList = std.ArrayList(FieldOption);

pub const FieldDescriptor = struct {
    name: []const u8,
    number: wire.FieldNumber,
    cardinality: Cardinality = .implicit,
    kind: FieldKind,
    default_value: ?OptionValue = null,
    json_name: ?[]const u8 = null,
    oneof_name: ?[]const u8 = null,
    proto3_optional: bool = false,
    packed_override: ?bool = null,
    options: OptionList = .empty,

    pub fn deinit(self: *FieldDescriptor, allocator: std.mem.Allocator) void {
        deinitKind(&self.kind, allocator);
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }

    pub fn isPackable(self: FieldDescriptor) bool {
        return self.cardinality == .repeated and self.kind.packable();
    }

    pub fn isRepeatedLike(self: FieldDescriptor) bool {
        return self.cardinality == .repeated or self.kind == .map;
    }

    pub fn resolvedPacked(self: FieldDescriptor, file: *const FileDescriptor) bool {
        if (!self.isPackable()) return false;
        if (self.packed_override) |is_packed| return is_packed;
        return switch (file.syntax) {
            .proto2 => false,
            .proto3 => true,
            .editions => file.features.repeated_field_encoding == FeatureSet.RepeatedFieldEncoding.packed_encoding,
        };
    }
};

pub const OneofDescriptor = struct {
    name: []const u8,
    options: OptionList = .empty,

    pub fn deinit(self: *OneofDescriptor, allocator: std.mem.Allocator) void {
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }
};

pub const ReservedRange = struct {
    start: i64,
    end: ?i64,
};

pub const ExtensionRange = struct {
    start: i64,
    end: ?i64,
    options: OptionList = .empty,

    pub fn deinit(self: *ExtensionRange, allocator: std.mem.Allocator) void {
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }
};

pub const EnumValueDescriptor = struct {
    name: []const u8,
    number: i32,
    options: OptionList = .empty,

    pub fn deinit(self: *EnumValueDescriptor, allocator: std.mem.Allocator) void {
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }
};

pub const EnumDescriptor = struct {
    name: []const u8,
    values: std.ArrayList(EnumValueDescriptor) = .empty,
    options: OptionList = .empty,
    reserved_ranges: std.ArrayList(ReservedRange) = .empty,
    reserved_names: std.ArrayList([]const u8) = .empty,

    pub fn deinit(self: *EnumDescriptor, allocator: std.mem.Allocator) void {
        for (self.values.items) |*value| value.deinit(allocator);
        self.values.deinit(allocator);
        deinitOptions(&self.options, allocator);
        self.reserved_ranges.deinit(allocator);
        self.reserved_names.deinit(allocator);
        self.* = undefined;
    }

    pub fn findValue(self: *const EnumDescriptor, name: []const u8) ?*const EnumValueDescriptor {
        for (self.values.items) |*value| {
            if (std.mem.eql(u8, value.name, name)) return value;
        }
        return null;
    }
};

pub const MessageDescriptor = struct {
    name: []const u8,
    fields: std.ArrayList(FieldDescriptor) = .empty,
    oneofs: std.ArrayList(OneofDescriptor) = .empty,
    messages: std.ArrayList(MessageDescriptor) = .empty,
    enums: std.ArrayList(EnumDescriptor) = .empty,
    extensions: std.ArrayList(FieldDescriptor) = .empty,
    extension_ranges: std.ArrayList(ExtensionRange) = .empty,
    reserved_ranges: std.ArrayList(ReservedRange) = .empty,
    reserved_names: std.ArrayList([]const u8) = .empty,
    options: OptionList = .empty,

    pub fn deinit(self: *MessageDescriptor, allocator: std.mem.Allocator) void {
        for (self.fields.items) |*field| field.deinit(allocator);
        self.fields.deinit(allocator);
        for (self.oneofs.items) |*oneof| oneof.deinit(allocator);
        self.oneofs.deinit(allocator);
        for (self.messages.items) |*message| message.deinit(allocator);
        self.messages.deinit(allocator);
        for (self.enums.items) |*enumeration| enumeration.deinit(allocator);
        self.enums.deinit(allocator);
        for (self.extensions.items) |*field| field.deinit(allocator);
        self.extensions.deinit(allocator);
        for (self.extension_ranges.items) |*range| range.deinit(allocator);
        self.extension_ranges.deinit(allocator);
        self.reserved_ranges.deinit(allocator);
        self.reserved_names.deinit(allocator);
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }

    pub fn findField(self: *const MessageDescriptor, name: []const u8) ?*const FieldDescriptor {
        for (self.fields.items) |*field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }
        return null;
    }

    pub fn findFieldByNumber(self: *const MessageDescriptor, number: wire.FieldNumber) ?*const FieldDescriptor {
        for (self.fields.items) |*field| {
            if (field.number == number) return field;
        }
        return null;
    }

    pub fn findMessage(self: *const MessageDescriptor, name: []const u8) ?*const MessageDescriptor {
        for (self.messages.items) |*message| {
            if (std.mem.eql(u8, message.name, name)) return message;
        }
        return null;
    }

    pub fn findEnum(self: *const MessageDescriptor, name: []const u8) ?*const EnumDescriptor {
        for (self.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, name)) return enumeration;
        }
        return null;
    }

    pub fn findMessageDeep(self: *const MessageDescriptor, name: []const u8) ?*const MessageDescriptor {
        const needle = leafName(name);
        for (self.messages.items) |*message| {
            if (std.mem.eql(u8, message.name, needle) or std.mem.eql(u8, message.name, name)) return message;
            if (message.findMessageDeep(name)) |found| return found;
        }
        return null;
    }

    pub fn findEnumDeep(self: *const MessageDescriptor, name: []const u8) ?*const EnumDescriptor {
        const needle = leafName(name);
        for (self.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, needle) or std.mem.eql(u8, enumeration.name, name)) return enumeration;
        }
        for (self.messages.items) |*message| {
            if (message.findEnumDeep(name)) |found| return found;
        }
        return null;
    }
};

pub const ServiceDescriptor = struct {
    name: []const u8,
    methods: std.ArrayList(MethodDescriptor) = .empty,
    options: OptionList = .empty,

    pub fn deinit(self: *ServiceDescriptor, allocator: std.mem.Allocator) void {
        for (self.methods.items) |*method| method.deinit(allocator);
        self.methods.deinit(allocator);
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }
};

pub const MethodDescriptor = struct {
    name: []const u8,
    input_type: []const u8,
    output_type: []const u8,
    client_streaming: bool = false,
    server_streaming: bool = false,
    options: OptionList = .empty,

    pub fn deinit(self: *MethodDescriptor, allocator: std.mem.Allocator) void {
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }
};

pub const Import = struct {
    path: []const u8,
    kind: Kind = .normal,

    pub const Kind = enum { normal, public, weak, option };
};

pub const FeatureSet = struct {
    field_presence: FieldPresence = .explicit,
    enum_type: EnumType = .open,
    repeated_field_encoding: RepeatedFieldEncoding = .packed_encoding,
    utf8_validation: Utf8Validation = .verify,

    pub const FieldPresence = enum { explicit, implicit, legacy_required };
    pub const EnumType = enum { open, closed };
    pub const RepeatedFieldEncoding = enum { packed_encoding, expanded };
    pub const Utf8Validation = enum { none, verify };

    pub fn defaults(syntax: Syntax) FeatureSet {
        return switch (syntax) {
            .proto2 => .{
                .field_presence = .explicit,
                .enum_type = .closed,
                .repeated_field_encoding = .expanded,
                .utf8_validation = .none,
            },
            .proto3 => .{
                .field_presence = .implicit,
                .enum_type = .open,
                .repeated_field_encoding = .packed_encoding,
                .utf8_validation = .verify,
            },
            .editions => .{
                .field_presence = .explicit,
                .enum_type = .open,
                .repeated_field_encoding = .packed_encoding,
                .utf8_validation = .verify,
            },
        };
    }

    pub fn applyOption(self: *FeatureSet, option_name: []const u8, value: OptionValue) void {
        const leaf = if (std.mem.lastIndexOfScalar(u8, option_name, '.')) |idx| option_name[idx + 1 ..] else option_name;
        const ident = switch (value) {
            .identifier => |s| s,
            .string => |s| s,
            .boolean => |b| if (b) "true" else "false",
            else => return,
        };
        if (std.mem.eql(u8, leaf, "field_presence")) {
            if (std.ascii.eqlIgnoreCase(ident, "EXPLICIT")) self.field_presence = .explicit;
            if (std.ascii.eqlIgnoreCase(ident, "IMPLICIT")) self.field_presence = .implicit;
            if (std.ascii.eqlIgnoreCase(ident, "LEGACY_REQUIRED")) self.field_presence = .legacy_required;
        } else if (std.mem.eql(u8, leaf, "enum_type")) {
            if (std.ascii.eqlIgnoreCase(ident, "OPEN")) self.enum_type = .open;
            if (std.ascii.eqlIgnoreCase(ident, "CLOSED")) self.enum_type = .closed;
        } else if (std.mem.eql(u8, leaf, "repeated_field_encoding")) {
            if (std.ascii.eqlIgnoreCase(ident, "PACKED")) self.repeated_field_encoding = .packed_encoding;
            if (std.ascii.eqlIgnoreCase(ident, "EXPANDED")) self.repeated_field_encoding = .expanded;
        } else if (std.mem.eql(u8, leaf, "utf8_validation")) {
            if (std.ascii.eqlIgnoreCase(ident, "NONE")) self.utf8_validation = .none;
            if (std.ascii.eqlIgnoreCase(ident, "VERIFY")) self.utf8_validation = .verify;
        }
    }
};

pub const FileDescriptor = struct {
    allocator: std.mem.Allocator,
    name: []const u8 = "",
    package: []const u8 = "",
    syntax: Syntax = .proto2,
    edition: Edition = .proto2,
    imports: std.ArrayList(Import) = .empty,
    messages: std.ArrayList(MessageDescriptor) = .empty,
    enums: std.ArrayList(EnumDescriptor) = .empty,
    extensions: std.ArrayList(FieldDescriptor) = .empty,
    services: std.ArrayList(ServiceDescriptor) = .empty,
    options: OptionList = .empty,
    features: FeatureSet = FeatureSet.defaults(.proto2),

    pub fn init(allocator: std.mem.Allocator) FileDescriptor {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FileDescriptor) void {
        for (self.messages.items) |*message| message.deinit(self.allocator);
        self.messages.deinit(self.allocator);
        for (self.enums.items) |*enumeration| enumeration.deinit(self.allocator);
        self.enums.deinit(self.allocator);
        for (self.extensions.items) |*field| field.deinit(self.allocator);
        self.extensions.deinit(self.allocator);
        for (self.services.items) |*service| service.deinit(self.allocator);
        self.services.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        deinitOptions(&self.options, self.allocator);
        self.* = undefined;
    }

    pub fn setSyntax(self: *FileDescriptor, syntax: Syntax) void {
        self.syntax = syntax;
        self.edition = syntax.defaultEdition();
        self.features = FeatureSet.defaults(syntax);
    }

    pub fn setEdition(self: *FileDescriptor, edition: Edition) void {
        self.syntax = .editions;
        self.edition = edition;
        self.features = FeatureSet.defaults(.editions);
    }

    pub fn addOption(self: *FileDescriptor, option: FieldOption) std.mem.Allocator.Error!void {
        try self.options.append(self.allocator, option);
        if (std.mem.startsWith(u8, option.name, "features.")) self.features.applyOption(option.name, option.value);
    }

    pub fn findMessage(self: *const FileDescriptor, name: []const u8) ?*const MessageDescriptor {
        for (self.messages.items) |*message| {
            if (std.mem.eql(u8, message.name, name)) return message;
        }
        return null;
    }

    pub fn findEnum(self: *const FileDescriptor, name: []const u8) ?*const EnumDescriptor {
        for (self.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, name)) return enumeration;
        }
        return null;
    }

    pub fn findMessageDeep(self: *const FileDescriptor, name: []const u8) ?*const MessageDescriptor {
        const normalized = self.stripPackagePrefix(name);
        const needle = leafName(normalized);
        for (self.messages.items) |*message| {
            if (std.mem.eql(u8, message.name, normalized) or std.mem.eql(u8, message.name, needle)) return message;
            if (message.findMessageDeep(normalized)) |found| return found;
        }
        return null;
    }

    pub fn findEnumDeep(self: *const FileDescriptor, name: []const u8) ?*const EnumDescriptor {
        const normalized = self.stripPackagePrefix(name);
        const needle = leafName(normalized);
        for (self.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, normalized) or std.mem.eql(u8, enumeration.name, needle)) return enumeration;
        }
        for (self.messages.items) |*message| {
            if (message.findEnumDeep(normalized)) |found| return found;
        }
        return null;
    }

    fn stripPackagePrefix(self: *const FileDescriptor, name: []const u8) []const u8 {
        var normalized = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
        if (self.package.len != 0 and std.mem.startsWith(u8, normalized, self.package)) {
            if (normalized.len == self.package.len) return "";
            if (normalized.len > self.package.len and normalized[self.package.len] == '.') normalized = normalized[self.package.len + 1 ..];
        }
        return normalized;
    }
};

fn leafName(name: []const u8) []const u8 {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
}

pub fn deinitKind(kind: *FieldKind, allocator: std.mem.Allocator) void {
    switch (kind.*) {
        .map => |map_type| {
            deinitKind(map_type.value, allocator);
            allocator.destroy(map_type.value);
        },
        else => {},
    }
}

pub fn deinitOptions(options: *OptionList, allocator: std.mem.Allocator) void {
    options.deinit(allocator);
}

pub fn optionAsBool(value: OptionValue) ?bool {
    return switch (value) {
        .boolean => |b| b,
        .identifier => |s| if (std.ascii.eqlIgnoreCase(s, "true")) true else if (std.ascii.eqlIgnoreCase(s, "false")) false else null,
        else => null,
    };
}

pub fn optionAsIdentifier(value: OptionValue) ?[]const u8 {
    return switch (value) {
        .identifier => |s| s,
        .string => |s| s,
        else => null,
    };
}

test "schema resolves feature defaults for proto2 proto3 and editions" {
    var file = FileDescriptor.init(std.testing.allocator);
    defer file.deinit();

    file.setSyntax(.proto2);
    try std.testing.expectEqual(FeatureSet.RepeatedFieldEncoding.expanded, file.features.repeated_field_encoding);

    file.setSyntax(.proto3);
    try std.testing.expectEqual(FeatureSet.FieldPresence.implicit, file.features.field_presence);
    try std.testing.expectEqual(FeatureSet.RepeatedFieldEncoding.packed_encoding, file.features.repeated_field_encoding);

    file.setEdition(.edition_2023);
    try file.addOption(.{ .name = "features.repeated_field_encoding", .value = .{ .identifier = "EXPANDED" } });
    try std.testing.expectEqual(Syntax.editions, file.syntax);
    try std.testing.expectEqual(Edition.edition_2023, file.edition);
    try std.testing.expectEqual(FeatureSet.RepeatedFieldEncoding.expanded, file.features.repeated_field_encoding);
}
