const std = @import("std");
const Type = std.builtin.Type;

const common = @import("../common.zig");
const impl = @import("impl.zig");

const errors = @import("error.zig");
pub const ValidationError = errors.ValidationError;
pub const ValidationResult = errors.ValidationResult;

const range = @import("range.zig");
pub const ValidateRange = range.ValidateRange;

const nested = @import("nested.zig");
pub const ValidateNested = nested.ValidateNested;

const StepMatch = struct {
    descriptor: Type.StructField,
    impl: impl.StepImpl,
};

fn matchStep(comptime fieldType: Type) ?StepMatch {
    switch (fieldType) {
        .@"struct" => |structInfo| {
            const descriptor = structInfo.fields[0];
            // That thing just convert comptime string to comptime value
            if (@hasField(impl.StepImpl, descriptor.name)) {
                return .{
                    .descriptor = descriptor,
                    .impl = @field(impl.StepImpl, descriptor.name),
                };
            }
        },
        else => {},
    }

    return null;
}

pub fn Validator(comptime Schema: type) type {
    const schema = @typeInfo(Schema).@"struct".fields;

    var fields: [schema.len]Type.StructField = undefined;
    var fieldsLen = 0;
    inline for (schema) |field| {
        const fieldType = @typeInfo(field.type);
        if (matchStep(fieldType)) |match| {
            fields[fieldsLen] = match.descriptor;
            fields[fieldsLen].name = field.name;
        } else {
            fields[fieldsLen] = field;
        }

        fieldsLen += 1;
    }

    const T = @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .is_tuple = false,
            .decls = &.{},
        },
    });

    return struct {
        pub const Raw = T;
        data: T,

        pub fn validateRawJson(raw: []const u8, options: std.json.ParseOptions) ValidationResult(std.json.Parsed(T)) {
            const parsed = std.json.parseFromSlice(T, common.ra, raw, options) catch |err| {
                if (std.fmt.allocPrintZ(common.ra, "Failed to parse JSON: {}", .{err})) |message| {
                    // string will be copied in ValidationError.init
                    // todo? owning in zig to allow passing values without copying?
                    defer common.ra.free(message);

                    return .{ .err = ValidationError.init(message) };
                } else |_| {
                    return .{ .err = ValidationError.init("Failed to parse JSON") };
                }
            };

            switch (validate(parsed.value)) {
                .err => |err| {
                    return .{ .err = err };
                },
                .ok => {
                    return .{ .ok = parsed };
                },
            }
        }

        pub fn validate(data: T) ValidationResult(T) {
            inline for (schema) |field| {
                const fieldType = @typeInfo(field.type);
                if (matchStep(fieldType)) |match| {
                    const fieldValue = @field(data, field.name);
                    if (match.impl.apply(match.descriptor.type, fieldType, fieldValue)) |err| {
                        err.prependPath(field.name);
                        return .{ .err = err };
                    }
                }
            }

            return .{ .ok = data };
        }
    };
}
