const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList(u8);

/// Appends a Server-Sent Event. `data` can contain line breaks, the client gets it unchanged
/// except that `\r\n` and `\r` become `\n`.
pub fn appendEvent(out: *ArrayList, allocator: Allocator, name: []const u8, data: []const u8) Allocator.Error!void {
    try out.appendSlice(allocator, "event: ");
    try out.appendSlice(allocator, name);
    try out.append(allocator, '\n');
    try appendLines(out, allocator, "data: ", data);
    try out.append(allocator, '\n');
}

/// Appends a comment, clients ignore it. Keeps the connection alive and reveals a gone client.
pub fn appendComment(out: *ArrayList, allocator: Allocator, text: []const u8) Allocator.Error!void {
    try appendLines(out, allocator, ": ", text);
    try out.append(allocator, '\n');
}

fn appendLines(out: *ArrayList, allocator: Allocator, prefix: []const u8, text: []const u8) Allocator.Error!void {
    var start: usize = 0;
    var i: usize = 0;

    while (i < text.len) : (i += 1) {
        if (text[i] != '\n' and text[i] != '\r') {
            continue;
        }

        try appendLine(out, allocator, prefix, text[start..i]);

        if (text[i] == '\r' and i + 1 < text.len and text[i + 1] == '\n') {
            i += 1;
        }

        start = i + 1;
    }

    try appendLine(out, allocator, prefix, text[start..]);
}

fn appendLine(out: *ArrayList, allocator: Allocator, prefix: []const u8, line: []const u8) Allocator.Error!void {
    try out.appendSlice(allocator, prefix);
    try out.appendSlice(allocator, line);
    try out.append(allocator, '\n');
}

fn expectEvent(expected: []const u8, name: []const u8, data: []const u8) !void {
    const allocator = std.testing.allocator;
    var out: ArrayList = .empty;
    defer out.deinit(allocator);

    try appendEvent(&out, allocator, name, data);
    try std.testing.expectEqualStrings(expected, out.items);
}

test "single line" {
    try expectEvent("event: line\ndata: hello\n\n", "line", "hello");
}

test "empty data" {
    try expectEvent("event: done\ndata: \n\n", "done", "");
}

test "multiline data keeps every line" {
    try expectEvent("event: frame\ndata: a\ndata: \ndata: b\n\n", "frame", "a\n\nb");
}

test "trailing line break is preserved" {
    try expectEvent("event: line\ndata: a\ndata: \n\n", "line", "a\n");
}

test "line breaks can not end the event early" {
    try expectEvent("event: x\ndata: a\ndata: b\ndata: c\n\n", "x", "a\r\nb\rc");
    try expectEvent("event: x\ndata: \ndata: \ndata: event: fake\n\n", "x", "\n\nevent: fake");
}

test "comment" {
    const allocator = std.testing.allocator;
    var out: ArrayList = .empty;
    defer out.deinit(allocator);

    try appendComment(&out, allocator, "keep-alive");
    try std.testing.expectEqualStrings(": keep-alive\n\n", out.items);
}
