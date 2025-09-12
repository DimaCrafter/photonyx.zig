const std = @import("std");
const entity = @import("entity.zig");

const common = @import("../common.zig");
const c_str = common.c_str;
const Slice = common.Slice;

extern "C" fn model_meta_add_field(model: *ModelMeta, name: c_str, setter: entity.SetterFn) callconv(.c) *ModelFieldMeta;
extern "C" fn model_meta_add_unique_key(model: *ModelMeta, compound: *const []const []const u8) callconv(.c) void;

pub const ModelMeta = opaque {
    pub inline fn addField(self: *ModelMeta, name: c_str, setter: entity.SetterFn) *ModelFieldMeta {
        return model_meta_add_field(self, name, setter);
    }

    pub fn addFieldsFrom(self: *ModelMeta, comptime M: type) void {
        inline for (@typeInfo(M.T).@"struct".fields) |field| {
            const holder = struct {
                pub fn setField(instance: *M.T, value_opt: ?*anyopaque) callconv(.c) void {
                    if (value_opt) |value| {
                        copyValue(M.T, instance, field.name, value) catch {
                            // todo! handle it somehow
                            return;
                        };
                    } else {
                        setDefaultValue(M.T, instance, field.name);
                    }
                }
            };

            // todo! include constraints into field meta
            const field_meta = self.addField(field.name, @ptrCast(&holder.setField));
            field_meta.parseInto(field.type);

            const constraints = M._getConstraints();
            if (@hasField(@TypeOf(constraints), field.name)) {
                field_meta.applyConstraints(M, @field(constraints, field.name));
            }
        }
    }

    pub inline fn addUniqueKey(self: *ModelMeta, compound: []const []const u8) void {
        model_meta_add_unique_key(self, &compound);
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

extern "C" fn model_field_meta_add_length(field_meta: *ModelFieldMeta, value: u32) callconv(.c) void;
extern "C" fn model_field_meta_add_primary_key(field_meta: *ModelFieldMeta) callconv(.c) void;
extern "C" fn model_field_meta_add_link(field_meta: *ModelFieldMeta, dst_collection: c_str, dst_column: c_str, delete: LinkPolicy, update: LinkPolicy) callconv(.c) void;

const ModelFieldMeta = extern struct {
    type_id: ModelFieldType,
    length: usize = 0,
    optional: bool = false,
    enum_values: [*]c_str = undefined,
    enum_size: usize = 0,

    pub fn parseInto(self: *ModelFieldMeta, comptime T: type) void {
        const type_id = comptime ModelFieldType.from(T);
        if (type_id != .Unknown) {
            self.type_id = type_id;
            return;
        }

        const info = @typeInfo(T);
        switch (info) {
            .optional => |opt_info| {
                self.parseInto(opt_info.child);
                self.optional = true;
            },
            .array => |array_info| {
                self.type_id = comptime ModelFieldType.from(array_info.child);
                self.length = array_info.len;
            },
            .@"enum" => |enum_info| {
                var values = common.ra.alloc(c_str, enum_info.fields.len) catch {
                    // todo! handle it somehow
                    std.process.exit(0xFE);
                };

                inline for (0..enum_info.fields.len) |i| {
                    values[i] = enum_info.fields[i].name;
                }

                self.type_id = .Enum;
                self.enum_values = values.ptr;
                self.enum_size = values.len;
                self.length = @sizeOf(T);
            },
            else => {
                @compileError("Unsupported model field type: " ++ @typeName(T));
            },
        }
    }

    pub fn applyConstraints(self: *ModelFieldMeta, comptime M: type, comptime constraints: anytype) void {
        inline for (constraints) |constraint| {
            switch (@TypeOf(constraint)) {
                type => {
                    if (constraint == sql.PrimaryKey) {
                        model_field_meta_add_primary_key(self);
                        continue;
                    } else {
                        @compileError("Unknown constraint type mark: " ++ @typeName(constraint));
                    }
                },
                Link => {
                    const dst_model = if (constraint.model == Self) M else constraint.model;

                    if (comptime dst_model._findPrimaryKey()) |dst_column| {
                        model_field_meta_add_link(self, dst_model._name, dst_column, constraint.delete, constraint.update);
                    } else {
                        @compileError("Failed to find primary key for " ++ dst_model._name);
                    }
                },
                sql.Length => {
                    model_field_meta_add_length(self, constraint.@"0");
                },
                else => {
                    @compileError("Unknown constraint structure: " ++ @typeName(@TypeOf(constraint)));
                },
            }
        }
    }
};
