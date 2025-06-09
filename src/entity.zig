const std = @import("std");

const common = @import("./common.zig");
const c_str = common.c_str;
const Slice = common.Slice;

const HttpCode = @import("./codes.zig").HttpCode;
const Json = @import("./json.zig").Json;

extern "C" fn http_context_set_response(ctx: *HttpContext, res: *Response) callconv(.C) void;
extern "C" fn http_context_get_body_ref(ctx: *const HttpContext) callconv(.C) Slice(u8);
extern "C" fn http_context_get_response(ctx: *HttpContext) callconv(.C) *Response;

pub const HttpContext = opaque {
    pub inline fn getBodyRef(self: *const HttpContext) []const u8 {
        return http_context_get_body_ref(self).intoNative();
    }

    pub fn validate(self: *HttpContext, comptime V: type) !std.json.Parsed(V.Raw) {
        const raw = self.getBodyRef();

        switch (V.validateRawJson(raw, .{})) {
            .err => |err| {
                self.jsonStatus(HttpCode.BadRequest, err.intoJson());
                return error.ValidationError;
            },
            .ok => |parsed| {
                return parsed;
            },
        }
    }

    pub inline fn setHeader(self: *HttpContext, name: c_str, value: c_str) void {
        const res = http_context_get_response(self);
        res.headers().set(name, value);
    }

    /// resSchema.code: HttpCode
    /// resSchema.json: *Json or anytype
    /// resSchema.raw: []const u8
    pub fn send(self: *HttpContext, resSchema: anytype) void {
        const S = @TypeOf(resSchema);
        const res = http_context_get_response(self);

        if (@hasField(S, "json")) {
            const jsonLike = @field(resSchema, "json");

            if (@TypeOf(jsonLike) == *Json) {
                const msg = jsonLike.dump();
                res.setPayload(msg[0..std.mem.len(msg)]);
            } else {
                const json = Json.from(jsonLike);
                defer json.deinit();

                const msg = json.dump();
                res.setPayload(msg[0..std.mem.len(msg)]);
            }
        }

        if (@hasField(S, "raw")) {
            res.setPayload(@field(resSchema, "raw"));
        }

        if (@hasField(S, "code")) {
            res.setCode(@field(resSchema, "code"));
        } else {
            res.setCode(HttpCode.OK);
        }
    }
};

extern "C" fn http_headers_set(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.C) void;
extern "C" fn http_headers_set_default(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.C) void;
extern "C" fn http_headers_set_normal(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.C) void;

pub const HttpHeaders = opaque {
    pub inline fn set(self: *HttpHeaders, name: c_str, value: c_str) void {
        http_headers_set(self, name, value);
    }

    pub inline fn setDefault(self: *HttpHeaders, name: c_str, value: c_str) void {
        http_headers_set_default(self, name, value);
    }

    pub inline fn setNormal(self: *HttpHeaders, name: c_str, value: c_str) void {
        http_headers_set_normal(self, name, value);
    }
};

extern "C" fn response_new() callconv(.C) *Response;
extern "C" fn response_set_code(res: *Response, code: HttpCode) callconv(.C) void;
extern "C" fn response_headers(res: *Response) callconv(.C) *HttpHeaders;
extern "C" fn response_set_drop(res: *Response) callconv(.C) void;
extern "C" fn response_set_payload(res: *Response, r_ptr: [*]const u8, size: usize) callconv(.C) void;
extern "C" fn response_drop(res: *Response) callconv(.C) void;

pub const Response = opaque {
    pub inline fn init() *Response {
        return response_new();
    }

    pub inline fn setCode(self: *Response, code: HttpCode) void {
        return response_set_code(self, code);
    }

    pub inline fn headers(self: *Response) *HttpHeaders {
        return response_headers(self);
    }

    pub inline fn setDrop(self: *Response) void {
        response_set_drop(self);
    }

    pub inline fn setPayload(self: *Response, r_payload: []const u8) void {
        response_set_payload(self, r_payload.ptr, r_payload.len);
    }

    pub inline fn deinit(self: *Response) void {
        response_drop(self);
    }
};
