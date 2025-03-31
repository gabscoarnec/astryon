const std = @import("std");
const easyboot = @cImport(@cInclude("easyboot.h"));
const mmap = @import("../../mmap.zig");
const pmm = @import("../../pmm.zig");
const platform = @import("platform.zig");
const debug = @import("../debug.zig");

const USER_ADDRESS_RANGE_END = 0x0000_7fff_ffff_ffff;
pub const PHYSICAL_MAPPING_BASE = 0xffff_8000_0000_0000;
const HUGE_PAGE_SIZE = 0x200000; // 2 MiB

pub const PageTableEntry = packed struct {
    present: u1,
    read_write: u1,
    user: u1,
    write_through: u1,
    cache_disabled: u1,
    accessed: u1,
    reserved: u1,
    larger_pages: u1,
    global: u1,
    available: u3,
    address: u48,
    available2: u3,
    no_execute: u1,

    pub fn setAddress(self: *PageTableEntry, address: u64) void {
        self.address = @intCast(address >> 12);
    }

    pub fn getAddress(self: *PageTableEntry) u64 {
        return self.address << 12;
    }

    pub fn clear(self: *PageTableEntry) void {
        self.* = std.mem.zeroes(PageTableEntry);
    }
};

// Used for all page tables (PML4, PDPT, PD and PT).
pub const PageTable = struct {
    entries: [512]PageTableEntry,
};

pub const AddressSpace = struct {
    phys: pmm.PhysFrame,
    table: *PageTable,

    pub fn create(frame: pmm.PhysFrame, base: usize) AddressSpace {
        return .{ .phys = frame, .table = @ptrFromInt(frame.virtualAddress(base)) };
    }
};

pub const Flags = enum(u32) {
    None = 0,
    ReadWrite = 1,
    User = 2,
    NoExecute = 4,
    WriteThrough = 8,
    CacheDisable = 16,
    Global = 32,
};

const PageTableIndexes = struct {
    level4: u24,
    level3: u24,
    level2: u24,
    level1: u24,
};

fn calculatePageTableIndexes(address: usize) PageTableIndexes {
    return .{ .level4 = @intCast((address >> 39) & 0o777), .level3 = @intCast((address >> 30) & 0o777), .level2 = @intCast((address >> 21) & 0o777), .level1 = @intCast((address >> 12) & 0o777) };
}

fn hasFlag(flags: u32, flag: Flags) u1 {
    return switch ((flags & @intFromEnum(flag)) > 0) {
        true => 1,
        false => 0,
    };
}

fn updatePageTableEntry(entry: *PageTableEntry, phys: pmm.PhysFrame, flags: u32) void {
    entry.clear();
    entry.present = 1;
    entry.read_write = hasFlag(flags, Flags.ReadWrite);
    entry.user = hasFlag(flags, Flags.User);
    entry.write_through = hasFlag(flags, Flags.WriteThrough);
    entry.cache_disabled = hasFlag(flags, Flags.CacheDisable);
    entry.no_execute = hasFlag(flags, Flags.NoExecute);
    entry.global = hasFlag(flags, Flags.Global);
    entry.setAddress(phys.address);
}

fn setUpParentPageTableEntry(allocator: *pmm.FrameAllocator, pte: *PageTableEntry, flags: u32, base: usize) !void {
    if (pte.present == 0) {
        pte.clear();
        const frame = try pmm.allocFrame(allocator);
        pte.present = 1;
        pte.setAddress(frame.address);
        getTable(pte, base).* = std.mem.zeroes(PageTable);
    }
    if (hasFlag(flags, Flags.ReadWrite) == 1) pte.read_write = 1;
    if (hasFlag(flags, Flags.User) == 1) pte.user = 1;
}

fn getTable(pte: *PageTableEntry, base: usize) *allowzero PageTable {
    const frame = pmm.PhysFrame{ .address = pte.getAddress() };
    return @ptrFromInt(frame.virtualAddress(base));
}

pub fn map(allocator: *pmm.FrameAllocator, space: AddressSpace, base: usize, virt_address: u64, phys: pmm.PhysFrame, flags: u32, use_huge_pages: bool) !void {
    const indexes = calculatePageTableIndexes(virt_address);
    const pml4_entry = &space.table.entries[indexes.level4];
    try setUpParentPageTableEntry(allocator, pml4_entry, flags, base);

    const pdpt_entry = &getTable(pml4_entry, base).entries[indexes.level3];
    if (pdpt_entry.larger_pages == 1) return error.MemoryAlreadyInUse;
    try setUpParentPageTableEntry(allocator, pdpt_entry, flags, base);

    const pd_entry = &getTable(pdpt_entry, base).entries[indexes.level2];
    if (pd_entry.larger_pages == 1) return error.MemoryAlreadyInUse;

    if (use_huge_pages) {
        updatePageTableEntry(pd_entry, phys, flags);
        pd_entry.larger_pages = 1;
        return;
    }

    try setUpParentPageTableEntry(allocator, pd_entry, flags, base);

    const pt_entry = &getTable(pd_entry, base).entries[indexes.level1];
    if (pt_entry.present == 1) return error.MemoryAlreadyInUse;
    updatePageTableEntry(pt_entry, phys, flags);
}

pub fn getEntry(space: AddressSpace, base: usize, virt_address: u64) ?*PageTableEntry {
    const indexes = calculatePageTableIndexes(virt_address);
    const pml4_entry = &space.table.entries[indexes.level4];
    if (pml4_entry.present == 0) return null;

    const pdpt_entry = &getTable(pml4_entry, base).entries[indexes.level3];
    if (pdpt_entry.present == 0) return null;
    if (pdpt_entry.larger_pages == 1) return pdpt_entry;

    const pd_entry = &getTable(pdpt_entry, base).entries[indexes.level2];
    if (pd_entry.present == 0) return null;
    if (pd_entry.larger_pages == 1) return pd_entry;

    const pt_entry = &getTable(pd_entry, base).entries[indexes.level1];
    if (pt_entry.present == 0) return null;

    return pt_entry;
}

pub fn getAddress(space: AddressSpace, base: usize, virt_address: u64) ?usize {
    const entry = getEntry(space, base, virt_address) orelse return null;
    return entry.getAddress();
}

pub fn copyToUser(space: AddressSpace, base: usize, user: usize, kernel: [*]const u8, size: usize) !void {
    const remainder: usize = @rem(user, platform.PAGE_SIZE);
    const user_page = user - remainder;

    var user_address = user;
    var kernel_ptr = kernel;
    var count = size;

    if (user_address != user_page) {
        const pte = getEntry(space, base, user_page) orelse return error.MemoryNotInUse;
        const frame = pmm.PhysFrame{ .address = pte.getAddress() };
        const amount: usize = @min((platform.PAGE_SIZE - remainder), count);
        const virt = frame.virtualAddress(base) + remainder;

        @memcpy(@as([*]u8, @ptrFromInt(virt))[0..amount], kernel_ptr[0..amount]);

        kernel_ptr += amount;
        user_address += amount;
        count -= amount;
    }

    while (count > 0) {
        const pte = getEntry(space, base, user_address) orelse return error.MemoryNotInUse;
        const frame = pmm.PhysFrame{ .address = pte.getAddress() };
        const amount: usize = @min(platform.PAGE_SIZE, count);
        const virt = frame.virtualAddress(base);

        @memcpy(@as([*]u8, @ptrFromInt(virt))[0..amount], kernel_ptr[0..amount]);

        kernel_ptr += amount;
        user_address += amount;
        count -= amount;
    }

    return;
}

pub fn copyFromUser(space: AddressSpace, base: usize, user: usize, kernel: [*]u8, size: usize) !void {
    const remainder: usize = @rem(user, platform.PAGE_SIZE);
    const user_page = user - remainder;

    var user_address = user;
    var kernel_ptr = kernel;
    var count = size;

    if (user_address != user_page) {
        const pte = getEntry(space, base, user_page) orelse return error.MemoryNotInUse;
        const frame = pmm.PhysFrame{ .address = pte.getAddress() };
        const amount: usize = @min((platform.PAGE_SIZE - remainder), count);
        const virt = frame.virtualAddress(base) + remainder;

        @memcpy(kernel_ptr[0..amount], @as([*]const u8, @ptrFromInt(virt))[0..amount]);

        kernel_ptr += amount;
        user_address += amount;
        count -= amount;
    }

    while (count > 0) {
        const pte = getEntry(space, base, user_address) orelse return error.MemoryNotInUse;
        const frame = pmm.PhysFrame{ .address = pte.getAddress() };
        const amount: usize = @min(platform.PAGE_SIZE, count);
        const virt = frame.virtualAddress(base);

        @memcpy(kernel_ptr[0..amount], @as([*]const u8, @ptrFromInt(virt))[0..amount]);

        kernel_ptr += amount;
        user_address += amount;
        count -= amount;
    }

    return;
}

pub fn memsetUser(space: AddressSpace, base: usize, user: usize, elem: u8, size: usize) !void {
    const remainder: usize = @rem(user, platform.PAGE_SIZE);
    const user_page = user - remainder;

    var user_address = user;
    var count = size;

    if (user_address != user_page) {
        const pte = getEntry(space, base, user_page) orelse return error.MemoryNotInUse;
        const frame = pmm.PhysFrame{ .address = pte.getAddress() };
        const amount: usize = @min((platform.PAGE_SIZE - remainder), count);
        const virt = frame.virtualAddress(base) + remainder;

        @memset(@as([*]u8, @ptrFromInt(virt))[0..amount], elem);

        user_address += amount;
        count -= amount;
    }

    while (count > 0) {
        const pte = getEntry(space, base, user_address) orelse return error.MemoryNotInUse;
        const frame = pmm.PhysFrame{ .address = pte.getAddress() };
        const amount: usize = @min(platform.PAGE_SIZE, count);
        const virt = frame.virtualAddress(base);

        @memset(@as([*]u8, @ptrFromInt(virt))[0..amount], elem);

        user_address += amount;
        count -= amount;
    }

    return;
}

pub fn allocAndMap(allocator: *pmm.FrameAllocator, space: AddressSpace, base: u64, pages: usize, flags: u32) !void {
    var virt = base;
    var i: usize = 0;

    while (i < pages) {
        const frame = try pmm.allocFrame(allocator);
        try map(allocator, space, PHYSICAL_MAPPING_BASE, virt, frame, flags, false);
        virt += platform.PAGE_SIZE;
        i += 1;
    }
}

fn mapPhysicalMemory(allocator: *pmm.FrameAllocator, tag: *easyboot.multiboot_tag_mmap_t, space: AddressSpace, base: usize, start_addr: usize, flags: u32) !void {
    const address_space_size = mmap.getAddressSpaceSize(tag) orelse return error.InvalidMemoryMap;
    const address_space_pages = address_space_size / HUGE_PAGE_SIZE;

    var index: usize = 0;
    while (index < address_space_pages) : (index += 1) {
        try map(allocator, space, base, start_addr + index * HUGE_PAGE_SIZE, pmm.PhysFrame{ .address = index * HUGE_PAGE_SIZE }, flags, true);
    }
}

fn lockPageTableFrames(allocator: *pmm.FrameAllocator, table: *PageTable, index: u8) !void {
    if (index > 1) {
        var i: u64 = 0;
        while (i < 512) : (i += 1) {
            const pte = &table.entries[i];
            if (pte.present == 0) continue;
            if ((index < 4) and (pte.larger_pages == 1)) continue;

            try pmm.lockFrame(allocator, pte.getAddress());

            const child_table: *PageTable = @ptrFromInt(pte.getAddress());

            try lockPageTableFrames(allocator, child_table, index - 1);
        }
    }
}

fn lockPageTable(allocator: *pmm.FrameAllocator, space: AddressSpace) !void {
    try pmm.lockFrame(allocator, space.phys.address);
    try lockPageTableFrames(allocator, space.table, 4);
}

fn setUpKernelPageDirectory(allocator: *pmm.FrameAllocator, tag: *easyboot.multiboot_tag_mmap_t) !pmm.PhysFrame {
    const table = readPageTable();

    const space = AddressSpace.create(table, 0);

    try lockPageTable(allocator, space);
    try mapPhysicalMemory(allocator, tag, space, 0, PHYSICAL_MAPPING_BASE, @intFromEnum(Flags.ReadWrite) | @intFromEnum(Flags.NoExecute) | @intFromEnum(Flags.Global));

    return table;
}

pub fn setUpInitialUserPageDirectory(allocator: *pmm.FrameAllocator, tag: *easyboot.multiboot_tag_mmap_t, space: AddressSpace) !usize {
    const kernel_space = AddressSpace.create(readPageTable(), PHYSICAL_MAPPING_BASE);
    const kernel_table = kernel_space.table;

    const physical_address_space_size = mmap.getAddressSpaceSize(tag) orelse return error.InvalidMemoryMap;

    space.table.* = std.mem.zeroes(PageTable);

    const directory_upper_half: *[256]PageTableEntry = kernel_table.entries[256..];
    const user_directory_upper_half: *[256]PageTableEntry = space.table.entries[256..];
    @memcpy(user_directory_upper_half, directory_upper_half);

    const user_physical_address_base = (USER_ADDRESS_RANGE_END + 1) - physical_address_space_size;

    try mapPhysicalMemory(allocator, tag, space, PHYSICAL_MAPPING_BASE, user_physical_address_base, @intFromEnum(Flags.ReadWrite) | @intFromEnum(Flags.NoExecute) | @intFromEnum(Flags.User));

    return user_physical_address_base;
}

pub fn createInitialMapping(allocator: *pmm.FrameAllocator, tag: *easyboot.multiboot_tag_mmap_t) !void {
    const frame = try setUpKernelPageDirectory(allocator, tag);
    const space = AddressSpace.create(frame, 0);

    setPageTable(space.phys);

    allocator.bitmap.location = @ptrFromInt(@as(usize, PHYSICAL_MAPPING_BASE) + @intFromPtr(allocator.bitmap.location));
}

pub fn readPageTable() pmm.PhysFrame {
    var address: u64 = undefined;
    asm volatile ("mov %%cr3, %[dir]"
        : [dir] "=r" (address),
    );
    return .{ .address = address };
}

pub fn setPageTable(directory: pmm.PhysFrame) void {
    asm volatile ("mov %[dir], %%cr3"
        :
        : [dir] "{rdi}" (directory.address),
    );
}
