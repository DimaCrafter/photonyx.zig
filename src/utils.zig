const std = @import("std");
const common = @import("common.zig");

pub fn splitOnce(comptime T: type, str: []const T, sep: T) ?struct { []const T, []const T } {
    var parts = std.mem.splitScalar(T, str, sep);
    if (parts.next()) |first| {
        const rest = parts.rest();
        if (rest.len != 0) {
            return .{ first, parts.rest() };
        }
    }

    return null;
}

pub fn decodeBase64(input: []const u8) !std.ArrayList(u8) {
    var result = std.ArrayList(u8).init(common.ra);
    errdefer result.deinit();

    try result.resize(try std.base64.standard.Decoder.calcSizeForSlice(input));
    try std.base64.standard.Decoder.decode(result.items, input);
    return result;
}

pub inline fn checkAccessLevel(required: anytype, given: @TypeOf(required)) bool {
    return @intFromEnum(given) >= @intFromEnum(required);
}
