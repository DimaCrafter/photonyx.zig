const std = @import("std");
const Type = std.builtin.Type;
// Possible innerParse errors: BufferUnderrun, DuplicateField, InvalidCharacter, InvalidEnumTag, InvalidNumber, LengthMismatch, MissingField, OutOfMemory, Overflow, SyntaxError, UnexpectedEndOfInput, UnexpectedToken, UnknownField, ValueTooLong

const common = @import("../common.zig");
const Slice = common.Slice;

const errors = @import("error.zig");
pub const ValidationError = errors.ValidationError;
pub const ValidationResult = errors.ValidationResult;

pub fn Range(comptime T: type, min: T, max: T) type {
    if (min > max) {
        @compileLog(min, max);
        @compileError("range min > max");
    }

    return struct {
        value: T,
        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            const value = try std.json.innerParse(T, allocator, source, options);
            if (value < min or value > max) {
                return error.Overflow;
            }

            return .{ .value = value };
        }
    };
}

extern "C" fn validation_check_email(input: Slice(u8)) callconv(.c) bool;

pub const Email = struct {
    const T = []const u8;
    value: T,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const value = try std.json.innerParse(T, allocator, source, options);
        if (!validation_check_email(Slice(u8).fromNative(value))) {
            return error.SyntaxError;
        }

        return .{ .value = value };
    }
};

/// Validates `[:0]const u8`:
/// - `min` - Minimal string length (optional = `0`)
/// - `max` - Maximal string length (optional = `0`)
pub fn String(min: usize, max: usize) type {
    const T = [:0]const u8;

    if (min != 0 and max != 0 and min > max) {
        @compileLog(min, max);
        @compileError("string length min > max");
    }

    return struct {
        value: T,
        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            const value = try std.json.innerParse(T, allocator, source, options);
            if (min != 0 and value.len < min or max != 0 and value.len > max) {
                return error.LengthMismatch;
            }

            return .{ .value = value };
        }
    };
}

pub fn parseJson(comptime T: type, raw: []const u8) ValidationResult(std.json.Parsed(T)) {
    var scanner_diag = std.json.Diagnostics{};
    var scanner = std.json.Scanner.initCompleteInput(common.ra, raw);
    scanner.enableDiagnostics(&scanner_diag);
    defer scanner.deinit();

    const parsed = std.json.parseFromTokenSource(T, common.ra, &scanner, .{}) catch |err| {
        // todo: add failed path diagnostics when available
        if (std.fmt.allocPrintSentinel(common.ra, "Failed to parse JSON: {} at {}:{}", .{ err, scanner_diag.getLine(), scanner_diag.getColumn() }, 0)) |message| {
            // string will be copied in ValidationError.init
            // todo? owning in zig to allow passing values without copying?
            defer common.ra.free(message);

            return .{ .err = ValidationError.init(message) };
        } else |_| {
            return .{ .err = ValidationError.init("Failed to parse JSON") };
        }
    };

    return .{ .ok = parsed };
}
