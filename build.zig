const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zf_dep = b.dependency("zf", .{
        .target = target,
        .optimize = optimize,
    });

    const termbox2 = b.dependency("termbox2-zig", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "gomodfile",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const module = b.addModule("gomodfile", .{
        .root_source_file = lib.root_module.root_source_file,
        .target = target,
        .optimize = optimize,
    });
    module.linkLibrary(lib);

    const exe = b.addExecutable(.{
        .name = "modupdate",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = b.option(bool, "strip", "strip executable"),
    });
    exe.linkLibrary(lib);
    exe.root_module.addImport("termbox2", termbox2.module("termbox2"));
    exe.root_module.addImport("zf", zf_dep.module("zf"));
    exe.root_module.addImport("gomodfile", module);

    const asm_step = b.step("asm", "Produce assembly");
    asm_step.dependOn(&b.addInstallFile(exe.getEmittedAsm(), "modupdate.s").step);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.linkLibrary(lib);

    const test_step = b.step("test", "Run unit tests");
    const build_only = b.option(bool, "build", "Build tests but do not run") orelse false;
    if (build_only) {
        const tests_artifact = b.addInstallArtifact(lib_unit_tests, .{});
        test_step.dependOn(&tests_artifact.step);
    } else {
        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
        test_step.dependOn(&run_lib_unit_tests.step);
    }

    const cov_step = b.step("cov", "Generate coverage");
    const cov_run = b.addSystemCommand(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output" });
    cov_run.addArtifactArg(lib_unit_tests);
    cov_step.dependOn(&cov_run.step);

    const lints_step = b.step("lints", "Run lints");
    const lints = b.addFmt(.{
        .paths = &.{ "src", "build.zig" },
        .check = true,
    });

    lints_step.dependOn(&lints.step);
    b.default_step.dependOn(lints_step);

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // b.default_step.dependOn(test_step); // run tests before building

    b.installArtifact(exe);
}
