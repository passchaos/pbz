//! pbz is a pure Zig Protocol Buffers toolkit.
//!
//! The library exposes low-level wire encoding/decoding, schema descriptors,
//! a `.proto` parser for proto2/proto3/editions files, and a dynamic message
//! representation for reflection-oriented applications.

pub const wire = @import("wire.zig");
pub const schema = @import("schema.zig");
pub const parser = @import("parser.zig");
pub const dynamic = @import("dynamic.zig");
pub const descriptor = @import("descriptor.zig");
pub const json = @import("json.zig");
pub const registry = @import("registry.zig");
pub const reflect = @import("reflect.zig");
pub const text = @import("text.zig");
pub const loader = @import("loader.zig");
pub const wkt = @import("wkt.zig");
pub const plugin = @import("plugin.zig");
pub const codegen = @import("codegen.zig");
pub const conformance = @import("conformance.zig");

pub const Allocator = @import("std").mem.Allocator;
pub const FieldNumber = wire.FieldNumber;
pub const WireType = wire.WireType;
pub const Reader = wire.Reader;
pub const Writer = wire.Writer;
pub const Syntax = schema.Syntax;
pub const Edition = schema.Edition;
pub const Cardinality = schema.Cardinality;
pub const ScalarType = schema.ScalarType;
pub const FieldKind = schema.FieldKind;
pub const MapType = schema.MapType;
pub const FieldOption = schema.FieldOption;
pub const OptionValue = schema.OptionValue;
pub const OptionList = schema.OptionList;
pub const FieldCType = schema.FieldCType;
pub const FieldJSType = schema.FieldJSType;
pub const MethodIdempotencyLevel = schema.MethodIdempotencyLevel;
pub const FileDescriptor = schema.FileDescriptor;
pub const MessageDescriptor = schema.MessageDescriptor;
pub const FieldDescriptor = schema.FieldDescriptor;
pub const OneofDescriptor = schema.OneofDescriptor;
pub const EnumDescriptor = schema.EnumDescriptor;
pub const EnumValueDescriptor = schema.EnumValueDescriptor;
pub const ServiceDescriptor = schema.ServiceDescriptor;
pub const MethodDescriptor = schema.MethodDescriptor;
pub const FieldEditionDefault = schema.FieldEditionDefault;
pub const FeatureSupport = schema.FeatureSupport;
pub const FeatureSet = schema.FeatureSet;
pub const FeatureSetEditionDefault = schema.FeatureSetEditionDefault;
pub const FeatureSetDefaults = schema.FeatureSetDefaults;
pub const SourceCodeInfo = schema.SourceCodeInfo;
pub const GeneratedCodeInfo = schema.GeneratedCodeInfo;
pub const Import = schema.Import;
pub const ReservedRange = schema.ReservedRange;
pub const ExtensionRange = schema.ExtensionRange;
pub const ExtensionDeclaration = schema.ExtensionDeclaration;
pub const ExtensionRangeVerification = schema.ExtensionRangeVerification;
pub const ProtoParser = parser.Parser;
pub const DynamicMessage = dynamic.DynamicMessage;
pub const DynamicValue = dynamic.Value;
pub const DynamicDefaultValue = dynamic.DefaultValue;
pub const DynamicFieldValue = dynamic.FieldValue;
pub const DynamicMapEntry = dynamic.MapEntry;
pub const DynamicUnknownField = dynamic.UnknownField;
pub const encodeFileDescriptorProto = descriptor.encodeFileDescriptorProto;
pub const encodeFileDescriptorProtoWithRegistry = descriptor.encodeFileDescriptorProtoWithRegistry;
pub const encodeFileDescriptorSet = descriptor.encodeFileDescriptorSet;
pub const encodeFileDescriptorSetWithRegistry = descriptor.encodeFileDescriptorSetWithRegistry;
pub const decodeFileDescriptorProto = descriptor.decodeFileDescriptorProto;
pub const decodeFileDescriptorSet = descriptor.decodeFileDescriptorSet;
pub const encodeFeatureSetDefaults = descriptor.encodeFeatureSetDefaults;
pub const decodeFeatureSetDefaults = descriptor.decodeFeatureSetDefaults;
pub const encodeGeneratedCodeInfo = descriptor.encodeGeneratedCodeInfo;
pub const decodeGeneratedCodeInfo = descriptor.decodeGeneratedCodeInfo;
pub const stringifyJson = json.stringify;
pub const stringifyJsonAlloc = json.stringifyAlloc;
pub const stringifyJsonAllocWithRegistry = json.stringifyAllocWithRegistry;
pub const stringifyJsonWithRegistry = json.stringifyWithRegistry;
pub const parseJsonAlloc = json.parseAlloc;
pub const parseJsonAllocWithRegistry = json.parseAllocWithRegistry;
pub const parseJsonInitializedAlloc = json.parseInitializedAlloc;
pub const parseJsonInitializedAllocWithRegistry = json.parseInitializedAllocWithRegistry;
pub const Registry = registry.Registry;
pub const ImportChain = registry.ImportChain;
pub const Reflection = reflect.Reflection;
pub const formatText = text.format;
pub const formatTextWithRegistry = text.formatWithRegistry;
pub const formatTextAlloc = text.formatAlloc;
pub const formatTextAllocWithRegistry = text.formatAllocWithRegistry;
pub const parseTextAlloc = text.parseAlloc;
pub const parseTextAllocWithRegistry = text.parseAllocWithRegistry;
pub const parseTextInitializedAlloc = text.parseInitializedAlloc;
pub const parseTextInitializedAllocWithRegistry = text.parseInitializedAllocWithRegistry;
pub const MemorySourceTree = loader.MemorySourceTree;
pub const loadMemory = loader.loadMemory;
pub const loadPath = loader.loadPath;
pub const loadDir = loader.loadDir;
pub const Timestamp = wkt.Timestamp;
pub const Duration = wkt.Duration;
pub const FieldMask = wkt.FieldMask;
pub const Any = wkt.Any;
pub const Empty = wkt.Empty;
pub const Struct = wkt.Struct;
pub const Value = wkt.Value;
pub const ListValue = wkt.ListValue;
pub const NullValue = wkt.NullValue;
pub const DoubleValue = wkt.DoubleValue;
pub const FloatValue = wkt.FloatValue;
pub const Int64Value = wkt.Int64Value;
pub const UInt64Value = wkt.UInt64Value;
pub const Int32Value = wkt.Int32Value;
pub const UInt32Value = wkt.UInt32Value;
pub const BoolValue = wkt.BoolValue;
pub const StringValue = wkt.StringValue;
pub const BytesValue = wkt.BytesValue;
pub const CodeGeneratorRequest = plugin.CodeGeneratorRequest;
pub const CodeGeneratorResponse = plugin.CodeGeneratorResponse;
pub const generateZigFile = codegen.generateZigFile;
pub const generateZigFileWithRegistry = codegen.generateZigFileWithRegistry;
pub const generatePluginResponse = codegen.generatePluginResponse;
pub const generatePluginResponseFromRequest = codegen.generatePluginResponseFromRequest;
pub const generatePluginResponseFromRequestBytes = codegen.generatePluginResponseFromRequestBytes;
pub const runPluginRequest = codegen.runPluginRequest;
pub const runPluginRequestBytes = codegen.runPluginRequestBytes;
pub const ConformanceRequest = conformance.ConformanceRequest;
pub const ConformanceResponse = conformance.ConformanceResponse;
pub const runConformanceDynamic = conformance.runDynamic;
pub const scalarTypeName = schema.scalarTypeName;
pub const declarationTypeNameIsScalar = schema.declarationTypeNameIsScalar;
pub const declarationSymbolIsQualified = schema.declarationSymbolIsQualified;
pub const isFullIdentifier = schema.isFullIdentifier;
pub const isIdentifier = schema.isIdentifier;

pub inline fn validateUtf8(value: []const u8) bool {
    const std = @import("std");
    const word_size = @sizeOf(usize);
    const high_bit_mask = comptime blk: {
        var mask: usize = 0;
        var i: usize = 0;
        while (i < word_size) : (i += 1) mask |= @as(usize, 0x80) << @intCast(i * 8);
        break :blk mask;
    };

    var index: usize = 0;
    while (index + word_size <= value.len) : (index += word_size) {
        const word = std.mem.readInt(usize, value[index..][0..word_size], .little);
        if ((word & high_bit_mask) != 0) return std.unicode.utf8ValidateSlice(value);
    }
    while (index < value.len) : (index += 1) {
        if (value[index] >= 0x80) return std.unicode.utf8ValidateSlice(value);
    }
    return true;
}

test {
    _ = wire;
    _ = schema;
    _ = parser;
    _ = dynamic;
    _ = descriptor;
    _ = json;
    _ = registry;
    _ = reflect;
    _ = text;
    _ = loader;
    _ = wkt;
    _ = plugin;
    _ = codegen;
    _ = conformance;
}

test "root exports descriptor schema support types" {
    const std = @import("std");
    try std.testing.expectEqual(Syntax.proto3, schema.Syntax.proto3);
    try std.testing.expectEqual(Edition.edition_2023, schema.Edition.edition_2023);
    try std.testing.expectEqual(Cardinality.repeated, schema.Cardinality.repeated);
    try std.testing.expectEqual(ScalarType.int32, schema.ScalarType.int32);
    try std.testing.expectEqualStrings("int32", scalarTypeName(.int32));
    try std.testing.expect(declarationTypeNameIsScalar("bytes"));
    try std.testing.expect(declarationSymbolIsQualified(".demo.Type"));
    try std.testing.expect(isFullIdentifier("demo.Type"));
    try std.testing.expect(isIdentifier("field_name"));
    const option_value = OptionValue{ .integer = 7 };
    const option = FieldOption{ .name = "answer", .value = option_value };
    try std.testing.expectEqual(@as(i64, 7), option.value.integer);
    try std.testing.expectEqual(FieldCType.string, schema.optionAsKnownEnum(FieldCType, .{ .identifier = "STRING" }).?);
    try std.testing.expectEqual(FieldJSType.js_string, schema.optionAsKnownEnum(FieldJSType, .{ .identifier = "JS_STRING" }).?);
    try std.testing.expectEqual(MethodIdempotencyLevel.no_side_effects, schema.optionAsKnownEnum(MethodIdempotencyLevel, .{ .identifier = "NO_SIDE_EFFECTS" }).?);
    const kind = FieldKind{ .scalar = .int32 };
    try std.testing.expectEqual(wire.WireType.varint, kind.wireType());
    var value_kind = FieldKind{ .scalar = .string };
    const map_type = MapType{ .key = .string, .value = &value_kind };
    try std.testing.expectEqual(ScalarType.string, map_type.key);
    const import = Import{ .path = "common.proto", .kind = .public };
    try std.testing.expectEqualStrings("common.proto", import.path);
    try std.testing.expect((ReservedRange{ .start = 10, .end = 20 }).containsWithMax(19, 100));
    try std.testing.expect((ExtensionRange{ .start = 100, .end = 200 }).containsWithMax(199, 1000));
    try std.testing.expectEqual(ExtensionRangeVerification.declaration, .declaration);
}

test "root exports dynamic support types" {
    const std = @import("std");
    const value = DynamicValue{ .int32 = 7 };
    try std.testing.expectEqual(@as(i32, 7), value.int32);
    const default_value = DynamicDefaultValue{ .string = "ok" };
    try std.testing.expectEqualStrings("ok", default_value.string);
    var field_value = DynamicFieldValue{ .descriptor = undefined };
    field_value.values = .empty;
    try std.testing.expectEqual(@as(usize, 0), field_value.values.items.len);
    const entry = DynamicMapEntry{ .key = .{ .string = @constCast("k") }, .value = .{ .int32 = 1 } };
    try std.testing.expectEqualStrings("k", entry.key.string);
    const unknown = DynamicUnknownField{ .number = 7, .wire_type = .varint, .data = @constCast(&[_]u8{ 0x38, 0x01 }) };
    try std.testing.expectEqual(@as(FieldNumber, 7), unknown.number);
}

test "root exports registry-aware codegen" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message User { optional int32 id = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event { optional .common.User user = 1; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var reg = Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&common);
    try reg.addFile(&app);
    const generated = try generateZigFileWithRegistry(allocator, &app, &reg);
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "imports.common_proto.common.User") != null);
}

test "root exports request-based plugin codegen" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var request = CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    try request.files_to_generate.append(allocator, "app.proto");
    try request.appendProtoFile(try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\message App { optional int32 id = 1; }
    ));
    request.proto_files.items[0].name = "app.proto";
    const response = try generatePluginResponseFromRequest(allocator, &request);
    defer allocator.free(response);
    try std.testing.expect(response.len != 0);
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try runPluginRequest(allocator, &request, &out.writer);
    try std.testing.expect(out.written().len != 0);
}

test "root exports registry-aware text formatting" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.Kind kind = 1; }
    );
    defer app.deinit();
    var reg = Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&common);
    try reg.addFile(&app);
    const desc = app.findMessage("Event").?;
    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("kind").?, .{ .enumeration = 1 });
    const rendered = try formatTextAllocWithRegistry(allocator, &app, &reg, &msg, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("kind: ADMIN\n", rendered);
}
