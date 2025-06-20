const std = @import("std");
const meta = @import("../meta.zig");
const Json = @import("../json.zig").Json;
const DatabaseConnection = @import("connection.zig").DatabaseConnection;
const ModelMeta = @import("meta.zig").ModelMeta;
const QueryBuilder = @import("query.zig").QueryBuilder;

const common = @import("../common.zig");
const c_str = common.c_str;
const Slice = common.Slice;
const AnySlice = common.AnySlice;

pub const sql = @import("sql/index.zig");

pub const StringArgs = struct {
    length: u32 = 0,
    optional: bool = false,
    default: ?[]const u8 = null,
};

/// Type for variable length string
pub fn String(comptime options: StringArgs) type {
    return struct { stringT: []u8, args: StringArgs = options };
}

pub const CharArgs = struct {
    length: u32,
    optional: bool = false,
    default: ?[]const u8 = null,
};

/// Type for fixed length string
pub fn Char(comptime options: CharArgs) type {
    const length: comptime_int = @field(options, "length");
    return struct { charT: [length]u8, args: CharArgs = options };
}

pub const LinkArgs = struct {
    Destination: type,
};

pub const LinkPolicy = enum {
    /// Link will be used just as key
    none,
    /// Service.user_id --> User: operation on User will be restricted if Service exist
    restrict,
    /// Service.user_id --> User: operation on User will cause some operation on Service
    cascade,
    /// Service.user_id --> User: operation on User will set Service.user_id to null
    set_null,
};

pub const Link = struct {
    model: type,
    delete: LinkPolicy = .none,
    update: LinkPolicy = .none,
};

pub const DateTimeArgs = struct {
    optional: bool = false,
    default: ?[]const u8 = null,
};

pub const DateTime = u64;
pub const CURRENT_DATE = 0;

const ModelAttr = struct { *DatabaseConnection, *ModelMeta };

pub fn Model(comptime _T: type, constraints: anytype) type {
    return struct {
        pub const T = _T;
        pub const _constraints = constraints;
        pub const _name = meta.getSimpleTypeName(T);

        var _conn: ?*DatabaseConnection = null;
        var _meta: ?*ModelMeta = null;

        fn initEntity() callconv(.C) ?*T {
            if (common.ra.create(T)) |ptr| {
                return ptr;
            } else |_| {
                return null;
            }
        }

        pub fn deinitEntity(ptr: *T) callconv(.C) void {
            inline for (@typeInfo(T).@"struct".fields) |field| {
                const F = @FieldType(T, field.name);
                switch (F) {
                    []const u8 => {
                        common.ra.free(@field(ptr, field.name));
                    },
                    else => {
                        // other types should be just values
                    },
                }
            }

            common.ra.destroy(ptr);
        }

        pub fn _register() void {
            if (_conn != null) {
                std.log.err("Trying to register already registered model " ++ _name, .{});
                return;
            }

            if (!@hasField(@TypeOf(constraints), "_connId")) {
                // todo: use photonyx logger
                std.log.err("Trying to register unbound model " ++ _name, .{});
                std.process.exit(0xFE);
            }

            if (DatabaseConnection.find(constraints._connId)) |conn| {
                const model_meta = conn.prepareModel(T, _name ++ "\x00", initEntity, deinitEntity);
                model_meta.addFieldsFrom(T);

                _conn = conn;
                _meta = model_meta;
            } else {
                std.log.err(
                    "Model " ++ _name ++ " is bound to missing connection '{s}'",
                    .{constraints._connId},
                );
                std.process.exit(0xFE);
            }
        }

        fn getConnection() ModelAttr {
            if (_conn) |conn_ptr| {
                if (_meta) |meta_ptr| {
                    return .{ conn_ptr, meta_ptr };
                }

                std.log.err("Model " ++ _name ++ " was used while it is not registered", .{});
                std.process.exit(0xFE);
            }

            std.log.err("Model " ++ _name ++ " was used while being unbound", .{});
            std.process.exit(0xFE);
        }

        pub fn count(query: anytype) u32 {
            const conn, _ = getConnection();

            const jsonQuery = Json.from_or_ref(query);
            defer jsonQuery.deinit();

            return conn.count(jsonQuery);
        }

        pub inline fn select(projection: []const []const u8) QueryBuilder(T) {
            const conn, const model = getConnection();
            return QueryBuilder(T).init(conn, model).select(projection);
        }
    };
}

pub fn boundModel(comptime M: type, connId: c_str) type {
    return Model(M.T, .{ ._chained = M._constraints, ._connId = connId });
}

/// Passed `cases` will be managed by the resulting object.
pub fn make_op(op_key: c_str, cases: anytype) *Json {
    const cInfo = @typeInfo(@TypeOf(cases));

    var cases_list = Json.init_array();
    inline for (cInfo.@"struct".fields) |field| {
        var case_stmt = Json.from_or_ref(@field(cases, field.name));
        _ = cases_list.push(case_stmt.move());
    }

    var op = Json.init_object();
    _ = op.set(op_key, cases_list);
    return op;
}

/// Passed `cases` will be managed by the resulting object.
pub fn cond_and(cases: anytype) *Json {
    return make_op("$and", cases);
}

/// Passed `cases` will be managed by the resulting object.
pub fn cond_or(cases: anytype) *Json {
    return make_op("$or", cases);
}

/// Check that value in database is greater than given
pub fn gt(value: anytype) *Json {
    return Json.from(.{ .@"$gt" = value });
}

/// Check that value in database is lower than given
pub fn lt(value: anytype) *Json {
    return Json.from(.{ .@"$lt" = value });
}

/// Check that value in database is not equal to given
pub fn neq(value: anytype) *Json {
    return Json.from(.{ .@"$neq" = value });
}

/// Check that string value in database contains given substring
pub fn contains(value: [:0]const u8) *Json {
    return Json.from(.{ .@"$contains" = value });
}
