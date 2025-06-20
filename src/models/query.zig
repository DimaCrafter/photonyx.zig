const Json = @import("../json.zig").Json;
const DatabaseConnection = @import("connection.zig").DatabaseConnection;
const ModelMeta = @import("meta.zig").ModelMeta;

const common = @import("../common.zig");
const EntityList = common.EntityList;
const AnyEntityList = common.AnyEntityList;

extern "C" fn db_connection_new_query(conn: *const DatabaseConnection, model: *const ModelMeta) callconv(.C) *anyopaque;
extern "C" fn query_builder_select(query: *anyopaque, projection: *const []const []const u8) callconv(.C) void;
extern "C" fn query_builder_where(query: *anyopaque, conditions: *const Json) callconv(.C) void;
extern "C" fn query_builder_debug(query: *anyopaque) callconv(.C) void;
extern "C" fn db_connection_exec_first(conn: *const DatabaseConnection, model: *const ModelMeta, query: *anyopaque) callconv(.C) ?*anyopaque;
extern "C" fn db_connection_exec_all(conn: *const DatabaseConnection, model: *const ModelMeta, query: *anyopaque) callconv(.C) *AnyEntityList;

pub fn QueryBuilder(comptime T: type) type {
    return struct {
        ptr: *anyopaque,
        conn: *DatabaseConnection,
        model: *ModelMeta,

        const Self = @This();

        pub inline fn init(conn: *DatabaseConnection, model: *ModelMeta) Self {
            return .{
                .ptr = @ptrCast(db_connection_new_query(conn, model)),
                .conn = conn,
                .model = model,
            };
        }

        pub inline fn select(self: Self, projection: []const []const u8) Self {
            query_builder_select(self.ptr, &projection);
            return self;
        }

        pub inline fn where(self: Self, conditions: anytype) Self {
            var conditions_json = Json.from_or_ref(conditions);
            defer conditions_json.deinit();

            query_builder_where(self.ptr, conditions_json.borrow());
            return self;
        }

        pub inline fn debug(self: Self) Self {
            query_builder_debug(self.ptr);
            return self;
        }

        pub inline fn first(self: Self) ?*T {
            if (db_connection_exec_first(self.conn, self.model, self.ptr)) |value| {
                return @ptrCast(@alignCast(value));
            } else {
                return null;
            }
        }

        pub inline fn all(self: Self) *EntityList(T) {
            return db_connection_exec_all(self.conn, self.model, self.ptr).cast(T);
        }
    };
}
