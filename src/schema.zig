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
    name_owned: bool = false,
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

    pub fn isRepeatedLike(self: FieldDescriptor) bool {
        return self.cardinality == .repeated or self.kind == .map;
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
        for (self.locations.items) |*location| location.deinit(allocator);
        self.locations.deinit(allocator);
        self.* = undefined;
    }

    pub fn isEmpty(self: *const SourceCodeInfo) bool {
        return self.locations.items.len == 0;
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
        for (self.annotations.items) |*annotation| annotation.deinit(allocator);
        self.annotations.deinit(allocator);
        self.* = undefined;
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

    pub fn messageSetWireFormat(self: *const MessageDescriptor) bool {
        for (self.options.items) |option| {
            if (std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), "message_set_wire_format")) return optionAsBool(option.value) orelse false;
        }
        return false;
    }
};

pub const ServiceDescriptor = struct {
    name: []const u8,
    methods: std.ArrayList(MethodDescriptor) = .empty,
    features: ?FeatureSet = null,
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
    features: ?FeatureSet = null,
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

pub fn optionBool(options: []const FieldOption, name: []const u8) ?bool {
    for (options) |option| {
        if (std.mem.eql(u8, optionLeaf(option.name), name)) return optionAsBool(option.value);
    }
    return null;
}

pub fn optionLeaf(name: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| return trimmed[idx + 1 ..];
    return trimmed;
}

pub fn jsonNameLooksLikeExtension(json_name: []const u8) bool {
    return json_name.len >= 2 and json_name[0] == '[' and json_name[json_name.len - 1] == ']';
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
