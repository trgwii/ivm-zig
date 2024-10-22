pub const main = @import("assemble_program.zig").main;

pub const output = "picture.ivm";

pub const code = .{
    .{ .push1, 0xFF },
    .{ .push1, 0xC0 },
    .{ .push1, 0x0 },
    .new_frame,
    .{ .push1, 0x0 },
    .{ .push1, 0x0 },
    .{ .push1, 0xFF },
    .{ .push1, 0x0 },
    .{ .push1, 0x0 },
    .set_pixel,
    .{ .push1, 0x1 },
    .{ .push1, 0x0 },
    .{ .push1, 0xFF },
    .{ .push1, 0x0 },
    .{ .push1, 0x0 },
    .set_pixel,
    .{ .push1, 0x2 },
    .{ .push1, 0x0 },
    .{ .push1, 0xFF },
    .{ .push1, 0x0 },
    .{ .push1, 0x0 },
    .set_pixel,
    .{ .push1, 0x0 },
    .{ .push1, 0x0 },
    .{ .push1, 0x0 },
    .new_frame,
};
