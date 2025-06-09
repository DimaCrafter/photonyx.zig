const std = @import("std");
const Type = std.builtin.Type;

const range = @import("range.zig");
const nested = @import("nested.zig");
pub const ValidationError = @import("error.zig").ValidationError;

fn getStepArgs(comptime T: type, comptime fieldType: Type) T {
    const argsField = fieldType.@"struct".fields[1];
    return argsField.defaultValue() orelse @compileError("no args meta-value");
}

pub const StepImpl = enum {
    rangeT,
    nestedT,

    pub fn apply(comptime self: StepImpl, comptime T: type, comptime fieldType: Type, value: T) ?*ValidationError {
        switch (self) {
            .rangeT => {
                return range.apply(T, getStepArgs(range.StepArgs(T), fieldType), value);
            },
            .nestedT => {
                return nested.apply(T, getStepArgs(nested.StepArgs, fieldType), value);
            },
        }
    }
};
