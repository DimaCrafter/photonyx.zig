const Json = @import("../json.zig").Json;
const connection = @import("connection.zig");
const DatabaseConnection = connection.DatabaseConnection;
const ModelHandle = connection.ModelHandle;

const common = @import("../common.zig");
const EntityList = common.EntityList;
const AnyEntityList = common.AnyEntityList;

extern "C" fn db_connection_new_query(conn: *const DatabaseConnection, model: *const ModelHandle) callconv(.c) *anyopaque;
extern "C" fn query_builder_select(query: *anyopaque, projection: *const []const []const u8) callconv(.c) void;
extern "C" fn query_builder_where(query: *anyopaque, conditions: *const Json) callconv(.c) void;
extern "C" fn query_builder_limit(query: *anyopaque, offset: u32, length: u32) callconv(.c) void;
extern "C" fn query_builder_debug(query: *anyopaque) callconv(.c) void;
extern "C" fn query_builder_deinit(query: *anyopaque) callconv(.c) void;
extern "C" fn db_connection_exec_first(conn: *const DatabaseConnection, model: *const ModelHandle, query: *anyopaque) callconv(.c) ?*anyopaque;
extern "C" fn db_connection_exec_all(conn: *const DatabaseConnection, model: *const ModelHandle, query: *anyopaque) callconv(.c) *AnyEntityList;

pub fn Query(comptime T: type, comptime W: type) type {
    return struct {
        ptr: *anyopaque,
        conn: *DatabaseConnection,
        model: *ModelHandle,
        /// Convert `W` to conditions JSON
        conditions_json: *const fn (W) *Json,

        const Self = @This();

        pub fn init(conn: *DatabaseConnection, model: *ModelHandle, conditions_json: *const fn (W) *Json) Self {
            return .{
                .ptr = db_connection_new_query(conn, model),
                .conn = conn,
                .model = model,
                .conditions_json = conditions_json,
            };
        }

        /// Select column names. Unselected fields get their default values.
        pub fn selectColumns(self: Self, columns: []const []const u8) Self {
            query_builder_select(self.ptr, &columns);
            return self;
        }

        /// Repeated calls are combined with `AND`
        pub fn where(self: Self, conditions: W) Self {
            const json = self.conditions_json(conditions);
            defer json.deinit();

            query_builder_where(self.ptr, json);
            return self;
        }

        pub fn limit(self: Self, offset: u32, length: u32) Self {
            query_builder_limit(self.ptr, offset, length);
            return self;
        }

        pub fn debug(self: Self) Self {
            query_builder_debug(self.ptr);
            return self;
        }

        pub fn deinit(self: Self) void {
            query_builder_deinit(self.ptr);
        }

        /// Free the result with `deinit()`
        pub fn first(self: Self) ?*T {
            if (db_connection_exec_first(self.conn, self.model, self.ptr)) |value| {
                return @ptrCast(@alignCast(value));
            } else {
                return null;
            }
        }

        /// Free the result with `deinit()` (it frees the entities too)
        pub fn all(self: Self) *EntityList(T) {
            return db_connection_exec_all(self.conn, self.model, self.ptr).cast(T);
        }
    };
}
