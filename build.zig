const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;

    const exe = b.addExecutable(.{
        .name = "ivm-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    const exe_debug = b.addExecutable(.{
        .name = "ivm-zig-debug",
        .root_source_file = b.path("src/main_debug.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    if (target.result.os.tag == .windows) {
        exe.linkLibC();
        exe.linkSystemLibrary("comdlg32");
        exe_debug.linkLibC();
        exe_debug.linkSystemLibrary("comdlg32");
    }

    b.installArtifact(exe);
    b.installArtifact(exe_debug);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "run iVM");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/ivm.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        tests.linkLibC();
        tests.linkSystemLibrary("comdlg32");
    }

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");

    test_step.dependOn(&run_tests.step);
}
