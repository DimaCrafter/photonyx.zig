const common = @import("../common.zig");
const c_str = common.c_str;

const Json = @import("../json.zig").Json;

extern "C" fn validation_error_new(message: c_str) callconv(.C) *ValidationError;
extern "C" fn validation_error_prepend_path(err: *ValidationError, parent_key: c_str) callconv(.C) void;
extern "C" fn validation_error_into_json(err: *ValidationError) callconv(.C) *Json;
extern "C" fn validation_error_drop(err: *ValidationError) callconv(.C) void;

pub const ValidationError = opaque {
    pub inline fn init(message: c_str) *ValidationError {
        return validation_error_new(message);
    }

    pub inline fn prependPath(self: *ValidationError, parent_key: c_str) void {
        validation_error_prepend_path(self, parent_key);
    }

    pub inline fn intoJson(self: *ValidationError) *Json {
        return validation_error_into_json(self);
    }

    pub inline fn deinit(self: *ValidationError) void {
        validation_error_drop(self);
    }
};

pub fn ValidationResult(comptime T: type) type {
    return union(enum) {
        err: *ValidationError,
        ok: T,

        pub fn intoError(self: @This()) ?*ValidationError {
            switch (self) {
                .err => |err| return err,
                .ok => return null,
            }
        }

        pub fn deinit(self: @This()) void {
            if (self.err) |err| {
                err.deinit();
            }
        }
    };
}
