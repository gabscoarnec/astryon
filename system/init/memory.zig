const std = @import("std");
const system = @import("system");

const vm = system.vm;

const MemoryRegion = struct {
    const Settings = struct {
        used: bool = true,
        persistent: bool = false,
        flags: i32 = 0,
        prot: i32 = 0,
    };

    start: usize,
    end: usize,
    count: u64,
    settings: Settings,
};

pub const ThreadMemoryMap = std.DoublyLinkedList(MemoryRegion);

pub fn createThreadMemoryMap(allocator: std.mem.Allocator) !ThreadMemoryMap {
    var map: ThreadMemoryMap = .{};
    errdefer destroyThreadMemoryMap(allocator, &map);

    _ = try createNullRegion(allocator, &map);
    _ = try createDefaultFreeRegion(allocator, &map);

    return map;
}

pub fn destroyThreadMemoryMap(allocator: std.mem.Allocator, map: *ThreadMemoryMap) void {
    var iter = map.first;

    while (iter) |node| {
        iter = node.next;

        map.remove(node);
        allocator.destroy(node);
    }
}

fn createNullRegion(allocator: std.mem.Allocator, map: *ThreadMemoryMap) !*MemoryRegion {
    var node = try allocator.create(ThreadMemoryMap.Node);
    const region = &node.data;

    region.* = std.mem.zeroInit(MemoryRegion, .{
        .start = 0,
        .end = vm.PAGE_SIZE,
        .count = 1,
        .settings = .{
            .used = true,
            .persistent = true,
        },
    });

    map.append(node);
    return region;
}

const VM_END: u64 = vm.USER_ADDRESS_RANGE_END + 1;

fn createDefaultFreeRegion(allocator: std.mem.Allocator, map: *ThreadMemoryMap) !*MemoryRegion {
    var node = try allocator.create(ThreadMemoryMap.Node);
    const region = &node.data;

    region.* = std.mem.zeroInit(MemoryRegion, .{
        .start = vm.PAGE_SIZE,
        .end = VM_END,
        .count = @divTrunc(VM_END, vm.PAGE_SIZE) - 1,
        .settings = .{
            .used = false,
        },
    });

    map.append(node);
    return region;
}

fn splitRegion(allocator: std.mem.Allocator, map: *ThreadMemoryMap, parent: *MemoryRegion, boundary: usize) !*MemoryRegion {
    var node = try allocator.create(ThreadMemoryMap.Node);
    const region = &node.data;

    region.start = boundary;
    region.end = parent.end;
    region.count = @divTrunc(region.end - region.start, vm.PAGE_SIZE);
    region.settings = parent.settings;

    map.insertAfter(@fieldParentPtr("data", parent), node);

    parent.end = boundary;
    parent.count -= region.count;

    return region;
}

fn mergeRegions(allocator: std.mem.Allocator, map: *ThreadMemoryMap, target: *MemoryRegion, origin: *MemoryRegion) void {
    target.end = origin.end;
    target.count += origin.count;

    const node: *ThreadMemoryMap.Node = @fieldParentPtr("data", origin);

    map.remove(node);
    allocator.destroy(node);
}

fn mergeable(a: *MemoryRegion, b: *MemoryRegion) bool {
    return std.meta.eql(a.settings, b.settings);
}

fn tryToMergeRegionWithBothNeighbours(allocator: std.mem.Allocator, map: *ThreadMemoryMap, region: *MemoryRegion) void {
    const node: *ThreadMemoryMap.Node = @fieldParentPtr("data", region);

    if (node.next) |next| {
        if (mergeable(&node.data, &next.data)) {
            mergeRegions(allocator, map, region, &next.data);
        }
    }

    if (node.prev) |prev| {
        if (mergeable(&node.data, &prev.data)) {
            mergeRegions(allocator, map, &prev.data, region);
        }
    }
}

fn tryToMergeRegionWithPrevious(allocator: std.mem.Allocator, map: *ThreadMemoryMap, region: *MemoryRegion) void {
    const node: *ThreadMemoryMap.Node = @fieldParentPtr("data", region);

    if (node.prev) |prev| {
        if (mergeable(&node.data, &prev.data)) {
            mergeRegions(allocator, map, &prev.data, region);
        }
    }
}

fn attemptToAllocateInRegion(allocator: std.mem.Allocator, map: *ThreadMemoryMap, region: *MemoryRegion, count: usize, settings: MemoryRegion.Settings) ?usize {
    if (!region.used) { // If the region is already used, skip it.
        if (region.count < count) return null; // Not enough space to allocate here, keep searching.

        if (region.count == count) { // Just enough space! Let's make this region used directly.
            region.settings = settings;
            region.settings.used = true; // Override this.

            const address: usize = region.start;
            tryToMergeRegionWithBothNeighbours(allocator, map, region);
            return address;
        }
        // More than enough space! Let's split the region and take just what we need.
        const boundary: usize = region.end - (count * vm.PAGE_SIZE);

        const child_region = try splitRegion(allocator, map, region, boundary);
        child_region.settings = settings;
        child_region.settings.used = true; // Override this.
        tryToMergeRegionWithBothNeighbours(allocator, map, child_region);

        return boundary;
    }

    return null;
}

pub fn allocRegion(allocator: std.mem.Allocator, map: *ThreadMemoryMap, count: usize, settings: MemoryRegion.Settings) ?usize {
    var iter = map.first;

    while (iter) |node| {
        const region = &node.data;
        if (attemptToAllocateInRegion(allocator, map, region, count, settings)) |address| return address;
        iter = node.next;
    }

    return null;
}

pub fn allocRegionFromEnd(allocator: std.mem.Allocator, map: *ThreadMemoryMap, count: usize, settings: MemoryRegion.Settings) ?usize {
    var iter = map.last;

    while (iter) |node| {
        const region = &node.data;
        if (attemptToAllocateInRegion(allocator, map, region, count, settings)) |address| return address;
        iter = node.prev;
    }

    return null;
}

// Checks that there's nothing preventing a selection from being updated.
fn canUpdate(map: *ThreadMemoryMap, start: usize, end: usize, used: bool, remap: bool) bool {
    var iter = map.first;
    while (iter) |node| {
        iter = node.next;
        const region = &node.data;

        // This region is completely out of our search range.
        if (region.end <= start) continue;
        if (region.start >= end) return true;

        // This region cannot be unmapped/remapped.
        if (region.settings.persistent) {
            system.io.print("Can't update selection {x}-{x}: Persistent region\n", .{ start, end });
            return false;
        }

        // Remapping a free region, not good.
        if (!region.settings.used and remap) {
            system.io.print("Can't update selection {x}-{x}: Remap of free region\n", .{ start, end });
            return false;
        }

        // Mapping an already used region, not good either.
        if (region.settings.used and used and !remap) {
            system.io.print("Can't update selection {x}-{x}: Map of used region\n", .{ start, end });
            return false;
        }

        // Unmapping an already freed region, not good either.
        if (!region.settings.used and !used and !remap) {
            system.io.print("Can't update selection {x}-{x}: Unmap of free region\n", .{ start, end });
            return false;
        }
    }

    return true;
}

// I wish there was some cleaner way to write all of this... giant mess.
// This function takes the address space "selection" from {address} to {end} and updates all regions that overlap it, splitting them if necessary.
// This can be used for freeing, mapping at a specific address, or remapping.
// Updates everything without any regard for previous settings, make sure canUpdate() has been called before. This is a private function for this reason.
// WARNING: If this function fails due to lack of memory, the selection may be partially updated!
fn updateSelection(allocator: std.mem.Allocator, map: *ThreadMemoryMap, address: usize, end: usize, settings: MemoryRegion.Settings) !void {
    var iter = map.first;
    while (iter) |node| {
        iter = node.next;
        const region = &node.data;

        // This region is out of our selection.
        if (region.end <= address) continue;

        if (region.start >= end) {
            system.io.print("Memory selection surpassed, reached {x}-{x}; no space for selection {x}-{x}, somehow! Something has gone terribly wrong\n", .{ region.start, region.end, address, end });
            while (true) {}
        }

        // We found the region we wanted, with its exact dimensions! All must rejoice.
        if (region.start == address and region.end == end) {
            region.settings = settings;
            tryToMergeRegionWithBothNeighbours(allocator, map, region);
            return;
        }

        // The region is entirely within our selection, let's update it and continue searching.
        if (region.start >= address and region.end <= end) {
            region.settings = settings;
            tryToMergeRegionWithPrevious(allocator, map, region);
            continue;
        }

        // The selection is entirely contained inside this region, let's split out the part we want.
        if (region.end > end and region.start < address) {
            const target_region = try splitRegion(allocator, map, region, address);
            _ = try splitRegion(allocator, map, target_region, end); // Cut off the end bit.
            target_region.settings = settings;
            tryToMergeRegionWithBothNeighbours(allocator, map, target_region); // Who knows, maybe the settings are compatible?
            return;
        }

        // The beginning of the selection is inside this region, with some extra at the beginning.
        if (region.start < address) {
            // Is this the last region we have to update?
            const finished: bool = region.end == end;

            const split_region = try splitRegion(allocator, map, region, address); // Cut off the beginning.
            split_region.settings = settings;
            if (!finished) {
                tryToMergeRegionWithPrevious(allocator, map, region);
                continue;
            }

            tryToMergeRegionWithBothNeighbours(allocator, map, split_region);
            return;
        }

        // The selection is inside this region, with some extra at the end. This means we have already handled all the other, earlier parts.
        if (region.end > end) {
            _ = try splitRegion(allocator, map, region, end); // Cut off the end.
            region.settings = settings;
            tryToMergeRegionWithBothNeighbours(allocator, map, region);
            return;
        }
    }

    system.io.print("End of memory map reached; no space for selection {x}-{x}, somehow! Something has gone terribly wrong\n", .{ address, end });
    while (true) {}
}

pub fn canUpdateRegion(map: *ThreadMemoryMap, address: usize, count: usize, settings: MemoryRegion.Settings, remap: bool) bool {
    if (address >= VM_END) return false;
    if (remap and !settings.used) return false; // Remap and free? What the hell?

    const end: u64 = address + (count * vm.PAGE_SIZE);

    return canUpdate(map, address, end, settings.used, remap);
}

pub fn updateRegion(allocator: std.mem.Allocator, map: *ThreadMemoryMap, address: usize, count: usize, settings: MemoryRegion.Settings, remap: bool) !bool {
    if (address >= VM_END) return false;
    if (remap and !settings.used) return false; // Remap and free? What the hell?

    const end: u64 = address + (count * vm.PAGE_SIZE);

    if (!canUpdate(map, address, end, settings.used, remap)) return false;

    try updateSelection(allocator, map, address, end, settings);

    return true;
}

pub inline fn freeRegion(allocator: std.mem.Allocator, map: *ThreadMemoryMap, address: usize, count: usize) !bool {
    return updateRegion(allocator, map, address, count, .{
        .used = false,
    }, false);
}

pub inline fn tryToAllocRegionAtAddress(allocator: std.mem.Allocator, map: *ThreadMemoryMap, address: usize, count: usize, settings: MemoryRegion.Settings) !bool {
    var settings_copy = settings;
    settings_copy.used = true;

    return updateRegion(allocator, map, address, count, settings_copy, false);
}
