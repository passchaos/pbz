const std = @import("std");

const cg = @import("../codegen.zig");
const registry_mod = @import("../registry.zig");
const schema = @import("../schema.zig");
const wire = @import("../wire.zig");
const plugin = @import("../plugin.zig");

test "codegen emits zig message and enum skeletons" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message User { string name = 1; Kind kind = 2; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Kind = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn fromInt(value: i32) ?@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "0 => .UNKNOWN,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn toInt(self: @This()) i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn protoName(self: @This()) []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".ADMIN => \"ADMIN\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn fromName(name: []const u8) ?@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, name, \"ADMIN\")) return .ADMIN;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParse(value: pbz.json.Value) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".string => |name| fromName(name) orelse error.InvalidEnumValue,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn textParse(value: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (fromName(value)) |known| return known;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn textFormat(self: @This(), writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const User = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const name_number = 1") != null);
}

test "codegen emits Zig enum aliases for proto allow_alias" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Alias {
        \\  option allow_alias = true;
        \\  UNKNOWN = 0;
        \\  STARTED = 1;
        \\  RUNNING = 1;
        \\  ACTIVE = 1;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Alias = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "STARTED = 1,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const RUNNING = @This().STARTED;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const ACTIVE = @This().STARTED;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => .STARTED,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".STARTED => \"STARTED\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".RUNNING =>") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, name, \"RUNNING\")) return .STARTED;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, name, \"ACTIVE\")) return .STARTED;") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits file-relative imports for nested proto paths" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\import "google/protobuf/bar.proto";
        \\import "other/baz.proto";
        \\message A {}
    );
    defer file.deinit();
    file.name = "google/protobuf/foo.proto";
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const google_protobuf_bar_proto = @import(\"../../google/protobuf/bar.pb.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const other_baz_proto = @import(\"../../other/baz.pb.zig\");") != null);
}

test "codegen emits package and import module metadata" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\import public "public/common.proto";
        \\message A {}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const proto_package = \"demo.app\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const proto_syntax = \"proto2\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const imports = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const common_proto = @import(\"common.pb.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const common_proto_kind = \"normal\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const public_common_proto = @import(\"public/common.pb.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const public_common_proto_kind = \"public\";") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits field metadata including imported type names" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message M {
        \\  optional .demo.common.User user = 1;
        \\  repeated int32 nums = 2 [packed = true];
        \\  optional string display_name = 3 [json_name = "shownName"];
        \\  map<string, .demo.common.Role> roles = 4;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const user_field = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const number = 1;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const cardinality = \"optional\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const kind = \"message\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_name = \".demo.common.User\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const has_presence = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const nums_field = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const is_packed = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const display_name_field = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const json_name = \"shownName\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const roles_field = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const kind = \"map\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"rolesMap\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_key = \"string\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_kind = \"message\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_type_name = \".demo.common.Role\";") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits direct fields for presence repeated map message and oneof fields" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 id = 1; }
        \\message Parent {
        \\  required int32 id = 1;
        \\  optional string name = 2 [default = "anon"];
        \\  repeated int32 nums = 3;
        \\  optional Child child = 4;
        \\  repeated Child children = 5;
        \\  map<string, Child> keyed = 6;
        \\  oneof pick { string alias = 7; Child picked = 8; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "id: i32 = 0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_id: bool = false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "name: []const u8 = \"anon\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "nums: []const i32 = &.{},") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "child: ?Child = null,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "children: []const Child = &.{},") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "keyed: keyedMap = .empty,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pick: @This().pickOneof = .none,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasField_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getField_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setField_name") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendField_nums") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setMessageField_child") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getMessageField_child") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setField_alias") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits typed enum metadata without field accessor wrappers" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message User {
        \\  optional Kind role = 1;
        \\  repeated Kind roles = 2;
        \\  oneof pick { Kind selected = 3; }
        \\  map<string, Kind> keyed = 4;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const has_enum_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const enum_ref = Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_has_enum_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_enum_ref = Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "role: i32 = 0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_role: bool = false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "roles: []const i32 = &.{},") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pick: @This().pickOneof = .none,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "keyed: keyedMap = .empty,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumField_role") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setEnumField_role") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendEnumField_roles") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendEnumEntryField_keyed") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits owned clone helper" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 id = 1; }
        \\message Parent {
        \\  optional string name = 1;
        \\  optional bytes raw = 2;
        \\  repeated string tags = 3;
        \\  optional Child child = 4;
        \\  repeated Child children = 5;
        \\  map<string, bytes> blobs = 6;
        \\  oneof pick { string alias = 7; Child picked = 8; int32 id = 9; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clear(self: *@This(), allocator: std.mem.Allocator) void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) anyerror!@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn adoptOwned(self: *@This(), allocator: std.mem.Allocator) anyerror!void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.adoptOwned(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeOwnedInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const owned_allocator = try out._pbzOwnedAllocator(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out.name = try owned_allocator.dupe(u8, self.name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out.raw = try owned_allocator.dupe(u8, self.raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const cloned = try allocator.alloc([]const u8, self.tags.len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.tags, 0..) |item, i| cloned[i] = try owned_allocator.dupe(u8, item);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out.tags = cloned;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |value| out.child = try value.cloneOwned(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.children, 0..) |item, i| cloned[i] = try item.cloneOwned(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out.blobs.putAssumeCapacityNoClobber(try owned_allocator.dupe(u8, entry.key_ptr.*), try owned_allocator.dupe(u8, entry.value_ptr.*));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".alias => |value| .{ .alias = try owned_allocator.dupe(u8, value) },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value| .{ .picked = try value.cloneOwned(allocator) },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".id => |value| .{ .id = value },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out._unknown_fields = try pbz.wire.cloneRawFields(allocator, self._unknown_fields);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry emits imported message type refs and accessors" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User {
        \\  optional int32 id = 1;
        \\  message Profile { optional string name = 1; }
        \\}
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message Request {
        \\  optional .demo.common.User user = 1;
        \\  repeated .demo.common.User.Profile profiles = 2;
        \\  map<string, .demo.common.User.Profile> keyed = 3;
        \\  oneof pick { .demo.common.User picked = 4; }
        \\  extensions 100 to max;
        \\}
        \\extend Request {
        \\  optional .demo.common.User ext_user = 100;
        \\  repeated .demo.common.User ext_users = 101;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.common.User;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.common.User.Profile;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_type_ref = imports.common_proto.demo.common.User.Profile;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "user: ?imports.common_proto.demo.common.User = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "profiles: []const imports.common_proto.demo.common.User.Profile = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"keyedMap\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: imports.common_proto.demo.common.User.Profile = .{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "picked: imports.common_proto.demo.common.User,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try profiles_list.append(allocator, _pbz_nested);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value_payload = try entry_reader.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var value_reader = try entry_reader.nested(value_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value = try imports.common_proto.demo.common.User.Profile.decodeFromReader(allocator, &value_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.User.decodeFromReader(allocator, &payload_reader); errdefer _pbz_nested.deinit(allocator); self._pbzDeinitOneof_pick(allocator); self.pick = .{ .picked = _pbz_nested };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value.writeTo(w);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value| { const payload_len = value.encodedSize(); try w.writeTag(4, .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value| { const payload_len = value.encodedSize(); try w.writeTag(4, .length_delimited); try w.writeVarint(payload_len); try value.writeDeterministicTo(allocator, w); },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value_ptr.validateRequiredRecursive(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |_pbz_nested| try _pbz_nested.validateRequiredRecursive(allocator),") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.User.jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.User.Profile.jsonParseValueWithOptions(allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var parsed_value = try imports.common_proto.demo.common.User.Profile.jsonParseValueWithOptions(allocator, arena_allocator, map_entry.value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "errdefer parsed_value.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".{ .key = map_entry.key, .value = parsed_value }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.User.jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._pbzDeinitOneof_pick(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .picked = _pbz_nested };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.user) |_pbz_nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.User.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.User.Profile.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "errdefer _pbz_nested.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._pbzDeinitOneof_pick(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .picked = _pbz_nested };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try imports.common_proto.demo.common.User.decode(allocator, payload);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry keeps local enum priority over imported enum" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; IMPORTED = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event {
        \\  enum Kind { LOCAL = 7; }
        \\  optional Kind kind = 1 [default = LOCAL];
        \\  map<string, Kind> keyed = 2;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateFileReferences(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Kind = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "LOCAL = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "kind: i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const enum_ref = Event.Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_enum_ref = Event.Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumField_kind") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry resolves same-package imported unqualified refs" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message User { optional int32 id = 1; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event {
        \\  optional User user = 1;
        \\  optional Kind kind = 2 [default = ADMIN];
        \\  map<string, User> keyed = 3;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateFileReferences(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.User;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const enum_ref = Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_type_ref = imports.common_proto.demo.User;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"keyedMap\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "kind: i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value = \"7\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "user: ?imports.common_proto.demo.User = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: imports.common_proto.demo.User = .{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value_payload = try entry_reader.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var value_reader = try entry_reader.nested(value_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value = try imports.common_proto.demo.User.decodeFromReader(allocator, &value_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value_ptr.validateRequiredRecursive(allocator);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry follows public import chains for message refs" {
    const allocator = std.testing.allocator;
    var leaf = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.leaf;
        \\message User { optional int32 id = 1; }
    );
    defer leaf.deinit();
    leaf.name = "leaf.proto";
    var bridge = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.bridge;
        \\import public "leaf.proto";
        \\message Bridge {}
    );
    defer bridge.deinit();
    bridge.name = "bridge.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "bridge.proto";
        \\message Request { optional .demo.leaf.User user = 1; }
    );
    defer app.deinit();
    app.name = "app.proto";

    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&leaf);
    try registry.addFile(&bridge);
    try registry.addFile(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_ref = imports.bridge_proto.imports.leaf_proto.demo.leaf.User;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "user: ?imports.bridge_proto.imports.leaf_proto.demo.leaf.User = null") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry resolves imported enum fields" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\enum Role { UNKNOWN = 0; ADMIN = 1; GUEST = 2; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message Request {
        \\  optional .demo.common.Role role = 1 [default = GUEST];
        \\  repeated .demo.common.Role roles = 2;
        \\  map<string, .demo.common.Role> keyed = 3;
        \\  oneof pick { .demo.common.Role picked = 4; }
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"demo.common.Role\" = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const kind = \"enum\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_name = \".demo.common.Role\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "role: i32 = 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value = \"2\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "roles: []const i32 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "picked: i32,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(1, self.role)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(1, self.role)") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!@This().enumKnown(value, &.{0, 1, 2}))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "&.{\"UNKNOWN\", \"ADMIN\", \"GUEST\"}, &.{0, 1, 2}, true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setMessageField_role") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen validates imported extension required payloads" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Host { extensions 100 to max; }
        \\message Payload { required int32 id = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message LocalHost { extensions 100 to max; }
        \\extend LocalHost { optional common.Payload payload = 100; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payloads = try extensions.payload.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.common.Payload.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try _pbz_nested.validateRequiredRecursive(allocator);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry emits extension type refs" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\enum Role { UNKNOWN = 0; ADMIN = 1; }
        \\message Host { extensions 100 to max; }
        \\message Note { optional int32 id = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message LocalHost { extensions 200 to max; }
        \\extend .demo.common.Host {
        \\  optional .demo.common.Note note = 100;
        \\  optional .demo.common.Role role = 101;
        \\  repeated .demo.common.Role roles = 102;
        \\}
        \\extend LocalHost { optional .demo.common.Note local_note = 200; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \".demo.common.Host\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee_has_type_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee_type_ref = imports.common_proto.demo.common.Host;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \".demo.common.Note\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_has_type_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type_ref = imports.common_proto.demo.common.Note;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const typed_zig_type = \"imports.common_proto.demo.common.Note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasOn(message: imports.common_proto.demo.common.Host) !bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setMessageOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, value: imports.common_proto.demo.common.Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getMessageOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) !?imports.common_proto.demo.common.Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_enum_ref = @\"demo.common.Role\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) !?@\"demo.common.Role\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return @\"demo.common.Role\".fromInt(_pbz_raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumOrDefaultOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) !@\"demo.common.Role\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try getEnumOn(message, allocator)) orelse @\"demo.common.Role\".fromInt(default_value_zig) orelse unreachable;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setEnumOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, value: @\"demo.common.Role\") !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try setOn(message, allocator, value.toInt());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumsOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) ![]@\"demo.common.Role\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn addEnumOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, value: @\"demo.common.Role\") !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendAllEnumsOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, values: []const @\"demo.common.Role\") !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try appendAllOn(message, allocator, _pbz_raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceAllEnumsOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, values: []const @\"demo.common.Role\") !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try replaceAllOn(message, allocator, _pbz_raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.Note.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.Note.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.Note.jsonParseValueWithOptions(arena_allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try imports.common_proto.demo.common.Note.decode(allocator_, payload_);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits protoc response" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User { optional int32 id = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\enum Kind { UNKNOWN = 0; STARTED = 1; }
        \\message A { optional .demo.common.User user = 1; oneof pick { int32 id = 2; } }
        \\service Api { rpc Get (A) returns (A); }
    );
    defer file.deinit();
    file.name = "a.proto";
    const files = [_]*const schema.FileDescriptor{ &common, &file };
    const response = try cg.generatePluginResponse(allocator, &files);
    defer allocator.free(response);
    try std.testing.expect(response.len != 0);

    var reader = wire.Reader.init(response);
    var saw_supported_features = false;
    var saw_minimum_edition = false;
    var saw_maximum_edition = false;
    var saw_file_name = false;
    var saw_registry_import_ref = false;
    var saw_generated_info = false;
    var saw_message_annotation = false;
    var saw_field_annotation = false;
    var saw_oneof_annotation = false;
    var saw_enum_value_annotation = false;
    var saw_method_annotation = false;
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => saw_supported_features = (try reader.readUInt64()) == cg.generatedResponseFeatureMask(),
            3 => saw_minimum_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.proto2),
            4 => saw_maximum_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.edition_2026),
            15 => {
                var file_reader = wire.Reader.init(try reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_file_name = std.mem.eql(u8, try file_reader.readBytes(), "a.pb.zig"),
                        15 => {
                            const content = try file_reader.readBytes();
                            saw_registry_import_ref = saw_registry_import_ref or std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.common.User;") != null;
                        },
                        16 => {
                            var info = try @import("../descriptor.zig").decodeGeneratedCodeInfo(allocator, try file_reader.readBytes());
                            defer info.deinit(allocator);
                            for (info.annotations.items) |*annotation| {
                                const source_matches = std.mem.eql(u8, annotation.source_file orelse "", "a.proto");
                                const range_valid = annotation.begin.? >= 0 and annotation.end.? > annotation.begin.?;
                                const semantic_matches = annotation.semantic.? == .set;
                                if (annotation.path.items.len == 0) {
                                    saw_generated_info = saw_generated_info or source_matches and annotation.begin.? == 0 and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 4, 0 })) {
                                    saw_message_annotation = saw_message_annotation or source_matches and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 4, 0, 2, 0 })) {
                                    saw_field_annotation = saw_field_annotation or source_matches and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 4, 0, 8, 0 })) {
                                    saw_oneof_annotation = saw_oneof_annotation or source_matches and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 5, 0, 2, 0 })) {
                                    saw_enum_value_annotation = saw_enum_value_annotation or source_matches and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 6, 0, 2, 0 })) {
                                    saw_method_annotation = saw_method_annotation or source_matches and range_valid and semantic_matches;
                                }
                            }
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_supported_features);
    try std.testing.expect(saw_minimum_edition);
    try std.testing.expect(saw_maximum_edition);
    try std.testing.expect(saw_file_name);
    try std.testing.expect(saw_registry_import_ref);
    try std.testing.expect(saw_generated_info);
    try std.testing.expect(saw_message_annotation);
    try std.testing.expect(saw_field_annotation);
    try std.testing.expect(saw_oneof_annotation);
    try std.testing.expect(saw_enum_value_annotation);
    try std.testing.expect(saw_method_annotation);
}

test "codegen emits protoc response from request file_to_generate" {
    const allocator = std.testing.allocator;
    var request = plugin.CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    try request.files_to_generate.append(allocator, "app.proto");
    try request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User { optional int32 id = 1; }
    ));
    request.proto_files.items[0].name = "common.proto";
    try request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message App { optional .demo.common.User user = 1; }
    ));
    request.proto_files.items[1].name = "app.proto";

    const response = try cg.generatePluginResponseFromRequest(allocator, &request);
    defer allocator.free(response);

    var reader = wire.Reader.init(response);
    var response_file_count: usize = 0;
    var saw_app_name = false;
    var saw_common_name = false;
    var saw_import_type_ref = false;
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                response_file_count += 1;
                var file_reader = wire.Reader.init(try reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => {
                            const name = try file_reader.readBytes();
                            saw_app_name = saw_app_name or std.mem.eql(u8, name, "app.pb.zig");
                            saw_common_name = saw_common_name or std.mem.eql(u8, name, "common.pb.zig");
                        },
                        15 => {
                            const content = try file_reader.readBytes();
                            saw_import_type_ref = saw_import_type_ref or std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.common.User;") != null;
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try reader.skipValue(tag),
        }
    }
    try std.testing.expectEqual(@as(usize, 1), response_file_count);
    try std.testing.expect(saw_app_name);
    try std.testing.expect(!saw_common_name);
    try std.testing.expect(saw_import_type_ref);

    var missing_request = plugin.CodeGeneratorRequest.init(allocator);
    defer missing_request.deinit();
    try missing_request.files_to_generate.append(allocator, "missing.proto");
    try missing_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message A {}"));
    missing_request.proto_files.items[0].name = "a.proto";

    const missing_response = try cg.generatePluginResponseFromRequest(allocator, &missing_request);
    defer allocator.free(missing_response);
    var missing_reader = wire.Reader.init(missing_response);
    var saw_error = false;
    while (try missing_reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => saw_error = std.mem.indexOf(u8, try missing_reader.readBytes(), "missing.proto") != null,
            else => try missing_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_error);

    var unresolved_request = plugin.CodeGeneratorRequest.init(allocator);
    defer unresolved_request.deinit();
    try unresolved_request.files_to_generate.append(allocator, "bad.proto");
    try unresolved_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional MissingType field = 1; }
    ));
    unresolved_request.proto_files.items[0].name = "bad.proto";
    const unresolved_response = try cg.generatePluginResponseFromRequest(allocator, &unresolved_request);
    defer allocator.free(unresolved_response);
    var unresolved_reader = wire.Reader.init(unresolved_response);
    var saw_unresolved_error = false;
    while (try unresolved_reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => saw_unresolved_error = std.mem.indexOf(u8, try unresolved_reader.readBytes(), "unresolved type") != null,
            else => try unresolved_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_unresolved_error);
}

test "codegen request plugin options include imports and raw bytes entrypoint" {
    const allocator = std.testing.allocator;
    var request = plugin.CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    request.parameter = "paths=source_relative,include_imports=true";
    try request.files_to_generate.append(allocator, "app.proto");
    try request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User { optional int32 id = 1; }
    ));
    request.proto_files.items[0].name = "common.proto";
    try request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message App { optional .demo.common.User user = 1; }
    ));
    request.proto_files.items[1].name = "app.proto";

    const include_response = try cg.generatePluginResponseFromRequest(allocator, &request);
    defer allocator.free(include_response);
    var include_reader = wire.Reader.init(include_response);
    var include_file_count: usize = 0;
    while (try include_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                include_file_count += 1;
                try include_reader.skipValue(tag);
            },
            else => try include_reader.skipValue(tag),
        }
    }
    try std.testing.expectEqual(@as(usize, 2), include_file_count);

    var no_info_request = plugin.CodeGeneratorRequest.init(allocator);
    defer no_info_request.deinit();
    no_info_request.parameter = "generated_info=false";
    try no_info_request.files_to_generate.append(allocator, "app.proto");
    try no_info_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message App {}"));
    no_info_request.proto_files.items[0].name = "app.proto";
    const no_info_response = try cg.generatePluginResponseFromRequest(allocator, &no_info_request);
    defer allocator.free(no_info_response);
    var no_info_reader = wire.Reader.init(no_info_response);
    var saw_no_info_file = false;
    var saw_generated_info_field = false;
    while (try no_info_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                saw_no_info_file = true;
                var file_reader = wire.Reader.init(try no_info_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        16 => {
                            saw_generated_info_field = true;
                            try file_reader.skipValue(file_tag);
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try no_info_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_no_info_file);
    try std.testing.expect(!saw_generated_info_field);

    var import_name_request = plugin.CodeGeneratorRequest.init(allocator);
    defer import_name_request.deinit();
    import_name_request.parameter = "pbz_import=custom_runtime";
    try import_name_request.files_to_generate.append(allocator, "app.proto");
    try import_name_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message App {}"));
    import_name_request.proto_files.items[0].name = "app.proto";
    const import_name_response = try cg.generatePluginResponseFromRequest(allocator, &import_name_request);
    defer allocator.free(import_name_response);
    var import_name_reader = wire.Reader.init(import_name_response);
    var saw_custom_runtime = false;
    while (try import_name_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try import_name_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        15 => saw_custom_runtime = std.mem.indexOf(u8, try file_reader.readBytes(), "const pbz = @import(\"custom_runtime\");") != null,
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try import_name_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_custom_runtime);

    var output_name_request = plugin.CodeGeneratorRequest.init(allocator);
    defer output_name_request.deinit();
    output_name_request.parameter = "output_suffix=.pbz.zig";
    try output_name_request.files_to_generate.append(allocator, "app.proto");
    try output_name_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User {}
    ));
    output_name_request.proto_files.items[0].name = "common.proto";
    try output_name_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message App { optional .demo.common.User user = 1; }
    ));
    output_name_request.proto_files.items[1].name = "app.proto";
    const output_name_response = try cg.generatePluginResponseFromRequest(allocator, &output_name_request);
    defer allocator.free(output_name_response);
    var output_name_reader = wire.Reader.init(output_name_response);
    var saw_custom_output_name = false;
    var saw_custom_import_name = false;
    while (try output_name_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try output_name_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_custom_output_name = saw_custom_output_name or std.mem.eql(u8, try file_reader.readBytes(), "app.pbz.zig"),
                        15 => saw_custom_import_name = saw_custom_import_name or std.mem.indexOf(u8, try file_reader.readBytes(), "@import(\"common.pbz.zig\")") != null,
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try output_name_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_custom_output_name);
    try std.testing.expect(saw_custom_import_name);

    var keep_ext_request = plugin.CodeGeneratorRequest.init(allocator);
    defer keep_ext_request.deinit();
    keep_ext_request.parameter = "strip_proto_ext=false";
    try keep_ext_request.files_to_generate.append(allocator, "app.proto");
    try keep_ext_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message App {}"));
    keep_ext_request.proto_files.items[0].name = "app.proto";
    const keep_ext_response = try cg.generatePluginResponseFromRequest(allocator, &keep_ext_request);
    defer allocator.free(keep_ext_response);
    var keep_ext_reader = wire.Reader.init(keep_ext_response);
    var saw_kept_ext_name = false;
    while (try keep_ext_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try keep_ext_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_kept_ext_name = saw_kept_ext_name or std.mem.eql(u8, try file_reader.readBytes(), "app.proto.pb.zig"),
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try keep_ext_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_kept_ext_name);

    var no_helpers_request = plugin.CodeGeneratorRequest.init(allocator);
    defer no_helpers_request.deinit();
    no_helpers_request.parameter = "json=false,text_format=false,descriptor=false";
    try no_helpers_request.files_to_generate.append(allocator, "app.proto");
    try no_helpers_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message App { optional int32 id = 1; }"));
    no_helpers_request.proto_files.items[0].name = "app.proto";
    const no_helpers_response = try cg.generatePluginResponseFromRequest(allocator, &no_helpers_request);
    defer allocator.free(no_helpers_response);
    var no_helpers_reader = wire.Reader.init(no_helpers_response);
    var saw_no_helper_content = false;
    while (try no_helpers_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try no_helpers_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        15 => {
                            const content = try file_reader.readBytes();
                            saw_no_helper_content = std.mem.indexOf(u8, content, "jsonStringify") == null and std.mem.indexOf(u8, content, "formatText") == null;
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try no_helpers_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_no_helper_content);

    var invalid_request = plugin.CodeGeneratorRequest.init(allocator);
    defer invalid_request.deinit();
    invalid_request.parameter = "unknown_option=true";
    try invalid_request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message A {}"));
    invalid_request.proto_files.items[0].name = "a.proto";
    const invalid_response = try cg.generatePluginResponseFromRequest(allocator, &invalid_request);
    defer allocator.free(invalid_response);
    var invalid_reader = wire.Reader.init(invalid_response);
    var saw_invalid_parameter = false;
    while (try invalid_reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => saw_invalid_parameter = std.mem.indexOf(u8, try invalid_reader.readBytes(), "invalid generator parameter") != null,
            else => try invalid_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_invalid_parameter);

    const common_fd = try @import("../descriptor.zig").encodeFileDescriptorProto(allocator, &request.proto_files.items[0], request.proto_files.items[0].name);
    defer allocator.free(common_fd);
    const fd = try @import("../descriptor.zig").encodeFileDescriptorProto(allocator, &request.proto_files.items[1], request.proto_files.items[1].name);
    defer allocator.free(fd);
    var raw_writer = wire.Writer.init(allocator);
    defer raw_writer.deinit();
    try raw_writer.writeString(1, "app.proto");
    try raw_writer.writeString(2, "paths=source_relative");
    try raw_writer.writeMessage(15, common_fd);
    try raw_writer.writeMessage(15, fd);
    const raw_response = try cg.generatePluginResponseFromRequestBytes(allocator, raw_writer.slice());
    defer allocator.free(raw_response);
    var raw_reader = wire.Reader.init(raw_response);
    var saw_raw_app = false;
    while (try raw_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try raw_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_raw_app = saw_raw_app or std.mem.eql(u8, try file_reader.readBytes(), "app.pb.zig"),
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try raw_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_raw_app);
}

test "codegen runs plugin requests to writers" {
    const allocator = std.testing.allocator;
    var request = plugin.CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    try request.files_to_generate.append(allocator, "app.proto");
    try request.appendProtoFile(try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message App { optional int32 id = 1; }
    ));
    request.proto_files.items[0].name = "app.proto";

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try cg.runPluginRequest(allocator, &request, &out.writer);
    try std.testing.expect(out.written().len != 0);

    const fd = try @import("../descriptor.zig").encodeFileDescriptorProto(allocator, &request.proto_files.items[0], request.proto_files.items[0].name);
    defer allocator.free(fd);
    var raw = wire.Writer.init(allocator);
    defer raw.deinit();
    try raw.writeString(1, "app.proto");
    try raw.writeMessage(15, fd);
    var raw_out: std.Io.Writer.Allocating = .init(allocator);
    defer raw_out.deinit();
    try cg.runPluginRequestBytes(allocator, raw.slice(), &raw_out.writer);
    try std.testing.expect(raw_out.written().len != 0);

    var reader = wire.Reader.init(raw_out.written());
    var saw_file = false;
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                saw_file = true;
                try reader.skipValue(tag);
            },
            else => try reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_file);
}

test "codegen quotes zig identifiers" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto3);
    var msg = schema.MessageDescriptor{ .name = "struct" };
    try msg.fields.append(allocator, .{ .name = "fn", .number = 1, .kind = .{ .scalar = .int32 } });
    try file.messages.append(allocator, msg);

    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"struct\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const fn_number = 1") != null);
}

test "codegen emits typed scalar fields and encode method" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Person { int32 id = 1; string name = 2; bool active = 3; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "id: i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "name: []const u8 = \"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn writeTo(self: @This(), w: *pbz.Writer) anyerror!void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeInto(self: @This(), buffer: []u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeIntoAssumeCapacity(self: @This(), buffer: []u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(1, self.id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.name.len != 0) { if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; try w.writeString(2, self.name); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.active) { buffer[index] = 24; index += 1; buffer[index] = if (self.active) 1 else 0; index += 1; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "writeVarintToSlice(buffer, &index, @as(u64, if (self.active) 1 else 0))") == null);
}

test "codegen emits repeated scalar slice types" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Repeated { repeated int32 ids = 1; repeated string names = 2; repeated bool flags = 3; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "ids: []const i32 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "names: []const []const u8 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "flags: []const bool = &.{}") != null);
}

test "codegen encodes enum fields" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message User { Kind kind = 1; repeated Kind roles = 2; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "kind: i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "roles: []const i32 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(1, self.kind)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.kind > 0 and self.kind < 0x80) { buffer[index] = @intCast(self.kind); index += 1; } else pbz.wire.writeVarintToSlice") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(2, .length_delimited);") != null);
}

test "codegen encodes and decodes packed repeated scalar and enum fields" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  repeated int32 ids = 1 [packed = true];
        \\  repeated Kind kinds = 2 [packed = true];
        \\  repeated fixed64 big_values = 3 [packed = true];
        \\  repeated uint32 counts = 4 [packed = true];
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "var packed_len: usize = 0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .length_delimited);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeVarint(packed_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(2, .length_delimited);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.wire_type == .length_delimited)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = try r.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendPackedInt32(allocator, &ids_list, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendPackedUInt32(allocator, &counts_list, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendPackedFixed64(allocator, &big_values_list, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.wire.writeUInt32VarintToSlice(buffer, &index, item);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (!packed_reader.eof()) { const value_start = packed_reader.position(); const value = try packed_reader.readInt32(); const value_end = packed_reader.position();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendRawVarintPayload(allocator, &_unknown_fields_list, 2, payload[value_start..value_end]);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try ids_list.append(allocator, try r.readInt32())") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen embeds a decodable file descriptor" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; }
        \\message Person {
        \\  message Nested { int32 id = 1; }
        \\  int32 id = 1;
        \\  string name = 2;
        \\  Kind kind = 3;
        \\  Nested nested = 4;
        \\}
    );
    defer file.deinit();
    file.name = "person.proto";
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const file_descriptor_proto = [_]u8{") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeFileDescriptor(allocator: std.mem.Allocator) !pbz.schema.FileDescriptor {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return pbz.decodeFileDescriptorProto(allocator, &file_descriptor_proto);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return file.findMessageDeep(\".demo.Person\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return file.findMessageDeep(\".demo.Person.Nested\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return file.findEnumDeep(\".demo.Kind\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn toDynamic(self: @This(), allocator: std.mem.Allocator, file: *const pbz.schema.FileDescriptor) !pbz.DynamicMessage {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn fromDynamic(allocator: std.mem.Allocator, file: *const pbz.schema.FileDescriptor, message: *const pbz.DynamicMessage) !@This() {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn parseTextConformant(allocator: std.mem.Allocator, text: []const u8) !@This() {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParseConformant(allocator: std.mem.Allocator, text: []const u8) !@This() {") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen validates known-field wire types during decode" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Child { int32 id = 1; }
        \\message M {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated int32 ids = 3;
        \\  repeated string names = 4;
        \\  Child child = 5;
        \\  repeated Child children = 6;
        \\  map<string, int32> counts = 7;
        \\  oneof pick {
        \\    string label = 8;
        \\    Child picked = 9;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "fn decodeAcceptsTag(tag: pbz.wire.Tag) bool {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!@This().decodeAcceptsTag(tag)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => tag.wire_type == .varint,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => tag.wire_type == .length_delimited,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => tag.wire_type == .varint or tag.wire_type == .length_delimited,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => tag.wire_type == .length_delimited,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "5 => tag.wire_type == .length_delimited,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "6 => tag.wire_type == .length_delimited,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "7 => tag.wire_type == .length_delimited,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "8 => tag.wire_type == .length_delimited,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "9 => tag.wire_type == .length_delimited,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (entry_tag.wire_type != .length_delimited) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (entry_tag.wire_type != .varint) {") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen accepts group wire type for delimited message fields" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\message Child { int32 id = 1; }
        \\message Parent {
        \\  Child child = 1 [features.message_encoding = DELIMITED];
        \\  repeated Child children = 2 [features.message_encoding = DELIMITED];
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "1 => tag.wire_type == .start_group,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => tag.wire_type == .start_group,") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits known-schema decode reuse for packed-only scalar and enum messages" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; HOT = 1; }
        \\message M {
        \\  bool active = 1;
        \\  repeated int32 ids = 2;
        \\  repeated sint32 deltas = 3;
        \\  repeated Kind kinds = 4;
        \\  repeated fixed32 words = 5;
        \\  repeated double ratios = 6;
        \\  repeated uint32 counts = 7;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeKnownReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "/// The caller must pre-size those buffers for the decoded element counts.") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const ids_buffer = @constCast(self.ids);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const deltas_buffer = @constCast(self.deltas);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const counts_buffer = @constCast(self.counts);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "ids_buffer[ids_len] = try pbz.wire.readInt32At(payload, &payload_index)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "deltas_buffer[deltas_len] = try pbz.wire.readSInt32At(payload, &payload_index)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "counts_buffer[counts_len] = @as(u32, @truncate(try pbz.wire.readVarintAt(payload, &payload_index)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const kinds_buffer = @constCast(self.kinds);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "kinds_buffer[kinds_len] = @truncate(@as(i64, @bitCast(try pbz.wire.readVarintAt(payload, &payload_index))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const words_buffer = @constCast(self.words);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (payload.len % 4 != 0) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.wire.copyBytes(std.mem.sliceAsBytes(out), payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const ratios_buffer = @constCast(self.ratios);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (payload.len % 8 != 0) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value.* = @bitCast(std.mem.readInt(u64, payload[payload_index..][0..8], .little));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (ids_len != ids_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (deltas_len != deltas_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (kinds_len != kinds_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (words_len != words_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (ratios_len != ratios_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (counts_len != counts_buffer.len) return error.InvalidWireType;") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits message payload fields and encoders" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Child { int32 id = 1; }
        \\message Parent {
        \\  Child child = 1;
        \\  repeated Child children = 2;
        \\  oneof pick { Child picked = 3; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "child: ?Child = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "children: []const Child = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_child: bool") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |value| { const payload_len = value.encodedSize(); try w.writeTag(1, .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.children) |item| { const payload_len = item.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try item.writeTo(w); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringifyWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |_pbz_nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try _pbz_nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.children.len != 0 or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.children, 0..) |item, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try Child.jsonParseValueWithOptions(allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._pbzDeinitOneof_pick(allocator); self.pick = .{ .picked = _pbz_nested };") != null);
}

test "codegen emits JSON helpers for proto2 group payload fields" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Parent {
        \\  optional group Box = 1 { optional int32 id = 2; }
        \\  repeated group Item = 3 { optional string name = 4; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "box: ?Box = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "item: []const Item = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.box) |_pbz_nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.item, 0..) |item, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try Box.jsonParseValueWithOptions(allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try Item.jsonParseValueWithOptions(allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "{ const old = self.item; self.item = try list.toOwnedSlice(allocator); for (old) |item| { var mutable = item; mutable.deinit(allocator); } if (old.len != 0) allocator.free(old); }") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits basic TextFormat formatters" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message M {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated string tags = 3;
        \\  Kind kind = 4;
        \\  Child child = 5;
        \\  repeated Child children = 12;
        \\  map<string, Child> kids = 6;
        \\  map<string, int32> counts = 7;
        \\  double ratio = 8;
        \\  oneof pick { string alias = 9; Kind picked = 10; Child picked_msg = 11; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const TextFormatOptions = struct { enum_as_name: bool = true, print_unknown_fields: bool = false };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().TextFormatOptions) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().TextFormatOptions) anyerror!void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"id: \"); const value = self.id; try writer.print(\"{d}\", .{value});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"tags: \"); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().textWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, options.enum_as_name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"child {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"kids {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"value {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"alias: \"); try @This().textWriteQuotedBytes(value, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"picked: \"); try @This().textWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, options.enum_as_name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn parseText(allocator: std.mem.Allocator, text: []const u8) anyerror!@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const TextParseOptions = struct { ignore_unknown_fields: bool = false };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn parseTextWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) anyerror!@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn parseTextInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.ignore_unknown_fields) continue;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const needs_normalized_text = @This().textNeedsSeparatorNormalization(text);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var lines = std.mem.splitScalar(u8, normalized_text, '\\n');") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try @This().textUnknownField(allocator, line)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try @This().textUnknownGroup(allocator, line, &lines, text_has_comments)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self._unknown_fields) |raw| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().textWriteUnknownRaw(raw, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteUnknownRaw(raw: []const u8, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteQuotedBytes(bytes: []const u8, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteUnknownField(tag: pbz.wire.Tag, r: *pbz.Reader, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "textLikelyUnknownMessage(bytes)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"\\\\{o:0>3}\", .{c});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"{d} {{\\n\", .{tag.number});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textUnknownField(allocator: std.mem.Allocator, line: []const u8) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textUnknownGroup(allocator: std.mem.Allocator, line: []const u8, lines: anytype, text_has_comments: bool) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try raw.writeTag(number, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try raw.writeTag(number, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try raw.writeBytes(number, bytes);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try raw.writeUInt64(number, try std.fmt.parseInt(u64, value, 0));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const line = @This().textCleanLine(raw_line, text_has_comments);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textFieldValue(line, \"id\")) |raw_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.ratio = try @This().textFloat(f64, raw_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "tags_list.append(allocator, blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.kind = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"counts\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textFieldValue(entry_line, \"value\")) |raw_value| { entry.value = try @This().textInt(i32, raw_value); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(entry_line, \"value\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "errdefer _pbz_nested.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value = _pbz_nested;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .alias = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; } };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .picked = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; } };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textFieldValue(line: []const u8, comptime name: []const u8) ?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textNormalizeSeparators(allocator: std.mem.Allocator, text: []const u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (c == ';' or c == ',')") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (c == '{' or c == '<')") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (c == '}' or c == '>')") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textBlockField(line: []const u8, comptime name: []const u8) bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textCleanLine(raw_line: []const u8, text_has_comments: bool) []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!text_has_comments) return @This().textTrimLine(raw_line);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "line[line.len - 1] == ';' or line[line.len - 1] == ','") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textInt(comptime T: type, value: []const u8) !T") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textFloat(comptime T: type, value: []const u8) !T") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "negative = body[0] == '-'") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.ascii.eqlIgnoreCase(body, \"nan\")) return std.math.nan(T);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return if (negative) -parsed else parsed;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textUnquote(allocator: std.mem.Allocator, raw_value: []const u8) ![]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (value.len >= 2)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (escaped_or_closed == null) return try allocator.dupe(u8, body);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (i < value.len and std.ascii.isWhitespace(value[i])) : (i += 1) {}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "decoded = decoded * 16 + digit;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "decoded = decoded * 8 + (value[end] - '0');") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textHexDigit(c: u8) ?u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var quote: ?u8 = null;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textEnum(value: []const u8, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"child\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const block = try @This().textBlock(allocator, &lines, text_has_comments);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try Child.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "errdefer _pbz_nested.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try children_list.append(allocator, _pbz_nested);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |*existing| { try existing.mergeFrom(allocator, _pbz_nested); _pbz_nested.deinit(allocator); } else { self.child = _pbz_nested; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try existing.mergeFrom(allocator, _pbz_nested)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"picked_msg\") or @This().textBlockField(line, \"pickedMsg\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textBlock(allocator: std.mem.Allocator, lines: anytype, text_has_comments: bool) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, line, \">\")") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits map entry types and encoders" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { FIRST = 7; SECOND = 8; }
        \\message Child {}
        \\message M {
        \\  map<string, int32> counts = 1;
        \\  map<string, Kind> keyed = 2;
        \\  map<string, Child> kids = 3;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const countsEntry = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "counts: countsMap = .empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: Child = .{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) anyerror!void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeDeterministicIntoAssumeCapacity(self: @This(), allocator: std.mem.Allocator, buffer: []u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.sort(countsEntry, entries") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.wire.bytesLessThan(a.key, b.key)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const insertion_sort_limit: usize = 32;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const stack_entry_count: usize = @max(insertion_sort_limit, (32 * 1024) / @max(@sizeOf(countsEntry), 1));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var stack_entries: [stack_entry_count]countsEntry = undefined;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const entries_already_sorted = sorted:") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (entries.len <= insertion_sort_limit)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeVarint(entry_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeString(1, entry.key);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(2, entry.value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var entry_writer = pbz.Writer.init(allocator);") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeDeterministicInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
}

test "codegen emits packed fixed-width borrowed field helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  repeated fixed32 values = 1;
        \\  repeated fixed64 big_values = 2;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.writePackedFixedWidthPayload(u32, w, self.values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.wire.writePackedFixedWidthPayloadAssumeCapacity(u32, w, self.values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.writePackedFixedWidthPayload(u64, w, self.big_values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.wire.writePackedFixedWidthPayloadAssumeCapacity(u64, w, self.big_values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedFixedView(bytes: []const u8) !?[]align(1) const u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedFixedWidthFieldView(u32, bytes, 1);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedFixedSlices(header: *[20]u8, values: []const u32) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedFixedWidthFieldSlices(u32, header, 1, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedFixed32View(bytes: []const u8) !?[]align(1) const u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try valuesPackedFixedView(bytes);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedFixed32Slices(header: *[20]u8, values: []const u32) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try valuesPackedFixedSlices(header, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn big_valuesPackedFixedView(bytes: []const u8) !?[]align(1) const u64") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedFixedWidthFieldView(u64, bytes, 2);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn big_valuesPackedFixedSlices(header: *[20]u8, values: []const u64) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedFixedWidthFieldSlices(u64, header, 2, values);") != null);
}

test "codegen emits borrowed packed bool slices helper" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { repeated bool values = 1; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedBoolSlices(header: *[20]u8, values: []const bool) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedBoolFieldSlices(header, 1, values);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits borrowed length-delimited slices helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  string title = 1;
        \\  repeated bytes chunks = 2;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn titleFieldSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return pbz.wire.lengthDelimitedFieldSlicesAssumeValid(header, 1, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn titleStringSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn chunksBytesSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits map duplicate-key last-wins helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  map<string, int32> counts = 1;
        \\  map<bool, Kind> flags = 2;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "fn appendOrReplaceMapEntry_counts(allocator: std.mem.Allocator, list: *std.ArrayList(countsEntry), entry: countsEntry) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, existing.key, entry.key)) { existing.* = entry; return; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn appendOrReplaceMapEntry_flags(allocator: std.mem.Allocator, list: *std.ArrayList(flagsEntry), entry: flagsEntry) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (existing.key == entry.key) { existing.* = entry; return; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const counts_other_count = other.counts.count();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.counts.ensureUnusedCapacity(allocator, counts_other_count);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const result = self.counts.getOrPutAssumeCapacity(key);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const result = try map.getOrPut(allocator, entry.key);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.counts.clearRetainingCapacity();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().putMapEntry_counts(allocator, &self.counts, entry);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const skip_entry = false;") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().putMapEntry_counts(allocator, &self.counts, .{ .key = map_entry.key, .value = try @This().jsonInt(i32, map_entry.value) })") != null);

    const text_start = std.mem.indexOf(u8, content, "pub fn parseText").?;
    try std.testing.expect(std.mem.indexOf(u8, content[text_start..], "try @This().appendOrReplaceMapEntry_counts(allocator, &counts_list, entry);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen deterministic encoder emits fields by number" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  int32 later = 10;
        \\  oneof pick { int32 mid = 3; }
        \\  int32 first = 1;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    const deterministic_start = std.mem.indexOf(u8, content, "pub fn writeDeterministicTo").?;
    const deterministic_end = std.mem.indexOfPos(u8, content, deterministic_start, "pub fn encodeDeterministic").?;
    const deterministic = content[deterministic_start..deterministic_end];
    const first_pos = std.mem.indexOf(u8, deterministic, "try w.writeInt32(1, self.first)").?;
    const mid_pos = std.mem.indexOf(u8, deterministic, ".mid => |value| try w.writeInt32(3, value)").?;
    const later_pos = std.mem.indexOf(u8, deterministic, "try w.writeInt32(10, self.later)").?;
    try std.testing.expect(first_pos < mid_pos);
    try std.testing.expect(mid_pos < later_pos);
}

test "codegen deterministic encoder recurses into available message payloads" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 a = 1; optional int32 b = 2; }
        \\message Parent {
        \\  optional Child child = 1;
        \\  repeated Child children = 2;
        \\  optional group Legacy = 3 { optional int32 a = 4; optional int32 b = 5; }
        \\  map<string, Child> keyed = 6;
        \\  oneof pick { Child picked = 7; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    const parent_start = std.mem.indexOf(u8, content, "pub const Parent = struct").?;
    const deterministic_start = std.mem.indexOfPos(u8, content, parent_start, "pub fn writeDeterministicTo").?;
    const deterministic_end = std.mem.indexOfPos(u8, content, deterministic_start, "pub fn encodeDeterministic").?;
    const deterministic = content[deterministic_start..deterministic_end];

    try std.testing.expect(std.mem.indexOf(u8, deterministic, "for (self.children) |item| { const payload_len = item.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "try w.writeTag(1, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w);") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w);") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "if (self.legacy) |item| { try w.writeTag(3, .start_group); try item.writeDeterministicTo(allocator, w); try w.writeTag(3, .end_group); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "std.mem.sort(keyedEntry, entries") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "entry.value.writeTo(w)") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, ".picked => |value| { const payload_len = value.encodedSize(); try w.writeTag(7, .length_delimited); try w.writeVarint(payload_len); try value.writeDeterministicTo(allocator, w); }") != null);
}

test "codegen emits map JSON stringify and parse helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message M {
        \\  map<string, int32> counts = 1;
        \\  map<int32, string> names = 2;
        \\  map<bool, Kind> flags = 3;
        \\  map<string, Child> kids = 4;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.counts.count() != 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (map_it.next()) |map_entry| : (i += 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteString(writer, entry.key)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"{d}\", .{entry.value})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"\\\"{d}\\\"\", .{entry.key})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteString(writer, entry.value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(if (entry.key) \"\\\"true\\\"\" else \"\\\"false\\\"\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteEnum(writer, entry.value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, options.enum_as_name)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().putMapEntry_counts(allocator, &self.counts, .{ .key = map_entry.key, .value = try @This().jsonInt(i32, map_entry.value) })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.counts.ensureUnusedCapacity(allocator, object_value.count());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().putMapEntry_counts(allocator, &self.counts, .{ .key = map_entry.key, .value = try @This().jsonInt(i32, map_entry.value) })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@This().deinitMap_counts(allocator, &self.counts);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.fmt.parseInt(i32, map_entry.key, 10)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonMapKeyBool(map_entry.key)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const parsed_value = @This().jsonEnum(map_entry.value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().putMapEntry_flags(allocator, &self.flags, .{ .key = try @This().jsonMapKeyBool(map_entry.key), .value = parsed_value });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var parsed_value = try Child.jsonParseValueWithOptions(allocator, arena_allocator, map_entry.value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "errdefer parsed_value.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().putMapEntry_kids(allocator, &self.kids, .{ .key = map_entry.key, .value = parsed_value });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.kids.ensureUnusedCapacity(allocator, object_value.count());") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits basic decode method" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Person { int32 id = 1; string name = 2; Kind kind = 3; bytes payload = 4; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "_ = &allocator;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "8 => { self.id = try r.readInt32(); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "18 => { self.name = try r.readBytes(); if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "24 => { const value = try r.readInt32(); self.kind = value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "34 => { self.payload = try r.readBytes(); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "_unknown_fields: []const []const u8 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFieldCount(self: @This()) usize") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFields(self: @This()) []const []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return pbz.wire.rawFieldCountByNumberAssumeValid(self._unknown_fields, number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return pbz.wire.rawFieldHasNumberAssumeValid(self._unknown_fields, number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFieldNumbersAlloc(self: @This(), allocator: std.mem.Allocator) ![]pbz.FieldNumber") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.rawFieldNumbersAlloc(allocator, self._unknown_fields);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFieldNumberRunsAlloc(self: @This(), allocator: std.mem.Allocator) ![]pbz.wire.RawFieldNumberRun") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.rawFieldNumberRunsAlloc(allocator, self._unknown_fields);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.rawFieldsByNumberAllocAssumeValid(allocator, self._unknown_fields, number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.clearRawFieldsByNumber(allocator, &self._unknown_fields, number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendRawFieldClone(allocator, &self._unknown_fields, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.wire.clearRawFields(allocator, &self._unknown_fields);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, r, raw_tag_start, try pbz.wire.Tag.decode(raw_tag))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self._unknown_fields) |raw| try w.appendSlice(raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.writeRawFieldsDeterministicAssumeCapacity(allocator, self._unknown_fields, w);") != null);
}

test "codegen decodes repeated scalar enum and message payload fields" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message M { repeated int32 ids = 1; repeated Kind kinds = 2; repeated Child children = 3; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "var ids_list: std.ArrayList(i32) = .empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try ids_list.append(allocator, try r.readInt32())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "{ const value = try r.readInt32(); try kinds_list.append(allocator, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var payload_reader = try r.nested(payload); var _pbz_nested = try Child.decodeFromReader(allocator, &payload_reader); errdefer _pbz_nested.deinit(allocator); try children_list.append(allocator, _pbz_nested);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.ids = if (ids_list.items.len != 0 and ids_list.items.len == ids_list.capacity) ids_list.toOwnedSliceAssert() else try ids_list.toOwnedSlice(allocator)") != null);
}

test "codegen supports self-recursive generated schemas" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Node {
        \\  Node child = 1;
        \\  repeated Node children = 2;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "child: []const u8 = \"\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_child: bool = false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "children: []const Node = &.{},") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) anyerror!@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { const payload = try r.readBytes(); var payload_reader = try r.nested(payload); var _pbz_nested = try Node.decodeFromReader(allocator, &payload_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "child: ?Node") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen decodes map fields into entry slices" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { map<string, int32> counts = 1; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "var counts_list: std.ArrayList(countsEntry) = .empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var entry = countsEntry{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (entry_tag.wire_type != .length_delimited) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value = try entry_reader.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.key = value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (entry_tag.wire_type != .varint) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value = try entry_reader.readInt32();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().appendOrReplaceMapEntry_counts(allocator, &counts_list, entry)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.counts.ensureUnusedCapacity(allocator, counts_list.items.len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.counts.putAssumeCapacityNoClobber(entry.key, entry.value);") != null);
}

test "codegen emits presence flags for optional required and proto3 optional fields" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M { optional int32 a = 1; required string b = 2; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_a: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_b: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_a) try w.writeInt32(1, self.a)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.a = try r.readInt32(); self.has_a = true") != null);

    var file3 = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { optional int32 a = 1; int32 b = 2; }
    );
    defer file3.deinit();
    const content3 = try cg.generateZigFile(allocator, &file3);
    defer allocator.free(content3);
    try std.testing.expect(std.mem.indexOf(u8, content3, "has_a: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content3, "has_b: bool = false") == null);
}

test "codegen hides protoc synthetic oneofs for proto3 optional fields" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  optional int32 count = 1;
        \\  optional string note = 2;
        \\  oneof pick { string name = 3; }
        \\}
    );
    defer file.deinit();
    file.name = "optional.proto";

    const descriptor_bytes = try @import("../descriptor.zig").encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(descriptor_bytes);
    var decoded = try @import("../descriptor.zig").decodeFileDescriptorProto(allocator, descriptor_bytes);
    defer decoded.deinit();

    const decoded_message = decoded.findMessage("M").?;
    try std.testing.expectEqual(@as(usize, 3), decoded_message.oneofs.items.len);
    try std.testing.expectEqualStrings("_count", decoded_message.findField("count").?.oneof_name.?);
    try std.testing.expect(decoded_message.findField("count").?.proto3_optional);

    const content = try cg.generateZigFile(allocator, &decoded);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "count: i32 = 0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_count: bool = false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "note: []const u8 = \"\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_note: bool = false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const pickOneof = union(enum)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const _countOneof") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const _noteOneof") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._pbzDeinitOneof__count") == null);
}

test "codegen emits proto2 scalar and enum defaults" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\enum Code { OK = 5; FAIL = 6; }
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional string name = 2 [default = "hello\nworld"];
        \\  optional bool enabled = 3 [default = true];
        \\  optional Kind kind = 4 [default = ADMIN];
        \\  optional bytes raw = 5 [default = "\001\x02"];
        \\  optional float ratio = 6 [default = inf];
        \\  optional Code code = 7;
        \\  optional double neg_ratio = 8 [default = -inf];
        \\  optional float quiet = 9 [default = nan];
        \\  optional float neg_quiet = 10 [default = -nan];
        \\  optional double infinity = 11 [default = Infinity];
        \\  optional double neg_infinity = 12 [default = -INFINITY];
        \\  optional uint64 max_u64 = 13 [default = 0xFFFFFFFFFFFFFFFF];
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "count: i32 = 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "name: []const u8 = \"hello\\nworld\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "enabled: bool = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "kind: i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "raw: []const u8 = \"\\x01\\x02\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "ratio: f32 = std.math.inf(f32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "code: i32 = 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "neg_ratio: f64 = -std.math.inf(f64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "quiet: f32 = std.math.nan(f32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "neg_quiet: f32 = std.math.nan(f32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "infinity: f64 = std.math.inf(f64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "neg_infinity: f64 = -std.math.inf(f64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "max_u64: u64 = 18446744073709551615") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_count: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_count or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_kind or options.always_print_primitive_fields)") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen output parses as Zig source" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message Person {
        \\  optional int32 id = 1;
        \\  string name = 2;
        \\  repeated string tags = 3;
        \\  Kind kind = 4;
        \\  Child child = 5;
        \\  map<string, int32> counts = 6;
        \\  bytes raw = 7;
        \\  repeated int64 nums = 8;
        \\  double ratio = 9;
        \\  oneof pick {
        \\    bool active = 10;
        \\    string alias = 11;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits typed json stringify and parse methods" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  int64 big = 3;
        \\  bytes raw = 4;
        \\  repeated string tags = 5;
        \\  optional bool active = 6;
        \\  Kind kind = 7;
        \\  int32 user_id = 10;
        \\  string display_name = 11 [json_name = "shownName"];
        \\  oneof choice {
        \\    string alias = 8;
        \\    int32 code = 9;
        \\    string alt_name = 12;
        \\    Kind pick_kind = 13;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const JsonStringifyOptions = struct { enum_as_name: bool = true, preserve_proto_field_names: bool = false, always_print_primitive_fields: bool = false };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(if (first) \"\\\"id\\\":\" else \",\\\"id\\\":\"); first = false;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.preserve_proto_field_names) \"\\\"id\\\":\" else \"\\\"id\\\":\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.preserve_proto_field_names) (if (first) \"\\\"user_id\\\":\" else \",\\\"user_id\\\":\") else (if (first) \"\\\"userId\\\":\" else \",\\\"userId\\\":\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.preserve_proto_field_names) (if (first) \"\\\"display_name\\\":\" else \",\\\"display_name\\\":\") else (if (first) \"\\\"shownName\\\":\" else \",\\\"shownName\\\":\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.id != 0 or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.kind != 0 or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.tags.len != 0 or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, options.enum_as_name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteString(writer, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"\\\"{d}\\\"\", .{value});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.base64.standard.Encoder.encodeWriter(writer, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.tags, 0..) |item, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_active)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (self.choice)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".alias => |value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const owned_text = try arena.allocator().dupe(u8, text)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.json.parseValueTree(arena.allocator(), owned_text, .{})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const JsonParseOptions = struct { ignore_unknown_fields: bool = false };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParseWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var self = try @This().jsonParseValueWithOptions(allocator, arena.allocator(), parsed, options)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._json_arena = arena") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParseInitialized(allocator: std.mem.Allocator, text: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var self = try @This().jsonParse(allocator, text);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParseInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.validateRequiredRecursive(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: pbz.json.Value, options: @This().JsonParseOptions) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonFloat(comptime T: type, value: pbz.json.Value) !T") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, text, \"NaN\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (std.mem.eql(u8, text, \"Infinity\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (std.mem.eql(u8, text, \"-Infinity\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.ignore_unknown_fields) continue;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (value == .null)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.id = try @This().jsonInt(i32, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"id\") or std.mem.eql(u8, key, \"id\")") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"user_id\") or std.mem.eql(u8, key, \"userId\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"display_name\") or std.mem.eql(u8, key, \"shownName\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.raw = try @This().jsonBytes(arena_allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.kind = @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (array.items) |item| try list.append(allocator, try @This().jsonString(item));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.tags = blk: { const old = self.tags; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.tags = &.{}; if (old.len != 0) allocator.free(old);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.choice = .{ .alias = try @This().jsonString(value) };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._pbzDeinitOneof_choice(allocator); continue;") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"alt_name\") or std.mem.eql(u8, key, \"altName\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.choice = .{ .pick_kind = @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; } };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonEnum(value: pbz.json.Value, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonEnumNumber(value: i32, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonWriteString(writer: *std.Io.Writer, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!pbz.validateUtf8(value)) return error.InvalidUtf8;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonDecodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8") != null);
}

test "codegen emits required validation" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M { required int32 id = 1; optional string name = 2; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.validateRequired();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try self.encode(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var self = try @This().decode(allocator, bytes);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "errdefer self.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn missingRequiredFieldName(self: @This()) ?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!self.has_id) return \"id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn validateRequired(self: @This()) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.missingRequiredFieldName() != null) return error.MissingRequiredField") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_name") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits recursive required validation for message payloads" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { required int32 id = 1; }
        \\message Parent {
        \\  optional Child child = 1;
        \\  repeated Child children = 2;
        \\  oneof pick { Child picked = 3; }
        \\  map<string, Child> keyed = 4;
        \\  extensions 100 to max;
        \\}
        \\extend Parent { optional Child child_ext = 100; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) anyerror!void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) anyerror!?[]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |_pbz_nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.children) |_pbz_nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |_pbz_nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var map_it = self.keyed.iterator(); while (map_it.next()) |entry|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value_ptr.validateRequiredRecursive(allocator)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payloads = try extensions.child_ext.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (payloads) |payload|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try _pbz_nested.validateRequiredRecursive(allocator)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"child_ext.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"child.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"children.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"keyed.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"picked.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.validateRequiredRecursive(allocator);") != null);
    const json_initialized_start = std.mem.indexOf(u8, content, "pub fn jsonParseInitialized").?;
    const json_initialized = content[json_initialized_start..];
    try std.testing.expect(std.mem.indexOf(u8, json_initialized, "try self.validateRequiredRecursive(allocator);") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits mergeFrom for singular message payloads and groups" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 id = 1; optional string name = 2; }
        \\message Parent {
        \\  optional int32 id = 1;
        \\  repeated int32 nums = 2;
        \\  optional Child child = 3;
        \\  optional group Box = 4 { optional int32 a = 5; optional int32 b = 6; }
        \\  oneof pick { string name = 7; Child picked = 8; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "fn _pbzOwnedAllocator(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) anyerror!void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.nums.len != 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const merged = try allocator.alloc(i32, old.len + other.nums.len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.child) |other_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |*self_value| { try self_value.mergeFrom(allocator, other_value); } else { self.child = try other_value.cloneOwned(allocator); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.box) |other_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.box) |*self_value| { try self_value.mergeFrom(allocator, other_value); } else { self.box = try other_value.cloneOwned(allocator); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try existing.mergeFrom(allocator, _pbz_nested)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (other.pick)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value| { const owned_value = try value.cloneOwned(allocator); errdefer owned_value.deinit(allocator); self._pbzDeinitOneof_pick(allocator); self.pick = .{ .picked = owned_value }; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const payload = try r.readBytes(); var payload_reader = try r.nested(payload); var _pbz_nested = try Child.decodeFromReader(allocator, &payload_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => { const payload = try r.readGroupBytes(4); var payload_reader = try r.nested(payload); var _pbz_nested = try Box.decodeFromReader(allocator, &payload_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.box) |value| { try w.writeTag(4, .start_group); try value.writeTo(w); try w.writeTag(4, .end_group); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.box) |_pbz_nested|") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen deep-copies string and bytes payloads in mergeFrom" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Child { string name = 1; }
        \\message Parent {
        \\  string name = 1;
        \\  bytes payload = 2;
        \\  repeated string tags = 3;
        \\  repeated bytes chunks = 4;
        \\  map<string, string> labels = 5;
        \\  Child child = 6;
        \\  oneof pick {
        \\    string label = 7;
        \\    bytes token = 8;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "self.name = try pbz.wire.dupeBytes(_pbz_owned_allocator,other.name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.payload = try pbz.wire.dupeBytes(_pbz_owned_allocator,other.payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const _pbz_owned_allocator = try self._pbzOwnedAllocator(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "merged[old.len + i] = try pbz.wire.dupeBytes(_pbz_owned_allocator,item);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const key = try pbz.wire.dupeBytes(_pbz_owned_allocator,entry.key_ptr.*);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value = try pbz.wire.dupeBytes(_pbz_owned_allocator,entry.value_ptr.*);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".label => |value| { const owned_value = try pbz.wire.dupeBytes(_pbz_owned_allocator,value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".token => |value| { const owned_value = try pbz.wire.dupeBytes(_pbz_owned_allocator,value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.name = _pbz_owned_block.take(self.name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (@constCast(self.tags)) |*item| item.* = _pbz_owned_block.take(item.*);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".label => |value| self.pick = .{ .label = _pbz_owned_block.take(value) },") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen maps oneof to tagged union" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Choice { oneof pick { string name = 1; int32 id = 2; } }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const pickOneof = union(enum)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "name: []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pick: @This().pickOneof = .none") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (self.pick)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".name => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try w.writeString(1, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; self._pbzDeinitOneof_pick(allocator); self.pick = .{ .name = value }; }") != null);
}

test "codegen emits proto2 extension metadata" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\message Host { extensions 100 to max; }
        \\message Note {}
        \\extend Host {
        \\  optional string tag = 100 [default = "untagged"];
        \\  repeated int32 nums = 101;
        \\  optional Note note = 102;
        \\  repeated int32 packed_nums = 103 [packed = true];
        \\  repeated Note notes = 104;
        \\  optional Kind role = 105 [default = ADMIN];
        \\  repeated Kind roles = 106;
        \\}
    );
    defer file.deinit();
    try file.extensions.append(allocator, .{ .name = "legacy", .number = 107, .cardinality = .optional, .kind = .{ .group = "Note" }, .extendee = "Host" });
    try file.extensions.append(allocator, .{ .name = "legacies", .number = 108, .cardinality = .repeated, .kind = .{ .group = "Note" }, .extendee = "Host" });
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extensions = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const tag = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const number = 100") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \"Host\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const cardinality = \"optional\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \"string\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"[]const u8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const typed_zig_type = \"[]const u8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const has_default = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value = \"untagged\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value_zig: []const u8 = \"untagged\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn write(w: *pbz.Writer, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeString(100, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeRaw(allocator: std.mem.Allocator, value: []const u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try write(&w, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try message.appendUnknownRaw(allocator, _pbz_raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasInUnknown(message: anytype) !bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try message.hasUnknownFieldNumber(number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn countInUnknown(message: anytype) !usize") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try message.unknownFieldCountByNumber(number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try message.clearUnknownFieldsByNumber(allocator, number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try clearFromUnknown(message, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try appendToUnknown(message, allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeValue(r: *pbz.Reader) ![]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try r.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeRaw(raw: []const u8) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (_pbz_tag.number != number or _pbz_tag.wire_type != .length_delimited) return null;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const _pbz_value = try decodeValue(&r);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!r.eof()) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return _pbz_value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![][]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (raw_fields) |_pbz_raw| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try decodeRaw(_pbz_raw)) |_pbz_value| try _pbz_list.append(allocator, _pbz_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![][]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try decodeAllRaw(allocator, message.unknownFields());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![][]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try decodeFromUnknownFieldsAlloc(message, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return if (_pbz_values.len == 0) null else _pbz_values[_pbz_values.len - 1];") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const nums = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const cardinality = \"repeated\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn writeAll(w: *pbz.Writer, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |_pbz_value| try write(w, _pbz_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeAllRaw(allocator: std.mem.Allocator, values: []const i32) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendAllToUnknown(message: anytype, allocator: std.mem.Allocator, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |_pbz_value| try appendToUnknown(message, allocator, _pbz_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceAllInUnknown(message: anytype, allocator: std.mem.Allocator, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try appendAllToUnknown(message, allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAppend(allocator: std.mem.Allocator, list: *std.ArrayList(i32), r: *pbz.Reader) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try list.append(allocator, try decodeValue(r));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAppendRaw(allocator: std.mem.Allocator, list: *std.ArrayList(i32), raw: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const packed_nums = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var packed_writer = pbz.Writer.init(w.allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| try packed_writer.writeVarint(@as(u64, @bitCast(@as(i64, value))));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeBytes(103, packed_writer.slice());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodePackedRaw(allocator: std.mem.Allocator, raw: []const u8) !?[]i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (values.len == 0) return;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const _pbz_raw = try encodeAllRaw(allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (!packed_reader.eof()) try _pbz_list.append(allocator, try packed_reader.readInt32());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try decodePackedRaw(allocator, _pbz_raw)) |_pbz_values| { defer allocator.free(_pbz_values); try _pbz_list.appendSlice(allocator, _pbz_values); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (extensions.packed_nums.decodePackedRaw(allocator, raw) catch null) |values| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[demo.packed_nums]: \"); try writer.print(\"{d}\", .{value});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \"Note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textFieldValue(line, \"[demo.tag]\") orelse @This().textFieldValue(line, \"[tag]\")) |raw_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try extensions.tag.encodeRaw(allocator, try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try extensions.nums.encodeRaw(allocator, try @This().textInt(i32, raw_value));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"[demo.note]\") or @This().textBlockField(line, \"[note]\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try Note.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try extensions.note.encodeRaw(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, key, \"[demo.tag]\") or std.mem.eql(u8, key, \"[tag]\")) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.clearUnknownFieldsByNumber(allocator, extensions.tag.number); continue;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.tag.replaceInUnknown(self, allocator, try @This().jsonString(value));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.nums.appendToUnknown(self, allocator, try @This().jsonInt(i32, item));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try Note.jsonParseValueWithOptions(arena_allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.note.replaceInUnknown(self, allocator, try _pbz_nested.encode(arena_allocator));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const values = try extensions.tag.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(if (first) \"\\\"[demo.tag]\\\":\" else \",\\\"[demo.tag]\\\":\"); first = false;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value = values[values.len - 1];") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteString(writer, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const values = try extensions.nums.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(if (first) \"\\\"[demo.nums]\\\":\" else \",\\\"[demo.nums]\\\":\"); first = false;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try struct { fn write(allocator_: std.mem.Allocator, writer_: *std.Io.Writer, options_: anytype, payload_: []const u8) !void { var _pbz_nested = try Note.decode(allocator_, payload_);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (extensions.tag.decodeRaw(raw) catch null) |value| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[demo.tag]: \"); try @This().textWriteQuotedBytes(value, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (extensions.note.decodeRaw(raw) catch null) |payload| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[demo.note] {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try Note.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasExtension_tag(self: @This()) !bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try extensions.tag.hasInUnknown(self);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn countExtension_tag(self: @This()) !usize") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtension_tag(self: @This(), allocator: std.mem.Allocator) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try extensions.tag.decodeFirstFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionOrDefault_tag(self: @This(), allocator: std.mem.Allocator) ![]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try self.getExtension_tag(allocator)) orelse extensions.tag.default_value_zig;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setExtension_tag(self: *@This(), allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.tag.replaceInUnknown(self, allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clearExtension_tag(self: *@This(), allocator: std.mem.Allocator) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.tag.clearFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setExtensionMessage_note(self: *@This(), allocator: std.mem.Allocator, value: Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = try value.encode(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.note.replaceInUnknown(self, allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionMessage_note(self: @This(), allocator: std.mem.Allocator) !?Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = (try extensions.note.decodeFirstFromUnknown(self, allocator)) orelse return null;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try Note.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn addExtensionMessage_notes(self: *@This(), allocator: std.mem.Allocator, value: Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.notes.appendToUnknown(self, allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendExtensionMessages_notes(self: *@This(), allocator: std.mem.Allocator, values: []const Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| try self.addExtensionMessage_notes(allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceExtensionMessages_notes(self: *@This(), allocator: std.mem.Allocator, values: []const Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.appendExtensionMessages_notes(allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionMessages_notes(self: @This(), allocator: std.mem.Allocator) ![]Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (payloads) |payload| try list.append(allocator, try Note.decode(allocator, payload));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtension_nums(self: @This(), allocator: std.mem.Allocator) ![]i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try extensions.nums.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendExtension_nums(self: *@This(), allocator: std.mem.Allocator, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.nums.appendAllToUnknown(self, allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn addExtension_nums(self: *@This(), allocator: std.mem.Allocator, value: i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.nums.appendToUnknown(self, allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceExtension_nums(self: *@This(), allocator: std.mem.Allocator, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.nums.replaceAllInUnknown(self, allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const role = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_has_enum_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_enum_ref = Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value = \"7\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value_zig: i32 = 7;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try self.getExtension_role(allocator)) orelse extensions.role.default_value_zig;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumExtension_role(self: @This(), allocator: std.mem.Allocator) !?Kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return Kind.fromInt(_pbz_raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumOrDefaultExtension_role(self: @This(), allocator: std.mem.Allocator) !Kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try self.getEnumExtension_role(allocator)) orelse Kind.fromInt(extensions.role.default_value_zig) orelse unreachable;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setEnumExtension_role(self: *@This(), allocator: std.mem.Allocator, value: Kind) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.setExtension_role(allocator, value.toInt());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumExtensions_roles(self: @This(), allocator: std.mem.Allocator) ![]Kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendEnumExtensions_roles(self: *@This(), allocator: std.mem.Allocator, values: []const Kind) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.appendExtension_roles(allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceEnumExtensions_roles(self: *@This(), allocator: std.mem.Allocator, values: []const Kind) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.replaceExtension_roles(allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const legacy = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \"Note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn write(w: *pbz.Writer, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(107, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.appendSlice(value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(107, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try r.readGroupBytes(number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"[demo.legacy]\") or @This().textBlockField(line, \"[legacy]\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try extensions.legacy.encodeRaw(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, key, \"[demo.legacy]\") or std.mem.eql(u8, key, \"[legacy]\")) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.legacy.replaceInUnknown(self, allocator, try _pbz_nested.encode(arena_allocator));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (extensions.legacy.decodeRaw(raw) catch null) |payload| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[demo.legacy] {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setExtensionMessage_legacy(self: *@This(), allocator: std.mem.Allocator, value: Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.legacy.replaceInUnknown(self, allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionMessage_legacy(self: @This(), allocator: std.mem.Allocator) !?Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = (try extensions.legacy.decodeFirstFromUnknown(self, allocator)) orelse return null;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const legacies = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(108, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn addExtensionMessage_legacies(self: *@This(), allocator: std.mem.Allocator, value: Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.legacies.appendToUnknown(self, allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendExtensionMessages_legacies(self: *@This(), allocator: std.mem.Allocator, values: []const Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionMessages_legacies(self: @This(), allocator: std.mem.Allocator) ![]Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (payloads) |payload| try list.append(allocator, try Note.decode(allocator, payload));") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen scopes qualified extensions to exact nested extendee" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message Outer {
        \\  message Host { extensions 100 to max; }
        \\  extend Host { optional int32 nested_ext = 100; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    var count: usize = 0;
    var index: usize = 0;
    const needle = "pub fn hasExtension_nested_ext";
    while (std.mem.indexOfPos(u8, content, index, needle)) |found| {
        count += 1;
        index = found + needle.len;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "codegen emits MessageSet extension write helper" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Note { optional int32 id = 1; }
        \\extend Host { optional Note note = 100; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeUInt32(2, 100);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(3, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeRaw(allocator: std.mem.Allocator, value: []const u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (_pbz_tag.number == 1 and _pbz_tag.wire_type == .start_group) { const _pbz_value = try decodeMessageSetItem(&r); if (!r.eof()) return error.InvalidWireType; return _pbz_value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (_pbz_tag.number == 100 and _pbz_tag.wire_type == .length_delimited) { const _pbz_value = try r.readBytes(); if (!r.eof()) return error.InvalidWireType; return _pbz_value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeMessageSetItem(r: *pbz.Reader) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw_type_id = try r.readUInt32(); if (raw_type_id == 0 or raw_type_id > std.math.maxInt(pbz.FieldNumber)) return error.InvalidFieldNumber; type_id = raw_type_id;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return if (type_id != null and type_id.? == 100) _pbz_payload else null;") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry normalizes imported extension extendee names" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Host { extensions 100 to max; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\extend common.Host { optional string note = 100; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \".common.Host\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \"common.Host\";") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee_type_ref = imports.common_proto.common.Host;") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen detects imported MessageSet extension extendees" {
    const allocator = std.testing.allocator;
    var host = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
    );
    defer host.deinit();
    host.name = "host.proto";
    var ext = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "host.proto";
        \\message Note { optional int32 id = 1; }
        \\extend common.Host { optional Note note = 100; }
    );
    defer ext.deinit();
    ext.name = "ext.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try registry.addFile(&ext);

    const content = try cg.generateZigFileWithRegistry(allocator, &ext, &registry);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeUInt32(2, 100);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(3, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (_pbz_tag.number == 1 and _pbz_tag.wire_type == .start_group) { const _pbz_value = try decodeMessageSetItem(&r); if (!r.eof()) return error.InvalidWireType; return _pbz_value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeMessageSetItem(r: *pbz.Reader) !?[]const u8") != null);
}

test "codegen emits service metadata and unary adapters" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Req {}
        \\message Res {}
        \\service Directory {
        \\  option deprecated = true;
        \\  rpc Get (Req) returns (Res);
        \\  rpc Stream (stream Req) returns (stream Res) {
        \\    option deprecated = true;
        \\    option idempotency_level = IDEMPOTENT;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const services = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Directory = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const name = \"Directory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const deprecated = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Get = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const idempotency_level = \"IDEMPOTENCY_UNKNOWN\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type = \"Req\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_type = \"Res\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_has_type_ref = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type_ref = Req;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_has_type_ref = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_type_ref = Res;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const client_streaming = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const server_streaming = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const idempotency_level = \"IDEMPOTENT\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const idempotency_level_number = 2;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn descriptor(file: *const pbz.schema.FileDescriptor) ?*const pbz.schema.ServiceDescriptor {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return file.findService(\"Directory\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn descriptor(service: *const pbz.schema.ServiceDescriptor) ?*const pbz.schema.MethodDescriptor {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return service.findMethod(\"Get\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Handler(comptime Impl: type) type") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Client(comptime Transport: type) type") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Get(self: @This(), allocator: std.mem.Allocator, request: Req) !Res") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try self.impl.Get(allocator, request);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn dispatchRaw(self: @This(), allocator: std.mem.Allocator, method_name: []const u8, request_payload: []const u8) !?[]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var request = try Req.decodeOwned(allocator, request_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var response = try self.Get(allocator, request);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const response_payload = try self.transport.call(allocator, \"Directory\", \"Get\", request_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Stream(self: @This(), allocator: std.mem.Allocator, requests: anytype, responses: anytype) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try self.impl.Stream(allocator, requests, responses);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.transport.callBidiStream(allocator, \"Directory\", \"Stream\", requests, responses);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "dispatchTyped") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return error.Unimplemented;") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"_pbzDispatchTyped_Get\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn GetTyped") == null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits registry-aware service metadata type references" {
    const allocator = std.testing.allocator;
    var common = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Req { optional string q = 1; }
        \\message Res { optional string value = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\service Directory {
        \\  rpc Get (common.Req) returns (common.Res);
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&common);
    try reg.addFile(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &reg);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type = \"common.Req\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_has_type_ref = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type_ref = imports.common_proto.common.Req;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_has_type_ref = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_type_ref = imports.common_proto.common.Res;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Get(self: @This(), allocator: std.mem.Allocator, request: imports.common_proto.common.Req) !imports.common_proto.common.Res") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var request = try imports.common_proto.common.Req.decodeOwned(allocator, request_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try imports.common_proto.common.Res.decodeOwned(allocator, response_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn GetTyped") == null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen skips proto3 implicit default scalar and enum values" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M { int32 id = 1; bool active = 2; Kind kind = 3; optional int32 opt = 4; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.id != 0) try w.writeInt32(1, self.id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.active) try w.writeBool(2, self.active)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.kind != 0) try w.writeInt32(3, self.kind)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_opt) try w.writeInt32(4, self.opt)") != null);
}

test "codegen honors editions field presence features" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.field_presence = EXPLICIT;
        \\message M {
        \\  int32 explicit_id = 1;
        \\  int32 implicit_id = 2 [features.field_presence = IMPLICIT];
        \\  int32 required_id = 3 [features.field_presence = LEGACY_REQUIRED];
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "has_explicit_id: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_implicit_id: bool = false") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_required_id: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_explicit_id) try w.writeInt32(1, self.explicit_id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.implicit_id != 0) try w.writeInt32(2, self.implicit_id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_required_id) try w.writeInt32(3, self.required_id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.explicit_id = try r.readInt32(); self.has_explicit_id = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.required_id = try r.readInt32(); self.has_required_id = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!self.has_required_id) return \"required_id\";") != null);
}

test "codegen honors editions message encoding features" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.message_encoding = DELIMITED;
        \\message Child { int32 id = 1; }
        \\message Parent {
        \\  Child delimited = 1;
        \\  Child length_prefixed = 2 [features.message_encoding = LENGTH_PREFIXED];
        \\  oneof pick { Child picked = 3 [features.message_encoding = DELIMITED]; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .start_group); try w.appendSlice(self.delimited); try w.writeTag(1, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.length_prefixed) |value| { const payload_len = value.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(3, .start_group); try w.appendSlice(value); try w.writeTag(3, .end_group)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = try r.readGroupBytes(1); if (self.has_delimited") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.has_delimited = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var _pbz_nested = try Child.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.length_prefixed = _pbz_nested;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value = try r.readGroupBytes(3);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._pbzDeinitOneof_pick(allocator); self.pick = .{ .picked = value };") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen honors utf8 validation features for wire strings" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\message M {
        \\  string strict = 1;
        \\  string relaxed = 2 [features.utf8_validation = NONE];
        \\  repeated string tags = 3;
        \\  oneof pick { string alias = 4; }
        \\  map<string, string> labels = 5;
        \\  map<string, string> relaxed_labels = 6 [features.utf8_validation = NONE];
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_strict) { if (!pbz.validateUtf8(self.strict)) return error.InvalidUtf8; try w.writeString(1, self.strict); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_relaxed) try w.writeString(2, self.relaxed);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.tags) |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; try w.writeString(3, item); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".alias => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try w.writeString(4, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { self.strict = try r.readBytes(); if (!pbz.validateUtf8(self.strict)) return error.InvalidUtf8; self.has_strict = true; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { self.relaxed = try r.readBytes(); self.has_relaxed = true; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try tags_list.append(allocator, value); },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; self._pbzDeinitOneof_pick(allocator); self.pick = .{ .alias = value }; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!pbz.validateUtf8(entry.value)) return error.InvalidUtf8;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (entry_tag.wire_type != .length_delimited) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value = try entry_reader.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.key = value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value = value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"strict: \"); const value = self.strict; if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"key: \"); if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(entry.key, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"value: \"); if (!pbz.validateUtf8(entry.value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(entry.value, writer);") != null);

    const text_start = std.mem.indexOf(u8, content, "pub fn parseText").?;
    const text_content = content[text_start..];
    try std.testing.expect(std.mem.indexOf(u8, text_content, "self.strict = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "self.relaxed = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "tags_list.append(allocator, blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; })") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "entry.key = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_key); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "entry.value = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "self._pbzDeinitOneof_pick(allocator); self.pick = .{ .alias = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; } };") != null);
}

test "codegen honors editions enum type features in JSON parse" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\enum OpenKind { option features.enum_type = OPEN; NONE = 0; USER = 1; }
        \\message M {
        \\  ClosedKind closed = 1;
        \\  OpenKind open = 2;
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "self.closed = @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) catch |err| { if (options.ignore_unknown_fields) continue; return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.open = @This().jsonEnum(value, &.{\"NONE\", \"USER\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; };") != null);
}

test "codegen validates closed enum values in wire decode" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  ClosedKind single = 1;
        \\  repeated ClosedKind many = 2;
        \\  oneof pick { ClosedKind choice = 3; }
        \\}
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try r.readInt32(); if (!@This().enumKnown(value, &.{0, 1})) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else { self.single = value; self.has_single = true; } }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!@This().enumKnown(value, &.{0, 1})) { try pbz.wire.appendRawVarintPayload(allocator, &_unknown_fields_list, 2, payload[value_start..value_end]); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendRawVarintPayload(allocator, &_unknown_fields_list, 2, payload[value_start..value_end]);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "{ const value = try r.readInt32(); if (!@This().enumKnown(value, &.{0, 1})) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else { try many_list.append(allocator, value); } }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._pbzDeinitOneof_pick(allocator); self.pick = .{ .choice = value };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn enumKnown(value: i32, comptime numbers: []const i32) bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.single = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const parsed_enum = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .choice = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; } };") != null);
}

test "codegen validates closed enum map values in wire decode" {
    const allocator = std.testing.allocator;
    var file = try @import("../parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\message M { map<string, ClosedKind> keyed = 1; }
    );
    defer file.deinit();
    const content = try cg.generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "var skip_entry = false;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (entry_tag.wire_type != .varint) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value = try entry_reader.readInt32();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!@This().enumKnown(value, &.{0, 1})) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "skip_entry = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value = value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (skip_entry) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else try @This().putMapEntry_keyed(allocator, &self.keyed, entry);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().putMapEntry_keyed(allocator, &self.keyed, entry);") != null);
}

test "codegen emits well-known-type JSON parse and stringify" {
    const allocator = std.testing.allocator;
    var wkt = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Timestamp { int64 seconds = 1; int32 nanos = 2; }
        \\message Duration { int64 seconds = 1; int32 nanos = 2; }
        \\message FieldMask { repeated string paths = 1; }
        \\message Empty {}
        \\message Int32Value { int32 value = 1; }
    );
    defer wkt.deinit();
    wkt.name = "wkt.proto";
    var app = try @import("../parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\import "wkt.proto";
        \\message Event {
        \\  google.protobuf.Timestamp at = 1;
        \\  google.protobuf.Duration wait = 2;
        \\  google.protobuf.Int32Value count = 3;
        \\  repeated google.protobuf.Timestamp history = 4;
        \\  oneof pick { google.protobuf.Timestamp picked = 5; }
        \\  google.protobuf.FieldMask mask = 6;
        \\  google.protobuf.Empty empty = 7;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&wkt);
    try registry.addFile(&app);

    const content = try cg.generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.Timestamp.jsonParseUnquoted(try @This().jsonString(value))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.Duration.jsonParseUnquoted(try @This().jsonString(value))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".{ .value = try @This().jsonInt(i32, value) }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.Timestamp.jsonParseUnquoted(try @This().jsonString(item))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "(pbz.Timestamp{ .seconds = value.seconds, .nanos = value.nanos }).jsonStringify(writer)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "(pbz.Int32Value{ .value = value.value }).jsonStringify(writer)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "(pbz.FieldMask{ .paths = value.paths }).jsonStringify(writer)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.Empty.jsonStringify(writer)") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}
