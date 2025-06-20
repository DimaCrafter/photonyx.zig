const common = @import("./common.zig");
const c_str = common.c_str;

const Json = @import("./json.zig").Json;

extern "C" fn get_config() callconv(.C) *const Config;
extern "C" fn config_get_path(config: *const Config, path: c_str) callconv(.C) *const Json;

pub const Config = opaque {
    pub inline fn borrow() *const Config {
        return get_config();
    }

    /// Returned value is owned by Photonyx
    pub inline fn getPath(self: *const Config, path: c_str) *const Json {
        return config_get_path(self, path);
    }
};
