const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ivm-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    if (target.result.os.tag == .windows) exe.linkSystemLibrary("comdlg32");

    b.installArtifact(exe);

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
    tests.linkLibC();
    if (target.result.os.tag == .windows) tests.linkSystemLibrary("comdlg32");

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");

    test_step.dependOn(&run_tests.step);
}
