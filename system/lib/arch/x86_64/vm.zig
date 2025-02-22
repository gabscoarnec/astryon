const std = @import("std");
const syscalls = @import("../../syscalls.zig");

const MapError = error{
    MemoryAlreadyInUse,
    MemoryNotInUse,
    OutOfMemory,
};

pub const PhysFrame = struct {
    address: u64,

    pub fn virtualAddress(self: *const PhysFrame, base: usize) usize {
        return base + self.address;
    }

    pub fn virtualPointer(self: *const PhysFrame, comptime T: type, base: usize) *T {
        const virt = self.virtualAddress(base);
        return @ptrFromInt(virt);
    }
};

const PageTableEntry = packed struct {
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

const PageDirectory = struct {
    entries: [512]PageTableEntry,
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

pub const MemoryMapper = struct {
    cr3: PhysFrame,
    directory: *PageDirectory,
    base: u64,

    pub fn create(frame: PhysFrame, base: usize) MemoryMapper {
        return .{ .cr3 = frame, .directory = frame.virtualPointer(PageDirectory, base), .base = base };
    }
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

fn updatePageTableEntry(entry: *PageTableEntry, phys: PhysFrame, flags: u32) void {
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

fn setUpParentPageTableEntry(mapper: *const MemoryMapper, pte: *PageTableEntry, flags: u32) !void {
    if (pte.present == 0) {
        pte.clear();
        const frame = PhysFrame{ .address = try syscalls.allocFrame() };
        pte.present = 1;
        pte.setAddress(frame.address);
        getTable(mapper, pte).* = std.mem.zeroes(PageDirectory);
    }
    if (hasFlag(flags, Flags.ReadWrite) == 1) pte.read_write = 1;
    if (hasFlag(flags, Flags.User) == 1) pte.user = 1;
}

fn getTable(mapper: *const MemoryMapper, pte: *PageTableEntry) *PageDirectory {
    const frame = PhysFrame{ .address = pte.getAddress() };
    return frame.virtualPointer(PageDirectory, mapper.base);
}

pub fn map(mapper: *const MemoryMapper, virt_address: u64, phys: PhysFrame, flags: u32) !void {
    const indexes = calculatePageTableIndexes(virt_address);
    const l4 = &mapper.directory.entries[indexes.level4];
    try setUpParentPageTableEntry(mapper, l4, flags);

    const l3 = &getTable(mapper, l4).entries[indexes.level3];
    if (l3.larger_pages == 1) return error.MemoryAlreadyInUse;
    try setUpParentPageTableEntry(mapper, l3, flags);

    const l2 = &getTable(mapper, l3).entries[indexes.level2];
    if (l2.larger_pages == 1) return error.MemoryAlreadyInUse;
    try setUpParentPageTableEntry(mapper, l2, flags);

    const l1 = &getTable(mapper, l2).entries[indexes.level1];
    if (l1.present == 1) return error.MemoryAlreadyInUse;
    updatePageTableEntry(l1, phys, flags);
}

pub fn remap(mapper: *const MemoryMapper, virt_address: u64, phys: ?PhysFrame, flags: u32) !PhysFrame {
    const entry = getEntry(mapper, virt_address) orelse return error.MemoryNotInUse;
    const old_frame = PhysFrame{ .address = entry.getAddress() };
    const frame = phys orelse old_frame;

    updatePageTableEntry(entry, frame, flags);

    return old_frame;
}

pub fn unmap(mapper: *const MemoryMapper, virt_address: u64) !PhysFrame {
    const entry = getEntry(mapper, virt_address) orelse return error.MemoryNotInUse;

    const frame = PhysFrame{ .address = entry.getAddress() };

    entry.clear();

    return frame;
}

pub fn getEntry(mapper: MemoryMapper, virt_address: u64) ?*PageTableEntry {
    const indexes = calculatePageTableIndexes(virt_address);
    const l4 = &mapper.directory.entries[indexes.level4];
    if (l4.present == 0) return null;

    const l3 = &getTable(mapper, l4).entries[indexes.level3];
    if (l3.present == 0) return null;
    if (l3.larger_pages == 1) return l3;

    const l2 = &getTable(mapper, l3).entries[indexes.level2];
    if (l2.present == 0) return null;
    if (l2.larger_pages == 1) return l2;

    const l1 = &getTable(mapper, l2).entries[indexes.level1];
    if (l1.present == 0) return null;

    return l1;
}

pub fn getPhysical(mapper: MemoryMapper, virt_address: u64) ?PhysFrame {
    const entry = getEntry(mapper, virt_address) orelse return null;

    return PhysFrame{ .address = entry.getAddress() };
}
