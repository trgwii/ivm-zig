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
    const run_debug_cmd = b.addRunArtifact(exe_debug);

    inline for (.{ "hello", "picture" }) |program_name| {
        const prog = b.addExecutable(.{
            .name = program_name,
            .root_source_file = b.path("src/tools/programs/" ++ program_name ++ ".zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        });
        const prog_cmd = b.addRunArtifact(prog);
        run_cmd.step.dependOn(&prog_cmd.step);
        run_debug_cmd.step.dependOn(&prog_cmd.step);
    }

    run_cmd.step.dependOn(b.getInstallStep());
    run_debug_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);
    if (b.args) |args| run_debug_cmd.addArgs(args);

    const run_step = b.step("run", "run iVM");
    run_step.dependOn(&run_cmd.step);

    const run_debug_step = b.step("run_debug", "run iVM in debug mode");
    run_debug_step.dependOn(&run_debug_cmd.step);

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
