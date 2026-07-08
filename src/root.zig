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
pub const FileDescriptor = schema.FileDescriptor;
pub const MessageDescriptor = schema.MessageDescriptor;
pub const FieldDescriptor = schema.FieldDescriptor;
pub const SourceCodeInfo = schema.SourceCodeInfo;
pub const ProtoParser = parser.Parser;
pub const DynamicMessage = dynamic.DynamicMessage;
pub const encodeFileDescriptorProto = descriptor.encodeFileDescriptorProto;
pub const encodeFileDescriptorSet = descriptor.encodeFileDescriptorSet;
pub const decodeFileDescriptorProto = descriptor.decodeFileDescriptorProto;
pub const decodeFileDescriptorSet = descriptor.decodeFileDescriptorSet;
pub const stringifyJson = json.stringify;
pub const stringifyJsonAlloc = json.stringifyAlloc;
pub const parseJsonAlloc = json.parseAlloc;
pub const Registry = registry.Registry;
pub const formatText = text.format;
pub const formatTextAlloc = text.formatAlloc;
pub const parseTextAlloc = text.parseAlloc;
pub const parseTextAllocWithRegistry = text.parseAllocWithRegistry;
pub const MemorySourceTree = loader.MemorySourceTree;
pub const loadMemory = loader.loadMemory;
pub const loadPath = loader.loadPath;
pub const loadDir = loader.loadDir;
pub const Timestamp = wkt.Timestamp;
pub const Duration = wkt.Duration;
pub const FieldMask = wkt.FieldMask;
pub const Any = wkt.Any;
pub const Empty = wkt.Empty;
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
pub const generatePluginResponse = codegen.generatePluginResponse;
pub const ConformanceRequest = conformance.ConformanceRequest;
pub const ConformanceResponse = conformance.ConformanceResponse;
pub const runConformanceDynamic = conformance.runDynamic;

test {
    _ = wire;
    _ = schema;
    _ = parser;
    _ = dynamic;
    _ = descriptor;
    _ = json;
    _ = registry;
    _ = text;
    _ = loader;
    _ = wkt;
    _ = plugin;
    _ = codegen;
    _ = conformance;
}
