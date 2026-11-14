const schema = @import("schema.zig");
const std = @import("std");
const wire = @import("wire.zig");
const module = @import("parser.zig");
const Parser = module.Parser;

test "parser handles proto2 proto3 and editions declarations" {
    const allocator = std.testing.allocator;
    const source =
        \\edition = "2023";
        \\package demo.ed;
        \\option features.repeated_field_encoding = EXPANDED;
        \\import public "other.proto";
        \\message Person {
        \\  string name = 1;
        \\  repeated int32 scores = 2 [features.repeated_field_encoding = PACKED];
        \\  oneof contact { string email = 3; bytes phone = 4; }
        \\  enum Kind { KIND_UNSPECIFIED = 0; ADMIN = 1; }
        \\  Kind kind = 5;
        \\  reserved 6 to 9, 20;
        \\  extensions 100 to max;
        \\}
        \\service Directory { rpc Get (Person) returns (Person); }
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    try std.testing.expectEqual(schema.Syntax.editions, file.syntax);
    try std.testing.expectEqual(schema.Edition.edition_2023, file.edition);
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, file.features.repeated_field_encoding);
    try std.testing.expectEqual(@as(usize, 1), file.imports.items.len);
    const person = file.findMessage("Person").?;
    try std.testing.expectEqual(@as(usize, 5), person.fields.items.len);
    try std.testing.expect(person.findField("scores").?.packed_override.?);
    try std.testing.expect(person.findField("kind").?.kind == .enumeration);
    try std.testing.expectEqual(@as(usize, 1), file.services.items.len);
}

test "parser accepts unstable and test-only edition declarations" {
    const allocator = std.testing.allocator;
    var unstable = try Parser.parse(allocator,
        \\edition = "UNSTABLE";
        \\message M { int32 id = 1; }
    );
    defer unstable.deinit();
    try std.testing.expectEqual(schema.Syntax.editions, unstable.syntax);
    try std.testing.expectEqual(schema.Edition.unstable, unstable.edition);

    var test_only = try Parser.parse(allocator,
        \\edition = "99998_TEST_ONLY";
        \\message M { int32 id = 1; }
    );
    defer test_only.deinit();
    try std.testing.expectEqual(schema.Edition.edition_99998_test_only, test_only.edition);

    try std.testing.expectError(error.InvalidEdition, Parser.parse(allocator,
        \\edition = "PROTO2";
        \\message Bad { int32 id = 1; }
    ));
    try std.testing.expectError(error.InvalidEdition, Parser.parse(allocator,
        \\edition = "UNKNOWN";
        \\message Bad { int32 id = 1; }
    ));
}

test "parser rejects duplicate or mixed syntax and edition declarations" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\edition = "2023";
        \\message Bad { optional int32 id = 1; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\syntax = "proto2";
        \\message Bad { int32 id = 1; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\syntax = "proto3";
        \\message Bad { optional int32 id = 1; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\edition = "2024";
        \\message Bad { int32 id = 1; }
    ));
}

test "parser rejects weak imports under edition 2024 and beyond" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2024";
        \\import weak "dep.proto";
        \\message Bad {}
    ));
}

test "parser validates option import edition and ordering" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\import "";
        \\message Bad {}
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\import "dep.proto";
        \\import "dep.proto";
        \\message Bad {}
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2024";
        \\import "dep.proto";
        \\import option "dep.proto";
        \\message Bad {}
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\import option "options.proto";
        \\message Bad {}
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\import option "options.proto";
        \\message Bad {}
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2024";
        \\import option "options.proto";
        \\import "data.proto";
        \\message Bad {}
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2024";
        \\import option "options.proto";
        \\import public "data.proto";
        \\message Bad {}
    ));

    var file = try Parser.parse(allocator,
        \\edition = "2024";
        \\import "data.proto";
        \\import option "options.proto";
        \\message Ok { int32 id = 1; }
    );
    defer file.deinit();
    try std.testing.expectEqual(schema.Import.Kind.normal, file.imports.items[0].kind);
    try std.testing.expectEqual(schema.Import.Kind.option, file.imports.items[1].kind);
}

test "parser records basic source code info locations" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\option java_package = "demo";
        \\message Person { option deprecated = true; optional string name = 1 [deprecated = true]; message Child { optional int32 id = 1 [deprecated = true]; } optional group Box = 3 [deprecated = true] { optional int32 id = 4; } oneof pick { option (demo.oneof_opt) = true; string nick = 2 [deprecated = true]; } extensions 100 to 199; reserved 50 to 60; reserved "old"; extend Person { optional int32 nested_ext = 100 [deprecated = true]; } }
        \\extend Person { optional string top_ext = 101 [deprecated = true]; }
        \\enum Kind { option allow_alias = true; A = 0; B = 0 [deprecated = true]; reserved 5 to 6; reserved "OLD"; }
        \\service Api { option deprecated = true; rpc Get (Person) returns (Person) { option deprecated = true; } }
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    try std.testing.expect(file.source_code_info.locations.items.len >= 6);
    try expectLocationPath(&file, &.{12});
    try expectLocationPath(&file, &.{2});
    try expectLocationPath(&file, &.{ 3, 0 });
    try expectLocationPath(&file, &.{8});
    try expectLocationPath(&file, &.{ 4, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 7 });
    try expectLocationPath(&file, &.{ 4, 0, 2, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 2, 0, 8 });
    try expectLocationPath(&file, &.{ 4, 0, 3, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 3, 0, 2, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 3, 1 });
    try expectLocationPath(&file, &.{ 4, 0, 3, 1, 2, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 3, 0, 2, 0, 8 });
    try expectLocationPath(&file, &.{ 4, 0, 2, 2 });
    try expectLocationPath(&file, &.{ 4, 0, 2, 2, 8 });
    try expectLocationPath(&file, &.{ 4, 0, 8, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 8, 0, 2 });
    try expectLocationPath(&file, &.{ 4, 0, 2, 1 });
    try expectLocationPath(&file, &.{ 4, 0, 2, 1, 8 });
    try expectLocationPath(&file, &.{ 4, 0, 5, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 9, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 10, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 6, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 6, 0, 8 });
    try expectLocationPath(&file, &.{ 7, 0 });
    try expectLocationPath(&file, &.{ 7, 0, 8 });
    try expectLocationPath(&file, &.{ 5, 0 });
    try expectLocationPath(&file, &.{ 5, 0, 3 });
    try expectLocationPath(&file, &.{ 5, 0, 2, 0 });
    try expectLocationPath(&file, &.{ 5, 0, 2, 1 });
    try expectLocationPath(&file, &.{ 5, 0, 2, 1, 3 });
    try expectLocationPath(&file, &.{ 5, 0, 4, 0 });
    try expectLocationPath(&file, &.{ 5, 0, 5, 0 });
    try expectLocationPath(&file, &.{ 6, 0 });
    try expectLocationPath(&file, &.{ 6, 0, 3 });
    try expectLocationPath(&file, &.{ 6, 0, 2, 0 });
    try expectLocationPath(&file, &.{ 6, 0, 2, 0, 4 });
}

test "parser records source code info line comments" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\// detached paragraph
        \\
        \\// Person leading one
        \\// Person leading two
        \\message Person {
        \\  // name leading
        \\  optional string name = 1; // name trailing
        \\}
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    const message_location = findLocationPath(&file, &.{ 4, 0 }).?;
    try std.testing.expectEqual(@as(usize, 1), message_location.leading_detached_comments.items.len);
    try std.testing.expectEqualStrings("detached paragraph\n", message_location.leading_detached_comments.items[0]);
    try std.testing.expectEqualStrings("Person leading one\nPerson leading two\n", message_location.leading_comments.?);
    const field_location = findLocationPath(&file, &.{ 4, 0, 2, 0 }).?;
    try std.testing.expectEqualStrings("name leading\n", field_location.leading_comments.?);
    try std.testing.expectEqualStrings("name trailing\n", field_location.trailing_comments.?);
}

test "parser records source code info block comments" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\/* Message block
        \\ * second line */
        \\message Person {
        \\  optional string name = 1; /* field trailing block */
        \\}
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    const message_location = findLocationPath(&file, &.{ 4, 0 }).?;
    try std.testing.expectEqualStrings("Message block\nsecond line\n", message_location.leading_comments.?);
    const field_location = findLocationPath(&file, &.{ 4, 0, 2, 0 }).?;
    try std.testing.expectEqualStrings("field trailing block\n", field_location.trailing_comments.?);
}

fn expectLocationPath(file: *const schema.FileDescriptor, path: []const i32) !void {
    const location = findLocationPath(file, path) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 4), location.span.items.len);
}

fn findLocationPath(file: *const schema.FileDescriptor, path: []const i32) ?*const schema.SourceCodeInfo.Location {
    for (file.source_code_info.locations.items) |*location| {
        if (std.mem.eql(i32, location.path.items, path)) {
            return location;
        }
    }
    return null;
}

test "parser handles proto3 optional and map fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Bag {
        \\  optional string label = 1;
        \\  map<string, int32> counts = 2;
        \\}
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    const bag = file.findMessage("Bag").?;
    try std.testing.expect(bag.findField("label").?.proto3_optional);
    try std.testing.expect(bag.findField("counts").?.kind == .map);
}

test "parser rejects explicit map_entry message option" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message BadEntry {
        \\  option map_entry = true;
        \\  string key = 1;
        \\  int32 value = 2;
        \\}
    ));
}

test "parser decodes string and bytes escapes" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Escapes {
        \\  optional string text = 1 [default = "line\n\x41\101"];
        \\  optional bytes raw = 2 [default = "\001\x02"];
        \\}
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    const msg = file.findMessage("Escapes").?;
    try std.testing.expectEqualSlices(u8, "line\nAA", msg.findField("text").?.default_value.?.string);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, msg.findField("raw").?.default_value.?.string);
}

test "parser concatenates adjacent string literals" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\import "foo/" "bar.proto";
        \\message Joined {
        \\  optional string text = 1 [default = "hello" "\n" "world"];
        \\}
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    try std.testing.expectEqualSlices(u8, "foo/bar.proto", file.imports.items[0].path);
    try std.testing.expectEqualSlices(u8, "hello\nworld", file.findMessage("Joined").?.findField("text").?.default_value.?.string);
}

test "parser resolves enum symbolic defaults" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\message Defaults { optional Kind kind = 1 [default = ADMIN]; }
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    try std.testing.expectEqual(@as(i64, 7), file.findMessage("Defaults").?.findField("kind").?.default_value.?.integer);
}

test "parser accepts max unsigned integer defaults" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Defaults {
        \\  optional uint32 u32 = 1 [default = 0xFFFFFFFF];
        \\  optional uint64 u64 = 2 [default = 0xFFFFFFFFFFFFFFFF];
        \\  optional fixed64 f64 = 3 [default = 18446744073709551615];
        \\  optional int32 i32 = 4 [default = 0x7FFFFFFF];
        \\}
    );
    defer file.deinit();
    const msg = file.findMessage("Defaults").?;
    try std.testing.expectEqual(@as(i64, 4294967295), msg.findField("u32").?.default_value.?.integer);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), msg.findField("u64").?.default_value.?.unsigned_integer);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), msg.findField("f64").?.default_value.?.unsigned_integer);
    try std.testing.expectEqual(@as(i64, 2147483647), msg.findField("i32").?.default_value.?.integer);

    try std.testing.expectError(error.InvalidDefault, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional uint64 value = 1 [default = 0x10000000000000000]; }
    ));
}

test "parser accepts special float defaults" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Defaults {
        \\  optional double pos = 1 [default = inf];
        \\  optional double neg = 2 [default = -inf];
        \\  optional float quiet = 3 [default = nan];
        \\  optional float plus = 4 [default = +inf];
        \\  optional float negative_quiet = 5 [default = -nan];
        \\  optional double infinity = 6 [default = Infinity];
        \\  optional double huge = 7 [default = 18446744073709551616];
        \\}
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    const msg = file.findMessage("Defaults").?;
    try std.testing.expectEqualStrings("inf", msg.findField("pos").?.default_value.?.identifier);
    try std.testing.expect(std.math.isNegativeInf(msg.findField("neg").?.default_value.?.float));
    try std.testing.expectEqualStrings("nan", msg.findField("quiet").?.default_value.?.identifier);
    try std.testing.expect(std.math.isPositiveInf(msg.findField("plus").?.default_value.?.float));
    try std.testing.expect(std.math.isNan(msg.findField("negative_quiet").?.default_value.?.float));
    try std.testing.expectEqualStrings("Infinity", msg.findField("infinity").?.default_value.?.identifier);
    try std.testing.expectEqual(@as(f64, 18446744073709551616), msg.findField("huge").?.default_value.?.float);
}

test "parser rejects missing proto2 field labels" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { int32 id = 1; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { group Legacy = 1 { optional int32 id = 2; } }
    ));
    var proto3 = try Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Ok { int32 id = 1; }
    );
    defer proto3.deinit();
    try std.testing.expectEqual(schema.Cardinality.implicit, proto3.findMessage("Ok").?.findField("id").?.cardinality);
}

test "parser rejects invalid field defaults" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidDefault, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Bad { int32 id = 1 [default = 1]; }
    ));
    try std.testing.expectError(error.InvalidDefault, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { repeated int32 ids = 1 [default = 1]; }
    ));
    try std.testing.expectError(error.InvalidDefault, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child {}
        \\message Bad { optional Child child = 1 [default = "x"]; }
    ));
    try std.testing.expectError(error.InvalidDefault, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 id = 1 [default = "not-int"]; }
    ));
    try std.testing.expectError(error.InvalidDefault, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; }
        \\message Bad { optional Kind kind = 1 [default = MISSING]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 id = 1 [default = 1, default = 2]; }
    ));
}

test "parser rejects duplicate type symbols in the same scope" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message User {}
        \\message User {}
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message User {}
        \\enum User { UNKNOWN = 0; }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Outer { message Item {} enum Item { UNKNOWN = 0; } }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Outer { message Item {} message Item {} }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Outer { optional int32 Item = 1; message Item {} }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Outer { optional int32 Kind = 1; enum Kind { UNKNOWN = 0; } }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Outer { oneof Item { int32 value = 1; } message Item {} }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Outer { oneof Kind { int32 value = 1; } enum Kind { UNKNOWN = 0; } }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to 200; }
        \\enum E { ext = 0; }
        \\extend Host { optional int32 ext = 100; }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to 200; }
        \\message ext {}
        \\extend Host { optional int32 ext = 100; }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\message Scope {
        \\  optional int32 ext = 1;
        \\  extend Target { optional int32 ext = 100; }
        \\}
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\message Scope {
        \\  oneof ext { int32 value = 1; }
        \\  extend Target { optional int32 ext = 100; }
        \\}
    ));
}

test "parser validates service and rpc symbols and local message types" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Api {}
        \\service Api { rpc Get (Req) returns (Req); }
        \\message Req {}
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Req {}
        \\service Api { rpc Get (Req) returns (Req); }
        \\service Api { rpc Put (Req) returns (Req); }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Req {}
        \\service Api { rpc Get (Req) returns (Req); rpc Get (Req) returns (Req); }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Req { UNKNOWN = 0; }
        \\service Api { rpc Get (Req) returns (Req); }
    ));
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Req {}
        \\service Api { rpc Get (Req) returns (External); }
    );
    defer file.deinit();
    try std.testing.expectEqual(@as(usize, 1), file.services.items.len);
}

test "parser rejects invalid packed field options" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 id = 1 [packed = true]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { repeated string names = 1 [packed = true]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2023";
        \\message Bad { string name = 1 [features.repeated_field_encoding = PACKED]; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\message Bad { repeated int32 values = 1 [packed = true]; }
    ));
}

test "parser rejects invalid field option applicability" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 id = 1 [jstype = JS_STRING]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 id = 1 [lazy = true]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 id = 1 [weak = true]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child {}
        \\message Bad { repeated Child children = 1 [weak = true]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child {}
        \\message Bad { oneof pick { Child child = 1 [weak = true]; } }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to 200; }
        \\message Ext {}
        \\extend Host { optional Ext ext = 100 [unverified_lazy = true]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to 200; }
        \\message Ext {}
        \\extend Host { optional Ext ext = 100 [weak = true]; }
    ));
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child {}
        \\message Ok {
        \\  optional Child child = 1 [lazy = true, weak = true, unverified_lazy = true];
        \\  optional int64 big = 2 [jstype = JS_STRING];
        \\}
    );
    defer file.deinit();
    try std.testing.expectEqual(@as(usize, 3), file.findMessage("Ok").?.findField("child").?.options.items.len);
    try std.testing.expectEqual(@as(usize, 1), file.findMessage("Ok").?.findField("big").?.options.items.len);
}

test "parser rejects group names not starting with capital letter" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional group legacy = 1 { optional int32 id = 2; } }
    ));
}

test "parser rejects legacy groups under editions" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\message Bad { optional group Legacy = 1 { int32 id = 2; } }
    ));
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Ok { optional group Legacy = 1 { optional int32 id = 2; } }
    );
    defer file.deinit();
    try std.testing.expect(file.findMessage("Ok").?.findField("legacy").?.kind == .group);
}

test "parser rejects invalid and reserved field numbers" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidNumber, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 zero = 0; }
    ));
    try std.testing.expectError(error.InvalidNumber, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 reserved = 19000; }
    ));
}

test "parser rejects duplicate field names and numbers" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 a = 1; optional int32 b = 1; }
    ));
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 a = 1; optional int32 a = 2; }
    ));
}

test "parser rejects invalid json_name options" {
    const allocator = std.testing.allocator;
    var legacy_default_conflict = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Legacy { optional int32 foo_bar = 1; optional int32 fooBar = 2; }
    );
    legacy_default_conflict.deinit();
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Bad { int32 foo_bar = 1; int32 fooBar = 2; }
    ));
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 foo = 1 [json_name = "sameName"];
        \\  optional int32 bar = 2 [json_name = "sameName"];
        \\}
    ));
    var legacy_custom_default_conflict = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Legacy {
        \\  optional int32 foo = 1 [json_name = "barBaz"];
        \\  optional int32 bar_baz = 2;
        \\}
    );
    legacy_custom_default_conflict.deinit();
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Bad {
        \\  int32 foo = 1 [json_name = "barBaz"];
        \\  int32 bar_baz = 2;
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 foo = 1 [json_name = "[demo.ext]"]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 foo = 1 [json_name = "has\000nul"]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 foo = 1 [json_name = true]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 foo = 1 [json_name = "first", json_name = "second"]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\extend Target { optional int32 ext = 150 [json_name = "customExt"]; }
    ));
}

test "parser validates enum values" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidEnum, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Empty {}
    ));
    try std.testing.expectError(error.InvalidEnum, Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Bad { ONE = 1; }
    ));
    try std.testing.expectError(error.DuplicateEnumValue, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { A = 1; B = 1; }
    ));
    try std.testing.expectError(error.DuplicateEnumValue, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { A = 1; A = 2; }
    ));
    try std.testing.expectError(error.DuplicateEnumValue, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum MyEnum { MY_ENUM_FOO = 1; FOO = 2; }
    ));
    try std.testing.expectError(error.InvalidEnum, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { option allow_alias = false; A = 1; B = 2; }
    ));
    try std.testing.expectError(error.InvalidEnum, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { option allow_alias = true; A = 1; B = 2; }
    ));
    var aliases = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Alias {
        \\  option allow_alias = true;
        \\  ALIAS_FOO = 1;
        \\  FOO = 1;
        \\}
    );
    defer aliases.deinit();
    try std.testing.expectEqual(@as(usize, 1), aliases.enums.items.len);
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum First { SHARED = 0; }
        \\enum Second { SHARED = 0; }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Clash {}
        \\enum Bad { Clash = 0; }
    ));
    try std.testing.expectError(error.DuplicateSymbol, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  optional int32 hit = 1;
        \\  enum Bad { hit = 0; }
        \\}
    ));
}

test "parser rejects enum values using reserved names or numbers" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { reserved 1 to 3; HIT = 2; }
    ));
    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { reserved "OLD"; OLD = 1; }
    ));
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { reserved 5 to 3; OK = 1; }
    ));
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { reserved 1 to 5, 4 to 8; OK = 9; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { A = 0; reserved OLD; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved old; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\enum Bad { A = 0; reserved "OLD"; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\message Bad { reserved "old"; }
    ));

    var editions = try Parser.parse(allocator,
        \\edition = "2023";
        \\enum Ok { A = 0; reserved OLD, REMOVED; }
        \\message M { reserved gone, legacy; }
    );
    defer editions.deinit();
    try std.testing.expectEqualStrings("OLD", editions.findEnum("Ok").?.reserved_names.items[0]);
    try std.testing.expectEqualStrings("REMOVED", editions.findEnum("Ok").?.reserved_names.items[1]);
    try std.testing.expectEqualStrings("gone", editions.findMessage("M").?.reserved_names.items[0]);
    try std.testing.expectEqualStrings("legacy", editions.findMessage("M").?.reserved_names.items[1]);
}

test "parser rejects fields using reserved names or numbers" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved 1 to 3; optional int32 hit = 2; }
    ));
    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved "old"; optional int32 old = 1; }
    ));
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved -10; }
    ));
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved 2147483647; }
    ));
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved 1 to 2147483647; }
    ));

    var enum_negative = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Ok { A = 0; reserved -10; }
    );
    defer enum_negative.deinit();
    try std.testing.expectEqual(@as(i64, -10), enum_negative.findEnum("Ok").?.reserved_ranges.items[0].start);
}

test "parser honors enum allow_alias option" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Alias { option allow_alias = true; A = 1; B = 1; }
    );
    defer file.deinit();
    try std.testing.expectEqual(@as(i32, 1), file.findEnum("Alias").?.findValue("B").?.number);
}

test "parser rejects max as range start" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.UnexpectedToken, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { extensions max; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved max; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Bad { A = 0; reserved max; }
    ));
}

test "parser rejects overlapping reserved declarations" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved 1 to 5, 4 to 8; }
    ));
    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved "old", "old"; }
    ));
}

test "parser rejects extension ranges overlapping reserved ranges" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { extensions 100 to 200; reserved 150 to 160; }
    ));
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved 150 to 160; extensions 100 to 200; }
    ));
}

test "parser rejects extension ranges in proto3" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Bad { extensions 100 to 200; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Outer { message Bad { extensions 100 to 200; } }
    ));
}

test "parser rejects overlapping extension ranges" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { extensions 100 to 200, 150 to 250; }
    ));
}

test "parser enforces message range upper bounds with MessageSet exception" {
    const allocator = std.testing.allocator;
    const field_max = @as(i64, std.math.maxInt(wire.FieldNumber));
    const beyond_field_max = field_max + 1;

    const bad_extension_range = try std.fmt.allocPrint(allocator,
        \\syntax = "proto2";
        \\message Bad {{ extensions {d} to max; }}
    , .{beyond_field_max});
    defer allocator.free(bad_extension_range);
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator, bad_extension_range));

    const bad_reserved_range = try std.fmt.allocPrint(allocator,
        \\syntax = "proto2";
        \\message Bad {{ reserved {d} to max; }}
    , .{beyond_field_max});
    defer allocator.free(bad_reserved_range);
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator, bad_reserved_range));

    const ordinary_max = try std.fmt.allocPrint(allocator,
        \\syntax = "proto2";
        \\message MaxExtension {{ extensions {d} to max; }}
        \\message MaxReserved {{ reserved {d} to max; }}
    , .{ field_max, field_max });
    defer allocator.free(ordinary_max);
    var ordinary = try Parser.parse(allocator, ordinary_max);
    defer ordinary.deinit();
    try std.testing.expectEqual(field_max, ordinary.findMessage("MaxExtension").?.extension_ranges.items[0].start);
    try std.testing.expectEqual(field_max, ordinary.findMessage("MaxReserved").?.reserved_ranges.items[0].start);

    const message_set_high_ranges = try std.fmt.allocPrint(allocator,
        \\syntax = "proto2";
        \\message MsExt {{ option message_set_wire_format = true; extensions 4 to 4, {d} to max; }}
        \\message MsReserved {{ option message_set_wire_format = true; extensions 4 to 4; reserved {d} to max; }}
    , .{ beyond_field_max, beyond_field_max });
    defer allocator.free(message_set_high_ranges);
    var message_set = try Parser.parse(allocator, message_set_high_ranges);
    defer message_set.deinit();
    try std.testing.expectEqual(beyond_field_max, message_set.findMessage("MsExt").?.extension_ranges.items[1].start);
    try std.testing.expectEqual(beyond_field_max, message_set.findMessage("MsReserved").?.reserved_ranges.items[0].start);
}

test "parser rejects normal fields inside extension ranges" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { extensions 100 to 200; optional int32 id = 150; }
    ));
}

test "parser validates extension field numbers against extension ranges" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\extend Target { optional int32 ok = 150; }
    );
    defer file.deinit();
    try std.testing.expectEqual(@as(u29, 150), file.extensions.items[0].number);

    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\extend Target { optional int32 bad = 99; }
    ));
}

test "parser preserves extension range declarations verification and features" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\edition = "2024";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" repeated: true },
        \\    verification = DECLARATION,
        \\    features.enforce_naming_style = STYLE_LEGACY
        \\  ];
        \\}
        \\message Ext {}
    );
    defer file.deinit();

    const range = &file.findMessage("Host").?.extension_ranges.items[0];
    try std.testing.expectEqual(@as(i64, 100), range.start);
    try std.testing.expectEqual(@as(?i64, null), range.end);
    try std.testing.expectEqual(@as(usize, 1), range.declarations.items.len);
    try std.testing.expectEqual(@as(i32, 100), range.declarations.items[0].number);
    try std.testing.expectEqualStrings(".demo.ext", range.declarations.items[0].full_name);
    try std.testing.expectEqualStrings(".demo.Ext", range.declarations.items[0].type_name);
    try std.testing.expect(range.declarations.items[0].repeated);
    try std.testing.expectEqual(schema.ExtensionRangeVerification.declaration, range.verification.?);
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.packed_encoding, range.features.?.repeated_field_encoding);
    try expectLocationPath(&file, &.{ 4, 0, 5, 0, 3 });
}

test "parser copies trailing extension range options across same statement" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\edition = "2024";
        \\message Host {
        \\  extensions 100 to 101, 200 to 201 [
        \\    verification = UNVERIFIED,
        \\    features.enforce_naming_style = STYLE_LEGACY
        \\  ];
        \\}
    );
    defer file.deinit();

    const host = file.findMessage("Host").?;
    try std.testing.expectEqual(@as(usize, 2), host.extension_ranges.items.len);
    for (host.extension_ranges.items) |range| {
        try std.testing.expectEqual(schema.ExtensionRangeVerification.unverified, range.verification.?);
        try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style_legacy, range.features.?.enforce_naming_style);
    }
    try expectLocationPath(&file, &.{ 4, 0, 5, 0, 3 });
    try expectLocationPath(&file, &.{ 4, 0, 5, 1, 3 });
}

test "parser parses field edition_defaults and feature_support aggregates" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message FeatureSetLike {
        \\  optional int32 field_presence = 1 [
        \\    edition_defaults = { edition: EDITION_LEGACY, value: "EXPLICIT" },
        \\    edition_defaults = { edition: EDITION_PROTO3, value: "IMPLICIT" },
        \\    feature_support = {
        \\      edition_introduced: EDITION_2023
        \\      edition_deprecated: EDITION_2024
        \\      deprecation_warning: "use " "new presence"
        \\      edition_removed: EDITION_2026
        \\      removal_error: "removed"
        \\    }
        \\  ];
        \\}
    );
    defer file.deinit();

    const field = file.findMessage("FeatureSetLike").?.findField("field_presence").?;
    try std.testing.expectEqual(@as(usize, 2), field.edition_defaults.items.len);
    try std.testing.expectEqual(schema.Edition.legacy, field.edition_defaults.items[0].edition);
    try std.testing.expectEqualStrings("EXPLICIT", field.edition_defaults.items[0].value);
    try std.testing.expectEqual(schema.Edition.proto3, field.edition_defaults.items[1].edition);
    try std.testing.expectEqualStrings("IMPLICIT", field.edition_defaults.items[1].value);
    try std.testing.expectEqual(schema.Edition.edition_2023, field.feature_support.?.edition_introduced.?);
    try std.testing.expectEqual(schema.Edition.edition_2024, field.feature_support.?.edition_deprecated.?);
    try std.testing.expectEqualStrings("use new presence", field.feature_support.?.deprecation_warning);
    try std.testing.expectEqual(schema.Edition.edition_2026, field.feature_support.?.edition_removed.?);
    try std.testing.expectEqualStrings("removed", field.feature_support.?.removal_error);
}

test "parser applies feature options across declaration scopes" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\edition = "2026";
        \\option features.json_format = LEGACY_BEST_EFFORT;
        \\message M {
        \\  option features.enforce_naming_style = STYLE_LEGACY;
        \\  repeated int32 values = 1 [features.repeated_field_encoding = EXPANDED];
        \\  oneof pick {
        \\    option features.enforce_naming_style = STYLE2024;
        \\    string name = 2;
        \\  }
        \\}
        \\enum E {
        \\  option features.enum_type = CLOSED;
        \\  A = 0 [
        \\    features.enforce_naming_style = STYLE2026,
        \\    feature_support = { edition_removed: EDITION_2026 removal_error: "removed enum value" }
        \\  ];
        \\}
        \\service S {
        \\  option features.enforce_naming_style = STYLE2024;
        \\  rpc Do (M) returns (M) {
        \\    option features.enforce_naming_style = STYLE_LEGACY;
        \\  }
        \\}
    );
    defer file.deinit();

    try std.testing.expectEqual(schema.FeatureSet.JsonFormat.legacy_best_effort, file.features.json_format);
    const message = file.findMessage("M").?;
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style_legacy, message.features.?.enforce_naming_style);
    const field = message.findField("values").?;
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, field.features.?.repeated_field_encoding);
    try std.testing.expect(!field.resolvedPacked(&file));
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2024, message.oneofs.items[0].features.?.enforce_naming_style);
    const enumeration = file.findEnum("E").?;
    try std.testing.expectEqual(schema.FeatureSet.EnumType.closed, enumeration.features.?.enum_type);
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2026, enumeration.values.items[0].features.?.enforce_naming_style);
    try std.testing.expectEqual(schema.Edition.edition_2026, enumeration.values.items[0].feature_support.?.edition_removed.?);
    try std.testing.expectEqualStrings("removed enum value", enumeration.values.items[0].feature_support.?.removal_error);
    const service = file.services.items[0];
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2024, service.features.?.enforce_naming_style);
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style_legacy, service.methods.items[0].features.?.enforce_naming_style);
}

test "parser enforces editions STYLE2024 naming" {
    const allocator = std.testing.allocator;
    var valid = try Parser.parse(allocator,
        \\edition = "2024";
        \\package demo.v1;
        \\option features.enforce_naming_style = STYLE2024;
        \\message GoodName {
        \\  int32 good_field = 1;
        \\  oneof good_oneof { int32 a = 2; }
        \\}
        \\enum GoodEnum { GOOD_ENUM_UNKNOWN = 0; }
        \\service GoodService { rpc DoThing (GoodName) returns (GoodName); }
    );
    defer valid.deinit();

    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE2024;
        \\message lower_name {}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE2024;
        \\message M { int32 camelCase = 1; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE2024;
        \\message M { int32 _x = 1; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE2024;
        \\message M { oneof camelOne { int32 x = 1; } }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE2024;
        \\enum E_BAD { E_BAD_UNKNOWN = 0; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE2024;
        \\enum E { unknown = 0; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE2024;
        \\message M { int32 x = 1; }
        \\service svc { rpc Do (M) returns (M); }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE2024;
        \\message M { int32 x = 1; }
        \\service Svc { rpc do_thing (M) returns (M); }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\package Demo;
        \\option features.enforce_naming_style = STYLE2024;
        \\message M {}
    ));
    var legacy = try Parser.parse(allocator,
        \\edition = "2024";
        \\option features.enforce_naming_style = STYLE_LEGACY;
        \\message lower_name { int32 camelCase = 1; }
    );
    defer legacy.deinit();
}

test "parser applies edition 2024 and 2026 feature defaults" {
    const allocator = std.testing.allocator;

    // Edition 2024 enables STYLE2024 and EXPORT_TOP_LEVEL without an explicit option.
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\package demo;
        \\message lower_name {}
    ));
    var v2024 = try Parser.parse(allocator,
        \\edition = "2024";
        \\package demo;
        \\message GoodName { int32 good_field = 1; }
    );
    defer v2024.deinit();
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2024, v2024.features.enforce_naming_style);
    try std.testing.expectEqual(schema.FeatureSet.DefaultSymbolVisibility.export_top_level, v2024.features.default_symbol_visibility);
    try std.testing.expectEqual(schema.FeatureSet.EnforceProtoLimits.legacy_no_explicit_limits, v2024.features.enforce_proto_limits);

    // Edition 2026 also enables STYLE2026 and PROTO_LIMITS2026.
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message lower_name {}
    ));
    var v2026 = try Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName { int32 good_field = 1; }
    );
    defer v2026.deinit();
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2026, v2026.features.enforce_naming_style);
    try std.testing.expectEqual(schema.FeatureSet.DefaultSymbolVisibility.strict, v2026.features.default_symbol_visibility);
    try std.testing.expectEqual(schema.FeatureSet.EnforceProtoLimits.proto_limits2026, v2026.features.enforce_proto_limits);

    // Explicit options still override the edition defaults.
    var legacy = try Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\option features.enforce_naming_style = STYLE_LEGACY;
        \\message lower_name { int32 camelCase = 1; }
    );
    defer legacy.deinit();
}

test "parser enforces STYLE2026 generated-name collision rules" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  int32 foo = 1;
        \\  int32 has_foo = 2;
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  int32 foo = 1;
        \\  int32 get_foo = 2;
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  int32 foo = 1;
        \\  int32 foo_value = 2;
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  int32 foo = 1;
        \\  oneof foo_value { int32 bar = 2; }
        \\}
    ));
    // STYLE2024 does not include the collision rule.
    var v2024 = try Parser.parse(allocator,
        \\edition = "2024";
        \\package demo;
        \\message GoodName {
        \\  int32 foo = 1;
        \\  int32 has_foo = 2;
        \\}
    );
    defer v2024.deinit();
    // A field without the colliding peer is fine under STYLE2026.
    var v2026 = try Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  int32 has_foo = 1;
        \\  int32 foo_value = 2;
        \\}
    );
    defer v2026.deinit();
}

test "parser enforces edition 2026 proto limits" {
    const allocator = std.testing.allocator;

    var fields: std.ArrayListUnmanaged(u8) = .empty;
    defer fields.deinit(allocator);
    try fields.appendSlice(allocator, "edition = \"2026\";\npackage demo;\nmessage GoodName {\n");
    for (0..1501) |i| {
        const line = try std.fmt.allocPrint(allocator, "  int32 f{d} = {d};\n", .{ i, i + 1 });
        defer allocator.free(line);
        try fields.appendSlice(allocator, line);
    }
    try fields.appendSlice(allocator, "}\n");
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator, fields.items));

    // A message-level opt-out restores the pre-2026 behavior.
    var opted_out: std.ArrayListUnmanaged(u8) = .empty;
    defer opted_out.deinit(allocator);
    try opted_out.appendSlice(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  option features.enforce_proto_limits = LEGACY_NO_EXPLICIT_LIMITS;
    );
    for (0..1501) |i| {
        const line = try std.fmt.allocPrint(allocator, "  int32 f{d} = {d};\n", .{ i, i + 1 });
        defer allocator.free(line);
        try opted_out.appendSlice(allocator, line);
    }
    try opted_out.appendSlice(allocator, "}\n");
    var allowed = try Parser.parse(allocator, opted_out.items);
    defer allowed.deinit();

    var values: std.ArrayListUnmanaged(u8) = .empty;
    defer values.deinit(allocator);
    try values.appendSlice(allocator, "edition = \"2026\";\npackage demo;\nenum BigEnum {\n");
    for (0..1701) |i| {
        const line = try std.fmt.allocPrint(allocator, "  BIG_ENUM_V{d} = {d};\n", .{ i, i });
        defer allocator.free(line);
        try values.appendSlice(allocator, line);
    }
    try values.appendSlice(allocator, "}\n");
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator, values.items));

    var oneofs: std.ArrayListUnmanaged(u8) = .empty;
    defer oneofs.deinit(allocator);
    try oneofs.appendSlice(allocator, "edition = \"2026\";\npackage demo;\nmessage GoodName {\n");
    for (0..1001) |i| {
        const line = try std.fmt.allocPrint(allocator, "  oneof o{d} {{ int32 f{d} = {d}; }}\n", .{ i, i, i + 1 });
        defer allocator.free(line);
        try oneofs.appendSlice(allocator, line);
    }
    try oneofs.appendSlice(allocator, "}\n");
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator, oneofs.items));

    var oneof_fields: std.ArrayListUnmanaged(u8) = .empty;
    defer oneof_fields.deinit(allocator);
    try oneof_fields.appendSlice(allocator, "edition = \"2026\";\npackage demo;\nmessage GoodName {\n  oneof pick {\n");
    for (0..1201) |i| {
        const line = try std.fmt.allocPrint(allocator, "    int32 f{d} = {d};\n", .{ i, i + 1 });
        defer allocator.free(line);
        try oneof_fields.appendSlice(allocator, line);
    }
    try oneof_fields.appendSlice(allocator, "  }\n}\n");
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator, oneof_fields.items));
}

test "parser rejects feature options on unsupported targets and removed options" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\option features.enforce_proto_limits = LEGACY_NO_EXPLICIT_LIMITS;
        \\message GoodName { int32 x = 1; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  option features.field_presence = IMPLICIT;
        \\  int32 x = 1;
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  int32 x = 1;
        \\  extensions 100 to max [features.repeated_field_encoding = PACKED];
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\option cc_enable_arenas = true;
        \\message GoodName { int32 x = 1; }
    ));
    var v2024 = try Parser.parse(allocator,
        \\edition = "2024";
        \\package demo;
        \\option cc_enable_arenas = true;
        \\message GoodName { int32 x = 1; }
    );
    defer v2024.deinit();
}

test "parser accepts edition 2024 local and export visibility modifiers" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\edition = "2024";
        \\package demo;
        \\local message LocalMessage { int32 x = 1; }
        \\export enum ExportedEnum { EXPORTED_ENUM_UNKNOWN = 0; }
        \\message Outer { export message Inner { int32 y = 1; } }
    );
    defer file.deinit();
    try std.testing.expectEqual(schema.SymbolVisibility.local, file.findMessage("LocalMessage").?.visibility);
    try std.testing.expectEqual(schema.SymbolVisibility.exported, file.findEnum("ExportedEnum").?.visibility);
    try std.testing.expectEqual(schema.SymbolVisibility.exported, file.findMessage("Outer").?.messages.items[0].visibility);

    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\package demo;
        \\local message LocalMessage { int32 x = 1; }
    ));
    // STRICT forbids exporting nested declarations but allows top-level export.
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message Outer { export message Inner { int32 y = 1; } }
    ));
    var strict_top = try Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\export message TopLevel { int32 x = 1; }
    );
    defer strict_top.deinit();
}

test "parser accepts custom FeatureSet extensions" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\edition = "2023";
        \\package demo;
        \\option features.(pb.cpp).string_type = VIEW;
        \\message M {
        \\  string value = 1 [features.(pb.cpp).string_type = CORD];
        \\}
    );
    defer file.deinit();
    const field = file.findMessage("M").?.findField("value").?;
    // Custom feature extensions stay uninterpreted instead of being applied
    // to the built-in FeatureSet.
    try std.testing.expect(field.features == null);
}

test "parser allows packed false on non-packable fields" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  repeated string strings = 1 [packed = false];
        \\  repeated int32 ints = 2 [packed = false];
        \\}
    );
    defer file.deinit();
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { repeated string strings = 1 [packed = true]; }
    ));
}

test "parser accepts proto2 oneof defaults and int64 minimum literals" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  oneof pick { int32 chosen = 1 [default = 5]; }
        \\  optional int64 minimum = 2 [default = -0x8000000000000000];
        \\}
    );
    defer file.deinit();
    try std.testing.expectEqual(@as(i64, 5), file.findMessage("M").?.findField("chosen").?.default_value.?.integer);
    try std.testing.expectEqual(std.math.minInt(i64), file.findMessage("M").?.findField("minimum").?.default_value.?.integer);
}

test "parser resolves scoped extension extendees" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message A {
        \\  message E { extensions 100 to max; }
        \\  message Ext { extend E { optional Ext e = 100; } }
        \\}
        \\message B {
        \\  message E { extensions 100 to max; }
        \\  message Ext { extend E { optional Ext e = 100; } }
        \\}
    );
    defer file.deinit();
    // The same number on different resolved extendees is legal.
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message E { extensions 100 to max; }
        \\message X { extend E { optional int32 a = 100; } }
        \\message Y { extend E { optional int32 b = 100; } }
    ));
}

test "parser inherits oneof naming style for member fields" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName {
        \\  oneof pick {
        \\    option features.enforce_naming_style = STYLE_LEGACY;
        \\    int32 foo_bar_1 = 1;
        \\  }
        \\}
    );
    defer file.deinit();
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2026";
        \\package demo;
        \\message GoodName { oneof pick { int32 foo_bar_1 = 1; } }
    ));
}

test "parser resolves feature inheritance for partial feature sets" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\edition = "2023";
        \\package demo;
        \\option features.repeated_field_encoding = EXPANDED;
        \\message M {
        \\  int32 plain = 1;
        \\  repeated int32 values = 2 [features.field_presence = IMPLICIT];
        \\}
    );
    defer file.deinit();
    const message = file.findMessage("M").?;
    const plain = message.findField("plain").?;
    const values = message.findField("values").?;
    try std.testing.expect(plain.hasPresence(&file));
    try std.testing.expectEqual(schema.FeatureSet.FieldPresence.implicit, values.fieldPresence(&file));
    try std.testing.expect(!values.resolvedPacked(&file));
    try std.testing.expect(values.features.?.hasPresent("field_presence"));
    try std.testing.expect(!values.features.?.hasPresent("repeated_field_encoding"));
}

test "parser rejects editions group syntax" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2024";
        \\message M { group G = 1 { int32 x = 2; } }
    ));
}

test "parser gates edition-2024 and edition-2026 feature options" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2023";
        \\option features.default_symbol_visibility = LOCAL_ALL;
        \\message A {}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enforce_naming_style = STYLE2024;
        \\message A {}
    ));
    var file = try Parser.parse(allocator,
        \\edition = "2024";
        \\option features.default_symbol_visibility = LOCAL_ALL;
        \\option features.enforce_naming_style = STYLE2024;
        \\message A {}
    );
    defer file.deinit();
    try std.testing.expectEqual(schema.FeatureSet.DefaultSymbolVisibility.local_all, file.features.default_symbol_visibility);
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2024, file.features.enforce_naming_style);
}

test "parser rejects invalid feature option names and values" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\option features.field_presence = IMPLICIT;
        \\message Bad { optional int32 id = 1; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 id = 1 [features.field_presence = IMPLICIT]; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { extensions 100 to 200 [features.enum_type = CLOSED]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2023";
        \\option features.not_a_feature = ENABLED;
        \\message Bad {}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2023";
        \\option features.field_presence = SOMETIMES;
        \\message Bad {}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2023";
        \\message Bad { string name = 1 [features.utf8_validation = true]; }
    ));
}

test "parser validates editions implicit presence feature constraints" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2024";
        \\message Bad { bytes data = 1 [ctype = CORD]; }
    ));
    try std.testing.expectError(error.InvalidDefault, Parser.parse(allocator,
        \\edition = "2023";
        \\option features.field_presence = IMPLICIT;
        \\message Bad { int32 id = 1 [default = 1]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\edition = "2023";
        \\option features.field_presence = IMPLICIT;
        \\option features.enum_type = CLOSED;
        \\enum Kind { A = 0; }
        \\message Bad { Kind kind = 1; }
    ));
    var file = try Parser.parse(allocator,
        \\edition = "2023";
        \\option features.field_presence = IMPLICIT;
        \\option features.enum_type = CLOSED;
        \\enum Kind { option features.enum_type = OPEN; A = 0; }
        \\message Good {
        \\  Kind kind = 1;
        \\  int32 explicit_id = 2 [features.field_presence = EXPLICIT, default = 1];
        \\}
    );
    defer file.deinit();
    try std.testing.expectEqual(@as(usize, 1), file.messages.items.len);
}

test "parser rejects invalid field edition_defaults and feature_support aggregates" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidEdition, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 field_presence = 1 [
        \\    edition_defaults = { edition: EDITION_DOES_NOT_EXIST, value: "EXPLICIT" }
        \\  ];
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 field_presence = 1 [feature_support = EDITION_2023];
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 missing_warning = 1 [
        \\    feature_support = { edition_introduced: EDITION_2023 edition_deprecated: EDITION_2024 }
        \\  ];
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 deprecated_before_introduced = 1 [
        \\    feature_support = { edition_introduced: EDITION_2024 edition_deprecated: EDITION_2023 deprecation_warning: "bad" }
        \\  ];
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 removed_before_introduced = 1 [
        \\    feature_support = { edition_introduced: EDITION_2024 edition_removed: EDITION_2023 }
        \\  ];
        \\}
    ));
}

test "parser validates extension range declarations against defined extensions" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" repeated: true },
        \\    declaration = { number: 101 full_name: ".demo.old" type: ".demo.Ext" reserved: true },
        \\    verification = DECLARATION
        \\  ];
        \\}
        \\message Ext {}
        \\extend Host { repeated Ext ext = 100; }
    );
    defer file.deinit();

    var scoped_type = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.Scope.ext" type: ".demo.Scope.Ext" }
        \\  ];
        \\}
        \\message Scope {
        \\  message Ext {}
        \\  extend Host { optional Ext ext = 100; }
        \\}
    );
    defer scoped_type.deinit();

    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" reserved: true }
        \\  ];
        \\}
        \\message Ext {}
        \\extend Host { optional Ext ext = 100; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Other" }
        \\  ];
        \\}
        \\message Ext {}
        \\message Other {}
        \\extend Host { optional Ext ext = 100; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\package other;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".other.ext" type: ".demo.Ext" }
        \\  ];
        \\}
        \\message Ext {}
        \\extend Host { optional Ext ext = 100; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" repeated: true }
        \\  ];
        \\}
        \\message Ext {}
        \\extend Host { optional Ext ext = 100; }
    ));
    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [verification = DECLARATION];
        \\}
        \\message Ext {}
        \\extend Host { optional Ext ext = 100; }
    ));
    try std.testing.expectError(error.ReservedField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" }
        \\  ];
        \\}
        \\message Ext {}
        \\extend Host { optional Ext other = 101; }
    ));
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".a" type: "int32" },
        \\    declaration = { number: 100 full_name: ".b" type: "int32" }
        \\  ];
        \\}
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to max [declaration = { number: 100 full_name: ".missing.type" }]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to max [declaration = { number: 100 full_name: "missing.dot" type: "int32" }]; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to max [declaration = { number: 100 full_name: ".bad.type" type: ".b#az" }]; }
    ));
    var reserved_declaration = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to max [declaration = { number: 100 reserved: true }]; }
    );
    defer reserved_declaration.deinit();
    try std.testing.expect(reserved_declaration.findMessage("Host").?.extension_ranges.items[0].declarations.items[0].reserved);
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host {
        \\  extensions 100 to 100 [declaration = { number: 100 full_name: ".dup" type: "int32" }],
        \\             101 to 101 [declaration = { number: 101 full_name: ".dup" type: "int32" }];
        \\}
    ));
}

test "parser validates proto2 MessageSet declarations and extensions" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host {
        \\  option message_set_wire_format = true;
        \\  extensions 4 to 529999999;
        \\}
        \\message Ext { optional int32 value = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    try std.testing.expect(file.findMessage("Host").?.messageSetWireFormat());
    try std.testing.expectEqual(@as(u29, 100), file.extensions.items[0].number);
    try std.testing.expectEqualStrings("Ext", file.extensions.items[0].kind.message);

    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { option message_set_wire_format = true; extensions 4 to max; optional int32 id = 1; }
    ));
    // protoc 36.2 no longer requires MessageSet extension ranges to cover 4.
    var narrow = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Narrow { option message_set_wire_format = true; extensions 5 to max; }
    );
    defer narrow.deinit();
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\extend Host { optional int32 bad = 100; }
    ));
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext {}
        \\extend Host { repeated Ext bad = 100; }
    ));
}

test "parser rejects non-option extensions in proto3" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Host {}
        \\extend Host { optional int32 ext = 100; }
    ));
    var options_extension = try Parser.parse(allocator,
        \\syntax = "proto3";
        \\extend google.protobuf.MessageOptions { optional string note = 1000; }
    );
    defer options_extension.deinit();
    try std.testing.expectEqual(@as(usize, 1), options_extension.extensions.items.len);
    try std.testing.expect(!options_extension.extensions.items[0].proto3_optional);
}

test "parser rejects required extension fields" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\extend Target { required int32 bad = 150; }
    ));
}

test "parser rejects extensions of non-message extendees in same file" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Target { UNKNOWN = 0; }
        \\extend Target { optional int32 bad = 100; }
    ));
}

test "parser rejects map and duplicate extension fields" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\extend Target { map<string, int32> bad = 150; }
    ));
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\extend Target { optional int32 a = 150; }
        \\extend Target { optional int32 b = 150; }
    ));
    var scoped = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Target { extensions 100 to 200; }
        \\extend Target { optional int32 a = 150; }
        \\message Scope { extend Target { optional string a = 151; } }
    );
    defer scoped.deinit();
    try std.testing.expect(scoped.extensions.items[0].full_name == null);
    try std.testing.expectEqualStrings("a", scoped.extensions.items[0].name);
    const scoped_ext = scoped.findMessage("Scope").?.extensions.items[0];
    try std.testing.expectEqualStrings("a", scoped_ext.name);
    try std.testing.expectEqualStrings("Scope.a", scoped_ext.full_name.?);
}

test "parser preserves proto2 group extension message types" {
    const allocator = std.testing.allocator;
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to 200; }
        \\extend Host { optional group Legacy = 100 { optional int32 id = 1; } }
        \\message Scope {
        \\  extend Host { optional group Scoped = 101 { optional string name = 1; } }
        \\}
    );
    defer file.deinit();
    try std.testing.expect(file.findMessage("Legacy") != null);
    try std.testing.expectEqualStrings("Legacy", file.extensions.items[0].kind.group);
    const scope = file.findMessage("Scope").?;
    try std.testing.expect(scope.findMessage("Scoped") != null);
    try std.testing.expectEqualStrings("Scoped", scope.extensions.items[0].kind.group);
}

test "parser rejects required label outside proto2" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Bad { required int32 id = 1; }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2023";
        \\message Bad { required int32 id = 1; }
    ));
}

test "parser rejects labelled and group fields inside oneof" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { oneof pick { optional int32 id = 1; } }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { oneof pick { required int32 id = 1; } }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { oneof pick { repeated int32 ids = 1; } }
    ));
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { oneof pick { group Legacy = 1 {} } }
    ));
}

test "parser rejects duplicate oneof names" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { oneof empty {} }
    ));
    try std.testing.expectError(error.DuplicateOneof, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  oneof pick { int32 id = 1; }
        \\  oneof pick { string name = 2; }
        \\}
    ));
    try std.testing.expectError(error.DuplicateOneof, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 pick = 1;
        \\  oneof pick { string name = 2; }
        \\}
    ));
}
