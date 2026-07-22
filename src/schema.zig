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
    edition_1_test_only = 1,
    edition_2_test_only = 2,
    legacy = 900,
    proto2 = 998,
    proto3 = 999,
    edition_2023 = 1000,
    edition_2024 = 1001,
    edition_2026 = 1002,
    unstable = 9999,
    edition_99997_test_only = 99997,
    edition_99998_test_only = 99998,
    edition_99999_test_only = 99999,
    max = 0x7fffffff,

    pub fn fromYear(year: []const u8) ?Edition {
        if (std.mem.eql(u8, year, "2023")) return .edition_2023;
        if (std.mem.eql(u8, year, "2024")) return .edition_2024;
        if (std.mem.eql(u8, year, "2026")) return .edition_2026;
        if (std.mem.eql(u8, year, "UNSTABLE")) return .unstable;
        if (std.mem.eql(u8, year, "1_TEST_ONLY")) return .edition_1_test_only;
        if (std.mem.eql(u8, year, "2_TEST_ONLY")) return .edition_2_test_only;
        if (std.mem.eql(u8, year, "99997_TEST_ONLY")) return .edition_99997_test_only;
        if (std.mem.eql(u8, year, "99998_TEST_ONLY")) return .edition_99998_test_only;
        if (std.mem.eql(u8, year, "99999_TEST_ONLY")) return .edition_99999_test_only;
        return null;
    }

    pub fn fromProtoName(name: []const u8) ?Edition {
        if (std.ascii.eqlIgnoreCase(name, "EDITION_UNKNOWN")) return .unknown;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_LEGACY")) return .legacy;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_PROTO2")) return .proto2;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_PROTO3")) return .proto3;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_2023")) return .edition_2023;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_2024")) return .edition_2024;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_2026")) return .edition_2026;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_UNSTABLE")) return .unstable;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_1_TEST_ONLY")) return .edition_1_test_only;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_2_TEST_ONLY")) return .edition_2_test_only;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_99997_TEST_ONLY")) return .edition_99997_test_only;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_99998_TEST_ONLY")) return .edition_99998_test_only;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_99999_TEST_ONLY")) return .edition_99999_test_only;
        if (std.ascii.eqlIgnoreCase(name, "EDITION_MAX")) return .max;
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

pub const FieldCppType = enum {
    int32,
    int64,
    uint32,
    uint64,
    double,
    float,
    bool,
    enumeration,
    string,
    message,

    pub fn typeName(self: FieldCppType) []const u8 {
        return fieldCppTypeName(self);
    }
};

pub fn fieldCppTypeName(cpp_type: FieldCppType) []const u8 {
    return switch (cpp_type) {
        .int32 => "int32",
        .int64 => "int64",
        .uint32 => "uint32",
        .uint64 => "uint64",
        .double => "double",
        .float => "float",
        .bool => "bool",
        .enumeration => "enum",
        .string => "string",
        .message => "message",
    };
}

pub const WellKnownType = enum {
    unspecified,
    double_value,
    float_value,
    int64_value,
    uint64_value,
    int32_value,
    uint32_value,
    string_value,
    bytes_value,
    bool_value,
    any,
    field_mask,
    duration,
    timestamp,
    value,
    list_value,
    @"struct",
};

pub fn scalarTypeName(scalar: ScalarType) []const u8 {
    return switch (scalar) {
        .double => "double",
        .float => "float",
        .int32 => "int32",
        .int64 => "int64",
        .uint32 => "uint32",
        .uint64 => "uint64",
        .sint32 => "sint32",
        .sint64 => "sint64",
        .fixed32 => "fixed32",
        .fixed64 => "fixed64",
        .sfixed32 => "sfixed32",
        .sfixed64 => "sfixed64",
        .bool => "bool",
        .string => "string",
        .bytes => "bytes",
    };
}

pub fn wellKnownTypeFromFullName(full_name: []const u8) WellKnownType {
    const normalized = normalizeProtoName(full_name);
    inline for (.{
        .{ "google.protobuf.DoubleValue", WellKnownType.double_value },
        .{ "google.protobuf.FloatValue", WellKnownType.float_value },
        .{ "google.protobuf.Int64Value", WellKnownType.int64_value },
        .{ "google.protobuf.UInt64Value", WellKnownType.uint64_value },
        .{ "google.protobuf.Int32Value", WellKnownType.int32_value },
        .{ "google.protobuf.UInt32Value", WellKnownType.uint32_value },
        .{ "google.protobuf.StringValue", WellKnownType.string_value },
        .{ "google.protobuf.BytesValue", WellKnownType.bytes_value },
        .{ "google.protobuf.BoolValue", WellKnownType.bool_value },
        .{ "google.protobuf.Any", WellKnownType.any },
        .{ "google.protobuf.FieldMask", WellKnownType.field_mask },
        .{ "google.protobuf.Duration", WellKnownType.duration },
        .{ "google.protobuf.Timestamp", WellKnownType.timestamp },
        .{ "google.protobuf.Value", WellKnownType.value },
        .{ "google.protobuf.ListValue", WellKnownType.list_value },
        .{ "google.protobuf.Struct", WellKnownType.@"struct" },
    }) |entry| {
        if (std.mem.eql(u8, normalized, entry[0])) return entry[1];
    }
    return .unspecified;
}

pub fn isWellKnownTypeFullName(full_name: []const u8) bool {
    return wellKnownTypeFromFullName(full_name) != .unspecified;
}

pub fn declarationTypeNameIsScalar(type_name: []const u8) bool {
    return ScalarType.fromName(type_name) != null;
}

pub fn declarationSymbolIsQualified(type_name: []const u8) bool {
    if (!std.mem.startsWith(u8, type_name, ".")) return false;
    return isFullIdentifier(type_name[1..]);
}

pub fn isFullIdentifier(value: []const u8) bool {
    var index: usize = 0;
    var expect_start = true;
    while (index < value.len) : (index += 1) {
        const c = value[index];
        if (c == '.') {
            if (expect_start) return false;
            expect_start = true;
            continue;
        }
        if (expect_start) {
            if (!isIdentifierStart(c)) return false;
            expect_start = false;
        } else if (!isIdentifierContinue(c)) return false;
    }
    return !expect_start;
}

pub fn isIdentifier(value: []const u8) bool {
    if (value.len == 0) return false;
    if (!isIdentifierStart(value[0])) return false;
    for (value[1..]) |c| {
        if (!isIdentifierContinue(c)) return false;
    }
    return true;
}

fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentifierContinue(c: u8) bool {
    return isIdentifierStart(c) or std.ascii.isDigit(c);
}

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

    pub fn cppType(self: FieldKind) FieldCppType {
        return switch (self) {
            .scalar => |scalar| switch (scalar) {
                .int32, .sint32, .sfixed32 => .int32,
                .int64, .sint64, .sfixed64 => .int64,
                .uint32, .fixed32 => .uint32,
                .uint64, .fixed64 => .uint64,
                .double => .double,
                .float => .float,
                .bool => .bool,
                .string, .bytes => .string,
            },
            .enumeration => .enumeration,
            .message, .group, .map => .message,
        };
    }

    pub fn typeName(self: FieldKind) []const u8 {
        return switch (self) {
            .scalar => |scalar| scalarTypeName(scalar),
            .message, .map => "message",
            .enumeration => "enum",
            .group => "group",
        };
    }
};

pub fn fieldKindTypeName(kind: FieldKind) []const u8 {
    return kind.typeName();
}

pub const MapType = struct {
    key: ScalarType,
    value: *FieldKind,
};

pub const FieldOption = struct {
    name: []const u8,
    value: OptionValue,
    name_owned: bool = false,
};

pub const OptionValue = union(enum) {
    identifier: []const u8,
    string: []const u8,
    integer: i64,
    unsigned_integer: u64,
    float: f64,
    boolean: bool,
    aggregate: []const u8,
};

pub const OptionList = std.ArrayList(FieldOption);

pub const FieldCType = enum(i32) { string = 0, cord = 1, string_piece = 2 };

pub const FieldJSType = enum(i32) { js_normal = 0, js_string = 1, js_number = 2 };

pub const MethodIdempotencyLevel = enum(i32) { idempotency_unknown = 0, no_side_effects = 1, idempotent = 2 };

pub const FileOptimizeMode = enum(i32) { speed = 1, code_size = 2, lite_runtime = 3 };

pub const FieldRetention = enum(i32) { retention_unknown = 0, retention_runtime = 1, retention_source = 2 };

pub const FieldTargetType = enum(i32) {
    target_type_unknown = 0,
    target_type_file = 1,
    target_type_extension_range = 2,
    target_type_message = 3,
    target_type_field = 4,
    target_type_oneof = 5,
    target_type_enum = 6,
    target_type_enum_entry = 7,
    target_type_service = 8,
    target_type_method = 9,
};

pub const FieldDescriptor = struct {
    name: []const u8,
    full_name: ?[]const u8 = null,
    number: wire.FieldNumber,
    cardinality: Cardinality = .implicit,
    kind: FieldKind,
    extendee: ?[]const u8 = null,
    default_value: ?OptionValue = null,
    json_name: ?[]const u8 = null,
    oneof_name: ?[]const u8 = null,
    proto3_optional: bool = false,
    packed_override: ?bool = null,
    edition_defaults: std.ArrayList(FieldEditionDefault) = .empty,
    features: ?FeatureSet = null,
    feature_support: ?FeatureSupport = null,
    options: OptionList = .empty,

    pub fn deinit(self: *FieldDescriptor, allocator: std.mem.Allocator) void {
        deinitKind(&self.kind, allocator);
        self.edition_defaults.deinit(allocator);
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }

    pub fn isPackable(self: FieldDescriptor) bool {
        return self.cardinality == .repeated and self.kind.packable();
    }

    pub fn hasPackedOverride(self: FieldDescriptor) bool {
        return self.packed_override != null;
    }

    pub fn packedOverride(self: FieldDescriptor) ?bool {
        return self.packed_override;
    }

    pub fn isMap(self: FieldDescriptor) bool {
        return self.kind == .map;
    }

    pub fn wireType(self: FieldDescriptor) wire.WireType {
        return self.kind.wireType();
    }

    pub fn cppType(self: FieldDescriptor) FieldCppType {
        return self.kind.cppType();
    }

    pub fn typeName(self: FieldDescriptor) []const u8 {
        return self.kind.typeName();
    }

    pub fn cppTypeName(self: FieldDescriptor) []const u8 {
        return self.cppType().typeName();
    }

    pub fn encodedWireType(self: FieldDescriptor, file: *const FileDescriptor) wire.WireType {
        if (self.resolvedPacked(file)) return .length_delimited;
        return self.wireType();
    }

    pub fn mapKeyType(self: FieldDescriptor) ?ScalarType {
        return switch (self.kind) {
            .map => |map_type| map_type.key,
            else => null,
        };
    }

    pub fn mapValueKind(self: FieldDescriptor) ?FieldKind {
        return switch (self.kind) {
            .map => |map_type| map_type.value.*,
            else => null,
        };
    }

    pub fn isRepeatedLike(self: FieldDescriptor) bool {
        return self.cardinality == .repeated or self.kind == .map;
    }

    pub fn isRequired(self: FieldDescriptor) bool {
        if (self.cardinality == .required) return true;
        if (self.features) |features| return features.field_presence == .legacy_required;
        return false;
    }

    pub fn hasOptionalKeyword(self: FieldDescriptor) bool {
        return self.cardinality == .optional;
    }

    pub fn isWeak(self: FieldDescriptor) bool {
        return optionBool(self.options.items, "weak") orelse false;
    }

    pub fn isLazy(self: FieldDescriptor) bool {
        return optionBool(self.options.items, "lazy") orelse false;
    }

    pub fn isUnverifiedLazy(self: FieldDescriptor) bool {
        return optionBool(self.options.items, "unverified_lazy") orelse false;
    }

    pub fn isDebugRedacted(self: FieldDescriptor) bool {
        return optionBool(self.options.items, "debug_redact") orelse false;
    }

    pub fn cType(self: FieldDescriptor) ?FieldCType {
        return optionKnownEnum(FieldCType, self.options.items, "ctype");
    }

    pub fn jsType(self: FieldDescriptor) ?FieldJSType {
        return optionKnownEnum(FieldJSType, self.options.items, "jstype");
    }

    pub fn retention(self: FieldDescriptor) ?FieldRetention {
        return optionKnownEnum(FieldRetention, self.options.items, "retention");
    }

    pub fn targetCount(self: FieldDescriptor) usize {
        var count: usize = 0;
        for (self.options.items) |option| {
            if (std.mem.eql(u8, optionLeaf(option.name), "targets")) count += 1;
        }
        return count;
    }

    pub fn targetAt(self: FieldDescriptor, index: usize) ?FieldTargetType {
        var seen: usize = 0;
        for (self.options.items) |option| {
            if (!std.mem.eql(u8, optionLeaf(option.name), "targets")) continue;
            if (seen == index) return optionAsKnownEnum(FieldTargetType, option.value);
            seen += 1;
        }
        return null;
    }

    pub fn hasDefaultValue(self: FieldDescriptor) bool {
        return self.default_value != null;
    }

    /// Return the parsed default option exactly as stored on the descriptor.
    /// Slices inside the returned value are owned by the descriptor graph.
    pub fn explicitDefaultValue(self: FieldDescriptor) ?OptionValue {
        return self.default_value;
    }

    pub fn hasPresence(self: FieldDescriptor, file: *const FileDescriptor) bool {
        if (self.isRequired() or self.proto3_optional or self.oneof_name != null or self.kind == .message or self.kind == .group) return true;
        if (self.cardinality == .repeated or self.kind == .map) return false;
        if (self.features) |features| return features.field_presence != .implicit;
        return file.features.field_presence != .implicit;
    }

    pub fn fieldPresence(self: FieldDescriptor, file: *const FileDescriptor) FeatureSet.FieldPresence {
        if (self.features) |features| return features.field_presence;
        return file.features.field_presence;
    }

    pub fn utf8Validation(self: FieldDescriptor, file: *const FileDescriptor) FeatureSet.Utf8Validation {
        if (self.features) |features| return features.utf8_validation;
        return file.features.utf8_validation;
    }

    pub fn messageEncoding(self: FieldDescriptor, file: *const FileDescriptor) FeatureSet.MessageEncoding {
        if (self.features) |features| return features.message_encoding;
        return file.features.message_encoding;
    }

    pub fn hasExplicitJsonName(self: FieldDescriptor) bool {
        return self.json_name != null;
    }

    pub fn explicitJsonName(self: FieldDescriptor) ?[]const u8 {
        return self.json_name;
    }

    pub fn lowercaseName(self: FieldDescriptor, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        return try lowercaseNameAlloc(allocator, self.name);
    }

    pub fn camelcaseName(self: FieldDescriptor, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        return try camelcaseNameAlloc(allocator, self.name);
    }

    pub fn jsonName(self: FieldDescriptor, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        if (self.json_name) |explicit| return try allocator.dupe(u8, explicit);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        var index: usize = 0;
        var upper_next = false;
        while (nextDefaultJsonNameChar(self.name, &index, &upper_next)) |c| try out.append(allocator, c);
        return try out.toOwnedSlice(allocator);
    }

    pub fn resolvedPacked(self: FieldDescriptor, file: *const FileDescriptor) bool {
        if (!self.isPackable()) return false;
        if (self.packed_override) |is_packed| return is_packed;
        if (self.features) |features| return features.repeated_field_encoding == FeatureSet.RepeatedFieldEncoding.packed_encoding;
        return switch (file.syntax) {
            .proto2 => false,
            .proto3 => true,
            .editions => file.features.repeated_field_encoding == FeatureSet.RepeatedFieldEncoding.packed_encoding,
        };
    }
};

pub const FieldEditionDefault = struct {
    edition: Edition = .unknown,
    value: []const u8 = "",
};

pub const FeatureSupport = struct {
    edition_introduced: ?Edition = null,
    edition_deprecated: ?Edition = null,
    deprecation_warning: []const u8 = "",
    edition_removed: ?Edition = null,
    removal_error: []const u8 = "",
};

pub fn validateFeatureSupport(feature_support: FeatureSupport) !void {
    if (feature_support.edition_introduced) |introduced| {
        if (introduced == .unknown) return error.InvalidFieldType;
    }
    if (feature_support.edition_deprecated) |deprecated| {
        if (deprecated == .unknown) return error.InvalidFieldType;
        if (feature_support.deprecation_warning.len == 0) return error.InvalidFieldType;
        if (feature_support.edition_introduced) |introduced| {
            if (@intFromEnum(deprecated) < @intFromEnum(introduced)) return error.InvalidFieldType;
        }
        if (feature_support.edition_removed) |removed| {
            if (@intFromEnum(deprecated) >= @intFromEnum(removed)) return error.InvalidFieldType;
        }
    } else if (feature_support.deprecation_warning.len != 0) return error.InvalidFieldType;
    if (feature_support.edition_removed) |removed| {
        if (removed == .unknown) return error.InvalidFieldType;
        if (feature_support.edition_introduced) |introduced| {
            if (@intFromEnum(removed) < @intFromEnum(introduced)) return error.InvalidFieldType;
        }
    } else if (feature_support.removal_error.len != 0) return error.InvalidFieldType;
}

pub const OneofDescriptor = struct {
    name: []const u8,
    features: ?FeatureSet = null,
    options: OptionList = .empty,

    pub fn deinit(self: *OneofDescriptor, allocator: std.mem.Allocator) void {
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }
};

pub const ReservedRange = struct {
    start: i64,
    end: ?i64,

    pub fn effectiveEnd(self: ReservedRange, max_end: i64) i64 {
        return self.end orelse max_end;
    }

    pub fn containsWithMax(self: ReservedRange, number: i64, max_end: i64) bool {
        return number >= self.start and number < self.effectiveEnd(max_end);
    }

    pub fn overlapsWithMax(self: ReservedRange, other: ReservedRange, max_end: i64) bool {
        const end = self.effectiveEnd(max_end);
        const other_end = other.effectiveEnd(max_end);
        return self.start < other_end and other.start < end;
    }
};

pub const ExtensionRange = struct {
    start: i64,
    end: ?i64,
    options: OptionList = .empty,
    declarations: std.ArrayList(ExtensionDeclaration) = .empty,
    verification: ?ExtensionRangeVerification = null,
    features: ?FeatureSet = null,

    pub fn deinit(self: *ExtensionRange, allocator: std.mem.Allocator) void {
        deinitOptions(&self.options, allocator);
        self.declarations.deinit(allocator);
        self.* = undefined;
    }

    pub fn contains(self: ExtensionRange, number: i64) bool {
        return self.containsWithMax(number, std.math.maxInt(i64));
    }

    pub fn effectiveEndWithMax(self: ExtensionRange, max_end: i64) i64 {
        return self.end orelse max_end;
    }

    pub fn containsWithMax(self: ExtensionRange, number: i64, max_end: i64) bool {
        return number >= self.start and number < self.effectiveEndWithMax(max_end);
    }

    pub fn overlapsInMessage(self: ExtensionRange, message: *const MessageDescriptor, other: ExtensionRange) bool {
        const end = self.effectiveEnd(message);
        const other_end = other.effectiveEnd(message);
        return self.start < other_end and other.start < end;
    }

    pub fn effectiveEnd(self: ExtensionRange, message: *const MessageDescriptor) i64 {
        // DescriptorProto stores extension/reserved range ends as exclusive
        // values, but an omitted source-level `to max` depends on the host
        // message shape: MessageSet ranges use the legacy int32 ceiling while
        // ordinary messages use protobuf's public field-number ceiling + 1.
        return self.effectiveEndWithMax(message.extensionRangeMaxExclusive());
    }

    pub fn containsInMessage(self: ExtensionRange, message: *const MessageDescriptor, number: i64) bool {
        return number >= self.start and number < self.effectiveEnd(message);
    }

    pub fn declarationForNumber(self: ExtensionRange, number: i32) ?ExtensionDeclaration {
        for (self.declarations.items) |declaration| {
            if (declaration.number == number) return declaration;
        }
        return null;
    }
};

pub const ExtensionDeclaration = struct {
    number: i32 = 0,
    full_name: []const u8 = "",
    type_name: []const u8 = "",
    reserved: bool = false,
    repeated: bool = false,
};

pub const ExtensionRangeVerification = enum(i32) {
    declaration = 0,
    unverified = 1,
};

pub const SourceCodeInfo = struct {
    locations: std.ArrayList(Location) = .empty,

    pub const Location = struct {
        path: std.ArrayList(i32) = .empty,
        span: std.ArrayList(i32) = .empty,
        leading_comments: ?[]const u8 = null,
        trailing_comments: ?[]const u8 = null,
        leading_detached_comments: std.ArrayList([]const u8) = .empty,

        pub fn deinit(self: *Location, allocator: std.mem.Allocator) void {
            self.path.deinit(allocator);
            self.span.deinit(allocator);
            self.leading_detached_comments.deinit(allocator);
            self.* = undefined;
        }
    };

    pub fn deinit(self: *SourceCodeInfo, allocator: std.mem.Allocator) void {
        for (self.locations.items) |*loc| loc.deinit(allocator);
        self.locations.deinit(allocator);
        self.* = undefined;
    }

    pub fn isEmpty(self: *const SourceCodeInfo) bool {
        return self.locations.items.len == 0;
    }

    pub fn location(self: *const SourceCodeInfo, path: []const i32) ?*const Location {
        for (self.locations.items) |*loc| {
            if (std.mem.eql(i32, loc.path.items, path)) return loc;
        }
        return null;
    }
};

pub const GeneratedCodeInfo = struct {
    annotations: std.ArrayList(Annotation) = .empty,

    pub const Semantic = enum(i32) {
        none = 0,
        set = 1,
        alias = 2,
    };

    pub const Annotation = struct {
        path: std.ArrayList(i32) = .empty,
        source_file: ?[]const u8 = null,
        begin: ?i32 = null,
        end: ?i32 = null,
        semantic: ?Semantic = null,

        pub fn deinit(self: *Annotation, allocator: std.mem.Allocator) void {
            self.path.deinit(allocator);
            self.* = undefined;
        }
    };

    pub fn deinit(self: *GeneratedCodeInfo, allocator: std.mem.Allocator) void {
        for (self.annotations.items) |*ann| ann.deinit(allocator);
        self.annotations.deinit(allocator);
        self.* = undefined;
    }

    pub fn annotation(self: *const GeneratedCodeInfo, path: []const i32) ?*const Annotation {
        for (self.annotations.items) |*ann| {
            if (std.mem.eql(i32, ann.path.items, path)) return ann;
        }
        return null;
    }
};

pub const EnumValueDescriptor = struct {
    name: []const u8,
    number: i32,
    features: ?FeatureSet = null,
    feature_support: ?FeatureSupport = null,
    options: OptionList = .empty,

    pub fn deinit(self: *EnumValueDescriptor, allocator: std.mem.Allocator) void {
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }

    pub fn isDebugRedacted(self: EnumValueDescriptor) bool {
        return optionBool(self.options.items, "debug_redact") orelse false;
    }
};

pub const EnumDescriptor = struct {
    name: []const u8,
    values: std.ArrayList(EnumValueDescriptor) = .empty,
    features: ?FeatureSet = null,
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

    pub fn findValueByNumber(self: *const EnumDescriptor, number: i32) ?*const EnumValueDescriptor {
        for (self.values.items) |*value| {
            if (value.number == number) return value;
        }
        return null;
    }

    pub fn valueCount(self: *const EnumDescriptor) usize {
        return self.values.items.len;
    }

    pub fn valueAt(self: *const EnumDescriptor, index: usize) ?*const EnumValueDescriptor {
        if (index >= self.values.items.len) return null;
        return &self.values.items[index];
    }

    pub fn valuesByNumberAlloc(self: *const EnumDescriptor, allocator: std.mem.Allocator, number: i32) std.mem.Allocator.Error![]*const EnumValueDescriptor {
        var values: std.ArrayList(*const EnumValueDescriptor) = .empty;
        errdefer values.deinit(allocator);
        for (self.values.items) |*value| {
            if (value.number == number) try values.append(allocator, value);
        }
        return try values.toOwnedSlice(allocator);
    }

    pub fn allowAlias(self: *const EnumDescriptor) bool {
        return optionBool(self.options.items, "allow_alias") orelse false;
    }

    pub fn enumType(self: *const EnumDescriptor, file: *const FileDescriptor) FeatureSet.EnumType {
        if (self.features) |features| return features.enum_type;
        return file.features.enum_type;
    }

    pub fn deprecatedLegacyJsonFieldConflicts(self: *const EnumDescriptor) bool {
        return optionBool(self.options.items, "deprecated_legacy_json_field_conflicts") orelse false;
    }

    pub fn isReservedName(self: *const EnumDescriptor, name: []const u8) bool {
        return reservedNameMatches(self.reserved_names.items, name);
    }

    pub fn reservedRangeForNumber(self: *const EnumDescriptor, number: i64) ?*const ReservedRange {
        return reservedRangeForNumberWithMax(self.reserved_ranges.items, number, std.math.maxInt(i64));
    }

    pub fn isReservedNumber(self: *const EnumDescriptor, number: i64) bool {
        return self.reservedRangeForNumber(number) != null;
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
    map_entry: bool = false,
    features: ?FeatureSet = null,
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

    pub fn findFieldByLowercaseName(self: *const MessageDescriptor, lowercase_name: []const u8) ?*const FieldDescriptor {
        for (self.fields.items) |*field| {
            if (eqlLowercaseName(field.name, lowercase_name)) return field;
        }
        return null;
    }

    pub fn findFieldByCamelcaseName(self: *const MessageDescriptor, camelcase_name: []const u8) ?*const FieldDescriptor {
        for (self.fields.items) |*field| {
            if (eqlCamelcaseName(field.name, camelcase_name)) return field;
        }
        return null;
    }

    pub fn findFieldByJsonName(self: *const MessageDescriptor, json_name: []const u8) ?*const FieldDescriptor {
        for (self.fields.items) |*field| {
            if (field.json_name) |explicit| {
                if (std.mem.eql(u8, explicit, json_name)) return field;
            } else if (eqlDefaultJsonName(field.name, json_name)) return field;
        }
        return null;
    }

    pub fn findFieldByNumber(self: *const MessageDescriptor, number: wire.FieldNumber) ?*const FieldDescriptor {
        for (self.fields.items) |*field| {
            if (field.number == number) return field;
        }
        return null;
    }

    pub fn fieldCount(self: *const MessageDescriptor) usize {
        return self.fields.items.len;
    }

    pub fn fieldAt(self: *const MessageDescriptor, index: usize) ?*const FieldDescriptor {
        if (index >= self.fields.items.len) return null;
        return &self.fields.items[index];
    }

    pub fn extensionCount(self: *const MessageDescriptor) usize {
        return self.extensions.items.len;
    }

    pub fn extensionAt(self: *const MessageDescriptor, index: usize) ?*const FieldDescriptor {
        if (index >= self.extensions.items.len) return null;
        return &self.extensions.items[index];
    }

    pub fn findExtension(self: *const MessageDescriptor, name: []const u8) ?*const FieldDescriptor {
        for (self.extensions.items) |*field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }
        return null;
    }

    pub fn findExtensionByLowercaseName(self: *const MessageDescriptor, lowercase_name: []const u8) ?*const FieldDescriptor {
        for (self.extensions.items) |*field| {
            if (eqlLowercaseName(field.name, lowercase_name)) return field;
        }
        return null;
    }

    pub fn findExtensionByCamelcaseName(self: *const MessageDescriptor, camelcase_name: []const u8) ?*const FieldDescriptor {
        for (self.extensions.items) |*field| {
            if (eqlCamelcaseName(field.name, camelcase_name)) return field;
        }
        return null;
    }

    pub fn oneofCount(self: *const MessageDescriptor) usize {
        return self.oneofs.items.len;
    }

    pub fn realOneofCount(self: *const MessageDescriptor) usize {
        var count: usize = 0;
        for (self.oneofs.items) |*oneof| {
            if (!self.oneofIsSynthetic(oneof)) count += 1;
        }
        return count;
    }

    pub fn oneofAt(self: *const MessageDescriptor, index: usize) ?*const OneofDescriptor {
        if (index >= self.oneofs.items.len) return null;
        return &self.oneofs.items[index];
    }

    pub fn realOneofAt(self: *const MessageDescriptor, index: usize) ?*const OneofDescriptor {
        var seen: usize = 0;
        for (self.oneofs.items) |*oneof| {
            if (self.oneofIsSynthetic(oneof)) continue;
            if (seen == index) return oneof;
            seen += 1;
        }
        return null;
    }

    pub fn oneofIsSynthetic(self: *const MessageDescriptor, oneof: *const OneofDescriptor) bool {
        var found_oneof = false;
        for (self.oneofs.items) |*candidate| {
            if (candidate == oneof) {
                found_oneof = true;
                break;
            }
        }
        if (!found_oneof) return false;

        // FileDescriptorProto represents each proto3 `optional` field as a
        // one-field synthetic oneof with the field's `proto3_optional` bit set.
        // Parsed source files keep proto3 optional as a plain field, so only
        // descriptor-decoded messages can satisfy this shape.
        var field_count: usize = 0;
        var only_field_is_proto3_optional = false;
        for (self.fields.items) |field| {
            const oneof_name = field.oneof_name orelse continue;
            if (!std.mem.eql(u8, oneof_name, oneof.name)) continue;
            field_count += 1;
            only_field_is_proto3_optional = field.proto3_optional;
        }
        return field_count == 1 and only_field_is_proto3_optional;
    }

    pub fn nestedMessageCount(self: *const MessageDescriptor) usize {
        return self.messages.items.len;
    }

    pub fn nestedMessageAt(self: *const MessageDescriptor, index: usize) ?*const MessageDescriptor {
        if (index >= self.messages.items.len) return null;
        return &self.messages.items[index];
    }

    pub fn nestedEnumCount(self: *const MessageDescriptor) usize {
        return self.enums.items.len;
    }

    pub fn nestedEnumAt(self: *const MessageDescriptor, index: usize) ?*const EnumDescriptor {
        if (index >= self.enums.items.len) return null;
        return &self.enums.items[index];
    }

    pub fn isReservedName(self: *const MessageDescriptor, name: []const u8) bool {
        return reservedNameMatches(self.reserved_names.items, name);
    }

    pub fn reservedRangeForNumber(self: *const MessageDescriptor, number: i64) ?*const ReservedRange {
        return reservedRangeForNumberWithMax(self.reserved_ranges.items, number, self.extensionRangeMaxExclusive());
    }

    pub fn isReservedNumber(self: *const MessageDescriptor, number: i64) bool {
        return self.reservedRangeForNumber(number) != null;
    }

    pub fn isMapEntry(self: *const MessageDescriptor) bool {
        return self.map_entry;
    }

    pub fn extensionRangeForNumber(self: *const MessageDescriptor, number: i64) ?*const ExtensionRange {
        if (number <= 0 or number >= self.extensionRangeMaxExclusive()) return null;
        for (self.extension_ranges.items) |*range| {
            if (range.containsInMessage(self, number)) return range;
        }
        return null;
    }

    pub fn isExtensionNumber(self: *const MessageDescriptor, number: i64) bool {
        return self.extensionRangeForNumber(number) != null;
    }

    pub fn extensionRangeMaxExclusive(self: *const MessageDescriptor) i64 {
        // Keep this in schema rather than descriptor encoding so reflection,
        // validation, and dynamic extension lookup all agree on open-range
        // membership, including the MessageSet exception.
        return if (self.messageSetWireFormat())
            std.math.maxInt(i32)
        else
            @as(i64, std.math.maxInt(wire.FieldNumber)) + 1;
    }

    pub fn findOneof(self: *const MessageDescriptor, name: []const u8) ?*const OneofDescriptor {
        for (self.oneofs.items) |*oneof| {
            if (std.mem.eql(u8, oneof.name, name)) return oneof;
        }
        return null;
    }

    pub fn oneofFieldsAlloc(self: *const MessageDescriptor, allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]*const FieldDescriptor {
        var fields: std.ArrayList(*const FieldDescriptor) = .empty;
        errdefer fields.deinit(allocator);
        for (self.fields.items) |*field| {
            if (field.oneof_name) |oneof_name| {
                if (std.mem.eql(u8, oneof_name, name)) try fields.append(allocator, field);
            }
        }
        return try fields.toOwnedSlice(allocator);
    }

    pub fn oneofFieldCount(self: *const MessageDescriptor, name: []const u8) usize {
        var count: usize = 0;
        for (self.fields.items) |field| {
            if (field.oneof_name) |oneof_name| {
                if (std.mem.eql(u8, oneof_name, name)) count += 1;
            }
        }
        return count;
    }

    pub fn oneofFieldAt(self: *const MessageDescriptor, name: []const u8, index: usize) ?*const FieldDescriptor {
        var seen: usize = 0;
        for (self.fields.items) |*field| {
            if (field.oneof_name) |oneof_name| {
                if (std.mem.eql(u8, oneof_name, name)) {
                    if (seen == index) return field;
                    seen += 1;
                }
            }
        }
        return null;
    }

    pub fn oneofFieldIndex(self: *const MessageDescriptor, oneof_name: []const u8, target: *const FieldDescriptor) ?usize {
        var seen: usize = 0;
        for (self.fields.items) |*field| {
            const field_oneof = field.oneof_name orelse continue;
            if (!std.mem.eql(u8, field_oneof, oneof_name)) continue;
            if (field == target) return seen;
            seen += 1;
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

    pub fn findEnumValue(self: *const MessageDescriptor, name: []const u8) ?*const EnumValueDescriptor {
        for (self.enums.items) |*enumeration| {
            if (enumeration.findValue(name)) |value| return value;
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

    pub fn messageSetWireFormat(self: *const MessageDescriptor) bool {
        for (self.options.items) |option| {
            if (std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), "message_set_wire_format")) return optionAsBool(option.value) orelse false;
        }
        return false;
    }

    pub fn noStandardDescriptorAccessor(self: *const MessageDescriptor) bool {
        return optionBool(self.options.items, "no_standard_descriptor_accessor") orelse false;
    }

    pub fn deprecatedLegacyJsonFieldConflicts(self: *const MessageDescriptor) bool {
        return optionBool(self.options.items, "deprecated_legacy_json_field_conflicts") orelse false;
    }
};

pub const ServiceDescriptor = struct {
    name: []const u8,
    methods: std.ArrayList(MethodDescriptor) = .empty,
    features: ?FeatureSet = null,
    options: OptionList = .empty,

    pub fn findMethod(self: *const ServiceDescriptor, name: []const u8) ?*const MethodDescriptor {
        for (self.methods.items) |*method| {
            if (std.mem.eql(u8, method.name, name)) return method;
        }
        return null;
    }

    pub fn methodCount(self: *const ServiceDescriptor) usize {
        return self.methods.items.len;
    }

    pub fn methodAt(self: *const ServiceDescriptor, index: usize) ?*const MethodDescriptor {
        if (index >= self.methods.items.len) return null;
        return &self.methods.items[index];
    }

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
    features: ?FeatureSet = null,
    options: OptionList = .empty,

    pub fn deinit(self: *MethodDescriptor, allocator: std.mem.Allocator) void {
        deinitOptions(&self.options, allocator);
        self.* = undefined;
    }

    pub fn idempotencyLevel(self: MethodDescriptor) ?MethodIdempotencyLevel {
        return optionKnownEnum(MethodIdempotencyLevel, self.options.items, "idempotency_level");
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
    message_encoding: MessageEncoding = .length_prefixed,
    json_format: JsonFormat = .allow,
    enforce_naming_style: EnforceNamingStyle = .style_legacy,
    default_symbol_visibility: DefaultSymbolVisibility = .export_all,
    enforce_proto_limits: EnforceProtoLimits = .legacy_no_explicit_limits,

    pub const FieldPresence = enum { explicit, implicit, legacy_required };
    pub const EnumType = enum { open, closed };
    pub const RepeatedFieldEncoding = enum { packed_encoding, expanded };
    pub const Utf8Validation = enum { none, verify };
    pub const MessageEncoding = enum { length_prefixed, delimited };
    pub const JsonFormat = enum { allow, legacy_best_effort };
    pub const EnforceNamingStyle = enum { style2024, style_legacy, style2026 };
    pub const DefaultSymbolVisibility = enum { export_all, export_top_level, local_all, strict };
    pub const EnforceProtoLimits = enum { legacy_no_explicit_limits, proto_limits2026 };

    pub fn defaults(syntax: Syntax) FeatureSet {
        return switch (syntax) {
            .proto2 => .{
                .field_presence = .explicit,
                .enum_type = .closed,
                .repeated_field_encoding = .expanded,
                .utf8_validation = .none,
                .json_format = .legacy_best_effort,
            },
            .proto3 => .{
                .field_presence = .implicit,
                .enum_type = .open,
                .repeated_field_encoding = .packed_encoding,
                .utf8_validation = .verify,
                .json_format = .allow,
            },
            .editions => .{
                .field_presence = .explicit,
                .enum_type = .open,
                .repeated_field_encoding = .packed_encoding,
                .utf8_validation = .verify,
                .json_format = .allow,
            },
        };
    }

    pub fn eql(self: FeatureSet, other: FeatureSet) bool {
        return self.field_presence == other.field_presence and
            self.enum_type == other.enum_type and
            self.repeated_field_encoding == other.repeated_field_encoding and
            self.utf8_validation == other.utf8_validation and
            self.message_encoding == other.message_encoding and
            self.json_format == other.json_format and
            self.enforce_naming_style == other.enforce_naming_style and
            self.default_symbol_visibility == other.default_symbol_visibility and
            self.enforce_proto_limits == other.enforce_proto_limits;
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
        } else if (std.mem.eql(u8, leaf, "message_encoding")) {
            if (std.ascii.eqlIgnoreCase(ident, "LENGTH_PREFIXED")) self.message_encoding = .length_prefixed;
            if (std.ascii.eqlIgnoreCase(ident, "DELIMITED")) self.message_encoding = .delimited;
        } else if (std.mem.eql(u8, leaf, "json_format")) {
            if (std.ascii.eqlIgnoreCase(ident, "ALLOW")) self.json_format = .allow;
            if (std.ascii.eqlIgnoreCase(ident, "LEGACY_BEST_EFFORT")) self.json_format = .legacy_best_effort;
        } else if (std.mem.eql(u8, leaf, "enforce_naming_style")) {
            if (std.ascii.eqlIgnoreCase(ident, "STYLE2024")) self.enforce_naming_style = .style2024;
            if (std.ascii.eqlIgnoreCase(ident, "STYLE_LEGACY")) self.enforce_naming_style = .style_legacy;
            if (std.ascii.eqlIgnoreCase(ident, "STYLE2026")) self.enforce_naming_style = .style2026;
        } else if (std.mem.eql(u8, leaf, "default_symbol_visibility")) {
            if (std.ascii.eqlIgnoreCase(ident, "EXPORT_ALL")) self.default_symbol_visibility = .export_all;
            if (std.ascii.eqlIgnoreCase(ident, "EXPORT_TOP_LEVEL")) self.default_symbol_visibility = .export_top_level;
            if (std.ascii.eqlIgnoreCase(ident, "LOCAL_ALL")) self.default_symbol_visibility = .local_all;
            if (std.ascii.eqlIgnoreCase(ident, "STRICT")) self.default_symbol_visibility = .strict;
        } else if (std.mem.eql(u8, leaf, "enforce_proto_limits")) {
            if (std.ascii.eqlIgnoreCase(ident, "LEGACY_NO_EXPLICIT_LIMITS")) self.enforce_proto_limits = .legacy_no_explicit_limits;
            if (std.ascii.eqlIgnoreCase(ident, "PROTO_LIMITS2026")) self.enforce_proto_limits = .proto_limits2026;
        }
    }
};

pub const FeatureSetEditionDefault = struct {
    edition: Edition = .unknown,
    overridable_features: ?FeatureSet = null,
    fixed_features: ?FeatureSet = null,
};

pub const FeatureSetDefaults = struct {
    defaults: std.ArrayList(FeatureSetEditionDefault) = .empty,
    minimum_edition: ?Edition = null,
    maximum_edition: ?Edition = null,

    pub fn deinit(self: *FeatureSetDefaults, allocator: std.mem.Allocator) void {
        self.defaults.deinit(allocator);
        self.* = undefined;
    }

    pub fn validate(self: *const FeatureSetDefaults) !void {
        var previous: ?Edition = null;
        for (self.defaults.items) |entry| {
            if (entry.edition == .unknown) return error.InvalidEdition;
            if (previous) |prev| {
                if (@intFromEnum(entry.edition) <= @intFromEnum(prev)) return error.InvalidEdition;
            }
            previous = entry.edition;
        }
        if (self.minimum_edition) |min| {
            if (self.maximum_edition) |max| {
                if (@intFromEnum(min) > @intFromEnum(max)) return error.InvalidEdition;
            }
        }
    }

    pub fn defaultsForEdition(self: *const FeatureSetDefaults, edition: Edition) ?*const FeatureSetEditionDefault {
        if (edition == .unknown) return null;
        const requested = @intFromEnum(edition);
        if (self.minimum_edition) |minimum| {
            if (requested < @intFromEnum(minimum)) return null;
        }
        if (self.maximum_edition) |maximum| {
            if (requested > @intFromEnum(maximum)) return null;
        }

        var closest: ?*const FeatureSetEditionDefault = null;
        for (self.defaults.items) |*entry| {
            const entry_value = @intFromEnum(entry.edition);
            if (entry.edition == .unknown or entry_value > requested) break;
            closest = entry;
        }
        return closest;
    }

    pub fn overridableFeaturesForEdition(self: *const FeatureSetDefaults, edition: Edition) ?FeatureSet {
        const entry = self.defaultsForEdition(edition) orelse return null;
        return entry.overridable_features;
    }

    pub fn fixedFeaturesForEdition(self: *const FeatureSetDefaults, edition: Edition) ?FeatureSet {
        const entry = self.defaultsForEdition(edition) orelse return null;
        return entry.fixed_features;
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
    source_code_info: SourceCodeInfo = .{},
    owned_strings: std.ArrayList([]u8) = .empty,
    missing_weak_imports: std.ArrayList([]const u8) = .empty,

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
        self.missing_weak_imports.deinit(self.allocator);
        deinitOptions(&self.options, self.allocator);
        self.source_code_info.deinit(self.allocator);
        for (self.owned_strings.items) |owned| self.allocator.free(owned);
        self.owned_strings.deinit(self.allocator);
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
        errdefer if (option.name_owned) self.allocator.free(option.name);
        try self.options.append(self.allocator, option);
        if (std.mem.startsWith(u8, option.name, "features.")) self.features.applyOption(option.name, option.value);
    }

    pub fn importCount(self: *const FileDescriptor) usize {
        return self.imports.items.len;
    }

    pub fn importAt(self: *const FileDescriptor, index: usize) ?Import {
        if (index >= self.imports.items.len) return null;
        return self.imports.items[index];
    }

    pub fn messageCount(self: *const FileDescriptor) usize {
        return self.messages.items.len;
    }

    pub fn messageAt(self: *const FileDescriptor, index: usize) ?*const MessageDescriptor {
        if (index >= self.messages.items.len) return null;
        return &self.messages.items[index];
    }

    pub fn enumCount(self: *const FileDescriptor) usize {
        return self.enums.items.len;
    }

    pub fn enumAt(self: *const FileDescriptor, index: usize) ?*const EnumDescriptor {
        if (index >= self.enums.items.len) return null;
        return &self.enums.items[index];
    }

    pub fn serviceCount(self: *const FileDescriptor) usize {
        return self.services.items.len;
    }

    pub fn serviceAt(self: *const FileDescriptor, index: usize) ?*const ServiceDescriptor {
        if (index >= self.services.items.len) return null;
        return &self.services.items[index];
    }

    pub fn extensionCount(self: *const FileDescriptor) usize {
        return self.extensions.items.len;
    }

    pub fn extensionAt(self: *const FileDescriptor, index: usize) ?*const FieldDescriptor {
        if (index >= self.extensions.items.len) return null;
        return &self.extensions.items[index];
    }

    pub fn findExtension(self: *const FileDescriptor, name: []const u8) ?*const FieldDescriptor {
        for (self.extensions.items) |*field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }
        return null;
    }

    pub fn findExtensionByLowercaseName(self: *const FileDescriptor, lowercase_name: []const u8) ?*const FieldDescriptor {
        for (self.extensions.items) |*field| {
            if (eqlLowercaseName(field.name, lowercase_name)) return field;
        }
        return null;
    }

    pub fn findExtensionByCamelcaseName(self: *const FileDescriptor, camelcase_name: []const u8) ?*const FieldDescriptor {
        for (self.extensions.items) |*field| {
            if (eqlCamelcaseName(field.name, camelcase_name)) return field;
        }
        return null;
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

    pub fn findEnumValue(self: *const FileDescriptor, name: []const u8) ?*const EnumValueDescriptor {
        for (self.enums.items) |*enumeration| {
            if (enumeration.findValue(name)) |value| return value;
        }
        return null;
    }

    pub fn findService(self: *const FileDescriptor, name: []const u8) ?*const ServiceDescriptor {
        for (self.services.items) |*service| {
            if (std.mem.eql(u8, service.name, name)) return service;
        }
        return null;
    }

    pub fn findImport(self: *const FileDescriptor, path: []const u8) ?Import {
        for (self.imports.items) |import| {
            if (std.mem.eql(u8, import.path, path)) return import;
        }
        return null;
    }

    pub fn optimizeFor(self: *const FileDescriptor) ?FileOptimizeMode {
        return optionKnownEnum(FileOptimizeMode, self.options.items, "optimize_for");
    }

    pub fn hasMissingWeakImport(self: *const FileDescriptor, path: []const u8) bool {
        for (self.missing_weak_imports.items) |missing| {
            if (std.mem.eql(u8, missing, path)) return true;
        }
        return false;
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
    for (options.items) |option| {
        if (option.name_owned) allocator.free(option.name);
    }
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

pub fn optionAsString(value: OptionValue) ?[]const u8 {
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

pub fn optionAsInteger(value: OptionValue) ?i64 {
    return switch (value) {
        .integer => |v| v,
        .unsigned_integer => |v| std.math.cast(i64, v),
        else => null,
    };
}

pub fn optionAsUnsignedInteger(value: OptionValue) ?u64 {
    return switch (value) {
        .unsigned_integer => |v| v,
        .integer => |v| if (v >= 0) @intCast(v) else null,
        else => null,
    };
}

pub fn optionAsFloat(value: OptionValue) ?f64 {
    return switch (value) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        .unsigned_integer => |v| @floatFromInt(v),
        else => null,
    };
}

pub fn optionAsAggregate(value: OptionValue) ?[]const u8 {
    return switch (value) {
        .aggregate => |s| s,
        else => null,
    };
}

pub fn optionKnownEnum(comptime T: type, options: []const FieldOption, name: []const u8) ?T {
    return if (optionValue(options, name)) |value| optionAsKnownEnum(T, value) else null;
}

pub fn optionAsKnownEnum(comptime T: type, value: OptionValue) ?T {
    switch (value) {
        .integer => |v| return if (std.enums.fromInt(T, v)) |known| known else null,
        .unsigned_integer => |v| {
            const signed = std.math.cast(i32, v) orelse return null;
            return std.enums.fromInt(T, signed);
        },
        .identifier, .string => |text| return optionKnownEnumFromName(T, text),
        else => return null,
    }
}

fn optionKnownEnumFromName(comptime T: type, text: []const u8) ?T {
    if (T == FieldCType) {
        if (std.ascii.eqlIgnoreCase(text, "STRING")) return .string;
        if (std.ascii.eqlIgnoreCase(text, "CORD")) return .cord;
        if (std.ascii.eqlIgnoreCase(text, "STRING_PIECE")) return .string_piece;
    } else if (T == FieldJSType) {
        if (std.ascii.eqlIgnoreCase(text, "JS_NORMAL")) return .js_normal;
        if (std.ascii.eqlIgnoreCase(text, "JS_STRING")) return .js_string;
        if (std.ascii.eqlIgnoreCase(text, "JS_NUMBER")) return .js_number;
    } else if (T == MethodIdempotencyLevel) {
        if (std.ascii.eqlIgnoreCase(text, "IDEMPOTENCY_UNKNOWN")) return .idempotency_unknown;
        if (std.ascii.eqlIgnoreCase(text, "NO_SIDE_EFFECTS")) return .no_side_effects;
        if (std.ascii.eqlIgnoreCase(text, "IDEMPOTENT")) return .idempotent;
    } else if (T == FileOptimizeMode) {
        if (std.ascii.eqlIgnoreCase(text, "SPEED")) return .speed;
        if (std.ascii.eqlIgnoreCase(text, "CODE_SIZE")) return .code_size;
        if (std.ascii.eqlIgnoreCase(text, "LITE_RUNTIME")) return .lite_runtime;
    } else if (T == FieldRetention) {
        if (std.ascii.eqlIgnoreCase(text, "RETENTION_UNKNOWN")) return .retention_unknown;
        if (std.ascii.eqlIgnoreCase(text, "RETENTION_RUNTIME")) return .retention_runtime;
        if (std.ascii.eqlIgnoreCase(text, "RETENTION_SOURCE")) return .retention_source;
    } else if (T == FieldTargetType) {
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_UNKNOWN")) return .target_type_unknown;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_FILE")) return .target_type_file;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_EXTENSION_RANGE")) return .target_type_extension_range;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_MESSAGE")) return .target_type_message;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_FIELD")) return .target_type_field;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_ONEOF")) return .target_type_oneof;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_ENUM")) return .target_type_enum;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_ENUM_ENTRY")) return .target_type_enum_entry;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_SERVICE")) return .target_type_service;
        if (std.ascii.eqlIgnoreCase(text, "TARGET_TYPE_METHOD")) return .target_type_method;
    }
    return null;
}

pub fn optionValue(options: []const FieldOption, name: []const u8) ?OptionValue {
    for (options) |option| {
        if (std.mem.eql(u8, option.name, name) or std.mem.eql(u8, optionLeaf(option.name), name)) return option.value;
    }
    return null;
}

pub fn optionBool(options: []const FieldOption, name: []const u8) ?bool {
    return if (optionValue(options, name)) |value| optionAsBool(value) else null;
}

pub fn optionIdentifier(options: []const FieldOption, name: []const u8) ?[]const u8 {
    return if (optionValue(options, name)) |value| optionAsIdentifier(value) else null;
}

pub fn optionString(options: []const FieldOption, name: []const u8) ?[]const u8 {
    return if (optionValue(options, name)) |value| optionAsString(value) else null;
}

pub fn optionInteger(options: []const FieldOption, name: []const u8) ?i64 {
    return if (optionValue(options, name)) |value| optionAsInteger(value) else null;
}

pub fn optionUnsignedInteger(options: []const FieldOption, name: []const u8) ?u64 {
    return if (optionValue(options, name)) |value| optionAsUnsignedInteger(value) else null;
}

pub fn optionFloat(options: []const FieldOption, name: []const u8) ?f64 {
    return if (optionValue(options, name)) |value| optionAsFloat(value) else null;
}

pub fn optionAggregate(options: []const FieldOption, name: []const u8) ?[]const u8 {
    return if (optionValue(options, name)) |value| optionAsAggregate(value) else null;
}

pub fn optionLeaf(name: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    const dotted_leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    if (dotted_leaf.len >= 2 and dotted_leaf[0] == '(' and dotted_leaf[dotted_leaf.len - 1] == ')') return dotted_leaf[1 .. dotted_leaf.len - 1];
    if (dotted_leaf.len != 0 and dotted_leaf[dotted_leaf.len - 1] == ')') return dotted_leaf[0 .. dotted_leaf.len - 1];
    return dotted_leaf;
}

fn reservedNameMatches(names: []const []const u8, name: []const u8) bool {
    for (names) |reserved_name| {
        if (std.mem.eql(u8, reserved_name, name)) return true;
    }
    return false;
}

fn reservedNumberMatches(ranges: []const ReservedRange, number: i64) bool {
    return reservedRangeForNumberWithMax(ranges, number, std.math.maxInt(i64)) != null;
}

fn reservedRangeForNumberWithMax(ranges: []const ReservedRange, number: i64, max_end: i64) ?*const ReservedRange {
    for (ranges) |*range| {
        if (range.containsWithMax(number, max_end)) return range;
    }
    return null;
}

pub fn extensionFullName(field: *const FieldDescriptor) []const u8 {
    return field.full_name orelse field.name;
}

pub fn extensionSymbolsEqual(package: []const u8, a: *const FieldDescriptor, b: *const FieldDescriptor) bool {
    return extensionSymbolsEqualWithPackages(package, a, package, b);
}

pub fn extensionSymbolsEqualWithPackages(a_package: []const u8, a: *const FieldDescriptor, b_package: []const u8, b: *const FieldDescriptor) bool {
    const a_name = normalizeProtoName(extensionFullName(a));
    const b_name = normalizeProtoName(extensionFullName(b));
    const a_scoped = a_package.len == 0 or std.mem.indexOfScalar(u8, a_name, '.') != null;
    const b_scoped = b_package.len == 0 or std.mem.indexOfScalar(u8, b_name, '.') != null;
    if (a_scoped and b_scoped) return std.mem.eql(u8, a_name, b_name);
    if (!a_scoped and !b_scoped) return std.mem.eql(u8, a_package, b_package) and std.mem.eql(u8, a_name, b_name);
    if (!a_scoped) return qualifiedLeafEquals(a_package, a_name, b_name);
    return qualifiedLeafEquals(b_package, b_name, a_name);
}

pub fn extensionNameMatches(package: []const u8, field: *const FieldDescriptor, query_name: []const u8) bool {
    const query = normalizeProtoName(query_name);
    if (extensionEffectiveNameEquals(package, field, query)) return true;
    if (std.mem.indexOfScalar(u8, query, '.') == null) return std.mem.eql(u8, optionLeaf(extensionFullName(field)), query);
    return false;
}

pub fn extensionDeclarationNameMatches(package: []const u8, declaration_full_name: []const u8, field: *const FieldDescriptor) bool {
    const declaration = normalizeProtoName(declaration_full_name);
    return extensionEffectiveNameEquals(package, field, declaration);
}

fn extensionEffectiveNameEquals(package: []const u8, field: *const FieldDescriptor, normalized_query: []const u8) bool {
    const full_name = normalizeProtoName(extensionFullName(field));
    if (std.mem.indexOfScalar(u8, full_name, '.') != null or package.len == 0) return std.mem.eql(u8, full_name, normalized_query);
    return qualifiedLeafEquals(package, full_name, normalized_query);
}

fn qualifiedLeafEquals(package: []const u8, leaf: []const u8, full_name: []const u8) bool {
    return package.len != 0 and
        full_name.len == package.len + 1 + leaf.len and
        std.mem.eql(u8, full_name[0..package.len], package) and
        full_name[package.len] == '.' and
        std.mem.eql(u8, full_name[package.len + 1 ..], leaf);
}

fn normalizeProtoName(name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
}

pub fn jsonNameLooksLikeExtension(json_name: []const u8) bool {
    return json_name.len >= 2 and json_name[0] == '[' and json_name[json_name.len - 1] == ']';
}

pub fn printableExtensionName(printable_name: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, printable_name, " \t\r\n");
    if (!jsonNameLooksLikeExtension(trimmed)) return null;
    const inner = trimmed[1 .. trimmed.len - 1];
    return if (inner.len == 0) null else inner;
}

pub fn lowercaseNameAlloc(allocator: std.mem.Allocator, field_name: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var index: usize = 0;
    while (nextLowercaseNameChar(field_name, &index)) |c| try out.append(allocator, c);
    return try out.toOwnedSlice(allocator);
}

pub fn camelcaseNameAlloc(allocator: std.mem.Allocator, field_name: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var index: usize = 0;
    var upper_next = false;
    var first = true;
    while (nextCamelcaseNameChar(field_name, &index, &upper_next, &first)) |c| try out.append(allocator, c);
    return try out.toOwnedSlice(allocator);
}

pub fn eqlLowercaseName(field_name: []const u8, candidate: []const u8) bool {
    var index: usize = 0;
    for (candidate) |expected| {
        const actual = nextLowercaseNameChar(field_name, &index) orelse return false;
        if (actual != expected) return false;
    }
    return nextLowercaseNameChar(field_name, &index) == null;
}

pub fn eqlCamelcaseName(field_name: []const u8, candidate: []const u8) bool {
    var index: usize = 0;
    var upper_next = false;
    var first = true;
    for (candidate) |expected| {
        const actual = nextCamelcaseNameChar(field_name, &index, &upper_next, &first) orelse return false;
        if (actual != expected) return false;
    }
    return nextCamelcaseNameChar(field_name, &index, &upper_next, &first) == null;
}

pub fn writeLowercaseName(field_name: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var index: usize = 0;
    while (nextLowercaseNameChar(field_name, &index)) |c| try writer.writeByte(c);
}

pub fn writeCamelcaseName(field_name: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var index: usize = 0;
    var upper_next = false;
    var first = true;
    while (nextCamelcaseNameChar(field_name, &index, &upper_next, &first)) |c| try writer.writeByte(c);
}

pub fn eqlDefaultJsonName(field_name: []const u8, candidate: []const u8) bool {
    var field_index: usize = 0;
    var upper_next = false;
    var candidate_index: usize = 0;
    while (nextDefaultJsonNameChar(field_name, &field_index, &upper_next)) |c| {
        if (candidate_index >= candidate.len or candidate[candidate_index] != c) return false;
        candidate_index += 1;
    }
    return candidate_index == candidate.len;
}

pub fn defaultJsonNamesEqual(a: []const u8, b: []const u8) bool {
    var a_index: usize = 0;
    var b_index: usize = 0;
    var a_upper = false;
    var b_upper = false;
    while (true) {
        const a_char = nextDefaultJsonNameChar(a, &a_index, &a_upper);
        const b_char = nextDefaultJsonNameChar(b, &b_index, &b_upper);
        if (a_char == null or b_char == null) return a_char == null and b_char == null;
        if (a_char.? != b_char.?) return false;
    }
}

pub fn writeDefaultJsonName(field_name: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var index: usize = 0;
    var upper_next = false;
    while (nextDefaultJsonNameChar(field_name, &index, &upper_next)) |c| try writer.writeByte(c);
}

pub fn enumValueCanonicalKey(allocator: std.mem.Allocator, enum_name: []const u8, value_name: []const u8) std.mem.Allocator.Error![]u8 {
    const stripped = enumValueWithoutPrefix(allocator, enum_name, value_name);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var next_upper = true;
    for (stripped) |c| {
        if (c == '_') {
            next_upper = true;
            continue;
        }
        try out.append(allocator, if (next_upper) std.ascii.toUpper(c) else std.ascii.toLower(c));
        next_upper = false;
    }
    return try out.toOwnedSlice(allocator);
}

fn enumValueWithoutPrefix(allocator: std.mem.Allocator, enum_name: []const u8, value_name: []const u8) []const u8 {
    _ = allocator;
    var prefix_buf: [256]u8 = undefined;
    var prefix_len: usize = 0;
    for (enum_name) |c| {
        if (c == '_') continue;
        if (prefix_len >= prefix_buf.len) return value_name;
        prefix_buf[prefix_len] = std.ascii.toLower(c);
        prefix_len += 1;
    }

    var i: usize = 0;
    var j: usize = 0;
    while (i < value_name.len and j < prefix_len) : (i += 1) {
        if (value_name[i] == '_') continue;
        if (std.ascii.toLower(value_name[i]) != prefix_buf[j]) return value_name;
        j += 1;
    }
    if (j < prefix_len) return value_name;
    while (i < value_name.len and value_name[i] == '_') : (i += 1) {}
    if (i == value_name.len) return value_name;
    return value_name[i..];
}

fn nextLowercaseNameChar(name: []const u8, index: *usize) ?u8 {
    if (index.* >= name.len) return null;
    const c = name[index.*];
    index.* += 1;
    return std.ascii.toLower(c);
}

fn nextCamelcaseNameChar(name: []const u8, index: *usize, upper_next: *bool, first: *bool) ?u8 {
    while (index.* < name.len) {
        const c = name[index.*];
        index.* += 1;
        if (c == '_') {
            upper_next.* = true;
            continue;
        }
        const out = if (first.*)
            std.ascii.toLower(c)
        else if (upper_next.*)
            std.ascii.toUpper(c)
        else
            c;
        first.* = false;
        upper_next.* = false;
        return out;
    }
    return null;
}

fn nextDefaultJsonNameChar(name: []const u8, index: *usize, upper_next: *bool) ?u8 {
    while (index.* < name.len) {
        const c = name[index.*];
        index.* += 1;
        if (c == '_') {
            upper_next.* = true;
            continue;
        }
        const out = if (upper_next.*) std.ascii.toUpper(c) else c;
        upper_next.* = false;
        return out;
    }
    return null;
}

test "schema identifies C++ descriptor well known types" {
    try std.testing.expectEqual(WellKnownType.any, wellKnownTypeFromFullName("google.protobuf.Any"));
    try std.testing.expectEqual(WellKnownType.any, wellKnownTypeFromFullName(".google.protobuf.Any"));
    try std.testing.expectEqual(WellKnownType.timestamp, wellKnownTypeFromFullName("google.protobuf.Timestamp"));
    try std.testing.expectEqual(WellKnownType.duration, wellKnownTypeFromFullName("google.protobuf.Duration"));
    try std.testing.expectEqual(WellKnownType.field_mask, wellKnownTypeFromFullName("google.protobuf.FieldMask"));
    try std.testing.expectEqual(WellKnownType.@"struct", wellKnownTypeFromFullName("google.protobuf.Struct"));
    try std.testing.expectEqual(WellKnownType.value, wellKnownTypeFromFullName("google.protobuf.Value"));
    try std.testing.expectEqual(WellKnownType.list_value, wellKnownTypeFromFullName("google.protobuf.ListValue"));
    try std.testing.expectEqual(WellKnownType.double_value, wellKnownTypeFromFullName("google.protobuf.DoubleValue"));
    try std.testing.expectEqual(WellKnownType.bytes_value, wellKnownTypeFromFullName("google.protobuf.BytesValue"));
    try std.testing.expectEqual(WellKnownType.unspecified, wellKnownTypeFromFullName("google.protobuf.Empty"));
    try std.testing.expectEqual(WellKnownType.unspecified, wellKnownTypeFromFullName("demo.Any"));
    try std.testing.expect(isWellKnownTypeFullName("google.protobuf.BoolValue"));
    try std.testing.expect(!isWellKnownTypeFullName("google.protobuf.Empty"));
}

test "schema mirrors C++ field lowercase and camelcase names" {
    const allocator = std.testing.allocator;

    const cases = [_]struct { source: []const u8, lower: []const u8, camel: []const u8 }{
        .{ .source = "FooBar", .lower = "foobar", .camel = "fooBar" },
        .{ .source = "foo_bar", .lower = "foo_bar", .camel = "fooBar" },
        .{ .source = "fooBar", .lower = "foobar", .camel = "fooBar" },
        .{ .source = "foo__bar", .lower = "foo__bar", .camel = "fooBar" },
        .{ .source = "_foo", .lower = "_foo", .camel = "foo" },
        .{ .source = "foo_", .lower = "foo_", .camel = "foo" },
        .{ .source = "FOO_BAR", .lower = "foo_bar", .camel = "fOOBAR" },
        .{ .source = "foo2_bar", .lower = "foo2_bar", .camel = "foo2Bar" },
        .{ .source = "foo_2bar", .lower = "foo_2bar", .camel = "foo2bar" },
        .{ .source = "URL_value", .lower = "url_value", .camel = "uRLValue" },
    };

    for (cases) |case| {
        const lower = try lowercaseNameAlloc(allocator, case.source);
        defer allocator.free(lower);
        try std.testing.expectEqualStrings(case.lower, lower);
        try std.testing.expect(eqlLowercaseName(case.source, case.lower));
        try std.testing.expect(!eqlLowercaseName(case.source, case.camel));

        const camel = try camelcaseNameAlloc(allocator, case.source);
        defer allocator.free(camel);
        try std.testing.expectEqualStrings(case.camel, camel);
        try std.testing.expect(eqlCamelcaseName(case.source, case.camel));
        try std.testing.expect(!eqlCamelcaseName(case.source, case.lower));
    }
}

test "schema extracts printable extension names" {
    try std.testing.expectEqualStrings("demo.priority", printableExtensionName("[demo.priority]").?);
    try std.testing.expectEqualStrings(".demo.priority", printableExtensionName(" \t[.demo.priority]\n").?);
    try std.testing.expect(printableExtensionName("demo.priority") == null);
    try std.testing.expect(printableExtensionName("[demo.priority") == null);
    try std.testing.expect(printableExtensionName("[]") == null);
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

test "schema parses edition source literals" {
    try std.testing.expectEqual(Edition.edition_2023, Edition.fromYear("2023").?);
    try std.testing.expectEqual(Edition.unstable, Edition.fromYear("UNSTABLE").?);
    try std.testing.expectEqual(Edition.edition_99998_test_only, Edition.fromYear("99998_TEST_ONLY").?);
    try std.testing.expect(Edition.fromYear("PROTO2") == null);
    try std.testing.expect(Edition.fromYear("UNKNOWN") == null);
}

test "schema finds closest FeatureSetDefaults entry for editions" {
    const allocator = std.testing.allocator;
    var defaults = FeatureSetDefaults{};
    defer defaults.deinit(allocator);
    try defaults.defaults.append(allocator, .{
        .edition = .legacy,
        .overridable_features = .{ .json_format = .legacy_best_effort },
        .fixed_features = .{ .enforce_naming_style = .style_legacy },
    });
    try defaults.defaults.append(allocator, .{
        .edition = .edition_2024,
        .overridable_features = .{ .default_symbol_visibility = .export_top_level },
        .fixed_features = .{ .enforce_naming_style = .style2024 },
    });
    defaults.minimum_edition = .legacy;
    defaults.maximum_edition = .edition_2026;
    try defaults.validate();

    try std.testing.expectEqual(Edition.legacy, defaults.defaultsForEdition(.proto2).?.edition);
    try std.testing.expectEqual(Edition.legacy, defaults.defaultsForEdition(.edition_2023).?.edition);
    try std.testing.expectEqual(Edition.edition_2024, defaults.defaultsForEdition(.edition_2026).?.edition);
    try std.testing.expectEqual(FeatureSet.JsonFormat.legacy_best_effort, defaults.overridableFeaturesForEdition(.edition_2023).?.json_format);
    try std.testing.expectEqual(FeatureSet.DefaultSymbolVisibility.export_top_level, defaults.overridableFeaturesForEdition(.edition_2024).?.default_symbol_visibility);
    try std.testing.expectEqual(FeatureSet.EnforceNamingStyle.style2024, defaults.fixedFeaturesForEdition(.edition_2026).?.enforce_naming_style);
    try std.testing.expect(defaults.defaultsForEdition(.unknown) == null);
    try std.testing.expect(defaults.defaultsForEdition(.unstable) == null);
}
