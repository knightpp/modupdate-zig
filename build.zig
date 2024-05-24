const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "modupdate",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = b.option(bool, "strip", "strip executable"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "gomod",
        .root_source_file = b.path("src/gomod.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });

    b.installArtifact(lib);
    b.installArtifact(exe);

    const asm_step = b.step("asm", "Produce assembly");
    asm_step.dependOn(&b.addInstallFile(exe.getEmittedAsm(), "modupdate.s").step);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const build_tests_step = b.step("tests", "Build tests");
    const tests_artifact = b.addInstallArtifact(lib_unit_tests, .{});
    build_tests_step.dependOn(&tests_artifact.step);
}
