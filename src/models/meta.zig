const std = @import("std");
const entity = @import("entity.zig");

const common = @import("../common.zig");
const c_str = common.c_str;
const Slice = common.Slice;

const datetime = @import("../datetime.zig");

extern "C" fn model_meta_add_field(model: *ModelMeta, name: c_str, setter: entity.SetterFn) callconv(.c) *ModelFieldMeta;
extern "C" fn model_meta_add_unique_key(model: *ModelMeta, compound: *const []const []const u8) callconv(.c) void;

pub const ModelMeta = opaque {
    pub inline fn addField(self: *ModelMeta, name: c_str, setter: entity.SetterFn) *ModelFieldMeta {
        return model_meta_add_field(self, name, setter);
    }

    pub fn addFieldsFrom(self: *ModelMeta, comptime M: type) void {
        const struct_meta = @typeInfo(M.T).@"struct";

        inline for (struct_meta.field_types, struct_meta.field_names) |field_type, field_name| {
            const holder = struct {
                pub fn setField(instance: *M.T, value_opt: ?*anyopaque) callconv(.c) void {
                    entity.setValue(M.T, instance, field_name, value_opt);
                }
            };

            const field_meta = self.addField(field_name, @ptrCast(&holder.setField));
            field_meta.parseInto(field_type);

            const constraints = M._getConstraints();
            if (@hasField(@TypeOf(constraints), field_name)) {
                field_meta.applyConstraints(M, @field(constraints, field_name));
            }
        }
    }

    pub inline fn addUniqueKey(self: *ModelMeta, compound: []const []const u8) void {
        model_meta_add_unique_key(self, &compound);
    }
};

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
    Enum,
    DateTime,

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
            *datetime.DateTime => .DateTime,
            else => .Unknown,
        };
    }
};

extern "C" fn model_field_meta_add_length(field_meta: *ModelFieldMeta, value: u32) callconv(.c) void;
extern "C" fn model_field_meta_add_primary_key(field_meta: *ModelFieldMeta) callconv(.c) void;
extern "C" fn model_field_meta_add_link(field_meta: *ModelFieldMeta, dst_collection: c_str, dst_column: c_str, delete: entity.LinkPolicy, update: entity.LinkPolicy) callconv(.c) void;

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
            .@"enum" => |enum_meta| {
                const enum_size = enum_meta.field_names.len;
                var values = common.ra.alloc(c_str, enum_size) catch {
                    // todo! handle it somehow
                    std.process.exit(0xFE);
                };

                inline for (0..enum_size) |i| {
                    values[i] = enum_meta.field_names[i];
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
                    if (constraint == entity.sql.PrimaryKey) {
                        model_field_meta_add_primary_key(self);
                        continue;
                    } else {
                        @compileError("Unknown constraint type mark: " ++ @typeName(constraint));
                    }
                },
                entity.Link => {
                    const dst_model = if (constraint.model == entity.Self) M else constraint.model;

                    if (comptime dst_model._findPrimaryKey()) |dst_column| {
                        model_field_meta_add_link(self, dst_model._name, dst_column, constraint.delete, constraint.update);
                    } else {
                        @compileError("Failed to find primary key for " ++ dst_model._name);
                    }
                },
                entity.sql.Length => {
                    model_field_meta_add_length(self, constraint.@"0");
                },
                else => {
                    @compileError("Unknown constraint structure: " ++ @typeName(@TypeOf(constraint)));
                },
            }
        }
    }
};
