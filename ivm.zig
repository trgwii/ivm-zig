const std = @import("std");

pub fn Machine(comptime N: u64) type {
    return struct {
        /// T
        terminated: bool = false,
        /// M
        memory: [N]u8 = [_]u8{0} ** N,
        /// P
        program_counter: u64 = 0,
        /// S
        stack_pointer: u64 = N,
        const Self = @This();
        fn put(self: *Self, comptime n: u4, x: u64, a: u64) void {
            comptime std.debug.assert(n == 1 or n == 2 or n == 4 or n == 8);
            for (0..n) |i| self.memory[a + i] = @as([8]u8, @bitCast(x))[i];
        }
        fn get(self: *Self, comptime n: u4, a: u64, x: *u64) void {
            comptime std.debug.assert(n == 1 or n == 2 or n == 4 or n == 8);
            for (0..n) |i| @as(*[8]u8, @ptrCast(x))[i] = self.memory[a + i];
        }
        pub fn push(self: *Self, x: u64) void {
            self.stack_pointer -= 8;
            self.put(8, x, self.stack_pointer);
        }
        pub fn pop(self: *Self, x: *u64) void {
            self.get(8, self.stack_pointer, x);
            self.stack_pointer += 8;
        }
        pub fn fetch(self: *Self, comptime n: u4, x: *u64) void {
            comptime std.debug.assert(n == 1 or n == 2 or n == 4 or n == 8);
            x.* = 0;
            self.get(n, self.program_counter, x);
            self.program_counter += n;
        }
        pub const Inst = enum(u8) {
            exit = 0x00,
            nop = 0x01,
            jump = 0x02,
            jz_fwd = 0x03,
            jz_back = 0x04,
            set_sp = 0x05,
            get_pc = 0x06,
            get_sp = 0x07,
            push0 = 0x08,
            push1 = 0x09,
            _,
        };
        /// The main procedure
        fn main(self: *Self) void {
            var k: u64 = 0;
            self.fetch(1, &k);
            switch (k) {
                0x00 => {
                    self.terminated = true;
                    std.debug.print("exit\n", .{});
                },
                0x01 => {
                    std.debug.print("nop\n", .{});
                },
                0x02 => {
                    var a: u64 = 0;
                    self.pop(&a);
                    self.program_counter = a;
                    std.debug.print("jump 0x{x}\n", .{a});
                },
                0x03 => {
                    var a: u64 = 0;
                    var x: u64 = 0;
                    self.fetch(1, &a);
                    self.pop(&x);
                    if (x == 0) self.program_counter += a;
                    std.debug.print("jz_fwd 0x{x} -> {s}\n", .{ a, if (x == 0) "true" else "false" });
                },
                0x04 => {
                    var a: u64 = 0;
                    var x: u64 = 0;
                    self.fetch(1, &a);
                    self.pop(&x);
                    if (x == 0) self.program_counter -= a + 1;
                    std.debug.print("jz_back 0x{x} -> {s}\n", .{ a, if (x == 0) "true" else "false" });
                },
                0x05 => {
                    var a: u64 = 0;
                    self.pop(&a);
                    self.stack_pointer = a;
                    std.debug.print("set_sp 0x{x}\n", .{a});
                },
                0x06 => {
                    const a = self.program_counter;
                    self.push(a);
                    std.debug.print("get_pc -> 0x{x}\n", .{a});
                },
                0x07 => {
                    const a = self.stack_pointer;
                    self.push(a);
                    std.debug.print("get_sp -> 0x{x}\n", .{a});
                },
                0x09 => {
                    var a: u64 = 0;
                    self.fetch(1, &a);
                    self.push(a);
                    std.debug.print("push1 0x{x}\n", .{a});
                },
                0x30 => {
                    var x: u64 = 0;
                    self.pop(&x);
                    if (x >= 2) self.terminated = true;
                    std.debug.print("check -> 0x{x}\n", .{x});
                },
                else => {
                    std.debug.print("hit unknown instruction: 0x{x}\n", .{k});
                    self.terminated = true;
                },
            }
        }
        pub fn run(self: *Self) void {
            while (!self.terminated) {
                std.debug.print("P = 0x{x}, S = 0x{x}\n", .{ self.program_counter, self.stack_pointer });
                self.main();
            }
        }
    };
}

test "put" {
    var machine = Machine(16){};
    const x: u64 = 0xa7a6a5a4a3a2a1a0;
    machine.put(1, x, 0x01);
    machine.put(2, x, 0x02);
    machine.put(4, x, 0x04);
    machine.put(8, x, 0x08);
    const answer = .{ 0x00, 0xa0, 0xa0, 0xa1, 0xa0, 0xa1, 0xa2, 0xa3, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7 };
    inline for (machine.memory, answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "get" {
    var machine = Machine(16){
        .memory = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf },
    };
    var x: u64 = 0;
    machine.get(1, 1, &x);
    try std.testing.expect(x == 0x00000000000000a1);
    machine.get(2, 2, &x);
    try std.testing.expect(x == 0x000000000000a3a2);
    machine.get(4, 4, &x);
    try std.testing.expect(x == 0x00000000a7a6a5a4);
    machine.get(8, 8, &x);
    try std.testing.expect(x == 0xafaeadacabaaa9a8);
}

test "push" {
    var machine = Machine(16){};
    const x: u64 = 0xafaeadacabaaa9a8;
    const y: u64 = 0xa7a6a5a4a3a2a1a0;
    machine.push(x);
    try std.testing.expect(machine.stack_pointer == 0x08);
    machine.push(y);
    try std.testing.expect(machine.stack_pointer == 0x00);
    const answer = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf };
    inline for (machine.memory, answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "pop" {
    var machine = Machine(16){
        .memory = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf },
        .stack_pointer = 0,
    };
    var x: u64 = 0;
    var y: u64 = 0;
    machine.pop(&x);
    try std.testing.expect(machine.stack_pointer == 0x08 and x == 0xa7a6a5a4a3a2a1a0);
    machine.pop(&y);
    try std.testing.expect(machine.stack_pointer == 0x10 and y == 0xafaeadacabaaa9a8);
}

test "fetch" {
    var machine = Machine(16){
        .memory = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf },
    };
    var w: u64 = 0;
    machine.fetch(1, &w);
    try std.testing.expect(machine.program_counter == 0x01 and w == 0x00000000000000a0);
    machine.fetch(2, &w);
    try std.testing.expect(machine.program_counter == 0x03 and w == 0x000000000000a2a1);
    machine.fetch(4, &w);
    try std.testing.expect(machine.program_counter == 0x07 and w == 0x00000000a6a5a4a3);
    machine.fetch(8, &w);
    try std.testing.expect(machine.program_counter == 0x0f and w == 0xaeadacabaaa9a8a7);
}

test "machine" {
    var machine = Machine(256){};
    machine.memory[0x00..0x28].* = .{ 0x01, 0x09, 0x1a, 0x09, 0x00, 0x09, 0x01, 0x09, 0x15, 0x09, 0x01, 0x09, 0x00, 0x03, 0x01, 0x00, 0x04, 0x02, 0x02, 0x00, 0x02, 0x03, 0x02, 0x04, 0x04, 0x00, 0x07, 0x06, 0x09, 0x01, 0x30, 0x09, 0xf8, 0x05, 0x09, 0x02, 0x30, 0x09, 0x00, 0x00 };
    machine.run();
    std.debug.print("P = 0x{x}, S = 0x{x}\n", .{ machine.program_counter, machine.stack_pointer });
    try std.testing.expect(machine.terminated == true and machine.program_counter == 0x25 and machine.stack_pointer == 0xf8);
    const answer = .{ 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    inline for (machine.memory[0xe8..], answer) |actual, expected| try std.testing.expect(actual == expected);
}
