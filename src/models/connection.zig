const Json = @import("../json.zig").Json;
const entity = @import("entity.zig");

const common = @import("../common.zig");
const c_str = common.c_str;

extern "C" fn find_db_connection(id: c_str) ?*DatabaseConnection;
extern "C" fn db_connection_count(conn: *DatabaseConnection, model: *ModelHandle, query: *const Json) u32;
extern "C" fn db_connection_exists(conn: *DatabaseConnection, model: *ModelHandle, query: *const Json) bool;
extern "C" fn model_attach(
    db: c_str,
    model: c_str,
    init: entity.InitFn(anyopaque),
    deinit: entity.DeinitFn(anyopaque),
    setters: [*]const entity.SetterFn,
    setters_len: usize,
) callconv(.c) ?*ModelHandle;

/// Model metadata built from `models_schema` by `model_attach`
pub const ModelHandle = opaque {
    /// `setters` go in the order of the model columns
    pub inline fn attach(
        db: c_str,
        model: c_str,
        comptime T: type,
        init: entity.InitFn(T),
        deinit: entity.DeinitFn(T),
        setters: []const entity.SetterFn,
    ) ?*ModelHandle {
        return model_attach(db, model, @ptrCast(init), @ptrCast(deinit), setters.ptr, setters.len);
    }
};

pub const DatabaseConnection = opaque {
    pub inline fn find(id: c_str) ?*DatabaseConnection {
        return find_db_connection(id);
    }

    pub inline fn count(self: *DatabaseConnection, model: *ModelHandle, query: *const Json) u32 {
        return db_connection_count(self, model, query);
    }

    pub inline fn exists(self: *DatabaseConnection, model: *ModelHandle, query: *const Json) bool {
        return db_connection_exists(self, model, query);
    }
};
