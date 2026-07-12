const std = @import("std");
const pbz = @import("pbz");
const streaming_pb = @import("generated/streaming.pb.zig");

const streaming = streaming_pb.demo.streaming;
const Event = streaming.Event;

const RequestStream = struct {
    items: []const Event,
    index: usize = 0,

    pub fn next(self: *@This()) !?Event {
        if (self.index >= self.items.len) return null;
        const item = self.items[self.index];
        self.index += 1;
        return item;
    }
};

const ResponseSink = struct {
    ids: [8]i32 = undefined,
    count: usize = 0,

    pub fn append(self: *@This(), _: std.mem.Allocator, item: Event) !void {
        if (self.count >= self.ids.len) return error.NoSpaceLeft;
        self.ids[self.count] = item.id;
        self.count += 1;
    }
};

const PipeImpl = struct {
    pub fn Get(_: *@This(), allocator: std.mem.Allocator, request: Event) !Event {
        var response = try request.cloneOwned(allocator);
        response.id += 100;
        return response;
    }

    pub fn Upload(_: *@This(), _: std.mem.Allocator, requests: anytype) !Event {
        var response = Event.init();
        response.note = "upload-summary";
        while (try requests.next()) |item| response.id += item.id;
        return response;
    }

    pub fn Watch(_: *@This(), allocator: std.mem.Allocator, request: Event, responses: anytype) !void {
        var first = try request.cloneOwned(allocator);
        defer first.deinit(allocator);
        first.id += 1;
        try responses.append(allocator, first);

        var second = try request.cloneOwned(allocator);
        defer second.deinit(allocator);
        second.id += 2;
        try responses.append(allocator, second);
    }

    pub fn Chat(_: *@This(), allocator: std.mem.Allocator, requests: anytype, responses: anytype) !void {
        while (try requests.next()) |item| {
            var response = try item.cloneOwned(allocator);
            defer response.deinit(allocator);
            response.id += 10;
            try responses.append(allocator, response);
        }
    }
};

const PipeHandler = streaming.services.Pipe.Handler(PipeImpl);

const InMemoryTransport = struct {
    handler: *PipeHandler,

    pub fn call(self: *@This(), allocator: std.mem.Allocator, service: []const u8, method: []const u8, request_payload: []const u8) ![]u8 {
        std.debug.assert(std.mem.eql(u8, service, streaming.services.Pipe.name));
        return try self.handler.dispatchRaw(allocator, method, request_payload) orelse error.UnknownMethod;
    }

    pub fn callClientStream(self: *@This(), allocator: std.mem.Allocator, service: []const u8, method: []const u8, requests: anytype) ![]u8 {
        std.debug.assert(std.mem.eql(u8, service, streaming.services.Pipe.name));
        std.debug.assert(std.mem.eql(u8, method, streaming.services.Pipe.Upload.name));
        var response = try self.handler.Upload(allocator, requests);
        defer response.deinit(allocator);
        return try response.encode(allocator);
    }

    pub fn callServerStream(self: *@This(), allocator: std.mem.Allocator, service: []const u8, method: []const u8, request_payload: []const u8, responses: anytype) !void {
        std.debug.assert(std.mem.eql(u8, service, streaming.services.Pipe.name));
        std.debug.assert(std.mem.eql(u8, method, streaming.services.Pipe.Watch.name));
        var request = try Event.decodeOwned(allocator, request_payload);
        defer request.deinit(allocator);
        try self.handler.Watch(allocator, request, responses);
    }

    pub fn callBidiStream(self: *@This(), allocator: std.mem.Allocator, service: []const u8, method: []const u8, requests: anytype, responses: anytype) !void {
        std.debug.assert(std.mem.eql(u8, service, streaming.services.Pipe.name));
        std.debug.assert(std.mem.eql(u8, method, streaming.services.Pipe.Chat.name));
        try self.handler.Chat(allocator, requests, responses);
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    std.debug.assert(streaming.services.Pipe.Get.input_type_ref == Event);
    std.debug.assert(streaming.services.Pipe.Upload.client_streaming);
    std.debug.assert(streaming.services.Pipe.Watch.server_streaming);
    std.debug.assert(streaming.services.Pipe.Chat.client_streaming and streaming.services.Pipe.Chat.server_streaming);

    var impl = PipeImpl{};
    var handler = PipeHandler.init(&impl);
    const PipeClient = streaming.services.Pipe.Client(InMemoryTransport);
    var client = PipeClient.init(.{ .handler = &handler });

    var request = Event.init();
    defer request.deinit(allocator);
    request.id = 7;
    request.note = "request";

    var unary = try client.Get(allocator, request);
    defer unary.deinit(allocator);
    std.debug.assert(unary.id == 107);

    var upload_items = [_]Event{ Event.init(), Event.init(), Event.init() };
    upload_items[0].id = 1;
    upload_items[1].id = 2;
    upload_items[2].id = 3;
    var upload_stream = RequestStream{ .items = &upload_items };
    var upload_response = try client.Upload(allocator, &upload_stream);
    defer upload_response.deinit(allocator);
    std.debug.assert(upload_response.id == 6);
    std.debug.assert(std.mem.eql(u8, upload_response.note, "upload-summary"));

    var watch_sink = ResponseSink{};
    try client.Watch(allocator, request, &watch_sink);
    std.debug.assert(watch_sink.count == 2);
    std.debug.assert(watch_sink.ids[0] == 8 and watch_sink.ids[1] == 9);

    var chat_items = [_]Event{ Event.init(), Event.init() };
    chat_items[0].id = 5;
    chat_items[1].id = 9;
    var chat_stream = RequestStream{ .items = &chat_items };
    var chat_sink = ResponseSink{};
    try client.Chat(allocator, &chat_stream, &chat_sink);
    std.debug.assert(chat_sink.count == 2);
    std.debug.assert(chat_sink.ids[0] == 15 and chat_sink.ids[1] == 19);
}

comptime {
    _ = pbz;
}
