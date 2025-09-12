const c_str = @import("./common.zig").c_str;
const Json = @import("./json.zig").Json;

extern "C" fn session_get_data(session: *Session) callconv(.c) *Json;
extern "C" fn session_is_none(session: *const Session) callconv(.c) bool;

pub const Session = opaque {
    pub inline fn get(self: *Session, key: c_str) *Json {
        return session_get_data(self).get(key);
    }

    pub inline fn set(self: *Session, key: c_str, value: anytype) void {
        var value_json = Json.from_or_ref(value);
        _ = session_get_data(self).set(key, value_json.move());
    }

    pub inline fn isNone(self: *const Session) bool {
        return session_is_none(self);
    }
};
