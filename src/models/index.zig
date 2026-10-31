const std = @import("std");
const Json = @import("../json.zig").Json;

const connection = @import("connection.zig");
pub const DatabaseConnection = connection.DatabaseConnection;
pub const ModelHandle = connection.ModelHandle;

pub const Query = @import("query.zig").Query;

const entity = @import("entity.zig");

const common = @import("../common.zig");
const c_str = common.c_str;

const datetime = @import("../datetime.zig");
pub const DateTime = datetime.DateTime;
pub const CURRENT_DATE = datetime.CURRENT_DATE;

extern "C" fn datetime_to_string(value: *const DateTime) callconv(.c) c_str;

pub const CondOp = enum { eq, neq, gt, gte, lt, lte, in, contains, is_null, not_null };

/// Condition on a field of type `T`.
/// Constructors are decl literals: `.{ .email = .eq("a@b.c"), .id = .gt(10) }`.
pub fn Cond(comptime T: type) type {
    const V = switch (@typeInfo(T)) {
        .optional => |optional_meta| optional_meta.child,
        else => T,
    };

    return struct {
        op: CondOp,
        value: T,
        values: []const V,
        text: []const u8,

        const Self = @This();

        pub fn eq(value: T) Self {
            return .{ .op = .eq, .value = value, .values = &.{}, .text = "" };
        }

        pub fn neq(value: T) Self {
            return .{ .op = .neq, .value = value, .values = &.{}, .text = "" };
        }

        pub fn gt(value: T) Self {
            return .{ .op = .gt, .value = value, .values = &.{}, .text = "" };
        }

        pub fn gte(value: T) Self {
            return .{ .op = .gte, .value = value, .values = &.{}, .text = "" };
        }

        pub fn lt(value: T) Self {
            return .{ .op = .lt, .value = value, .values = &.{}, .text = "" };
        }

        pub fn lte(value: T) Self {
            return .{ .op = .lte, .value = value, .values = &.{}, .text = "" };
        }

        pub fn in(values: []const V) Self {
            return .{ .op = .in, .value = undefined, .values = values, .text = "" };
        }

        pub fn contains(text: []const u8) Self {
            return .{ .op = .contains, .value = undefined, .values = &.{}, .text = text };
        }

        pub fn is_null(flag: bool) Self {
            return .{ .op = if (flag) .is_null else .not_null, .value = undefined, .values = &.{}, .text = "" };
        }
    };
}

pub const Column = struct {
    name: [:0]const u8,
    /// Database representation of enum values (by ordinal), when stored as a string
    enum_db: ?[]const []const u8 = null,
    /// Database representation of enum values (by ordinal), when stored as a number
    enum_int: ?[]const i64 = null,
};

pub const TableOptions = struct {
    db: [:0]const u8,
    model: [:0]const u8,
    columns: []const Column,
};

/// `W` and `F` are separate parameters because ZLS has limited depth
pub fn Table(comptime T: type, comptime W: type, comptime F: type, comptime options: TableOptions) type {
    comptime {
        const fields_len = @typeInfo(T).@"struct".field_names.len;
        if (fields_len != options.columns.len or @typeInfo(W).@"struct".field_names.len != fields_len) {
            @compileError("Model " ++ options.model ++ ": fields, Where and columns do not match");
        }
    }

    return struct {
        var handle: ?*ModelHandle = null;
        var default_conn: ?*DatabaseConnection = null;

        /// Connection given by name at runtime like `User.on("main_replica")`
        pub const Bound = struct {
            conn: *DatabaseConnection,
            model: *ModelHandle,

            pub fn where(self: Bound, conditions: W) Query(T, W) {
                return Query(T, W).init(self.conn, self.model, conditionsJson).where(conditions);
            }

            pub fn select(self: Bound, fields: []const F) Query(T, W) {
                const query = Query(T, W).init(self.conn, self.model, conditionsJson);

                var names: [options.columns.len][]const u8 = undefined;
                for (fields, 0..) |field, i| {
                    names[i] = column_names[@backingInt(field)];
                }

                return query.selectColumns(names[0..fields.len]);
            }

            pub fn count(self: Bound, conditions: W) u32 {
                const json = conditionsJson(conditions);
                defer json.deinit();

                return self.conn.count(self.model, json);
            }

            pub fn exists(self: Bound, conditions: W) bool {
                const json = conditionsJson(conditions);
                defer json.deinit();

                return self.conn.exists(self.model, json);
            }
        };

        const column_names = blk: {
            var names: [options.columns.len][]const u8 = undefined;
            for (options.columns, 0..) |column, i| {
                names[i] = column.name;
            }

            const result = names;
            break :blk result;
        };

        /// Frees an entity from `first()` (generated `T.deinit`)
        pub const deinitEntity = entity.deinitEntity(T);

        pub fn attach() void {
            const setters = comptime entity.get_setters(T);
            handle = ModelHandle.attach(options.db, options.model, T, entity.initEntity(T), entity.deinitEntity(T), &setters) orelse {
                // the reason is logged by photonyx
                std.process.exit(0xFE);
            };

            default_conn = DatabaseConnection.find(options.db) orelse {
                std.log.err("Model " ++ options.model ++ " is bound to missing connection '" ++ options.db ++ "'", .{});
                std.process.exit(0xFE);
            };
        }

        fn bound() Bound {
            if (handle) |model| {
                if (default_conn) |conn| {
                    return .{ .conn = conn, .model = model };
                }
            }

            std.log.err("Model " ++ options.model ++ " was used before provide_models", .{});
            std.process.exit(0xFE);
        }

        pub fn where(conditions: W) Query(T, W) {
            return bound().where(conditions);
        }

        pub fn select(fields: []const F) Query(T, W) {
            return bound().select(fields);
        }

        pub fn count(conditions: W) u32 {
            return bound().count(conditions);
        }

        pub fn exists(conditions: W) bool {
            return bound().exists(conditions);
        }

        pub fn on(conn_name: [:0]const u8) Bound {
            const model = bound().model;
            const conn = DatabaseConnection.find(conn_name) orelse {
                std.log.err("Model " ++ options.model ++ ": connection '{s}' not found", .{conn_name});
                std.process.exit(0xFE);
            };

            return .{ .conn = conn, .model = model };
        }

        fn conditionsJson(conditions: W) *Json {
            const obj = Json.init_object();
            const where_meta = @typeInfo(W).@"struct";

            inline for (where_meta.field_names, 0..) |field_name, i| {
                if (@field(conditions, field_name)) |cond| {
                    _ = obj.set(options.columns[i].name, condJson(@TypeOf(cond.value), cond, options.columns[i]));
                }
            }

            return obj;
        }
    };
}

fn condJson(comptime V: type, cond: Cond(V), comptime column: Column) *Json {
    const op_key: ?[:0]const u8 = switch (cond.op) {
        .eq, .is_null => null,
        .neq, .not_null => "$neq",
        .gt => "$gt",
        .gte => "$gte",
        .lt => "$lt",
        .lte => "$lte",
        .in => "$in",
        .contains => "$contains",
    };

    const value = switch (cond.op) {
        .is_null, .not_null => Json.init_null(),
        .in => blk: {
            const list = Json.init_array();
            for (cond.values) |item| {
                _ = list.push(valueJson(@TypeOf(item), item, column));
            }

            break :blk list;
        },
        .contains => Json.from(cond.text),
        else => valueJson(V, cond.value, column),
    };

    if (op_key) |key| {
        const obj = Json.init_object();
        _ = obj.set(key, value);
        return obj;
    }

    return value;
}

fn valueJson(comptime V: type, value: V, comptime column: Column) *Json {
    switch (@typeInfo(V)) {
        .optional => {
            if (value) |inner| {
                return valueJson(@TypeOf(inner), inner, column);
            }

            return Json.init_null();
        },
        .@"enum" => {
            const ordinal = @backingInt(value);
            if (column.enum_int) |ints| {
                return Json.init_number(@floatFromInt(ints[ordinal]));
            }

            if (column.enum_db) |names| {
                return Json.from(names[ordinal]);
            }

            return Json.from(@tagName(value));
        },
        else => {},
    }

    if (V == *DateTime) {
        const raw = datetime_to_string(value);
        defer common.strDeinit(raw);

        return Json.init_str(raw);
    }

    return Json.from(value);
}
