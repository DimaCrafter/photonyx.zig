const std = @import("std");
pub const ValidationError = @import("error.zig").ValidationError;

pub fn StepArgs(comptime T: type) type {
    return struct {
        min: T,
        max: T,
    };
}

pub fn ValidateRange(comptime T: type, comptime min: T, comptime max: T) type {
    return struct {
        rangeT: T,
        args: StepArgs(T) = .{ .min = min, .max = max },
    };
}

pub fn apply(comptime T: type, comptime args: StepArgs(T), value: T) ?*ValidationError {
    if (args.min > args.max) {
        @compileLog(args.min, args.max);
        @compileError("range min > max");
    }

    if (value < args.min or value > args.max) {
        const msg = std.fmt.comptimePrint("value out of range [{d}; {d}]", .{ args.min, args.max });
        return ValidationError.init(msg);
    }

    return null;
}
