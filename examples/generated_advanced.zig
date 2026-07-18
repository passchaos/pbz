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
    var review = adv.Envelope.Audit.init();
    defer review.deinit(allocator);
    review.actor = "reviewer";
    review.at_unix = 67890;

    var envelope = adv.Envelope.init();
    defer envelope.deinit(allocator);
    envelope.id = 42;
    envelope.kind = adv.Kind.KIND_PERSON.toInt();
    envelope.audit = audit;
    envelope.subject = .{ .user_name = "ziggy" };
    try envelope.audits.put(allocator, "latest", try audit.cloneOwned(allocator));
    {
        var owned = try review.cloneOwned(allocator);
        errdefer owned.deinit(allocator);
        const old = try envelope.audits.fetchPut(allocator, "latest", owned);
        if (old) |entry| {
            var old_value = entry.value;
            old_value.deinit(allocator);
        }
    }

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
    std.debug.assert(adv.Envelope.audits_field.map_value_has_type_ref);
    const MapAuditRef = adv.Envelope.audits_field.map_value_type_ref;
    std.debug.assert(decoded.audits.count() == 1);
    const decoded_map_audit: MapAuditRef = decoded.audits.get("latest") orelse return error.MissingAudit;
    std.debug.assert(std.mem.eql(u8, decoded_map_audit.actor, "reviewer"));

    const json = try decoded.jsonStringifyAllocWithOptions(allocator, .{ .preserve_proto_field_names = true });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"user_name\":\"ziggy\"") != null);
    std.debug.assert(std.mem.indexOf(u8, json, "\"audits\":") != null);
    std.debug.assert(std.mem.indexOf(u8, json, "\"reviewer\"") != null);
    var json_roundtrip = try adv.Envelope.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    std.debug.assert(json_roundtrip.audits.count() == 1);
    std.debug.assert(std.mem.eql(u8, (json_roundtrip.audits.get("latest") orelse return error.MissingAudit).actor, "reviewer"));

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    std.debug.assert(std.mem.indexOf(u8, text, "audits {") != null);
    std.debug.assert(std.mem.indexOf(u8, text, "reviewer") != null);
    var text_roundtrip = try adv.Envelope.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    std.debug.assert(text_roundtrip.audits.count() == 1);
    std.debug.assert(std.mem.eql(u8, (text_roundtrip.audits.get("latest") orelse return error.MissingAudit).actor, "reviewer"));

    var audit_subject_envelope = adv.Envelope.init();
    defer audit_subject_envelope.deinit(allocator);
    audit_subject_envelope.id = 43;
    audit_subject_envelope.subject = .{ .audit_subject = audit };
    const audit_subject_bytes = try audit_subject_envelope.encodeInitialized(allocator);
    defer allocator.free(audit_subject_bytes);
    var decoded_audit_subject = try adv.Envelope.decodeOwnedInitialized(allocator, audit_subject_bytes);
    defer decoded_audit_subject.deinit(allocator);
    switch (decoded_audit_subject.subject) {
        .audit_subject => |subject_audit| std.debug.assert(std.mem.eql(u8, subject_audit.actor, "tester")),
        else => return error.UnexpectedOneof,
    }

    // Service metadata plus lightweight unary handler/client adapters are
    // generated without imposing a concrete network runtime.
    std.debug.assert(std.mem.eql(u8, adv.services.Directory.name, "Directory"));
    std.debug.assert(adv.services.Directory.Get.input_has_type_ref);
    std.debug.assert(adv.services.Directory.Get.input_type_ref == adv.Envelope);
    std.debug.assert(adv.services.Directory.Watch.server_streaming);

    const DirectoryImpl = struct {
        pub fn Get(_: *@This(), alloc: std.mem.Allocator, request: adv.Envelope) !adv.Envelope {
            var out = try request.cloneOwned(alloc);
            out.id += 1;
            return out;
        }

        pub fn Watch(_: *@This(), alloc: std.mem.Allocator, request: adv.Envelope, responses: anytype) !void {
            try responses.append(alloc, request);
        }
    };
    const DirectoryHandler = adv.services.Directory.Handler(DirectoryImpl);
    var impl = DirectoryImpl{};
    var handler = DirectoryHandler.init(&impl);
    const raw_response = try handler.dispatchRaw(allocator, "Get", bytes) orelse return error.MissingResponse;
    defer allocator.free(raw_response);
    var decoded_response = try adv.Envelope.decodeOwnedInitialized(allocator, raw_response);
    defer decoded_response.deinit(allocator);
    std.debug.assert(decoded_response.id == 43);

    const StreamSink = struct {
        count: usize = 0,

        pub fn append(self: *@This(), _: std.mem.Allocator, item: adv.Envelope) !void {
            std.debug.assert(item.id == 42);
            self.count += 1;
        }
    };
    var sink = StreamSink{};
    try handler.Watch(allocator, decoded, &sink);
    std.debug.assert(sink.count == 1);
}

comptime {
    _ = pbz;
}
