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
        .name = "gomodfile",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });

    _ = b.addModule("gomodfile", .{
        .root_source_file = b.path("src/lib.zig"),
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

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    const build_only = b.option(bool, "build", "Build tests but do not run") orelse false;
    if (build_only) {
        const tests_artifact = b.addInstallArtifact(lib_unit_tests, .{});
        test_step.dependOn(&tests_artifact.step);
    } else {
        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
        test_step.dependOn(&run_lib_unit_tests.step);
    }
}
