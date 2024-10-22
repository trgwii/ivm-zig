const std = @import("std");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;

    var exes: [2]*Step.Compile = undefined;

    inline for (.{ "ivm-zig", "ivm-zig-debug" }, .{ "main", "main_debug" }, 0..) |exe_name, src_name, i| {
        exes[i] = b.addExecutable(.{
            .name = exe_name,
            .root_source_file = b.path("src/" ++ src_name ++ ".zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        });
    }

    if (target.result.os.tag == .windows) {
        inline for (exes) |exe| {
            exe.linkLibC();
            exe.linkSystemLibrary("comdlg32");
            exe.linkSystemLibrary("Gdi32");
        }
    }

    var progs: [2]*Step.Run = undefined;

    inline for (.{ "hello", "picture" }, 0..) |program_name, i| {
        const prog = b.addExecutable(.{
            .name = program_name,
            .root_source_file = b.path("src/tools/programs/" ++ program_name ++ ".zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        });
        progs[i] = b.addRunArtifact(prog);
    }

    inline for (exes, .{ "run", "run_debug" }, .{ "run iVM", "run iVM in debug mode" }) |exe, step_name, step_description| {
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        for (progs) |prog| run_cmd.step.dependOn(&prog.step);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        const run_step = b.step(step_name, step_description);
        run_step.dependOn(&run_cmd.step);
    }

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
