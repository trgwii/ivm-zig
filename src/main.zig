const std = @import("std");
const Machine = @import("ivm.zig").Machine;

// var machine = Machine(1024 * 1024 * 64, .{ .strange_push0_behavior = true }){};
var machine = Machine(1024, .{ .strange_push0_behavior = true }){};

pub fn main() !void {
    var fbs = std.io.fixedBufferStream(&machine.memory);
    var fifo = std.fifo.LinearFifo(u8, .{ .Static = 4096 }).init();
    try fifo.pump(std.io.getStdIn().reader(), fbs.writer());
    const program_length = fbs.getWritten().len;
    try machine.setProgramLength(program_length);
    // machine.printProgram(program_length);
    machine.run(.{ .debug = true });
}
