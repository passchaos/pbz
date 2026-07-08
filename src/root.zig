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

pub const Allocator = @import("std").mem.Allocator;
pub const FieldNumber = wire.FieldNumber;
pub const WireType = wire.WireType;
pub const Reader = wire.Reader;
pub const Writer = wire.Writer;
pub const FileDescriptor = schema.FileDescriptor;
pub const MessageDescriptor = schema.MessageDescriptor;
pub const FieldDescriptor = schema.FieldDescriptor;
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

test {
    _ = wire;
    _ = schema;
    _ = parser;
    _ = dynamic;
    _ = descriptor;
    _ = json;
    _ = registry;
    _ = text;
}
