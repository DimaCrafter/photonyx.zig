const std = @import("std");
const entity = @import("entity.zig");

const common = @import("../common.zig");
const c_str = common.c_str;
const Slice = common.Slice;

extern "C" fn model_meta_add_field(model: *ModelMeta, name: c_str, _meta: ModelFieldMeta, setter: entity.SetterFn) callconv(.C) void;

pub const ModelMeta = opaque {
    pub inline fn addField(self: *ModelMeta, name: c_str, _meta: ModelFieldMeta, setter: entity.SetterFn) void {
        model_meta_add_field(self, name, _meta, setter);
    }

    pub fn addFieldsFrom(self: *ModelMeta, comptime T: type) void {
        inline for (@typeInfo(T).@"struct".fields) |field| {
            const holder = struct {
                pub fn setField(instance: *T, value_opt: ?*anyopaque) callconv(.C) void {
                    if (value_opt) |value| {
                        copyValue(T, instance, field.name, value) catch {
                            // todo! handle it somehow
                            return;
                        };
                    } else {
                        setDefaultValue(T, instance, field.name);
                    }
                }
            };

            const field_meta = ModelFieldMeta.parse(field.type);
            // todo! include constraints into field meta
            self.addField(field.name, field_meta, @ptrCast(&holder.setField));
        }
    }
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
        else => {
            const info = @typeInfo(T);
            switch (info) {
                .@"enum" => |enum_info| {
                    return @field(T, enum_info.fields[0].name);
                },
                .array => |array_info| {
                    return [_]array_info.child{getDefaultValue(array_info.child)} ** array_info.len;
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

const ModelFieldType = enum(u8) {
    Unknown,
    U8,
    I8,
    U16,
    I16,
    F32,
    U32,
    I32,
    F64,
    U64,
    I64,
    Bool,
    String,
    Array,
    Enum,

    pub fn from(comptime T: type) ModelFieldType {
        return comptime switch (T) {
            u8 => .U8,
            i8 => .I8,
            u16 => .U16,
            i16 => .I16,
            f32 => .F32,
            u32 => .U32,
            i32 => .I32,
            f64 => .F64,
            u64 => .U64,
            i64 => .I64,
            bool => .Bool,
            []const u8 => .String,
            else => .Unknown,
        };
    }
};

const ModelFieldMeta = extern struct {
    type_id: ModelFieldType,
    length: usize = 0,
    optional: bool = false,
    enum_values: [*]c_str = undefined,
    enum_size: usize = 0,

    pub fn parse(comptime T: type) ModelFieldMeta {
        const type_id = comptime ModelFieldType.from(T);
        if (type_id != .Unknown) {
            return .{ .type_id = type_id };
        }

        const info = @typeInfo(T);
        switch (info) {
            .optional => |opt_info| {
                var result = parse(opt_info.child);
                result.optional = true;
                return result;
            },
            .array => |array_info| {
                return .{
                    .type_id = comptime ModelFieldType.from(array_info.child),
                    .length = array_info.len,
                };
            },
            .@"enum" => |enum_info| {
                var values = common.ra.alloc(c_str, enum_info.fields.len) catch {
                    // todo! handle it somehow
                    std.process.exit(0xFE);
                };

                inline for (0..enum_info.fields.len) |i| {
                    values[i] = enum_info.fields[i].name;
                }

                return .{
                    .type_id = .Enum,
                    .enum_values = values.ptr,
                    .enum_size = values.len,
                    .length = @sizeOf(T),
                };
            },
            else => {
                @compileError("Unsupported model field type: " ++ @typeName(T));
            },
        }
    }
};
