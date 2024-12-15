const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // exported module
    const module = b.addModule("libregex", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const c_source_files_options = std.Build.Module.AddCSourceFilesOptions{
        .files = &[_][]const u8{"src/c_src/regex_adapter.c"},
    };
    const c_include_path = std.Build.LazyPath{
        .src_path = .{
            .owner = b,
            .sub_path = "src",
        },
    };

    const regex_c_lib = b.addStaticLibrary(.{
        .name = "regex_slim",
        .optimize = optimize,
        .target = target,
    });
    regex_c_lib.addIncludePath(c_include_path);
    regex_c_lib.addCSourceFiles(c_source_files_options);
    regex_c_lib.linkLibC();

    module.linkLibrary(regex_c_lib);
    module.addIncludePath(c_include_path);
    module.addCSourceFiles(c_source_files_options);

    // unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.linkLibrary(regex_c_lib);
    unit_tests.addIncludePath(c_include_path);
    unit_tests.addCSourceFiles(c_source_files_options);
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // documentation
    const docs = b.addTest(.{
        .name = "zig-regex-lib",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    docs.linkLibrary(regex_c_lib);
    docs.addIncludePath(c_include_path);
    docs.addCSourceFiles(c_source_files_options);
    docs.linkLibC();

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .{ .custom = "../docs" },
        .install_subdir = "",
    });

    const docs_step = b.step("docs", "Generate docs");
    docs_step.dependOn(&install_docs.step);
    docs_step.dependOn(&docs.step);
}
