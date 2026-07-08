const std = @import("std");
const schema = @import("schema.zig");
const wire = @import("wire.zig");

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidSyntax,
    InvalidEdition,
    InvalidNumber,
    InvalidFieldType,
    InvalidEnum,
    DuplicateEnumValue,
    DuplicateField,
    InvalidRange,
    InvalidEscape,
    UnterminatedString,
    UnterminatedComment,
};

pub const Error = ParseError || std.mem.Allocator.Error;

const TokenTag = enum {
    eof,
    identifier,
    number,
    string_literal,
    symbol,
};

const Token = struct {
    tag: TokenTag,
    start: usize,
    end: usize,
    text: []const u8,
    symbol: u8 = 0,
};

const Lexer = struct {
    input: []const u8,
    index: usize = 0,

    fn next(self: *Lexer) ParseError!Token {
        try self.skipSpaceAndComments();
        if (self.index >= self.input.len) return .{ .tag = .eof, .start = self.index, .end = self.index, .text = "" };

        const start = self.index;
        const c = self.input[self.index];
        if (isIdentStart(c)) {
            self.index += 1;
            while (self.index < self.input.len and isIdentContinue(self.input[self.index])) self.index += 1;
            return .{ .tag = .identifier, .start = start, .end = self.index, .text = self.input[start..self.index] };
        }
        if (std.ascii.isDigit(c)) {
            self.index += 1;
            while (self.index < self.input.len and isNumberContinue(self.input[self.index])) self.index += 1;
            return .{ .tag = .number, .start = start, .end = self.index, .text = self.input[start..self.index] };
        }
        if (c == '"' or c == '\'') return try self.readString(c);

        self.index += 1;
        return .{ .tag = .symbol, .start = start, .end = self.index, .text = self.input[start..self.index], .symbol = c };
    }

    fn skipSpaceAndComments(self: *Lexer) ParseError!void {
        while (self.index < self.input.len) {
            const c = self.input[self.index];
            if (std.ascii.isWhitespace(c)) {
                self.index += 1;
                continue;
            }
            if (c == '/' and self.index + 1 < self.input.len) {
                const n = self.input[self.index + 1];
                if (n == '/') {
                    self.index += 2;
                    while (self.index < self.input.len and self.input[self.index] != '\n') self.index += 1;
                    continue;
                }
                if (n == '*') {
                    self.index += 2;
                    while (self.index + 1 < self.input.len) : (self.index += 1) {
                        if (self.input[self.index] == '*' and self.input[self.index + 1] == '/') {
                            self.index += 2;
                            break;
                        }
                    } else return error.UnterminatedComment;
                    continue;
                }
            }
            break;
        }
    }

    fn readString(self: *Lexer, quote: u8) ParseError!Token {
        const token_start = self.index;
        self.index += 1;
        const content_start = self.index;
        while (self.index < self.input.len) {
            const c = self.input[self.index];
            if (c == quote) {
                const content_end = self.index;
                self.index += 1;
                return .{
                    .tag = .string_literal,
                    .start = token_start,
                    .end = self.index,
                    .text = self.input[content_start..content_end],
                };
            }
            if (c == '\\') {
                self.index += 1;
                if (self.index >= self.input.len) return error.UnterminatedString;
            }
            self.index += 1;
        }
        return error.UnterminatedString;
    }
};

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return isIdentStart(c) or std.ascii.isDigit(c);
}

fn isNumberContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c == '+' or c == '-';
}

pub const Parser = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    lexer: Lexer,
    current: Token,
    file: schema.FileDescriptor,
    previous_end: usize = 0,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Error!Parser {
        var lexer = Lexer{ .input = input };
        const first = try lexer.next();
        return .{
            .allocator = allocator,
            .input = input,
            .lexer = lexer,
            .current = first,
            .file = schema.FileDescriptor.init(allocator),
            .previous_end = 0,
        };
    }

    pub fn parse(allocator: std.mem.Allocator, input: []const u8) Error!schema.FileDescriptor {
        var self = try Parser.init(allocator, input);
        errdefer self.file.deinit();
        try self.parseFile();
        try self.resolveFieldKinds();
        return self.file;
    }

    fn parseFile(self: *Parser) Error!void {
        while (self.current.tag != .eof) {
            if (self.matchIdent("syntax")) {
                try self.expectSymbol('=');
                const syntax = try self.expectString();
                if (std.mem.eql(u8, syntax, "proto2")) self.file.setSyntax(.proto2) else if (std.mem.eql(u8, syntax, "proto3")) self.file.setSyntax(.proto3) else return error.InvalidSyntax;
                try self.expectSymbol(';');
            } else if (self.matchIdent("edition")) {
                try self.expectSymbol('=');
                const edition_text = try self.expectString();
                const edition = schema.Edition.fromYear(edition_text) orelse return error.InvalidEdition;
                self.file.setEdition(edition);
                try self.expectSymbol(';');
            } else if (self.matchIdent("package")) {
                self.file.package = try self.parseFullIdent();
                try self.expectSymbol(';');
            } else if (self.matchIdent("import")) {
                try self.parseImport();
            } else if (self.matchIdent("option")) {
                try self.file.addOption(try self.parseOptionAssignmentStatement());
            } else if (self.matchIdent("message")) {
                try self.file.messages.append(self.allocator, try self.parseMessageAfterKeyword());
            } else if (self.matchIdent("enum")) {
                try self.file.enums.append(self.allocator, try self.parseEnumAfterKeyword());
            } else if (self.matchIdent("extend")) {
                try self.parseExtend(&self.file.extensions);
            } else if (self.matchIdent("service")) {
                try self.file.services.append(self.allocator, try self.parseServiceAfterKeyword());
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else {
                return error.UnexpectedToken;
            }
        }
    }

    fn parseImport(self: *Parser) Error!void {
        var kind: schema.Import.Kind = .normal;
        if (self.matchIdent("public")) kind = .public else if (self.matchIdent("weak")) kind = .weak else if (self.matchIdent("option")) kind = .option;
        const path = try self.expectString();
        try self.expectSymbol(';');
        try self.file.imports.append(self.allocator, .{ .path = path, .kind = kind });
    }

    fn parseMessageAfterKeyword(self: *Parser) Error!schema.MessageDescriptor {
        var message = schema.MessageDescriptor{ .name = try self.expectIdentifier() };
        errdefer message.deinit(self.allocator);
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.matchIdent("option")) {
                try message.options.append(self.allocator, try self.parseOptionAssignmentStatement());
            } else if (self.matchIdent("message")) {
                try message.messages.append(self.allocator, try self.parseMessageAfterKeyword());
            } else if (self.matchIdent("enum")) {
                try message.enums.append(self.allocator, try self.parseEnumAfterKeyword());
            } else if (self.matchIdent("oneof")) {
                try self.parseOneof(&message);
            } else if (self.matchIdent("extensions")) {
                try self.parseExtensionRanges(&message.extension_ranges);
            } else if (self.matchIdent("reserved")) {
                try self.parseReserved(&message.reserved_ranges, &message.reserved_names);
            } else if (self.matchIdent("extend")) {
                try self.parseExtend(&message.extensions);
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else {
                try message.fields.append(self.allocator, try self.parseField(null, &message));
            }
        }
        try validateMessageFields(&message);
        return message;
    }

    fn parseEnumAfterKeyword(self: *Parser) Error!schema.EnumDescriptor {
        var enumeration = schema.EnumDescriptor{ .name = try self.expectIdentifier() };
        errdefer enumeration.deinit(self.allocator);
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.matchIdent("option")) {
                try enumeration.options.append(self.allocator, try self.parseOptionAssignmentStatement());
            } else if (self.matchIdent("reserved")) {
                try self.parseReserved(&enumeration.reserved_ranges, &enumeration.reserved_names);
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else {
                const name = try self.expectIdentifier();
                try self.expectSymbol('=');
                const number = try self.parseSignedInt32();
                var options: schema.OptionList = .empty;
                errdefer schema.deinitOptions(&options, self.allocator);
                if (self.consumeSymbol('[')) try self.parseOptionList(&options, ']');
                try self.expectSymbol(';');
                try enumeration.values.append(self.allocator, .{ .name = name, .number = number, .options = options });
            }
        }
        try validateEnum(&enumeration, self.file.syntax);
        return enumeration;
    }

    fn parseServiceAfterKeyword(self: *Parser) Error!schema.ServiceDescriptor {
        var service = schema.ServiceDescriptor{ .name = try self.expectIdentifier() };
        errdefer service.deinit(self.allocator);
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.matchIdent("option")) {
                try service.options.append(self.allocator, try self.parseOptionAssignmentStatement());
            } else if (self.matchIdent("rpc")) {
                try service.methods.append(self.allocator, try self.parseRpcAfterKeyword());
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else return error.UnexpectedToken;
        }
        return service;
    }

    fn parseRpcAfterKeyword(self: *Parser) Error!schema.MethodDescriptor {
        var method = schema.MethodDescriptor{ .name = try self.expectIdentifier(), .input_type = "", .output_type = "" };
        errdefer method.deinit(self.allocator);
        try self.expectSymbol('(');
        if (self.matchIdent("stream")) method.client_streaming = true;
        method.input_type = try self.parseTypeNameSlice();
        try self.expectSymbol(')');
        try self.expectIdent("returns");
        try self.expectSymbol('(');
        if (self.matchIdent("stream")) method.server_streaming = true;
        method.output_type = try self.parseTypeNameSlice();
        try self.expectSymbol(')');
        if (self.consumeSymbol('{')) {
            while (!self.consumeSymbol('}')) {
                if (self.current.tag == .eof) return error.UnexpectedEof;
                if (self.matchIdent("option")) try method.options.append(self.allocator, try self.parseOptionAssignmentStatement()) else if (self.consumeSymbol(';')) {} else return error.UnexpectedToken;
            }
            _ = self.consumeSymbol(';');
        } else try self.expectSymbol(';');
        return method;
    }

    fn parseOneof(self: *Parser, message: *schema.MessageDescriptor) Error!void {
        const oneof_name = try self.expectIdentifier();
        try message.oneofs.append(self.allocator, .{ .name = oneof_name });
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.matchIdent("option")) {
                try message.oneofs.items[message.oneofs.items.len - 1].options.append(self.allocator, try self.parseOptionAssignmentStatement());
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else {
                try message.fields.append(self.allocator, try self.parseField(oneof_name, message));
            }
        }
    }

    fn parseExtend(self: *Parser, output: *std.ArrayList(schema.FieldDescriptor)) Error!void {
        const extendee = try self.parseTypeNameSlice();
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.consumeSymbol(';')) continue;
            var field = try self.parseField(null, null);
            field.extendee = extendee;
            try output.append(self.allocator, field);
        }
    }

    fn parseField(self: *Parser, oneof_name: ?[]const u8, parent: ?*schema.MessageDescriptor) Error!schema.FieldDescriptor {
        var cardinality: schema.Cardinality = .implicit;
        var proto3_optional = false;
        if (self.current.tag == .identifier) {
            if (std.mem.eql(u8, self.current.text, "optional")) {
                _ = try self.advance();
                cardinality = .optional;
                proto3_optional = self.file.syntax == .proto3;
            } else if (std.mem.eql(u8, self.current.text, "required")) {
                _ = try self.advance();
                cardinality = .required;
            } else if (std.mem.eql(u8, self.current.text, "repeated")) {
                _ = try self.advance();
                cardinality = .repeated;
            }
        }

        if (self.matchIdent("group")) return try self.parseGroupField(cardinality, oneof_name, parent);

        const kind = try self.parseFieldKind();
        if (kind == .map and (cardinality != .implicit or oneof_name != null)) return error.InvalidFieldType;
        const effective_cardinality: schema.Cardinality = if (kind == .map) .repeated else cardinality;
        const name = try self.expectIdentifier();
        try self.expectSymbol('=');
        const number = try self.parseFieldNumber();
        var field = schema.FieldDescriptor{
            .name = name,
            .number = number,
            .cardinality = effective_cardinality,
            .kind = kind,
            .oneof_name = oneof_name,
            .proto3_optional = proto3_optional,
        };
        errdefer field.deinit(self.allocator);
        if (self.consumeSymbol('[')) try self.parseFieldOptions(&field);
        try self.expectSymbol(';');
        return field;
    }

    fn parseGroupField(self: *Parser, cardinality: schema.Cardinality, oneof_name: ?[]const u8, parent: ?*schema.MessageDescriptor) Error!schema.FieldDescriptor {
        const name = try self.expectIdentifier();
        try self.expectSymbol('=');
        const number = try self.parseFieldNumber();
        var field = schema.FieldDescriptor{
            .name = name,
            .number = number,
            .cardinality = if (cardinality == .implicit) .optional else cardinality,
            .kind = .{ .group = name },
            .oneof_name = oneof_name,
        };
        errdefer field.deinit(self.allocator);
        if (self.consumeSymbol('[')) try self.parseFieldOptions(&field);
        var nested = schema.MessageDescriptor{ .name = name };
        errdefer nested.deinit(self.allocator);
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.consumeSymbol(';')) continue;
            try nested.fields.append(self.allocator, try self.parseField(null, &nested));
        }
        if (parent) |message| {
            try message.messages.append(self.allocator, nested);
        } else {
            nested.deinit(self.allocator);
        }
        return field;
    }

    fn parseFieldKind(self: *Parser) Error!schema.FieldKind {
        if (self.matchIdent("map")) {
            try self.expectSymbol('<');
            const key_name = try self.expectIdentifier();
            const key = schema.ScalarType.fromName(key_name) orelse return error.InvalidFieldType;
            if (!key.validMapKey()) return error.InvalidFieldType;
            try self.expectSymbol(',');
            const value_kind = try self.parseFieldKind();
            try self.expectSymbol('>');
            if (value_kind == .map or value_kind == .group) return error.InvalidFieldType;
            const ptr = try self.allocator.create(schema.FieldKind);
            ptr.* = value_kind;
            return .{ .map = .{ .key = key, .value = ptr } };
        }

        const type_name = try self.parseTypeNameSlice();
        if (schema.ScalarType.fromName(type_name)) |scalar| return .{ .scalar = scalar };
        return .{ .message = type_name };
    }

    fn parseFieldOptions(self: *Parser, field: *schema.FieldDescriptor) Error!void {
        try self.parseOptionList(&field.options, ']');
        for (field.options.items) |option| {
            const leaf = optionLeaf(option.name);
            if (std.mem.eql(u8, leaf, "default")) field.default_value = option.value;
            if (std.mem.eql(u8, leaf, "json_name") and option.value == .string) field.json_name = option.value.string;
            if (std.mem.eql(u8, leaf, "packed")) field.packed_override = schema.optionAsBool(option.value);
            if (std.mem.eql(u8, leaf, "repeated_field_encoding")) {
                if (schema.optionAsIdentifier(option.value)) |ident| {
                    if (std.ascii.eqlIgnoreCase(ident, "PACKED")) field.packed_override = true;
                    if (std.ascii.eqlIgnoreCase(ident, "EXPANDED")) field.packed_override = false;
                }
            }
        }
    }

    fn parseOptionAssignmentStatement(self: *Parser) Error!schema.FieldOption {
        const option = try self.parseOptionAssignment(';');
        try self.expectSymbol(';');
        return option;
    }

    fn parseOptionList(self: *Parser, options: *schema.OptionList, end_symbol: u8) Error!void {
        while (!self.consumeSymbol(end_symbol)) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            try options.append(self.allocator, try self.parseOptionAssignment(end_symbol));
            if (self.consumeSymbol(',')) continue;
            try self.expectSymbol(end_symbol);
            break;
        }
    }

    fn parseOptionAssignment(self: *Parser, terminator: u8) Error!schema.FieldOption {
        const start = self.current.start;
        var paren_depth: usize = 0;
        while (true) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (paren_depth == 0 and self.current.tag == .symbol and self.current.symbol == '=') break;
            if (paren_depth == 0 and self.current.tag == .symbol and (self.current.symbol == terminator or self.current.symbol == ',')) return error.UnexpectedToken;
            if (self.current.tag == .symbol and self.current.symbol == '(') paren_depth += 1;
            if (self.current.tag == .symbol and self.current.symbol == ')') {
                if (paren_depth == 0) return error.UnexpectedToken;
                paren_depth -= 1;
            }
            try self.advanceVoid();
        }
        const raw_name = std.mem.trim(u8, self.input[start..self.current.start], " \t\r\n");
        try self.expectSymbol('=');
        return .{ .name = raw_name, .value = try self.parseOptionValue() };
    }

    fn parseOptionValue(self: *Parser) Error!schema.OptionValue {
        if (self.current.tag == .string_literal) {
            return .{ .string = try self.expectString() };
        }
        if (self.current.tag == .identifier) {
            const value = self.current.text;
            try self.advanceVoid();
            if (std.ascii.eqlIgnoreCase(value, "true")) return .{ .boolean = true };
            if (std.ascii.eqlIgnoreCase(value, "false")) return .{ .boolean = false };
            return .{ .identifier = value };
        }
        if (self.current.tag == .number or (self.current.tag == .symbol and (self.current.symbol == '-' or self.current.symbol == '+'))) {
            const negative = self.consumeSymbol('-');
            _ = if (!negative) self.consumeSymbol('+') else false;
            const number_text = try self.expectNumber();
            if (std.mem.indexOfAny(u8, number_text, ".eE") != null) {
                var buf: [128]u8 = undefined;
                const signed = try signedText(&buf, negative, number_text);
                return .{ .float = std.fmt.parseFloat(f64, signed) catch return error.InvalidNumber };
            }
            var value = try parseI64(number_text);
            if (negative) value = -value;
            return .{ .integer = value };
        }
        if (self.current.tag == .symbol and (self.current.symbol == '{' or self.current.symbol == '<')) {
            return .{ .aggregate = try self.consumeBalancedAggregate() };
        }
        return error.UnexpectedToken;
    }

    fn parseExtensionRanges(self: *Parser, ranges: *std.ArrayList(schema.ExtensionRange)) Error!void {
        while (true) {
            const start = try self.parseRangeBound();
            var end: ?i64 = start + 1;
            if (self.matchIdent("to")) end = try self.parseRangeEnd();
            var range = schema.ExtensionRange{ .start = start, .end = end };
            errdefer range.deinit(self.allocator);
            if (self.consumeSymbol('[')) try self.parseOptionList(&range.options, ']');
            try ranges.append(self.allocator, range);
            if (!self.consumeSymbol(',')) break;
        }
        try self.expectSymbol(';');
    }

    fn parseReserved(self: *Parser, ranges: *std.ArrayList(schema.ReservedRange), names: *std.ArrayList([]const u8)) Error!void {
        if (self.current.tag == .string_literal) {
            while (true) {
                try names.append(self.allocator, try self.expectString());
                if (!self.consumeSymbol(',')) break;
            }
            try self.expectSymbol(';');
            return;
        }
        while (true) {
            const start = try self.parseRangeBound();
            var end: ?i64 = start + 1;
            if (self.matchIdent("to")) end = try self.parseRangeEnd();
            try ranges.append(self.allocator, .{ .start = start, .end = end });
            if (!self.consumeSymbol(',')) break;
        }
        try self.expectSymbol(';');
    }

    fn parseRangeBound(self: *Parser) Error!i64 {
        if (self.matchIdent("max")) return std.math.maxInt(i32);
        return try self.parseSignedInt64();
    }

    fn parseRangeEnd(self: *Parser) Error!?i64 {
        if (self.matchIdent("max")) return null;
        const inclusive = try self.parseSignedInt64();
        return inclusive + 1;
    }

    fn parseFieldNumber(self: *Parser) Error!wire.FieldNumber {
        const value = try self.parseSignedInt64();
        if (value <= 0 or value > std.math.maxInt(wire.FieldNumber)) return error.InvalidNumber;
        if (value >= 19000 and value <= 19999) return error.InvalidNumber;
        return @intCast(value);
    }

    fn parseSignedInt32(self: *Parser) Error!i32 {
        const value = try self.parseSignedInt64();
        if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return error.InvalidNumber;
        return @intCast(value);
    }

    fn parseSignedInt64(self: *Parser) Error!i64 {
        const negative = self.consumeSymbol('-');
        _ = if (!negative) self.consumeSymbol('+') else false;
        const number_text = try self.expectNumber();
        var value = try parseI64(number_text);
        if (negative) value = -value;
        return value;
    }

    fn parseFullIdent(self: *Parser) Error![]const u8 {
        const start = self.current.start;
        _ = try self.expectIdentifier();
        while (self.consumeSymbol('.')) _ = try self.expectIdentifier();
        return self.input[start..self.previousEnd()];
    }

    fn parseTypeNameSlice(self: *Parser) Error![]const u8 {
        const start = self.current.start;
        _ = self.consumeSymbol('.');
        _ = try self.expectIdentifier();
        while (self.consumeSymbol('.')) _ = try self.expectIdentifier();
        return self.input[start..self.previousEnd()];
    }

    fn consumeBalancedAggregate(self: *Parser) Error![]const u8 {
        const open = self.current.symbol;
        const close: u8 = if (open == '{') '}' else '>';
        const start = self.current.start;
        var depth: usize = 0;
        while (true) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.current.tag == .symbol and self.current.symbol == open) depth += 1;
            if (self.current.tag == .symbol and self.current.symbol == close) {
                depth -= 1;
                const end = self.current.end;
                try self.advanceVoid();
                if (depth == 0) return self.input[start..end];
                continue;
            }
            try self.advanceVoid();
        }
    }

    fn resolveFieldKinds(self: *Parser) Error!void {
        for (self.file.messages.items) |*message| try self.resolveMessageFieldKinds(message);
        for (self.file.extensions.items) |*field| try self.resolveFieldKind(field, null);
    }

    fn resolveMessageFieldKinds(self: *Parser, message: *schema.MessageDescriptor) Error!void {
        for (message.fields.items) |*field| try self.resolveFieldKind(field, message);
        for (message.extensions.items) |*field| try self.resolveFieldKind(field, message);
        for (message.messages.items) |*nested| try self.resolveMessageFieldKinds(nested);
    }

    fn resolveFieldKind(self: *Parser, field: *schema.FieldDescriptor, context: ?*schema.MessageDescriptor) Error!void {
        switch (field.kind) {
            .message => |name| {
                if (self.isEnumName(name, context)) field.kind = .{ .enumeration = name };
            },
            .map => |map_type| switch (map_type.value.*) {
                .message => |name| {
                    if (self.isEnumName(name, context)) map_type.value.* = .{ .enumeration = name };
                },
                else => {},
            },
            else => {},
        }
        self.resolveEnumDefault(field, context);
    }

    fn resolveEnumDefault(self: *Parser, field: *schema.FieldDescriptor, context: ?*schema.MessageDescriptor) void {
        const enum_name = switch (field.kind) {
            .enumeration => |name| name,
            else => return,
        };
        const default_name = switch (field.default_value orelse return) {
            .identifier => |name| name,
            .string => |name| name,
            else => return,
        };
        const enumeration = self.findEnumDescriptor(enum_name, context) orelse return;
        if (enumeration.findValue(default_name)) |value| field.default_value = .{ .integer = value.number };
    }

    fn findEnumDescriptor(self: *Parser, name: []const u8, context: ?*schema.MessageDescriptor) ?*const schema.EnumDescriptor {
        const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
        const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
        if (context) |message| {
            if (message.findEnum(leaf)) |enumeration| return enumeration;
        }
        for (self.file.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, leaf) or std.mem.eql(u8, enumeration.name, trimmed)) return enumeration;
        }
        for (self.file.messages.items) |*message| {
            if (findEnumInMessage(message, leaf)) |enumeration| return enumeration;
        }
        return null;
    }

    fn isEnumName(self: *Parser, name: []const u8, context: ?*schema.MessageDescriptor) bool {
        const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
        const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
        if (context) |message| {
            if (message.findEnum(leaf) != null) return true;
        }
        for (self.file.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, leaf) or std.mem.eql(u8, enumeration.name, trimmed)) return true;
        }
        for (self.file.messages.items) |*message| {
            if (messageContainsEnum(message, leaf)) return true;
        }
        return false;
    }

    fn advance(self: *Parser) ParseError!Token {
        const old = self.current;
        self.previous_end = old.end;
        self.current = try self.lexer.next();
        return old;
    }

    fn advanceVoid(self: *Parser) ParseError!void {
        _ = try self.advance();
    }

    fn expectIdentifier(self: *Parser) Error![]const u8 {
        if (self.current.tag != .identifier) return error.UnexpectedToken;
        const text = self.current.text;
        try self.advanceVoid();
        return text;
    }

    fn expectNumber(self: *Parser) Error![]const u8 {
        if (self.current.tag != .number) return error.UnexpectedToken;
        const text = self.current.text;
        try self.advanceVoid();
        return text;
    }

    fn decodeStringLiteral(self: *Parser, text: []const u8) Error![]const u8 {
        const decoded = try decodeStringLiteralAlloc(self.allocator, text);
        errdefer self.allocator.free(decoded);
        try self.file.owned_strings.append(self.allocator, decoded);
        return decoded;
    }

    fn expectString(self: *Parser) Error![]const u8 {
        if (self.current.tag != .string_literal) return error.UnexpectedToken;
        const first = try self.decodeStringLiteral(self.current.text);
        try self.advanceVoid();
        if (self.current.tag != .string_literal) return first;

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        try out.appendSlice(self.allocator, first);
        while (self.current.tag == .string_literal) {
            const part = try self.decodeStringLiteral(self.current.text);
            try out.appendSlice(self.allocator, part);
            try self.advanceVoid();
        }
        const joined = try out.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(joined);
        try self.file.owned_strings.append(self.allocator, joined);
        return joined;
    }

    fn expectSymbol(self: *Parser, symbol: u8) Error!void {
        if (!self.consumeSymbol(symbol)) return error.UnexpectedToken;
    }

    fn expectIdent(self: *Parser, text: []const u8) Error!void {
        if (!self.matchIdent(text)) return error.UnexpectedToken;
    }

    fn consumeSymbol(self: *Parser, symbol: u8) bool {
        if (self.current.tag == .symbol and self.current.symbol == symbol) {
            self.previous_end = self.current.end;
            self.current = self.lexer.next() catch unreachable;
            return true;
        }
        return false;
    }

    fn matchIdent(self: *Parser, text: []const u8) bool {
        if (self.current.tag == .identifier and std.mem.eql(u8, self.current.text, text)) {
            self.previous_end = self.current.end;
            self.current = self.lexer.next() catch unreachable;
            return true;
        }
        return false;
    }

    fn previousEnd(self: *const Parser) usize {
        return self.previous_end;
    }
};

fn validateEnum(enumeration: *const schema.EnumDescriptor, syntax: schema.Syntax) ParseError!void {
    if (syntax == .proto3 and (enumeration.values.items.len == 0 or enumeration.values.items[0].number != 0)) return error.InvalidEnum;
    for (enumeration.values.items, 0..) |value, i| {
        for (enumeration.values.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, value.name, other.name) or value.number == other.number) return error.DuplicateEnumValue;
        }
    }
}

fn validateMessageFields(message: *const schema.MessageDescriptor) ParseError!void {
    for (message.fields.items, 0..) |field, i| {
        for (message.fields.items[i + 1 ..]) |other| {
            if (field.number == other.number or std.mem.eql(u8, field.name, other.name)) return error.DuplicateField;
        }
    }
}

fn findEnumInMessage(message: *const schema.MessageDescriptor, leaf: []const u8) ?*const schema.EnumDescriptor {
    if (message.findEnum(leaf)) |enumeration| return enumeration;
    for (message.messages.items) |*nested| if (findEnumInMessage(nested, leaf)) |found| return found;
    return null;
}

fn optionLeaf(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| name[idx + 1 ..] else name;
}

fn messageContainsEnum(message: *const schema.MessageDescriptor, leaf: []const u8) bool {
    if (message.findEnum(leaf) != null) return true;
    for (message.messages.items) |*nested| if (messageContainsEnum(nested, leaf)) return true;
    return false;
}

fn parseI64(text: []const u8) ParseError!i64 {
    const cleaned = removeUnderscore(text);
    // `cleaned` is either the original slice or a thread-local scratch-free path.
    // Protobuf numeric tokens in schemas are small; this stack copy avoids heap
    // ownership in descriptors.
    return parseI64Clean(cleaned) catch return error.InvalidNumber;
}

fn parseI64Clean(text: []const u8) !i64 {
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) return std.fmt.parseInt(i64, text[2..], 16);
    return std.fmt.parseInt(i64, text, 10);
}

fn removeUnderscore(text: []const u8) []const u8 {
    // Zig's integer parser accepts underscores in recent versions; keep this
    // helper as a semantic marker and fallback to the original slice.
    return text;
}

fn signedText(buf: []u8, negative: bool, text: []const u8) std.mem.Allocator.Error![]const u8 {
    if (!negative) return text;
    if (text.len + 1 > buf.len) return error.OutOfMemory;
    buf[0] = '-';
    @memcpy(buf[1 .. text.len + 1], text);
    return buf[0 .. text.len + 1];
}

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

fn decodeStringLiteralAlloc(allocator: std.mem.Allocator, text: []const u8) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];
        if (c != '\\') {
            try out.append(allocator, c);
            i += 1;
            continue;
        }
        i += 1;
        if (i >= text.len) return error.InvalidEscape;
        const esc = text[i];
        i += 1;
        switch (esc) {
            'a' => try out.append(allocator, 0x07),
            'b' => try out.append(allocator, 0x08),
            'f' => try out.append(allocator, 0x0c),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            'v' => try out.append(allocator, 0x0b),
            '\\' => try out.append(allocator, '\\'),
            '\'' => try out.append(allocator, '\''),
            '"' => try out.append(allocator, '"'),
            '?' => try out.append(allocator, '?'),
            'x', 'X' => {
                var value: u8 = 0;
                var digits: usize = 0;
                while (i < text.len and digits < 2) : (digits += 1) {
                    const digit = hexValue(text[i]) orelse break;
                    value = value * 16 + digit;
                    i += 1;
                }
                if (digits == 0) return error.InvalidEscape;
                try out.append(allocator, value);
            },
            '0'...'7' => {
                var value: u8 = esc - '0';
                var digits: usize = 1;
                while (i < text.len and digits < 3 and text[i] >= '0' and text[i] <= '7') : (digits += 1) {
                    value = value * 8 + (text[i] - '0');
                    i += 1;
                }
                try out.append(allocator, value);
            },
            else => return error.InvalidEscape,
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn hexValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
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

test "parser validates enum values" {
    const allocator = std.testing.allocator;
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
}
