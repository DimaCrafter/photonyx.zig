const entity = @import("entity.zig");
const ModelMeta = @import("meta.zig").ModelMeta;
const Json = @import("../json.zig").Json;

const common = @import("../common.zig");
const c_str = common.c_str;

extern "C" fn find_db_connection(id: c_str) ?*DatabaseConnection;
extern "C" fn db_connection_count(conn: *DatabaseConnection, query: *const Json) u32;
extern "C" fn db_connection_prepare_model(conn: *DatabaseConnection, name: c_str, init: entity.InitFn(void), deinit: entity.DeinitFn(void)) callconv(.C) *ModelMeta;

pub const DatabaseConnection = opaque {
    pub inline fn find(id: c_str) ?*DatabaseConnection {
        return find_db_connection(id);
    }

    pub inline fn prepareModel(self: *DatabaseConnection, comptime T: type, name: c_str, init: entity.InitFn(T), deinit: entity.DeinitFn(T)) *ModelMeta {
        return db_connection_prepare_model(self, name, @ptrCast(init), @ptrCast(deinit));
    }

    pub inline fn count(self: *DatabaseConnection, query: *const Json) u32 {
        return db_connection_count(self, query);
    }
};
