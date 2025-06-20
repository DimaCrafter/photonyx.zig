pub fn InitFn(comptime T: type) type {
    return *const fn () callconv(.C) ?*T;
}

pub fn DeinitFn(comptime T: type) type {
    return *const fn (*T) callconv(.C) void;
}

pub const SetterFn = *const fn (entity: *anyopaque, value: *anyopaque) callconv(.C) void;
