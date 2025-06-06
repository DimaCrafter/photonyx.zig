const std = @import("std");
const Type = std.builtin.Type;

const common = @import("./common.zig");
const c_str = common.c_str;

pub const Json = opaque {
    pub inline fn new_object() *Json {
        return json_new_object();
    }

    pub inline fn set(self: *Json, key: c_str, value: *Json) bool {
        return json_set(self, key, value);
    }

    pub inline fn dump(self: *const Json) c_str {
        return json_dump(self);
    }

    pub inline fn dump_pretty(self: *const Json, ident: u16) c_str {
        return json_dump_pretty(self, ident);
    }

    pub fn new_array() *Json {
        return json_new_array();
    }

    pub inline fn push(self: *Json, value: *Json) bool {
        return json_push(self, value);
    }

    pub fn new_null() *Json {
        return json_new_null();
    }

    pub fn new_number(value: f64) *Json {
        return json_new_number(value);
    }

    pub fn new_bool(value: bool) *Json {
        return json_new_bool(value);
    }

    pub fn new_str(value: c_str) *Json {
        return json_new_str(value);
    }

    pub fn deinit(self: *Json) void {
        return json_drop(self);
    }

    pub fn from(value: anytype) *Json {
        const T = @TypeOf(value);
        const info = @typeInfo(T);
        switch (info) {
            .bool => {
                return new_bool(value);
            },
            .int, .comptime_int => {
                return new_number(@as(f64, @floatFromInt(value)));
            },
            .float, .comptime_float => {
                return new_number(@as(f64, @floatCast(value)));
            },
            .@"struct" => |structInfo| {
                if (structInfo.is_tuple) {
                    var list = new_array();
                    inline for (structInfo.fields) |field| {
                        _ = list.push(from(@field(value, field.name)));
                    }

                    return list;
                } else {
                    var obj = new_object();
                    inline for (structInfo.fields) |field| {
                        _ = obj.set(field.name, from(@field(value, field.name)));
                    }

                    return obj;
                }
            },
            .array => |arrayInfo| {
                if (arrayInfo.sentinel().? == 0 and arrayInfo.child == u8) {
                    return new_str(&value);
                }

                var list = new_array();
                inline for (0..arrayInfo.len) |i| {
                    _ = list.push(from(value[i]));
                }

                return list;
            },
            .pointer => |ptrInfo| {
                if (ptrInfo.size == .one) {
                    return from(value.*);
                }
                @compileError("Unable to interpret pointer " ++ @typeName(T) ++ "' as a JSON value");
            },
            else => {
                if (value == null) {
                    return new_null();
                } else {
                    @compileError("Unable to interpret '" ++ @typeName(T) ++ "' as a JSON value");
                }
            },
        }
    }
};

extern "C" fn json_new_object() callconv(.C) *Json;
extern "C" fn json_set(obj: *Json, key: c_str, value: *Json) callconv(.C) bool;
extern "C" fn json_dump(value: *const Json) callconv(.C) c_str;
extern "C" fn json_dump_pretty(value: *const Json, ident: u16) callconv(.C) c_str;

extern "C" fn json_new_array() callconv(.C) *Json;
extern "C" fn json_push(list: *Json, value: *Json) callconv(.C) bool;

extern "C" fn json_new_null() callconv(.C) *Json;
extern "C" fn json_new_number(value: f64) callconv(.C) *Json;
extern "C" fn json_new_bool(value: bool) callconv(.C) *Json;
extern "C" fn json_new_str(value: c_str) callconv(.C) *Json;
extern "C" fn json_drop(value: *Json) callconv(.C) void;
