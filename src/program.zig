const std = @import("std");
const Machine = @import("ivm.zig").Machine;
const root = @import("root");

const VM = Machine(1024 * 1024 * 64, .{ .strange_push0_behavior = false, .flush_every_line = true });

pub fn main() !void {
    var arg_mem: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arg_mem);
    const args = try std.process.argsAlloc(fba.allocator());
    defer std.process.argsFree(fba.allocator(), args);

    const machine = try std.heap.page_allocator.create(VM);
    defer std.heap.page_allocator.destroy(machine);
    machine.init();

    const input_reader = if (args.len > 1)
        (try std.fs.cwd().openFile(args[args.len - 1], .{})).reader()
    else
        std.io.getStdIn().reader();

    const program_length = try input_reader.readAll(&machine.memory);

    @memset(machine.memory[program_length..], 0);

    try machine.setProgramLength(program_length);

    // machine.printProgram(program_length);
    machine.run(.{
        .debug = @hasDecl(root, "debug") and root.debug,
        .colors = @hasDecl(root, "colors") and root.colors,
        .right_align_machine_state = @hasDecl(root, "right_align_machine_state") and root.right_align_machine_state,
    });
    // machine.printMemory(0x200);
}
