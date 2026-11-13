const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // C++/Rust-style flow: import the generated module and use the package
    // namespace plus concrete message type directly.
    var person = person_pb.demo.Person.init();
    defer person.deinit(allocator);

    person.id = 7;
    person.name = "Zig";
    person.scores = try allocator.dupe(i32, &.{ 10, 20 });
    try person.counts.put(allocator, "red", 1);

    // Map fields are generated as Zig map containers, matching C++/Rust/Go-style
    // typed map usage while retaining protobuf last-wins merge semantics.
    var other = person_pb.demo.Person.init();
    defer other.deinit(allocator);
    try other.counts.put(allocator, "red", 2);
    try person.mergeFrom(allocator, other);
    std.debug.assert(person.counts.count() == 1);
    std.debug.assert(person.counts.get("red").? == 2);

    // Protobuf JSON rejects duplicate object keys instead of applying
    // last-wins semantics.
    try std.testing.expectError(error.DuplicateField, person_pb.demo.Person.jsonParse(allocator,
        \\{"counts":{"red":1,"red":3}}
    ));

    // The same field reached through two accepted spellings is also a
    // duplicate, and two different members of one oneof are rejected.
    try std.testing.expectError(error.DuplicateField, person_pb.demo.ScalarMix.jsonParse(allocator,
        \\{"big_delta":1,"bigDelta":2}
    ));
    try std.testing.expectError(error.DuplicateField, person_pb.demo.PresenceMix.jsonParse(allocator,
        \\{"name":"a","code":2}
    ));
    {
        var oneof = try person_pb.demo.PresenceMix.jsonParse(allocator,
            \\{"name":"a"}
        );
        defer oneof.deinit(allocator);
        std.debug.assert(std.meta.activeTag(oneof.pick) == .name);
    }

    // Packed fixed-width numeric fields expose zero-copy helpers when the
    // wire buffer can be inspected directly (little-endian targets).
    var signed_fixed = person_pb.demo.SFixedPacked.init();
    defer signed_fixed.deinit(allocator);
    signed_fixed.values = try allocator.dupe(i32, &.{ -7, 0, 42, -1024 });
    const signed_fixed_bytes = try signed_fixed.encode(allocator);
    defer allocator.free(signed_fixed_bytes);

    const signed_fixed_view = (try person_pb.demo.SFixedPacked.valuesPackedFixedView(signed_fixed_bytes)).?;
    std.debug.assert(signed_fixed_view.len == signed_fixed.values.len);
    for (signed_fixed_view, signed_fixed.values) |actual, expected| {
        std.debug.assert(actual == expected);
    }

    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.SFixedPacked.valuesPackedFixedSlices(&header, signed_fixed.values);
    std.debug.assert(std.mem.eql(u8, slices.header, signed_fixed_bytes[0..slices.header.len]));

    const bytes = try person.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var stack_buffer: [128]u8 = undefined;
    const stack_bytes = try person.encodeInto(&stack_buffer);
    std.debug.assert(std.mem.eql(u8, stack_bytes, bytes));
    const fast_stack_bytes = try person.encodeIntoAssumeCapacity(&stack_buffer);
    std.debug.assert(std.mem.eql(u8, fast_stack_bytes, bytes));

    var decoded = try person_pb.demo.Person.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    std.debug.assert(decoded.id == 7);
    std.debug.assert(std.mem.eql(u8, decoded.name, "Zig"));

    // Unknown fields preserve the exact source bytes. This deliberately uses a
    // non-canonical three-byte encoding for field 100's tag; callers that store
    // raw unknowns need the original byte sequence, not a normalized tag.
    const noncanonical_unknown = [_]u8{ 0xa0, 0x86, 0x00, 0x01 };
    var unknown_decoded = try person_pb.demo.Person.decode(allocator, &noncanonical_unknown);
    defer unknown_decoded.deinit(allocator);
    std.debug.assert(unknown_decoded.unknownFieldCount() == 1);
    std.debug.assert(std.mem.eql(u8, unknown_decoded.unknownFields()[0], &noncanonical_unknown));
    const unknown_roundtrip = try unknown_decoded.encode(allocator);
    defer allocator.free(unknown_roundtrip);
    std.debug.assert(std.mem.eql(u8, unknown_roundtrip, &noncanonical_unknown));

    // A known field number with an unexpected wire type is an unknown field,
    // not a value to reinterpret. The first occurrence below is field 1
    // encoded as length-delimited; it must be preserved byte-for-byte while
    // the following valid varint occurrence still sets id = 42.
    const wrong_wire_type = [_]u8{ 0x0A, 0x01, 0x08, 0x08, 0x2A };
    var wrong_wire_decoded = try person_pb.demo.Person.decode(allocator, &wrong_wire_type);
    defer wrong_wire_decoded.deinit(allocator);
    std.debug.assert(wrong_wire_decoded.id == 42);
    std.debug.assert(wrong_wire_decoded.unknownFieldCount() == 1);
    std.debug.assert(std.mem.eql(u8, wrong_wire_decoded.unknownFields()[0], &.{ 0x0A, 0x01, 0x08 }));

    // mergeFrom owns its destination strings/bytes. Merging from a JSON-parsed
    // source must not alias the source arena; freeing the source below proves
    // the destination remains valid.
    var merge_source = try person_pb.demo.Person.jsonParse(allocator, "{\"name\":\"merged\"}");
    errdefer merge_source.deinit(allocator);
    var merge_target = person_pb.demo.Person.init();
    defer merge_target.deinit(allocator);
    try merge_target.mergeFrom(allocator, merge_source);
    merge_source.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, merge_target.name, "merged"));

    // Generated files embed their FileDescriptorProto so generated types can
    // participate in registry/reflection workflows without re-parsing .proto
    // source at runtime.
    var file_descriptor = try person_pb.decodeFileDescriptor(allocator);
    defer file_descriptor.deinit();
    std.debug.assert(std.mem.eql(u8, file_descriptor.package, "demo"));
    const person_descriptor = file_descriptor.findMessage("Person") orelse unreachable;
    std.debug.assert(person_descriptor.fields.items.len == 4);
    std.debug.assert(person_pb.demo.Person.descriptor(&file_descriptor).? == person_descriptor);
    std.debug.assert(person_pb.demo.PresenceMix.Child.descriptor(&file_descriptor) != null);
    std.debug.assert(person_pb.demo.BenchKind.descriptor(&file_descriptor) != null);

    var dynamic_person = try person.toDynamic(allocator, &file_descriptor);
    defer dynamic_person.deinit();
    std.debug.assert(dynamic_person.get("id").?.values.items[0].int32 == 7);
    var bridged_person = try person_pb.demo.Person.fromDynamic(allocator, &file_descriptor, &dynamic_person);
    defer bridged_person.deinit(allocator);
    std.debug.assert(bridged_person.id == 7);
    std.debug.assert(std.mem.eql(u8, bridged_person.name, "Zig"));

    // The generated fast TextFormat parser is line-oriented; the conformant
    // entry point delegates to the dynamic parser for the full TextFormat
    // surface, including repeated list syntax.
    var conformant_text = try person_pb.demo.Person.parseTextConformant(allocator,
        \\scores: [10, 20]
        \\counts { key: "red" value: 1 }
    );
    defer conformant_text.deinit(allocator);
    std.debug.assert(std.mem.eql(i32, conformant_text.scores, &.{ 10, 20 }));
    std.debug.assert(conformant_text.counts.get("red").? == 1);

    var conformant_json = try person_pb.demo.Person.jsonParseConformant(allocator,
        \\{"id":7,"name":"Zig","scores":[10,20]}
    );
    defer conformant_json.deinit(allocator);
    std.debug.assert(conformant_json.id == 7);
    std.debug.assert(std.mem.eql(u8, conformant_json.name, "Zig"));

    var clear_target = try person_pb.demo.Person.jsonParse(allocator, "{\"id\":7,\"name\":\"Zig\"}");
    defer clear_target.deinit(allocator);
    clear_target.clear(allocator);
    std.debug.assert(clear_target.id == 0);
    std.debug.assert(clear_target.name.len == 0);

    // decodeOwned adopts borrowed wire payloads in place; freeing the input
    // below must leave the decoded strings and map keys valid.
    const owned_wire = try person.encode(allocator);
    var owned_person = try person_pb.demo.Person.decodeOwned(allocator, owned_wire);
    defer owned_person.deinit(allocator);
    allocator.free(owned_wire);
    std.debug.assert(std.mem.eql(u8, owned_person.name, "Zig"));
    std.debug.assert(owned_person.counts.get("red").? == 2);

    const json = try decoded.jsonStringifyAllocWithOptions(allocator, .{
        .preserve_proto_field_names = true,
        .always_print_primitive_fields = true,
    });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"scores\":[10,20]") != null);

    // Protobuf JSON allows unquoted exponent spellings for integer tokens when
    // the represented value is integral and in range. Keeping this in the
    // public generated-type example guards the same compatibility surface that
    // C++ and Go protobuf expose for generated messages.
    var exponent_scalars = try person_pb.demo.ScalarMix.jsonParse(allocator,
        \\{"count":1.2345e4,"total":9.87654321e9,"delta":-3.21e2,"ids":[1e0,1.27e2,1.28e2]}
    );
    defer exponent_scalars.deinit(allocator);
    std.debug.assert(exponent_scalars.count == 12345);
    std.debug.assert(exponent_scalars.total == 9_876_543_210);
    std.debug.assert(exponent_scalars.delta == -321);
    std.debug.assert(std.mem.eql(u64, exponent_scalars.ids, &.{ 1, 127, 128 }));

    var parsed = try person_pb.demo.Person.parseText(allocator,
        \\id: 8
        \\name: "Text"
        \\scores: 30
        \\counts {
        \\  key: "blue"
        \\  value: 3
        \\}
    );
    defer parsed.deinit(allocator);
    std.debug.assert(parsed.id == 8);
}

// Keep the runtime import visibly used in the example even though the generated
// file itself imports pbz.
comptime {
    _ = pbz;
}
