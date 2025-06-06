const std = @import("std");

const common = @import("./common.zig");
const c_str = common.c_str;

const entity = @import("./entity.zig");
const HttpContext = entity.HttpContext;
const Response = entity.Response;

const ActionHandlerC = *const fn (*HttpContext) callconv(.C) ?*Response;
extern fn router_register(router: *Router, pattern: c_str, action: ActionHandlerC) callconv(.C) void;

pub const ActionHandler = *const fn (*HttpContext) anyerror!?*Response;
pub const Router = opaque {
    pub inline fn register(self: *Router, pattern: c_str, action: ActionHandler) void {
        const handler = struct {
            fn call(ctx: *HttpContext) callconv(.C) ?*Response {
                const res = action(ctx) catch |err| {
                    std.log.err("Route {s} returned error: {}", .{ pattern, err });
                    // todo? return 500 error
                    return null;
                };

                return res;
            }
        };

        router_register(self, pattern, handler.call);
    }
};
