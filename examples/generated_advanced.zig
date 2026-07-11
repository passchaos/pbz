const std = @import("std");
const pbz = @import("pbz");
const advanced_pb = @import("generated/advanced.pb.zig");

const adv = advanced_pb.demo.advanced;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Proto package maps to nested Zig namespaces: package demo.advanced ->
    // advanced_pb.demo.advanced.
    std.debug.assert(std.mem.eql(u8, advanced_pb.proto_package, "demo.advanced"));
    std.debug.assert(adv.Kind.fromName("KIND_PERSON") == .KIND_PERSON);
    std.debug.assert(adv.Kind.KIND_ORG.toInt() == 2);

    var audit = adv.Envelope.Audit.init();
    defer audit.deinit(allocator);
    audit.actor = "tester";
    audit.at_unix = 12345;
    var envelope = adv.Envelope.init();
    defer envelope.deinit(allocator);
    envelope.id = 42;
    envelope.kind = adv.Kind.KIND_PERSON.toInt();
    envelope.audit = audit;
    envelope.subject = .{ .user_name = "ziggy" };

    const bytes = try envelope.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var decoded = try adv.Envelope.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    std.debug.assert(decoded.id == 42);
    std.debug.assert(adv.Kind.fromInt(decoded.kind) == .KIND_PERSON);
    switch (decoded.subject) {
        .user_name => |name| std.debug.assert(std.mem.eql(u8, name, "ziggy")),
        else => return error.UnexpectedOneof,
    }

    // Same-file generated message metadata exposes type refs for nested payloads.
    std.debug.assert(adv.Envelope.audit_field.has_type_ref);
    const AuditRef = adv.Envelope.audit_field.type_ref;
    const decoded_audit: AuditRef = decoded.audit orelse return error.MissingAudit;
    std.debug.assert(std.mem.eql(u8, decoded_audit.actor, "tester"));

    const json = try decoded.jsonStringifyAllocWithOptions(allocator, .{ .preserve_proto_field_names = true });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"user_name\":\"ziggy\"") != null);

    // Service metadata is generated without imposing an RPC runtime.
    std.debug.assert(std.mem.eql(u8, adv.services.Directory.name, "Directory"));
    std.debug.assert(adv.services.Directory.Get.input_has_type_ref);
    std.debug.assert(adv.services.Directory.Get.input_type_ref == adv.Envelope);
    std.debug.assert(adv.services.Directory.Watch.server_streaming);
}

comptime {
    _ = pbz;
}
