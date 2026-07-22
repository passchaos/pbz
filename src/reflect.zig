const std = @import("std");
const schema = @import("schema.zig");
const parser = @import("parser.zig");
const registry_mod = @import("registry.zig");
const dynamic = @import("dynamic.zig");
const wire = @import("wire.zig");

pub const Error = dynamic.DecodeError || dynamic.ValidationError || error{ UnknownFile, UnknownMessage, UnknownEnum, UnknownService, UnknownField, MissingField, InvalidEnumValue };

const ValueTag = std.meta.Tag(dynamic.Value);
const DefaultTag = std.meta.Tag(dynamic.DefaultValue);

pub const Reflection = struct {
    allocator: std.mem.Allocator,
    registry: *const registry_mod.Registry,

    pub fn init(allocator: std.mem.Allocator, registry: *const registry_mod.Registry) Reflection {
        return .{ .allocator = allocator, .registry = registry };
    }

    pub fn file(self: Reflection, path: []const u8) Error!*const schema.FileDescriptor {
        return self.registry.findFile(path) orelse error.UnknownFile;
    }

    pub fn fileName(_: Reflection, file_descriptor: *const schema.FileDescriptor) []const u8 {
        return file_descriptor.name;
    }

    pub fn filePackage(_: Reflection, file_descriptor: *const schema.FileDescriptor) []const u8 {
        return file_descriptor.package;
    }

    pub fn fileSyntax(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.Syntax {
        return file_descriptor.syntax;
    }

    pub fn fileEdition(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.Edition {
        return file_descriptor.edition;
    }

    pub fn fileFeatures(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet {
        return file_descriptor.features;
    }

    pub fn fileFieldPresence(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.FieldPresence {
        return file_descriptor.features.field_presence;
    }

    pub fn fileEnumType(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.EnumType {
        return file_descriptor.features.enum_type;
    }

    pub fn fileRepeatedFieldEncoding(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.RepeatedFieldEncoding {
        return file_descriptor.features.repeated_field_encoding;
    }

    pub fn fileUtf8Validation(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.Utf8Validation {
        return file_descriptor.features.utf8_validation;
    }

    pub fn fileMessageEncoding(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.MessageEncoding {
        return file_descriptor.features.message_encoding;
    }

    pub fn fileJsonFormat(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.JsonFormat {
        return file_descriptor.features.json_format;
    }

    pub fn fileOptimizeFor(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?schema.FileOptimizeMode {
        return file_descriptor.optimizeFor();
    }

    pub fn fileJavaPackage(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "java_package");
    }

    pub fn fileJavaOuterClassname(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "java_outer_classname");
    }

    pub fn fileGoPackage(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "go_package");
    }

    pub fn fileJavaMultipleFiles(_: Reflection, file_descriptor: *const schema.FileDescriptor) bool {
        return schema.optionBool(file_descriptor.options.items, "java_multiple_files") orelse false;
    }

    pub fn fileJavaStringCheckUtf8(_: Reflection, file_descriptor: *const schema.FileDescriptor) bool {
        return schema.optionBool(file_descriptor.options.items, "java_string_check_utf8") orelse false;
    }

    pub fn fileJavaGenerateEqualsAndHash(_: Reflection, file_descriptor: *const schema.FileDescriptor) bool {
        return schema.optionBool(file_descriptor.options.items, "java_generate_equals_and_hash") orelse false;
    }

    pub fn fileCcEnableArenas(_: Reflection, file_descriptor: *const schema.FileDescriptor) bool {
        return schema.optionBool(file_descriptor.options.items, "cc_enable_arenas") orelse false;
    }

    pub fn fileObjcClassPrefix(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "objc_class_prefix");
    }

    pub fn fileCsharpNamespace(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "csharp_namespace");
    }

    pub fn fileSwiftPrefix(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "swift_prefix");
    }

    pub fn filePhpClassPrefix(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "php_class_prefix");
    }

    pub fn filePhpNamespace(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "php_namespace");
    }

    pub fn filePhpMetadataNamespace(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "php_metadata_namespace");
    }

    pub fn fileRubyPackage(_: Reflection, file_descriptor: *const schema.FileDescriptor) ?[]const u8 {
        return schema.optionString(file_descriptor.options.items, "ruby_package");
    }

    pub fn fileCcGenericServices(_: Reflection, file_descriptor: *const schema.FileDescriptor) bool {
        return schema.optionBool(file_descriptor.options.items, "cc_generic_services") orelse false;
    }

    pub fn fileJavaGenericServices(_: Reflection, file_descriptor: *const schema.FileDescriptor) bool {
        return schema.optionBool(file_descriptor.options.items, "java_generic_services") orelse false;
    }

    pub fn filePyGenericServices(_: Reflection, file_descriptor: *const schema.FileDescriptor) bool {
        return schema.optionBool(file_descriptor.options.items, "py_generic_services") orelse false;
    }

    pub fn fileEnforceNamingStyle(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.EnforceNamingStyle {
        return file_descriptor.features.enforce_naming_style;
    }

    pub fn fileDefaultSymbolVisibility(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.DefaultSymbolVisibility {
        return file_descriptor.features.default_symbol_visibility;
    }

    pub fn fileEnforceProtoLimits(_: Reflection, file_descriptor: *const schema.FileDescriptor) schema.FeatureSet.EnforceProtoLimits {
        return file_descriptor.features.enforce_proto_limits;
    }

    pub fn fileOptions(_: Reflection, file_descriptor: *const schema.FileDescriptor) []const schema.FieldOption {
        return file_descriptor.options.items;
    }

    pub fn fileIsPlaceholder(_: Reflection, _: *const schema.FileDescriptor) bool {
        return false;
    }

    pub fn sourceLocation(_: Reflection, file_descriptor: *const schema.FileDescriptor, path: []const i32) Error!*const schema.SourceCodeInfo.Location {
        return file_descriptor.source_code_info.location(path) orelse error.UnknownField;
    }

    pub fn sourceLocationExists(_: Reflection, file_descriptor: *const schema.FileDescriptor, path: []const i32) bool {
        return file_descriptor.source_code_info.location(path) != null;
    }

    pub fn sourceLocationCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return file_descriptor.source_code_info.locations.items.len;
    }

    pub fn sourceLocationAt(_: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.SourceCodeInfo.Location {
        if (index >= file_descriptor.source_code_info.locations.items.len) return error.UnknownField;
        return &file_descriptor.source_code_info.locations.items[index];
    }

    pub fn sourceLocationIndex(_: Reflection, file_descriptor: *const schema.FileDescriptor, location: *const schema.SourceCodeInfo.Location) Error!usize {
        for (file_descriptor.source_code_info.locations.items, 0..) |*candidate, index| {
            if (candidate == location) return index;
        }
        return error.UnknownField;
    }

    pub fn sourceLocationPath(_: Reflection, location: *const schema.SourceCodeInfo.Location) []const i32 {
        return location.path.items;
    }

    pub fn sourceLocationPathCount(_: Reflection, location: *const schema.SourceCodeInfo.Location) usize {
        return location.path.items.len;
    }

    pub fn sourceLocationPathAt(_: Reflection, location: *const schema.SourceCodeInfo.Location, index: usize) Error!i32 {
        if (index >= location.path.items.len) return error.UnknownField;
        return location.path.items[index];
    }

    pub fn sourceLocationPathIndex(_: Reflection, location: *const schema.SourceCodeInfo.Location, value: i32) Error!usize {
        for (location.path.items, 0..) |candidate, index| {
            if (candidate == value) return index;
        }
        return error.UnknownField;
    }

    pub fn sourceLocationSpan(_: Reflection, location: *const schema.SourceCodeInfo.Location) []const i32 {
        return location.span.items;
    }

    pub fn sourceLocationSpanCount(_: Reflection, location: *const schema.SourceCodeInfo.Location) usize {
        return location.span.items.len;
    }

    pub fn sourceLocationSpanAt(_: Reflection, location: *const schema.SourceCodeInfo.Location, index: usize) Error!i32 {
        if (index >= location.span.items.len) return error.UnknownField;
        return location.span.items[index];
    }

    pub fn sourceLocationSpanIndex(_: Reflection, location: *const schema.SourceCodeInfo.Location, value: i32) Error!usize {
        for (location.span.items, 0..) |candidate, index| {
            if (candidate == value) return index;
        }
        return error.UnknownField;
    }

    pub fn sourceLocationLeadingComments(_: Reflection, location: *const schema.SourceCodeInfo.Location) ?[]const u8 {
        return location.leading_comments;
    }

    pub fn sourceLocationTrailingComments(_: Reflection, location: *const schema.SourceCodeInfo.Location) ?[]const u8 {
        return location.trailing_comments;
    }

    pub fn sourceLocationLeadingDetachedCommentCount(_: Reflection, location: *const schema.SourceCodeInfo.Location) usize {
        return location.leading_detached_comments.items.len;
    }

    pub fn sourceLocationLeadingDetachedCommentAt(_: Reflection, location: *const schema.SourceCodeInfo.Location, index: usize) Error![]const u8 {
        if (index >= location.leading_detached_comments.items.len) return error.UnknownField;
        return location.leading_detached_comments.items[index];
    }

    pub fn sourceLocationLeadingDetachedCommentIndex(_: Reflection, location: *const schema.SourceCodeInfo.Location, comment: []const u8) Error!usize {
        for (location.leading_detached_comments.items, 0..) |candidate, index| {
            if (std.mem.eql(u8, candidate, comment)) return index;
        }
        return error.UnknownField;
    }

    pub fn generatedAnnotation(_: Reflection, generated_code_info: *const schema.GeneratedCodeInfo, path: []const i32) Error!*const schema.GeneratedCodeInfo.Annotation {
        return generated_code_info.annotation(path) orelse error.UnknownField;
    }

    pub fn generatedAnnotationExists(_: Reflection, generated_code_info: *const schema.GeneratedCodeInfo, path: []const i32) bool {
        return generated_code_info.annotation(path) != null;
    }

    pub fn generatedAnnotationCount(_: Reflection, generated_code_info: *const schema.GeneratedCodeInfo) usize {
        return generated_code_info.annotations.items.len;
    }

    pub fn generatedAnnotationAt(_: Reflection, generated_code_info: *const schema.GeneratedCodeInfo, index: usize) Error!*const schema.GeneratedCodeInfo.Annotation {
        if (index >= generated_code_info.annotations.items.len) return error.UnknownField;
        return &generated_code_info.annotations.items[index];
    }

    pub fn generatedAnnotationIndex(_: Reflection, generated_code_info: *const schema.GeneratedCodeInfo, annotation: *const schema.GeneratedCodeInfo.Annotation) Error!usize {
        for (generated_code_info.annotations.items, 0..) |*candidate, index| {
            if (candidate == annotation) return index;
        }
        return error.UnknownField;
    }

    pub fn generatedAnnotationPath(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) []const i32 {
        return annotation.path.items;
    }

    pub fn generatedAnnotationHasSourceFile(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) bool {
        return annotation.source_file != null;
    }

    pub fn generatedAnnotationSourceFile(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) Error![]const u8 {
        return annotation.source_file orelse error.MissingField;
    }

    pub fn generatedAnnotationHasBegin(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) bool {
        return annotation.begin != null;
    }

    pub fn generatedAnnotationBegin(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) Error!i32 {
        return annotation.begin orelse error.MissingField;
    }

    pub fn generatedAnnotationHasEnd(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) bool {
        return annotation.end != null;
    }

    pub fn generatedAnnotationEnd(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) Error!i32 {
        return annotation.end orelse error.MissingField;
    }

    pub fn generatedAnnotationHasSemantic(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) bool {
        return annotation.semantic != null;
    }

    pub fn generatedAnnotationSemantic(_: Reflection, annotation: *const schema.GeneratedCodeInfo.Annotation) Error!schema.GeneratedCodeInfo.Semantic {
        return annotation.semantic orelse error.MissingField;
    }

    pub fn fileImport(_: Reflection, file_descriptor: *const schema.FileDescriptor, path: []const u8) Error!schema.Import {
        return file_descriptor.findImport(path) orelse error.UnknownFile;
    }

    pub fn importPath(_: Reflection, import: schema.Import) []const u8 {
        return import.path;
    }

    pub fn importKind(_: Reflection, import: schema.Import) schema.Import.Kind {
        return import.kind;
    }

    pub fn importIsPublic(_: Reflection, import: schema.Import) bool {
        return import.kind == .public;
    }

    pub fn importIsWeak(_: Reflection, import: schema.Import) bool {
        return import.kind == .weak;
    }

    pub fn importIsOption(_: Reflection, import: schema.Import) bool {
        return import.kind == .option;
    }

    pub fn fileHasMissingWeakImport(_: Reflection, file_descriptor: *const schema.FileDescriptor, path: []const u8) bool {
        return file_descriptor.hasMissingWeakImport(path);
    }

    pub fn fileMissingWeakImportCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return file_descriptor.missing_weak_imports.items.len;
    }

    pub fn fileMissingWeakImportAt(_: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error![]const u8 {
        if (index >= file_descriptor.missing_weak_imports.items.len) return error.UnknownFile;
        return file_descriptor.missing_weak_imports.items[index];
    }

    pub fn fileMissingWeakImportIndex(_: Reflection, file_descriptor: *const schema.FileDescriptor, path: []const u8) Error!usize {
        for (file_descriptor.missing_weak_imports.items, 0..) |missing, index| {
            if (std.mem.eql(u8, missing, path)) return index;
        }
        return error.UnknownFile;
    }

    pub fn fileImportCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return file_descriptor.importCount();
    }

    pub fn fileImportAt(_: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!schema.Import {
        return file_descriptor.importAt(index) orelse error.UnknownFile;
    }

    pub fn fileImportIndex(_: Reflection, file_descriptor: *const schema.FileDescriptor, path: []const u8) Error!usize {
        for (file_descriptor.imports.items, 0..) |import, index| {
            if (std.mem.eql(u8, import.path, path)) return index;
        }
        return error.UnknownFile;
    }

    pub fn fileDependencyCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return file_descriptor.imports.items.len;
    }

    pub fn fileDependency(self: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.FileDescriptor {
        if (index >= file_descriptor.imports.items.len) return error.UnknownFile;
        return try self.file(file_descriptor.imports.items[index].path);
    }

    pub fn fileDependencyIndex(self: Reflection, file_descriptor: *const schema.FileDescriptor, dependency: *const schema.FileDescriptor) Error!usize {
        for (file_descriptor.imports.items, 0..) |import, index| {
            const imported = self.registry.findFile(import.path) orelse continue;
            if (registry_mod.sameFile(imported, dependency)) return index;
        }
        return error.UnknownFile;
    }

    pub fn filePublicDependencyCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return importKindCount(file_descriptor, .public);
    }

    pub fn filePublicDependency(self: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.FileDescriptor {
        const import = importOfKindAt(file_descriptor, .public, index) orelse return error.UnknownFile;
        return try self.file(import.path);
    }

    pub fn filePublicDependencyIndex(self: Reflection, file_descriptor: *const schema.FileDescriptor, dependency: *const schema.FileDescriptor) Error!usize {
        return self.fileDependencyIndexOfKind(file_descriptor, .public, dependency) orelse error.UnknownFile;
    }

    pub fn fileWeakDependencyCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return importKindCount(file_descriptor, .weak);
    }

    pub fn fileWeakDependency(self: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.FileDescriptor {
        const import = importOfKindAt(file_descriptor, .weak, index) orelse return error.UnknownFile;
        return try self.file(import.path);
    }

    pub fn fileWeakDependencyIndex(self: Reflection, file_descriptor: *const schema.FileDescriptor, dependency: *const schema.FileDescriptor) Error!usize {
        return self.fileDependencyIndexOfKind(file_descriptor, .weak, dependency) orelse error.UnknownFile;
    }

    pub fn fileOptionDependencyCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return importKindCount(file_descriptor, .option);
    }

    pub fn fileOptionDependency(self: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.FileDescriptor {
        const import = importOfKindAt(file_descriptor, .option, index) orelse return error.UnknownFile;
        return try self.file(import.path);
    }

    pub fn fileOptionDependencyIndex(self: Reflection, file_descriptor: *const schema.FileDescriptor, dependency: *const schema.FileDescriptor) Error!usize {
        return self.fileDependencyIndexOfKind(file_descriptor, .option, dependency) orelse error.UnknownFile;
    }

    fn fileDependencyIndexOfKind(self: Reflection, file_descriptor: *const schema.FileDescriptor, kind: schema.Import.Kind, dependency: *const schema.FileDescriptor) ?usize {
        var seen: usize = 0;
        for (file_descriptor.imports.items) |import| {
            if (import.kind != kind) continue;
            const imported = self.registry.findFile(import.path) orelse {
                seen += 1;
                continue;
            };
            if (registry_mod.sameFile(imported, dependency)) return seen;
            seen += 1;
        }
        return null;
    }

    pub fn fileMessageCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return file_descriptor.messageCount();
    }

    pub fn fileMessageAt(_: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.MessageDescriptor {
        return file_descriptor.messageAt(index) orelse error.UnknownMessage;
    }

    pub fn fileMessage(_: Reflection, file_descriptor: *const schema.FileDescriptor, name: []const u8) Error!*const schema.MessageDescriptor {
        return file_descriptor.findMessage(name) orelse error.UnknownMessage;
    }

    pub fn fileMessageIndex(_: Reflection, file_descriptor: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor) Error!usize {
        for (file_descriptor.messages.items, 0..) |*candidate, index| {
            if (candidate == descriptor) return index;
        }
        return error.UnknownMessage;
    }

    pub fn fileMessageDeep(_: Reflection, file_descriptor: *const schema.FileDescriptor, name: []const u8) Error!*const schema.MessageDescriptor {
        return file_descriptor.findMessageDeep(name) orelse error.UnknownMessage;
    }

    pub fn fileEnumCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return file_descriptor.enumCount();
    }

    pub fn fileEnumAt(_: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.EnumDescriptor {
        return file_descriptor.enumAt(index) orelse error.UnknownEnum;
    }

    pub fn fileEnum(_: Reflection, file_descriptor: *const schema.FileDescriptor, name: []const u8) Error!*const schema.EnumDescriptor {
        return file_descriptor.findEnum(name) orelse error.UnknownEnum;
    }

    pub fn fileEnumIndex(_: Reflection, file_descriptor: *const schema.FileDescriptor, descriptor: *const schema.EnumDescriptor) Error!usize {
        for (file_descriptor.enums.items, 0..) |*candidate, index| {
            if (candidate == descriptor) return index;
        }
        return error.UnknownEnum;
    }

    pub fn fileEnumValue(_: Reflection, file_descriptor: *const schema.FileDescriptor, name: []const u8) Error!*const schema.EnumValueDescriptor {
        return file_descriptor.findEnumValue(name) orelse error.UnknownEnum;
    }

    pub fn fileEnumDeep(_: Reflection, file_descriptor: *const schema.FileDescriptor, name: []const u8) Error!*const schema.EnumDescriptor {
        return file_descriptor.findEnumDeep(name) orelse error.UnknownEnum;
    }

    pub fn fileServiceCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return file_descriptor.serviceCount();
    }

    pub fn fileServiceAt(_: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.ServiceDescriptor {
        return file_descriptor.serviceAt(index) orelse error.UnknownService;
    }

    pub fn fileServiceIndex(_: Reflection, file_descriptor: *const schema.FileDescriptor, descriptor: *const schema.ServiceDescriptor) Error!usize {
        for (file_descriptor.services.items, 0..) |*candidate, index| {
            if (candidate == descriptor) return index;
        }
        return error.UnknownService;
    }

    pub fn fileExtensionCount(_: Reflection, file_descriptor: *const schema.FileDescriptor) usize {
        return file_descriptor.extensionCount();
    }

    pub fn fileExtensionAt(_: Reflection, file_descriptor: *const schema.FileDescriptor, index: usize) Error!*const schema.FieldDescriptor {
        return file_descriptor.extensionAt(index) orelse error.UnknownField;
    }

    pub fn fileExtension(_: Reflection, file_descriptor: *const schema.FileDescriptor, name: []const u8) Error!*const schema.FieldDescriptor {
        return file_descriptor.findExtension(name) orelse error.UnknownField;
    }

    pub fn fileExtensionByLowercaseName(_: Reflection, file_descriptor: *const schema.FileDescriptor, lowercase_name: []const u8) Error!*const schema.FieldDescriptor {
        return file_descriptor.findExtensionByLowercaseName(lowercase_name) orelse error.UnknownField;
    }

    pub fn fileExtensionByCamelcaseName(_: Reflection, file_descriptor: *const schema.FileDescriptor, camelcase_name: []const u8) Error!*const schema.FieldDescriptor {
        return file_descriptor.findExtensionByCamelcaseName(camelcase_name) orelse error.UnknownField;
    }

    pub fn fileExtensionIndex(_: Reflection, file_descriptor: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) Error!usize {
        for (file_descriptor.extensions.items, 0..) |*candidate, index| {
            if (candidate == field) return index;
        }
        return error.UnknownField;
    }

    pub fn fileCanSee(self: Reflection, from: *const schema.FileDescriptor, to: *const schema.FileDescriptor) bool {
        return self.registry.fileCanSee(from, to);
    }

    pub fn fileContainingSymbol(self: Reflection, symbol_name: []const u8) Error!*const schema.FileDescriptor {
        return self.registry.findFileContainingSymbol(symbol_name) orelse error.UnknownFile;
    }

    pub fn importChain(self: Reflection, from: *const schema.FileDescriptor, to: *const schema.FileDescriptor) ?registry_mod.ImportChain {
        return self.registry.importChain(from, to);
    }

    pub fn importChainByPath(self: Reflection, from_path: []const u8, to_path: []const u8) Error!?registry_mod.ImportChain {
        return self.importChain(try self.file(from_path), try self.file(to_path));
    }

    pub fn importChainLength(_: Reflection, chain: registry_mod.ImportChain) usize {
        return chain.len;
    }

    pub fn importChainPathAt(_: Reflection, chain: registry_mod.ImportChain, index: usize) Error![]const u8 {
        if (index >= chain.len) return error.UnknownFile;
        return chain.paths[index];
    }

    pub fn importChainPathIndex(_: Reflection, chain: registry_mod.ImportChain, path: []const u8) Error!usize {
        for (chain.slice(), 0..) |candidate, index| {
            if (std.mem.eql(u8, candidate, path)) return index;
        }
        return error.UnknownFile;
    }

    pub fn importChainPaths(_: Reflection, chain: registry_mod.ImportChain) []const []const u8 {
        return chain.slice();
    }

    pub fn message(self: Reflection, name: []const u8) Error!*const schema.MessageDescriptor {
        return self.registry.findMessage(name, null) orelse error.UnknownMessage;
    }

    pub fn messageName(_: Reflection, descriptor: *const schema.MessageDescriptor) []const u8 {
        return descriptor.name;
    }

    pub fn messageIsDeprecated(_: Reflection, descriptor: *const schema.MessageDescriptor) bool {
        return schema.optionBool(descriptor.options.items, "deprecated") orelse false;
    }

    pub fn messageIsPlaceholder(_: Reflection, _: *const schema.MessageDescriptor) bool {
        return false;
    }

    pub fn messageNoStandardDescriptorAccessor(_: Reflection, descriptor: *const schema.MessageDescriptor) bool {
        return descriptor.noStandardDescriptorAccessor();
    }

    pub fn messageDeprecatedLegacyJsonFieldConflicts(_: Reflection, descriptor: *const schema.MessageDescriptor) bool {
        return descriptor.deprecatedLegacyJsonFieldConflicts();
    }

    pub fn messageIsMapEntry(_: Reflection, descriptor: *const schema.MessageDescriptor) bool {
        return descriptor.isMapEntry();
    }

    pub fn messageIsMessageSetWireFormat(_: Reflection, descriptor: *const schema.MessageDescriptor) bool {
        return descriptor.messageSetWireFormat();
    }

    pub fn messageOptions(_: Reflection, descriptor: *const schema.MessageDescriptor) []const schema.FieldOption {
        return descriptor.options.items;
    }

    pub fn messageHasExplicitFeatures(_: Reflection, descriptor: *const schema.MessageDescriptor) bool {
        return descriptor.features != null;
    }

    pub fn messageExplicitFeatures(_: Reflection, descriptor: *const schema.MessageDescriptor) Error!schema.FeatureSet {
        return descriptor.features orelse error.MissingField;
    }

    pub fn messageFullName(self: Reflection, descriptor: *const schema.MessageDescriptor) Error![]u8 {
        const owner_file = try self.fileOfMessage(descriptor);
        return try messageFullNameInFileAlloc(self.allocator, owner_file, descriptor) orelse error.UnknownMessage;
    }

    pub fn messageWellKnownType(self: Reflection, descriptor: *const schema.MessageDescriptor) Error!schema.WellKnownType {
        const full_name = try self.messageFullName(descriptor);
        defer self.allocator.free(full_name);
        return schema.wellKnownTypeFromFullName(full_name);
    }

    pub fn messageIsWellKnownType(self: Reflection, descriptor: *const schema.MessageDescriptor) Error!bool {
        return (try self.messageWellKnownType(descriptor)) != .unspecified;
    }

    pub fn messageIndex(self: Reflection, descriptor: *const schema.MessageDescriptor) Error!usize {
        const owner_file = try self.fileOfMessage(descriptor);
        if (containingMessageForMessage(owner_file, descriptor)) |parent| {
            for (parent.messages.items, 0..) |*candidate, index| {
                if (candidate == descriptor) return index;
            }
        } else {
            for (owner_file.messages.items, 0..) |*candidate, index| {
                if (candidate == descriptor) return index;
            }
        }
        return error.UnknownMessage;
    }

    pub fn messageContainingType(self: Reflection, descriptor: *const schema.MessageDescriptor) Error!?*const schema.MessageDescriptor {
        const owner_file = try self.fileOfMessage(descriptor);
        return containingMessageForMessage(owner_file, descriptor);
    }

    pub fn fileOfMessage(self: Reflection, descriptor: *const schema.MessageDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingMessage(descriptor) orelse error.UnknownMessage;
    }

    pub fn messageFieldCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.fieldCount();
    }

    pub fn messageFieldAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error!*const schema.FieldDescriptor {
        return descriptor.fieldAt(index) orelse error.UnknownField;
    }

    pub fn fieldIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!usize {
        for (descriptor.fields.items, 0..) |*candidate, index| {
            if (candidate == field) return index;
        }
        return error.UnknownField;
    }

    pub fn messageExtensionCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.extensionCount();
    }

    pub fn messageExtensionAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error!*const schema.FieldDescriptor {
        return descriptor.extensionAt(index) orelse error.UnknownField;
    }

    pub fn messageExtension(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.FieldDescriptor {
        return descriptor.findExtension(name) orelse error.UnknownField;
    }

    pub fn messageExtensionByLowercaseName(_: Reflection, descriptor: *const schema.MessageDescriptor, lowercase_name: []const u8) Error!*const schema.FieldDescriptor {
        return descriptor.findExtensionByLowercaseName(lowercase_name) orelse error.UnknownField;
    }

    pub fn messageExtensionByCamelcaseName(_: Reflection, descriptor: *const schema.MessageDescriptor, camelcase_name: []const u8) Error!*const schema.FieldDescriptor {
        return descriptor.findExtensionByCamelcaseName(camelcase_name) orelse error.UnknownField;
    }

    pub fn messageExtensionIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!usize {
        for (descriptor.extensions.items, 0..) |*candidate, index| {
            if (candidate == field) return index;
        }
        return error.UnknownField;
    }

    pub fn messageOneofCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.oneofCount();
    }

    pub fn messageRealOneofCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.realOneofCount();
    }

    pub fn messageOneofAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error!*const schema.OneofDescriptor {
        return descriptor.oneofAt(index) orelse error.UnknownField;
    }

    pub fn messageRealOneofAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error!*const schema.OneofDescriptor {
        return descriptor.realOneofAt(index) orelse error.UnknownField;
    }

    pub fn oneofIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error!usize {
        for (descriptor.oneofs.items, 0..) |*candidate, index| {
            if (candidate == oneof) return index;
        }
        return error.UnknownField;
    }

    pub fn realOneofIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error!usize {
        var seen: usize = 0;
        for (descriptor.oneofs.items) |*candidate| {
            if (descriptor.oneofIsSynthetic(candidate)) continue;
            if (candidate == oneof) return seen;
            seen += 1;
        }
        return error.UnknownField;
    }

    pub fn messageNestedMessageCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.nestedMessageCount();
    }

    pub fn messageNestedMessageAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error!*const schema.MessageDescriptor {
        return descriptor.nestedMessageAt(index) orelse error.UnknownMessage;
    }

    pub fn messageNestedMessage(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.MessageDescriptor {
        return descriptor.findMessage(name) orelse error.UnknownMessage;
    }

    pub fn messageNestedMessageIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, nested: *const schema.MessageDescriptor) Error!usize {
        for (descriptor.messages.items, 0..) |*candidate, index| {
            if (candidate == nested) return index;
        }
        return error.UnknownMessage;
    }

    pub fn messageNestedMessageDeep(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.MessageDescriptor {
        return descriptor.findMessageDeep(name) orelse error.UnknownMessage;
    }

    pub fn messageNestedEnumCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.nestedEnumCount();
    }

    pub fn messageNestedEnumAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error!*const schema.EnumDescriptor {
        return descriptor.nestedEnumAt(index) orelse error.UnknownEnum;
    }

    pub fn messageNestedEnum(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.EnumDescriptor {
        return descriptor.findEnum(name) orelse error.UnknownEnum;
    }

    pub fn messageNestedEnumIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, nested: *const schema.EnumDescriptor) Error!usize {
        for (descriptor.enums.items, 0..) |*candidate, index| {
            if (candidate == nested) return index;
        }
        return error.UnknownEnum;
    }

    pub fn messageNestedEnumValue(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.EnumValueDescriptor {
        return descriptor.findEnumValue(name) orelse error.UnknownEnum;
    }

    pub fn messageNestedEnumDeep(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.EnumDescriptor {
        return descriptor.findEnumDeep(name) orelse error.UnknownEnum;
    }

    pub fn enumeration(self: Reflection, name: []const u8) Error!*const schema.EnumDescriptor {
        return self.registry.findEnum(name, null) orelse error.UnknownEnum;
    }

    pub fn enumName(_: Reflection, descriptor: *const schema.EnumDescriptor) []const u8 {
        return descriptor.name;
    }

    pub fn enumIsDeprecated(_: Reflection, descriptor: *const schema.EnumDescriptor) bool {
        return schema.optionBool(descriptor.options.items, "deprecated") orelse false;
    }

    pub fn enumIsPlaceholder(_: Reflection, _: *const schema.EnumDescriptor) bool {
        return false;
    }

    pub fn enumDeprecatedLegacyJsonFieldConflicts(_: Reflection, descriptor: *const schema.EnumDescriptor) bool {
        return descriptor.deprecatedLegacyJsonFieldConflicts();
    }

    pub fn enumOptions(_: Reflection, descriptor: *const schema.EnumDescriptor) []const schema.FieldOption {
        return descriptor.options.items;
    }

    pub fn enumHasExplicitFeatures(_: Reflection, descriptor: *const schema.EnumDescriptor) bool {
        return descriptor.features != null;
    }

    pub fn enumExplicitFeatures(_: Reflection, descriptor: *const schema.EnumDescriptor) Error!schema.FeatureSet {
        return descriptor.features orelse error.MissingField;
    }

    pub fn enumFullName(self: Reflection, descriptor: *const schema.EnumDescriptor) Error![]u8 {
        const owner_file = try self.fileOfEnum(descriptor);
        return try enumFullNameInFileAlloc(self.allocator, owner_file, descriptor) orelse error.UnknownEnum;
    }

    pub fn enumIndex(self: Reflection, descriptor: *const schema.EnumDescriptor) Error!usize {
        const owner_file = try self.fileOfEnum(descriptor);
        if (containingMessageForEnum(owner_file, descriptor)) |parent| {
            for (parent.enums.items, 0..) |*candidate, index| {
                if (candidate == descriptor) return index;
            }
        } else {
            for (owner_file.enums.items, 0..) |*candidate, index| {
                if (candidate == descriptor) return index;
            }
        }
        return error.UnknownEnum;
    }

    pub fn enumContainingType(self: Reflection, descriptor: *const schema.EnumDescriptor) Error!?*const schema.MessageDescriptor {
        const owner_file = try self.fileOfEnum(descriptor);
        return containingMessageForEnum(owner_file, descriptor);
    }

    pub fn fileOfEnum(self: Reflection, descriptor: *const schema.EnumDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingEnum(descriptor) orelse error.UnknownEnum;
    }

    pub fn enumValueName(_: Reflection, descriptor: *const schema.EnumValueDescriptor) []const u8 {
        return descriptor.name;
    }

    pub fn enumValueNumber(_: Reflection, descriptor: *const schema.EnumValueDescriptor) i32 {
        return descriptor.number;
    }

    pub fn enumValueIsDeprecated(_: Reflection, descriptor: *const schema.EnumValueDescriptor) bool {
        return schema.optionBool(descriptor.options.items, "deprecated") orelse false;
    }

    pub fn enumValueIsDebugRedacted(_: Reflection, descriptor: *const schema.EnumValueDescriptor) bool {
        return descriptor.isDebugRedacted();
    }

    pub fn enumValueOptions(_: Reflection, descriptor: *const schema.EnumValueDescriptor) []const schema.FieldOption {
        return descriptor.options.items;
    }

    pub fn enumValueHasFeatureSupport(_: Reflection, descriptor: *const schema.EnumValueDescriptor) bool {
        return descriptor.feature_support != null;
    }

    pub fn enumValueFeatureSupport(_: Reflection, descriptor: *const schema.EnumValueDescriptor) Error!schema.FeatureSupport {
        return descriptor.feature_support orelse error.MissingField;
    }

    pub fn featureSupportHasEditionIntroduced(_: Reflection, support: schema.FeatureSupport) bool {
        return support.edition_introduced != null;
    }

    pub fn featureSupportEditionIntroduced(_: Reflection, support: schema.FeatureSupport) Error!schema.Edition {
        return support.edition_introduced orelse error.MissingField;
    }

    pub fn featureSupportHasEditionDeprecated(_: Reflection, support: schema.FeatureSupport) bool {
        return support.edition_deprecated != null;
    }

    pub fn featureSupportEditionDeprecated(_: Reflection, support: schema.FeatureSupport) Error!schema.Edition {
        return support.edition_deprecated orelse error.MissingField;
    }

    pub fn featureSupportDeprecationWarning(_: Reflection, support: schema.FeatureSupport) []const u8 {
        return support.deprecation_warning;
    }

    pub fn featureSupportHasEditionRemoved(_: Reflection, support: schema.FeatureSupport) bool {
        return support.edition_removed != null;
    }

    pub fn featureSupportEditionRemoved(_: Reflection, support: schema.FeatureSupport) Error!schema.Edition {
        return support.edition_removed orelse error.MissingField;
    }

    pub fn featureSupportRemovalError(_: Reflection, support: schema.FeatureSupport) []const u8 {
        return support.removal_error;
    }

    pub fn enumValueHasExplicitFeatures(_: Reflection, descriptor: *const schema.EnumValueDescriptor) bool {
        return descriptor.features != null;
    }

    pub fn enumValueExplicitFeatures(_: Reflection, descriptor: *const schema.EnumValueDescriptor) Error!schema.FeatureSet {
        return descriptor.features orelse error.MissingField;
    }

    pub fn enumValueFullName(self: Reflection, enum_descriptor: *const schema.EnumDescriptor, value: *const schema.EnumValueDescriptor) Error![]u8 {
        const enum_full_name = try self.enumFullName(enum_descriptor);
        defer self.allocator.free(enum_full_name);
        // Protobuf enum values are scoped to the enum's parent, not to the enum
        // type itself.  This matches C++ EnumValueDescriptor::full_name() and
        // the DescriptorPool duplicate-symbol rules also enforced by Registry.
        const parent_scope = if (std.mem.lastIndexOfScalar(u8, enum_full_name, '.')) |idx| enum_full_name[0..idx] else "";
        return try joinNameAlloc(self.allocator, parent_scope, value.name);
    }

    pub fn enumValueContainingEnum(_: Reflection, enum_descriptor: *const schema.EnumDescriptor, value: *const schema.EnumValueDescriptor) Error!*const schema.EnumDescriptor {
        if (enum_descriptor.findValue(value.name) != value) return error.UnknownEnum;
        return enum_descriptor;
    }

    pub fn enumValueType(self: Reflection, value: *const schema.EnumValueDescriptor) Error!*const schema.EnumDescriptor {
        return self.registry.enumContainingValue(value) orelse error.UnknownEnum;
    }

    pub fn enumValueContainingFile(self: Reflection, enum_descriptor: *const schema.EnumDescriptor, value: *const schema.EnumValueDescriptor) Error!*const schema.FileDescriptor {
        _ = try self.enumValueContainingEnum(enum_descriptor, value);
        return try self.fileOfEnum(enum_descriptor);
    }

    pub fn enumValueFile(self: Reflection, value: *const schema.EnumValueDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingEnumValue(value) orelse error.UnknownEnum;
    }

    pub fn enumValueDirectIndex(self: Reflection, value: *const schema.EnumValueDescriptor) Error!usize {
        return try self.enumValueIndex(try self.enumValueType(value), value);
    }

    pub fn enumValueDirectFullName(self: Reflection, value: *const schema.EnumValueDescriptor) Error![]u8 {
        return try self.enumValueFullName(try self.enumValueType(value), value);
    }

    pub fn enumValueCount(_: Reflection, descriptor: *const schema.EnumDescriptor) usize {
        return descriptor.valueCount();
    }

    pub fn enumValueAt(_: Reflection, descriptor: *const schema.EnumDescriptor, index: usize) Error!*const schema.EnumValueDescriptor {
        return descriptor.valueAt(index) orelse error.UnknownEnum;
    }

    pub fn enumValueIndex(_: Reflection, descriptor: *const schema.EnumDescriptor, value: *const schema.EnumValueDescriptor) Error!usize {
        for (descriptor.values.items, 0..) |*candidate, index| {
            if (candidate == value) return index;
        }
        return error.UnknownEnum;
    }

    pub fn service(self: Reflection, name: []const u8) Error!*const schema.ServiceDescriptor {
        return self.registry.findService(name, null) orelse error.UnknownService;
    }

    pub fn methodByFullName(self: Reflection, name: []const u8) Error!*const schema.MethodDescriptor {
        return self.registry.findMethod(name, null) orelse error.UnknownField;
    }

    pub fn serviceName(_: Reflection, descriptor: *const schema.ServiceDescriptor) []const u8 {
        return descriptor.name;
    }

    pub fn serviceIsDeprecated(_: Reflection, descriptor: *const schema.ServiceDescriptor) bool {
        return schema.optionBool(descriptor.options.items, "deprecated") orelse false;
    }

    pub fn serviceOptions(_: Reflection, descriptor: *const schema.ServiceDescriptor) []const schema.FieldOption {
        return descriptor.options.items;
    }

    pub fn serviceHasExplicitFeatures(_: Reflection, descriptor: *const schema.ServiceDescriptor) bool {
        return descriptor.features != null;
    }

    pub fn serviceExplicitFeatures(_: Reflection, descriptor: *const schema.ServiceDescriptor) Error!schema.FeatureSet {
        return descriptor.features orelse error.MissingField;
    }

    pub fn fileService(_: Reflection, file_descriptor: *const schema.FileDescriptor, name: []const u8) Error!*const schema.ServiceDescriptor {
        return file_descriptor.findService(name) orelse error.UnknownService;
    }

    pub fn serviceFullName(self: Reflection, descriptor: *const schema.ServiceDescriptor) Error![]u8 {
        const owner_file = try self.fileOfService(descriptor);
        return try qualifyFileSymbolAlloc(self.allocator, owner_file, descriptor.name);
    }

    pub fn fileOfService(self: Reflection, descriptor: *const schema.ServiceDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingService(descriptor) orelse error.UnknownService;
    }

    pub fn serviceIndex(self: Reflection, descriptor: *const schema.ServiceDescriptor) Error!usize {
        const owner_file = try self.fileOfService(descriptor);
        for (owner_file.services.items, 0..) |*candidate, index| {
            if (candidate == descriptor) return index;
        }
        return error.UnknownService;
    }

    pub fn methodName(_: Reflection, method: *const schema.MethodDescriptor) []const u8 {
        return method.name;
    }

    pub fn methodIsDeprecated(_: Reflection, method: *const schema.MethodDescriptor) bool {
        return schema.optionBool(method.options.items, "deprecated") orelse false;
    }

    pub fn methodOptions(_: Reflection, method: *const schema.MethodDescriptor) []const schema.FieldOption {
        return method.options.items;
    }

    pub fn methodIdempotencyLevel(_: Reflection, method: *const schema.MethodDescriptor) ?schema.MethodIdempotencyLevel {
        return method.idempotencyLevel();
    }

    pub fn methodHasExplicitFeatures(_: Reflection, method: *const schema.MethodDescriptor) bool {
        return method.features != null;
    }

    pub fn methodExplicitFeatures(_: Reflection, method: *const schema.MethodDescriptor) Error!schema.FeatureSet {
        return method.features orelse error.MissingField;
    }

    pub fn methodFullName(self: Reflection, service_descriptor: *const schema.ServiceDescriptor, method: *const schema.MethodDescriptor) Error![]u8 {
        const service_full_name = try self.serviceFullName(service_descriptor);
        defer self.allocator.free(service_full_name);
        return try joinNameAlloc(self.allocator, service_full_name, method.name);
    }

    pub fn methodDirectFullName(self: Reflection, method: *const schema.MethodDescriptor) Error![]u8 {
        return try self.methodFullName(try self.methodService(method), method);
    }

    pub fn methodContainingService(_: Reflection, service_descriptor: *const schema.ServiceDescriptor, method: *const schema.MethodDescriptor) Error!*const schema.ServiceDescriptor {
        if (service_descriptor.findMethod(method.name) != method) return error.UnknownField;
        return service_descriptor;
    }

    pub fn methodService(self: Reflection, method: *const schema.MethodDescriptor) Error!*const schema.ServiceDescriptor {
        return self.registry.serviceContainingMethod(method) orelse error.UnknownService;
    }

    pub fn methodContainingFile(self: Reflection, service_descriptor: *const schema.ServiceDescriptor, method: *const schema.MethodDescriptor) Error!*const schema.FileDescriptor {
        _ = try self.methodContainingService(service_descriptor, method);
        return try self.fileOfService(service_descriptor);
    }

    pub fn methodFile(self: Reflection, method: *const schema.MethodDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingMethod(method) orelse error.UnknownService;
    }

    pub fn serviceMethodCount(_: Reflection, descriptor: *const schema.ServiceDescriptor) usize {
        return descriptor.methodCount();
    }

    pub fn serviceMethodAt(_: Reflection, descriptor: *const schema.ServiceDescriptor, index: usize) Error!*const schema.MethodDescriptor {
        return descriptor.methodAt(index) orelse error.UnknownField;
    }

    pub fn methodIndex(_: Reflection, descriptor: *const schema.ServiceDescriptor, method: *const schema.MethodDescriptor) Error!usize {
        for (descriptor.methods.items, 0..) |*candidate, index| {
            if (candidate == method) return index;
        }
        return error.UnknownField;
    }

    pub fn methodDirectIndex(self: Reflection, method: *const schema.MethodDescriptor) Error!usize {
        return try self.methodIndex(try self.methodService(method), method);
    }

    pub fn methodByName(_: Reflection, descriptor: *const schema.ServiceDescriptor, name: []const u8) Error!*const schema.MethodDescriptor {
        return descriptor.findMethod(name) orelse error.UnknownField;
    }

    pub fn methodInputTypeName(_: Reflection, method: *const schema.MethodDescriptor) []const u8 {
        return method.input_type;
    }

    pub fn methodOutputTypeName(_: Reflection, method: *const schema.MethodDescriptor) []const u8 {
        return method.output_type;
    }

    pub fn methodInputType(self: Reflection, service_descriptor: *const schema.ServiceDescriptor, method: *const schema.MethodDescriptor) Error!*const schema.MessageDescriptor {
        const owner_file = try self.fileOfService(service_descriptor);
        return self.registry.findMessageVisible(owner_file, method.input_type, owner_file.package) orelse error.UnknownMessage;
    }

    pub fn methodOutputType(self: Reflection, service_descriptor: *const schema.ServiceDescriptor, method: *const schema.MethodDescriptor) Error!*const schema.MessageDescriptor {
        const owner_file = try self.fileOfService(service_descriptor);
        return self.registry.findMessageVisible(owner_file, method.output_type, owner_file.package) orelse error.UnknownMessage;
    }

    pub fn methodClientStreaming(_: Reflection, method: *const schema.MethodDescriptor) bool {
        return method.client_streaming;
    }

    pub fn methodServerStreaming(_: Reflection, method: *const schema.MethodDescriptor) bool {
        return method.server_streaming;
    }

    pub fn newMessage(self: Reflection, name: []const u8) Error!dynamic.DynamicMessage {
        return dynamic.DynamicMessage.init(self.allocator, try self.message(name));
    }

    pub fn newMessageForField(self: Reflection, parent_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!dynamic.DynamicMessage {
        const type_name = switch (field.kind) {
            .message => |name| name,
            else => return error.TypeMismatch,
        };
        const descriptor = try self.messageForFieldType(parent_descriptor, field, type_name);
        return dynamic.DynamicMessage.init(self.allocator, descriptor);
    }

    pub fn newMessageForFieldName(self: Reflection, parent_descriptor: *const schema.MessageDescriptor, name: []const u8) Error!dynamic.DynamicMessage {
        return try self.newMessageForField(parent_descriptor, try self.fieldByName(parent_descriptor, name));
    }

    pub fn newGroupForField(self: Reflection, parent_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!dynamic.DynamicMessage {
        const type_name = switch (field.kind) {
            .group => |name| name,
            else => return error.TypeMismatch,
        };
        const descriptor = try self.messageForFieldType(parent_descriptor, field, type_name);
        return dynamic.DynamicMessage.init(self.allocator, descriptor);
    }

    pub fn newGroupForFieldName(self: Reflection, parent_descriptor: *const schema.MessageDescriptor, name: []const u8) Error!dynamic.DynamicMessage {
        return try self.newGroupForField(parent_descriptor, try self.fieldByName(parent_descriptor, name));
    }

    pub fn fieldByName(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.FieldDescriptor {
        return descriptor.findField(name) orelse error.UnknownField;
    }

    pub fn fieldByFullName(self: Reflection, name: []const u8) Error!*const schema.FieldDescriptor {
        return self.registry.findField(name, null) orelse error.UnknownField;
    }

    pub fn fieldByLowercaseName(_: Reflection, descriptor: *const schema.MessageDescriptor, lowercase_name: []const u8) Error!*const schema.FieldDescriptor {
        return descriptor.findFieldByLowercaseName(lowercase_name) orelse error.UnknownField;
    }

    pub fn fieldByCamelcaseName(_: Reflection, descriptor: *const schema.MessageDescriptor, camelcase_name: []const u8) Error!*const schema.FieldDescriptor {
        return descriptor.findFieldByCamelcaseName(camelcase_name) orelse error.UnknownField;
    }

    pub fn fieldName(_: Reflection, field: *const schema.FieldDescriptor) []const u8 {
        return field.name;
    }

    pub fn fieldLowercaseName(self: Reflection, field: *const schema.FieldDescriptor) Error![]u8 {
        return try field.lowercaseName(self.allocator);
    }

    pub fn fieldCamelcaseName(self: Reflection, field: *const schema.FieldDescriptor) Error![]u8 {
        return try field.camelcaseName(self.allocator);
    }

    pub fn fieldIsDeprecated(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return schema.optionBool(field.options.items, "deprecated") orelse false;
    }

    pub fn fieldIsDebugRedacted(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isDebugRedacted();
    }

    pub fn fieldCType(_: Reflection, field: *const schema.FieldDescriptor) ?schema.FieldCType {
        return field.cType();
    }

    pub fn fieldJSType(_: Reflection, field: *const schema.FieldDescriptor) ?schema.FieldJSType {
        return field.jsType();
    }

    pub fn fieldRetention(_: Reflection, field: *const schema.FieldDescriptor) ?schema.FieldRetention {
        return field.retention();
    }

    pub fn fieldTargetCount(_: Reflection, field: *const schema.FieldDescriptor) usize {
        return field.targetCount();
    }

    pub fn fieldTargetAt(_: Reflection, field: *const schema.FieldDescriptor, index: usize) Error!schema.FieldTargetType {
        return field.targetAt(index) orelse error.MissingField;
    }

    pub fn fieldTargetIndex(_: Reflection, field: *const schema.FieldDescriptor, target: schema.FieldTargetType) Error!usize {
        var seen: usize = 0;
        for (field.options.items) |option| {
            if (!std.mem.eql(u8, schema.optionLeaf(option.name), "targets")) continue;
            const candidate = schema.optionAsKnownEnum(schema.FieldTargetType, option.value) orelse {
                seen += 1;
                continue;
            };
            if (candidate == target) return seen;
            seen += 1;
        }
        return error.MissingField;
    }

    pub fn fieldIsWeak(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isWeak();
    }

    pub fn fieldIsLazy(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isLazy();
    }

    pub fn fieldIsUnverifiedLazy(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isUnverifiedLazy();
    }

    pub fn fieldOptions(_: Reflection, field: *const schema.FieldDescriptor) []const schema.FieldOption {
        return field.options.items;
    }

    pub fn fieldFullName(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error![]u8 {
        if (field.extendee != null) return try self.extensionFullName(field);
        const message_full_name = try self.messageFullName(descriptor);
        defer self.allocator.free(message_full_name);
        return try joinNameAlloc(self.allocator, message_full_name, field.name);
    }

    pub fn fieldDirectFullName(self: Reflection, field: *const schema.FieldDescriptor) Error![]u8 {
        if (field.extendee != null) return try self.extensionFullName(field);
        const owner = self.registry.messageContainingField(field) orelse return error.UnknownField;
        return try self.fieldFullName(owner, field);
    }

    pub fn extensionFullName(self: Reflection, field: *const schema.FieldDescriptor) Error![]u8 {
        const owner_file = try self.fileOfExtension(field);
        return try qualifyFileSymbolAlloc(self.allocator, owner_file, schema.extensionFullName(field));
    }

    pub fn fieldNumber(_: Reflection, field: *const schema.FieldDescriptor) wire.FieldNumber {
        return field.number;
    }

    pub fn fieldCardinality(_: Reflection, field: *const schema.FieldDescriptor) schema.Cardinality {
        return field.cardinality;
    }

    pub fn fieldKind(_: Reflection, field: *const schema.FieldDescriptor) schema.FieldKind {
        return field.kind;
    }

    pub fn fieldCppType(_: Reflection, field: *const schema.FieldDescriptor) schema.FieldCppType {
        return field.cppType();
    }

    pub fn fieldDeclaredTypeName(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error![]const u8 {
        return switch (field.kind) {
            .scalar => |scalar| schema.scalarTypeName(scalar),
            .enumeration => "enum",
            .group => "group",
            .map => "message",
            .message => if (try self.fieldMessageArmResolvesToEnum(descriptor, field)) "enum" else "message",
        };
    }

    pub fn fieldCppTypeName(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error![]const u8 {
        if (try self.fieldMessageArmResolvesToEnum(descriptor, field)) return "enum";
        return field.cppTypeName();
    }

    pub fn fieldWireType(_: Reflection, field: *const schema.FieldDescriptor) wire.WireType {
        return field.wireType();
    }

    pub fn fieldEncodedWireType(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!wire.WireType {
        return field.encodedWireType(try self.fileForFieldContext(descriptor, field));
    }

    pub fn fieldIsScalar(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.kind == .scalar;
    }

    pub fn fieldScalarType(_: Reflection, field: *const schema.FieldDescriptor) Error!schema.ScalarType {
        return switch (field.kind) {
            .scalar => |scalar| scalar,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldScalarTypeName(_: Reflection, field: *const schema.FieldDescriptor) Error![]const u8 {
        return schema.scalarTypeName(switch (field.kind) {
            .scalar => |scalar| scalar,
            else => return error.TypeMismatch,
        });
    }

    pub fn fieldIsMessage(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.kind == .message;
    }

    pub fn fieldIsEnum(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.kind == .enumeration;
    }

    pub fn fieldIsGroup(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.kind == .group;
    }

    pub fn fieldTypeName(_: Reflection, field: *const schema.FieldDescriptor) Error![]const u8 {
        return switch (field.kind) {
            .message, .enumeration, .group => |name| name,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldMessageType(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.MessageDescriptor {
        const type_name = switch (field.kind) {
            .message => |name| name,
            else => return error.TypeMismatch,
        };
        return try self.messageForFieldType(message_descriptor, field, type_name);
    }

    pub fn fieldGroupType(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.MessageDescriptor {
        const type_name = switch (field.kind) {
            .group => |name| name,
            else => return error.TypeMismatch,
        };
        return try self.messageForFieldType(message_descriptor, field, type_name);
    }

    pub fn fieldDirectMessageType(self: Reflection, field: *const schema.FieldDescriptor) Error!*const schema.MessageDescriptor {
        const owner = try self.fieldDirectContainingType(field);
        return switch (field.kind) {
            .message => |type_name| try self.messageForFieldType(owner, field, type_name),
            .group => |type_name| try self.messageForFieldType(owner, field, type_name),
            else => error.TypeMismatch,
        };
    }

    pub fn fieldDirectGroupType(self: Reflection, field: *const schema.FieldDescriptor) Error!*const schema.MessageDescriptor {
        const owner = try self.fieldDirectContainingType(field);
        const type_name = switch (field.kind) {
            .group => |name| name,
            else => return error.TypeMismatch,
        };
        return try self.messageForFieldType(owner, field, type_name);
    }

    pub fn fieldEnumType(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.EnumDescriptor {
        return try self.enumForField(message_descriptor, field);
    }

    pub fn fieldDirectEnumType(self: Reflection, field: *const schema.FieldDescriptor) Error!*const schema.EnumDescriptor {
        return try self.enumForField(try self.fieldDirectContainingType(field), field);
    }

    fn fieldMessageArmResolvesToEnum(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!bool {
        switch (field.kind) {
            .message => {},
            else => return false,
        }
        _ = self.enumForKind(message_descriptor, field, field.kind) catch |err| switch (err) {
            error.TypeMismatch, error.UnknownEnum => return false,
            else => return err,
        };
        return true;
    }

    pub fn fieldHasOneof(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.oneof_name != null;
    }

    pub fn fieldOneofName(_: Reflection, field: *const schema.FieldDescriptor) Error![]const u8 {
        return field.oneof_name orelse error.MissingField;
    }

    pub fn fieldContainingOneof(_: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.OneofDescriptor {
        const oneof_name = field.oneof_name orelse return error.MissingField;
        return descriptor.findOneof(oneof_name) orelse error.UnknownField;
    }

    pub fn fieldRealContainingOneof(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!?*const schema.OneofDescriptor {
        const oneof = try self.fieldContainingOneof(descriptor, field);
        return if (descriptor.oneofIsSynthetic(oneof)) null else oneof;
    }

    pub fn fieldIndexInOneof(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!usize {
        const oneof_name = try self.fieldOneofName(field);
        return descriptor.oneofFieldIndex(oneof_name, field) orelse error.UnknownField;
    }

    pub fn fieldIsExtension(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.extendee != null;
    }

    pub fn fieldExtendeeName(_: Reflection, field: *const schema.FieldDescriptor) Error![]const u8 {
        return field.extendee orelse error.TypeMismatch;
    }

    pub fn fieldExtendeeType(self: Reflection, field: *const schema.FieldDescriptor) Error!*const schema.MessageDescriptor {
        const extendee = field.extendee orelse return error.TypeMismatch;
        const owner_file = try self.fileOfExtension(field);
        const scope = extensionScope(owner_file, field);
        if (self.registry.findMessageVisible(owner_file, extendee, scope)) |message_desc| return message_desc;
        if (self.registry.findMessage(extendee, scope)) |message_desc| return message_desc;
        return error.UnknownMessage;
    }

    pub fn fieldContainingType(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.MessageDescriptor {
        if (field.extendee != null) return try self.fieldExtendeeType(field);
        if (!messageDirectlyContainsField(descriptor, field)) return error.UnknownField;
        return descriptor;
    }

    pub fn fieldDirectContainingType(self: Reflection, field: *const schema.FieldDescriptor) Error!*const schema.MessageDescriptor {
        if (field.extendee != null) return try self.fieldExtendeeType(field);
        return self.registry.messageContainingField(field) orelse error.UnknownField;
    }

    pub fn fieldContainingFile(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.FileDescriptor {
        if (field.extendee != null) return try self.fileOfExtension(field);
        if (!messageDirectlyContainsField(descriptor, field)) return error.UnknownField;
        return try self.fileOfMessage(descriptor);
    }

    pub fn fieldDirectContainingFile(self: Reflection, field: *const schema.FieldDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingField(field) orelse error.UnknownField;
    }

    pub fn fieldExtensionScope(self: Reflection, field: *const schema.FieldDescriptor) Error!?*const schema.MessageDescriptor {
        if (field.extendee == null) return error.TypeMismatch;
        const owner_file = try self.fileOfExtension(field);
        return extensionScopeMessageInFile(owner_file, field);
    }

    pub fn fieldHasExtensionScope(self: Reflection, field: *const schema.FieldDescriptor) Error!bool {
        return (try self.fieldExtensionScope(field)) != null;
    }

    pub fn fieldByJsonName(_: Reflection, descriptor: *const schema.MessageDescriptor, json_name: []const u8) Error!*const schema.FieldDescriptor {
        return descriptor.findFieldByJsonName(json_name) orelse error.UnknownField;
    }

    pub fn fieldJsonName(self: Reflection, field: *const schema.FieldDescriptor) Error![]u8 {
        return try field.jsonName(self.allocator);
    }

    pub fn fieldHasExplicitJsonName(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.hasExplicitJsonName();
    }

    pub fn fieldExplicitJsonName(_: Reflection, field: *const schema.FieldDescriptor) Error![]const u8 {
        return field.explicitJsonName() orelse error.MissingField;
    }

    pub fn fieldHasPresence(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!bool {
        return field.hasPresence(try self.fileForFieldContext(descriptor, field));
    }

    pub fn fieldPresence(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!schema.FeatureSet.FieldPresence {
        return field.fieldPresence(try self.fileForFieldContext(descriptor, field));
    }

    pub fn fieldIsRequired(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isRequired();
    }

    pub fn fieldIsOptional(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.cardinality != .repeated and !field.isRequired();
    }

    pub fn fieldHasOptionalKeyword(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.hasOptionalKeyword();
    }

    pub fn fieldIsRepeated(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isRepeatedLike();
    }

    pub fn fieldIsSingular(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return !field.isRepeatedLike();
    }

    pub fn fieldIsProto3Optional(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.proto3_optional;
    }

    pub fn fieldHasDefaultValue(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.hasDefaultValue();
    }

    pub fn fieldExplicitDefaultValue(_: Reflection, field: *const schema.FieldDescriptor) Error!schema.OptionValue {
        return field.explicitDefaultValue() orelse error.MissingField;
    }

    pub fn fieldEditionDefaultCount(_: Reflection, field: *const schema.FieldDescriptor) usize {
        return field.edition_defaults.items.len;
    }

    pub fn fieldEditionDefaultAt(_: Reflection, field: *const schema.FieldDescriptor, index: usize) Error!schema.FieldEditionDefault {
        if (index >= field.edition_defaults.items.len) return error.UnknownField;
        return field.edition_defaults.items[index];
    }

    pub fn fieldEditionDefaultIndex(_: Reflection, field: *const schema.FieldDescriptor, default: schema.FieldEditionDefault) Error!usize {
        for (field.edition_defaults.items, 0..) |candidate, index| {
            if (candidate.edition == default.edition and std.mem.eql(u8, candidate.value, default.value)) return index;
        }
        return error.UnknownField;
    }

    pub fn fieldEditionDefaultEdition(_: Reflection, default: schema.FieldEditionDefault) schema.Edition {
        return default.edition;
    }

    pub fn fieldEditionDefaultValue(_: Reflection, default: schema.FieldEditionDefault) []const u8 {
        return default.value;
    }

    pub fn fieldDefaultValue(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!dynamic.DefaultValue {
        const owner_file = try self.fileForFieldContext(descriptor, field);
        const default_scope = if (field.extendee != null) (try self.fieldExtensionScope(field)) orelse descriptor else descriptor;
        return dynamic.defaultValueForFieldWithRegistry(owner_file, self.registry, default_scope, field);
    }

    pub fn fieldDefaultInt32(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!i32 {
        return switch (try self.fieldDefaultValue(descriptor, field)) {
            .int32, .sint32, .sfixed32 => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldDefaultInt64(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!i64 {
        return switch (try self.fieldDefaultValue(descriptor, field)) {
            .int64, .sint64, .sfixed64 => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldDefaultUInt32(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!u32 {
        return switch (try self.fieldDefaultValue(descriptor, field)) {
            .uint32, .fixed32 => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldDefaultUInt64(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!u64 {
        return switch (try self.fieldDefaultValue(descriptor, field)) {
            .uint64, .fixed64 => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldDefaultFloat(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!f32 {
        return switch (try self.fieldDefaultValue(descriptor, field)) {
            .float => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldDefaultDouble(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!f64 {
        return switch (try self.fieldDefaultValue(descriptor, field)) {
            .double => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldDefaultBool(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!bool {
        return switch (try self.fieldDefaultValue(descriptor, field)) {
            .boolean => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn fieldDefaultString(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error![]const u8 {
        return switch (try self.fieldDefaultValue(descriptor, field)) {
            .string, .bytes => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn defaultValueTag(_: Reflection, value: dynamic.DefaultValue) DefaultTag {
        return std.meta.activeTag(value);
    }

    pub fn fieldDefaultEnumValue(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.EnumValueDescriptor {
        const enum_desc = try self.fieldEnumType(descriptor, field);
        const value = switch (try self.fieldDefaultValue(descriptor, field)) {
            .enumeration => |number| number,
            else => return error.TypeMismatch,
        };
        return try self.enumValueByNumber(enum_desc, value);
    }

    pub fn fieldDefaultEnumName(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error![]const u8 {
        return (try self.fieldDefaultEnumValue(descriptor, field)).name;
    }

    pub fn fieldHasFeatureSupport(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.feature_support != null;
    }

    pub fn fieldFeatureSupport(_: Reflection, field: *const schema.FieldDescriptor) Error!schema.FeatureSupport {
        return field.feature_support orelse error.MissingField;
    }

    pub fn fieldHasExplicitFeatures(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.features != null;
    }

    pub fn fieldExplicitFeatures(_: Reflection, field: *const schema.FieldDescriptor) Error!schema.FeatureSet {
        return field.features orelse error.MissingField;
    }

    pub fn fieldIsMap(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isMap();
    }

    pub fn fieldMapKeyType(_: Reflection, field: *const schema.FieldDescriptor) Error!schema.ScalarType {
        return field.mapKeyType() orelse error.TypeMismatch;
    }

    pub fn fieldMapValueKind(_: Reflection, field: *const schema.FieldDescriptor) Error!schema.FieldKind {
        return field.mapValueKind() orelse error.TypeMismatch;
    }

    pub fn fieldIsRepeatedLike(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isRepeatedLike();
    }

    pub fn fieldIsPackable(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.isPackable();
    }

    pub fn fieldHasPackedOverride(_: Reflection, field: *const schema.FieldDescriptor) bool {
        return field.hasPackedOverride();
    }

    pub fn fieldPackedOverride(_: Reflection, field: *const schema.FieldDescriptor) Error!bool {
        return field.packedOverride() orelse error.MissingField;
    }

    pub fn fieldIsPacked(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!bool {
        return field.resolvedPacked(try self.fileForFieldContext(descriptor, field));
    }

    pub fn fieldUtf8Validation(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!schema.FeatureSet.Utf8Validation {
        return field.utf8Validation(try self.fileForFieldContext(descriptor, field));
    }

    pub fn fieldMessageEncoding(self: Reflection, descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!schema.FeatureSet.MessageEncoding {
        return field.messageEncoding(try self.fileForFieldContext(descriptor, field));
    }

    pub fn optionValue(_: Reflection, options: []const schema.FieldOption, name: []const u8) ?schema.OptionValue {
        return schema.optionValue(options, name);
    }

    pub fn optionBool(_: Reflection, options: []const schema.FieldOption, name: []const u8) ?bool {
        return schema.optionBool(options, name);
    }

    pub fn optionIdentifier(_: Reflection, options: []const schema.FieldOption, name: []const u8) ?[]const u8 {
        return schema.optionIdentifier(options, name);
    }

    pub fn optionString(_: Reflection, options: []const schema.FieldOption, name: []const u8) ?[]const u8 {
        return schema.optionString(options, name);
    }

    pub fn optionInteger(_: Reflection, options: []const schema.FieldOption, name: []const u8) ?i64 {
        return schema.optionInteger(options, name);
    }

    pub fn optionUnsignedInteger(_: Reflection, options: []const schema.FieldOption, name: []const u8) ?u64 {
        return schema.optionUnsignedInteger(options, name);
    }

    pub fn optionFloat(_: Reflection, options: []const schema.FieldOption, name: []const u8) ?f64 {
        return schema.optionFloat(options, name);
    }

    pub fn optionAggregate(_: Reflection, options: []const schema.FieldOption, name: []const u8) ?[]const u8 {
        return schema.optionAggregate(options, name);
    }

    pub fn fieldByNumber(_: Reflection, descriptor: *const schema.MessageDescriptor, number: wire.FieldNumber) Error!*const schema.FieldDescriptor {
        return descriptor.findFieldByNumber(number) orelse error.UnknownField;
    }

    pub fn extension(self: Reflection, extendee: []const u8, number: wire.FieldNumber) Error!*const schema.FieldDescriptor {
        return self.registry.findExtension(extendee, number) orelse error.UnknownField;
    }

    pub fn extensionForMessage(self: Reflection, descriptor: *const schema.MessageDescriptor, number: wire.FieldNumber) Error!*const schema.FieldDescriptor {
        return self.registry.findExtensionForMessage(descriptor, number) orelse error.UnknownField;
    }

    pub fn fileContainingExtension(self: Reflection, descriptor: *const schema.MessageDescriptor, number: wire.FieldNumber) Error!*const schema.FileDescriptor {
        return self.registry.findFileContainingExtensionForMessage(descriptor, number) orelse error.UnknownFile;
    }

    pub fn fileContainingExtensionByName(self: Reflection, extendee: []const u8, number: wire.FieldNumber) Error!*const schema.FileDescriptor {
        return self.registry.findFileContainingExtension(extendee, number) orelse error.UnknownFile;
    }

    pub fn extensionsForMessage(self: Reflection, descriptor: *const schema.MessageDescriptor) Error![]*const schema.FieldDescriptor {
        return try self.registry.extensionsForMessageAlloc(self.allocator, descriptor);
    }

    pub fn extensionByName(self: Reflection, extendee: []const u8, name: []const u8) Error!*const schema.FieldDescriptor {
        return self.registry.findExtensionByName(extendee, name) orelse error.UnknownField;
    }

    pub fn extensionByNameForMessage(self: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.FieldDescriptor {
        return self.registry.findExtensionByNameForMessage(descriptor, name) orelse error.UnknownField;
    }

    pub fn extensionByPrintableNameForMessage(self: Reflection, descriptor: *const schema.MessageDescriptor, printable_name: []const u8) Error!*const schema.FieldDescriptor {
        return self.registry.findExtensionByPrintableNameForMessage(descriptor, printable_name) orelse error.UnknownField;
    }

    pub fn fileOfExtension(self: Reflection, descriptor: *const schema.FieldDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingExtension(descriptor) orelse error.UnknownField;
    }

    pub fn oneofByName(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.OneofDescriptor {
        return descriptor.findOneof(name) orelse error.UnknownField;
    }

    pub fn oneofByFullName(self: Reflection, name: []const u8) Error!*const schema.OneofDescriptor {
        return self.registry.findOneof(name, null) orelse error.UnknownField;
    }

    pub fn oneofName(_: Reflection, descriptor: *const schema.OneofDescriptor) []const u8 {
        return descriptor.name;
    }

    pub fn oneofOptions(_: Reflection, descriptor: *const schema.OneofDescriptor) []const schema.FieldOption {
        return descriptor.options.items;
    }

    pub fn oneofHasExplicitFeatures(_: Reflection, descriptor: *const schema.OneofDescriptor) bool {
        return descriptor.features != null;
    }

    pub fn oneofExplicitFeatures(_: Reflection, descriptor: *const schema.OneofDescriptor) Error!schema.FeatureSet {
        return descriptor.features orelse error.MissingField;
    }

    pub fn oneofIsSynthetic(_: Reflection, message_descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error!bool {
        if (!messageDirectlyContainsOneof(message_descriptor, oneof)) return error.UnknownField;
        return message_descriptor.oneofIsSynthetic(oneof);
    }

    pub fn oneofIsReal(self: Reflection, message_descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error!bool {
        return !(try self.oneofIsSynthetic(message_descriptor, oneof));
    }

    pub fn oneofFullName(self: Reflection, message_descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error![]u8 {
        const message_full_name = try self.messageFullName(message_descriptor);
        defer self.allocator.free(message_full_name);
        return try joinNameAlloc(self.allocator, message_full_name, oneof.name);
    }

    pub fn oneofDirectFullName(self: Reflection, oneof: *const schema.OneofDescriptor) Error![]u8 {
        return try self.oneofFullName(try self.oneofDirectContainingType(oneof), oneof);
    }

    pub fn oneofContainingType(_: Reflection, message_descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error!*const schema.MessageDescriptor {
        if (message_descriptor.findOneof(oneof.name) != oneof) return error.UnknownField;
        return message_descriptor;
    }

    pub fn oneofDirectContainingType(self: Reflection, oneof: *const schema.OneofDescriptor) Error!*const schema.MessageDescriptor {
        return self.registry.messageContainingOneof(oneof) orelse error.UnknownField;
    }

    pub fn oneofContainingFile(self: Reflection, message_descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error!*const schema.FileDescriptor {
        _ = try self.oneofContainingType(message_descriptor, oneof);
        return try self.fileOfMessage(message_descriptor);
    }

    pub fn oneofDirectContainingFile(self: Reflection, oneof: *const schema.OneofDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingOneof(oneof) orelse error.UnknownField;
    }

    pub fn oneofDirectIndex(self: Reflection, oneof: *const schema.OneofDescriptor) Error!usize {
        return try self.oneofIndex(try self.oneofDirectContainingType(oneof), oneof);
    }

    pub fn oneofFields(self: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error![]*const schema.FieldDescriptor {
        _ = try self.oneofByName(descriptor, name);
        return try descriptor.oneofFieldsAlloc(self.allocator, name);
    }

    pub fn oneofDescriptorFields(self: Reflection, descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error![]*const schema.FieldDescriptor {
        _ = try self.oneofContainingType(descriptor, oneof);
        return try descriptor.oneofFieldsAlloc(self.allocator, oneof.name);
    }

    pub fn oneofFieldCount(self: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!usize {
        _ = try self.oneofByName(descriptor, name);
        return descriptor.oneofFieldCount(name);
    }

    pub fn oneofDescriptorFieldCount(self: Reflection, descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor) Error!usize {
        _ = try self.oneofContainingType(descriptor, oneof);
        return descriptor.oneofFieldCount(oneof.name);
    }

    pub fn oneofFieldAt(self: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8, index: usize) Error!*const schema.FieldDescriptor {
        _ = try self.oneofByName(descriptor, name);
        return descriptor.oneofFieldAt(name, index) orelse error.UnknownField;
    }

    pub fn oneofDescriptorFieldAt(self: Reflection, descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor, index: usize) Error!*const schema.FieldDescriptor {
        _ = try self.oneofContainingType(descriptor, oneof);
        return descriptor.oneofFieldAt(oneof.name, index) orelse error.UnknownField;
    }

    pub fn oneofFieldIndex(self: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8, field: *const schema.FieldDescriptor) Error!usize {
        _ = try self.oneofByName(descriptor, name);
        return descriptor.oneofFieldIndex(name, field) orelse error.UnknownField;
    }

    pub fn oneofDescriptorFieldIndex(self: Reflection, descriptor: *const schema.MessageDescriptor, oneof: *const schema.OneofDescriptor, field: *const schema.FieldDescriptor) Error!usize {
        _ = try self.oneofContainingType(descriptor, oneof);
        return descriptor.oneofFieldIndex(oneof.name, field) orelse error.UnknownField;
    }

    pub fn enumValueByName(_: Reflection, descriptor: *const schema.EnumDescriptor, name: []const u8) Error!*const schema.EnumValueDescriptor {
        return descriptor.findValue(name) orelse error.UnknownEnum;
    }

    pub fn enumValueByFullName(self: Reflection, name: []const u8) Error!*const schema.EnumValueDescriptor {
        return self.registry.findEnumValue(name, null) orelse error.UnknownEnum;
    }

    pub fn enumValueByNumber(_: Reflection, descriptor: *const schema.EnumDescriptor, number: i32) Error!*const schema.EnumValueDescriptor {
        return descriptor.findValueByNumber(number) orelse error.UnknownEnum;
    }

    pub fn enumValuesByNumber(self: Reflection, descriptor: *const schema.EnumDescriptor, number: i32) Error![]*const schema.EnumValueDescriptor {
        return try descriptor.valuesByNumberAlloc(self.allocator, number);
    }

    pub fn enumAllowAlias(_: Reflection, descriptor: *const schema.EnumDescriptor) bool {
        return descriptor.allowAlias();
    }

    pub fn enumType(self: Reflection, descriptor: *const schema.EnumDescriptor) Error!schema.FeatureSet.EnumType {
        return descriptor.enumType(try self.fileOfEnum(descriptor));
    }

    pub fn enumReservedName(_: Reflection, descriptor: *const schema.EnumDescriptor, name: []const u8) bool {
        return descriptor.isReservedName(name);
    }

    pub fn enumReservedNameCount(_: Reflection, descriptor: *const schema.EnumDescriptor) usize {
        return descriptor.reserved_names.items.len;
    }

    pub fn enumReservedNameAt(_: Reflection, descriptor: *const schema.EnumDescriptor, index: usize) Error![]const u8 {
        if (index >= descriptor.reserved_names.items.len) return error.UnknownEnum;
        return descriptor.reserved_names.items[index];
    }

    pub fn enumReservedNameIndex(_: Reflection, descriptor: *const schema.EnumDescriptor, name: []const u8) Error!usize {
        for (descriptor.reserved_names.items, 0..) |reserved_name, index| {
            if (std.mem.eql(u8, reserved_name, name)) return index;
        }
        return error.UnknownEnum;
    }

    pub fn enumReservedNumber(_: Reflection, descriptor: *const schema.EnumDescriptor, number: i64) bool {
        return descriptor.isReservedNumber(number);
    }

    pub fn enumReservedRange(_: Reflection, descriptor: *const schema.EnumDescriptor, number: i64) ?*const schema.ReservedRange {
        return descriptor.reservedRangeForNumber(number);
    }

    pub fn enumReservedRangeCount(_: Reflection, descriptor: *const schema.EnumDescriptor) usize {
        return descriptor.reserved_ranges.items.len;
    }

    pub fn enumReservedRangeAt(_: Reflection, descriptor: *const schema.EnumDescriptor, index: usize) Error!schema.ReservedRange {
        if (index >= descriptor.reserved_ranges.items.len) return error.UnknownEnum;
        return descriptor.reserved_ranges.items[index];
    }

    pub fn enumReservedRangeIndex(_: Reflection, descriptor: *const schema.EnumDescriptor, range: schema.ReservedRange) Error!usize {
        for (descriptor.reserved_ranges.items, 0..) |candidate, index| {
            if (candidate.start == range.start and candidate.end == range.end) return index;
        }
        return error.UnknownEnum;
    }

    pub fn reservedRangeStart(_: Reflection, range: schema.ReservedRange) i64 {
        return range.start;
    }

    pub fn reservedRangeEnd(_: Reflection, range: schema.ReservedRange, max_end: i64) i64 {
        return range.effectiveEnd(max_end);
    }

    pub fn reservedRangeContains(_: Reflection, range: schema.ReservedRange, number: i64, max_end: i64) bool {
        return range.containsWithMax(number, max_end);
    }

    pub fn enumForField(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.EnumDescriptor {
        return try self.enumForKind(message_descriptor, field, field.kind);
    }

    fn enumForKind(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, kind: schema.FieldKind) Error!*const schema.EnumDescriptor {
        const enum_name, const declared_enum = switch (kind) {
            .enumeration => |name| .{ name, true },
            // Imported enum references can remain in the parser's message arm
            // until a registry-backed lookup resolves them.  Keep accepting
            // that representation so reflection over descriptor sets behaves
            // like C++ DescriptorPool-backed reflection.
            .message => |name| .{ name, false },
            else => return error.TypeMismatch,
        };
        const owner_file = try self.fileForFieldContext(message_descriptor, field);
        var scope_buf: [512]u8 = undefined;
        const scope = fieldLookupScope(owner_file, message_descriptor, field, &scope_buf);
        if (self.registry.findEnumVisible(owner_file, enum_name, scope)) |enum_desc| return enum_desc;
        if (self.registry.findEnum(enum_name, scope)) |enum_desc| return enum_desc;
        return if (declared_enum) error.UnknownEnum else error.TypeMismatch;
    }

    pub fn has(_: Reflection, message_value: *const dynamic.DynamicMessage, field: *const schema.FieldDescriptor) bool {
        return message_value.has(field);
    }

    pub fn messageReservedName(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) bool {
        return descriptor.isReservedName(name);
    }

    pub fn messageReservedNameCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.reserved_names.items.len;
    }

    pub fn messageReservedNameAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error![]const u8 {
        if (index >= descriptor.reserved_names.items.len) return error.UnknownField;
        return descriptor.reserved_names.items[index];
    }

    pub fn messageReservedNameIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!usize {
        for (descriptor.reserved_names.items, 0..) |reserved_name, index| {
            if (std.mem.eql(u8, reserved_name, name)) return index;
        }
        return error.UnknownField;
    }

    pub fn messageReservedNumber(_: Reflection, descriptor: *const schema.MessageDescriptor, number: i64) bool {
        return descriptor.isReservedNumber(number);
    }

    pub fn messageReservedRange(_: Reflection, descriptor: *const schema.MessageDescriptor, number: i64) ?*const schema.ReservedRange {
        return descriptor.reservedRangeForNumber(number);
    }

    pub fn messageReservedRangeCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.reserved_ranges.items.len;
    }

    pub fn messageReservedRangeAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error!schema.ReservedRange {
        if (index >= descriptor.reserved_ranges.items.len) return error.UnknownField;
        return descriptor.reserved_ranges.items[index];
    }

    pub fn messageReservedRangeIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, range: schema.ReservedRange) Error!usize {
        for (descriptor.reserved_ranges.items, 0..) |candidate, index| {
            if (candidate.start == range.start and candidate.end == range.end) return index;
        }
        return error.UnknownField;
    }

    pub fn messageExtensionRange(_: Reflection, descriptor: *const schema.MessageDescriptor, number: i64) ?*const schema.ExtensionRange {
        return descriptor.extensionRangeForNumber(number);
    }

    pub fn messageExtensionRangeCount(_: Reflection, descriptor: *const schema.MessageDescriptor) usize {
        return descriptor.extension_ranges.items.len;
    }

    pub fn messageExtensionRangeAt(_: Reflection, descriptor: *const schema.MessageDescriptor, index: usize) Error!*const schema.ExtensionRange {
        if (index >= descriptor.extension_ranges.items.len) return error.UnknownField;
        return &descriptor.extension_ranges.items[index];
    }

    pub fn messageExtensionRangeIndex(_: Reflection, descriptor: *const schema.MessageDescriptor, range: *const schema.ExtensionRange) Error!usize {
        for (descriptor.extension_ranges.items, 0..) |*candidate, index| {
            if (candidate == range) return index;
        }
        return error.UnknownField;
    }

    pub fn extensionRangeContainingType(_: Reflection, descriptor: *const schema.MessageDescriptor, range: *const schema.ExtensionRange) Error!*const schema.MessageDescriptor {
        if (!messageDirectlyContainsExtensionRange(descriptor, range)) return error.UnknownField;
        return descriptor;
    }

    pub fn messageExtensionRangeMaxExclusive(_: Reflection, descriptor: *const schema.MessageDescriptor) i64 {
        return descriptor.extensionRangeMaxExclusive();
    }

    pub fn extensionRangeStart(_: Reflection, range: *const schema.ExtensionRange) i64 {
        return range.start;
    }

    pub fn extensionRangeEnd(_: Reflection, descriptor: *const schema.MessageDescriptor, range: *const schema.ExtensionRange) Error!i64 {
        if (!messageDirectlyContainsExtensionRange(descriptor, range)) return error.UnknownField;
        return range.effectiveEnd(descriptor);
    }

    pub fn extensionRangeContains(self: Reflection, descriptor: *const schema.MessageDescriptor, range: *const schema.ExtensionRange, number: i64) Error!bool {
        const end = try self.extensionRangeEnd(descriptor, range);
        return number >= range.start and number < end;
    }

    pub fn extensionRangeHasVerification(_: Reflection, range: *const schema.ExtensionRange) bool {
        return range.verification != null;
    }

    pub fn extensionRangeOptions(_: Reflection, range: *const schema.ExtensionRange) []const schema.FieldOption {
        return range.options.items;
    }

    pub fn extensionRangeVerification(_: Reflection, range: *const schema.ExtensionRange) Error!schema.ExtensionRangeVerification {
        return range.verification orelse error.MissingField;
    }

    pub fn extensionRangeHasExplicitFeatures(_: Reflection, range: *const schema.ExtensionRange) bool {
        return range.features != null;
    }

    pub fn extensionRangeExplicitFeatures(_: Reflection, range: *const schema.ExtensionRange) Error!schema.FeatureSet {
        return range.features orelse error.MissingField;
    }

    pub fn extensionDeclaration(_: Reflection, range: *const schema.ExtensionRange, number: i32) ?schema.ExtensionDeclaration {
        return range.declarationForNumber(number);
    }

    pub fn extensionDeclarationCount(_: Reflection, range: *const schema.ExtensionRange) usize {
        return range.declarations.items.len;
    }

    pub fn extensionDeclarationAt(_: Reflection, range: *const schema.ExtensionRange, index: usize) Error!schema.ExtensionDeclaration {
        if (index >= range.declarations.items.len) return error.UnknownField;
        return range.declarations.items[index];
    }

    pub fn extensionDeclarationIndex(_: Reflection, range: *const schema.ExtensionRange, declaration: schema.ExtensionDeclaration) Error!usize {
        for (range.declarations.items, 0..) |candidate, index| {
            if (candidate.number == declaration.number) return index;
        }
        return error.UnknownField;
    }

    pub fn extensionDeclarationNumber(_: Reflection, declaration: schema.ExtensionDeclaration) i32 {
        return declaration.number;
    }

    pub fn extensionDeclarationFullName(_: Reflection, declaration: schema.ExtensionDeclaration) []const u8 {
        return declaration.full_name;
    }

    pub fn extensionDeclarationTypeName(_: Reflection, declaration: schema.ExtensionDeclaration) []const u8 {
        return declaration.type_name;
    }

    pub fn extensionDeclarationIsReserved(_: Reflection, declaration: schema.ExtensionDeclaration) bool {
        return declaration.reserved;
    }

    pub fn extensionDeclarationIsRepeated(_: Reflection, declaration: schema.ExtensionDeclaration) bool {
        return declaration.repeated;
    }

    pub fn messageIsExtensionNumber(_: Reflection, descriptor: *const schema.MessageDescriptor, number: i64) bool {
        return descriptor.isExtensionNumber(number);
    }

    pub fn hasField(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!bool {
        return self.has(message_value, try self.fieldByName(message_value.descriptor, name));
    }

    pub fn get(_: Reflection, message_value: *const dynamic.DynamicMessage, field: *const schema.FieldDescriptor) ?*const dynamic.FieldValue {
        return message_value.getByNumber(field.number);
    }

    pub fn fieldValueDescriptor(_: Reflection, field_value: *const dynamic.FieldValue) *const schema.FieldDescriptor {
        return field_value.descriptor;
    }

    pub fn fieldValueCount(_: Reflection, field_value: *const dynamic.FieldValue) usize {
        return field_value.values.items.len;
    }

    pub fn fieldValueAt(_: Reflection, field_value: *const dynamic.FieldValue, index: usize) Error!dynamic.Value {
        if (index >= field_value.values.items.len) return error.MissingField;
        return field_value.values.items[index];
    }

    pub fn fieldValueIndex(_: Reflection, field_value: *const dynamic.FieldValue, value: dynamic.Value) Error!usize {
        for (field_value.values.items, 0..) |candidate, index| {
            if (dynamic.valueEqual(candidate, value)) return index;
        }
        return error.MissingField;
    }

    pub fn valueTag(_: Reflection, value: dynamic.Value) ValueTag {
        return std.meta.activeTag(value);
    }

    pub fn getField(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!?*const dynamic.FieldValue {
        return self.get(message_value, try self.fieldByName(message_value.descriptor, name));
    }

    pub fn listFields(self: Reflection, message_value: *const dynamic.DynamicMessage) Error![]*const schema.FieldDescriptor {
        return try message_value.listFieldsAlloc(self.allocator);
    }

    pub fn unknownCount(_: Reflection, message_value: *const dynamic.DynamicMessage) usize {
        return message_value.unknownCount();
    }

    pub fn unknownFields(_: Reflection, message_value: *const dynamic.DynamicMessage) []const dynamic.UnknownField {
        return message_value.unknownFields();
    }

    pub fn unknownAt(_: Reflection, message_value: *const dynamic.DynamicMessage, index: usize) Error!dynamic.UnknownField {
        const fields = message_value.unknownFields();
        if (index >= fields.len) return error.UnknownField;
        return fields[index];
    }

    pub fn unknownIndex(_: Reflection, message_value: *const dynamic.DynamicMessage, unknown: dynamic.UnknownField) Error!usize {
        for (message_value.unknownFields(), 0..) |candidate, index| {
            if (candidate.number == unknown.number and
                candidate.wire_type == unknown.wire_type and
                std.mem.eql(u8, candidate.data, unknown.data))
            {
                return index;
            }
        }
        return error.UnknownField;
    }

    pub fn unknownFieldNumber(_: Reflection, unknown: dynamic.UnknownField) wire.FieldNumber {
        return unknown.number;
    }

    pub fn unknownFieldWireType(_: Reflection, unknown: dynamic.UnknownField) wire.WireType {
        return unknown.wire_type;
    }

    pub fn unknownFieldData(_: Reflection, unknown: dynamic.UnknownField) []const u8 {
        return unknown.data;
    }

    pub fn unknownFieldCountByNumber(_: Reflection, message_value: *const dynamic.DynamicMessage, number: wire.FieldNumber) usize {
        return message_value.unknownFieldCountByNumber(number);
    }

    pub fn hasUnknownFieldNumber(_: Reflection, message_value: *const dynamic.DynamicMessage, number: wire.FieldNumber) bool {
        return message_value.hasUnknownFieldNumber(number);
    }

    pub fn unknownFieldNumbers(self: Reflection, message_value: *const dynamic.DynamicMessage) Error![]wire.FieldNumber {
        return try message_value.unknownFieldNumbersAlloc(self.allocator);
    }

    pub fn unknownFieldNumberRuns(self: Reflection, message_value: *const dynamic.DynamicMessage) Error![]wire.RawFieldNumberRun {
        return try message_value.unknownFieldNumberRunsAlloc(self.allocator);
    }

    pub fn unknownFieldNumberRunNumber(_: Reflection, run: wire.RawFieldNumberRun) wire.FieldNumber {
        return run.number;
    }

    pub fn unknownFieldNumberRunCount(_: Reflection, run: wire.RawFieldNumberRun) usize {
        return run.count;
    }

    pub fn unknownByNumber(_: Reflection, message_value: *const dynamic.DynamicMessage, number: wire.FieldNumber) []const dynamic.UnknownField {
        return message_value.unknownByNumber(number);
    }

    pub fn unknownByNumberAlloc(self: Reflection, message_value: *const dynamic.DynamicMessage, number: wire.FieldNumber) Error![]dynamic.UnknownField {
        return try message_value.unknownByNumberAlloc(self.allocator, number);
    }

    pub fn isInitialized(_: Reflection, message_value: *const dynamic.DynamicMessage) bool {
        message_value.validateRequired() catch return false;
        return true;
    }

    pub fn validateInitialized(_: Reflection, message_value: *const dynamic.DynamicMessage) Error!void {
        return try message_value.validateRequired();
    }

    pub fn missingRequiredFieldPath(self: Reflection, message_value: *const dynamic.DynamicMessage) Error!?[]u8 {
        return try message_value.missingRequiredFieldPath(self.allocator);
    }

    pub fn getOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, field: *const schema.FieldDescriptor) Error!dynamic.DefaultValue {
        const owner_file = try self.fileOfMessage(message_value.descriptor);
        return message_value.getOrDefaultWithRegistry(owner_file, self.registry, field);
    }

    pub fn getFieldOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!dynamic.DefaultValue {
        return try self.getOrDefault(message_value, try self.fieldByName(message_value.descriptor, name));
    }

    pub fn repeatedLen(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!usize {
        const field = try self.fieldByName(message_value.descriptor, name);
        return if (message_value.getByNumber(field.number)) |value| value.values.items.len else 0;
    }

    pub fn repeatedValue(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!dynamic.Value {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = message_value.getByNumber(field.number) orelse return error.MissingField;
        if (index >= value.values.items.len) return error.MissingField;
        return value.values.items[index];
    }

    pub fn repeatedMessage(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!*dynamic.DynamicMessage {
        const field = try self.fieldByName(message_value.descriptor, name);
        if (field.cardinality != .repeated or field.kind != .message) return error.TypeMismatch;
        return switch (try self.repeatedValue(message_value, name, index)) {
            .message => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn mutableRepeatedMessage(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize) Error!*dynamic.DynamicMessage {
        return try self.repeatedMessage(message_value, name, index);
    }

    pub fn repeatedGroup(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!*dynamic.DynamicMessage {
        const field = try self.fieldByName(message_value.descriptor, name);
        if (field.cardinality != .repeated or field.kind != .group) return error.TypeMismatch;
        return switch (try self.repeatedValue(message_value, name, index)) {
            .group => |value| value,
            else => error.TypeMismatch,
        };
    }

    pub fn mutableRepeatedGroup(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize) Error!*dynamic.DynamicMessage {
        return try self.repeatedGroup(message_value, name, index);
    }

    pub fn repeatedInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!i32 {
        return try self.getRepeatedScalar(i32, message_value, name, index, .int32);
    }

    pub fn repeatedInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!i64 {
        return try self.getRepeatedScalar(i64, message_value, name, index, .int64);
    }

    pub fn repeatedUInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!u32 {
        return try self.getRepeatedScalar(u32, message_value, name, index, .uint32);
    }

    pub fn repeatedUInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!u64 {
        return try self.getRepeatedScalar(u64, message_value, name, index, .uint64);
    }

    pub fn repeatedSInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!i32 {
        return try self.getRepeatedScalar(i32, message_value, name, index, .sint32);
    }

    pub fn repeatedSInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!i64 {
        return try self.getRepeatedScalar(i64, message_value, name, index, .sint64);
    }

    pub fn repeatedFixed32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!u32 {
        return try self.getRepeatedScalar(u32, message_value, name, index, .fixed32);
    }

    pub fn repeatedFixed64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!u64 {
        return try self.getRepeatedScalar(u64, message_value, name, index, .fixed64);
    }

    pub fn repeatedSFixed32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!i32 {
        return try self.getRepeatedScalar(i32, message_value, name, index, .sfixed32);
    }

    pub fn repeatedSFixed64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!i64 {
        return try self.getRepeatedScalar(i64, message_value, name, index, .sfixed64);
    }

    pub fn repeatedFloat(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!f32 {
        return try self.getRepeatedScalar(f32, message_value, name, index, .float);
    }

    pub fn repeatedDouble(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!f64 {
        return try self.getRepeatedScalar(f64, message_value, name, index, .double);
    }

    pub fn repeatedBool(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!bool {
        return try self.getRepeatedScalar(bool, message_value, name, index, .boolean);
    }

    pub fn repeatedString(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error![]const u8 {
        return try self.getRepeatedScalar([]const u8, message_value, name, index, .string);
    }

    pub fn repeatedBytes(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error![]const u8 {
        return try self.getRepeatedScalar([]const u8, message_value, name, index, .bytes);
    }

    pub fn repeatedEnum(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!i32 {
        return try self.getRepeatedScalar(i32, message_value, name, index, .enumeration);
    }

    pub fn setRepeatedInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: i32) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .int32, value);
    }

    pub fn setRepeatedInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: i64) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .int64, value);
    }

    pub fn setRepeatedUInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: u32) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .uint32, value);
    }

    pub fn setRepeatedUInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: u64) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .uint64, value);
    }

    pub fn setRepeatedSInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: i32) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .sint32, value);
    }

    pub fn setRepeatedSInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: i64) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .sint64, value);
    }

    pub fn setRepeatedFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: u32) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .fixed32, value);
    }

    pub fn setRepeatedFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: u64) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .fixed64, value);
    }

    pub fn setRepeatedSFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: i32) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .sfixed32, value);
    }

    pub fn setRepeatedSFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: i64) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .sfixed64, value);
    }

    pub fn setRepeatedFloat(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: f32) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .float, value);
    }

    pub fn setRepeatedDouble(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: f64) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .double, value);
    }

    pub fn setRepeatedBool(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: bool) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .boolean, value);
    }

    pub fn setRepeatedString(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: []const u8) Error!bool {
        const owned = try self.allocator.dupe(u8, value);
        return try self.setRepeatedValue(message_value, name, index, .{ .string = owned });
    }

    pub fn setRepeatedBytes(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: []const u8) Error!bool {
        const owned = try self.allocator.dupe(u8, value);
        return try self.setRepeatedValue(message_value, name, index, .{ .bytes = owned });
    }

    pub fn setRepeatedEnum(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: i32) Error!bool {
        return try self.setRepeatedScalar(message_value, name, index, .enumeration, value);
    }

    pub fn setRepeatedEnumByName(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value_name: []const u8) Error!bool {
        const field = try self.fieldByName(message_value.descriptor, name);
        const enum_desc = try self.enumForField(message_value.descriptor, field);
        const value = try self.enumValueByName(enum_desc, value_name);
        return try self.setRepeatedValue(message_value, name, index, .{ .enumeration = value.number });
    }

    pub fn removeRepeatedValue(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize) Error!bool {
        return message_value.removeRepeatedValue(try self.fieldByName(message_value.descriptor, name), index);
    }

    pub fn setRepeatedValue(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, value: dynamic.Value) Error!bool {
        var owned = value;
        var owns_owned = true;
        defer if (owns_owned) dynamic.deinitValue(&owned, self.allocator);
        const field = try self.fieldByName(message_value.descriptor, name);
        try self.validateValueForField(message_value.descriptor, field, owned);
        if (!message_value.setRepeatedValue(field, index, owned)) return false;
        owns_owned = false;
        return true;
    }

    pub fn swapRepeatedValues(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, lhs: usize, rhs: usize) Error!bool {
        return message_value.swapRepeatedValues(try self.fieldByName(message_value.descriptor, name), lhs, rhs);
    }

    pub fn mapLen(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!usize {
        const field = try self.fieldByName(message_value.descriptor, name);
        if (field.kind != .map) return error.TypeMismatch;
        return if (message_value.getByNumber(field.number)) |entry| entry.values.items.len else 0;
    }

    pub fn mapEntryAt(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!*const dynamic.MapEntry {
        const field = try self.fieldByName(message_value.descriptor, name);
        if (field.kind != .map) return error.TypeMismatch;
        const value = message_value.getByNumber(field.number) orelse return error.MissingField;
        if (index >= value.values.items.len) return error.MissingField;
        return switch (value.values.items[index]) {
            .map_entry => |entry| entry,
            else => error.TypeMismatch,
        };
    }

    pub fn mapEntryKey(_: Reflection, entry: *const dynamic.MapEntry) dynamic.Value {
        return entry.key;
    }

    pub fn mapEntryValue(_: Reflection, entry: *const dynamic.MapEntry) dynamic.Value {
        return entry.value;
    }

    pub fn mapEntries(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]*const dynamic.MapEntry {
        const field = try self.fieldByName(message_value.descriptor, name);
        if (field.kind != .map) return error.TypeMismatch;
        const value = message_value.getByNumber(field.number) orelse return try self.allocator.alloc(*const dynamic.MapEntry, 0);
        var entries = try self.allocator.alloc(*const dynamic.MapEntry, value.values.items.len);
        errdefer self.allocator.free(entries);
        for (value.values.items, 0..) |item, index| {
            entries[index] = switch (item) {
                .map_entry => |entry| entry,
                else => return error.TypeMismatch,
            };
        }
        return entries;
    }

    pub fn mapKeys(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]dynamic.Value {
        const entries = try self.mapEntries(message_value, name);
        defer self.allocator.free(entries);
        var keys = try self.allocator.alloc(dynamic.Value, entries.len);
        errdefer self.allocator.free(keys);
        for (entries, 0..) |entry, index| keys[index] = entry.key;
        return keys;
    }

    pub fn mapValues(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]dynamic.Value {
        const entries = try self.mapEntries(message_value, name);
        defer self.allocator.free(entries);
        var values = try self.allocator.alloc(dynamic.Value, entries.len);
        errdefer self.allocator.free(values);
        for (entries, 0..) |entry, index| values[index] = entry.value;
        return values;
    }

    pub fn mapContains(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, key: dynamic.Value) Error!bool {
        return (try self.mapEntry(message_value, name, key)) != null;
    }

    pub fn mapEntry(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, key: dynamic.Value) Error!?*const dynamic.MapEntry {
        const field = try self.fieldByName(message_value.descriptor, name);
        try self.validateMapKey(field, key);
        return message_value.getMapEntry(field, key);
    }

    pub fn mapValue(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, key: dynamic.Value) Error!?dynamic.Value {
        const entry = (try self.mapEntry(message_value, name, key)) orelse return null;
        return entry.value;
    }

    pub fn mapEnumValueName(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, key: dynamic.Value) Error!?[]const u8 {
        const field = try self.fieldByName(message_value.descriptor, name);
        try self.validateMapKey(field, key);
        const owner_file = try self.fileOfMessage(message_value.descriptor);
        return try message_value.getEnumMapValueNameWithRegistry(owner_file, self.registry, field, key);
    }

    pub fn stringMapEntry(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, key: []const u8) Error!?*const dynamic.MapEntry {
        const owned_key = try self.allocator.dupe(u8, key);
        defer self.allocator.free(owned_key);
        return try self.mapEntry(message_value, name, .{ .string = owned_key });
    }

    pub fn stringMapValue(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, key: []const u8) Error!?dynamic.Value {
        const entry = (try self.stringMapEntry(message_value, name, key)) orelse return null;
        return entry.value;
    }

    pub fn stringMapContains(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, key: []const u8) Error!bool {
        return (try self.stringMapEntry(message_value, name, key)) != null;
    }

    pub fn stringMapEnumValueName(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, key: []const u8) Error!?[]const u8 {
        const owned_key = try self.allocator.dupe(u8, key);
        defer self.allocator.free(owned_key);
        return try self.mapEnumValueName(message_value, name, .{ .string = owned_key });
    }

    /// Replace a singular field or append/replace map entries using an owned
    /// dynamic value. String, bytes, message, group, and map-entry payloads are
    /// consumed on success and freed on failure.
    pub fn set(self: Reflection, message_value: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor, value: dynamic.Value) Error!void {
        var owned = value;
        errdefer dynamic.deinitValue(&owned, self.allocator);
        try self.validateValueForField(message_value.descriptor, field, owned);
        // DynamicMessage.add already replaces singular values and map entries.
        // Avoid clearing those fields first: if allocation fails while adding
        // the replacement, callers should not lose the previous value.
        if (field.cardinality == .repeated and field.kind != .map) self.clear(message_value, field);
        try message_value.add(field, owned);
    }

    /// Add an owned dynamic value. String, bytes, message, group, and map-entry
    /// payloads are consumed on success and freed on failure.
    pub fn add(self: Reflection, message_value: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor, value: dynamic.Value) Error!void {
        var owned = value;
        errdefer dynamic.deinitValue(&owned, message_value.allocator);
        try self.validateValueForField(message_value.descriptor, field, owned);
        try message_value.add(field, owned);
    }

    pub fn mergeFrom(self: Reflection, message_value: *dynamic.DynamicMessage, other: *const dynamic.DynamicMessage) Error!void {
        if (message_value.descriptor != other.descriptor) return error.TypeMismatch;
        if (message_value == other) {
            // DynamicMessage.mergeFrom appends/replaces through the destination
            // field array while reading the source.  Snapshot self-merges first
            // so aliases behave like C++ Message::MergeFrom(message) rather
            // than depending on ArrayList reallocation details.
            var snapshot = try other.cloneOwned(self.allocator);
            defer snapshot.deinit();
            return try message_value.mergeFrom(&snapshot);
        }
        return try message_value.mergeFrom(other);
    }

    pub fn copyFrom(self: Reflection, message_value: *dynamic.DynamicMessage, other: *const dynamic.DynamicMessage) Error!void {
        if (message_value.descriptor != other.descriptor) return error.TypeMismatch;
        if (message_value == other) return;
        message_value.clear();
        return try self.mergeFrom(message_value, other);
    }

    pub fn cloneMessage(self: Reflection, message_value: *const dynamic.DynamicMessage) Error!dynamic.DynamicMessage {
        return try message_value.cloneOwned(self.allocator);
    }

    pub fn clear(self: Reflection, message_value: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor) void {
        _ = self;
        _ = message_value.clearField(field);
    }

    pub fn clearField(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8) Error!void {
        self.clear(message_value, try self.fieldByName(message_value.descriptor, name));
    }

    pub fn appendUnknownRaw(_: Reflection, message_value: *dynamic.DynamicMessage, raw: []const u8) Error!void {
        return try message_value.appendUnknownRaw(raw);
    }

    pub fn clearUnknownFieldsByNumber(_: Reflection, message_value: *dynamic.DynamicMessage, number: wire.FieldNumber) void {
        message_value.clearUnknownFieldsByNumber(number);
    }

    pub fn clearUnknownFields(_: Reflection, message_value: *dynamic.DynamicMessage) void {
        message_value.clearUnknownFields();
    }

    pub fn clearOneof(self: Reflection, message_value: *dynamic.DynamicMessage, oneof_name: []const u8) Error!bool {
        _ = try self.oneofByName(message_value.descriptor, oneof_name);
        return message_value.clearOneof(oneof_name);
    }

    pub fn hasOneof(self: Reflection, message_value: *const dynamic.DynamicMessage, oneof_name: []const u8) Error!bool {
        _ = try self.oneofByName(message_value.descriptor, oneof_name);
        return message_value.hasOneof(oneof_name);
    }

    pub fn whichOneof(_: Reflection, message_value: *const dynamic.DynamicMessage, oneof_name: []const u8) ?*const schema.FieldDescriptor {
        return message_value.whichOneof(oneof_name);
    }

    fn setScalar(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, comptime tag: ValueTag, value: anytype) Error!void {
        try self.set(message_value, try self.fieldByName(message_value.descriptor, name), @unionInit(dynamic.Value, @tagName(tag), value));
    }

    fn addScalar(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, comptime tag: ValueTag, value: anytype) Error!void {
        try self.add(message_value, try self.fieldByName(message_value.descriptor, name), @unionInit(dynamic.Value, @tagName(tag), value));
    }

    fn setRepeatedScalar(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, index: usize, comptime tag: ValueTag, value: anytype) Error!bool {
        return try self.setRepeatedValue(message_value, name, index, @unionInit(dynamic.Value, @tagName(tag), value));
    }

    fn getScalar(self: Reflection, comptime T: type, message_value: *const dynamic.DynamicMessage, name: []const u8, comptime tag: ValueTag) Error!T {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = lastValue(message_value, field) orelse return error.MissingField;
        if (std.meta.activeTag(value) != tag) return error.TypeMismatch;
        return @field(value, @tagName(tag));
    }

    fn getRepeatedScalar(self: Reflection, comptime T: type, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize, comptime tag: ValueTag) Error!T {
        const value = try self.repeatedValue(message_value, name, index);
        if (std.meta.activeTag(value) != tag) return error.TypeMismatch;
        return @field(value, @tagName(tag));
    }

    fn getScalarOrDefault(self: Reflection, comptime T: type, message_value: *const dynamic.DynamicMessage, name: []const u8, comptime tag: DefaultTag) Error!T {
        const value = try self.getFieldOrDefault(message_value, name);
        if (std.meta.activeTag(value) != tag) return error.TypeMismatch;
        return @field(value, @tagName(tag));
    }

    pub fn setInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.setScalar(message_value, name, .int32, value);
    }

    pub fn addInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.addScalar(message_value, name, .int32, value);
    }

    pub fn getInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalar(i32, message_value, name, .int32);
    }

    pub fn getInt32OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalarOrDefault(i32, message_value, name, .int32);
    }

    pub fn setInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.setScalar(message_value, name, .int64, value);
    }

    pub fn addInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.addScalar(message_value, name, .int64, value);
    }

    pub fn getInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalar(i64, message_value, name, .int64);
    }

    pub fn getInt64OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalarOrDefault(i64, message_value, name, .int64);
    }

    pub fn setUInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u32) Error!void {
        try self.setScalar(message_value, name, .uint32, value);
    }

    pub fn addUInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u32) Error!void {
        try self.addScalar(message_value, name, .uint32, value);
    }

    pub fn getUInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u32 {
        return try self.getScalar(u32, message_value, name, .uint32);
    }

    pub fn getUInt32OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u32 {
        return try self.getScalarOrDefault(u32, message_value, name, .uint32);
    }

    pub fn setUInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u64) Error!void {
        try self.setScalar(message_value, name, .uint64, value);
    }

    pub fn addUInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u64) Error!void {
        try self.addScalar(message_value, name, .uint64, value);
    }

    pub fn getUInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u64 {
        return try self.getScalar(u64, message_value, name, .uint64);
    }

    pub fn getUInt64OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u64 {
        return try self.getScalarOrDefault(u64, message_value, name, .uint64);
    }

    pub fn setSInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.setScalar(message_value, name, .sint32, value);
    }

    pub fn addSInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.addScalar(message_value, name, .sint32, value);
    }

    pub fn getSInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalar(i32, message_value, name, .sint32);
    }

    pub fn getSInt32OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalarOrDefault(i32, message_value, name, .sint32);
    }

    pub fn setSInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.setScalar(message_value, name, .sint64, value);
    }

    pub fn addSInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.addScalar(message_value, name, .sint64, value);
    }

    pub fn getSInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalar(i64, message_value, name, .sint64);
    }

    pub fn getSInt64OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalarOrDefault(i64, message_value, name, .sint64);
    }

    pub fn setFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u32) Error!void {
        try self.setScalar(message_value, name, .fixed32, value);
    }

    pub fn addFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u32) Error!void {
        try self.addScalar(message_value, name, .fixed32, value);
    }

    pub fn getFixed32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u32 {
        return try self.getScalar(u32, message_value, name, .fixed32);
    }

    pub fn getFixed32OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u32 {
        return try self.getScalarOrDefault(u32, message_value, name, .fixed32);
    }

    pub fn setFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u64) Error!void {
        try self.setScalar(message_value, name, .fixed64, value);
    }

    pub fn addFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u64) Error!void {
        try self.addScalar(message_value, name, .fixed64, value);
    }

    pub fn getFixed64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u64 {
        return try self.getScalar(u64, message_value, name, .fixed64);
    }

    pub fn getFixed64OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u64 {
        return try self.getScalarOrDefault(u64, message_value, name, .fixed64);
    }

    pub fn setSFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.setScalar(message_value, name, .sfixed32, value);
    }

    pub fn addSFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.addScalar(message_value, name, .sfixed32, value);
    }

    pub fn getSFixed32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalar(i32, message_value, name, .sfixed32);
    }

    pub fn getSFixed32OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalarOrDefault(i32, message_value, name, .sfixed32);
    }

    pub fn setSFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.setScalar(message_value, name, .sfixed64, value);
    }

    pub fn addSFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.addScalar(message_value, name, .sfixed64, value);
    }

    pub fn getSFixed64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalar(i64, message_value, name, .sfixed64);
    }

    pub fn getSFixed64OrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalarOrDefault(i64, message_value, name, .sfixed64);
    }

    pub fn setFloat(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: f32) Error!void {
        try self.setScalar(message_value, name, .float, value);
    }

    pub fn addFloat(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: f32) Error!void {
        try self.addScalar(message_value, name, .float, value);
    }

    pub fn getFloat(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!f32 {
        return try self.getScalar(f32, message_value, name, .float);
    }

    pub fn getFloatOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!f32 {
        return try self.getScalarOrDefault(f32, message_value, name, .float);
    }

    pub fn setDouble(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: f64) Error!void {
        try self.setScalar(message_value, name, .double, value);
    }

    pub fn addDouble(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: f64) Error!void {
        try self.addScalar(message_value, name, .double, value);
    }

    pub fn getDouble(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!f64 {
        return try self.getScalar(f64, message_value, name, .double);
    }

    pub fn getDoubleOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!f64 {
        return try self.getScalarOrDefault(f64, message_value, name, .double);
    }

    pub fn setBool(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: bool) Error!void {
        try self.setScalar(message_value, name, .boolean, value);
    }

    pub fn addBool(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: bool) Error!void {
        try self.addScalar(message_value, name, .boolean, value);
    }

    pub fn getBool(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!bool {
        return try self.getScalar(bool, message_value, name, .boolean);
    }

    pub fn getBoolOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!bool {
        return try self.getScalarOrDefault(bool, message_value, name, .boolean);
    }

    pub fn setString(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.set(message_value, field, .{ .string = owned });
    }

    pub fn addString(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.add(message_value, field, .{ .string = owned });
    }

    pub fn getString(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]const u8 {
        return try self.getScalar([]const u8, message_value, name, .string);
    }

    pub fn getStringOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]const u8 {
        return try self.getScalarOrDefault([]const u8, message_value, name, .string);
    }

    pub fn setBytes(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.set(message_value, field, .{ .bytes = owned });
    }

    pub fn addBytes(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.add(message_value, field, .{ .bytes = owned });
    }

    pub fn getBytes(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]const u8 {
        return try self.getScalar([]const u8, message_value, name, .bytes);
    }

    pub fn getBytesOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]const u8 {
        return try self.getScalarOrDefault([]const u8, message_value, name, .bytes);
    }

    pub fn setEnum(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.setScalar(message_value, name, .enumeration, value);
    }

    pub fn addEnum(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.addScalar(message_value, name, .enumeration, value);
    }

    pub fn setEnumByName(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value_name: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const enum_desc = try self.enumForField(message_value.descriptor, field);
        const value = try self.enumValueByName(enum_desc, value_name);
        try self.set(message_value, field, .{ .enumeration = value.number });
    }

    pub fn addEnumByName(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value_name: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const enum_desc = try self.enumForField(message_value.descriptor, field);
        const value = try self.enumValueByName(enum_desc, value_name);
        try self.add(message_value, field, .{ .enumeration = value.number });
    }

    pub fn getEnum(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalar(i32, message_value, name, .enumeration);
    }

    pub fn getEnumOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return switch (try self.getFieldOrDefault(message_value, name)) {
            .enumeration => |number| number,
            else => error.TypeMismatch,
        };
    }

    pub fn getEnumNameOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!?[]const u8 {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owner_file = try self.fileOfMessage(message_value.descriptor);
        return message_value.getEnumNameOrDefaultWithRegistry(owner_file, self.registry, field);
    }

    pub fn repeatedEnumNames(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]const []const u8 {
        const field = try self.fieldByName(message_value.descriptor, name);
        if (field.cardinality != .repeated or field.kind == .map) return error.TypeMismatch;
        const owner_file = try self.fileOfMessage(message_value.descriptor);
        return try message_value.getEnumNamesWithRegistry(self.allocator, owner_file, self.registry, field);
    }

    pub fn repeatedEnumName(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!?[]const u8 {
        const field = try self.fieldByName(message_value.descriptor, name);
        const number = try self.repeatedEnum(message_value, name, index);
        const descriptor = try self.enumForField(message_value.descriptor, field);
        if (descriptor.findValueByNumber(number)) |value| return value.name;
        return null;
    }

    pub fn getEnumValue(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!*const schema.EnumValueDescriptor {
        const field = try self.fieldByName(message_value.descriptor, name);
        const number = try self.getEnum(message_value, name);
        const descriptor = try self.enumForField(message_value.descriptor, field);
        return try self.enumValueByNumber(descriptor, number);
    }

    pub fn getEnumValueOrDefault(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!*const schema.EnumValueDescriptor {
        const field = try self.fieldByName(message_value.descriptor, name);
        const number = try self.getEnumOrDefault(message_value, name);
        const descriptor = try self.enumForField(message_value.descriptor, field);
        return try self.enumValueByNumber(descriptor, number);
    }

    pub fn repeatedEnumValue(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!*const schema.EnumValueDescriptor {
        const field = try self.fieldByName(message_value.descriptor, name);
        const number = try self.repeatedEnum(message_value, name, index);
        const descriptor = try self.enumForField(message_value.descriptor, field);
        return try self.enumValueByNumber(descriptor, number);
    }

    pub fn setMessageOwned(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: *dynamic.DynamicMessage) Error!void {
        try self.set(message_value, try self.fieldByName(message_value.descriptor, name), .{ .message = value });
    }

    pub fn addMessageOwned(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: *dynamic.DynamicMessage) Error!void {
        try self.add(message_value, try self.fieldByName(message_value.descriptor, name), .{ .message = value });
    }

    pub fn getMessage(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!*dynamic.DynamicMessage {
        return try self.getScalar(*dynamic.DynamicMessage, message_value, name, .message);
    }

    pub fn mutableMessage(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8) Error!*dynamic.DynamicMessage {
        if (self.getMessage(message_value, name)) |existing| return existing else |err| switch (err) {
            error.MissingField => {},
            else => return err,
        }
        const field = try self.fieldByName(message_value.descriptor, name);
        const nested = try self.allocator.create(dynamic.DynamicMessage);
        errdefer self.allocator.destroy(nested);
        nested.* = try self.newMessageForField(message_value.descriptor, field);
        var owns_nested = true;
        errdefer if (owns_nested) nested.deinit();
        try self.set(message_value, field, .{ .message = nested });
        owns_nested = false;
        return nested;
    }

    pub fn addMutableMessage(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8) Error!*dynamic.DynamicMessage {
        const field = try self.fieldByName(message_value.descriptor, name);
        if (field.cardinality != .repeated) return error.TypeMismatch;
        const nested = try self.allocator.create(dynamic.DynamicMessage);
        errdefer self.allocator.destroy(nested);
        nested.* = try self.newMessageForField(message_value.descriptor, field);
        var owns_nested = true;
        errdefer if (owns_nested) nested.deinit();
        try self.add(message_value, field, .{ .message = nested });
        owns_nested = false;
        return nested;
    }

    pub fn setGroupOwned(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: *dynamic.DynamicMessage) Error!void {
        try self.set(message_value, try self.fieldByName(message_value.descriptor, name), .{ .group = value });
    }

    pub fn addGroupOwned(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: *dynamic.DynamicMessage) Error!void {
        try self.add(message_value, try self.fieldByName(message_value.descriptor, name), .{ .group = value });
    }

    pub fn getGroup(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!*dynamic.DynamicMessage {
        return try self.getScalar(*dynamic.DynamicMessage, message_value, name, .group);
    }

    pub fn mutableGroup(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8) Error!*dynamic.DynamicMessage {
        if (self.getGroup(message_value, name)) |existing| return existing else |err| switch (err) {
            error.MissingField => {},
            else => return err,
        }
        const field = try self.fieldByName(message_value.descriptor, name);
        const nested = try self.allocator.create(dynamic.DynamicMessage);
        errdefer self.allocator.destroy(nested);
        nested.* = try self.newGroupForField(message_value.descriptor, field);
        var owns_nested = true;
        errdefer if (owns_nested) nested.deinit();
        try self.set(message_value, field, .{ .group = nested });
        owns_nested = false;
        return nested;
    }

    pub fn addMutableGroup(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8) Error!*dynamic.DynamicMessage {
        const field = try self.fieldByName(message_value.descriptor, name);
        if (field.cardinality != .repeated) return error.TypeMismatch;
        const nested = try self.allocator.create(dynamic.DynamicMessage);
        errdefer self.allocator.destroy(nested);
        nested.* = try self.newGroupForField(message_value.descriptor, field);
        var owns_nested = true;
        errdefer if (owns_nested) nested.deinit();
        try self.add(message_value, field, .{ .group = nested });
        owns_nested = false;
        return nested;
    }

    pub fn putMapEntryOwned(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: dynamic.Value, value: dynamic.Value) Error!void {
        var owned_key = key;
        var owns_key = true;
        errdefer if (owns_key) dynamic.deinitValue(&owned_key, self.allocator);
        var owned_value = value;
        var owns_value = true;
        errdefer if (owns_value) dynamic.deinitValue(&owned_value, self.allocator);
        const field = try self.fieldByName(message_value.descriptor, name);
        try self.validateMapEntryParts(message_value.descriptor, field, owned_key, owned_value);
        const entry = try self.allocator.create(dynamic.MapEntry);
        var owns_entry = true;
        errdefer if (owns_entry) self.allocator.destroy(entry);
        entry.* = .{ .key = owned_key, .value = owned_value };
        owns_key = false;
        owns_value = false;
        errdefer if (owns_entry) entry.deinit(self.allocator);
        try message_value.add(field, .{ .map_entry = entry });
        owns_entry = false;
    }

    pub fn putStringInt32MapEntry(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: []const u8, value: i32) Error!void {
        const owned_key = try self.allocator.dupe(u8, key);
        try self.putMapEntryOwned(message_value, name, .{ .string = owned_key }, .{ .int32 = value });
    }

    pub fn clearMapEntry(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: dynamic.Value) Error!bool {
        return message_value.clearMapEntry(try self.fieldByName(message_value.descriptor, name), key);
    }

    pub fn clearStringMapEntry(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: []const u8) Error!bool {
        const owned_key = try self.allocator.dupe(u8, key);
        defer self.allocator.free(owned_key);
        return try self.clearMapEntry(message_value, name, .{ .string = owned_key });
    }

    fn validateValueForField(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, value: dynamic.Value) Error!void {
        if (field.kind == .map) {
            const entry = switch (value) {
                .map_entry => |entry| entry,
                else => return error.TypeMismatch,
            };
            return try self.validateMapEntryParts(message_descriptor, field, entry.key, entry.value);
        }
        if (value == .map_entry) return error.TypeMismatch;
        try self.validateValueForKind(message_descriptor, field, field.kind, value);
    }

    fn validateMapEntryParts(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, key: dynamic.Value, value: dynamic.Value) Error!void {
        try self.validateMapKey(field, key);
        const map_type = field.kind.map;
        try self.validateValueForKind(message_descriptor, field, map_type.value.*, value);
    }

    fn validateMapKey(_: Reflection, field: *const schema.FieldDescriptor, key: dynamic.Value) Error!void {
        const map_type = switch (field.kind) {
            .map => |map_type| map_type,
            else => return error.TypeMismatch,
        };
        if (!valueMatchesScalar(map_type.key, key)) return error.TypeMismatch;
    }

    fn validateValueForKind(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, kind: schema.FieldKind, value: dynamic.Value) Error!void {
        switch (kind) {
            .scalar => |scalar| if (!valueMatchesScalar(scalar, value)) return error.TypeMismatch,
            .enumeration => if (value != .enumeration) return error.TypeMismatch,
            .message => |type_name| {
                if (self.enumForKind(message_descriptor, field, kind)) |_| {
                    if (value != .enumeration) return error.TypeMismatch;
                    return;
                } else |err| switch (err) {
                    error.TypeMismatch, error.UnknownEnum => {},
                    else => return err,
                }
                try self.validateMessageValue(message_descriptor, field, type_name, value);
            },
            .group => |type_name| try self.validateGroupValue(message_descriptor, field, type_name, value),
            .map => return error.TypeMismatch,
        }
    }

    fn validateMessageValue(self: Reflection, parent_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, type_name: []const u8, value: dynamic.Value) Error!void {
        const nested_message = switch (value) {
            .message => |nested| nested,
            else => return error.TypeMismatch,
        };
        const descriptor = try self.messageForFieldType(parent_descriptor, field, type_name);
        if (nested_message.descriptor != descriptor) return error.TypeMismatch;
    }

    fn validateGroupValue(self: Reflection, parent_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, type_name: []const u8, value: dynamic.Value) Error!void {
        const nested_message = switch (value) {
            .group => |nested| nested,
            else => return error.TypeMismatch,
        };
        const descriptor = try self.messageForFieldType(parent_descriptor, field, type_name);
        if (nested_message.descriptor != descriptor) return error.TypeMismatch;
    }

    fn messageForFieldType(self: Reflection, parent_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, type_name: []const u8) Error!*const schema.MessageDescriptor {
        const owner_file = try self.fileForFieldContext(parent_descriptor, field);
        var scope_buf: [512]u8 = undefined;
        const scope = fieldLookupScope(owner_file, parent_descriptor, field, &scope_buf);
        if (self.registry.findMessageVisible(owner_file, type_name, scope)) |msg_desc| return msg_desc;
        if (self.registry.findMessage(type_name, scope)) |msg_desc| return msg_desc;
        return error.TypeMismatch;
    }

    fn fileForFieldContext(self: Reflection, message_descriptor: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!*const schema.FileDescriptor {
        if (field.extendee != null) return self.registry.fileContainingExtension(field) orelse error.UnknownField;
        return try self.fileOfMessage(message_descriptor);
    }
};

fn lastValue(message_value: *const dynamic.DynamicMessage, field: *const schema.FieldDescriptor) ?dynamic.Value {
    const field_value = message_value.getByNumber(field.number) orelse return null;
    if (field_value.values.items.len == 0) return null;
    return field_value.values.items[field_value.values.items.len - 1];
}

fn valueMatchesScalar(scalar: schema.ScalarType, value: dynamic.Value) bool {
    return switch (scalar) {
        .double => value == .double,
        .float => value == .float,
        .int32 => value == .int32,
        .int64 => value == .int64,
        .uint32 => value == .uint32,
        .uint64 => value == .uint64,
        .sint32 => value == .sint32,
        .sint64 => value == .sint64,
        .fixed32 => value == .fixed32,
        .fixed64 => value == .fixed64,
        .sfixed32 => value == .sfixed32,
        .sfixed64 => value == .sfixed64,
        .bool => value == .boolean,
        .string => value == .string,
        .bytes => value == .bytes,
    };
}

fn importKindCount(file: *const schema.FileDescriptor, kind: schema.Import.Kind) usize {
    var count: usize = 0;
    for (file.imports.items) |import| {
        if (import.kind == kind) count += 1;
    }
    return count;
}

fn importOfKindAt(file: *const schema.FileDescriptor, kind: schema.Import.Kind, index: usize) ?schema.Import {
    var seen: usize = 0;
    for (file.imports.items) |import| {
        if (import.kind != kind) continue;
        if (seen == index) return import;
        seen += 1;
    }
    return null;
}

fn messageDirectlyContainsField(message: *const schema.MessageDescriptor, target: *const schema.FieldDescriptor) bool {
    for (message.fields.items) |*field| {
        if (field == target) return true;
    }
    return false;
}

fn messageDirectlyContainsOneof(message: *const schema.MessageDescriptor, target: *const schema.OneofDescriptor) bool {
    for (message.oneofs.items) |*oneof| {
        if (oneof == target) return true;
    }
    return false;
}

fn messageDirectlyContainsExtensionRange(message: *const schema.MessageDescriptor, target: *const schema.ExtensionRange) bool {
    for (message.extension_ranges.items) |*range| {
        if (range == target) return true;
    }
    return false;
}

fn containingMessageForMessage(file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor) ?*const schema.MessageDescriptor {
    for (file.messages.items) |*message| {
        if (message == target) return null;
        if (containingMessageForMessageInMessage(message, target)) |parent| return parent;
    }
    return null;
}

fn containingMessageForMessageInMessage(parent: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor) ?*const schema.MessageDescriptor {
    for (parent.messages.items) |*nested| {
        if (nested == target) return parent;
        if (containingMessageForMessageInMessage(nested, target)) |ancestor| return ancestor;
    }
    return null;
}

fn containingMessageForEnum(file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor) ?*const schema.MessageDescriptor {
    for (file.enums.items) |*enum_desc| {
        if (enum_desc == target) return null;
    }
    for (file.messages.items) |*message| {
        if (containingMessageForEnumInMessage(message, target)) |parent| return parent;
    }
    return null;
}

fn containingMessageForEnumInMessage(parent: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor) ?*const schema.MessageDescriptor {
    for (parent.enums.items) |*enum_desc| {
        if (enum_desc == target) return parent;
    }
    for (parent.messages.items) |*nested| {
        if (containingMessageForEnumInMessage(nested, target)) |ancestor| return ancestor;
    }
    return null;
}

fn extensionScopeMessageInFile(file: *const schema.FileDescriptor, target: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (file.extensions.items) |*field| {
        if (field == target) return null;
    }
    for (file.messages.items) |*message| {
        if (extensionScopeMessageInMessage(message, target)) |scope| return scope;
    }
    return null;
}

fn extensionScopeMessageInMessage(message: *const schema.MessageDescriptor, target: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (message.extensions.items) |*field| {
        if (field == target) return message;
    }
    for (message.messages.items) |*nested| {
        if (extensionScopeMessageInMessage(nested, target)) |scope| return scope;
    }
    return null;
}

fn fieldLookupScope(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, buf: *[512]u8) ?[]const u8 {
    if (field.extendee != null) return extensionScope(file, field);
    return messageScope(file, current, buf) orelse if (file.package.len != 0) file.package else null;
}

fn extensionScope(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.full_name) |full_name| {
        const normalized = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
        if (std.mem.lastIndexOfScalar(u8, normalized, '.')) |idx| return normalized[0..idx];
        if (std.mem.startsWith(u8, full_name, ".")) return null;
    }
    return if (file.package.len != 0) file.package else null;
}

fn messageScope(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, buf: *[512]u8) ?[]const u8 {
    for (file.messages.items) |*msg_desc| {
        if (msg_desc == current) return formatMessageScope(file.package, msg_desc.name, buf);
        if (messageScopeInMessage(file.package, msg_desc.name, msg_desc, current, buf)) |path| return path;
    }
    return null;
}

fn messageScopeInMessage(package: []const u8, prefix: []const u8, scope_message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor, buf: *[512]u8) ?[]const u8 {
    for (scope_message.messages.items) |*nested| {
        var path_buf: [512]u8 = undefined;
        const nested_path = std.fmt.bufPrint(&path_buf, "{s}.{s}", .{ prefix, nested.name }) catch return null;
        if (nested == target) return formatMessageScope(package, nested_path, buf);
        if (messageScopeInMessage(package, nested_path, nested, target, buf)) |path| return path;
    }
    return null;
}

fn formatMessageScope(package: []const u8, path: []const u8, buf: *[512]u8) ?[]const u8 {
    if (package.len == 0) return std.fmt.bufPrint(buf, "{s}", .{path}) catch null;
    return std.fmt.bufPrint(buf, "{s}.{s}", .{ package, path }) catch null;
}

fn messageFullNameInFileAlloc(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor) std.mem.Allocator.Error!?[]u8 {
    for (file.messages.items) |*message_desc| {
        if (message_desc == target) return try qualifyFileSymbolAlloc(allocator, file, message_desc.name);
        if (try messageFullNameInMessageAlloc(allocator, file, message_desc.name, message_desc, target)) |full_name| return full_name;
    }
    return null;
}

fn messageFullNameInMessageAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    parent_path: []const u8,
    parent: *const schema.MessageDescriptor,
    target: *const schema.MessageDescriptor,
) std.mem.Allocator.Error!?[]u8 {
    for (parent.messages.items) |*nested| {
        const nested_path = try joinNameAlloc(allocator, parent_path, nested.name);
        defer allocator.free(nested_path);
        if (nested == target) return try qualifyFileSymbolAlloc(allocator, file, nested_path);
        if (try messageFullNameInMessageAlloc(allocator, file, nested_path, nested, target)) |full_name| return full_name;
    }
    return null;
}

fn enumFullNameInFileAlloc(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor) std.mem.Allocator.Error!?[]u8 {
    for (file.enums.items) |*enum_desc| {
        if (enum_desc == target) return try qualifyFileSymbolAlloc(allocator, file, enum_desc.name);
    }
    for (file.messages.items) |*message_desc| {
        if (try enumFullNameInMessageAlloc(allocator, file, message_desc.name, message_desc, target)) |full_name| return full_name;
    }
    return null;
}

fn enumFullNameInMessageAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    parent_path: []const u8,
    parent: *const schema.MessageDescriptor,
    target: *const schema.EnumDescriptor,
) std.mem.Allocator.Error!?[]u8 {
    for (parent.enums.items) |*enum_desc| {
        const enum_path = try joinNameAlloc(allocator, parent_path, enum_desc.name);
        defer allocator.free(enum_path);
        if (enum_desc == target) return try qualifyFileSymbolAlloc(allocator, file, enum_path);
    }
    for (parent.messages.items) |*nested| {
        const nested_path = try joinNameAlloc(allocator, parent_path, nested.name);
        defer allocator.free(nested_path);
        if (try enumFullNameInMessageAlloc(allocator, file, nested_path, nested, target)) |full_name| return full_name;
    }
    return null;
}

fn qualifyFileSymbolAlloc(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8) std.mem.Allocator.Error![]u8 {
    const absolute = std.mem.startsWith(u8, name, ".");
    const normalized = if (absolute) name[1..] else name;
    if (absolute or file.package.len == 0 or startsWithPackage(file.package, normalized)) return try allocator.dupe(u8, normalized);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ file.package, normalized });
}

fn startsWithPackage(package: []const u8, name: []const u8) bool {
    return name.len > package.len and
        std.mem.eql(u8, name[0..package.len], package) and
        name[package.len] == '.';
}

fn joinNameAlloc(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (prefix.len == 0) return try allocator.dupe(u8, name);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, name });
}

test "reflection facade creates and edits dynamic messages" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Person {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated int32 score = 3;
        \\  map<string, int32> counts = 4;
        \\  oneof pick { bool active = 5; string label = 6; }
        \\  Child child = 7;
        \\  map<string, Child> children = 8;
        \\}
        \\message Child { string name = 1; }
        \\message Other { string name = 1; }
    );
    defer file.deinit();
    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&file);

    const refl = Reflection.init(allocator, &reg);
    const person_desc = try refl.message("demo.Person");
    const child_desc = try refl.message("demo.Child");
    const other_desc = try refl.message("demo.Other");
    var synthetic_map_entry = schema.MessageDescriptor{ .name = "CountsEntry", .map_entry = true };
    defer synthetic_map_entry.deinit(allocator);
    try std.testing.expect(refl.messageIsMapEntry(&synthetic_map_entry));
    try std.testing.expect(!refl.messageIsMapEntry(person_desc));
    var msg = try refl.newMessage("demo.Person");
    defer msg.deinit();

    try refl.setInt32(&msg, "id", 7);
    try refl.setString(&msg, "name", "Zig");
    try refl.addInt32(&msg, "score", 10);
    try refl.addInt32(&msg, "score", 20);
    try refl.putStringInt32MapEntry(&msg, "counts", "red", 1);
    try refl.setBool(&msg, "active", true);
    try std.testing.expectEqual(@as(i32, 7), try refl.getInt32(&msg, "id"));
    try std.testing.expectEqualStrings("Zig", try refl.getString(&msg, "name"));
    try std.testing.expectEqual(@as(usize, 2), try refl.repeatedLen(&msg, "score"));
    try std.testing.expectEqual(@as(i32, 20), (try refl.repeatedValue(&msg, "score", 1)).int32);
    try std.testing.expectEqualStrings("active", refl.whichOneof(&msg, "pick").?.name);

    const listed = try refl.listFields(&msg);
    defer allocator.free(listed);
    try std.testing.expectEqual(@as(usize, 5), listed.len);
    try std.testing.expectEqualStrings("id", listed[0].name);
    try std.testing.expectEqualStrings("name", listed[1].name);
    try std.testing.expectEqualStrings("score", listed[2].name);
    try std.testing.expectEqualStrings("counts", listed[3].name);
    try std.testing.expectEqualStrings("active", listed[4].name);

    // Reflection writes validate the dynamic value before mutating the message,
    // matching C++ Reflection's typed setters rather than allowing an invalid
    // FieldValue to linger until a later read or encode.
    try std.testing.expectError(error.TypeMismatch, refl.setInt32(&msg, "name", 99));
    try std.testing.expectEqualStrings("Zig", try refl.getString(&msg, "name"));
    try std.testing.expectError(error.TypeMismatch, refl.addString(&msg, "score", "bad"));
    try std.testing.expectEqual(@as(usize, 2), try refl.repeatedLen(&msg, "score"));
    try std.testing.expectError(error.TypeMismatch, refl.putMapEntryOwned(&msg, "counts", .{ .int32 = 1 }, .{ .int32 = 2 }));
    try std.testing.expectError(error.TypeMismatch, refl.putMapEntryOwned(&msg, "counts", .{ .string = try allocator.dupe(u8, "bad") }, .{ .string = try allocator.dupe(u8, "value") }));
    try std.testing.expectEqual(@as(usize, 1), msg.get("counts").?.values.items.len);

    const child = try allocator.create(dynamic.DynamicMessage);
    child.* = dynamic.DynamicMessage.init(allocator, child_desc);
    try refl.setString(child, "name", "child");
    try refl.set(&msg, try refl.fieldByName(person_desc, "child"), .{ .message = child });
    const other = try allocator.create(dynamic.DynamicMessage);
    other.* = dynamic.DynamicMessage.init(allocator, other_desc);
    try std.testing.expectError(error.TypeMismatch, refl.set(&msg, try refl.fieldByName(person_desc, "child"), .{ .message = other }));
    const still_child = (try refl.getField(&msg, "child")).?.values.items[0].message;
    try std.testing.expect(still_child.descriptor == child_desc);

    const child_entry = try allocator.create(dynamic.DynamicMessage);
    child_entry.* = dynamic.DynamicMessage.init(allocator, child_desc);
    try refl.setString(child_entry, "name", "map-child");
    try refl.putMapEntryOwned(&msg, "children", .{ .string = try allocator.dupe(u8, "ok") }, .{ .message = child_entry });
    try std.testing.expectError(error.TypeMismatch, refl.putMapEntryOwned(&msg, "children", .{ .string = try allocator.dupe(u8, "bad") }, .{ .int32 = 1 }));
    try std.testing.expectEqual(@as(usize, 1), msg.get("children").?.values.items.len);

    try std.testing.expectError(error.TypeMismatch, refl.setBytes(&msg, "label", "not-a-string"));
    try std.testing.expect(try refl.hasOneof(&msg, "pick"));
    try std.testing.expectEqualStrings("active", refl.whichOneof(&msg, "pick").?.name);

    try refl.setString(&msg, "label", "chosen");
    try std.testing.expectEqualStrings("label", refl.whichOneof(&msg, "pick").?.name);
    try std.testing.expectEqualStrings("chosen", try refl.getString(&msg, "label"));
    try std.testing.expectEqualStrings("pick", (try refl.oneofByName(msg.descriptor, "pick")).name);
    try std.testing.expect(try refl.clearOneof(&msg, "pick"));
    try std.testing.expect(!(try refl.hasOneof(&msg, "pick")));
    try std.testing.expect(refl.whichOneof(&msg, "pick") == null);
    try std.testing.expectError(error.MissingField, refl.getString(&msg, "label"));
    try std.testing.expect(!(try refl.clearOneof(&msg, "pick")));
    try std.testing.expectError(error.UnknownField, refl.hasOneof(&msg, "missing"));
    try std.testing.expectError(error.UnknownField, refl.clearOneof(&msg, "missing"));

    try refl.clearField(&msg, "name");
    try std.testing.expect(!(try refl.hasField(&msg, "name")));
}

test "reflection facade finds extension descriptors" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
        \\message Scope { extend Host { optional int32 code = 101; } }
    );
    defer file.deinit();
    file.name = "extensions.proto";
    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&file);

    const refl = Reflection.init(allocator, &reg);
    const host_desc = try refl.message(".demo.Host");
    const note = try refl.extensionForMessage(host_desc, 100);
    try std.testing.expectEqual(@as(usize, 1), refl.fileExtensionCount(&file));
    try std.testing.expect(note == try refl.fileExtensionAt(&file, 0));
    try std.testing.expectEqual(@as(usize, 0), try refl.fileExtensionIndex(&file, note));
    try std.testing.expectError(error.UnknownField, refl.fileExtensionAt(&file, 9));
    try std.testing.expect(note == try refl.extension(".demo.Host", 100));
    try std.testing.expect(note == try refl.extensionByName(".demo.Host", ".demo.note"));
    try std.testing.expect(note == try refl.extensionByNameForMessage(host_desc, "note"));
    try std.testing.expectEqualStrings("extensions.proto", (try refl.fileOfExtension(note)).name);

    const code = try refl.extensionByNameForMessage(host_desc, ".demo.Scope.code");
    const scope_desc = try refl.message(".demo.Scope");
    try std.testing.expectEqual(@as(usize, 1), refl.messageExtensionCount(scope_desc));
    try std.testing.expect(code == try refl.messageExtensionAt(scope_desc, 0));
    try std.testing.expectEqual(@as(usize, 0), try refl.messageExtensionIndex(scope_desc, code));
    try std.testing.expectError(error.UnknownField, refl.messageExtensionAt(scope_desc, 9));
    try std.testing.expectEqual(@as(usize, 0), refl.messageExtensionCount(host_desc));
    try std.testing.expect(code == try refl.extensionForMessage(host_desc, 101));
    try std.testing.expectEqual(@as(wire.FieldNumber, 101), code.number);
    try std.testing.expectError(error.UnknownField, refl.extensionForMessage(host_desc, 102));
}

test "reflection exposes field edition defaults" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.name = "edition-defaults.proto";
    file.setSyntax(.proto2);

    var host = schema.MessageDescriptor{ .name = "Host" };
    var field = schema.FieldDescriptor{ .name = "presence", .number = 1, .cardinality = .optional, .kind = .{ .scalar = .int32 } };
    try field.edition_defaults.append(allocator, .{ .edition = .legacy, .value = "EXPLICIT" });
    try field.edition_defaults.append(allocator, .{ .edition = .proto3, .value = "IMPLICIT" });
    try host.fields.append(allocator, field);
    try file.messages.append(allocator, host);

    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&file);

    const refl = Reflection.init(allocator, &reg);
    const desc = try refl.message(".Host");
    const presence = try refl.fieldByName(desc, "presence");
    try std.testing.expectEqual(@as(usize, 2), refl.fieldEditionDefaultCount(presence));
    const legacy_default = try refl.fieldEditionDefaultAt(presence, 0);
    try std.testing.expectEqual(@as(usize, 0), try refl.fieldEditionDefaultIndex(presence, legacy_default));
    try std.testing.expectEqual(schema.Edition.legacy, refl.fieldEditionDefaultEdition(legacy_default));
    try std.testing.expectEqualStrings("EXPLICIT", refl.fieldEditionDefaultValue(legacy_default));
    const proto3_default = try refl.fieldEditionDefaultAt(presence, 1);
    try std.testing.expectEqual(@as(usize, 1), try refl.fieldEditionDefaultIndex(presence, proto3_default));
    try std.testing.expectEqual(schema.Edition.proto3, refl.fieldEditionDefaultEdition(proto3_default));
    try std.testing.expectEqualStrings("IMPLICIT", refl.fieldEditionDefaultValue(proto3_default));
    try std.testing.expectError(error.UnknownField, refl.fieldEditionDefaultAt(presence, 2));
}

test "reflection facade resolves files and import chains" {
    const allocator = std.testing.allocator;
    var leaf = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.leaf;
        \\message User { int32 id = 1; }
    );
    defer leaf.deinit();
    leaf.name = "leaf.proto";
    var bridge = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.bridge;
        \\import public "leaf.proto";
        \\message Bridge {}
    );
    defer bridge.deinit();
    bridge.name = "bridge.proto";
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.app;
        \\import "bridge.proto";
        \\message App { demo.leaf.User user = 1; }
    );
    defer app.deinit();
    app.name = "app.proto";

    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&leaf);
    try reg.addFile(&bridge);
    try reg.addFile(&app);
    try reg.validateAllFileReferences();

    const refl = Reflection.init(allocator, &reg);
    const app_file = try refl.file("app.proto");
    const bridge_file = try refl.file("bridge.proto");
    const leaf_file = try refl.file("leaf.proto");
    try std.testing.expect(refl.fileCanSee(app_file, bridge_file));
    try std.testing.expect(refl.fileCanSee(app_file, leaf_file));
    try std.testing.expect(!refl.fileCanSee(leaf_file, app_file));

    const direct = refl.importChain(app_file, bridge_file).?;
    try std.testing.expectEqual(@as(usize, 1), refl.importChainLength(direct));
    try std.testing.expectEqualStrings("bridge.proto", try refl.importChainPathAt(direct, 0));

    const public_chain = (try refl.importChainByPath("app.proto", "leaf.proto")).?;
    try std.testing.expectEqual(@as(usize, 2), refl.importChainLength(public_chain));
    try std.testing.expectEqualStrings("bridge.proto", try refl.importChainPathAt(public_chain, 0));
    try std.testing.expectEqualStrings("leaf.proto", try refl.importChainPathAt(public_chain, 1));
    try std.testing.expectEqualStrings("leaf.proto", refl.importChainPaths(public_chain)[1]);
    try std.testing.expectError(error.UnknownFile, refl.importChainPathAt(public_chain, 2));
    try std.testing.expectEqual(@as(usize, 0), refl.importChainLength(refl.importChain(app_file, app_file).?));
    try std.testing.expectError(error.UnknownFile, refl.file("missing.proto"));
    try std.testing.expectError(error.UnknownFile, refl.importChainByPath("app.proto", "missing.proto"));
}

fn exerciseReflectionCleanup(allocator: std.mem.Allocator, registry: *const registry_mod.Registry) !void {
    const refl = Reflection.init(allocator, registry);
    var msg = try refl.newMessage("demo.Person");
    defer msg.deinit();

    try refl.setString(&msg, "name", "Zig");
    try refl.addString(&msg, "tags", "one");
    try refl.putStringInt32MapEntry(&msg, "counts", "red", 1);

    try std.testing.expectEqualStrings("Zig", try refl.getString(&msg, "name"));
    try std.testing.expectEqual(@as(usize, 1), try refl.repeatedLen(&msg, "tags"));
    try std.testing.expectEqual(@as(usize, 1), msg.get("counts").?.values.items.len);
}

test "reflection facade cleans up allocation failures" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Person {
        \\  string name = 1;
        \\  repeated string tags = 2;
        \\  map<string, int32> counts = 3;
        \\}
    );
    defer file.deinit();
    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&file);

    try std.testing.checkAllAllocationFailures(allocator, exerciseReflectionCleanup, .{&reg});
}
