const std = @import("std");
const syscalls = @import("syscalls.zig");
const vm = @import("arch/vm.zig");
const init = @import("services/init.zig");
const ipc = @import("ipc.zig");

const PAGE_SIZE = vm.PAGE_SIZE;

const PageAllocator = struct {
    ptr: *anyopaque,
    allocAndMap: *const fn (ptr: *anyopaque, count: u64) anyerror!usize,
    unmapAndFree: *const fn (ptr: *anyopaque, base: usize, count: u64) anyerror!void,
};

// Not thread-safe and depends on userspace memory manipulation, should only be used in non-multithreading system processes (such as init).
pub const VirtualMemoryAllocator = struct {
    mapper: vm.MemoryMapper,
    base: usize,
    end: usize,
    start: usize,

    pub fn create(mapper: vm.MemoryMapper, base: usize, end: usize) VirtualMemoryAllocator {
        return .{ .mapper = mapper, .base = base, .end = end, .start = base };
    }

    pub fn page_allocator(self: *VirtualMemoryAllocator) PageAllocator {
        return .{ .ptr = self, .allocAndMap = VirtualMemoryAllocator.allocAndMap, .unmapAndFree = VirtualMemoryAllocator.unmapAndFree };
    }

    fn isAvailable(self: *VirtualMemoryAllocator, page: usize) bool {
        if (vm.getPhysical(&self.mapper, page)) |_| {
            return false;
        } else {
            return true;
        }
    }

    fn findFreeVirtualMemory(self: *VirtualMemoryAllocator, count: u64) ?usize {
        var page = self.start;

        var first_free_page: usize = 0;
        var free_contiguous_pages: u64 = 0;
        while (page < self.end) : (page += PAGE_SIZE) {
            if (!self.isAvailable(page)) {
                free_contiguous_pages = 0;
                continue;
            }

            if (free_contiguous_pages == 0) first_free_page = page;
            free_contiguous_pages += 1;

            // Found enough contiguous free pages!!
            if (free_contiguous_pages == count) {
                self.start = first_free_page + (PAGE_SIZE * count);
                return first_free_page;
            }
        }

        return null;
    }

    pub fn allocAndMap(ptr: *anyopaque, count: u64) anyerror!usize {
        const self: *VirtualMemoryAllocator = @ptrCast(@alignCast(ptr));

        const base = self.findFreeVirtualMemory(count) orelse return error.OutOfMemory;
        var virtual_address = base;

        var pages_mapped: u64 = 0;
        while (pages_mapped < count) : (pages_mapped += 1) {
            const address = try syscalls.allocFrame();
            try vm.map(&self.mapper, virtual_address, .{ .address = address }, @intFromEnum(vm.Flags.User) | @intFromEnum(vm.Flags.ReadWrite) | @intFromEnum(vm.Flags.NoExecute));
            virtual_address += PAGE_SIZE;
        }

        return base;
    }

    pub fn unmapAndFree(ptr: *anyopaque, base: usize, count: u64) anyerror!void {
        const self: *VirtualMemoryAllocator = @ptrCast(@alignCast(ptr));

        var virtual_address = base;

        var pages_unmapped: u64 = 0;
        while (pages_unmapped < count) : (pages_unmapped += 1) {
            const frame = try vm.unmap(&self.mapper, virtual_address);
            syscalls.freeFrame(frame.address);
            virtual_address += PAGE_SIZE;
        }

        self.start = @min(self.start, base);
    }
};

// Uses memory mapping IPC functions provided by init.
pub const MapMemoryAllocator = struct {
    connection: ipc.Connection,

    pub fn create(connection: ipc.Connection) MapMemoryAllocator {
        return .{ .connection = connection };
    }

    pub fn page_allocator(self: *MapMemoryAllocator) PageAllocator {
        return .{ .ptr = self, .allocAndMap = MapMemoryAllocator.allocAndMap, .unmapAndFree = MapMemoryAllocator.unmapAndFree };
    }

    pub fn allocAndMap(ptr: *anyopaque, count: u64) anyerror!usize {
        const self: *MapMemoryAllocator = @ptrCast(@alignCast(ptr));

        const base = init.map(&self.connection, count * vm.PAGE_SIZE, @intFromEnum(init.MapProt.PROT_READ) | @intFromEnum(init.MapProt.PROT_WRITE), @intFromEnum(init.MapFlags.MAP_ANONYMOUS) | @intFromEnum(init.MapFlags.MAP_PRIVATE)) orelse return error.OutOfMemory;

        return base;
    }

    pub fn unmapAndFree(ptr: *anyopaque, base: usize, count: u64) anyerror!void {
        const self: *MapMemoryAllocator = @ptrCast(@alignCast(ptr));

        init.unmap(&self.connection, base, count);
    }
};

const MEMORY_BLOCK_FREE_TAG = 0xffeeffcc;
const MEMORY_BLOCK_USED_TAG = 0xee55ee66;

const MemoryBlockStatus = enum(u16) {
    Default = 0,
    Used = 1 << 0,
    StartOfMemoryRange = 1 << 1,
    EndOfMemoryRange = 1 << 2,
};

const MemoryBlockTag = packed struct {
    tag: u32,
    status: u16,
    alignment: u16,
    base_address: u64,
    used: u64,
    allocated: u64,
};

const MemoryBlockList = std.DoublyLinkedList(MemoryBlockTag);

pub const SystemAllocator = struct {
    tags: MemoryBlockList,
    underlying_alloc: PageAllocator,

    pub fn init(page_allocator: PageAllocator) SystemAllocator {
        return .{ .tags = .{}, .underlying_alloc = page_allocator };
    }

    pub fn allocator(self: *SystemAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn ptrFromBlockNode(block: *MemoryBlockList.Node) [*]u8 {
        return @ptrFromInt(@intFromPtr(block) + @sizeOf(MemoryBlockList.Node));
    }

    fn blockNodeFromPtr(ptr: [*]u8) *MemoryBlockList.Node {
        return @ptrFromInt(@intFromPtr(ptr) - @sizeOf(MemoryBlockList.Node));
    }

    fn isBlockFree(block: *MemoryBlockList.Node) bool {
        return (block.data.status & @intFromEnum(MemoryBlockStatus.Used)) == 0;
    }

    fn checkStatus(block: *MemoryBlockList.Node, status: MemoryBlockStatus) bool {
        return (block.data.status & @intFromEnum(status)) == @intFromEnum(status);
    }

    fn spaceAvailable(block: *MemoryBlockList.Node) u64 {
        return block.data.allocated - block.data.used;
    }

    fn alignBlockAddressDownwards(block_address: usize, alignment: usize) usize {
        var object_address = block_address + @sizeOf(MemoryBlockList.Node);
        object_address -= @rem(object_address, alignment);

        return object_address - @sizeOf(MemoryBlockList.Node);
    }

    fn alignBlockAddressUpwards(block_address: usize, alignment: usize) usize {
        var object_address = block_address + @sizeOf(MemoryBlockList.Node);
        const unalignment = @rem(object_address, alignment);
        if (unalignment != 0) object_address += (alignment - unalignment);

        return object_address - @sizeOf(MemoryBlockList.Node);
    }

    fn alignOffset(block: *MemoryBlockList.Node, offset: usize, alignment: usize) usize {
        var block_address = @intFromPtr(ptrFromBlockNode(block)) + offset;

        block_address = alignBlockAddressDownwards(block_address, alignment);

        return block_address - @intFromPtr(ptrFromBlockNode(block));
    }

    fn getFairSplitOffset(block: *MemoryBlockList.Node, min: usize, alignment: usize) ?u64 {
        var available = spaceAvailable(block);

        available -= min; // reserve at least min size for the new block.
        available -= @divTrunc(available, 2); // reserve half of the rest for the new block, while still leaving another half for the old one.
        available -= @rem(available, 16); // Everything has to be aligned on a 16-byte boundary

        const block_offset = alignOffset(block, available + block.data.used, alignment);
        if (block_offset < block.data.used) return null;

        return block_offset;
    }

    fn getSplitOffset(block: *MemoryBlockList.Node, min: usize, alignment: usize) ?u64 {
        if (getFairSplitOffset(block, min, alignment)) |offset| return offset;
        // Otherwise, allocate space at the end of the block.

        var available = spaceAvailable(block);

        available -= min; // reserve only min size for the new block.

        const block_offset = alignOffset(block, available + block.data.used, alignment);
        if (block_offset < block.data.used) return null;

        return block_offset;
    }

    fn split(list: *MemoryBlockList, block: *MemoryBlockList.Node, len: usize, alignment: usize) ?*MemoryBlockList.Node {
        const available = spaceAvailable(block);
        const old_size = block.data.allocated;

        if (available < (len + @sizeOf(MemoryBlockList.Node))) return null; // Not enough space in this block

        const offset = getSplitOffset(block, len + @sizeOf(MemoryBlockList.Node), alignment) orelse return null;
        block.data.allocated = offset;

        const new_node: *MemoryBlockList.Node = @ptrFromInt(@as(usize, @intFromPtr(block)) + offset + @sizeOf(MemoryBlockList.Node));
        new_node.* = std.mem.zeroes(MemoryBlockList.Node);

        new_node.data.tag = MEMORY_BLOCK_USED_TAG;

        if (checkStatus(block, MemoryBlockStatus.EndOfMemoryRange)) {
            new_node.data.status = @intFromEnum(MemoryBlockStatus.EndOfMemoryRange);
        } else {
            new_node.data.status = @intFromEnum(MemoryBlockStatus.Default);
        }

        new_node.data.allocated = old_size - (offset + @sizeOf(MemoryBlockList.Node));
        new_node.data.alignment = @truncate(alignment);
        new_node.data.base_address = block.data.base_address;

        list.insertAfter(block, new_node);

        block.data.status &= ~@intFromEnum(MemoryBlockStatus.EndOfMemoryRange); // this block is no longer the last block in its memory range

        return new_node;
    }

    fn combineForward(list: *MemoryBlockList, block: *MemoryBlockList.Node) void {
        // This block ends a memory range, cannot be combined with blocks outside its range.
        if (checkStatus(block, MemoryBlockStatus.EndOfMemoryRange)) return;

        // The caller needs to ensure there is a next block.
        const next = block.next.?;
        // This block starts a memory range, cannot be combined with blocks outside its range.
        if (checkStatus(next, MemoryBlockStatus.StartOfMemoryRange)) return;

        list.remove(next);
        next.data.tag = MEMORY_BLOCK_FREE_TAG;

        block.data.allocated += next.data.allocated + @sizeOf(MemoryBlockList.Node);

        if (checkStatus(next, MemoryBlockStatus.EndOfMemoryRange)) {
            block.data.status |= @intFromEnum(MemoryBlockStatus.EndOfMemoryRange);
        }
    }

    fn combineBackward(list: *MemoryBlockList, block: *MemoryBlockList.Node) *MemoryBlockList.Node {
        // This block starts a memory range, cannot be combined with blocks outside its range.
        if (checkStatus(block, MemoryBlockStatus.StartOfMemoryRange)) return block;

        // The caller needs to ensure there is a last block.
        const last = block.prev.?;
        // This block ends a memory range, cannot be combined with blocks outside its range.
        if (checkStatus(last, MemoryBlockStatus.EndOfMemoryRange)) return block;

        list.remove(block);
        block.data.tag = MEMORY_BLOCK_FREE_TAG;

        last.data.allocated += block.data.allocated + @sizeOf(MemoryBlockList.Node);

        if (checkStatus(block, MemoryBlockStatus.EndOfMemoryRange)) {
            last.data.status |= @intFromEnum(MemoryBlockStatus.EndOfMemoryRange);
        }

        return last;
    }

    const MINIMUM_PAGES_PER_ALLOCATION = 4;

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, _: usize) ?[*]u8 {
        const self: *SystemAllocator = @ptrCast(@alignCast(ctx));

        if (len == 0) return null;

        var alignment = @as(usize, 1) << @truncate(ptr_align);
        if (alignment < 16) alignment = 16;

        var iter = self.tags.first;
        while (iter) |tag| {
            iter = tag.next;

            if (isBlockFree(tag)) {
                if (tag.data.allocated < len) continue;
                break;
            }

            iter = split(&self.tags, tag, len, alignment) orelse continue;
            break;
        }

        if (iter == null) {
            const pages: usize = @max(MINIMUM_PAGES_PER_ALLOCATION, @divTrunc(len + @sizeOf(MemoryBlockList.Node), PAGE_SIZE));

            const base_address = self.underlying_alloc.allocAndMap(self.underlying_alloc.ptr, pages) catch return null;
            const address = alignBlockAddressUpwards(base_address, alignment);

            const padding = address - base_address;

            const node: *MemoryBlockList.Node = @ptrFromInt(address);
            node.* = std.mem.zeroes(MemoryBlockList.Node);

            node.data.allocated = (pages * PAGE_SIZE) - (@sizeOf(MemoryBlockList.Node) + padding);
            node.data.tag = MEMORY_BLOCK_USED_TAG;
            node.data.status = @intFromEnum(MemoryBlockStatus.StartOfMemoryRange) | @intFromEnum(MemoryBlockStatus.EndOfMemoryRange);
            node.data.alignment = @truncate(alignment);
            node.data.base_address = base_address;
            self.tags.append(node);

            iter = node;
        }

        const tag = iter.?;

        tag.data.used = len;
        tag.data.status |= @intFromEnum(MemoryBlockStatus.Used);

        return ptrFromBlockNode(tag);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, _: usize) bool {
        _ = ctx;

        var alignment: usize = @as(usize, 1) << @truncate(buf_align);
        if (alignment < 16) alignment = 16;

        const block = blockNodeFromPtr(buf.ptr);
        if (block.data.tag != MEMORY_BLOCK_USED_TAG) return false;
        if (block.data.alignment != alignment) return false;
        if (!isBlockFree(block)) return false;

        if (new_len > block.data.allocated) return false;
        block.data.used = new_len;

        return true;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, _: usize) void {
        const self: *SystemAllocator = @ptrCast(@alignCast(ctx));

        var alignment: usize = @as(usize, 1) << @truncate(buf_align);
        if (alignment < 16) alignment = 16;

        var block = blockNodeFromPtr(buf.ptr);
        if (block.data.tag != MEMORY_BLOCK_USED_TAG) return;
        if (block.data.alignment != alignment) return;
        if (!isBlockFree(block)) return;

        block.data.status &= ~@intFromEnum(MemoryBlockStatus.Used);

        const maybe_next = block.next;
        if (maybe_next) |next| {
            if (isBlockFree(next)) combineForward(&self.tags, block);
        }

        const maybe_last = block.prev;
        if (maybe_last) |last| {
            if (isBlockFree(last)) block = combineBackward(&self.tags, block);
        }

        if (checkStatus(block, MemoryBlockStatus.StartOfMemoryRange) and checkStatus(block, MemoryBlockStatus.EndOfMemoryRange)) {
            self.tags.remove(block);

            const base_address = block.data.base_address;
            const block_address = @intFromPtr(block);

            const padding = block_address - base_address;

            const pages = std.math.divCeil(usize, block.data.allocated + padding + @sizeOf(MemoryBlockList.Node), PAGE_SIZE) catch return;
            self.underlying_alloc.unmapAndFree(self.underlying_alloc.ptr, base_address, pages) catch return;
        }
    }
};
