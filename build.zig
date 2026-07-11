const std = @import("std");

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

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(examples_step);
}
