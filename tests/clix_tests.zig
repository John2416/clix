const std = @import("std");
const clix = @import("clix");

test "selection window stays in bounds" {
    try std.testing.expectEqual(@as(usize, 0), clix.testing.windowStart(3, 0, 10));
    try std.testing.expectEqual(@as(usize, 0), clix.testing.windowStart(20, 0, 10));
    try std.testing.expectEqual(@as(usize, 5), clix.testing.windowStart(20, 10, 10));
    try std.testing.expectEqual(@as(usize, 10), clix.testing.windowStart(20, 19, 10));
}

test "read key recognizes common navigation sequences" {
    var up: std.Io.Reader = .fixed("\x1b[A");
    try std.testing.expectEqual(clix.Key.up, try clix.testing.parseKey(&up));

    var down: std.Io.Reader = .fixed("j");
    try std.testing.expectEqual(clix.Key.down, try clix.testing.parseKey(&down));

    var page: std.Io.Reader = .fixed("\x1b[6~");
    try std.testing.expectEqual(clix.Key.page_down, try clix.testing.parseKey(&page));

    var home: std.Io.Reader = .fixed("\x1b[H");
    try std.testing.expectEqual(clix.Key.home, try clix.testing.parseKey(&home));

    var end: std.Io.Reader = .fixed("\x1bOF");
    try std.testing.expectEqual(clix.Key.end, try clix.testing.parseKey(&end));
}

test "color mode honors explicit options" {
    try std.testing.expect(clix.testing.modeUsesColor(.always, null, true));
    try std.testing.expect(!clix.testing.modeUsesColor(.always, null, false));
    try std.testing.expect(!clix.testing.modeUsesColor(.never, null, true));
    try std.testing.expect(clix.testing.modeUsesColor(.auto, null, true));
    try std.testing.expect(!clix.testing.modeUsesColor(.auto, null, false));
}

test "console options can disable terminal escape behavior" {
    var console = clix.Console.initOptions(
        std.testing.allocator,
        std.testing.io,
        null,
        .{ .color = .always, .escapes = .never },
    );

    try std.testing.expect(!console.supportsAnsiEscapes());
    try std.testing.expect(!console.capabilities().ansi_escape);
    try std.testing.expect(!console.capabilities().color);

    console.setAnsiEscapes(true);
    console.setColor(true);
    try std.testing.expect(console.supportsAnsiEscapes());
    try std.testing.expect(console.capabilities().color);

    console.setAnsiEscapes(false);
    try std.testing.expect(!console.supportsAnsiEscapes());
    try std.testing.expect(!console.capabilities().color);
}
