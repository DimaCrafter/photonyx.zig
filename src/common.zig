const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

pub const c_str = [*:0]const u8;

extern fn rs_alloc(size: usize, alignment: usize) callconv(.C) ?[*]u8;
extern fn rs_realloc(ptr: [*]u8, old_size: usize, new_size: usize, alignment: usize) callconv(.C) ?[*]u8;
extern fn rs_dealloc(ptr: [*]u8, size: usize, alignment: usize) callconv(.C) void;

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
