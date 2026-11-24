const std = @import("std");
const Type = std.builtin.Type;

const common = @import("./common.zig");
const c_str = common.c_str;
const Shared = common.Shared;

extern "C" fn json_get(obj: *Json, key: c_str) callconv(.c) *Json;
extern "C" fn json_as_str(obj: *const Json) callconv(.c) ?c_str;

extern "C" fn json_new_object() callconv(.c) *Json;
extern "C" fn json_set(obj: *Json, key: c_str, value: *Json) callconv(.c) bool;
extern "C" fn json_dump(value: *const Json) callconv(.c) c_str;
extern "C" fn json_dump_pretty(value: *const Json, ident: u16) callconv(.c) c_str;

extern "C" fn json_new_array() callconv(.c) *Json;
extern "C" fn json_push(list: *Json, value: *Json) callconv(.c) bool;

extern "C" fn json_new_null() callconv(.c) *Json;
extern "C" fn json_new_number(value: f64) callconv(.c) *Json;
extern "C" fn json_new_bool(value: bool) callconv(.c) *Json;
extern "C" fn json_new_str(value: c_str) callconv(.c) *Json;
extern "C" fn json_drop(value: *Json) callconv(.c) void;

pub const Json = opaque {
    pub inline fn initObject() *Json {
        return json_new_object();
    }

    pub inline fn get(self: *Json, key: c_str) *Json {
        return json_get(self, key);
    }

    pub inline fn asStr(self: *const Json) ?c_str {
        return json_as_str(self);
    }

    pub inline fn asEnum(self: *const Json, comptime E: type) !E {
        const enum_meta = @typeInfo(E).@"enum";

        const value = self.asStr() orelse {
            return error.InvalidType;
        };

        inline for (enum_meta.field_names) |name| {
            if (std.mem.eql(u8, name, value[0..std.mem.len(value)])) {
                return @field(E, name);
            }
        }

        return error.InvalidEnumString;
    }

    /// Set value for object key. Passed `value` will be managed by the object.
    pub inline fn set(self: *Json, key: c_str, value: *Json) bool {
        return json_set(self, key, value);
    }

    pub inline fn dump(self: *const Json) c_str {
        return json_dump(self);
    }

    pub inline fn dumpPretty(self: *const Json, ident: u16) c_str {
        return json_dump_pretty(self, ident);
    }

    pub fn initArray() *Json {
        return json_new_array();
    }

    /// Push value into array. Passed `value` will be managed by the array.
    pub inline fn push(self: *Json, value: *Json) bool {
        return json_push(self, value);
    }

    pub fn initNull() *Json {
        return json_new_null();
    }

    pub fn initNumber(value: f64) *Json {
        return json_new_number(value);
    }

    pub fn initBool(value: bool) *Json {
        return json_new_bool(value);
    }

    pub fn initStr(value: c_str) *Json {
        return json_new_str(value);
    }

    pub fn deinit(self: *Json) void {
        return json_drop(self);
    }

    /// Creates new `Json` instance for given structure
    pub fn from(value: anytype) *Json {
        const T = @TypeOf(value);
        const info = @typeInfo(T);
        switch (info) {
            .bool => {
                return initBool(value);
            },
            .int, .comptime_int => {
                return initNumber(@as(f64, @floatFromInt(value)));
            },
            .float, .comptime_float => {
                return initNumber(@as(f64, @floatCast(value)));
            },
            .@"struct" => |struct_meta| {
                if (struct_meta.is_tuple) {
                    var list = initArray();
                    inline for (struct_meta.field_names) |field_name| {
                        _ = list.push(from(@field(value, field_name)));
                    }

                    return list;
                } else {
                    var obj = initObject();
                    inline for (struct_meta.field_names) |field_name| {
                        _ = obj.set(field_name, from(@field(value, field_name)));
                    }

                    return obj;
                }
            },
            .array => |arrayInfo| {
                if (arrayInfo.sentinel().? == 0 and arrayInfo.child == u8) {
                    return initStr(&value);
                }

                var list = initArray();
                inline for (0..arrayInfo.len) |i| {
                    _ = list.push(from(value[i]));
                }

                return list;
            },
            .pointer => |ptrInfo| {
                if (ptrInfo.size == .one) {
                    if (ptrInfo.child == Json) {
                        return value;
                    } else {
                        return from(value.*);
                    }
                } else if (ptrInfo.size == .slice) {
                    if (ptrInfo.sentinel()) |sentinel| {
                        if (sentinel == 0 and ptrInfo.child == u8) {
                            return initStr(value);
                        }
                    } else {
                        if (ptrInfo.child == u8) {
                            const tmp = common.ra.dupeSentinel(u8, value, 0) catch {
                                // todo! remove this when c_str will be replaced with slice
                                return initNull();
                            };
                            defer common.ra.free(tmp);

                            return initStr(tmp);
                        }
                    }
                }

                @compileError("Unable to interpret pointer " ++ @typeName(T) ++ "' as a JSON value");
            },
            .@"enum" => {
                return from(@tagName(value));
            },
            .enum_literal => {
                return from(@tagName(value));
            },
            .optional => {
                if (value) |inner| {
                    return from(inner);
                } else {
                    return initNull();
                }
            },
            else => {
                if (value == null) {
                    return initNull();
                } else {
                    @compileError("Unable to interpret '" ++ @typeName(T) ++ "' as a JSON value");
                }
            },
        }
    }

    /// Creates new owned `Json` instance for `anytype` or reference for `*Json`
    pub fn fromOrRef(json_like: anytype) Shared(*Json) {
        if (@TypeOf(json_like) == *Json) {
            return Shared(*Json).fromBorrowed(json_like);
        } else {
            const json = Json.from(json_like);
            return Shared(*Json).fromOwned(json);
        }
    }
};
