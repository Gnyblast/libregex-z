const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zig-regex",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const c_source_files_options = std.Build.Module.AddCSourceFilesOptions{
        // .root = .{
        //     .cwd_relative = "./src/c_src",
        // },
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

    lib.linkLibrary(regex_c_lib);
    lib.addIncludePath(c_include_path);
    lib.addCSourceFiles(c_source_files_options);
    lib.linkLibC();

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_unit_tests.linkLibrary(regex_c_lib);
    lib_unit_tests.addIncludePath(c_include_path);
    lib_unit_tests.addCSourceFiles(c_source_files_options);
    lib_unit_tests.linkLibC();

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
