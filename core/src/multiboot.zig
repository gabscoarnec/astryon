const std = @import("std");
const easyboot = @cImport(@cInclude("easyboot.h"));
const debug = @import("arch/debug.zig");

fn dumpUUID(uuid: [16]u8) void {
    debug.print("{x:0^2}{x:0^2}{x:0^2}{x:0^2}-{x:0^2}{x:0^2}-{x:0^2}{x:0^2}-{x:0^2}{x:0^2}{x:0^2}{x:0^2}{x:0^2}{x:0^2}{x:0^2}{x:0^2}\n", .{ uuid[3], uuid[2], uuid[1], uuid[0], uuid[5], uuid[4], uuid[7], uuid[6], uuid[8], uuid[9], uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15] });
}

const MultibootInfo = [*]u8;

/// Return the first multiboot tag of the given type.
pub fn findMultibootTag(comptime Type: type, info: MultibootInfo) ?*Type {
    const mb_tag: *easyboot.multiboot_info_t = @alignCast(@ptrCast(info));
    const mb_size = mb_tag.total_size;

    var tag: *easyboot.multiboot_tag_t = @alignCast(@ptrCast(info + 8));
    const last = @intFromPtr(info) + mb_size;
    while ((@intFromPtr(tag) < last) and (tag.type != easyboot.MULTIBOOT_TAG_TYPE_END)) {
        switch (tag.type) {
            easyboot.MULTIBOOT_TAG_TYPE_CMDLINE => {
                if (Type == easyboot.multiboot_tag_cmdline_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_BOOT_LOADER_NAME => {
                if (Type == easyboot.multiboot_tag_loader_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_MODULE => {
                if (Type == easyboot.multiboot_tag_module_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_MMAP => {
                if (Type == easyboot.multiboot_tag_mmap_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_FRAMEBUFFER => {
                if (Type == easyboot.multiboot_tag_framebuffer_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_EFI64 => {
                if (Type == easyboot.multiboot_tag_efi64_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_EFI64_IH => {
                if (Type == easyboot.multiboot_tag_efi64_ih_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_SMBIOS => {
                if (Type == easyboot.multiboot_tag_smbios_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_ACPI_OLD => {
                if (Type == easyboot.multiboot_tag_old_acpi_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_ACPI_NEW => {
                if (Type == easyboot.multiboot_tag_new_acpi_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_SMP => {
                if (Type == easyboot.multiboot_tag_smp_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_PARTUUID => {
                if (Type == easyboot.multiboot_tag_partuuid_t) return @alignCast(@ptrCast(tag));
            },
            easyboot.MULTIBOOT_TAG_TYPE_EDID => {
                if (Type == easyboot.multiboot_tag_edid_t) return @alignCast(@ptrCast(tag));
            },
            else => {},
        }

        var new_tag: [*]u8 = @ptrCast(tag);
        new_tag += ((tag.size + 7) & ~@as(usize, 7));
        tag = @alignCast(@ptrCast(new_tag));
    }

    return null;
}

/// Find every multiboot tag of the given type.
pub fn findMultibootTags(comptime Type: type, info: MultibootInfo, callback: *const fn (tag: *Type) void) void {
    const mb_tag: *easyboot.multiboot_info_t = @alignCast(@ptrCast(info));
    const mb_size = mb_tag.total_size;

    var tag: *easyboot.multiboot_tag_t = @alignCast(@ptrCast(info + 8));
    const last = @intFromPtr(info) + mb_size;
    while ((@intFromPtr(tag) < last) and (tag.type != easyboot.MULTIBOOT_TAG_TYPE_END)) {
        switch (tag.type) {
            easyboot.MULTIBOOT_TAG_TYPE_CMDLINE => {
                if (Type == easyboot.multiboot_tag_cmdline_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_BOOT_LOADER_NAME => {
                if (Type == easyboot.multiboot_tag_loader_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_MODULE => {
                if (Type == easyboot.multiboot_tag_module_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_MMAP => {
                if (Type == easyboot.multiboot_tag_mmap_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_FRAMEBUFFER => {
                if (Type == easyboot.multiboot_tag_framebuffer_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_EFI64 => {
                if (Type == easyboot.multiboot_tag_efi64_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_EFI64_IH => {
                if (Type == easyboot.multiboot_tag_efi64_ih_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_SMBIOS => {
                if (Type == easyboot.multiboot_tag_smbios_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_ACPI_OLD => {
                if (Type == easyboot.multiboot_tag_old_acpi_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_ACPI_NEW => {
                if (Type == easyboot.multiboot_tag_new_acpi_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_SMP => {
                if (Type == easyboot.multiboot_tag_smp_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_PARTUUID => {
                if (Type == easyboot.multiboot_tag_partuuid_t) callback(@alignCast(@ptrCast(tag)));
            },
            easyboot.MULTIBOOT_TAG_TYPE_EDID => {
                if (Type == easyboot.multiboot_tag_edid_t) callback(@alignCast(@ptrCast(tag)));
            },
            else => {},
        }

        var new_tag: [*]u8 = @ptrCast(tag);
        new_tag += ((tag.size + 7) & ~@as(usize, 7));
        tag = @alignCast(@ptrCast(new_tag));
    }
}

/// Log every multiboot tag in a multiboot struct.
pub fn parseMultibootTags(info: MultibootInfo) void {
    const mb_tag: *easyboot.multiboot_info_t = @alignCast(@ptrCast(info));
    const mb_size = mb_tag.total_size;

    var tag: *easyboot.multiboot_tag_t = @alignCast(@ptrCast(info + 8));
    const last = @intFromPtr(info) + mb_size;
    while ((@intFromPtr(tag) < last) and (tag.type != easyboot.MULTIBOOT_TAG_TYPE_END)) {
        switch (tag.type) {
            easyboot.MULTIBOOT_TAG_TYPE_CMDLINE => {
                var cmdline: *easyboot.multiboot_tag_cmdline_t = @alignCast(@ptrCast(tag));
                debug.print("Command line = {s}\n", .{std.mem.sliceTo(cmdline.string(), 0)});
            },
            easyboot.MULTIBOOT_TAG_TYPE_BOOT_LOADER_NAME => {
                var bootloader: *easyboot.multiboot_tag_loader_t = @alignCast(@ptrCast(tag));
                debug.print("Boot loader name = {s}\n", .{std.mem.sliceTo(bootloader.string(), 0)});
            },
            easyboot.MULTIBOOT_TAG_TYPE_MODULE => {
                var module: *easyboot.multiboot_tag_module_t = @alignCast(@ptrCast(tag));
                debug.print("Module at {x}-{x}. Command line {s}\n", .{ module.mod_start, module.mod_end, std.mem.sliceTo(module.string(), 0) });
            },
            easyboot.MULTIBOOT_TAG_TYPE_MMAP => {
                var mmap: *easyboot.multiboot_tag_mmap_t = @alignCast(@ptrCast(tag));
                debug.print("Memory map:\n", .{});
                var entry: *easyboot.multiboot_mmap_entry_t = @alignCast(@ptrCast(mmap.entries()));
                const end = @intFromPtr(tag) + tag.size;
                while (@intFromPtr(entry) < end) {
                    debug.print(" base_addr = {x}, length = {x}, type = {x} {s}, res = {x}\n", .{ entry.base_addr, entry.length, entry.type, switch (entry.type) {
                        easyboot.MULTIBOOT_MEMORY_AVAILABLE => "free",
                        easyboot.MULTIBOOT_MEMORY_ACPI_RECLAIMABLE => "ACPI",
                        easyboot.MULTIBOOT_MEMORY_NVS => "ACPI NVS",
                        else => "used",
                    }, entry.reserved });

                    var new_entry: [*c]u8 = @ptrCast(entry);
                    new_entry += mmap.entry_size;
                    entry = @alignCast(@ptrCast(new_entry));
                }
            },
            easyboot.MULTIBOOT_TAG_TYPE_FRAMEBUFFER => {
                const fb: *easyboot.multiboot_tag_framebuffer_t = @alignCast(@ptrCast(tag));
                debug.print("Framebuffer: \n", .{});
                debug.print(" address {x} pitch {d}\n", .{ fb.framebuffer_addr, fb.framebuffer_pitch });
                debug.print(" width {d} height {d} depth {d} bpp\n", .{ fb.framebuffer_width, fb.framebuffer_height, fb.framebuffer_bpp });
                debug.print(" red channel:   at {d}, {d} bits\n", .{ fb.framebuffer_red_field_position, fb.framebuffer_red_mask_size });
                debug.print(" green channel: at {d}, {d} bits\n", .{ fb.framebuffer_green_field_position, fb.framebuffer_green_mask_size });
                debug.print(" blue channel:  at {d}, {d} bits\n", .{ fb.framebuffer_blue_field_position, fb.framebuffer_blue_mask_size });
            },
            easyboot.MULTIBOOT_TAG_TYPE_EFI64 => {
                const efi: *easyboot.multiboot_tag_efi64_t = @alignCast(@ptrCast(tag));
                debug.print("EFI system table {x}\n", .{efi.pointer});
            },
            easyboot.MULTIBOOT_TAG_TYPE_EFI64_IH => {
                const efi_ih: *easyboot.multiboot_tag_efi64_t = @alignCast(@ptrCast(tag));
                debug.print("EFI image handle {x}\n", .{efi_ih.pointer});
            },
            easyboot.MULTIBOOT_TAG_TYPE_SMBIOS => {
                const smbios: *easyboot.multiboot_tag_smbios_t = @alignCast(@ptrCast(tag));
                debug.print("SMBIOS table major {d} minor {d}\n", .{ smbios.major, smbios.minor });
            },
            easyboot.MULTIBOOT_TAG_TYPE_ACPI_OLD => {
                const acpi: *easyboot.multiboot_tag_old_acpi_t = @alignCast(@ptrCast(tag));
                const rsdp = @intFromPtr(acpi.rsdp());
                debug.print("ACPI table (1.0, old RSDP) at {x}\n", .{rsdp});
            },
            easyboot.MULTIBOOT_TAG_TYPE_ACPI_NEW => {
                const acpi: *easyboot.multiboot_tag_new_acpi_t = @alignCast(@ptrCast(tag));
                const rsdp = @intFromPtr(acpi.rsdp());
                debug.print("ACPI table (2.0, new RSDP) at {x}\n", .{rsdp});
            },
            easyboot.MULTIBOOT_TAG_TYPE_SMP => {
                const smp: *easyboot.multiboot_tag_smp_t = @alignCast(@ptrCast(tag));
                debug.print("SMP supported\n", .{});
                debug.print(" {d} core(s)\n", .{smp.numcores});
                debug.print(" {d} running\n", .{smp.running});
                debug.print(" {x} bsp id\n", .{smp.bspid});
            },
            easyboot.MULTIBOOT_TAG_TYPE_PARTUUID => {
                const part: *easyboot.multiboot_tag_partuuid_t = @alignCast(@ptrCast(tag));
                debug.print("Partition UUIDs\n", .{});
                debug.print(" boot ", .{});
                dumpUUID(part.bootuuid);
                if (tag.size >= 40) {
                    debug.print(" root ", .{});
                    dumpUUID(part.rootuuid);
                }
            },
            easyboot.MULTIBOOT_TAG_TYPE_EDID => {
                const edid_tag: *easyboot.multiboot_tag_edid_t = @alignCast(@ptrCast(tag));
                const edid: []u8 = edid_tag.edid()[0 .. tag.size - @sizeOf(easyboot.multiboot_tag_t)];
                debug.print("EDID info\n", .{});
                debug.print(" manufacturer ID {x}{x}\n", .{ edid[8], edid[9] });
                debug.print(" EDID ID {x}{x} Version {d} Rev {d}\n", .{ edid[10], edid[11], edid[18], edid[19] });
                debug.print(" monitor type {x} size {d} cm x {d} cm\n", .{ edid[20], edid[21], edid[22] });
            },
            else => {
                debug.print("Unknown MBI tag, this shouldn't happen with Simpleboot/Easyboot!---\n", .{});
            },
        }

        var new_tag: [*]u8 = @ptrCast(tag);
        new_tag += ((tag.size + 7) & ~@as(usize, 7));
        tag = @alignCast(@ptrCast(new_tag));
    }
}
