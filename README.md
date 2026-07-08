# clix

`clix` is a small cross-platform interactive command-line library for Zig.

It provides a compact console helper for prompts, confirmations, selection menus, terminal control, and ANSI capability handling:

- **Windows**: enables Virtual Terminal support through `std.Io.File.enableAnsiEscapeCodes()` and uses Win32 console modes for raw input.
- **Linux / Unix-like**: uses POSIX `termios` raw mode for interactive key input.
- **Non-interactive environments**: falls back to plain numbered selection and line input when raw terminal support is unavailable.
- **ANSI behavior**: can be auto-detected, forced on, or disabled.

The library is designed for CLI tools that want a pleasant interactive experience without pulling in a large framework.

## Features

- Styled output: title, status, success, and error messages.
- Plain stdout / stderr helpers.
- Line input with optional default values.
- Required input prompts.
- Yes / no confirmation prompts.
- Secret input, with optional masking.
- Interactive selection menu with arrow keys, `j` / `k`, PageUp / PageDown, Home / End.
- Numbered selection fallback.
- Terminal controls: clear screen, clear line, cursor movement, cursor visibility, reset style, and window title.
- ANSI capability detection and behavior switches.

## Installation

Add `clix` as a Zig package dependency:

```sh
zig fetch --save git+https://github.com/John2416/clix.git
```

Import it in `build.zig`:

```zig
const clix_dep = b.dependency("clix", .{
    .target = target,
    .optimize = optimize,
});

const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "clix", .module = clix_dep.module("clix") },
    },
});
```

## Usage

```zig
const std = @import("std");
const clix = @import("clix");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const console = clix.Console.fromInit(init);

    try console.title("Project setup");

    const name = try console.readLine(arena, "Project name", "demo");
    const private = try console.confirm("Make it private", true);

    const templates = [_][]const u8{
        "app",
        "library",
        "tool",
    };
    const selected = try console.select("Choose a template", templates[0..]);

    try console.success(
        "created {s} from {s}; private={}",
        .{ name, templates[selected], private },
    );
}
```

Configure behavior:

```zig
const console = clix.Console.fromInitOptions(init, .{
    .color = .auto,
    .escapes = .auto,
    .max_visible_choices = 6,
});
```

Disable ANSI escape behavior for legacy terminals or logs:

```zig
const console = clix.Console.fromInitOptions(init, .{
    .color = .never,
    .escapes = .never,
});
```

## API

Console construction:

```zig
clix.Console.init(allocator, io, environ_map)
clix.Console.initOptions(allocator, io, environ_map, options)
clix.Console.fromInit(init)
clix.Console.fromInitOptions(init, options)
```

Capabilities:

```zig
clix.detectCapabilities(io, environ_map)
clix.supportsAnsiEscapes(io)
clix.enableAnsiEscapes(io)

console.capabilities()
console.supportsAnsiEscapes()
console.activateAnsiEscapes()
console.setAnsiEscapes(enabled)
console.setColor(enabled)
```

Output:

```zig
console.write(bytes)
console.writeErr(bytes)
console.print(fmt, args)
console.printErr(fmt, args)
console.title(text)
console.status(text)
console.success(fmt, args)
console.err(fmt, args)
```

Input:

```zig
console.readLine(allocator, prompt, default_value)
console.readRequired(allocator, prompt)
console.readSecret(allocator, prompt)
console.readSecretMasked(allocator, prompt, mask)
console.readSecretOptions(allocator, prompt, options)
console.confirm(prompt, default_value)
console.pause(prompt)
```

Selection:

```zig
console.select(title, choices)
console.numberedSelect(title, choices)
```

Terminal controls:

```zig
console.clear()
console.clearScreen()
console.clearScrollback()
console.clearLine()
console.clearLineAfterCursor()
console.moveCursorHome()
console.moveCursor(row, column)
console.cursorUp(count)
console.cursorDown(count)
console.cursorForward(count)
console.cursorBackward(count)
console.hideCursor()
console.showCursor()
console.resetStyle()
console.setWindowTitle(text)
```

## Options

```zig
pub const Options = struct {
    color: ColorMode = .auto,
    escapes: EscapeMode = .auto,
    max_visible_choices: usize = 10,
};
```

Color modes:

- `auto`: use color when ANSI escape support is available and `NO_COLOR` is not set.
- `always`: use color when ANSI escape support is enabled.
- `never`: never use color.

Escape modes:

- `auto`: try to enable and use ANSI escape codes.
- `always`: emit ANSI escape codes without auto-detection.
- `never`: disable ANSI terminal controls.

Secret input options:

```zig
pub const SecretOptions = struct {
    mask: ?u8 = null,
    max_bytes: usize = 4096,
};
```

## Environment

- `NO_COLOR`: disables color in `.auto` color mode.
- `TERM=dumb`: disables ANSI escape behavior in `.auto` escape mode.
- `CLIX_NO_ESCAPE`: disables ANSI escape behavior in `.auto` escape mode.

## Platform Notes

### Windows

Windows terminals must have Virtual Terminal Processing enabled before ANSI escape sequences work. `clix` tries to activate it automatically in `.auto` escape mode.

If the console does not support ANSI escapes, terminal controls become no-ops and `select()` falls back to `numberedSelect()`.

### Linux / Unix-like

Interactive selection and secret input use POSIX `termios` raw mode when available. If stdin is not a terminal, `clix` falls back to plain line input and numbered selection.

### Non-interactive output

When ANSI escape support is disabled, methods such as `clearScreen()`, `moveCursor()`, and `hideCursor()` do not emit escape sequences. This keeps redirected output and logs readable.

## Development

Run tests:

```sh
zig build test --summary all
```

Check formatting:

```sh
zig fmt --check .
```

## License

Apache-2.0
