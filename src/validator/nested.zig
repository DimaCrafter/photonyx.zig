pub const ValidationError = @import("error.zig").ValidationError;

pub const StepArgs = struct {
    validator: type,
};

pub fn ValidateNested(comptime T: type) type {
    return struct {
        nestedT: T.Raw,
        args: StepArgs = .{ .validator = T },
    };
}

pub fn apply(comptime T: type, comptime args: StepArgs, value: T) ?*ValidationError {
    return args.validator.validate(value).intoError();
}
