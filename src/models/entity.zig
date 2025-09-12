pub fn InitFn(comptime T: type) type {
    return *const fn () callconv(.c) ?*T;
}

pub fn DeinitFn(comptime T: type) type {
    return *const fn (*T) callconv(.c) void;
}

pub const SetterFn = *const fn (entity: *anyopaque, value: *anyopaque) callconv(.c) void;
