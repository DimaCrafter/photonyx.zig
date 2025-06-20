const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

extern "C" fn rs_alloc(size: usize, alignment: usize) callconv(.C) ?[*]u8;
extern "C" fn rs_realloc(ptr: [*]u8, old_size: usize, new_size: usize, alignment: usize) callconv(.C) ?[*]u8;
extern "C" fn rs_dealloc(ptr: [*]u8, size: usize, alignment: usize) callconv(.C) void;

const RAllocator = struct {
    const vtable: Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn alloc(_: *anyopaque, size: usize, alignment: Alignment, _: usize) ?[*]u8 {
        return rs_alloc(size, alignment.toByteUnits());
    }

    fn resize(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) bool {
        return false;
    }

    fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_size: usize, _: usize) ?[*]u8 {
        return rs_realloc(memory.ptr, memory.len, new_size, alignment.toByteUnits());
    }

    fn free(_: *anyopaque, memory: []u8, alignment: Alignment, _: usize) void {
        rs_dealloc(memory.ptr, memory.len, alignment.toByteUnits());
    }
};

pub const ra: Allocator = .{
    .ptr = undefined,
    .vtable = &RAllocator.vtable,
};

pub const c_str = [*:0]const u8;
extern "C" fn str_drop(ptr: c_str) callconv(.C) void;

pub inline fn strDeinit(str: c_str) void {
    str_drop(str);
}

pub const AnySlice = extern struct {
    ptr: *const anyopaque,
    len: usize,

    pub fn cast(self: AnySlice, comptime R: type) Slice(R) {
        return .{ .ptr = @ptrCast(@alignCast(self.ptr)), .len = self.len };
    }
};

pub fn Slice(comptime T: type) type {
    return extern struct {
        const Self = @This();

        ptr: [*]const T,
        len: usize,

        pub fn fromNative(native: []const T) Self {
            return .{ .ptr = native.ptr, .len = native.len };
        }

        pub fn cast(self: Self, comptime R: type) Slice(R) {
            return .{ .ptr = @ptrCast(self.ptr), .len = self.len };
        }

        pub fn intoNative(self: Self) []const T {
            return self.ptr[0..self.len];
        }
    };
}

pub const AnyEntityList = opaque {
    pub inline fn cast(self: *AnyEntityList, comptime R: type) *EntityList(R) {
        return @ptrCast(self);
    }
};

extern "C" fn entity_list_get_items(vec: *AnyEntityList) callconv(.C) AnySlice;
extern "C" fn entity_list_deinit(vec: *AnyEntityList) callconv(.C) void;

pub fn EntityList(comptime T: type) type {
    return opaque {
        const Self = @This();

        pub inline fn items(self: *Self) []const *T {
            return entity_list_get_items(self.downcast()).cast(*T).intoNative();
        }

        pub inline fn downcast(self: *Self) *AnyEntityList {
            return @ptrCast(self);
        }

        pub inline fn deinit(self: *Self) void {
            entity_list_deinit(self.downcast());
        }
    };
}

/// Provides unified instance management, so you can `move` or `deinit` it unconditionally.
/// If inner value is owned by Zig, it will be `deinit`ed automatically.
/// If inner value is borrowed (referenced) it will be `deinit`ed by the owner.
pub fn Shared(comptime T: type) type {
    return extern struct {
        const Self = @This();
        value: T,
        owned: bool,

        pub fn from_borrowed(value: T) Self {
            return .{ .value = value, .owned = false };
        }

        pub fn from_owned(value: T) Self {
            return .{ .value = value, .owned = true };
        }

        /// Make owned value be managed by a receiver.
        /// After this stored value becomes borrowed for the caller.
        pub fn move(self: *Self) T {
            self.owned = false;
            return self.value;
        }

        pub fn borrow(self: *const Self) T {
            return self.value;
        }

        pub fn deinit(self: Self) void {
            if (self.owned) {
                self.value.deinit();
            }
        }
    };
}
