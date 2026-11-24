const std = @import("std");

extern fn datetime_from_micros(timestamp: i64) callconv(.c) *DateTime;
extern fn datetime_deinit(value: *DateTime) callconv(.c) void;

pub const DateTime = opaque {
    pub inline fn fromMicros(timestamp: i64) *DateTime {
        return datetime_from_micros(timestamp);
    }

    pub inline fn deinit(self: *DateTime) void {
        datetime_deinit(self);
    }
};

pub const current_date: *DateTime = @ptrFromInt(std.math.maxInt(usize));
