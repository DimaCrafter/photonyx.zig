const std = @import("std");

extern fn datetime_from_micros(timestamp: i64) callconv(.c) *DateTime;

pub const DateTime = opaque {
    pub inline fn from_micros(timestamp: i64) *DateTime {
        return datetime_from_micros(timestamp);
    }
};

pub const CURRENT_DATE: *DateTime = @ptrFromInt(std.math.maxInt(usize));
