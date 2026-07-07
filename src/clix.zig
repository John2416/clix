const std = @import("std");
const builtin = @import("builtin");

pub const ConsoleError = error{
    Cancelled,
    InvalidInput,
    UnsupportedTerminal,
};

pub const Key = enum {
    up,
    down,
    page_up,
    page_down,
    home,
    end,
    enter,
    cancel,
    other,
};

pub const ColorMode = enum {
    auto,
    always,
    never,
};

pub const EscapeMode = enum {
    auto,
    always,
    never,
};

pub const TerminalCapabilities = struct {
    ansi_escape: bool,
    color: bool,
};

pub const Options = struct {
    color: ColorMode = .auto,
    escapes: EscapeMode = .auto,
    max_visible_choices: usize = 10,
};

pub const SecretOptions = struct {
    mask: ?u8 = null,
    max_bytes: usize = 4096,
};

pub fn detectCapabilities(io: std.Io, environ_map: ?*const std.process.Environ.Map) TerminalCapabilities {
    const escapes = escapeEnabled(io, environ_map, .auto);
    return .{
        .ansi_escape = escapes,
        .color = colorEnabled(.auto, environ_map, escapes),
    };
}

pub fn supportsAnsiEscapes(io: std.Io) bool {
    return std.Io.File.stdout().supportsAnsiEscapeCodes(io) catch false;
}

pub fn enableAnsiEscapes(io: std.Io) bool {
    std.Io.File.stdout().enableAnsiEscapeCodes(io) catch return false;
    return true;
}

pub const Console = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    color: bool,
    escapes: bool,
    max_visible_choices: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ_map: *const std.process.Environ.Map,
    ) Console {
        return initOptions(allocator, io, environ_map, .{});
    }

    pub fn fromInit(init_ctx: std.process.Init) Console {
        return init(init_ctx.gpa, init_ctx.io, init_ctx.environ_map);
    }

    pub fn fromInitOptions(init_ctx: std.process.Init, options: Options) Console {
        return initOptions(init_ctx.gpa, init_ctx.io, init_ctx.environ_map, options);
    }

    pub fn initOptions(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ_map: ?*const std.process.Environ.Map,
        options: Options,
    ) Console {
        const escapes = escapeEnabled(io, environ_map, options.escapes);
        return .{
            .allocator = allocator,
            .io = io,
            .color = colorEnabled(options.color, environ_map, escapes),
            .escapes = escapes,
            .max_visible_choices = @max(options.max_visible_choices, 1),
        };
    }

    pub fn capabilities(self: Console) TerminalCapabilities {
        return .{
            .ansi_escape = self.escapes,
            .color = self.usesColor(),
        };
    }

    pub fn supportsAnsiEscapes(self: Console) bool {
        return self.escapes;
    }

    pub fn activateAnsiEscapes(self: *Console) bool {
        if (enableAnsiEscapes(self.io)) {
            self.escapes = true;
            return true;
        }
        self.escapes = false;
        self.color = false;
        return false;
    }

    pub fn setAnsiEscapes(self: *Console, enabled: bool) void {
        self.escapes = enabled;
        if (!enabled) self.color = false;
    }

    pub fn setColor(self: *Console, enabled: bool) void {
        self.color = enabled;
    }

    fn usesColor(self: Console) bool {
        return self.color and self.escapes;
    }

    pub fn write(self: Console, bytes: []const u8) !void {
        try std.Io.File.stdout().writeStreamingAll(self.io, bytes);
    }

    pub fn writeErr(self: Console, bytes: []const u8) !void {
        try std.Io.File.stderr().writeStreamingAll(self.io, bytes);
    }

    pub fn print(self: Console, comptime fmt: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);
        try self.write(text);
    }

    pub fn printErr(self: Console, comptime fmt: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);
        try self.writeErr(text);
    }

    pub fn clear(self: Console) !void {
        try self.clearScreen();
    }

    pub fn clearScreen(self: Console) !void {
        if (!self.escapes) return;
        try self.write("\x1b[2J\x1b[H");
    }

    pub fn clearScrollback(self: Console) !void {
        if (!self.escapes) return;
        try self.write("\x1b[3J");
    }

    pub fn clearLine(self: Console) !void {
        if (!self.escapes) return;
        try self.write("\x1b[2K\r");
    }

    pub fn clearLineAfterCursor(self: Console) !void {
        if (!self.escapes) return;
        try self.write("\x1b[K");
    }

    pub fn moveCursorHome(self: Console) !void {
        if (!self.escapes) return;
        try self.write("\x1b[H");
    }

    pub fn moveCursor(self: Console, row: usize, column: usize) !void {
        if (!self.escapes) return;
        try self.print("\x1b[{d};{d}H", .{ @max(row, 1), @max(column, 1) });
    }

    pub fn cursorUp(self: Console, count: usize) !void {
        if (!self.escapes or count == 0) return;
        try self.print("\x1b[{d}A", .{count});
    }

    pub fn cursorDown(self: Console, count: usize) !void {
        if (!self.escapes or count == 0) return;
        try self.print("\x1b[{d}B", .{count});
    }

    pub fn cursorForward(self: Console, count: usize) !void {
        if (!self.escapes or count == 0) return;
        try self.print("\x1b[{d}C", .{count});
    }

    pub fn cursorBackward(self: Console, count: usize) !void {
        if (!self.escapes or count == 0) return;
        try self.print("\x1b[{d}D", .{count});
    }

    pub fn hideCursor(self: Console) !void {
        if (!self.escapes) return;
        try self.write("\x1b[?25l");
    }

    pub fn showCursor(self: Console) !void {
        if (!self.escapes) return;
        try self.write("\x1b[?25h");
    }

    pub fn resetStyle(self: Console) !void {
        if (!self.escapes) return;
        try self.write("\x1b[0m");
    }

    pub fn setWindowTitle(self: Console, text: []const u8) !void {
        if (!self.escapes) return;
        try self.print("\x1b]0;{s}\x07", .{text});
    }

    pub fn title(self: Console, text: []const u8) !void {
        if (self.usesColor()) {
            try self.print("\x1b[36;1m{s}\x1b[0m\n", .{text});
        } else {
            try self.print("{s}\n", .{text});
        }
    }

    pub fn success(self: Console, comptime fmt: []const u8, args: anytype) !void {
        if (self.usesColor()) try self.write("\x1b[32;1m");
        try self.write("OK: ");
        if (self.usesColor()) try self.write("\x1b[0m");
        try self.print(fmt, args);
        try self.write("\n");
    }

    pub fn err(self: Console, comptime fmt: []const u8, args: anytype) void {
        if (self.usesColor()) {
            self.writeErr("\x1b[31;1mError: \x1b[0m") catch {};
        } else {
            self.writeErr("Error: ") catch {};
        }

        const text = std.fmt.allocPrint(self.allocator, fmt, args) catch return;
        defer self.allocator.free(text);
        self.writeErr(text) catch {};
        self.writeErr("\n") catch {};
    }

    pub fn status(self: Console, text: []const u8) !void {
        if (self.usesColor()) {
            try self.print("\x1b[2m{s}\x1b[0m\n", .{text});
        } else {
            try self.print("{s}\n", .{text});
        }
    }

    pub fn readLine(
        self: Console,
        allocator: std.mem.Allocator,
        prompt: []const u8,
        default_value: ?[]const u8,
    ) ![]u8 {
        if (default_value) |default| {
            try self.print("{s} [{s}]: ", .{ prompt, default });
        } else {
            try self.print("{s}: ", .{prompt});
        }

        var buffer: [4096]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().readerStreaming(self.io, &buffer);
        const raw_line = stdin_reader.interface.takeDelimiterExclusive('\n') catch |read_err| switch (read_err) {
            error.EndOfStream => "",
            else => return read_err,
        };
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0) {
            if (default_value) |default| return allocator.dupe(u8, default);
        }
        return allocator.dupe(u8, line);
    }

    pub fn readRequired(
        self: Console,
        allocator: std.mem.Allocator,
        prompt: []const u8,
    ) ![]u8 {
        while (true) {
            const answer = try self.readLine(allocator, prompt, null);
            const trimmed = std.mem.trim(u8, answer, " \t\r\n");
            if (trimmed.len != 0) {
                const result = try allocator.dupe(u8, trimmed);
                allocator.free(answer);
                return result;
            }
            allocator.free(answer);
            try self.status("Please enter a value.");
        }
    }

    pub fn readSecret(
        self: Console,
        allocator: std.mem.Allocator,
        prompt: []const u8,
    ) ![]u8 {
        return self.readSecretOptions(allocator, prompt, .{});
    }

    pub fn readSecretMasked(
        self: Console,
        allocator: std.mem.Allocator,
        prompt: []const u8,
        mask: u8,
    ) ![]u8 {
        return self.readSecretOptions(allocator, prompt, .{ .mask = mask });
    }

    pub fn readSecretOptions(
        self: Console,
        allocator: std.mem.Allocator,
        prompt: []const u8,
        options: SecretOptions,
    ) ![]u8 {
        if (enableRawMode()) |raw| {
            var raw_mode = raw;
            defer raw_mode.restore();
            return self.readSecretRaw(allocator, prompt, options);
        } else |_| {
            return self.readLine(allocator, prompt, null);
        }
    }

    fn readSecretRaw(
        self: Console,
        allocator: std.mem.Allocator,
        prompt: []const u8,
        options: SecretOptions,
    ) ![]u8 {
        try self.print("{s}: ", .{prompt});

        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(allocator);

        var stdin_buffer: [16]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().readerStreaming(self.io, &stdin_buffer);

        while (true) {
            const byte = try stdin_reader.interface.takeByte();
            switch (byte) {
                3, 4 => return error.Cancelled,
                '\r', '\n' => {
                    try self.write("\n");
                    return try bytes.toOwnedSlice(allocator);
                },
                8, 127 => {
                    if (bytes.pop() != null) {
                        if (options.mask != null) try self.write("\x08 \x08");
                    }
                },
                else => {
                    if (byte < 0x20 and byte != '\t') continue;
                    if (bytes.items.len >= options.max_bytes) continue;
                    try bytes.append(allocator, byte);
                    if (options.mask) |mask| try self.write(&.{mask});
                },
            }
        }
    }

    pub fn pause(self: Console, prompt: []const u8) !void {
        const answer = try self.readLine(self.allocator, prompt, null);
        defer self.allocator.free(answer);
    }

    pub fn confirm(self: Console, prompt: []const u8, default_value: bool) !bool {
        while (true) {
            const suffix = if (default_value) "Y/n" else "y/N";
            const prompt_text = try std.fmt.allocPrint(self.allocator, "{s} ({s})", .{ prompt, suffix });
            defer self.allocator.free(prompt_text);

            const answer = try self.readLine(self.allocator, prompt_text, null);
            defer self.allocator.free(answer);

            const trimmed = std.mem.trim(u8, answer, " \t\r\n");
            if (trimmed.len == 0) return default_value;
            if (std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes")) return true;
            if (std.ascii.eqlIgnoreCase(trimmed, "n") or std.ascii.eqlIgnoreCase(trimmed, "no")) return false;
            try self.status("Please answer y or n.");
        }
    }

    pub fn select(self: Console, title_text: []const u8, choices: []const []const u8) !usize {
        if (choices.len == 0) return error.InvalidInput;
        if (!self.escapes) return self.numberedSelect(title_text, choices);

        if (enableRawMode()) |raw| {
            var raw_mode = raw;
            defer raw_mode.restore();
            return self.interactiveSelect(title_text, choices);
        } else |_| {
            return self.numberedSelect(title_text, choices);
        }
    }

    pub fn numberedSelect(self: Console, title_text: []const u8, choices: []const []const u8) !usize {
        if (choices.len == 0) return error.InvalidInput;

        try self.title(title_text);
        for (choices, 0..) |choice, index| {
            try self.print("  {d}. {s}\n", .{ index + 1, choice });
        }

        while (true) {
            const answer = try self.readLine(self.allocator, "Select number", null);
            defer self.allocator.free(answer);
            const trimmed = std.mem.trim(u8, answer, " \t\r\n");
            const value = std.fmt.parseInt(usize, trimmed, 10) catch {
                try self.status("Please enter a valid number.");
                continue;
            };
            if (value >= 1 and value <= choices.len) return value - 1;
            try self.status("Selection is out of range.");
        }
    }

    fn interactiveSelect(self: Console, title_text: []const u8, choices: []const []const u8) !usize {
        var selected: usize = 0;
        const page_size: usize = @min(choices.len, self.max_visible_choices);
        var first_render = true;

        var stdin_buffer: [16]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().readerStreaming(self.io, &stdin_buffer);

        try self.write("\x1b[?25l");
        defer self.write("\x1b[?25h") catch {};
        errdefer self.write("\n") catch {};

        while (true) {
            try self.renderSelection(title_text, choices, selected, page_size, first_render);
            first_render = false;

            switch (try readKey(&stdin_reader.interface)) {
                .up => selected = if (selected == 0) choices.len - 1 else selected - 1,
                .down => selected = (selected + 1) % choices.len,
                .page_up => selected = if (selected > page_size) selected - page_size else 0,
                .page_down => selected = @min(choices.len - 1, selected + page_size),
                .home => selected = 0,
                .end => selected = choices.len - 1,
                .enter => {
                    try self.write("\n");
                    return selected;
                },
                .cancel => return error.Cancelled,
                .other => {},
            }
        }
    }

    fn renderSelection(
        self: Console,
        title_text: []const u8,
        choices: []const []const u8,
        selected: usize,
        page_size: usize,
        first_render: bool,
    ) !void {
        const line_count = page_size + 1;
        if (!first_render) {
            try self.print("\x1b[{d}A", .{line_count});
        }

        const start = selectionWindowStart(choices.len, selected, page_size);

        try self.write("\x1b[2K\r");
        if (self.usesColor()) {
            try self.print("\x1b[36;1m{s}\x1b[0m\n", .{title_text});
        } else {
            try self.print("{s}\n", .{title_text});
        }

        var i: usize = 0;
        while (i < page_size) : (i += 1) {
            const index = start + i;
            try self.write("\x1b[2K\r");
            if (index == selected) {
                if (self.usesColor()) {
                    try self.print("\x1b[7m > {s} \x1b[0m\n", .{choices[index]});
                } else {
                    try self.print("> {s}\n", .{choices[index]});
                }
            } else {
                try self.print("   {s}\n", .{choices[index]});
            }
        }
    }
};

fn escapeEnabled(io: std.Io, environ_map: ?*const std.process.Environ.Map, mode: EscapeMode) bool {
    return switch (mode) {
        .always => true,
        .never => false,
        .auto => blk: {
            if (environ_map) |env| {
                if (env.get("CLIX_NO_ESCAPE") != null) break :blk false;
                if (env.get("TERM")) |term| {
                    if (std.ascii.eqlIgnoreCase(term, "dumb")) break :blk false;
                }
            }
            break :blk enableAnsiEscapes(io);
        },
    };
}

fn colorEnabled(mode: ColorMode, environ_map: ?*const std.process.Environ.Map, escapes: bool) bool {
    return switch (mode) {
        .always => escapes,
        .never => false,
        .auto => escapes and if (environ_map) |env| env.get("NO_COLOR") == null else true,
    };
}

fn selectionWindowStart(len: usize, selected: usize, page_size: usize) usize {
    if (len <= page_size) return 0;
    const half = page_size / 2;
    var start = if (selected > half) selected - half else 0;
    if (start + page_size > len) start = len - page_size;
    return start;
}

fn readKey(reader: *std.Io.Reader) !Key {
    const first = try reader.takeByte();
    return switch (first) {
        3, 4 => .cancel,
        '\r', '\n' => .enter,
        'k', 'K' => .up,
        'j', 'J' => .down,
        0x1b => blk: {
            const second = reader.takeByte() catch return .cancel;
            if (second == 'O') {
                const third = reader.takeByte() catch return .other;
                break :blk switch (third) {
                    'H' => .home,
                    'F' => .end,
                    else => .other,
                };
            }
            if (second != '[') break :blk .other;

            const third = reader.takeByte() catch return .other;
            break :blk switch (third) {
                'A' => .up,
                'B' => .down,
                'H' => .home,
                'F' => .end,
                '1', '7' => escapeWithTilde(reader, .home),
                '4', '8' => escapeWithTilde(reader, .end),
                '5' => escapeWithTilde(reader, .page_up),
                '6' => escapeWithTilde(reader, .page_down),
                else => .other,
            };
        },
        else => .other,
    };
}

fn escapeWithTilde(reader: *std.Io.Reader, key: Key) Key {
    const trailing = reader.takeByte() catch return key;
    return if (trailing == '~') key else .other;
}

const RawMode = switch (builtin.os.tag) {
    .windows => WindowsRawMode,
    .linux,
    .driverkit,
    .ios,
    .maccatalyst,
    .macos,
    .tvos,
    .visionos,
    .watchos,
    .dragonfly,
    .freebsd,
    .netbsd,
    .openbsd,
    => PosixRawMode,
    else => UnsupportedRawMode,
};

fn enableRawMode() !RawMode {
    return RawMode.enable();
}

const UnsupportedRawMode = struct {
    pub fn enable() !UnsupportedRawMode {
        return error.UnsupportedTerminal;
    }

    pub fn restore(_: *UnsupportedRawMode) void {}
};

const PosixRawMode = struct {
    fd: std.posix.fd_t,
    original: std.posix.termios,

    pub fn enable() !PosixRawMode {
        const file = std.Io.File.stdin();
        const original = std.posix.tcgetattr(file.handle) catch |err| switch (err) {
            error.NotATerminal => return error.UnsupportedTerminal,
            else => return err,
        };

        var raw = original;
        makeRaw(&raw);
        std.posix.tcsetattr(file.handle, .FLUSH, raw) catch |err| switch (err) {
            error.NotATerminal, error.ProcessOrphaned => return error.UnsupportedTerminal,
            else => return err,
        };

        return .{
            .fd = file.handle,
            .original = original,
        };
    }

    pub fn restore(self: *PosixRawMode) void {
        std.posix.tcsetattr(self.fd, .FLUSH, self.original) catch {};
    }
};

fn makeRaw(term: *std.posix.termios) void {
    setFlag(@TypeOf(term.iflag), &term.iflag, "BRKINT", false);
    setFlag(@TypeOf(term.iflag), &term.iflag, "ICRNL", false);
    setFlag(@TypeOf(term.iflag), &term.iflag, "INPCK", false);
    setFlag(@TypeOf(term.iflag), &term.iflag, "ISTRIP", false);
    setFlag(@TypeOf(term.iflag), &term.iflag, "IXON", false);

    setFlag(@TypeOf(term.oflag), &term.oflag, "OPOST", false);

    if (@hasField(@TypeOf(term.cflag), "CSIZE")) {
        term.cflag.CSIZE = .CS8;
    }

    setFlag(@TypeOf(term.lflag), &term.lflag, "ECHO", false);
    setFlag(@TypeOf(term.lflag), &term.lflag, "ICANON", false);
    setFlag(@TypeOf(term.lflag), &term.lflag, "IEXTEN", false);
    setFlag(@TypeOf(term.lflag), &term.lflag, "ISIG", false);

    term.cc[@as(usize, @intFromEnum(std.posix.V.MIN))] = 1;
    term.cc[@as(usize, @intFromEnum(std.posix.V.TIME))] = 0;
}

fn setFlag(comptime T: type, flags: *T, comptime name: []const u8, value: bool) void {
    if (@hasField(T, name)) {
        @field(flags, name) = value;
    }
}

const WindowsRawMode = struct {
    input_handle: std.os.windows.HANDLE,
    output_handle: std.os.windows.HANDLE,
    input_mode: std.os.windows.DWORD,
    output_mode: std.os.windows.DWORD,

    const ENABLE_PROCESSED_INPUT: std.os.windows.DWORD = 0x0001;
    const ENABLE_LINE_INPUT: std.os.windows.DWORD = 0x0002;
    const ENABLE_ECHO_INPUT: std.os.windows.DWORD = 0x0004;
    const ENABLE_VIRTUAL_TERMINAL_INPUT: std.os.windows.DWORD = 0x0200;
    const ENABLE_PROCESSED_OUTPUT: std.os.windows.DWORD = 0x0001;
    const ENABLE_WRAP_AT_EOL_OUTPUT: std.os.windows.DWORD = 0x0002;

    extern "kernel32" fn GetConsoleMode(
        hConsoleHandle: std.os.windows.HANDLE,
        lpMode: *std.os.windows.DWORD,
    ) callconv(.winapi) std.os.windows.BOOL;

    extern "kernel32" fn SetConsoleMode(
        hConsoleHandle: std.os.windows.HANDLE,
        dwMode: std.os.windows.DWORD,
    ) callconv(.winapi) std.os.windows.BOOL;

    pub fn enable() !WindowsRawMode {
        const input_handle = std.os.windows.peb().ProcessParameters.hStdInput;
        const output_handle = std.os.windows.peb().ProcessParameters.hStdOutput;

        var input_mode: std.os.windows.DWORD = 0;
        var output_mode: std.os.windows.DWORD = 0;
        if (!GetConsoleMode(input_handle, &input_mode).toBool()) return error.UnsupportedTerminal;
        if (!GetConsoleMode(output_handle, &output_mode).toBool()) return error.UnsupportedTerminal;

        const new_input = (input_mode | ENABLE_VIRTUAL_TERMINAL_INPUT) & ~(ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
        const new_output = output_mode | ENABLE_PROCESSED_OUTPUT | ENABLE_WRAP_AT_EOL_OUTPUT | std.os.windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING;

        if (!SetConsoleMode(input_handle, new_input).toBool()) return error.UnsupportedTerminal;
        if (!SetConsoleMode(output_handle, new_output).toBool()) {
            _ = SetConsoleMode(input_handle, input_mode);
            return error.UnsupportedTerminal;
        }

        return .{
            .input_handle = input_handle,
            .output_handle = output_handle,
            .input_mode = input_mode,
            .output_mode = output_mode,
        };
    }

    pub fn restore(self: *WindowsRawMode) void {
        _ = SetConsoleMode(self.input_handle, self.input_mode);
        _ = SetConsoleMode(self.output_handle, self.output_mode);
    }
};

test "selection window stays in bounds" {
    try std.testing.expectEqual(@as(usize, 0), selectionWindowStart(3, 0, 10));
    try std.testing.expectEqual(@as(usize, 0), selectionWindowStart(20, 0, 10));
    try std.testing.expectEqual(@as(usize, 5), selectionWindowStart(20, 10, 10));
    try std.testing.expectEqual(@as(usize, 10), selectionWindowStart(20, 19, 10));
}

test "read key recognizes common navigation sequences" {
    var up: std.Io.Reader = .fixed("\x1b[A");
    try std.testing.expectEqual(Key.up, try readKey(&up));

    var down: std.Io.Reader = .fixed("j");
    try std.testing.expectEqual(Key.down, try readKey(&down));

    var page: std.Io.Reader = .fixed("\x1b[6~");
    try std.testing.expectEqual(Key.page_down, try readKey(&page));

    var home: std.Io.Reader = .fixed("\x1b[H");
    try std.testing.expectEqual(Key.home, try readKey(&home));

    var end: std.Io.Reader = .fixed("\x1bOF");
    try std.testing.expectEqual(Key.end, try readKey(&end));
}

test "color mode honors explicit options" {
    try std.testing.expect(colorEnabled(.always, null, true));
    try std.testing.expect(!colorEnabled(.always, null, false));
    try std.testing.expect(!colorEnabled(.never, null, true));
    try std.testing.expect(colorEnabled(.auto, null, true));
    try std.testing.expect(!colorEnabled(.auto, null, false));
}
