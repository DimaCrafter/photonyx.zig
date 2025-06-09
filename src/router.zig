const std = @import("std");

const common = @import("./common.zig");
const c_str = common.c_str;

const Json = @import("./json.zig").Json;
const HttpCode = @import("./codes.zig").HttpCode;

const entity = @import("./entity.zig");
const HttpContext = entity.HttpContext;
const Response = entity.Response;

const ActionHandlerC = *const fn (*HttpContext) callconv(.C) ?*Response;
extern "C" fn router_register(router: *Router, pattern: c_str, action: ActionHandlerC) callconv(.C) void;

pub const ActionHandler = *const fn (*HttpContext) anyerror!void;
pub const Router = opaque {
    pub inline fn register(self: *Router, pattern: c_str, action: ActionHandler) void {
        const handler = struct {
            fn call(ctx: *HttpContext) callconv(.C) ?*Response {
                action(ctx) catch |err| {
                    if (err == error.ValidationError) {
                        return null;
                    }

                    ctx.send(.{
                        .code = HttpCode.InternalServerError,
                        .json = .{ .type = "InternalError" },
                    });
                };

                return null;
            }
        };

        router_register(self, pattern, handler.call);
    }
};
