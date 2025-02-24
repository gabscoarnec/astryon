const std = @import("std");
const easyboot = @cImport(@cInclude("easyboot.h"));
const platform = @import("arch/platform.zig");
const vmm = @import("arch/vmm.zig");
const mmap = @import("mmap.zig");
const bmap = @import("lib/bitmap.zig");
const locking = @import("lib/spinlock.zig");
const debug = @import("arch/debug.zig");
const multiboot = @import("multiboot.zig");

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

    // Avoid causing trouble.
    try lockFrame(&allocator, 0);

    try reserveKernelMemory(&allocator);

    return allocator;
}

fn adjustAddressToPageBoundary(address: *usize, size: *usize) void {
    const diff = address.* % platform.PAGE_SIZE;

    address.* -= diff;
    size.* += diff;
}

extern const kernel_start: [*]u8;
extern const kernel_end: [*]u8;

fn reserveKernelMemory(allocator: *FrameAllocator) !void {
    debug.print("Kernel begins at {*} and ends at {*}\n", .{ &kernel_start, &kernel_end });

    const start: usize = @intFromPtr(&kernel_start);
    const end: usize = @intFromPtr(&kernel_end);
    const pages = try std.math.divCeil(usize, end - start, platform.PAGE_SIZE);

    const page_table = vmm.readPageTable();
    const space = vmm.AddressSpace.create(page_table, 0);

    var i: usize = 0;
    while (i < pages) : (i += 1) {
        try lockFrame(allocator, vmm.getAddress(space, 0, start + (i * platform.PAGE_SIZE)).?);
    }
}

pub fn reserveMultibootMemory(allocator: *FrameAllocator, info: [*c]u8) !void {
    const info_tag: *easyboot.multiboot_info_t = @alignCast(@ptrCast(info));

    var address: usize = @intFromPtr(info);
    var size: usize = info_tag.total_size;
    adjustAddressToPageBoundary(&address, &size);

    debug.print("Locking multiboot memory at {x}, {d} bytes\n", .{ address, size });

    try lockFrames(allocator, address, try std.math.divCeil(usize, size, platform.PAGE_SIZE));

    const Context = struct {
        allocator: *FrameAllocator,
    };

    var ctx = Context{ .allocator = allocator };

    multiboot.findMultibootTags(easyboot.multiboot_tag_module_t, @ptrCast(info), struct {
        fn reserveMemory(mod: *easyboot.multiboot_tag_module_t, context: *const Context) !void {
            var mod_address: usize = mod.mod_start;
            var mod_size: usize = mod.mod_end - mod.mod_start;
            adjustAddressToPageBoundary(&mod_address, &mod_size);

            debug.print("Locking memory for module {s} at address {x}, {d} bytes\n", .{ mod.string(), mod_address, mod_size });

            try lockFrames(context.allocator, mod_address, try std.math.divCeil(usize, mod_size, platform.PAGE_SIZE));
        }

        fn handler(mod: *easyboot.multiboot_tag_module_t, context: *const anyopaque) void {
            reserveMemory(mod, @alignCast(@ptrCast(context))) catch |err| {
                debug.print("Error while reserving multiboot memory {s}: {}\n", .{ mod.string(), err });
                while (true) {}
            };
        }
    }.handler, &ctx);
}

var lock: locking.SpinLock = .{};
var global_allocator: *FrameAllocator = undefined;

pub fn setGlobalAllocator(allocator: *FrameAllocator) !void {
    const frame = try allocFrame(allocator);
    const virt = frame.virtualAddress(vmm.PHYSICAL_MAPPING_BASE);

    global_allocator = @ptrFromInt(virt);
    global_allocator.* = allocator.*;
}

pub fn lockGlobalAllocator() *FrameAllocator {
    lock.lock();
    return global_allocator;
}

pub fn tryLockGlobalAllocator() ?*FrameAllocator {
    if (!lock.tryLock()) return null;
    return global_allocator;
}

pub fn unlockGlobalAllocator() void {
    lock.unlock();
}
