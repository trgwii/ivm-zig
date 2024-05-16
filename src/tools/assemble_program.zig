const std = @import("std");

fn generate(out: *std.ArrayList(u8), data_start: ?u64, data: []const u8, code: anytype) !void {
    // TODO: integreate with real enum
    inline for (code) |instruction| {
        if (@typeInfo(@TypeOf(instruction)) == .EnumLiteral) {
            switch (instruction) {
                .jump => try out.append(0x02),
                .set_sp => try out.append(0x05),
                .get_sp => try out.append(0x07),
                .load1 => try out.append(0x10),
                .load8 => try out.append(0x13),
                .add => try out.append(0x20),
                .AND => try out.append(0x28),
                .put_byte => try out.append(0xF9),
                else => @compileError("Unknown instruction " ++ @tagName(instruction)),
            }
        } else switch (instruction[0]) {
            .jz_fwd => try out.appendSlice(&.{ 0x03, instruction[1] }),
            .push1 => try out.appendSlice(&.{ 0x09, instruction[1] }),
            .push8 => try out.appendSlice(&.{0x0c} ++ &@as([8]u8, @bitCast(@as(u64, instruction[1])))),
            else => @compileError("Unknown instruction " ++ @tagName(instruction[0])),
        }
    }
    while (out.items.len < data_start orelse std.mem.alignForward(u64, out.items.len, 16)) try out.append(0x00);
    try out.appendSlice(data);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var code = std.ArrayList(u8).init(allocator);
    defer code.deinit();

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    try data.appendSlice("Hello, World!\n\x00");

    try generate(&code, 0x20, data.items, .{
        .{ .push1, 0x20 },
        .get_sp,
        .load8,
        .load1,
        .get_sp,
        .load8,
        .{ .jz_fwd, 0x07 },
        .put_byte,
        .{ .push1, 0x01 },
        .add,
        .{ .push1, 0x02 },
        .jump,
        .get_sp,
        .{ .push1, 0x10 },
        .add,
        .set_sp,
    });

    try std.fs.cwd().writeFile(.{ .sub_path = "hello.ivm", .data = code.items });
}
