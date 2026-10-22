const std = @import("std");
const meta = @import("../meta.zig");
const Json = @import("../json.zig").Json;
pub const DatabaseConnection = @import("connection.zig").DatabaseConnection;
const QueryBuilder = @import("query.zig").QueryBuilder;
const ModelMeta = @import("meta.zig").ModelMeta;

const common = @import("../common.zig");
const c_str = common.c_str;
const Slice = common.Slice;
const AnySlice = common.AnySlice;

const entity = @import("entity.zig");
pub const Self = entity.Self;
pub const Link = entity.Link;
pub const sql = entity.sql;

const datetime = @import("../datetime.zig");
pub const DateTime = datetime.DateTime;
pub const CURRENT_DATE = datetime.CURRENT_DATE;

const ModelAttr = struct { *DatabaseConnection, *ModelMeta };

pub fn Model(comptime _T: type, constraints: anytype) type {
    return struct {
        pub const T = _T;
        pub const _constraints = constraints;
        pub const _name = meta.getSimpleTypeName(T);

        var _conn: ?*DatabaseConnection = null;
        var _meta: ?*ModelMeta = null;

        pub fn initEntity() callconv(.c) ?*T {
            if (common.ra.create(T)) |ptr| {
                return ptr;
            } else |_| {
                return null;
            }
        }

        pub fn deinitEntity(ptr: *T) callconv(.c) void {
            const struct_meta = @typeInfo(T).@"struct";

            inline for (struct_meta.field_names) |field_name| {
                const F = @FieldType(T, field_name);
                switch (F) {
                    []const u8 => {
                        common.ra.free(@field(ptr, field_name));
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
                model_meta.addFieldsFrom(@This());

                if (@hasField(@TypeOf(constraints._chained), "$unique")) {
                    inline for (constraints._chained.@"$unique") |key| {
                        model_meta.addUniqueKey(&key);
                    }
                }

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

        pub fn _getConstraints() if (@hasField(@TypeOf(constraints), "_chained")) @TypeOf(constraints._chained) else @TypeOf(constraints) {
            if (@hasField(@TypeOf(constraints), "_chained")) {
                return constraints._chained;
            } else {
                return constraints;
            }
        }

        pub fn _findPrimaryKey() ?[:0]const u8 {
            const resolved_constraints = _getConstraints();
            const constraints_meta = @typeInfo(@TypeOf(resolved_constraints)).@"struct";

            inline for (constraints_meta.field_names) |field_name| {
                inline for (@field(resolved_constraints, field_name)) |constraint| {
                    if (constraint == sql.PrimaryKey) {
                        return field_name;
                    }
                }
            }

            return null;
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

        pub fn autoMigrate() void {
            const conn, const model_meta = getConnection();
            conn.autoMigrate(model_meta);
        }

        pub fn count(query: anytype) u32 {
            const conn, const model_meta = getConnection();

            const jsonQuery = Json.from_or_ref(query);
            defer jsonQuery.deinit();

            return conn.count(model_meta, jsonQuery.borrow());
        }

        pub fn exists(query: anytype) bool {
            const conn, const model_meta = getConnection();

            const jsonQuery = Json.from_or_ref(query);
            defer jsonQuery.deinit();

            return conn.exists(model_meta, jsonQuery.borrow());
        }

        pub inline fn select(projection: []const []const u8) QueryBuilder(T) {
            const conn, const model = getConnection();
            return QueryBuilder(T).init(conn, model).select(projection);
        }
    };
}

pub inline fn boundModel(comptime M: type, connId: c_str) type {
    return Model(M.T, .{ ._chained = M._constraints, ._connId = connId });
}

// Source - https://stackoverflow.com/a/4106962
// Posted by Loïc Février, modified by community. See post 'Timeline' for change history
// Retrieved 2026-04-13, License - CC BY-SA 4.0
pub fn topoSort(comptime models: anytype) [(@typeInfo(@TypeOf(models)).@"struct".fields.len)]type {
    const N = @typeInfo(@TypeOf(models)).@"struct".fields.len;

    // adj[j][i] = true  →  model i depends on model j (j must come before i)
    comptime var adj: [N][N]bool = @splat(@splat(false));
    comptime var in_degree: [N]usize = @splat(0);

    // Build dependency graph: for every Link in model i's constraints,
    // find the index j of the referenced model and add edge j → i.
    inline for (0..N) |i| {
        const M = models[i];
        const constraints = M._getConstraints();
        inline for (@typeInfo(@TypeOf(constraints)).@"struct".fields) |field_info| {
            inline for (@field(constraints, field_info.name)) |constraint| {
                if (@TypeOf(constraint) == Link) {
                    inline for (0..N) |j| {
                        if (models[j] == constraint.model and i != j and !adj[j][i]) {
                            adj[j][i] = true;
                            in_degree[i] += 1;
                        }
                    }
                }
            }
        }
    }

    comptime var result: [N]type = undefined;

    // L ← empty list, S ← nodes with no incoming edge
    comptime {
        var result_len: usize = 0;
        var queue: [N]usize = undefined;
        var q_head: usize = 0;
        var q_tail: usize = 0;

        for (0..N) |i| {
            if (in_degree[i] == 0) {
                queue[q_tail] = i;
                q_tail += 1;
            }
        }

        while (q_head < q_tail) {
            const n = queue[q_head];
            q_head += 1;
            result[result_len] = models[n];
            result_len += 1;

            for (0..N) |m| {
                if (adj[n][m]) {
                    in_degree[m] -= 1;
                    if (in_degree[m] == 0) {
                        queue[q_tail] = m;
                        q_tail += 1;
                    }
                }
            }
        }

        if (result_len != N) {
            @compileError("Cycle detected in model dependencies");
        }
    }

    return result;
}

pub fn autoMigrate(comptime models: anytype) void {
    const sorted = topoSort(models);
    inline for (sorted) |M| {
        M.autoMigrate();
    }
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
