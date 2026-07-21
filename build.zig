const std = @import("std");

pub const GenerateProtobufOptions = struct {
    /// Optional dependency handle for consumers that already called
    /// `b.dependency("pbz", ...)`. If omitted, the helper resolves the pbz
    /// dependency from this build.zig type. When called inside pbz's own
    /// build.zig, pass `plugin_exe` instead.
    dependency: ?*std.Build.Dependency = null,
    /// Optional protoc-gen-pbz artifact. Useful inside this package's own
    /// build.zig or for advanced consumers that build the plugin themselves.
    plugin_exe: ?*std.Build.Step.Compile = null,
    /// `protoc` executable name/path.
    protoc: []const u8 = "protoc",
    /// .proto files to generate, relative to the caller build root.
    proto_files: []const []const u8,
    /// String include paths passed as `--proto_path=...`.
    include_paths: []const []const u8 = &.{},
    /// Lazy include directories passed as `--proto_path=...`.
    include_dirs: []const std.Build.LazyPath = &.{},
    /// Add the caller build root as a proto search path.
    include_build_root: bool = true,
    /// Raw protoc-gen-pbz parameter string. This is the same parameter surface
    /// as `protoc --pbz_opt=...` / `protoc-gen-pbz`.
    parameter: []const u8 = "",
    /// Directory basename inside zig-cache for generated files.
    output_dir_name: []const u8 = "pbz-generated",
    /// Mirrors protoc-gen-pbz `output_suffix`; used by generatedFile().
    output_suffix: []const u8 = ".pb.zig",
    /// Mirrors protoc-gen-pbz `strip_proto_ext`; used by generatedFile().
    strip_proto_ext: bool = true,
    /// Import name used by addModule() for the pbz runtime module.
    pbz_import: []const u8 = "pbz",
};

pub const ProtobufCodegen = struct {
    run: *std.Build.Step.Run,
    step: *std.Build.Step,
    output_dir: std.Build.LazyPath,
    output_suffix: []const u8,
    strip_proto_ext: bool,
    pbz_import: []const u8,

    pub fn generatedFile(self: ProtobufCodegen, b: *std.Build, proto_file: []const u8) std.Build.LazyPath {
        const output_name = outputNameForProto(b, proto_file, self.output_suffix, self.strip_proto_ext);
        return self.output_dir.path(b, output_name);
    }

    pub fn addModule(
        self: ProtobufCodegen,
        b: *std.Build,
        name: []const u8,
        proto_file: []const u8,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        pbz_module: *std.Build.Module,
    ) *std.Build.Module {
        return b.addModule(name, .{
            .root_source_file = self.generatedFile(b, proto_file),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = self.pbz_import, .module = pbz_module }},
        });
    }
};

/// Build-system codegen helper similar in spirit to prost-build.
///
/// The helper deliberately shells out to `protoc` with this package's
/// `protoc-gen-pbz` artifact, so it has the same descriptor handling and plugin
/// parameter support as the standalone executable. Consumers can depend on the
/// returned `step`, import generated files via `generatedFile()`, or create a
/// Zig module with `addModule()`.
pub fn generateProtobuf(b: *std.Build, options: GenerateProtobufOptions) ProtobufCodegen {
    const plugin = options.plugin_exe orelse if (options.dependency) |dep|
        dep.artifact("protoc-gen-pbz")
    else
        b.dependencyFromBuildZig(@This(), .{}).artifact("protoc-gen-pbz");

    const run = b.addSystemCommand(&.{options.protoc});
    run.addPrefixedArtifactArg("--plugin=protoc-gen-pbz=", plugin);
    if (options.include_build_root) run.addArg("--proto_path=.");
    for (options.include_paths) |path| run.addArg(b.fmt("--proto_path={s}", .{path}));
    for (options.include_dirs) |dir| run.addPrefixedDirectoryArg("--proto_path=", dir);
    if (options.parameter.len != 0) run.addArg(b.fmt("--pbz_opt={s}", .{options.parameter}));
    const output_dir = run.addPrefixedOutputDirectoryArg("--pbz_out=", options.output_dir_name);
    for (options.proto_files) |proto_file| {
        run.addFileInput(b.path(proto_file));
        run.addArg(proto_file);
    }
    return .{
        .run = run,
        .step = &run.step,
        .output_dir = output_dir,
        .output_suffix = b.dupe(options.output_suffix),
        .strip_proto_ext = options.strip_proto_ext,
        .pbz_import = b.dupe(options.pbz_import),
    };
}

fn outputNameForProto(b: *std.Build, proto_file: []const u8, suffix: []const u8, strip_proto_ext: bool) []const u8 {
    const stem = if (strip_proto_ext and std.mem.endsWith(u8, proto_file, ".proto"))
        proto_file[0 .. proto_file.len - ".proto".len]
    else
        proto_file;
    return b.fmt("{s}{s}", .{ stem, suffix });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("pbz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "pbz",
        .root_module = mod,
    });
    b.installArtifact(lib);

    const plugin_exe = b.addExecutable(.{
        .name = "protoc-gen-pbz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/protoc_gen_pbz.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pbz", .module = mod }},
        }),
    });
    b.installArtifact(plugin_exe);

    const conformance_exe = b.addExecutable(.{
        .name = "pbz-conformance",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pbz_conformance.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pbz", .module = mod }},
        }),
    });
    b.installArtifact(conformance_exe);

    const tests = b.addTest(.{
        .root_module = mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const examples_step = b.step("examples", "Build and run examples");
    const example_names = [_][]const u8{
        "wire",
        "dynamic_message",
        "json_text",
        "registry_loader",
        "descriptors_codegen",
        "generated_types",
        "generated_performance",
        "generated_advanced",
        "generated_required",
        "generated_defaults",
        "generated_extensions",
        "generated_identifiers",
        "generated_imports",
        "generated_groups",
        "generated_recursive",
        "generated_streaming",
        "ownership_patterns",
        "well_known_types",
        "proto2_extensions",
        "conformance",
    };
    for (example_names) |example_name| {
        const root_source_file = b.fmt("examples/{s}.zig", .{example_name});
        const example_exe = b.addExecutable(.{
            .name = b.fmt("pbz-example-{s}", .{example_name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(root_source_file),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "pbz", .module = mod }},
            }),
        });
        const run_example = b.addRunArtifact(example_exe);
        examples_step.dependOn(&run_example.step);
    }

    const build_codegen = generateProtobuf(b, .{
        .plugin_exe = plugin_exe,
        .proto_files = &.{"examples/proto/person.proto"},
        .include_paths = &.{"examples/proto"},
        .output_dir_name = "pbz-build-codegen-smoke",
    });
    const build_codegen_module = build_codegen.addModule(
        b,
        "build_codegen_person_pb",
        "examples/proto/person.proto",
        target,
        optimize,
        mod,
    );
    const build_codegen_smoke_exe = b.addExecutable(.{
        .name = "pbz-example-build-codegen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/build_codegen.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pbz", .module = mod },
                .{ .name = "person_pb", .module = build_codegen_module },
            },
        }),
    });
    build_codegen_smoke_exe.step.dependOn(build_codegen.step);
    const run_build_codegen_smoke = b.addRunArtifact(build_codegen_smoke_exe);
    const build_codegen_step = b.step("build-codegen-smoke", "Generate protobuf code during build.zig and run smoke test");
    build_codegen_step.dependOn(&run_build_codegen_smoke.step);
    examples_step.dependOn(&run_build_codegen_smoke.step);

    const bench_exe = b.addExecutable(.{
        .name = "pbz-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/pbz_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pbz", .module = mod },
                .{ .name = "person_pb", .module = b.createModule(.{
                    .root_source_file = b.path("examples/generated/person.pb.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{.{ .name = "pbz", .module = mod }},
                }) },
            },
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run pbz benchmark baseline");
    bench_step.dependOn(&run_bench.step);

    const run_summary_self_test = b.addSystemCommand(&.{
        "python3",
        "bench/summarize_compare.py",
        "--self-test",
    });
    const run_generated_examples_check = b.addSystemCommand(&.{
        "python3",
        "tools/check_generated_examples.py",
        "--plugin",
    });
    run_generated_examples_check.addArtifactArg(plugin_exe);
    const generated_examples_check_step = b.step("check-generated-examples", "Regenerate checked-in protobuf examples and verify no drift");
    generated_examples_check_step.dependOn(&run_generated_examples_check.step);
    const run_conformance_smoke = b.addSystemCommand(&.{
        "python3",
        "tools/smoke_conformance.py",
        "--exe",
    });
    run_conformance_smoke.addArtifactArg(conformance_exe);
    const conformance_smoke_step = b.step("conformance-smoke", "Run lightweight pbz-conformance smoke test");
    conformance_smoke_step.dependOn(&run_conformance_smoke.step);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(examples_step);
    test_step.dependOn(&run_summary_self_test.step);

    const check_step = b.step("check", "Run non-benchmark validation gates");
    check_step.dependOn(test_step);
    check_step.dependOn(generated_examples_check_step);
    check_step.dependOn(conformance_smoke_step);
}
