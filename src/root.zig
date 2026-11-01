const std = @import("std");

pub const ra = @import("./common.zig").ra;
pub const HttpCode = @import("./codes.zig").HttpCode;
pub const Json = @import("./json.zig").Json;

const entity = @import("./entity.zig");
pub const HttpContext = entity.HttpContext;
pub const HttpHeaders = entity.HttpHeaders;
pub const HttpMethod = entity.HttpMethod;
pub const ResponseStream = entity.ResponseStream;
pub const SseStream = entity.SseStream;
pub const Response = entity.Response;
pub const Request = entity.Request;

const router = @import("./router.zig");
pub const ActionHandler = router.ActionHandler;
pub const MiddlewareFn = router.MiddlewareFn;
pub const Router = router.Router;
pub const MiddlewareResult = router.MiddlewareResult;

pub const utils = @import("./utils.zig");
pub const validator = @import("./validator/index.zig");
pub const meta = @import("./meta.zig");
pub const models = @import("./models/index.zig");

const _config = @import("./config.zig");
// Using `undefined` is safe here because `init_module` is the module's entrypoint
pub var config: *const _config.Config = undefined;

var threaded: std.Io.Threaded = undefined;

pub fn io() std.Io {
    return threaded.io();
}

export fn init_module() void {
    config = _config.Config.borrow();
    threaded = std.Io.Threaded.init(ra, .{});
}
