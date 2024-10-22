const builtin = @import("builtin");
const std = @import("std");
const c = @cImport({
    @cInclude("windows.h");
});

const BufferedIOBufferSize = 65536;

const MachineOptions = struct {
    strange_push0_behavior: bool = false,
    buffered_io: bool = true,
    flush_every_line: bool = false,
};
pub fn Machine(comptime N: u64, comptime machine_options: MachineOptions) type {
    return struct {
        /// T
        terminated: bool = false,
        /// M
        memory: [N]u8 = [_]u8{0} ** N,
        /// P
        program_counter: u64 = 0,
        /// S
        stack_pointer: u64 = N,

        stack_size: u64 = N,

        current_read_frame: if (builtin.target.os.tag == .windows) ?c.HANDLE else void =
            if (builtin.target.os.tag == .windows) null else {},

        current_write_frame: c.HWND,

        buffered_stderr: if (machine_options.buffered_io) std.io.BufferedWriter(BufferedIOBufferSize, std.fs.File.Writer) else void =
            undefined,
        buffered_stdout: if (machine_options.buffered_io) std.io.BufferedWriter(BufferedIOBufferSize, std.fs.File.Writer) else void =
            undefined,

        const Self = @This();

        pub fn init(self: *Self) void {
            self.terminated = false;
            self.program_counter = 0;
            self.stack_pointer = N;
            self.stack_size = N;
            if (builtin.target.os.tag == .windows) self.current_read_frame = null;
            self.initBufferedIO();
        }

        pub fn initBufferedIO(self: *Self) void {
            if (machine_options.buffered_io) {
                self.buffered_stderr = .{ .unbuffered_writer = std.io.getStdErr().writer() };
                self.buffered_stdout = .{ .unbuffered_writer = std.io.getStdOut().writer() };
            }
        }

        pub fn debugLog(self: *Self, comptime colors: bool, comptime fmt: []const u8, args: anytype) void {
            const actual_fmt = comptime if (colors) fmt else removeColorsFmt(fmt);
            if (machine_options.buffered_io)
                self.buffered_stderr.writer().print(actual_fmt, args) catch unreachable
            else
                std.io.getStdErr().writer().print(actual_fmt, args) catch unreachable;
        }

        pub fn debugFlush(self: *Self) void {
            if (machine_options.buffered_io) {
                self.buffered_stderr.flush() catch unreachable;
                self.buffered_stdout.flush() catch unreachable;
            }
        }

        fn removeColorsFmt(comptime fmt: []const u8) []const u8 {
            comptime var result_fmt: []const u8 = &.{};
            comptime var i: usize = 0;
            inline while (i < fmt.len) : (i += 1) {
                if (fmt[i] == '\x1b') {
                    if (comptime std.mem.indexOfScalar(u8, fmt[i + 1 ..], 'm')) |idx| {
                        i += idx + 1;
                        continue;
                    }
                    continue;
                }
                result_fmt = result_fmt ++ &[_]u8{fmt[i]};
            }
            return result_fmt;
        }

        fn countPrintedChars(s: []const u8) u64 {
            var printedChars: u32 = 0;
            var i: usize = 0;
            while (i < s.len) : (i += 1) {
                if (s[i] == '\x1b') {
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

        pub fn setProgramLength(self: *Self, len: u64) !void {
            if (len > N) return error.ProgramTooLarge;
            self.stack_size = N - len;
        }

        pub fn loadProgram(self: *Self, program: []const u8) !void {
            try self.setProgramLength(program.len);
            @memcpy(self.memory[0..program.len], program);
        }

        pub fn printProgram(self: *Self, comptime colors: bool, len: u64) void {
            defer self.debugFlush();
            self.debugLog(colors, "\n", .{});
            const pc = self.program_counter;
            defer self.program_counter = pc;
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
                    .DIV,
                    .REM,
                    .LT,
                    .AND,
                    .OR,
                    .NOT,
                    .XOR,
                    .POW2,
                    .CHECK,
                    .PUT_BYTE,
                    .PUT_CHAR,
                    .NEW_FRAME,
                    => self.debugLog(colors, "\x1b[33m{s}\x1b[0m\n", .{@tagName(inst)}),
                    .PUSH0 => {
                        self.debugLog(colors, "\x1b[33m{s}\x1b[0m\n", .{@tagName(inst)});
                        if (machine_options.strange_push0_behavior) _ = self.fetch(u8) catch {};
                    },
                    .JZ_FWD,
                    .JZ_BACK,
                    .PUSH1,
                    => self.debugLog(colors, "\x1b[33m{s}\x1b[32m 0x{x:0>2}\x1b[0m\n", .{ @tagName(inst), self.fetch(u8) catch return }),
                    .PUSH2 => self.debugLog(colors, "\x1b[33m{s}\x1b[32m 0x{x:0>2}\x1b[0m\n", .{ @tagName(inst), self.fetch(u16) catch return }),
                    .PUSH4 => self.debugLog(colors, "\x1b[33m{s}\x1b[32m 0x{x:0>2}\x1b[0m\n", .{ @tagName(inst), self.fetch(u32) catch return }),
                    .PUSH8 => self.debugLog(colors, "\x1b[33m{s}\x1b[32m 0x{x:0>2}\x1b[0m\n", .{ @tagName(inst), self.fetch(u64) catch return }),
                    // .READ_CHAR,
                    // .ADD_SAMPLE,
                    // .SET_PIXEL,
                    // .READ_PIXEL,
                    // .READ_FRAME,
                    // => @panic("Unimplemented"),
                    else => {
                        self.debugLog(colors, "(unimplemented) \x1b[33m0x{x:0>2}\x1b[0m\n", .{@intFromEnum(inst)});
                    },
                }
            }
        }

        pub fn printMemory(self: *Self, comptime colors: bool, limit: ?u64) void {
            defer self.debugFlush();
            for (self.memory[0 .. limit orelse self.memory.len], 0..) |x, i| {
                if (i % 32 == 0) self.debugLog(colors, "\n\x1b[34m0x{x:0>2}\x1b[90m..\x1b[34m0x{x:0>2}\x1b[90m: ", .{ i, i + 32 });
                self.debugLog(colors, "\x1b[32m{x:0>2}", .{x});
            }
            self.debugLog(colors, "\n\x1b[90m                000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\x1b[0m\n", .{});
        }

        fn printDebugState(self: *Self, comptime colors: bool, comptime right_align_machine_state: bool) void {
            const maybeRemoveColors = if (colors) struct {
                fn id(x: anytype) @TypeOf(x) {
                    return x;
                }
            }.id else removeColorsFmt;
            const w = if (right_align_machine_state) b: {
                var mem: [1024]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&mem);
                var list = std.ArrayList(u8).init(fba.allocator());
                const w = list.writer();
                break :b w;
            } else if (machine_options.buffered_io)
                self.buffered_stderr.writer()
            else
                std.io.getStdErr().writer();
            w.print("[", .{}) catch unreachable;
            var s = self.stack_pointer;
            var i: u64 = 0;
            const too_big = while (s < N) : (s += @sizeOf(u64)) {
                i += 1;
                if (i > 6) break true;
                w.print(comptime maybeRemoveColors("{s}\x1b[{s}m0x{x:0>2}\x1b[0m"), if (colors) .{
                    if (s == self.stack_pointer) "" else comptime maybeRemoveColors("\x1b[90m,\x1b[0m "),
                    if (s == self.stack_pointer) "33" else "34",
                    self.get(u64, s) catch unreachable,
                } else .{
                    if (s == self.stack_pointer) "" else comptime maybeRemoveColors("\x1b[90m,\x1b[0m "),
                    self.get(u64, s) catch unreachable,
                }) catch unreachable;
            } else false;
            if (builtin.os.tag == .windows) {
                w.print(comptime maybeRemoveColors("{s}] \x1b[35mPC\x1b[0m \x1b[34m0x{x:0>2}\x1b[0m \x1b[33mSP\x1b[0m \x1b[34m0x{x:0>2}\x1b[90m [\x1b[32m{}\x1b[90m/\x1b[32m{}\x1b[90m]\x1b[0m {s} {s}"), .{
                    if (too_big) comptime maybeRemoveColors("\x1b[90m, ...\x1b[0m") else "",
                    self.program_counter,
                    self.stack_pointer,
                    (N - self.stack_pointer) / 8,
                    self.stack_size / 8,
                    if (self.current_read_frame) |_| comptime maybeRemoveColors("\x1b[36mF\x1b[0m") else comptime maybeRemoveColors("\x1b[90m_\x1b[0m"),
                    if (self.terminated) comptime maybeRemoveColors("\x1b[31mT\x1b[0m") else comptime maybeRemoveColors("\x1b[32mR\x1b[0m"),
                }) catch unreachable;
            } else {
                w.print(comptime maybeRemoveColors("{s}] \x1b[35mPC\x1b[0m \x1b[34m0x{x:0>2}\x1b[0m \x1b[33mSP\x1b[0m \x1b[34m0x{x:0>2}\x1b[90m [\x1b[32m{}\x1b[90m/\x1b[32m{}\x1b[90m]\x1b[0m {s}"), .{
                    if (too_big) comptime maybeRemoveColors("\x1b[90m, ...\x1b[0m") else "",
                    self.program_counter,
                    self.stack_pointer,
                    (N - self.stack_pointer) / 8,
                    self.stack_size / 8,
                    if (self.terminated) comptime maybeRemoveColors("\x1b[31mT\x1b[0m") else comptime maybeRemoveColors("\x1b[32mR\x1b[0m"),
                }) catch unreachable;
            }
            if (right_align_machine_state) {
                const list = w.context;
                const printedChars = countPrintedChars(list.items);
                if (printedChars < 80) for (0..80 - printedChars) |_| self.debugLog(false, " ", .{});
                self.debugLog(false, "{s}\n", .{list.items});
            }
        }

        pub const Error = error{
            AddressOutOfBounds,
            StackUnderflow,
            StackOverflow,
            StackPointerOutOfBounds,
            ProgramCounterOutOfBounds,
        };

        fn put(self: *Self, comptime T: type, x: T, a: u64) Error!void {
            if (a > N - @sizeOf(T)) return Error.AddressOutOfBounds;
            @as(*align(1) T, @ptrCast(&self.memory[a])).* = std.mem.nativeToLittle(T, x);
        }
        fn get(self: *const Self, comptime T: type, a: u64) !T {
            if (a > N - @sizeOf(T)) return Error.AddressOutOfBounds;
            return std.mem.littleToNative(T, @as(*align(1) const T, @ptrCast(&self.memory[a])).*);
        }
        pub fn push(self: *Self, x: u64) !void {
            const next = self.stack_pointer - @sizeOf(u64);
            if (next < N - self.stack_size) return Error.StackOverflow;
            self.stack_pointer -%= @sizeOf(u64);
            self.put(u64, x, self.stack_pointer) catch return Error.StackPointerOutOfBounds;
        }
        pub fn pop(self: *Self) !u64 {
            const x = self.get(u64, self.stack_pointer) catch return Error.StackUnderflow;
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
        fn exception(self: *Self, log: bool, err: Error, comptime colors: bool, values: anytype) void {
            if (log) self.debugLog(colors, " \x1b[31m{s}\x1b[0m", .{@errorName(err)});
            if (log) {
                if (values.len != 0) self.debugLog(colors, "\x1b[90m:\x1b[0m", .{});
                inline for (values) |v| self.debugLog(colors, " \x1b[34m0x{x:0>2}\x1b[0m", .{v});
            }
            if (log) self.debugLog(colors, "\n", .{});
            self.terminated = true;
        }
        /// The main procedure
        fn main(self: *Self, comptime options: RunOptions) void {
            const inst = self.fetch(Inst) catch |err| return self.exception(options.debug, err, options.colors, .{});
            const log = options.debug and inst.isKnown();
            if (log) self.debugLog(options.colors, "\x1b[33m0x{x:0>2}\x1b[90m:\x1b[33m{s}\x1b[0m", .{ @intFromEnum(inst), @tagName(inst) });
            switch (inst) {
                .EXIT => self.terminated = true,
                .NOP => {},
                .JUMP => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[35mPC\x1b[90m = \x1b[34m0x{x:0>2}\x1b[0m", .{a});
                    self.program_counter = a;
                },
                .JZ_FWD => {
                    const a = self.fetch(u8) catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[90mif (\x1b[32m0x{x:0>2}\x1b[90m == \x1b[32m0\x1b[90m) then \x1b[35mPC\x1b[90m += \x1b[32m0x{x:0>2}\x1b[0m", .{ x, a });
                    if (x == 0) self.program_counter += a;
                },
                .JZ_BACK => {
                    const a = self.fetch(u8) catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[90mif (\x1b[32m0x{x:0>2}\x1b[90m == \x1b[32m0\x1b[90m) then \x1b[35mPC\x1b[90m -= (\x1b[32m0x{x:0>2}\x1b[90m + \x1b[32m1\x1b[90m)\x1b[0m", .{ x, a });
                    if (x == 0) self.program_counter -= a + 1;
                },
                .SET_SP => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[33mSP\x1b[90m = \x1b[34m0x{x:0>2}\x1b[0m", .{a});
                    if (a > N) return self.exception(log, Error.StackUnderflow, options.colors, .{});
                    if (a < N - self.stack_size) return self.exception(log, Error.StackOverflow, options.colors, .{});
                    self.stack_pointer = a;
                },
                .GET_PC => {
                    if (log) self.debugLog(options.colors, " \x1b[34m0x{x:0>2}\x1b[0m", .{self.program_counter});
                    self.push(self.program_counter) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .GET_SP => {
                    if (log) self.debugLog(options.colors, " \x1b[34m0x{x:0>2}\x1b[0m", .{self.stack_pointer});
                    self.push(self.stack_pointer) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .PUSH0 => {
                    if (machine_options.strange_push0_behavior) _ = self.fetch(u8) catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[0m", .{0});
                    self.push(0) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .PUSH1 => {
                    const x = self.fetch(u8) catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[0m", .{x});
                    self.push(x) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .PUSH2 => {
                    const x = self.fetch(u16) catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[0m", .{x});
                    self.push(x) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .PUSH4 => {
                    const x = self.fetch(u32) catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[0m", .{x});
                    self.push(x) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .PUSH8 => {
                    const x = self.fetch(u64) catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[0m", .{x});
                    self.push(x) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .LOAD1 => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.get(u8, a) catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2} \x1b[90mfrom \x1b[34m0x{x:0>2}\x1b[0m", .{ x, a });
                    self.push(x) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .LOAD2 => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.get(u16, a) catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2} \x1b[90mfrom \x1b[34m0x{x:0>2}\x1b[0m", .{ x, a });
                    self.push(x) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .LOAD4 => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.get(u32, a) catch |err| return self.exception(log, err, options.colors, .{a});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2} \x1b[90mfrom \x1b[34m0x{x:0>2}\x1b[0m", .{ x, a });
                    self.push(x) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .LOAD8 => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.get(u64, a) catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2} \x1b[90mfrom \x1b[34m0x{x:0>2}\x1b[0m", .{ x, a });
                    self.push(x) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .STORE1 => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x: u8 = @truncate(self.pop() catch |err| return self.exception(log, err, options.colors, .{}));
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2} \x1b[90minto \x1b[34m0x{x:0>2}\x1b[0m", .{ x, a });
                    self.put(u8, x, a) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .STORE2 => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x: u16 = @truncate(self.pop() catch |err| return self.exception(log, err, options.colors, .{}));
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2} \x1b[90minto \x1b[34m0x{x:0>2}\x1b[0m", .{ x, a });
                    self.put(u16, x, a) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .STORE4 => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x: u32 = @truncate(self.pop() catch |err| return self.exception(log, err, options.colors, .{}));
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2} \x1b[90minto \x1b[34m0x{x:0>2}\x1b[0m", .{ x, a });
                    self.put(u32, x, a) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .STORE8 => {
                    const a = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x: u64 = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2} \x1b[90minto \x1b[34m0x{x:0>2}\x1b[0m", .{ x, a });
                    self.put(u64, x, a) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .ADD => {
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = x +% y;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m + \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .MULT => {
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = x *% y;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m * \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .DIV => {
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = x / y;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m / \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .REM => {
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = x % y;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m % \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .LT => {
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r: u64 = if (x < y) 0xffffffffffffffff else 0;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m < \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .AND => {
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = x & y;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m & \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .OR => {
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = x | y;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m | \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .NOT => {
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = ~x;
                    if (log) self.debugLog(options.colors, " \x1b[90m~\x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .XOR => {
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = x ^ y;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m ^ \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ x, y, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .POW2 => {
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = if (x < 64) std.math.pow(u64, 2, x) else 0;
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[90m ^ \x1b[32m0x{x:0>2}\x1b[90m = \x1b[32m0x{x:0>2}\x1b[0m", .{ 2, x, r });
                    self.push(r) catch |err| return self.exception(log, err, options.colors, .{});
                },
                .CHECK => {
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m0x{x:0>2}\x1b[0m", .{x});
                    if (x >= 2) self.terminated = true;
                },
                .READ_CHAR => @panic("Unimplemented"),
                .PUT_BYTE, .PUT_CHAR => {
                    const char: u8 = @intCast(self.pop() catch |err| return self.exception(log, err, options.colors, .{}));
                    if (log) self.debugLog(options.colors, " \x1b[32m'{c}'\x1b[0m", .{char});
                    if (machine_options.buffered_io) {
                        self.buffered_stdout.writer().writeByte(char) catch unreachable;
                        if (machine_options.flush_every_line and char == '\n') {
                            self.debugFlush();
                        }
                    } else {
                        std.io.getStdOut().writer().writeByte(char) catch unreachable;
                    }
                },
                .SET_PIXEL => {
                    const b = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const g = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const r = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const y = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const x = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m{d}\x1b[90m,\x1b[32m{d}\x1b[90m {x:0>2}{x:0>2}{x:0>2}\x1b[0m", .{ x, y, r, g, b });
                    if (self.current_write_frame != null) {
                        const dc = c.GetDC(self.current_write_frame);
                        _ = c.SetPixel(dc, @intCast(x), @intCast(y), c.RGB(r, g, b));
                    }
                },
                .NEW_FRAME => {
                    // open window with dimensions from stack
                    const rate = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const height = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    const width = self.pop() catch |err| return self.exception(log, err, options.colors, .{});
                    if (log) self.debugLog(options.colors, " \x1b[32m{d}\x1b[90m x \x1b[32m{d}\x1b[90m r{d}\x1b[0m", .{ width, height, rate });
                    if (self.current_write_frame) |window| {
                        if (width == 0 and height == 0) while (true) {};
                        _ = c.DestroyWindow(window);
                    }
                    self.current_write_frame = c.CreateWindowExA(
                        0,
                        windowClassOptions.lpszClassName,
                        "iVM Frame",
                        c.WS_OVERLAPPEDWINDOW | c.WS_VISIBLE,
                        c.CW_USEDEFAULT,
                        c.CW_USEDEFAULT,
                        @intCast(width),
                        @intCast(height),
                        null,
                        null,
                        windowClassOptions.hInstance,
                        null,
                    );
                },
                .ADD_SAMPLE,
                .READ_PIXEL,
                => @panic("Unimplemented"),
                .READ_FRAME => {
                    if (builtin.os.tag != .windows) @panic("Unimplemented");
                    var file_string: [std.fs.max_path_bytes]u8 = [_]u8{0} ** std.fs.max_path_bytes;
                    var ofna = c.OPENFILENAMEA{
                        .lStructSize = @sizeOf(c.OPENFILENAMEA),
                        .lpstrFile = &file_string,
                        .nMaxFile = file_string.len,
                        .lpstrTitle = "Select frame",
                        .Flags = c.OFN_FILEMUSTEXIST,
                    };
                    if (c.GetOpenFileNameA(&ofna) == 0) {
                        const err = c.CommDlgExtendedError();
                        switch (err) {
                            0 => {
                                self.debugLog(options.colors, " \x1b[31mNo frame file selected\x1b[0m", .{});
                                self.terminated = true;
                            },
                            c.CDERR_DIALOGFAILURE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: DIALOGFAILURE\x1b[0m", .{}),
                            c.CDERR_FINDRESFAILURE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: FINDRESFAILURE\x1b[0m", .{}),
                            c.CDERR_INITIALIZATION => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: INITIALIZATION\x1b[0m", .{}),
                            c.CDERR_LOADRESFAILURE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: LOADRESFAILURE\x1b[0m", .{}),
                            c.CDERR_LOADSTRFAILURE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: LOADSTRFAILURE\x1b[0m", .{}),
                            c.CDERR_LOCKRESFAILURE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: LOCKRESFAILURE\x1b[0m", .{}),
                            c.CDERR_MEMALLOCFAILURE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: MEMALLOCFAILURE\x1b[0m", .{}),
                            c.CDERR_MEMLOCKFAILURE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: MEMLOCKFAILURE\x1b[0m", .{}),
                            c.CDERR_NOHINSTANCE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: NOHINSTANCE\x1b[0m", .{}),
                            c.CDERR_NOHOOK => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: NOHOOK\x1b[0m", .{}),
                            c.CDERR_NOTEMPLATE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: NOTEMPLATE\x1b[0m", .{}),
                            c.CDERR_REGISTERMSGFAIL => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: REGISTERMSGFAIL\x1b[0m", .{}),
                            c.CDERR_STRUCTSIZE => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: STRUCTSIZE\x1b[0m", .{}),
                            else => self.debugLog(options.colors, " \x1b[31mGetOpenFileNameA: CommDlgExtendedError({})\x1b[0m", .{err}),
                        }
                        self.debugLog(options.colors, "\n", .{});
                        return;
                    }
                    const file_name = file_string[ofna.nFileOffset..];
                    self.debugLog(options.colors, " \x1b[32m{s}\x1b[0m", .{file_name});
                    const fd = c.CreateFileA(
                        &file_string,
                        c.GENERIC_READ,
                        c.FILE_SHARE_READ,
                        null,
                        c.OPEN_EXISTING,
                        c.FILE_ATTRIBUTE_NORMAL,
                        null,
                    );
                    if (fd == c.INVALID_HANDLE_VALUE) {
                        self.debugLog(options.colors, " \x1b[31mFailed to open {s} (TODO: GetLastError)\x1b[0m\n", .{file_name});
                        self.terminated = true;
                        return;
                    }
                    self.current_read_frame = fd;
                },
                _ => {
                    self.debugLog(options.colors, "\x1b[33m0x{x:0>2}\x1b[90m: \x1b[31mUnknown instruction\x1b[0m\n", .{@intFromEnum(inst)});
                    self.terminated = true;
                },
            }
            if (log) self.debugLog(options.colors, "\n", .{});
        }
        pub const RunOptions = struct {
            debug: bool = false,
            colors: bool = true,
            right_align_machine_state: bool = true,
        };
        var windowClassOptions = c.WNDCLASSEXA{
            .cbSize = @sizeOf(c.WNDCLASSEXA),
            .style = c.CS_OWNDC,
            .lpfnWndProc = struct {
                fn wndProc(hWnd: c.HWND, uMsg: c.UINT, wParam: c.WPARAM, lParam: c.LPARAM) callconv(.C) c.LRESULT {
                    return c.DefWindowProcA(hWnd, uMsg, wParam, lParam);
                }
            }.wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = null,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = "iVM_Frame_Viewer",
            .hIconSm = null,
        };
        var windowClass: c.ATOM = 0;
        pub fn run(self: *Self, comptime options: RunOptions) void {
            defer self.debugFlush();
            if (builtin.os.tag == .windows) {
                const instance = c.GetModuleHandleA(0);
                windowClassOptions.hInstance = instance;
                windowClass = c.RegisterClassExA(&windowClassOptions);
            }
            if (options.debug) self.debugLog(options.colors, "\n", .{});
            while (!self.terminated) {
                if (options.debug) {
                    self.printDebugState(options.colors, options.right_align_machine_state);
                    self.debugFlush();
                }
                self.main(options);
            }
            if (builtin.os.tag == .windows) {
                if (self.current_read_frame) |handle| {
                    if (c.CloseHandle(handle) == 0) {
                        @panic("TODO: GetLastError()");
                    } else self.current_read_frame = null;
                }
            }
            if (options.debug) self.printDebugState(options.colors, options.right_align_machine_state);
        }
    };
}

test "put" {
    var machine = Machine(16, .{}){};
    const x: u64 = 0xa7a6a5a4a3a2a1a0;
    try machine.put(u8, @truncate(x), 0x01);
    try machine.put(u16, @truncate(x), 0x02);
    try machine.put(u32, @truncate(x), 0x04);
    try machine.put(u64, x, 0x08);
    const answer = .{ 0x00, 0xa0, 0xa0, 0xa1, 0xa0, 0xa1, 0xa2, 0xa3, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7 };
    inline for (machine.memory, answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "get" {
    var machine = Machine(16, .{}){
        .memory = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf },
    };
    try std.testing.expect(try machine.get(u8, 1) == 0x00000000000000a1);
    try std.testing.expect(try machine.get(u16, 2) == 0x000000000000a3a2);
    try std.testing.expect(try machine.get(u32, 4) == 0x00000000a7a6a5a4);
    try std.testing.expect(try machine.get(u64, 8) == 0xafaeadacabaaa9a8);
}

test "push" {
    var machine = Machine(16, .{}){};
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
    var machine = Machine(16, .{}){
        .memory = .{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf },
        .stack_pointer = 0,
    };
    const x = try machine.pop();
    try std.testing.expect(machine.stack_pointer == 0x08 and x == 0xa7a6a5a4a3a2a1a0);
    const y = try machine.pop();
    try std.testing.expect(machine.stack_pointer == 0x10 and y == 0xafaeadacabaaa9a8);
}

test "fetch" {
    var machine = Machine(16, .{}){
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
    var machine = Machine(256, .{}){};
    try machine.loadProgram(&.{ 0x01, 0x09, 0x1a, 0x09, 0x00, 0x09, 0x01, 0x09, 0x15, 0x09, 0x01, 0x09, 0x00, 0x03, 0x01, 0x00, 0x04, 0x02, 0x02, 0x00, 0x02, 0x03, 0x02, 0x04, 0x04, 0x00, 0x07, 0x06, 0x09, 0x01, 0x30, 0x09, 0xf8, 0x05, 0x09, 0x02, 0x30, 0x09, 0x00, 0x00 });
    machine.run(.{ .debug = false });
    try std.testing.expect(machine.terminated == true and machine.program_counter == 0x25 and machine.stack_pointer == 0xf8);
    const answer = [_]u8{ 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    inline for (machine.memory[0xe8..], answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "adding bit-copying capabilities" {
    var machine = Machine(256, .{ .strange_push0_behavior = true }){};
    machine.memory[0x00..0x28].* = .{ 0x08, 0x19, 0x13, 0x08, 0xe0, 0x17, 0x08, 0x21, 0x12, 0x08, 0xe8, 0x16, 0x08, 0x25, 0x11, 0x08, 0xec, 0x15, 0x08, 0x27, 0x10, 0x08, 0xee, 0x14, 0x00, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae };
    machine.run(.{ .debug = false });
    try std.testing.expect(machine.terminated == true and machine.stack_pointer == 0x100);
    const answer = [_]u8{ 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0x00 };
    inline for (machine.memory[0x19..0x29], answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "adding more bit-copying capabilities" {
    // if (true) return error.SkipZigTest;
    var machine = Machine(256, .{}){};
    machine.memory[0x00..0x13].* = .{ 0x08, 0x0a, 0x20, 0x21, 0x0b, 0x10, 0x11, 0x12, 0x13, 0x0c, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x00 };
    machine.run(.{ .debug = false });
    try std.testing.expect(machine.terminated == true and machine.stack_pointer == 0xe0);
    const answer = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x10, 0x11, 0x12, 0x13, 0x00, 0x00, 0x00, 0x00, 0x20, 0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    inline for (machine.memory[0xe0..0x100], answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "adding arithmetic" {
    var machine = Machine(256, .{ .strange_push0_behavior = true }){};
    machine.memory[0x00..0x2d].* = .{ 0x09, 0x1d, 0x13, 0x09, 0x25, 0x13, 0x20, 0x09, 0x1d, 0x13, 0x09, 0x25, 0x13, 0x21, 0x09, 0x1d, 0x13, 0x09, 0x25, 0x13, 0x22, 0x09, 0x1d, 0x13, 0x09, 0x25, 0x13, 0x23, 0x00, 0x98, 0xe7, 0xd9, 0x58, 0x1b, 0xc9, 0x77, 0xff, 0x88, 0x60, 0x09, 0x5c, 0x7d, 0x2c, 0x17, 0x3f };
    machine.run(.{ .debug = false });
    try std.testing.expect(machine.terminated == true and machine.stack_pointer == 0xe0);
    const answer = [_]u8{ 0x78, 0x65, 0xb4, 0xe8, 0x25, 0x17, 0x1b, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x08, 0xf4, 0xae, 0xf4, 0xbb, 0xcd, 0x95, 0x20, 0x48, 0xe3, 0xb4, 0x98, 0xf5, 0x8e, 0x3e };
    inline for (machine.memory[0xe0..0x100], answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "adding more arithmetic" {
    var machine = Machine(256, .{ .strange_push0_behavior = true }){};
    machine.memory[0x00..0x2d].* = .{ 0x09, 0x24, 0x13, 0x09, 0x24, 0x13, 0x24, 0x09, 0x24, 0x13, 0x09, 0x25, 0x13, 0x24, 0x09, 0x25, 0x13, 0x09, 0x24, 0x13, 0x24, 0x09, 0x22, 0x10, 0x2c, 0x09, 0x23, 0x10, 0x2c, 0x09, 0x24, 0x10, 0x2c, 0x00, 0x40, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xa0 };
    machine.run(.{ .debug = false });
    try std.testing.expect(machine.terminated == true and machine.stack_pointer == 0xd0);
    const answer = [_]u8{ 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    inline for (machine.memory[0xd0..0x100], answer) |actual, expected| try std.testing.expect(actual == expected);
}

test "adding bitwise boolean logic" {
    var machine = Machine(256, .{ .strange_push0_behavior = true }){};
    machine.memory[0x00..0x2a].* = .{ 0x09, 0x1a, 0x13, 0x09, 0x22, 0x13, 0x28, 0x09, 0x1a, 0x13, 0x09, 0x22, 0x13, 0x29, 0x09, 0x1a, 0x13, 0x09, 0x22, 0x13, 0x2b, 0x09, 0x1a, 0x13, 0x2a, 0x00, 0x98, 0xe7, 0xd9, 0x58, 0x1b, 0xc9, 0x77, 0xff, 0x88, 0x60, 0x09, 0x5c, 0x7d, 0x2c, 0x17, 0x3f };
    machine.run(.{ .debug = false });
    try std.testing.expect(machine.terminated == true and machine.stack_pointer == 0xe0);
    const answer = [_]u8{ 0x67, 0x18, 0x26, 0xa7, 0xe4, 0x36, 0x88, 0x00, 0x10, 0x87, 0xd0, 0x04, 0x66, 0xe5, 0x60, 0xc0, 0x98, 0xe7, 0xd9, 0x5c, 0x7f, 0xed, 0x77, 0xff, 0x88, 0x60, 0x09, 0x58, 0x19, 0x08, 0x17, 0x3f };
    inline for (machine.memory[0xe0..0x100], answer) |actual, expected| try std.testing.expect(actual == expected);
}
