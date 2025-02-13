const std = @import("std");

const BitmapError = error{
    OutOfRange,
};

pub const Bitmap = struct {
    location: [*]u8,
    byte_size: usize,

    pub fn bit_size(self: *Bitmap) usize {
        return self.byte_size * 8;
    }

    pub fn set(self: *Bitmap, index: usize, value: u1) BitmapError!void {
        if (index >= self.bit_size()) return error.OutOfRange;

        const byte_index = index / 8;
        const bit_mask = @as(u8, 0b10000000) >> @as(u3, @intCast(index % 8));
        self.location[byte_index] &= ~bit_mask;
        if (value == 1) {
            self.location[byte_index] |= bit_mask;
        }
    }

    pub fn get(self: *Bitmap, index: usize) BitmapError!u1 {
        if (index >= self.bit_size()) return error.OutOfRange;

        const byte_index = index / 8;
        const bit_mask = @as(u8, 0b10000000) >> @as(u3, @intCast(index % 8));
        if ((self.location[byte_index] & bit_mask) > 0) return 1;
        return 0;
    }

    pub fn clear(self: *Bitmap, value: u1) void {
        @memset(self.location[0..self.byte_size], byteThatOnlyContainsBit(value));
    }
};

pub fn createBitmap(location: [*]u8, byte_size: usize) Bitmap {
    return Bitmap{ .location = location, .byte_size = byte_size };
}

// Self-explanatory.
fn byteThatDoesNotContainBit(value: u1) u8 {
    return switch (value) {
        1 => 0x00,
        0 => 0xff,
    };
}

fn byteThatOnlyContainsBit(value: u1) u8 {
    return switch (value) {
        1 => 0xff,
        0 => 0x00,
    };
}

pub fn findInBitmap(bitmap: *Bitmap, value: u1, begin: usize) BitmapError!?usize {
    if (begin >= bitmap.bit_size()) return error.OutOfRange;

    var index = begin;

    while ((index % 8) != 0) {
        if (try bitmap.get(index) == value) return index;
        index += 1;
    }

    if (index == bitmap.bit_size()) return null;

    var i: usize = index / 8;
    const byte_that_does_not_contain_value = byteThatDoesNotContainBit(value);
    while (i < bitmap.byte_size) {
        if (bitmap.location[i] == byte_that_does_not_contain_value) {
            i += 1;
            continue;
        }

        var j: usize = i * 8;
        const end: usize = j + 8;
        while (j < end) {
            if (try bitmap.get(j) == value) return j;
            j += 1;
        }

        // Once we've located a byte that contains the value, we should succeed in finding it.
        unreachable;
    }

    return null;
}

pub fn findInBitmapAndToggle(bitmap: *Bitmap, value: u1, begin: usize) BitmapError!?usize {
    const index = try findInBitmap(bitmap, value, begin);

    switch (value) {
        0 => try bitmap.set(index, 1),
        1 => try bitmap.set(index, 0),
    }

    return index;
}

pub fn updateBitmapRegion(bitmap: *Bitmap, begin: usize, count: usize, value: u1) BitmapError!void {
    if ((begin + count) > bitmap.bit_size()) return error.OutOfRange;

    if (count == 0) return;

    var index = begin; // The bit index we're updating.
    var bits_remaining = count; // The number of bits left to update.

    // If the index is in the middle of a byte, update individual bits until we reach a byte.
    while ((index % 8) > 0 and bits_remaining > 0) {
        try bitmap.set(index, value);
        index += 1;
        bits_remaining -= 1;
    }

    // Clear out the rest in bytes. We calculate the number of bytes to update, and then memset them all.
    const bytes: usize = bits_remaining / 8;

    if (bytes > 0) {
        const start = index / 8;
        const end = start + bytes;
        @memset(bitmap.location[start..end], byteThatOnlyContainsBit(value));

        // Update the counting variables after the memset.
        index += bytes * 8;
        bits_remaining -= bytes * 8;
    }

    // Set the remaining individual bits.
    while (bits_remaining > 0) {
        try bitmap.set(index, value);
        index += 1;
        bits_remaining -= 1;
    }
}
