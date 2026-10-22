const std = @import("std");

const common = @import("../common.zig");
const Slice = common.Slice;

const datetime = @import("../datetime.zig");

pub fn InitFn(comptime T: type) type {
    return *const fn () callconv(.c) ?*T;
}

pub fn DeinitFn(comptime T: type) type {
    return *const fn (*T) callconv(.c) void;
}

pub const SetterFn = *const fn (entity: *anyopaque, value: *anyopaque) callconv(.c) void;

pub const LinkPolicy = enum(u8) {
    /// Link will be used just as key
    none,
    /// Service.user_id --> User: operation on User will be restricted if Service exist
    restrict,
    /// Service.user_id --> User: operation on User will cause some operation on Service
    cascade,
    /// Service.user_id --> User: operation on User will set Service.user_id to null
    set_null,
};

pub const Link = struct {
    model: type,
    delete: LinkPolicy = .none,
    update: LinkPolicy = .none,
};

pub const Self = opaque {};

pub const sql = struct {
    pub const PrimaryKey = struct {};
    pub const Length = struct { u32 };
};

fn setDefaultValue(comptime T: type, instance: *T, comptime key: [:0]const u8) void {
    const F = @FieldType(T, key);
    @field(instance, key) = getDefaultValue(F);
}

fn getDefaultValue(comptime T: type) T {
    switch (T) {
        []const u8 => {
            return "";
        },
        i8, u8, i16, u16, i32, u32, f32, i64, u64, f64 => {
            return 0;
        },
        bool => {
            return false;
        },
        *datetime.DateTime => {
            return datetime.DateTime.from_micros(0);
        },
        else => {
            const info = @typeInfo(T);
            switch (info) {
                .@"enum" => |enum_meta| {
                    return @field(T, enum_meta.field_names[0]);
                },
                .array => |array_info| {
                    const value: [array_info.len]array_info.child = @splat(getDefaultValue(array_info.child));
                    return value;
                },
                .optional => {
                    return null;
                },
                else => {
                    @compileError("No default value for the " ++ @typeName(T));
                },
            }
        },
    }
}

fn copyValue(comptime T: type, instance: *T, comptime key: [:0]const u8, value: *anyopaque) !void {
    const F = @FieldType(T, key);
    switch (F) {
        []const u8 => {
            const slice_ptr: *Slice(u8) = @ptrCast(@alignCast(value));
            @field(instance, key) = try common.ra.dupe(u8, slice_ptr.intoNative());
        },
        else => {
            @field(instance, key) = @as(*F, @ptrCast(@alignCast(value))).*;
        },
    }
}

pub inline fn setValue(comptime T: type, instance: *T, comptime key: [:0]const u8, value_opt: ?*anyopaque) void {
    if (value_opt) |value| {
        copyValue(T, instance, key, value) catch {
            // todo! handle it somehow
            return;
        };
    } else {
        setDefaultValue(T, instance, key);
    }
}
