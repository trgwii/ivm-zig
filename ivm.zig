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

        fn countPrintedChars(s: []const u8) u64 {
            var printedChars: u32 = 0;
            var i: usize = 0;
            while (i < s.len) : (i += 1) {
                const c = s[i];
                if (c == '\x1b') {
                    if (std.mem.indexOfScalar(u8, s[i + 1 ..], 'm')) |idx| {
                        i += idx + 1;
                        continue;
                    }
                    continue;
                }
                printedChars += 1;
            }
            return printedChars;
        }

        fn printProgram(self: *Self, len: u64) void {
            std.debug.print("\n", .{});
            while (self.program_counter < len) {
                const inst = self.fetch(Inst) catch return;
                switch (inst) {
                    .EXIT,
                    .NOP,
                    .JUMP,
                    .SET_SP,
                    .GET_PC,
                    .GET_SP,
                    .LOAD1,
                    .LOAD2,
                    .LOAD4,
                    .LOAD8,
                    .STORE1,
                    .STORE2,
                    .STORE4,
                    .STORE8,
                    .ADD,
                    .MULT,
                    .CHECK,
                    => std.debug.print("\x1b[33m{s}\x1b[0m\n", .{@tagName(inst)}),
                    .PUSH0 => {
                        std.debug.print("\x1b[33m{s}\x1b[0m\n", .{@tagName(inst)});
                        _ = self.fetch(u8) catch {};
                    },
                    .JZ_FWD,
                    .JZ_BACK,
                    .PUSH1,
                    => std.debug.print("\x1b[33m{s}\x1b[32m 0x{x:0>4}\x1b[0m\n", .{ @tagName(inst), self.fetch(u8) catch return }),
                    .PUSH2,
                    => std.debug.print("\x1b[33m{s}\x1b[32m 0x{x:0>4}\x1b[0m\n", .{ @tagName(inst), self.fetch(u16) catch return }),
                    .PUSH4,
                    => std.debug.print("\x1b[33m{s}\x1b[32m 0x{x:0>4}\x1b[0m\n", .{ @tagName(inst), self.fetch(u32) catch return }),
                    .PUSH8,
                    => std.debug.print("\x1b[33m{s}\x1b[32m 0x{x:0>4}\x1b[0m\n", .{ @tagName(inst), self.fetch(u64) catch return }),
                    else => {
                        std.debug.print("(unimplemented) \x1b[33m{s}\x1b[0m\n", .{@tagName(inst)});
                    },
                }
            }
        }

        fn printMemory(self: Self) void {
            for (self.memory, 0..) |x, i| {
                if (i % 32 == 0) std.debug.print("\n\x1b[34m0x{x:0>4}\x1b[30m..\x1b[34m0x{x:0>4}\x1b[30m: ", .{ i, i + 32 });
                std.debug.print("\x1b[32m{x:0>2}", .{x});
            }
            std.debug.print("\x1b[0m\n", .{});
        }

        fn printDebugState(self: Self) void {
            var mem: [1024]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&mem);
            var list = std.ArrayList(u8).init(fba.allocator());
            const w = list.writer();
            w.print("[", .{}) catch unreachable;
            var s = self.stack_pointer;
            var i: u64 = 0;
            const too_big = while (s < N) : (s += @sizeOf(u64)) {
                i += 1;
                if (i > 6) break true;
                w.print("{s}\x1b[{s}m0x{x:0>4}\x1b[0m", .{
                    if (s == self.stack_pointer) "" else "\x1b[30m,\x1b[0m ",
                    if (s == self.stack_pointer) "33" else "34",
                    self.get(u64, s) catch unreachable,
                }) catch unreachable;
            } else false;
            w.print("{s}] \x1b[35mPC\x1b[0m \x1b[34m0x{x:0>4}\x1b[0m \x1b[33mSP\x1b[0m \x1b[34m0x{x:0>4}\x1b[0m {s}", .{
                if (too_big) "\x1b[30m, ...\x1b[0m" else "",
                self.program_counter,
                self.stack_pointer,
                if (self.terminated) "\x1b[31mT\x1b[0m" else "\x1b[32mR\x1b[0m",
            }) catch unreachable;
            const printedChars = countPrintedChars(list.items);
            if (printedChars < 80) for (0..80 - printedChars) |_| std.debug.print(" ", .{});
            std.debug.print("{s}\n", .{list.items});
        }

        pub const Error = error{
            AddressOutOfBounds,
            StackPointerOutOfBounds,
            ProgramCounterOutOfBounds,
        };

        fn put(self: *Self, comptime T: type, x: T, a: u64) Error!void {
            if (a > self.memory.len - @sizeOf(T)) return Error.AddressOutOfBounds;
            @as(*align(1) T, @ptrCast(&self.memory[a])).* = std.mem.nativeToLittle(T, x);
        }
        fn get(self: *const Self, comptime T: type, a: u64) !T {
            if (a > self.memory.len - @sizeOf(T)) return Error.AddressOutOfBounds;
            return std.mem.littleToNative(T, @as(*align(1) const T, @ptrCast(&self.memory[a])).*);
        }
        pub fn push(self: *Self, x: u64) !void {
            self.stack_pointer -%= @sizeOf(u64);
            self.put(u64, x, self.stack_pointer) catch return Error.StackPointerOutOfBounds;
        }
        pub fn pop(self: *Self) !u64 {
            const x = self.get(u64, self.stack_pointer) catch return Error.StackPointerOutOfBounds;
            self.stack_pointer +%= @sizeOf(u64);
            return x;
        }
        pub fn fetch(self: *Self, comptime T: type) !T {
            const x = self.get(T, self.program_counter) catch return Error.ProgramCounterOutOfBounds;
            self.program_counter += @sizeOf(T);
            return x;
        }
        pub const Inst = enum(u8) {
            EXIT = 0x00,
            NOP = 0x01,
            JUMP = 0x02,
            JZ_FWD = 0x03,
            JZ_BACK = 0x04,
            SET_SP = 0x05,
            GET_PC = 0x06,
            GET_SP = 0x07,
            PUSH0 = 0x08,
            PUSH1 = 0x09,
            PUSH2 = 0x0A,
            PUSH4 = 0x0B,
            PUSH8 = 0x0C,
            LOAD1 = 0x10,
            LOAD2 = 0x11,
            LOAD4 = 0x12,
            LOAD8 = 0x13,
            STORE1 = 0x14,
            STORE2 = 0x15,
            STORE4 = 0x16,
            STORE8 = 0x17,
            ADD = 0x20,
            MULT = 0x21,
            DIV = 0x22,
            REM = 0x23,
            LT = 0x24,
            AND = 0x28,
            OR = 0x29,
            NOT = 0x2A,
            XOR = 0x2B,
            POW2 = 0x2C,
            CHECK = 0x30,
            READ_CHAR = 0xF8,
            PUT_BYTE = 0xF9,
            PUT_CHAR = 0xFA,
            ADD_SAMPLE = 0xFB,
            SET_PIXEL = 0xFC,
            NEW_FRAME = 0xFD,
            READ_PIXEL = 0xFE,
            READ_FRAME = 0xFF,
            _,
            fn isKnown(self: Inst) bool {
                return switch (self) {
                    .EXIT,
                    .NOP,
                    .JUMP,
                    .JZ_FWD,
                    .JZ_BACK,
                    .SET_SP,
                    .GET_PC,
                    .GET_SP,
                    .PUSH0,
                    .PUSH1,
                    .PUSH2,
                    .PUSH4,
                    .PUSH8,
                    .LOAD1,
                    .LOAD2,
                    .LOAD4,
                    .LOAD8,
                    .STORE1,
                    .STORE2,
                    .STORE4,
                    .STORE8,
                    .ADD,
                    .MULT,
                    .DIV,
                    .REM,
                    .LT,
                    .AND,
                    .OR,
                    .NOT,
                    .XOR,
                    .POW2,
                    .CHECK,
                    .READ_CHAR,
                    .PUT_BYTE,
                    .PUT_CHAR,
                    .ADD_SAMPLE,
                    .SET_PIXEL,
                    .NEW_FRAME,
                    .READ_PIXEL,
                    .READ_FRAME,
                    => true,
                    _ => false,
                };
            }
        };
        fn exception(self: *Self, log: bool, err: Error, values: anytype) void {
            if (log) std.debug.print(" \x1b[31m{s}\x1b[0m", .{@errorName(err)});
            if (log) {
                if (values.len != 0) std.debug.print("\x1b[30m:\x1b[0m", .{});
                inline for (values) |v| std.debug.print(" \x1b[34m0x{x:0>4}\x1b[0m", .{v});
            }
            if (log) std.debug.print("\n", .{});
            self.terminated = true;
        }
        /// The main procedure
        fn main(self: *Self, comptime options: RunOptions) void {
            const inst = self.fetch(Inst) catch |err| return self.exception(options.debug, err, .{});
            const log = options.debug and inst.isKnown();
            if (log) std.debug.print("\x1b[33m{s}\x1b[0m", .{@tagName(inst)});
            switch (inst) {
                .EXIT => self.terminated = true,
                .NOP => {},
                .JUMP => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[35mPC\x1b[30m = \x1b[34m0x{x:0>4}\x1b[0m", .{a});
                    self.program_counter = a;
                },
                .JZ_FWD => {
                    const a = self.fetch(u8) catch |err| return self.exception(log, err, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[30mif (\x1b[32m0x{x:0>4}\x1b[30m == \x1b[32m0\x1b[30m) then \x1b[35mPC\x1b[30m += \x1b[32m0x{x:0>4}\x1b[0m", .{ x, a });
                    if (x == 0) self.program_counter += a;
                },
                .JZ_BACK => {
                    const a = self.fetch(u8) catch |err| return self.exception(log, err, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[30mif (\x1b[32m0x{x:0>4}\x1b[30m == \x1b[32m0\x1b[30m) then \x1b[35mPC\x1b[30m -= (\x1b[32m0x{x:0>4}\x1b[30m + \x1b[32m1\x1b[30m)\x1b[0m", .{ x, a });
                    if (x == 0) self.program_counter -= a + 1;
                },
                .SET_SP => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[33mSP\x1b[30m = \x1b[34m0x{x:0>4}\x1b[0m", .{a});
                    self.stack_pointer = a;
                },
                .GET_PC => {
                    if (log) std.debug.print(" \x1b[34m0x{x:0>4}\x1b[0m", .{self.program_counter});
                    self.push(self.program_counter) catch |err| return self.exception(log, err, .{});
                },
                .GET_SP => {
                    if (log) std.debug.print(" \x1b[34m0x{x:0>4}\x1b[0m", .{self.stack_pointer});
                    self.push(self.stack_pointer) catch |err| return self.exception(log, err, .{});
                },
                .PUSH0 => {
                    _ = self.fetch(u8) catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4}\x1b[0m", .{0});
                    self.push(0) catch |err| return self.exception(log, err, .{});
                },
                .PUSH1 => {
                    const x = self.fetch(u8) catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4}\x1b[0m", .{x});
                    self.push(x) catch |err| return self.exception(log, err, .{});
                },
                .PUSH2 => {
                    const x = self.fetch(u16) catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4}\x1b[0m", .{x});
                    self.push(x) catch |err| return self.exception(log, err, .{});
                },
                .PUSH4 => {
                    const x = self.fetch(u32) catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4}\x1b[0m", .{x});
                    self.push(x) catch |err| return self.exception(log, err, .{});
                },
                .PUSH8 => {
                    const x = self.fetch(u64) catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4}\x1b[0m", .{x});
                    self.push(x) catch |err| return self.exception(log, err, .{});
                },
                .LOAD1 => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    const x = self.get(u8, a) catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4} \x1b[30mfrom \x1b[34m0x{x:0>4}\x1b[0m", .{ x, a });
                    self.push(x) catch |err| return self.exception(log, err, .{});
                },
                .LOAD2 => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    const x = self.get(u16, a) catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4} \x1b[30mfrom \x1b[34m0x{x:0>4}\x1b[0m", .{ x, a });
                    self.push(x) catch |err| return self.exception(log, err, .{});
                },
                .LOAD4 => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    const x = self.get(u32, a) catch |err| return self.exception(log, err, .{a});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4} \x1b[30mfrom \x1b[34m0x{x:0>4}\x1b[0m", .{ x, a });
                    self.push(x) catch |err| return self.exception(log, err, .{});
                },
                .LOAD8 => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    const x = self.get(u64, a) catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4} \x1b[30mfrom \x1b[34m0x{x:0>4}\x1b[0m", .{ x, a });
                    self.push(x) catch |err| return self.exception(log, err, .{});
                },
                .STORE1 => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    const x: u8 = @truncate(self.pop() catch |err| return self.exception(log, err, .{}));
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4} \x1b[30minto \x1b[34m0x{x:0>4}\x1b[0m", .{ x, a });
                    self.put(u8, x, a) catch |err| return self.exception(log, err, .{});
                },
                .STORE2 => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    const x: u16 = @truncate(self.pop() catch |err| return self.exception(log, err, .{}));
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4} \x1b[30minto \x1b[34m0x{x:0>4}\x1b[0m", .{ x, a });
                    self.put(u16, x, a) catch |err| return self.exception(log, err, .{});
                },
                .STORE4 => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    const x: u32 = @truncate(self.pop() catch |err| return self.exception(log, err, .{}));
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4} \x1b[30minto \x1b[34m0x{x:0>4}\x1b[0m", .{ x, a });
                    self.put(u32, x, a) catch |err| return self.exception(log, err, .{});
                },
                .STORE8 => {
                    const a = self.pop() catch |err| return self.exception(log, err, .{});
                    const x: u64 = self.pop() catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4} \x1b[30minto \x1b[34m0x{x:0>4}\x1b[0m", .{ x, a });
                    self.put(u64, x, a) catch |err| return self.exception(log, err, .{});
                },
                .ADD => {
                    const x = self.pop() catch |err| return self.exception(log, err, .{});
                    const y = self.pop() catch |err| return self.exception(log, err, .{});
                    const r = x + y;
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4}\x1b[30m + \x1b[32m0x{x:0>4}\x1b[30m = \x1b[32m0x{x:0>4}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, .{});
                },
                .MULT => {
                    const x = self.pop() catch |err| return self.exception(log, err, .{});
                    const y = self.pop() catch |err| return self.exception(log, err, .{});
                    const r = x * y;
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4}\x1b[30m * \x1b[32m0x{x:0>4}\x1b[30m = \x1b[32m0x{x:0>4}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, .{});
                },
                .DIV,
                .REM,
                .LT,
                .AND,
                .OR,
                .NOT,
                .XOR,
                .POW2,
                => @panic("Unimplemented"),
                .CHECK => {
                    const x = self.pop() catch |err| return self.exception(log, err, .{});
                    if (log) std.debug.print(" \x1b[32m0x{x:0>4}\x1b[0m", .{x});
                    if (x >= 2) self.terminated = true;
                },
                .READ_CHAR,
                .PUT_BYTE,
                .PUT_CHAR,
                .ADD_SAMPLE,
                .SET_PIXEL,
                .NEW_FRAME,
                .READ_PIXEL,
                .READ_FRAME,
                => @panic("Unimplemented"),
                _ => |k| {
                    std.debug.print("hit unknown instruction: 0x{x}\n", .{k});
                    self.terminated = true;
                },
            }
            if (log) std.debug.print("\n", .{});
        }
        pub const RunOptions = struct { debug: bool = false };
        pub fn run(self: *Self, comptime options: RunOptions) void {
            if (options.debug) std.debug.print("\n", .{});
            while (!self.terminated) {
                if (options.debug) self.printDebugState();
                self.main(options);
            }
            if (options.debug) self.printDebugState();
        }
    };
}

test "put" {
    var machine = Machine(16){};
    const x: u64 = 0xa7a6a5a4a3a2a1a0;
    try machine.put(u8, @truncate(x), 0x01);
    try machine.put(u16, @truncate(x), 0x02);
    try machine.put(u32, @truncate(x), 0x04);
    try machine.put(u64, x, 0x08);
    const answer = .{ 0x00, 0xa0, 0xa0, 0xa1, 0xa0, 0xa1, 0xa2, 0xa3, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7 };
    inline for (machine.memory, answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "get" {
    var machine = Machine(16){
        .memory = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf },
    };
    try std.testing.expect(try machine.get(u8, 1) == 0x00000000000000a1);
    try std.testing.expect(try machine.get(u16, 2) == 0x000000000000a3a2);
    try std.testing.expect(try machine.get(u32, 4) == 0x00000000a7a6a5a4);
    try std.testing.expect(try machine.get(u64, 8) == 0xafaeadacabaaa9a8);
}

test "push" {
    var machine = Machine(16){};
    const x: u64 = 0xafaeadacabaaa9a8;
    const y: u64 = 0xa7a6a5a4a3a2a1a0;
    try machine.push(x);
    try std.testing.expect(machine.stack_pointer == 0x08);
    try machine.push(y);
    try std.testing.expect(machine.stack_pointer == 0x00);
    const answer = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf };
    inline for (machine.memory, answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "pop" {
    var machine = Machine(16){
        .memory = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf },
        .stack_pointer = 0,
    };
    const x = try machine.pop();
    try std.testing.expect(machine.stack_pointer == 0x08 and x == 0xa7a6a5a4a3a2a1a0);
    const y = try machine.pop();
    try std.testing.expect(machine.stack_pointer == 0x10 and y == 0xafaeadacabaaa9a8);
}

test "fetch" {
    var machine = Machine(16){
        .memory = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf },
    };
    try std.testing.expect(try machine.fetch(u8) == 0x00000000000000a0);
    try std.testing.expect(machine.program_counter == 0x01);
    try std.testing.expect(try machine.fetch(u16) == 0x000000000000a2a1);
    try std.testing.expect(machine.program_counter == 0x03);
    try std.testing.expect(try machine.fetch(u32) == 0x00000000a6a5a4a3);
    try std.testing.expect(machine.program_counter == 0x07);
    try std.testing.expect(try machine.fetch(u64) == 0xaeadacabaaa9a8a7);
    try std.testing.expect(machine.program_counter == 0x0f);
}

test "a very basic machine" {
    var machine = Machine(256){};
    machine.memory[0x00..0x28].* = .{ 0x01, 0x09, 0x1a, 0x09, 0x00, 0x09, 0x01, 0x09, 0x15, 0x09, 0x01, 0x09, 0x00, 0x03, 0x01, 0x00, 0x04, 0x02, 0x02, 0x00, 0x02, 0x03, 0x02, 0x04, 0x04, 0x00, 0x07, 0x06, 0x09, 0x01, 0x30, 0x09, 0xf8, 0x05, 0x09, 0x02, 0x30, 0x09, 0x00, 0x00 };
    machine.run(.{ .debug = false });
    try std.testing.expect(machine.terminated == true and machine.program_counter == 0x25 and machine.stack_pointer == 0xf8);
    const answer = .{ 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    inline for (machine.memory[0xe8..], answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "adding bit-copying capabilities" {
    var machine = Machine(256){};
    machine.memory[0x00..0x28].* = .{ 0x08, 0x19, 0x13, 0x08, 0xe0, 0x17, 0x08, 0x21, 0x12, 0x08, 0xe8, 0x16, 0x08, 0x25, 0x11, 0x08, 0xec, 0x15, 0x08, 0x27, 0x10, 0x08, 0xee, 0x14, 0x00, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae };
    machine.run(.{ .debug = false });
    try std.testing.expect(machine.terminated == true and machine.stack_pointer == 0x100);
    const answer = [_]u8{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0x00 };
    inline for (machine.memory[0x19..0x29], answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "adding more bit-copying capabilities" {
    var machine = Machine(256){};
    machine.memory[0x00..0x13].* = .{ 0x07, 0x09, 0x20, 0x21, 0x0a, 0x10, 0x11, 0x12, 0x13, 0x0b, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x00 };
    machine.printProgram(0x13);
    machine.program_counter = 0;
    machine.run(.{ .debug = true });
    machine.printMemory();
    try std.testing.expect(machine.terminated == true and machine.stack_pointer == 0xe0);
    const answer = .{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x10, 0x11, 0x12, 0x13, 0x00, 0x00, 0x00, 0x00, 0x20, 0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    inline for (machine.memory[0xe0..0x100], answer) |actual, expected| try std.testing.expect(actual == expected);
}
