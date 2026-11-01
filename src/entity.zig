const std = @import("std");

const validator = @import("./validator/index.zig");

const common = @import("./common.zig");
const c_str = common.c_str;
const Slice = common.Slice;

const HttpCode = @import("./codes.zig").HttpCode;
const Json = @import("./json.zig").Json;
const Session = @import("./session.zig").Session;
const sse = @import("./sse.zig");

extern "C" fn http_context_set_response(ctx: *HttpContext, res: *Response) callconv(.c) void;
extern "C" fn http_context_get_body_ref(ctx: *const HttpContext) callconv(.c) Slice(u8);
extern "C" fn http_context_get_meta_ref(ctx: *const HttpContext) callconv(.c) ?*HttpContextMeta;
extern "C" fn http_context_set_meta_ref(ctx: *HttpContext, ptr: ?*HttpContextMeta) callconv(.c) void;
extern "C" fn http_context_get_request(ctx: *HttpContext) callconv(.c) *Request;
extern "C" fn http_context_get_response(ctx: *HttpContext) callconv(.c) *Response;
extern "C" fn http_context_get_session(ctx: *HttpContext) callconv(.c) *Session;
extern "C" fn http_context_get_address(ctx: *HttpContext) callconv(.c) Slice(u8);
extern "C" fn http_context_get_method(ctx: *const HttpContext) callconv(.c) HttpMethod;
extern "C" fn http_context_stream_begin(ctx: *HttpContext) callconv(.c) bool;
extern "C" fn http_context_stream_write(ctx: *HttpContext, ptr: [*]const u8, size: usize) callconv(.c) bool;

pub const HttpMethod = enum(u8) { GET, POST, OPTIONS };

pub const HttpContext = opaque {
    pub fn getMeta(self: *HttpContext) *HttpContextMeta {
        if (http_context_get_meta_ref(self)) |meta| {
            return meta;
        }

        const meta = common.ra.create(HttpContextMeta) catch |err| {
            // todo: report out of memory and exit
            std.debug.print("Out of memory ({})", .{err});
            std.process.exit(0xFF);
        };

        meta.* = HttpContextMeta{};
        http_context_set_meta_ref(self, meta);

        return meta;
    }

    pub inline fn getBodyRef(self: *const HttpContext) []const u8 {
        return http_context_get_body_ref(self).intoNative();
    }

    pub fn validate(self: *HttpContext, comptime T: type) !T {
        const raw = self.getBodyRef();

        switch (validator.parseJson(T, raw)) {
            .err => |err| {
                const json = err.intoJson();
                defer json.deinit();

                self.send(.{ .code = HttpCode.BadRequest, .json = json });
                return error.ValidationError;
            },
            .ok => |parsed| {
                const meta = self.getMeta();
                meta.parsedBodyArena = parsed.arena;

                return parsed.value;
            },
        }
    }

    pub inline fn getHeader(self: *HttpContext, name: []const u8) ?[]const u8 {
        const req = http_context_get_request(self);
        return req.headers().get(name);
    }

    pub inline fn setHeader(self: *HttpContext, name: c_str, value: c_str) void {
        const res = http_context_get_response(self);
        res.headers().set(name, value);
    }

    pub inline fn session(self: *HttpContext) *Session {
        return http_context_get_session(self);
    }

    /// Address of the peer in text form, valid until the handler returns
    pub inline fn address(self: *HttpContext) []const u8 {
        return http_context_get_address(self).intoNative();
    }

    pub inline fn method(self: *const HttpContext) HttpMethod {
        return http_context_get_method(self);
    }

    pub fn stream(self: *HttpContext, code: HttpCode) error{ClientGone}!ResponseStream {
        http_context_get_response(self).setCode(code);

        if (!http_context_stream_begin(self)) {
            return error.ClientGone;
        }

        return .{ .ctx = self };
    }

    pub fn sse(self: *HttpContext) error{ClientGone}!SseStream {
        self.setHeader("content-type", "text/event-stream");
        self.setHeader("cache-control", "no-cache");

        return .{ .stream = try self.stream(HttpCode.OK) };
    }

    /// - resSchema.code: `HttpCode`
    /// - resSchema.json: `*Json` or `anytype`
    /// - resSchema.bytes: `[]const u8`, copied
    /// - resSchema.raw: `[]const u8`, must be allocated with `p.ra`, Photonyx takes ownership
    pub fn send(self: *HttpContext, resSchema: anytype) void {
        const S = @TypeOf(resSchema);
        const res = http_context_get_response(self);

        if (@hasField(S, "json")) {
            const json = Json.from_or_ref(@field(resSchema, "json"));
            defer json.deinit();

            const msg = json.borrow().dump();
            defer common.strDeinit(msg);

            res.setPayloadCopy(msg[0..std.mem.len(msg)]);
            res.headers().setDefault("content-type", "application/json");
        }

        if (@hasField(S, "bytes")) {
            res.setPayloadCopy(@field(resSchema, "bytes"));
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

pub const ResponseStream = struct {
    ctx: *HttpContext,

    pub fn write(self: ResponseStream, chunk: []const u8) error{ClientGone}!void {
        if (!http_context_stream_write(self.ctx, chunk.ptr, chunk.len)) {
            return error.ClientGone;
        }
    }
};

pub const SseStream = struct {
    stream: ResponseStream,

    /// `data` can contain line breaks
    pub fn event(self: SseStream, name: []const u8, data: []const u8) error{ ClientGone, OutOfMemory }!void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(common.ra);

        try sse.appendEvent(&out, common.ra, name, data);
        try self.stream.write(out.items);
    }

    /// Clients ignore comments. Send one periodically during silence to notice a gone client
    pub fn comment(self: SseStream, text: []const u8) error{ ClientGone, OutOfMemory }!void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(common.ra);

        try sse.appendComment(&out, common.ra, text);
        try self.stream.write(out.items);
    }
};

const HttpContextMeta = struct {
    parsedBodyArena: ?*std.heap.ArenaAllocator = null,

    pub fn deinit(self: *HttpContextMeta) void {
        // ref: json.Parsed(T)
        if (self.parsedBodyArena) |arena| {
            const allocator = arena.child_allocator;
            arena.deinit();
            allocator.destroy(arena);
        }

        common.ra.destroy(self);
    }
};

const HeaderValue = extern struct { ptr: ?[*]const u8, len: usize };

extern "C" fn http_headers_get(headers: *const HttpHeaders, name: Slice(u8)) callconv(.c) HeaderValue;
extern "C" fn http_headers_set(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.c) void;
extern "C" fn http_headers_set_default(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.c) void;
extern "C" fn http_headers_set_normal(headers: *HttpHeaders, name: c_str, value: c_str) callconv(.c) void;

pub const HttpHeaders = opaque {
    pub inline fn get(self: *const HttpHeaders, name: []const u8) ?[]const u8 {
        const value = http_headers_get(self, Slice(u8).fromNative(name));
        return if (value.ptr) |ptr| ptr[0..value.len] else null;
    }

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

extern "C" fn response_new() callconv(.c) *Response;
extern "C" fn response_set_code(res: *Response, code: HttpCode) callconv(.c) void;
extern "C" fn response_headers(res: *Response) callconv(.c) *HttpHeaders;
extern "C" fn response_set_drop(res: *Response) callconv(.c) void;
extern "C" fn response_set_payload(res: *Response, r_ptr: [*]const u8, size: usize) callconv(.c) void;
extern "C" fn response_set_payload_copy(res: *Response, ptr: [*]const u8, size: usize) callconv(.c) void;
extern "C" fn response_drop(res: *Response) callconv(.c) void;

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

    /// Set raw response body. Passed slice must be allocated with `p.ra`,
    /// and it will be `deinit`ed by Photonyx.
    pub inline fn setPayload(self: *Response, r_payload: []const u8) void {
        response_set_payload(self, r_payload.ptr, r_payload.len);
    }

    /// Set response body to a copy of `payload`
    pub inline fn setPayloadCopy(self: *Response, payload: []const u8) void {
        response_set_payload_copy(self, payload.ptr, payload.len);
    }

    pub inline fn deinit(self: *Response) void {
        response_drop(self);
    }
};

extern "C" fn request_headers(res: *const Request) callconv(.c) *const HttpHeaders;

pub const Request = opaque {
    pub inline fn headers(self: *const Request) *const HttpHeaders {
        return request_headers(self);
    }
};
