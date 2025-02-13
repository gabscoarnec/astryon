const easyboot = @cImport(@cInclude("easyboot.h"));

const MemoryMapIterator = struct {
    tag: *easyboot.multiboot_tag_mmap_t,
    entry: ?*easyboot.multiboot_mmap_entry_t,
    end: usize,

    pub fn next(self: *MemoryMapIterator) ?*easyboot.multiboot_mmap_entry_t {
        if (self.entry) |e| {
            const current_entry = self.entry;

            var new_entry: [*c]u8 = @ptrCast(e);
            new_entry += self.tag.entry_size;
            self.entry = @alignCast(@ptrCast(new_entry));

            if (@intFromPtr(self.entry) >= self.end) self.entry = null;

            return current_entry;
        }

        return null;
    }
};

pub fn createMemoryMapIterator(tag: *easyboot.multiboot_tag_mmap_t) MemoryMapIterator {
    return MemoryMapIterator{ .tag = tag, .entry = @alignCast(@ptrCast(tag.entries())), .end = @intFromPtr(tag) + tag.size };
}

pub fn findLargestFreeEntry(tag: *easyboot.multiboot_tag_mmap_t) ?*easyboot.multiboot_mmap_entry_t {
    var max_length: u64 = 0;
    var biggest_entry: ?*easyboot.multiboot_mmap_entry_t = null;

    var iter = createMemoryMapIterator(tag);

    while (iter.next()) |entry| {
        if (entry.type == easyboot.MULTIBOOT_MEMORY_AVAILABLE and entry.length > max_length) {
            max_length = entry.length;
            biggest_entry = entry;
        }
    }

    return biggest_entry;
}

pub fn findHighestEntry(tag: *easyboot.multiboot_tag_mmap_t) ?*easyboot.multiboot_mmap_entry_t {
    var highest_entry: ?*easyboot.multiboot_mmap_entry_t = null;

    var iter = createMemoryMapIterator(tag);

    while (iter.next()) |entry| {
        highest_entry = entry;
    }

    return highest_entry;
}

pub fn getAddressSpaceSize(tag: *easyboot.multiboot_tag_mmap_t) ?usize {
    const highest_entry = findHighestEntry(tag) orelse return null;

    return highest_entry.base_addr + highest_entry.length;
}
