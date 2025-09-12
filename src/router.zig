const std = @import("std");

const common = @import("./common.zig");
const c_str = common.c_str;

const Json = @import("./json.zig").Json;
const HttpCode = @import("./codes.zig").HttpCode;

const entity = @import("./entity.zig");
const HttpContext = entity.HttpContext;
const Response = entity.Response;

pub const ActionHandler = *const fn (*HttpContext) anyerror!void;
const ActionHandlerC = *const fn (*HttpContext) callconv(.c) ?*Response;
extern "C" fn router_register(router: *Router, pattern: c_str, action: ActionHandlerC) callconv(.c) void;

pub const MiddlewareFn = *const fn (*HttpContext) anyerror!MiddlewareResult;
const MiddlewareFnC = *const fn (*HttpContext) callconv(.c) MiddlewareResult;
extern "C" fn router_use(router: *Router, pattern: c_str, action: MiddlewareFnC) callconv(.c) void;

pub const Router = opaque {
    pub inline fn register(self: *Router, pattern: c_str, action: ActionHandler) void {
        const handler = struct {
            fn call(ctx: *HttpContext) callconv(.c) ?*Response {
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

    pub inline fn use(self: *Router, pattern: c_str, middleware: MiddlewareFn) void {
        const handler = struct {
            fn call(ctx: *HttpContext) callconv(.c) MiddlewareResult {
                return middleware(ctx) catch |err| {
                    if (err != error.ValidationError) {
                        ctx.send(.{
                            .code = HttpCode.InternalServerError,
                            .json = .{ .type = "InternalError" },
                        });
                    }

                    return .Stop;
                };
            }
        };

        router_use(self, pattern, handler.call);
    }
};

pub const MiddlewareResult = enum(u8) {
    /// Continue execution of middleware chain
    Continue,
    /// Stop execution of middleware chain and call the action handler
    Stop,
};
