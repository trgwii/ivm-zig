pub const main = @import("assemble_program.zig").main;

pub const output = "hello.ivm";

pub const data = ("Hello, World!\n" ** (16)) ++ "\x00";

pub const data_start = 0x20;

pub const code = .{
    .get_pc,
    .get_sp,
    .load8,
    .{ .push1, 0x1f },
    .add,
    .get_sp,
    .load8,
    .load1,
    .get_sp,
    .load8,
    .{ .jz_fwd, 0x0d },
    .put_byte,
    .{ .push1, 0x01 },
    .add,
    .get_sp,
    .{ .push1, 0x08 },
    .add,
    .load8,
    .{ .push1, 0x05 },
    .add,
    .jump,
    .get_sp,
    .{ .push1, 0x18 },
    .add,
    .set_sp,
    .exit,
};
