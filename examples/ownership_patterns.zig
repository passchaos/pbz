const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

pub fn main() !void {
    var backing = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(backing.deinit() == .ok);
    const backing_allocator = backing.allocator();

    // Request/arena style: allocate all short-lived generated data from an
    // arena, skip per-message deinit for those arena-backed values, and free the
    // whole graph in one operation.
    var stable_person = person_pb.demo.Person.init();
    defer stable_person.deinit(backing_allocator);
    {
        var request_arena = std.heap.ArenaAllocator.init(backing_allocator);
        defer request_arena.deinit();
        const arena = request_arena.allocator();

        var person = person_pb.demo.Person.init();
        person.id = 42;
        person.name = "arena-user";
        person.scores = try arena.dupe(i32, &.{ 1, 2, 3, 5, 8 });
        try person.counts.put(arena, try arena.dupe(u8, "blue"), 8);

        const wire = try person.encode(arena);
        var decoded = try person_pb.demo.Person.decode(arena, wire);
        std.debug.assert(decoded.id == 42);
        std.debug.assert(decoded.scores.len == 5);
        std.debug.assert(decoded.counts.get("blue").? == 8);

        // Clone the arena-backed value into a long-lived allocator before the
        // arena is discarded.
        stable_person = try decoded.cloneOwned(backing_allocator);
    }
    std.debug.assert(stable_person.id == 42);
    std.debug.assert(stable_person.counts.get("blue").? == 8);

    // Long-lived generated values can still use explicit deinit plus decodeReuse
    // to keep repeated-field buffers across iterations.
    var scalar_template = person_pb.demo.ScalarMix.init();
    defer scalar_template.deinit(backing_allocator);
    scalar_template.active = true;
    scalar_template.count = 7;
    scalar_template.total = 123;
    scalar_template.delta = -1;
    scalar_template.big_delta = -2;
    scalar_template.checksum = 0x1234;
    scalar_template.token = 0x5678;
    scalar_template.signed_fixed = -3;
    scalar_template.signed_big_fixed = -4;
    scalar_template.ratio = 1.5;
    scalar_template.score = 2.5;
    scalar_template.kind = person_pb.demo.BenchKind.BENCH_KIND_ALPHA.toInt();
    scalar_template.flags = try backing_allocator.dupe(bool, &.{ true, false, true, true });
    scalar_template.ids = try backing_allocator.dupe(u64, &.{ 1, 128, 4096, 65536 });

    const scalar_wire = try scalar_template.encode(backing_allocator);
    defer backing_allocator.free(scalar_wire);
    var reusable = person_pb.demo.ScalarMix.init();
    defer reusable.deinit(backing_allocator);
    try reusable.decodeReuse(backing_allocator, scalar_wire);
    const flags_ptr = reusable.flags.ptr;
    try reusable.decodeReuse(backing_allocator, scalar_wire);
    std.debug.assert(reusable.flags.ptr == flags_ptr);
    std.debug.assert(reusable.ids[3] == 65536);

    // The same arena pattern works for dynamic/reflection-oriented messages.
    {
        var dynamic_arena = std.heap.ArenaAllocator.init(backing_allocator);
        defer dynamic_arena.deinit();
        const arena = dynamic_arena.allocator();

        var file = try pbz.ProtoParser.parse(arena,
            \\syntax = "proto3";
            \\message Event {
            \\  int32 id = 1;
            \\  repeated string tags = 2;
            \\  map<string, int32> counts = 3;
            \\}
        );
        const desc = file.findMessage("Event").?;
        var event = pbz.DynamicMessage.init(arena, desc);
        try event.add(desc.findField("id").?, .{ .int32 = 99 });
        try event.add(desc.findField("tags").?, .{ .string = try arena.dupe(u8, "arena") });
        const entry = try arena.create(pbz.dynamic.MapEntry);
        entry.* = .{ .key = .{ .string = try arena.dupe(u8, "hits") }, .value = .{ .int32 = 3 } };
        try event.add(desc.findField("counts").?, .{ .map_entry = entry });

        const event_wire = try event.encoded(&file);
        var decoded_event = pbz.DynamicMessage.init(arena, desc);
        try decoded_event.decode(&file, event_wire);
        std.debug.assert(decoded_event.get("id").?.values.items[0].int32 == 99);
        std.debug.assert(decoded_event.get("counts").?.values.items[0].map_entry.value.int32 == 3);
    }
}
