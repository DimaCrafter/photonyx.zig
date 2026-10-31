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

pub const SetterFn = *const fn (entity: *anyopaque, value: ?*const anyopaque) callconv(.c) void;

pub fn initEntity(comptime T: type) InitFn(T) {
    return &struct {
        fn init() callconv(.c) ?*T {
            const ptr = common.ra.create(T) catch return null;
            const struct_meta = @typeInfo(T).@"struct";

            inline for (struct_meta.field_names, struct_meta.field_types, struct_meta.field_attrs) |field_name, F, attrs| {
                @field(ptr, field_name) = defaultValue(F, attrs);
            }

            return ptr;
        }
    }.init;
}

pub fn deinitEntity(comptime T: type) DeinitFn(T) {
    return &struct {
        fn deinit(ptr: *T) callconv(.c) void {
            const struct_meta = @typeInfo(T).@"struct";

            inline for (struct_meta.field_names, struct_meta.field_types) |field_name, F| {
                freeValue(F, @field(ptr, field_name));
            }

            common.ra.destroy(ptr);
        }
    }.deinit;
}

fn freeValue(comptime F: type, value: F) void {
    switch (F) {
        []const u8 => common.ra.free(value),
        ?[]const u8 => if (value) |inner| common.ra.free(inner),
        *datetime.DateTime => value.deinit(),
        ?*datetime.DateTime => if (value) |inner| inner.deinit(),
        else => {
            // other types are plain values
        },
    }
}

pub fn get_setters(comptime T: type) [@typeInfo(T).@"struct".field_names.len]SetterFn {
    const struct_meta = @typeInfo(T).@"struct";
    var result: [struct_meta.field_names.len]SetterFn = undefined;

    inline for (0..struct_meta.field_names.len) |i| {
        result[i] = get_setter(T, i);
    }

    return result;
}

fn get_setter(comptime T: type, comptime index: usize) SetterFn {
    const struct_meta = @typeInfo(T).@"struct";
    const name = struct_meta.field_names[index];
    const F = struct_meta.field_types[index];
    const attrs = struct_meta.field_attrs[index];

    return &struct {
        fn set(instance: *anyopaque, value_opt: ?*const anyopaque) callconv(.c) void {
            const target: *T = @ptrCast(@alignCast(instance));
            freeValue(F, @field(target, name));

            if (value_opt) |value| {
                @field(target, name) = readValue(F, value);
            } else if (@typeInfo(F) == .optional) {
                @field(target, name) = null;
            } else {
                // NULL in a NOT NULL column
                @field(target, name) = defaultValue(F, attrs);
            }
        }
    }.set;
}

fn readValue(comptime F: type, value: *const anyopaque) F {
    switch (F) {
        []const u8 => {
            const slice: *const Slice(u8) = @ptrCast(@alignCast(value));
            return dupeString(slice.intoNative());
        },
        *datetime.DateTime => {
            // The entity takes ownership of the value created by the driver
            return @ptrCast(@constCast(value));
        },
        else => {},
    }

    switch (@typeInfo(F)) {
        .optional => |optional_meta| {
            return readValue(optional_meta.child, value);
        },
        .@"enum" => |enum_meta| {
            const ordinal: *const u32 = @ptrCast(@alignCast(value));
            return @fromBackingInt(@as(enum_meta.tag_type, @intCast(ordinal.*)));
        },
        .int, .float, .bool => {
            return @as(*const F, @ptrCast(@alignCast(value))).*;
        },
        else => {
            @compileError("Unsupported model field type: " ++ @typeName(F));
        },
    }
}

fn defaultValue(comptime F: type, comptime attrs: std.lang.Type.Struct.FieldAttributes) F {
    if (comptime attrs.defaultValue(F)) |default| {
        return switch (F) {
            []const u8 => dupeString(default),
            ?[]const u8 => if (default) |value| dupeString(value) else null,
            else => default,
        };
    }

    return switch (F) {
        []const u8 => dupeString(""),
        bool => false,
        *datetime.DateTime => datetime.DateTime.from_micros(0),
        else => switch (@typeInfo(F)) {
            .optional => null,
            .int, .float => 0,
            .@"enum" => |enum_meta| @field(F, enum_meta.field_names[0]),
            else => @compileError("No default value for " ++ @typeName(F)),
        },
    };
}

fn dupeString(value: []const u8) []const u8 {
    return common.ra.dupe(u8, value) catch {
        // TODO: report out of memory
        return "";
    };
}
