const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const build_only = b.option(bool, "build", "Build tests/benchmarks but do not run") orelse false;

    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    const zbench = b.dependency("zbench", .{
        .target = target,
        .optimize = optimize,
    }).module("zbench");

    const strip = b.option(bool, "strip", "strip executable");

    const exe = b.addExecutable(.{
        .name = "modupdate",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = false,
        .strip = strip,
    });

    exe.root_module.addImport("vaxis", vaxis.module("vaxis"));

    const gomodfile_mod = b.addModule("gomodfile", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });

    b.installArtifact(exe);

    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = b.path("src/bench/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    benchmark.root_module.addImport("zbench", zbench);
    benchmark.root_module.addImport("gomodfile", gomodfile_mod);
    const benchmark_step = b.step("bench", "Run benchmark");
    const benchmark_cmd = b.addRunArtifact(benchmark);
    const benchmark_install = b.addInstallArtifact(benchmark, .{});
    if (build_only) {
        benchmark_step.dependOn(&benchmark_install.step);
    } else {
        benchmark_step.dependOn(&benchmark_cmd.step);
    }

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
    if (build_only) {
        const tests_artifact = b.addInstallArtifact(lib_unit_tests, .{});
        test_step.dependOn(&tests_artifact.step);
    } else {
        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
        test_step.dependOn(&run_lib_unit_tests.step);
    }

    // b.default_step.dependOn(test_step); // run tests before building

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
}
