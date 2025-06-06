const common = @import("./common.zig");
const c_str = common.c_str;

const HttpCode = @import("./codes.zig").HttpCode;

pub const HttpContext = opaque {};

extern fn http_headers_set(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.C) void;
extern fn http_headers_set_default(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.C) void;
extern fn http_headers_set_normal(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.C) void;

pub const HttpHeaders = opaque {
    pub inline fn set(self: *HttpHeaders, name: c_str, value: c_str) void {
        http_headers_set(self, name, value);
    }

    pub inline fn set_default(self: *HttpHeaders, name: c_str, value: c_str) void {
        http_headers_set_default(self, name, value);
    }

    pub inline fn set_normal(self: *HttpHeaders, name: c_str, value: c_str) void {
        http_headers_set_normal(self, name, value);
    }
};

extern fn response_new() callconv(.C) *Response;
extern fn response_set_code(res: *Response, code: HttpCode) callconv(.C) void;
extern fn response_headers(res: *Response) callconv(.C) *HttpHeaders;
extern fn response_set_drop(res: *Response) callconv(.C) void;
extern fn response_set_payload(res: *Response, r_ptr: [*]u8, size: usize) callconv(.C) void;
extern fn response_drop(res: *Response) callconv(.C) void;

pub const Response = opaque {
    pub inline fn init() *Response {
        return response_new();
    }

    pub inline fn set_code(self: *Response, code: HttpCode) void {
        return response_set_code(self, code);
    }

    pub inline fn headers(self: *Response) *HttpHeaders {
        return response_headers(self);
    }

    pub inline fn set_drop(self: *Response) void {
        response_set_drop(self);
    }

    pub inline fn set_payload(self: *Response, r_payload: []u8) void {
        response_set_payload(self, r_payload.ptr, r_payload.len);
    }

    pub inline fn deinit(self: *Response) void {
        response_drop(self);
    }
};
