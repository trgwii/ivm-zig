const std = @import("std");
const Machine = @import("ivm.zig").Machine;
const root = @import("root");

const VM = Machine(1024 * 1024 * 64, .{ .strange_push0_behavior = true });

const debug = @hasDecl(root, "debug") and root.debug;

pub fn main() !void {
    var arg_mem: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&arg_mem);
    const args = try std.process.argsAlloc(fba.allocator());
    defer std.process.argsFree(fba.allocator(), args);

    const machine = try std.heap.page_allocator.create(VM);
    defer std.heap.page_allocator.destroy(machine);
    machine.init();

    const input_reader = if (args.len > 1)
        (try std.fs.cwd().openFile(args[1], .{})).reader()
    else
        std.io.getStdIn().reader();

    var fbs = std.io.fixedBufferStream(&machine.memory);
    var fifo = std.fifo.LinearFifo(u8, .{ .Static = 4096 }).init();
    try fifo.pump(input_reader, fbs.writer());

    const program_length = fbs.getWritten().len;
    try machine.setProgramLength(program_length);

    // machine.printProgram(program_length);
    machine.run(.{ .debug = debug, .colors = false });
    // machine.printMemory(0x200);
}
