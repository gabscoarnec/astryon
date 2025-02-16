const std = @import("std");
const debug = @import("../arch/debug.zig");

pub const SpinLock = struct {
    lock_value: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn lock(self: *SpinLock) void {
        while (self.lock_value.cmpxchgWeak(0, 1, .seq_cst, .seq_cst) != null) {}
    }

    pub fn unlock(self: *SpinLock) void {
        if (self.lock_value.cmpxchgStrong(1, 0, .seq_cst, .seq_cst) != null) {
            debug.print("Error: SpinLock.unlock() called on an unlocked lock!\n", .{});
        }
    }

    pub fn tryLock(self: *SpinLock) bool {
        return self.lock_value.cmpxchgStrong(0, 1, .seq_cst, .seq_cst) == null;
    }

    pub fn isLocked(self: *SpinLock) bool {
        return self.lock_value.load() != 0;
    }
};
