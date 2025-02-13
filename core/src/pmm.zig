const std = @import("std");
const easyboot = @cImport(@cInclude("easyboot.h"));
const platform = @import("arch/platform.zig").arch;
const mmap = @import("mmap.zig");
const bmap = @import("lib/bitmap.zig");

const FrameAllocatorError = error{
    InvalidMemoryMap,
    MemoryAlreadyInUse,
    MemoryNotInUse,
    OutOfMemory,
};

pub const FrameAllocator = struct {
    bitmap: bmap.Bitmap,
    free_memory: u64,
    used_memory: u64,
    reserved_memory: u64,
    start_index: usize,
};

pub const PhysFrame = struct {
    address: usize,

    pub fn virtualAddress(self: *const PhysFrame, base: usize) usize {
        return base + self.address;
    }
};

pub fn lockFrame(allocator: *FrameAllocator, address: usize) !void {
    const index = address / platform.PAGE_SIZE;
    if (try allocator.bitmap.get(index) == 1) return error.MemoryAlreadyInUse;
    try allocator.bitmap.set(index, 1);
    allocator.used_memory += platform.PAGE_SIZE;
    allocator.free_memory -= platform.PAGE_SIZE;
}

pub fn lockFrames(allocator: *FrameAllocator, address: usize, pages: usize) !void {
    var index: usize = 0;
    while (index < pages) : (index += 1) {
        try lockFrame(allocator, address + (index * platform.PAGE_SIZE));
    }
}

pub fn freeFrame(allocator: *FrameAllocator, address: usize) !void {
    const index = address / platform.PAGE_SIZE;
    if (try allocator.bitmap.get(index) == 0) return error.MemoryNotInUse;
    try allocator.bitmap.set(index, 0);
    allocator.used_memory -= platform.PAGE_SIZE;
    allocator.free_memory += platform.PAGE_SIZE;

    if (allocator.start_index > index) allocator.start_index = index;
}

pub fn freeFrames(allocator: *FrameAllocator, address: usize, pages: usize) !void {
    const index: usize = 0;
    while (index < pages) : (index += 1) {
        try freeFrame(allocator, address + (index * platform.PAGE_SIZE));
    }
}

pub fn allocFrame(allocator: *FrameAllocator) !PhysFrame {
    const index: usize = try bmap.findInBitmap(&allocator.bitmap, 0, allocator.start_index) orelse return error.OutOfMemory;
    const address = index * platform.PAGE_SIZE;
    try lockFrame(allocator, address);

    allocator.start_index = index + 1;

    return PhysFrame{ .address = address };
}

pub fn initializeFrameAllocator(tag: *easyboot.multiboot_tag_mmap_t) !FrameAllocator {
    const largest_free = mmap.findLargestFreeEntry(tag) orelse return error.InvalidMemoryMap;
    const physical_address_space_size = mmap.getAddressSpaceSize(tag) orelse return error.InvalidMemoryMap;

    const bitmap_base_address: [*]u8 = @ptrFromInt(largest_free.base_addr);

    const bitmap_bit_size = physical_address_space_size / @as(usize, platform.PAGE_SIZE);
    const bitmap_size: usize = try std.math.divCeil(usize, bitmap_bit_size, 8);

    var allocator: FrameAllocator = FrameAllocator{ .bitmap = bmap.createBitmap(bitmap_base_address, bitmap_size), .free_memory = 0, .used_memory = 0, .reserved_memory = 0, .start_index = 0 };

    allocator.bitmap.clear(1); // Set all pages to used/reserved by default, then clear out the free ones

    var iter = mmap.createMemoryMapIterator(tag);
    while (iter.next()) |entry| {
        const index = entry.base_addr / platform.PAGE_SIZE;
        const pages = entry.length / platform.PAGE_SIZE;

        if (entry.type != easyboot.MULTIBOOT_MEMORY_AVAILABLE) {
            allocator.reserved_memory += entry.length;
            continue;
        }

        allocator.free_memory += entry.length;
        try bmap.updateBitmapRegion(&allocator.bitmap, index, pages, 0);
    }

    const frames_to_lock = try std.math.divCeil(usize, bitmap_size, platform.PAGE_SIZE);
    try lockFrames(&allocator, @intFromPtr(bitmap_base_address), frames_to_lock);

    return allocator;
}
