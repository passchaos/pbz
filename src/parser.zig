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
    DuplicateOneof,
    DuplicateSymbol,
    InvalidRange,
    ReservedField,
    InvalidEscape,
    InvalidDefault,
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
        try self.validateImports();
        try self.validateTypeSymbols();
        try self.validateServices();
        try self.resolveFieldKinds();
        try self.validateExtensions();
        try self.validateMessageSets();
        try self.validateDefaults();
        try self.validatePackedOptions();
        try self.validateFieldOptionApplicabilities();
        try self.validateFeatureSemantics();
        return self.file;
    }

    fn parseFile(self: *Parser) Error!void {
        while (self.current.tag != .eof) {
            const decl_start = self.current.start;
            if (self.matchIdent("syntax")) {
                try self.expectSymbol('=');
                const syntax = try self.expectString();
                if (std.mem.eql(u8, syntax, "proto2")) self.file.setSyntax(.proto2) else if (std.mem.eql(u8, syntax, "proto3")) self.file.setSyntax(.proto3) else return error.InvalidSyntax;
                try self.expectSymbol(';');
                try self.addSourceLocation(&.{12}, decl_start, self.previousEnd());
            } else if (self.matchIdent("edition")) {
                try self.expectSymbol('=');
                const edition_text = try self.expectString();
                const edition = schema.Edition.fromYear(edition_text) orelse return error.InvalidEdition;
                self.file.setEdition(edition);
                try self.expectSymbol(';');
                try self.addSourceLocation(&.{14}, decl_start, self.previousEnd());
            } else if (self.matchIdent("package")) {
                self.file.package = try self.parseFullIdent();
                try self.expectSymbol(';');
                try self.addSourceLocation(&.{2}, decl_start, self.previousEnd());
            } else if (self.matchIdent("import")) {
                const import_index: i32 = @intCast(self.file.imports.items.len);
                try self.parseImport();
                try self.addSourceLocation(&.{ 3, import_index }, decl_start, self.previousEnd());
            } else if (self.matchIdent("option")) {
                try self.addFileOption(try self.parseOptionAssignmentStatement());
            } else if (self.matchIdent("message")) {
                const index: i32 = @intCast(self.file.messages.items.len);
                try self.file.messages.append(self.allocator, try self.parseMessageAfterKeyword(&.{ 4, index }, decl_start, self.file.package));
            } else if (self.matchIdent("enum")) {
                const index: i32 = @intCast(self.file.enums.items.len);
                try self.file.enums.append(self.allocator, try self.parseEnumAfterKeyword(&.{ 5, index }, decl_start));
            } else if (self.matchIdent("extend")) {
                try self.parseExtend(&self.file.extensions, "");
            } else if (self.matchIdent("service")) {
                const index: i32 = @intCast(self.file.services.items.len);
                try self.file.services.append(self.allocator, try self.parseServiceAfterKeyword(&.{ 6, index }, decl_start));
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else {
                return error.UnexpectedToken;
            }
        }
    }

    fn addSourceLocation(self: *Parser, path: []const i32, start: usize, end: usize) Error!void {
        var location = schema.SourceCodeInfo.Location{};
        errdefer location.deinit(self.allocator);
        try location.path.appendSlice(self.allocator, path);
        const start_pos = self.lineColumn(start);
        const end_pos = self.lineColumn(end);
        try location.span.appendSlice(self.allocator, &.{ start_pos.line, start_pos.column, end_pos.line, end_pos.column });
        location.leading_comments = try self.leadingLineComments(start);
        try self.leadingDetachedLineComments(start, &location.leading_detached_comments);
        location.trailing_comments = try self.trailingLineComment(end);
        try self.file.source_code_info.locations.append(self.allocator, location);
    }

    fn leadingLineComments(self: *Parser, start: usize) Error!?[]const u8 {
        var line_start = start;
        while (line_start > 0 and self.input[line_start - 1] != '\n') line_start -= 1;
        var cursor = line_start;
        var lines: std.ArrayList([]const u8) = .empty;
        defer lines.deinit(self.allocator);
        while (cursor > 0) {
            const prev_end = cursor - 1;
            var prev_start = prev_end;
            while (prev_start > 0 and self.input[prev_start - 1] != '\n') prev_start -= 1;
            const line = std.mem.trim(u8, self.input[prev_start..prev_end], " \t\r");
            if (line.len == 0) break;
            if (std.mem.endsWith(u8, line, "*/")) {
                if (std.mem.lastIndexOf(u8, self.input[0..prev_end], "/*")) |block_start| {
                    return try self.normalizeBlockComment(self.input[block_start + 2 .. prev_end - 2]);
                }
            }
            if (!std.mem.startsWith(u8, line, "//")) break;
            var text = line[2..];
            if (text.len != 0 and text[0] == ' ') text = text[1..];
            try lines.append(self.allocator, text);
            cursor = prev_start;
        }
        if (lines.items.len == 0) return null;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        var i = lines.items.len;
        while (i > 0) {
            i -= 1;
            try out.appendSlice(self.allocator, lines.items[i]);
            try out.append(self.allocator, '\n');
        }
        const owned = try out.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned);
        try self.file.owned_strings.append(self.allocator, owned);
        return owned;
    }

    fn leadingDetachedLineComments(self: *Parser, start: usize, output: *std.ArrayList([]const u8)) Error!void {
        var cursor = lineStart(self.input, start);
        // Skip the attached leading comment block first.
        while (previousLine(self.input, cursor)) |prev| {
            const line = std.mem.trim(u8, self.input[prev.start..prev.end], " \t\r");
            if (line.len == 0 or !std.mem.startsWith(u8, line, "//")) break;
            cursor = prev.start;
        }

        var paragraphs: std.ArrayList([]const u8) = .empty;
        defer paragraphs.deinit(self.allocator);
        while (true) {
            var saw_blank = false;
            while (previousLine(self.input, cursor)) |prev| {
                const line = std.mem.trim(u8, self.input[prev.start..prev.end], " \t\r");
                if (line.len != 0) break;
                saw_blank = true;
                cursor = prev.start;
            }
            if (!saw_blank) break;

            var lines: std.ArrayList([]const u8) = .empty;
            defer lines.deinit(self.allocator);
            while (previousLine(self.input, cursor)) |prev| {
                const line = std.mem.trim(u8, self.input[prev.start..prev.end], " \t\r");
                if (line.len == 0 or !std.mem.startsWith(u8, line, "//")) break;
                var text = line[2..];
                if (text.len != 0 and text[0] == ' ') text = text[1..];
                try lines.append(self.allocator, text);
                cursor = prev.start;
            }
            if (lines.items.len == 0) break;
            try paragraphs.append(self.allocator, try self.joinCommentLines(lines.items));
        }

        var i = paragraphs.items.len;
        while (i > 0) {
            i -= 1;
            try output.append(self.allocator, paragraphs.items[i]);
        }
    }

    fn joinCommentLines(self: *Parser, lines_reversed: []const []const u8) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        var i = lines_reversed.len;
        while (i > 0) {
            i -= 1;
            try out.appendSlice(self.allocator, lines_reversed[i]);
            try out.append(self.allocator, '\n');
        }
        const owned = try out.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned);
        try self.file.owned_strings.append(self.allocator, owned);
        return owned;
    }

    fn trailingLineComment(self: *Parser, end: usize) Error!?[]const u8 {
        var cursor = end;
        while (cursor < self.input.len and (self.input[cursor] == ' ' or self.input[cursor] == '\t' or self.input[cursor] == '\r')) cursor += 1;
        if (cursor + 1 >= self.input.len or self.input[cursor] != '/') return null;
        if (self.input[cursor + 1] == '*') {
            const block_start = cursor + 2;
            const block_end = std.mem.indexOf(u8, self.input[block_start..], "*/") orelse return null;
            return try self.normalizeBlockComment(self.input[block_start .. block_start + block_end]);
        }
        if (self.input[cursor + 1] != '/') return null;
        cursor += 2;
        if (cursor < self.input.len and self.input[cursor] == ' ') cursor += 1;
        const comment_start = cursor;
        while (cursor < self.input.len and self.input[cursor] != '\n') cursor += 1;
        const comment = std.mem.trim(u8, self.input[comment_start..cursor], "\r");
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        try out.appendSlice(self.allocator, comment);
        try out.append(self.allocator, '\n');
        const owned = try out.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned);
        try self.file.owned_strings.append(self.allocator, owned);
        return owned;
    }

    fn normalizeBlockComment(self: *Parser, raw: []const u8) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        var rest = raw;
        while (rest.len != 0) {
            const newline = std.mem.indexOfScalar(u8, rest, '\n');
            const raw_line = if (newline) |idx| rest[0..idx] else rest;
            var line = std.mem.trim(u8, raw_line, " \t\r");
            if (std.mem.startsWith(u8, line, "*")) {
                line = line[1..];
                if (line.len != 0 and line[0] == ' ') line = line[1..];
            }
            try out.appendSlice(self.allocator, line);
            try out.append(self.allocator, '\n');
            if (newline) |idx| {
                rest = rest[idx + 1 ..];
            } else break;
        }
        if (out.items.len == 0) try out.append(self.allocator, '\n');
        const owned = try out.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned);
        try self.file.owned_strings.append(self.allocator, owned);
        return owned;
    }

    fn lineStart(input: []const u8, index: usize) usize {
        var start = @min(index, input.len);
        while (start > 0 and input[start - 1] != '\n') start -= 1;
        return start;
    }

    fn previousLine(input: []const u8, cursor: usize) ?struct { start: usize, end: usize } {
        if (cursor == 0) return null;
        const end = cursor - 1;
        var start = end;
        while (start > 0 and input[start - 1] != '\n') start -= 1;
        return .{ .start = start, .end = end };
    }

    fn childPath(self: *Parser, base: []const i32, field_number: i32, index: i32) std.mem.Allocator.Error![]i32 {
        var path = try self.allocator.alloc(i32, base.len + 2);
        @memcpy(path[0..base.len], base);
        path[base.len] = field_number;
        path[base.len + 1] = index;
        return path;
    }

    fn addRepeatedLocations(self: *Parser, base: []const i32, field_number: i32, start_index: usize, end_index: usize, start: usize, end: usize) Error!void {
        var index = start_index;
        while (index < end_index) : (index += 1) {
            const path = try self.childPath(base, field_number, @intCast(index));
            defer self.allocator.free(path);
            try self.addSourceLocation(path, start, end);
        }
    }

    fn lineColumn(self: *const Parser, byte_index: usize) struct { line: i32, column: i32 } {
        var line: i32 = 0;
        var column: i32 = 0;
        var i: usize = 0;
        const end = @min(byte_index, self.input.len);
        while (i < end) : (i += 1) {
            if (self.input[i] == '\n') {
                line += 1;
                column = 0;
            } else {
                column += 1;
            }
        }
        return .{ .line = line, .column = column };
    }

    fn parseImport(self: *Parser) Error!void {
        var kind: schema.Import.Kind = .normal;
        if (self.matchIdent("public")) kind = .public else if (self.matchIdent("weak")) kind = .weak else if (self.matchIdent("option")) kind = .option;
        const path = try self.expectString();
        try self.expectSymbol(';');
        try self.file.imports.append(self.allocator, .{ .path = path, .kind = kind });
    }

    fn validateImports(self: *Parser) ParseError!void {
        if (@intFromEnum(self.file.edition) < @intFromEnum(schema.Edition.edition_2024)) return;
        for (self.file.imports.items) |import| {
            if (import.kind == .weak) return error.InvalidSyntax;
        }
    }

    fn parseMessageAfterKeyword(self: *Parser, source_path: []const i32, decl_start: usize, parent_scope: []const u8) Error!schema.MessageDescriptor {
        var message = schema.MessageDescriptor{ .name = try self.expectIdentifier() };
        errdefer message.deinit(self.allocator);
        const message_scope = try self.qualifiedName(parent_scope, message.name);
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.matchIdent("option")) {
                const option = try self.parseOptionAssignmentStatement();
                try message.options.append(self.allocator, option);
                try self.applyMessageOption(&message, option);
            } else if (self.matchIdent("message")) {
                const index: i32 = @intCast(message.messages.items.len);
                const path = try self.childPath(source_path, 3, index);
                defer self.allocator.free(path);
                const nested_start = self.previous_end;
                try message.messages.append(self.allocator, try self.parseMessageAfterKeyword(path, nested_start, message_scope));
            } else if (self.matchIdent("enum")) {
                const index: i32 = @intCast(message.enums.items.len);
                const path = try self.childPath(source_path, 4, index);
                defer self.allocator.free(path);
                const enum_start = self.previous_end;
                try message.enums.append(self.allocator, try self.parseEnumAfterKeyword(path, enum_start));
            } else if (self.matchIdent("oneof")) {
                const oneof_start = self.previous_end;
                const index: i32 = @intCast(message.oneofs.items.len);
                const path = try self.childPath(source_path, 8, index);
                defer self.allocator.free(path);
                try self.parseOneof(&message, source_path);
                try self.addSourceLocation(path, oneof_start, self.previousEnd());
            } else if (self.matchIdent("extensions")) {
                const range_start = self.previous_end;
                const start_index = message.extension_ranges.items.len;
                try self.parseExtensionRanges(&message.extension_ranges);
                try self.addRepeatedLocations(source_path, 5, start_index, message.extension_ranges.items.len, range_start, self.previousEnd());
            } else if (self.matchIdent("reserved")) {
                const reserved_start = self.previous_end;
                const range_start_index = message.reserved_ranges.items.len;
                const name_start_index = message.reserved_names.items.len;
                try self.parseReserved(&message.reserved_ranges, &message.reserved_names);
                try self.addRepeatedLocations(source_path, 9, range_start_index, message.reserved_ranges.items.len, reserved_start, self.previousEnd());
                try self.addRepeatedLocations(source_path, 10, name_start_index, message.reserved_names.items.len, reserved_start, self.previousEnd());
            } else if (self.matchIdent("extend")) {
                try self.parseExtend(&message.extensions, message_scope);
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else {
                const field_start = self.current.start;
                const index: i32 = @intCast(message.fields.items.len);
                try message.fields.append(self.allocator, try self.parseField(null, &message));
                const path = try self.childPath(source_path, 2, index);
                defer self.allocator.free(path);
                try self.addSourceLocation(path, field_start, self.previousEnd());
            }
        }
        try validateMessageFields(&message, self.file.syntax);
        try self.addSourceLocation(source_path, decl_start, self.previousEnd());
        return message;
    }

    fn parseEnumAfterKeyword(self: *Parser, source_path: []const i32, decl_start: usize) Error!schema.EnumDescriptor {
        var enumeration = schema.EnumDescriptor{ .name = try self.expectIdentifier() };
        errdefer enumeration.deinit(self.allocator);
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.matchIdent("option")) {
                const option = try self.parseOptionAssignmentStatement();
                try enumeration.options.append(self.allocator, option);
                try self.applyFeatureOption(&enumeration.features, option);
            } else if (self.matchIdent("reserved")) {
                const reserved_start = self.previous_end;
                const range_start_index = enumeration.reserved_ranges.items.len;
                const name_start_index = enumeration.reserved_names.items.len;
                try self.parseReserved(&enumeration.reserved_ranges, &enumeration.reserved_names);
                try self.addRepeatedLocations(source_path, 4, range_start_index, enumeration.reserved_ranges.items.len, reserved_start, self.previousEnd());
                try self.addRepeatedLocations(source_path, 5, name_start_index, enumeration.reserved_names.items.len, reserved_start, self.previousEnd());
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else {
                const value_start = self.current.start;
                const index: i32 = @intCast(enumeration.values.items.len);
                const name = try self.expectIdentifier();
                try self.expectSymbol('=');
                const number = try self.parseSignedInt32();
                var options: schema.OptionList = .empty;
                errdefer schema.deinitOptions(&options, self.allocator);
                if (self.consumeSymbol('[')) try self.parseOptionList(&options, ']');
                try self.expectSymbol(';');
                var enum_value = schema.EnumValueDescriptor{ .name = name, .number = number, .options = options };
                try self.applyEnumValueOptions(&enum_value);
                try enumeration.values.append(self.allocator, enum_value);
                options = .empty;
                const path = try self.childPath(source_path, 2, index);
                defer self.allocator.free(path);
                try self.addSourceLocation(path, value_start, self.previousEnd());
            }
        }
        try validateEnum(self.allocator, &enumeration, self.file.syntax);
        try self.addSourceLocation(source_path, decl_start, self.previousEnd());
        return enumeration;
    }

    fn parseServiceAfterKeyword(self: *Parser, source_path: []const i32, decl_start: usize) Error!schema.ServiceDescriptor {
        var service = schema.ServiceDescriptor{ .name = try self.expectIdentifier() };
        errdefer service.deinit(self.allocator);
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.matchIdent("option")) {
                const option = try self.parseOptionAssignmentStatement();
                try service.options.append(self.allocator, option);
                try self.applyFeatureOption(&service.features, option);
            } else if (self.matchIdent("rpc")) {
                const method_start = self.previous_end;
                const index: i32 = @intCast(service.methods.items.len);
                try service.methods.append(self.allocator, try self.parseRpcAfterKeyword());
                const path = try self.childPath(source_path, 2, index);
                defer self.allocator.free(path);
                try self.addSourceLocation(path, method_start, self.previousEnd());
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else return error.UnexpectedToken;
        }
        try self.addSourceLocation(source_path, decl_start, self.previousEnd());
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
                if (self.matchIdent("option")) {
                    const option = try self.parseOptionAssignmentStatement();
                    try method.options.append(self.allocator, option);
                    try self.applyFeatureOption(&method.features, option);
                } else if (self.consumeSymbol(';')) {} else return error.UnexpectedToken;
            }
            _ = self.consumeSymbol(';');
        } else try self.expectSymbol(';');
        return method;
    }

    fn parseOneof(self: *Parser, message: *schema.MessageDescriptor, message_path: []const i32) Error!void {
        const oneof_name = try self.expectIdentifier();
        try message.oneofs.append(self.allocator, .{ .name = oneof_name });
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.matchIdent("option")) {
                const option = try self.parseOptionAssignmentStatement();
                const oneof = &message.oneofs.items[message.oneofs.items.len - 1];
                try oneof.options.append(self.allocator, option);
                try self.applyFeatureOption(&oneof.features, option);
            } else if (self.consumeSymbol(';')) {
                // Empty declaration.
            } else {
                const field_start = self.current.start;
                const index: i32 = @intCast(message.fields.items.len);
                try message.fields.append(self.allocator, try self.parseField(oneof_name, message));
                const path = try self.childPath(message_path, 2, index);
                defer self.allocator.free(path);
                try self.addSourceLocation(path, field_start, self.previousEnd());
            }
        }
    }

    fn parseExtend(self: *Parser, output: *std.ArrayList(schema.FieldDescriptor), scope: []const u8) Error!void {
        const extendee = try self.parseTypeNameSlice();
        try self.expectSymbol('{');
        while (!self.consumeSymbol('}')) {
            if (self.current.tag == .eof) return error.UnexpectedEof;
            if (self.consumeSymbol(';')) continue;
            var field = try self.parseField(null, null);
            if (field.cardinality == .required) {
                field.deinit(self.allocator);
                return error.InvalidSyntax;
            }
            field.extendee = extendee;
            field.full_name = if (scope.len == 0) null else try self.qualifiedName(scope, field.name);
            try output.append(self.allocator, field);
        }
    }

    fn qualifiedName(self: *Parser, scope: []const u8, name: []const u8) std.mem.Allocator.Error![]const u8 {
        if (scope.len == 0 or std.mem.startsWith(u8, name, ".") or std.mem.indexOfScalar(u8, name, '.') != null) return name;
        const full_name = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ scope, name });
        errdefer self.allocator.free(full_name);
        try self.file.owned_strings.append(self.allocator, full_name);
        return full_name;
    }

    fn parseField(self: *Parser, oneof_name: ?[]const u8, parent: ?*schema.MessageDescriptor) Error!schema.FieldDescriptor {
        var cardinality: schema.Cardinality = .implicit;
        var proto3_optional = false;
        if (self.current.tag == .identifier) {
            if (std.mem.eql(u8, self.current.text, "optional")) {
                if (oneof_name != null) return error.InvalidSyntax;
                _ = try self.advance();
                cardinality = .optional;
                proto3_optional = self.file.syntax == .proto3;
            } else if (std.mem.eql(u8, self.current.text, "required")) {
                if (oneof_name != null) return error.InvalidSyntax;
                if (self.file.syntax != .proto2) return error.InvalidSyntax;
                _ = try self.advance();
                cardinality = .required;
            } else if (std.mem.eql(u8, self.current.text, "repeated")) {
                if (oneof_name != null) return error.InvalidSyntax;
                _ = try self.advance();
                cardinality = .repeated;
            }
        }

        if (self.matchIdent("group")) {
            if (oneof_name != null) return error.InvalidSyntax;
            if (self.file.syntax == .editions) return error.InvalidSyntax;
            if (self.file.syntax == .proto2 and cardinality == .implicit) return error.InvalidSyntax;
            return try self.parseGroupField(cardinality, oneof_name, parent);
        }

        const kind = try self.parseFieldKind();
        if (self.file.syntax == .proto2 and cardinality == .implicit and kind != .map and oneof_name == null) return error.InvalidSyntax;
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
        if (name.len == 0 or !std.ascii.isUpper(name[0])) return error.InvalidFieldType;
        const field_name = try self.lowercaseOwned(name);
        errdefer self.allocator.free(field_name);
        try self.expectSymbol('=');
        const number = try self.parseFieldNumber();
        var field = schema.FieldDescriptor{
            .name = field_name,
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

    fn lowercaseOwned(self: *Parser, name: []const u8) std.mem.Allocator.Error![]const u8 {
        const owned = try self.allocator.dupe(u8, name);
        for (owned) |*c| c.* = std.ascii.toLower(c.*);
        errdefer self.allocator.free(owned);
        try self.file.owned_strings.append(self.allocator, owned);
        return owned;
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
            if (std.mem.eql(u8, leaf, "json_name")) {
                field.json_name = switch (option.value) {
                    .string => |text| text,
                    else => return error.InvalidFieldType,
                };
            }
            if (std.mem.eql(u8, leaf, "packed")) {
                if (self.file.syntax == .editions) return error.InvalidSyntax;
                field.packed_override = schema.optionAsBool(option.value);
            }
            if (std.mem.eql(u8, leaf, "edition_defaults")) {
                const aggregate = switch (option.value) {
                    .aggregate => |text| text,
                    else => return error.InvalidFieldType,
                };
                try field.edition_defaults.append(self.allocator, try self.parseFieldEditionDefaultAggregate(aggregate));
            }
            if (std.mem.eql(u8, leaf, "feature_support")) {
                const aggregate = switch (option.value) {
                    .aggregate => |text| text,
                    else => return error.InvalidFieldType,
                };
                field.feature_support = try self.parseFeatureSupportAggregate(aggregate);
            }
            try self.applyFeatureOption(&field.features, option);
            if (std.mem.eql(u8, leaf, "repeated_field_encoding")) {
                if (schema.optionAsIdentifier(option.value)) |ident| {
                    if (std.ascii.eqlIgnoreCase(ident, "PACKED")) field.packed_override = true;
                    if (std.ascii.eqlIgnoreCase(ident, "EXPANDED")) field.packed_override = false;
                }
            }
        }
    }

    fn applyMessageOption(self: *Parser, message: *schema.MessageDescriptor, option: schema.FieldOption) Error!void {
        const leaf = optionLeaf(option.name);
        if (std.mem.eql(u8, leaf, "map_entry")) {
            return error.InvalidFieldType;
        }
        try self.applyFeatureOption(&message.features, option);
    }

    fn applyEnumValueOptions(self: *Parser, enum_value: *schema.EnumValueDescriptor) Error!void {
        for (enum_value.options.items) |option| {
            const leaf = optionLeaf(option.name);
            if (std.mem.eql(u8, leaf, "feature_support")) {
                const aggregate = switch (option.value) {
                    .aggregate => |text| text,
                    else => return error.InvalidFieldType,
                };
                enum_value.feature_support = try self.parseFeatureSupportAggregate(aggregate);
            }
            try self.applyFeatureOption(&enum_value.features, option);
        }
    }

    fn addFileOption(self: *Parser, option: schema.FieldOption) Error!void {
        if (isFeatureOption(option.name)) {
            try applyFeatureOptionValue(&self.file.features, option);
            try self.file.options.append(self.allocator, option);
        } else {
            try self.file.addOption(option);
        }
    }

    fn applyFeatureOption(self: *Parser, target: *?schema.FeatureSet, option: schema.FieldOption) Error!void {
        if (!isFeatureOption(option.name)) return;
        var features = target.* orelse schema.FeatureSet.defaults(self.file.syntax);
        try applyFeatureOptionValue(&features, option);
        target.* = features;
    }

    fn isFeatureOption(name: []const u8) bool {
        return std.mem.startsWith(u8, std.mem.trim(u8, name, " \t\r\n"), "features.");
    }

    fn applyFeatureOptionValue(features: *schema.FeatureSet, option: schema.FieldOption) ParseError!void {
        const leaf = optionLeaf(option.name);
        const ident = schema.optionAsIdentifier(option.value) orelse return error.InvalidFieldType;
        if (std.mem.eql(u8, leaf, "field_presence")) {
            if (std.ascii.eqlIgnoreCase(ident, "EXPLICIT")) features.field_presence = .explicit else if (std.ascii.eqlIgnoreCase(ident, "IMPLICIT")) features.field_presence = .implicit else if (std.ascii.eqlIgnoreCase(ident, "LEGACY_REQUIRED")) features.field_presence = .legacy_required else return error.InvalidFieldType;
        } else if (std.mem.eql(u8, leaf, "enum_type")) {
            if (std.ascii.eqlIgnoreCase(ident, "OPEN")) features.enum_type = .open else if (std.ascii.eqlIgnoreCase(ident, "CLOSED")) features.enum_type = .closed else return error.InvalidFieldType;
        } else if (std.mem.eql(u8, leaf, "repeated_field_encoding")) {
            if (std.ascii.eqlIgnoreCase(ident, "PACKED")) features.repeated_field_encoding = .packed_encoding else if (std.ascii.eqlIgnoreCase(ident, "EXPANDED")) features.repeated_field_encoding = .expanded else return error.InvalidFieldType;
        } else if (std.mem.eql(u8, leaf, "utf8_validation")) {
            if (std.ascii.eqlIgnoreCase(ident, "NONE")) features.utf8_validation = .none else if (std.ascii.eqlIgnoreCase(ident, "VERIFY")) features.utf8_validation = .verify else return error.InvalidFieldType;
        } else if (std.mem.eql(u8, leaf, "message_encoding")) {
            if (std.ascii.eqlIgnoreCase(ident, "LENGTH_PREFIXED")) features.message_encoding = .length_prefixed else if (std.ascii.eqlIgnoreCase(ident, "DELIMITED")) features.message_encoding = .delimited else return error.InvalidFieldType;
        } else if (std.mem.eql(u8, leaf, "json_format")) {
            if (std.ascii.eqlIgnoreCase(ident, "ALLOW")) features.json_format = .allow else if (std.ascii.eqlIgnoreCase(ident, "LEGACY_BEST_EFFORT")) features.json_format = .legacy_best_effort else return error.InvalidFieldType;
        } else if (std.mem.eql(u8, leaf, "enforce_naming_style")) {
            if (std.ascii.eqlIgnoreCase(ident, "STYLE2024")) features.enforce_naming_style = .style2024 else if (std.ascii.eqlIgnoreCase(ident, "STYLE_LEGACY")) features.enforce_naming_style = .style_legacy else if (std.ascii.eqlIgnoreCase(ident, "STYLE2026")) features.enforce_naming_style = .style2026 else return error.InvalidFieldType;
        } else if (std.mem.eql(u8, leaf, "default_symbol_visibility")) {
            if (std.ascii.eqlIgnoreCase(ident, "EXPORT_ALL")) features.default_symbol_visibility = .export_all else if (std.ascii.eqlIgnoreCase(ident, "EXPORT_TOP_LEVEL")) features.default_symbol_visibility = .export_top_level else if (std.ascii.eqlIgnoreCase(ident, "LOCAL_ALL")) features.default_symbol_visibility = .local_all else if (std.ascii.eqlIgnoreCase(ident, "STRICT")) features.default_symbol_visibility = .strict else return error.InvalidFieldType;
        } else if (std.mem.eql(u8, leaf, "enforce_proto_limits")) {
            if (std.ascii.eqlIgnoreCase(ident, "LEGACY_NO_EXPLICIT_LIMITS")) features.enforce_proto_limits = .legacy_no_explicit_limits else if (std.ascii.eqlIgnoreCase(ident, "PROTO_LIMITS2026")) features.enforce_proto_limits = .proto_limits2026 else return error.InvalidFieldType;
        } else return error.InvalidFieldType;
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
            if (self.current.tag == .identifier) {
                const ident = self.current.text;
                try self.advanceVoid();
                return .{ .float = try parseSpecialFloat(ident, negative) };
            }
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
            if (self.consumeSymbol('[')) {
                try self.parseOptionList(&range.options, ']');
                try self.applyExtensionRangeOptions(&range);
            }
            try ranges.append(self.allocator, range);
            if (!self.consumeSymbol(',')) break;
        }
        try self.expectSymbol(';');
    }

    fn applyExtensionRangeOptions(self: *Parser, range: *schema.ExtensionRange) Error!void {
        for (range.options.items) |option| {
            const leaf = optionLeaf(option.name);
            if (std.mem.eql(u8, leaf, "declaration")) {
                const aggregate = switch (option.value) {
                    .aggregate => |text| text,
                    else => return error.InvalidFieldType,
                };
                try range.declarations.append(self.allocator, try self.parseExtensionDeclarationAggregate(aggregate));
            } else if (std.mem.eql(u8, leaf, "verification")) {
                const value = schema.optionAsIdentifier(option.value) orelse return error.InvalidFieldType;
                if (std.ascii.eqlIgnoreCase(value, "DECLARATION")) {
                    range.verification = .declaration;
                } else if (std.ascii.eqlIgnoreCase(value, "UNVERIFIED")) {
                    range.verification = .unverified;
                } else return error.InvalidFieldType;
            } else if (std.mem.startsWith(u8, option.name, "features.")) {
                var features = range.features orelse schema.FeatureSet.defaults(self.file.syntax);
                features.applyOption(option.name, option.value);
                range.features = features;
            }
        }
    }

    fn parseExtensionDeclarationAggregate(self: *Parser, aggregate: []const u8) Error!schema.ExtensionDeclaration {
        var parser = try AggregateOptionParser.init(self.allocator, &self.file.owned_strings, aggregate);
        return try parser.parseExtensionDeclaration();
    }

    fn parseFieldEditionDefaultAggregate(self: *Parser, aggregate: []const u8) Error!schema.FieldEditionDefault {
        var parser = try AggregateOptionParser.init(self.allocator, &self.file.owned_strings, aggregate);
        return try parser.parseFieldEditionDefault();
    }

    fn parseFeatureSupportAggregate(self: *Parser, aggregate: []const u8) Error!schema.FeatureSupport {
        var parser = try AggregateOptionParser.init(self.allocator, &self.file.owned_strings, aggregate);
        return try parser.parseFeatureSupport();
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

    fn validateDefaults(self: *Parser) ParseError!void {
        for (self.file.messages.items) |*message| try self.validateMessageDefaults(message);
        for (self.file.extensions.items) |*field| try self.validateFieldDefault(field, null);
    }

    fn validateMessageDefaults(self: *Parser, message: *schema.MessageDescriptor) ParseError!void {
        for (message.fields.items) |*field| try self.validateFieldDefault(field, message);
        for (message.extensions.items) |*field| try self.validateFieldDefault(field, message);
        for (message.messages.items) |*nested| try self.validateMessageDefaults(nested);
    }

    fn validateFieldDefault(self: *Parser, field: *const schema.FieldDescriptor, context: ?*schema.MessageDescriptor) ParseError!void {
        const value = field.default_value orelse return;
        if (self.file.syntax == .proto3) return error.InvalidDefault;
        if (field.cardinality == .repeated or field.kind == .map or field.oneof_name != null) return error.InvalidDefault;
        switch (field.kind) {
            .scalar => |scalar| try validateScalarDefault(scalar, value),
            .enumeration => |name| {
                const number = switch (value) {
                    .integer => |v| v,
                    else => return error.InvalidDefault,
                };
                const enumeration = self.findEnumDescriptor(name, context) orelse return error.InvalidDefault;
                for (enumeration.values.items) |enum_value| {
                    if (enum_value.number == number) return;
                }
                return error.InvalidDefault;
            },
            .message, .group => return error.InvalidDefault,
            .map => return error.InvalidDefault,
        }
    }

    fn validatePackedOptions(self: *Parser) ParseError!void {
        for (self.file.messages.items) |*message| try self.validateMessagePackedOptions(message);
        for (self.file.extensions.items) |*field| try validateFieldPackedOption(field);
    }

    fn validateMessagePackedOptions(self: *Parser, message: *schema.MessageDescriptor) ParseError!void {
        for (message.fields.items) |*field| try validateFieldPackedOption(field);
        for (message.extensions.items) |*field| try validateFieldPackedOption(field);
        for (message.messages.items) |*nested| try self.validateMessagePackedOptions(nested);
    }

    fn validateFieldPackedOption(field: *const schema.FieldDescriptor) ParseError!void {
        if (field.packed_override != null and !field.isPackable()) return error.InvalidFieldType;
    }

    fn validateFieldOptionApplicabilities(self: *Parser) ParseError!void {
        for (self.file.extensions.items) |*field| try validateFieldOptionApplicability(field);
        for (self.file.messages.items) |*message| try self.validateMessageFieldOptionApplicabilities(message);
    }

    fn validateMessageFieldOptionApplicabilities(self: *Parser, message: *schema.MessageDescriptor) ParseError!void {
        for (message.fields.items) |*field| try validateFieldOptionApplicability(field);
        for (message.extensions.items) |*field| try validateFieldOptionApplicability(field);
        for (message.messages.items) |*nested| try self.validateMessageFieldOptionApplicabilities(nested);
    }

    fn validateFeatureSemantics(self: *Parser) ParseError!void {
        if (self.file.syntax != .editions) return;
        for (self.file.messages.items) |*message| try self.validateMessageFeatureSemantics(message);
        for (self.file.extensions.items) |*field| try self.validateFieldFeatureSemantics(field, null);
    }

    fn validateMessageFeatureSemantics(self: *Parser, message: *schema.MessageDescriptor) ParseError!void {
        for (message.fields.items) |*field| try self.validateFieldFeatureSemantics(field, message);
        for (message.extensions.items) |*field| try self.validateFieldFeatureSemantics(field, message);
        for (message.messages.items) |*nested| try self.validateMessageFeatureSemantics(nested);
    }

    fn validateFieldFeatureSemantics(self: *Parser, field: *const schema.FieldDescriptor, context: ?*schema.MessageDescriptor) ParseError!void {
        if (@intFromEnum(self.file.edition) >= @intFromEnum(schema.Edition.edition_2024)) {
            for (field.options.items) |option| {
                if (std.mem.eql(u8, optionLeaf(option.name), "ctype")) return error.InvalidFieldType;
            }
        }
        if (field.cardinality == .repeated or field.kind == .map or field.oneof_name != null or field.proto3_optional) return;
        if (field.kind == .message or field.kind == .group) return;
        const features = field.features orelse self.file.features;
        if (features.field_presence != .implicit) return;
        if (field.default_value != null) return error.InvalidDefault;
        if (field.kind == .enumeration) {
            const enumeration = self.findEnumDescriptor(field.kind.enumeration, context) orelse return;
            const enum_features = enumeration.features orelse self.file.features;
            if (enum_features.enum_type == .closed) return error.InvalidFieldType;
        }
    }

    fn validateFieldOptionApplicability(field: *const schema.FieldDescriptor) ParseError!void {
        for (field.options.items) |option| {
            const leaf = optionLeaf(option.name);
            if (std.mem.eql(u8, leaf, "jstype")) {
                const value = try parserOptionEnumNumber(option.value, .jstype);
                if (value != 0 and !fieldKindAllowsJSType(field.kind)) return error.InvalidFieldType;
            } else if (std.mem.eql(u8, leaf, "lazy") or std.mem.eql(u8, leaf, "unverified_lazy")) {
                if (schema.optionAsBool(option.value) orelse return error.InvalidFieldType) {
                    if (!fieldKindIsSubmessage(field.kind)) return error.InvalidFieldType;
                    if (std.mem.eql(u8, leaf, "unverified_lazy") and field.extendee != null) return error.InvalidFieldType;
                }
            }
        }
    }

    fn validateTypeSymbols(self: *Parser) ParseError!void {
        try validateFileTypeSymbols(&self.file);
        for (self.file.messages.items) |*message| try validateMessageTypeSymbols(message);
    }

    fn validateFileTypeSymbols(file: *const schema.FileDescriptor) ParseError!void {
        for (file.messages.items) |*message| {
            for (file.messages.items) |*other| {
                if (message == other) continue;
                if (std.mem.eql(u8, message.name, other.name)) return error.DuplicateSymbol;
            }
            for (file.enums.items) |*enumeration| {
                if (std.mem.eql(u8, message.name, enumeration.name)) return error.DuplicateSymbol;
            }
        }
        for (file.enums.items, 0..) |enumeration, i| {
            for (file.enums.items[i + 1 ..]) |other| {
                if (std.mem.eql(u8, enumeration.name, other.name)) return error.DuplicateSymbol;
            }
        }
        try validateFileEnumValueSymbols(file);
    }

    fn validateFileEnumValueSymbols(file: *const schema.FileDescriptor) ParseError!void {
        for (file.enums.items, 0..) |*enumeration, enum_index| {
            for (enumeration.values.items) |value| {
                for (file.messages.items) |message| {
                    if (std.mem.eql(u8, value.name, message.name)) return error.DuplicateSymbol;
                }
                for (file.enums.items) |other_enum| {
                    if (std.mem.eql(u8, value.name, other_enum.name)) return error.DuplicateSymbol;
                }
                for (file.services.items) |service| {
                    if (std.mem.eql(u8, value.name, service.name)) return error.DuplicateSymbol;
                }
                for (file.enums.items[enum_index + 1 ..]) |other_enum| {
                    for (other_enum.values.items) |other_value| {
                        if (std.mem.eql(u8, value.name, other_value.name)) return error.DuplicateSymbol;
                    }
                }
            }
        }
    }

    fn validateMessageTypeSymbols(message: *const schema.MessageDescriptor) ParseError!void {
        for (message.messages.items) |*nested| {
            for (message.messages.items) |*other| {
                if (nested == other) continue;
                if (std.mem.eql(u8, nested.name, other.name)) return error.DuplicateSymbol;
            }
            for (message.enums.items) |*enumeration| {
                if (std.mem.eql(u8, nested.name, enumeration.name)) return error.DuplicateSymbol;
            }
        }
        for (message.enums.items, 0..) |enumeration, i| {
            for (message.enums.items[i + 1 ..]) |other| {
                if (std.mem.eql(u8, enumeration.name, other.name)) return error.DuplicateSymbol;
            }
        }
        try validateMessageEnumValueSymbols(message);
        for (message.messages.items) |*nested| try validateMessageTypeSymbols(nested);
    }

    fn validateMessageEnumValueSymbols(message: *const schema.MessageDescriptor) ParseError!void {
        for (message.enums.items, 0..) |*enumeration, enum_index| {
            for (enumeration.values.items) |value| {
                for (message.fields.items) |field| {
                    if (std.mem.eql(u8, value.name, field.name)) return error.DuplicateSymbol;
                }
                for (message.oneofs.items) |oneof| {
                    if (std.mem.eql(u8, value.name, oneof.name)) return error.DuplicateSymbol;
                }
                for (message.messages.items) |nested| {
                    if (std.mem.eql(u8, value.name, nested.name)) return error.DuplicateSymbol;
                }
                for (message.enums.items) |other_enum| {
                    if (std.mem.eql(u8, value.name, other_enum.name)) return error.DuplicateSymbol;
                }
                for (message.extensions.items) |extension| {
                    if (std.mem.eql(u8, value.name, extension.name)) return error.DuplicateSymbol;
                }
                for (message.enums.items[enum_index + 1 ..]) |other_enum| {
                    for (other_enum.values.items) |other_value| {
                        if (std.mem.eql(u8, value.name, other_value.name)) return error.DuplicateSymbol;
                    }
                }
            }
        }
    }

    fn validateServices(self: *Parser) ParseError!void {
        for (self.file.services.items, 0..) |service, i| {
            for (self.file.services.items[i + 1 ..]) |other| {
                if (std.mem.eql(u8, service.name, other.name)) return error.DuplicateSymbol;
            }
            for (self.file.messages.items) |message| {
                if (std.mem.eql(u8, service.name, message.name)) return error.DuplicateSymbol;
            }
            for (self.file.enums.items) |enumeration| {
                if (std.mem.eql(u8, service.name, enumeration.name)) return error.DuplicateSymbol;
            }
            for (service.methods.items, 0..) |method, method_index| {
                for (service.methods.items[method_index + 1 ..]) |other| {
                    if (std.mem.eql(u8, method.name, other.name)) return error.DuplicateSymbol;
                }
                try self.validateRpcType(method.input_type);
                try self.validateRpcType(method.output_type);
            }
        }
    }

    fn validateRpcType(self: *Parser, type_name: []const u8) ParseError!void {
        if (self.file.findMessageDeep(type_name) != null) return;
        if (self.file.findEnumDeep(type_name) != null) return error.InvalidFieldType;
    }

    fn validateExtensions(self: *Parser) Error!void {
        for (self.file.extensions.items) |*field| try self.validateExtensionField(field);
        for (self.file.messages.items) |*message| try self.validateMessageExtensions(message);
        var extensions: std.ArrayList(*const schema.FieldDescriptor) = .empty;
        defer extensions.deinit(self.allocator);
        try self.collectExtensions(&extensions);
        for (extensions.items, 0..) |field, i| {
            for (extensions.items[i + 1 ..]) |other| {
                const field_extendee = field.extendee orelse "";
                const other_extendee = other.extendee orelse "";
                if (!std.mem.eql(u8, field_extendee, other_extendee)) continue;
                if (field.number == other.number or schema.extensionSymbolsEqual(self.file.package, field, other)) return error.DuplicateField;
            }
        }
        for (self.file.messages.items) |*message| try self.validateMessageExtensionDeclarations(message);
    }

    fn validateMessageExtensions(self: *Parser, message: *schema.MessageDescriptor) ParseError!void {
        for (message.extensions.items) |*field| try self.validateExtensionField(field);
        for (message.messages.items) |*nested| try self.validateMessageExtensions(nested);
    }

    fn collectExtensions(self: *Parser, output: *std.ArrayList(*const schema.FieldDescriptor)) std.mem.Allocator.Error!void {
        for (self.file.extensions.items) |*field| try output.append(self.allocator, field);
        for (self.file.messages.items) |*message| try collectMessageExtensions(self.allocator, message, output);
    }

    fn collectMessageExtensions(allocator: std.mem.Allocator, message: *schema.MessageDescriptor, output: *std.ArrayList(*const schema.FieldDescriptor)) std.mem.Allocator.Error!void {
        for (message.extensions.items) |*field| try output.append(allocator, field);
        for (message.messages.items) |*nested| try collectMessageExtensions(allocator, nested, output);
    }

    fn validateMessageExtensionDeclarations(self: *Parser, message: *const schema.MessageDescriptor) ParseError!void {
        for (message.extension_ranges.items) |range| try self.validateExtensionRangeDeclarations(range);
        try validateExtensionDeclarationNames(message.extension_ranges.items);
        for (message.messages.items) |*nested| try self.validateMessageExtensionDeclarations(nested);
    }

    fn validateExtensionRangeDeclarations(self: *Parser, range: schema.ExtensionRange) ParseError!void {
        _ = self;
        if (range.declarations.items.len != 0 and range.verification == .unverified) return error.InvalidFieldType;
        const end = range.end orelse std.math.maxInt(i64);
        for (range.declarations.items, 0..) |declaration, i| {
            if (declaration.number <= 0) return error.InvalidFieldType;
            if (declaration.number < range.start or declaration.number >= end) return error.ReservedField;
            try validateExtensionDeclarationShape(declaration);
            for (range.declarations.items[i + 1 ..]) |other| {
                if (declaration.number == other.number) return error.DuplicateField;
                if (declaration.full_name.len != 0 and other.full_name.len != 0 and std.mem.eql(u8, declaration.full_name, other.full_name)) return error.DuplicateField;
            }
        }
    }

    fn validateExtensionField(self: *Parser, field: *const schema.FieldDescriptor) ParseError!void {
        if (field.kind == .map) return error.InvalidFieldType;
        if (field.json_name != null) return error.InvalidFieldType;
        const extendee_name = field.extendee orelse return;
        if (self.file.findMessageDeep(extendee_name) == null and self.file.findEnumDeep(extendee_name) != null) return error.InvalidFieldType;
        const extendee = self.file.findMessageDeep(extendee_name) orelse return;
        for (extendee.extension_ranges.items) |range| {
            const end = range.end orelse std.math.maxInt(i64);
            if (field.number >= range.start and field.number < end) {
                try self.validateExtensionFieldDeclaration(field, range);
                return;
            }
        }
        return error.ReservedField;
    }

    fn validateExtensionFieldDeclaration(self: *Parser, field: *const schema.FieldDescriptor, range: schema.ExtensionRange) ParseError!void {
        var matching_declaration: ?schema.ExtensionDeclaration = null;
        for (range.declarations.items) |declaration| {
            if (declaration.number <= 0) return error.InvalidFieldType;
            const end = range.end orelse std.math.maxInt(i64);
            if (declaration.number < range.start or declaration.number >= end) return error.ReservedField;
            if (declaration.number == @as(i32, @intCast(field.number))) matching_declaration = declaration;
        }
        const declaration = matching_declaration orelse {
            if (range.verification == .declaration) return error.ReservedField;
            return;
        };
        if (declaration.reserved) return error.ReservedField;
        if (declaration.full_name.len != 0 and !schema.extensionDeclarationNameMatches(self.file.package, declaration.full_name, field)) return error.InvalidFieldType;
        if (declaration.repeated and field.cardinality != .repeated) return error.InvalidFieldType;
        if (!declaration.repeated and field.cardinality == .repeated) return error.InvalidFieldType;
        if (declaration.type_name.len != 0 and !extensionTypeMatches(self, field, declaration.type_name)) return error.InvalidFieldType;
    }

    fn validateMessageSets(self: *Parser) ParseError!void {
        for (self.file.messages.items) |*message| try self.validateMessageSetMessage(message);
    }

    fn validateMessageSetMessage(self: *Parser, message: *const schema.MessageDescriptor) ParseError!void {
        if (message.messageSetWireFormat()) {
            if (self.file.syntax == .proto3) return error.InvalidFieldType;
            if (message.fields.items.len != 0) return error.InvalidFieldType;
            var has_message_set_range = false;
            for (message.extension_ranges.items) |range| {
                const end = range.end orelse std.math.maxInt(i64);
                if (range.start <= 4 and end > 4) has_message_set_range = true;
            }
            if (!has_message_set_range) return error.InvalidRange;
        }
        for (self.file.extensions.items) |*field| try self.validateMessageSetExtension(message, field);
        for (self.file.messages.items) |*scope| try self.validateMessageSetExtensionsInMessage(message, scope);
        for (message.messages.items) |*nested| try self.validateMessageSetMessage(nested);
    }

    fn validateMessageSetExtensionsInMessage(self: *Parser, message_set: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) ParseError!void {
        for (scope.extensions.items) |*field| try self.validateMessageSetExtension(message_set, field);
        for (scope.messages.items) |*nested| try self.validateMessageSetExtensionsInMessage(message_set, nested);
    }

    fn validateMessageSetExtension(self: *Parser, message_set: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) ParseError!void {
        if (!message_set.messageSetWireFormat()) return;
        const extendee = field.extendee orelse return;
        const extendee_message = self.file.findMessageDeep(extendee) orelse return;
        if (extendee_message != message_set) return;
        if (field.cardinality == .repeated or field.cardinality == .required) return error.InvalidFieldType;
        switch (field.kind) {
            .message => {},
            else => return error.InvalidFieldType,
        }
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

const AggregateOptionParser = struct {
    allocator: std.mem.Allocator,
    owned_strings: *std.ArrayList([]u8),
    lexer: Lexer,
    current: Token,

    fn init(allocator: std.mem.Allocator, owned_strings: *std.ArrayList([]u8), input: []const u8) Error!AggregateOptionParser {
        var lexer = Lexer{ .input = input };
        const first = try lexer.next();
        return .{
            .allocator = allocator,
            .owned_strings = owned_strings,
            .lexer = lexer,
            .current = first,
        };
    }

    fn parseExtensionDeclaration(self: *AggregateOptionParser) Error!schema.ExtensionDeclaration {
        _ = self.consumeSymbol('{') or self.consumeSymbol('<');
        var declaration = schema.ExtensionDeclaration{};
        while (!self.consumeSymbol('}') and !self.consumeSymbol('>')) {
            if (self.current.tag == .eof) break;
            const name = try self.expectIdentifier();
            try self.expectSymbol(':');
            if (std.mem.eql(u8, name, "number")) {
                declaration.number = try self.parseSignedInt32();
            } else if (std.mem.eql(u8, name, "full_name")) {
                declaration.full_name = try self.expectString();
            } else if (std.mem.eql(u8, name, "type")) {
                declaration.type_name = try self.expectString();
            } else if (std.mem.eql(u8, name, "reserved")) {
                declaration.reserved = try self.expectBool();
            } else if (std.mem.eql(u8, name, "repeated")) {
                declaration.repeated = try self.expectBool();
            } else {
                try self.skipValue();
            }
            _ = self.consumeSymbol(',') or self.consumeSymbol(';');
        }
        return declaration;
    }

    fn parseFieldEditionDefault(self: *AggregateOptionParser) Error!schema.FieldEditionDefault {
        _ = self.consumeSymbol('{') or self.consumeSymbol('<');
        var edition_default = schema.FieldEditionDefault{};
        while (!self.consumeSymbol('}') and !self.consumeSymbol('>')) {
            if (self.current.tag == .eof) break;
            const name = try self.expectIdentifier();
            try self.expectSymbol(':');
            if (std.mem.eql(u8, name, "edition")) {
                edition_default.edition = try self.expectEdition();
            } else if (std.mem.eql(u8, name, "value")) {
                edition_default.value = try self.expectString();
            } else {
                try self.skipValue();
            }
            _ = self.consumeSymbol(',') or self.consumeSymbol(';');
        }
        return edition_default;
    }

    fn parseFeatureSupport(self: *AggregateOptionParser) Error!schema.FeatureSupport {
        _ = self.consumeSymbol('{') or self.consumeSymbol('<');
        var feature_support = schema.FeatureSupport{};
        while (!self.consumeSymbol('}') and !self.consumeSymbol('>')) {
            if (self.current.tag == .eof) break;
            const name = try self.expectIdentifier();
            try self.expectSymbol(':');
            if (std.mem.eql(u8, name, "edition_introduced")) {
                feature_support.edition_introduced = try self.expectEdition();
            } else if (std.mem.eql(u8, name, "edition_deprecated")) {
                feature_support.edition_deprecated = try self.expectEdition();
            } else if (std.mem.eql(u8, name, "deprecation_warning")) {
                feature_support.deprecation_warning = try self.expectString();
            } else if (std.mem.eql(u8, name, "edition_removed")) {
                feature_support.edition_removed = try self.expectEdition();
            } else if (std.mem.eql(u8, name, "removal_error")) {
                feature_support.removal_error = try self.expectString();
            } else {
                try self.skipValue();
            }
            _ = self.consumeSymbol(',') or self.consumeSymbol(';');
        }
        return feature_support;
    }

    fn skipValue(self: *AggregateOptionParser) Error!void {
        if (self.current.tag == .symbol and (self.current.symbol == '{' or self.current.symbol == '<')) {
            const open = self.current.symbol;
            const close: u8 = if (open == '{') '}' else '>';
            var depth: usize = 0;
            while (true) {
                if (self.current.tag == .eof) return error.UnexpectedEof;
                if (self.current.tag == .symbol and self.current.symbol == open) depth += 1;
                if (self.current.tag == .symbol and self.current.symbol == close) {
                    depth -= 1;
                    try self.advanceVoid();
                    if (depth == 0) return;
                    continue;
                }
                try self.advanceVoid();
            }
        }
        try self.advanceVoid();
    }

    fn expectEdition(self: *AggregateOptionParser) Error!schema.Edition {
        if (self.current.tag == .identifier) {
            const text = try self.expectIdentifier();
            return schema.Edition.fromProtoName(text) orelse error.InvalidEdition;
        }
        const number = try self.parseSignedInt32();
        return std.enums.fromInt(schema.Edition, number) orelse error.InvalidEdition;
    }

    fn expectIdentifier(self: *AggregateOptionParser) Error![]const u8 {
        if (self.current.tag != .identifier) return error.UnexpectedToken;
        const text = self.current.text;
        try self.advanceVoid();
        return text;
    }

    fn expectString(self: *AggregateOptionParser) Error![]const u8 {
        const decoded = try self.consumeStringLiteral();
        if (self.current.tag != .string_literal) return decoded;

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        try out.appendSlice(self.allocator, decoded);
        while (self.current.tag == .string_literal) {
            const part = try self.consumeStringLiteral();
            try out.appendSlice(self.allocator, part);
        }
        const joined = try out.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(joined);
        try self.owned_strings.append(self.allocator, joined);
        return joined;
    }

    fn consumeStringLiteral(self: *AggregateOptionParser) Error![]const u8 {
        if (self.current.tag != .string_literal) return error.UnexpectedToken;
        const decoded = try decodeStringLiteralAlloc(self.allocator, self.current.text);
        errdefer self.allocator.free(decoded);
        try self.advanceVoid();
        try self.owned_strings.append(self.allocator, decoded);
        return decoded;
    }

    fn expectBool(self: *AggregateOptionParser) Error!bool {
        const text = try self.expectIdentifier();
        if (std.ascii.eqlIgnoreCase(text, "true")) return true;
        if (std.ascii.eqlIgnoreCase(text, "false")) return false;
        return error.InvalidFieldType;
    }

    fn parseSignedInt32(self: *AggregateOptionParser) Error!i32 {
        const negative = self.consumeSymbol('-');
        _ = if (!negative) self.consumeSymbol('+') else false;
        if (self.current.tag != .number) return error.UnexpectedToken;
        var value = try parseI64(self.current.text);
        if (negative) value = -value;
        if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return error.InvalidNumber;
        try self.advanceVoid();
        return @intCast(value);
    }

    fn expectSymbol(self: *AggregateOptionParser, symbol: u8) Error!void {
        if (!self.consumeSymbol(symbol)) return error.UnexpectedToken;
    }

    fn consumeSymbol(self: *AggregateOptionParser, symbol: u8) bool {
        if (self.current.tag == .symbol and self.current.symbol == symbol) {
            self.advanceVoid() catch unreachable;
            return true;
        }
        return false;
    }

    fn advanceVoid(self: *AggregateOptionParser) ParseError!void {
        self.current = try self.lexer.next();
    }
};

fn validateEnum(allocator: std.mem.Allocator, enumeration: *const schema.EnumDescriptor, syntax: schema.Syntax) (ParseError || std.mem.Allocator.Error)!void {
    if (syntax == .proto3 and (enumeration.values.items.len == 0 or enumeration.values.items[0].number != 0)) return error.InvalidEnum;
    try validateEnumReserved(enumeration);
    const allow_alias = enumAllowsAlias(enumeration);
    for (enumeration.values.items, 0..) |value, i| {
        for (enumeration.values.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, value.name, other.name)) return error.DuplicateEnumValue;
            if (!allow_alias and value.number == other.number) return error.DuplicateEnumValue;
        }
    }
    try validateEnumValueCanonicalNames(allocator, enumeration);
}

fn validateEnumValueCanonicalNames(allocator: std.mem.Allocator, enumeration: *const schema.EnumDescriptor) (ParseError || std.mem.Allocator.Error)!void {
    for (enumeration.values.items, 0..) |value, i| {
        const key = try schema.enumValueCanonicalKey(allocator, enumeration.name, value.name);
        defer allocator.free(key);
        for (enumeration.values.items[i + 1 ..]) |other| {
            const other_key = try schema.enumValueCanonicalKey(allocator, enumeration.name, other.name);
            defer allocator.free(other_key);
            if (std.mem.eql(u8, key, other_key) and !std.mem.eql(u8, value.name, other.name) and value.number != other.number) return error.DuplicateEnumValue;
        }
    }
}

fn validateEnumReserved(enumeration: *const schema.EnumDescriptor) ParseError!void {
    for (enumeration.reserved_ranges.items, 0..) |range, i| {
        const end = range.end orelse std.math.maxInt(i64);
        if (range.start >= end) return error.InvalidRange;
        for (enumeration.reserved_ranges.items[i + 1 ..]) |other| {
            const other_end = other.end orelse std.math.maxInt(i64);
            if (other.start >= other_end) return error.InvalidRange;
            if (range.start < other_end and other.start < end) return error.InvalidRange;
        }
    }
    for (enumeration.reserved_names.items, 0..) |name, i| {
        for (enumeration.reserved_names.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, name, other)) return error.ReservedField;
        }
    }
    for (enumeration.values.items) |value| {
        for (enumeration.reserved_ranges.items) |range| {
            const end = range.end orelse std.math.maxInt(i64);
            if (value.number >= range.start and value.number < end) return error.ReservedField;
        }
        for (enumeration.reserved_names.items) |name| {
            if (std.mem.eql(u8, value.name, name)) return error.ReservedField;
        }
    }
}

fn enumAllowsAlias(enumeration: *const schema.EnumDescriptor) bool {
    for (enumeration.options.items) |option| {
        if (std.mem.eql(u8, option.name, "allow_alias")) return schema.optionAsBool(option.value) orelse false;
    }
    return false;
}

fn validateExtensionRanges(message: *const schema.MessageDescriptor, syntax: schema.Syntax) ParseError!void {
    if (syntax == .proto3 and message.extension_ranges.items.len != 0) return error.InvalidSyntax;
    for (message.extension_ranges.items, 0..) |range, i| {
        const end = range.end orelse std.math.maxInt(i64);
        if (range.start <= 0 or range.start >= end) return error.InvalidRange;
        for (message.extension_ranges.items[i + 1 ..]) |other| {
            const other_end = other.end orelse std.math.maxInt(i64);
            if (other.start <= 0 or other.start >= other_end) return error.InvalidRange;
            if (range.start < other_end and other.start < end) return error.InvalidRange;
        }
        for (message.reserved_ranges.items) |reserved| {
            const reserved_end = reserved.end orelse std.math.maxInt(i64);
            if (range.start < reserved_end and reserved.start < end) return error.InvalidRange;
        }
    }
}

fn validateReserved(message: *const schema.MessageDescriptor) ParseError!void {
    for (message.reserved_ranges.items, 0..) |range, i| {
        const end = range.end orelse std.math.maxInt(i64);
        if (range.start >= end) return error.InvalidRange;
        for (message.reserved_ranges.items[i + 1 ..]) |other| {
            const other_end = other.end orelse std.math.maxInt(i64);
            if (other.start >= other_end) return error.InvalidRange;
            if (range.start < other_end and other.start < end) return error.InvalidRange;
        }
    }
    for (message.reserved_names.items, 0..) |name, i| {
        for (message.reserved_names.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, name, other)) return error.ReservedField;
        }
    }
}

fn validateMessageFields(message: *const schema.MessageDescriptor, syntax: schema.Syntax) ParseError!void {
    try validateReserved(message);
    try validateExtensionRanges(message, syntax);
    try validateOneofs(message);
    try validateJsonNames(message);
    for (message.fields.items, 0..) |field, i| {
        for (message.fields.items[i + 1 ..]) |other| {
            if (field.number == other.number or std.mem.eql(u8, field.name, other.name)) return error.DuplicateField;
        }
        for (message.reserved_ranges.items) |range| {
            const end = range.end orelse std.math.maxInt(i64);
            if (field.number >= range.start and field.number < end) return error.ReservedField;
        }
        for (message.extension_ranges.items) |range| {
            const end = range.end orelse std.math.maxInt(i64);
            if (field.number >= range.start and field.number < end) return error.ReservedField;
        }
        for (message.reserved_names.items) |name| {
            if (std.mem.eql(u8, field.name, name)) return error.ReservedField;
        }
    }
}

fn validateJsonNames(message: *const schema.MessageDescriptor) ParseError!void {
    for (message.fields.items, 0..) |field, i| {
        if (field.json_name) |json_name| {
            if (std.mem.indexOfScalar(u8, json_name, 0) != null) return error.InvalidFieldType;
            if (schema.jsonNameLooksLikeExtension(json_name)) return error.InvalidFieldType;
        }
        for (message.fields.items[i + 1 ..]) |other| {
            if (schema.defaultJsonNamesEqual(field.name, other.name)) return error.DuplicateField;
            if (effectiveJsonNamesEqual(&field, &other)) return error.DuplicateField;
        }
    }
}

fn effectiveJsonNamesEqual(a: *const schema.FieldDescriptor, b: *const schema.FieldDescriptor) bool {
    if (a.json_name) |a_json| {
        if (b.json_name) |b_json| return std.mem.eql(u8, a_json, b_json);
        return schema.eqlDefaultJsonName(b.name, a_json);
    }
    if (b.json_name) |b_json| return schema.eqlDefaultJsonName(a.name, b_json);
    return schema.defaultJsonNamesEqual(a.name, b.name);
}

fn validateOneofs(message: *const schema.MessageDescriptor) ParseError!void {
    for (message.oneofs.items, 0..) |oneof, i| {
        var field_count: usize = 0;
        for (message.fields.items) |field| {
            if (field.oneof_name) |oneof_name| {
                if (std.mem.eql(u8, oneof.name, oneof_name)) field_count += 1;
            }
        }
        if (field_count == 0) return error.InvalidFieldType;
        for (message.oneofs.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, oneof.name, other.name)) return error.DuplicateOneof;
        }
        for (message.fields.items) |field| {
            if (std.mem.eql(u8, oneof.name, field.name)) return error.DuplicateOneof;
        }
    }
}

fn validateExtensionDeclarationNames(ranges: []const schema.ExtensionRange) ParseError!void {
    for (ranges, 0..) |range, range_index| {
        for (range.declarations.items) |declaration| {
            if (declaration.full_name.len == 0) continue;
            for (ranges[range_index + 1 ..]) |other_range| {
                for (other_range.declarations.items) |other| {
                    if (std.mem.eql(u8, declaration.full_name, other.full_name)) return error.DuplicateField;
                }
            }
        }
    }
}

fn validateExtensionDeclarationShape(declaration: schema.ExtensionDeclaration) ParseError!void {
    const has_full_name = declaration.full_name.len != 0;
    const has_type = declaration.type_name.len != 0;
    if (!has_full_name or !has_type) {
        if (has_full_name != has_type or !declaration.reserved) return error.InvalidFieldType;
        return;
    }
    if (!schema.declarationSymbolIsQualified(declaration.full_name)) return error.InvalidFieldType;
    if (!extensionDeclarationTypeNameValid(declaration.type_name)) return error.InvalidFieldType;
}

fn extensionDeclarationTypeNameValid(type_name: []const u8) bool {
    return schema.declarationTypeNameIsScalar(type_name) or schema.declarationSymbolIsQualified(type_name);
}

fn findEnumInMessage(message: *const schema.MessageDescriptor, leaf: []const u8) ?*const schema.EnumDescriptor {
    if (message.findEnum(leaf)) |enumeration| return enumeration;
    for (message.messages.items) |*nested| if (findEnumInMessage(nested, leaf)) |found| return found;
    return null;
}

fn extensionTypeMatches(parser: *Parser, field: *const schema.FieldDescriptor, declared_type: []const u8) bool {
    _ = parser;
    return switch (field.kind) {
        .message, .enumeration, .group => |type_name| nameMatchesType(declared_type, type_name),
        .scalar => |scalar| std.mem.eql(u8, schema.scalarTypeName(scalar), declared_type),
        .map => false,
    };
}

fn nameMatchesType(a: []const u8, b: []const u8) bool {
    const an = stripLeadingDot(a);
    const bn = stripLeadingDot(b);
    if (std.mem.eql(u8, an, bn)) return true;
    const a_leaf = if (std.mem.lastIndexOfScalar(u8, an, '.')) |idx| an[idx + 1 ..] else an;
    const b_leaf = if (std.mem.lastIndexOfScalar(u8, bn, '.')) |idx| bn[idx + 1 ..] else bn;
    return std.mem.eql(u8, a_leaf, b_leaf);
}

fn stripLeadingDot(name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
}

fn optionLeaf(name: []const u8) []const u8 {
    return schema.optionLeaf(name);
}

fn messageContainsEnum(message: *const schema.MessageDescriptor, leaf: []const u8) bool {
    if (message.findEnum(leaf) != null) return true;
    for (message.messages.items) |*nested| if (messageContainsEnum(nested, leaf)) return true;
    return false;
}

fn validateScalarDefault(scalar: schema.ScalarType, value: schema.OptionValue) ParseError!void {
    switch (scalar) {
        .double, .float => {
            if (optionFloat(value) == null) return error.InvalidDefault;
        },
        .int32, .sint32, .sfixed32 => {
            _ = optionInt(i32, value) orelse return error.InvalidDefault;
        },
        .int64, .sint64, .sfixed64 => {
            _ = optionInt(i64, value) orelse return error.InvalidDefault;
        },
        .uint32, .fixed32 => {
            _ = optionInt(u32, value) orelse return error.InvalidDefault;
        },
        .uint64, .fixed64 => {
            _ = optionInt(u64, value) orelse return error.InvalidDefault;
        },
        .bool => {
            if (schema.optionAsBool(value) == null) return error.InvalidDefault;
        },
        .string, .bytes => switch (value) {
            .string => {},
            else => return error.InvalidDefault,
        },
    }
}

const ParserOptionEnum = enum { jstype };

fn parserOptionEnumNumber(value: schema.OptionValue, kind: ParserOptionEnum) ParseError!i32 {
    switch (value) {
        .integer => |v| {
            if (v < std.math.minInt(i32) or v > std.math.maxInt(i32)) return error.InvalidFieldType;
            const number: i32 = @intCast(v);
            return if (parserOptionEnumNumberKnown(number, kind)) number else error.InvalidFieldType;
        },
        .identifier, .string => |text| {
            if (kind == .jstype) {
                if (std.mem.eql(u8, text, "JS_NORMAL")) return 0;
                if (std.mem.eql(u8, text, "JS_STRING")) return 1;
                if (std.mem.eql(u8, text, "JS_NUMBER")) return 2;
            }
            return error.InvalidFieldType;
        },
        else => return error.InvalidFieldType,
    }
}

fn parserOptionEnumNumberKnown(number: i32, kind: ParserOptionEnum) bool {
    return switch (kind) {
        .jstype => number >= 0 and number <= 2,
    };
}

fn fieldKindAllowsJSType(kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .int64, .uint64, .sint64, .fixed64, .sfixed64 => true,
            else => false,
        },
        else => false,
    };
}

fn fieldKindIsSubmessage(kind: schema.FieldKind) bool {
    return switch (kind) {
        .message, .group => true,
        else => false,
    };
}

fn optionInt(comptime T: type, value: schema.OptionValue) ?T {
    return switch (value) {
        .integer => |v| if (v >= std.math.minInt(T) and v <= std.math.maxInt(T)) @intCast(v) else null,
        .identifier, .string => |text| std.fmt.parseInt(T, text, 10) catch null,
        else => null,
    };
}

fn optionFloat(value: schema.OptionValue) ?f64 {
    return switch (value) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        .identifier, .string => |text| parseSpecialFloat(text, false) catch (std.fmt.parseFloat(f64, text) catch null),
        else => null,
    };
}

fn parseSpecialFloat(text: []const u8, negative: bool) ParseError!f64 {
    if (std.ascii.eqlIgnoreCase(text, "inf") or std.ascii.eqlIgnoreCase(text, "infinity")) {
        const value = std.math.inf(f64);
        return if (negative) -value else value;
    }
    if (std.ascii.eqlIgnoreCase(text, "nan")) {
        if (negative) return error.InvalidNumber;
        return std.math.nan(f64);
    }
    return error.InvalidNumber;
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

test "parser rejects weak imports under edition 2024 and beyond" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSyntax, Parser.parse(allocator,
        \\edition = "2024";
        \\import weak "dep.proto";
        \\message Bad {}
    ));
}

test "parser records basic source code info locations" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Person { optional string name = 1; message Child { optional int32 id = 1; } oneof pick { string nick = 2; } extensions 100 to 199; reserved 50 to 60; reserved "old"; }
        \\enum Kind { A = 0; reserved 5 to 6; reserved "OLD"; }
        \\service Api { rpc Get (Person) returns (Person); }
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    try std.testing.expect(file.source_code_info.locations.items.len >= 6);
    try expectLocationPath(&file, &.{12});
    try expectLocationPath(&file, &.{2});
    try expectLocationPath(&file, &.{ 3, 0 });
    try expectLocationPath(&file, &.{ 4, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 2, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 3, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 3, 0, 2, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 8, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 2, 1 });
    try expectLocationPath(&file, &.{ 4, 0, 5, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 9, 0 });
    try expectLocationPath(&file, &.{ 4, 0, 10, 0 });
    try expectLocationPath(&file, &.{ 5, 0 });
    try expectLocationPath(&file, &.{ 5, 0, 2, 0 });
    try expectLocationPath(&file, &.{ 5, 0, 4, 0 });
    try expectLocationPath(&file, &.{ 5, 0, 5, 0 });
    try expectLocationPath(&file, &.{ 6, 0 });
    try expectLocationPath(&file, &.{ 6, 0, 2, 0 });
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

test "parser accepts special float defaults" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Defaults {
        \\  optional double pos = 1 [default = inf];
        \\  optional double neg = 2 [default = -inf];
        \\  optional float quiet = 3 [default = nan];
        \\  optional float plus = 4 [default = +inf];
        \\}
    ;
    var file = try Parser.parse(allocator, source);
    defer file.deinit();
    const msg = file.findMessage("Defaults").?;
    try std.testing.expectEqualStrings("inf", msg.findField("pos").?.default_value.?.identifier);
    try std.testing.expect(std.math.isNegativeInf(msg.findField("neg").?.default_value.?.float));
    try std.testing.expectEqualStrings("nan", msg.findField("quiet").?.default_value.?.identifier);
    try std.testing.expect(std.math.isPositiveInf(msg.findField("plus").?.default_value.?.float));
    try std.testing.expectError(error.InvalidNumber, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional float value = 1 [default = -nan]; }
    ));
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
        \\message Host { extensions 100 to 200; }
        \\message Ext {}
        \\extend Host { optional Ext ext = 100 [unverified_lazy = true]; }
    ));
    var file = try Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child {}
        \\message Ok {
        \\  optional Child child = 1 [lazy = true, unverified_lazy = true];
        \\  optional int64 big = 2 [jstype = JS_STRING];
        \\}
    );
    defer file.deinit();
    try std.testing.expectEqual(@as(usize, 2), file.findMessage("Ok").?.findField("child").?.options.items.len);
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
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional int32 foo_bar = 1; optional int32 fooBar = 2; }
    ));
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 foo = 1 [json_name = "sameName"];
        \\  optional int32 bar = 2 [json_name = "sameName"];
        \\}
    ));
    try std.testing.expectError(error.DuplicateField, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad {
        \\  optional int32 foo = 1 [json_name = "barBaz"];
        \\  optional int32 bar_baz = 2;
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
        \\message Target { extensions 100 to 200; }
        \\extend Target { optional int32 ext = 150 [json_name = "customExt"]; }
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
    try std.testing.expectError(error.DuplicateEnumValue, Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum MyEnum { MY_ENUM_FOO = 1; FOO = 2; }
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
    try std.testing.expectError(error.UnexpectedToken, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { reserved max; }
    ));
    try std.testing.expectError(error.UnexpectedToken, Parser.parse(allocator,
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
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" repeated: true },
        \\    verification = DECLARATION,
        \\    features.repeated_field_encoding = PACKED
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
        \\edition = "2023";
        \\option features.json_format = LEGACY_BEST_EFFORT;
        \\message M {
        \\  option features.message_encoding = DELIMITED;
        \\  repeated int32 values = 1 [features.repeated_field_encoding = EXPANDED];
        \\  oneof pick {
        \\    option features.field_presence = EXPLICIT;
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
        \\    option features.enforce_proto_limits = PROTO_LIMITS2026;
        \\  }
        \\}
    );
    defer file.deinit();

    try std.testing.expectEqual(schema.FeatureSet.JsonFormat.legacy_best_effort, file.features.json_format);
    const message = file.findMessage("M").?;
    try std.testing.expectEqual(schema.FeatureSet.MessageEncoding.delimited, message.features.?.message_encoding);
    const field = message.findField("values").?;
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, field.features.?.repeated_field_encoding);
    try std.testing.expect(!field.resolvedPacked(&file));
    try std.testing.expectEqual(schema.FeatureSet.FieldPresence.explicit, message.oneofs.items[0].features.?.field_presence);
    const enumeration = file.findEnum("E").?;
    try std.testing.expectEqual(schema.FeatureSet.EnumType.closed, enumeration.features.?.enum_type);
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2026, enumeration.values.items[0].features.?.enforce_naming_style);
    try std.testing.expectEqual(schema.Edition.edition_2026, enumeration.values.items[0].feature_support.?.edition_removed.?);
    try std.testing.expectEqualStrings("removed enum value", enumeration.values.items[0].feature_support.?.removal_error);
    const service = file.services.items[0];
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2024, service.features.?.enforce_naming_style);
    try std.testing.expectEqual(schema.FeatureSet.EnforceProtoLimits.proto_limits2026, service.methods.items[0].features.?.enforce_proto_limits);
}

test "parser rejects invalid feature option names and values" {
    const allocator = std.testing.allocator;
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
    try std.testing.expectError(error.InvalidRange, Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { option message_set_wire_format = true; extensions 5 to max; }
    ));
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
