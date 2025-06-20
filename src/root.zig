pub usingnamespace @import("./codes.zig");
pub usingnamespace @import("./common.zig");
pub usingnamespace @import("./entity.zig");
pub usingnamespace @import("./json.zig");
pub usingnamespace @import("./router.zig");
pub usingnamespace @import("./validator/index.zig");
pub const meta = @import("./meta.zig");

pub const models = @import("./models/index.zig");

pub const _config = @import("./config.zig");
// Using `undefined` is safe here because `init_module` is the module's entrypoint
pub var config: *const _config.Config = undefined;

export fn init_module() void {
    config = _config.Config.borrow();
}
