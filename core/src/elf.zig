const std = @import("std");
const target = @import("builtin").target;
const vmm = @import("arch/vmm.zig");
const platform = @import("arch/platform.zig");
const pmm = @import("pmm.zig");
const debug = @import("arch/debug.zig");

const ELFMAG = "\x7fELF";
const SELFMAG = 4;
const EI_CLASS = 4; // File class byte index
const ELFCLASS64 = 2; // 64-bit objects
const EI_DATA = 5; // Data encoding byte index
const ELFDATA2LSB = 1; // 2's complement, little endian
const ET_EXEC = 2; // Executable file
const PT_LOAD = 1; // Loadable program segment
const EM_MACH = switch (target.cpu.arch) {
    .x86_64 => 62,
    else => @compileError("unsupported architecture"),
};

const Elf64_Ehdr align(8) = packed struct {
    e_ident: u128, // Magic number and other info
    e_type: u16, // Object file type
    e_machine: u16, // Architecture
    e_version: u32, // Object file version
    e_entry: u64, // Entry point virtual address
    e_phoff: u64, // Program header table file offset
    e_shoff: u64, // Section header table file offset
    e_flags: u32, // Processor-specific flags
    e_ehsize: u16, // ELF header size in bytes
    e_phentsize: u16, // Program header table entry size
    e_phnum: u16, // Program header table entry count
    e_shentsize: u16, // Section header table entry size
    e_shnum: u16, // Section header table entry count
    e_shstrndx: u16, // Section header string table index
};

const Elf64_Phdr align(8) = packed struct {
    p_type: u32, // Segment type
    p_flags: u32, // Segment flags
    p_offset: u64, // Segment file offset
    p_vaddr: u64, // Segment virtual address
    p_paddr: u64, // Segment physical address
    p_filesz: u64, // Segment size in file
    p_memsz: u64, // Segment size in memory
    p_align: u64, // Segment alignment
};

const ElfError = error{
    InvalidExecutable,
};

fn canExecuteSegment(flags: u32) bool {
    return (flags & 1) > 0;
}

fn canWriteSegment(flags: u32) bool {
    return (flags & 2) > 0;
}

pub fn loadElf(allocator: *pmm.FrameAllocator, space: vmm.AddressSpace, base_address: pmm.PhysFrame) !usize {
    const address = base_address.virtualAddress(vmm.PHYSICAL_MAPPING_BASE);

    const elf_header: *Elf64_Ehdr = @ptrFromInt(address);

    debug.print("ELF header: {}\n", .{elf_header});

    const e_ident: [*]u8 = @ptrFromInt(address);

    if (!std.mem.eql(u8, e_ident[0..SELFMAG], ELFMAG[0..SELFMAG])) {
        debug.print("Error while loading ELF: ELF header has no valid magic\n", .{});
        return error.InvalidExecutable;
    }

    if (e_ident[EI_CLASS] != ELFCLASS64) {
        debug.print("Error while loading ELF: ELF object is not 64-bit\n", .{});
        return error.InvalidExecutable;
    }

    if (e_ident[EI_DATA] != ELFDATA2LSB) {
        debug.print("Error while loading ELF: ELF object is not 2's complement little-endian\n", .{});
        return error.InvalidExecutable;
    }

    if (elf_header.e_type != ET_EXEC) {
        debug.print("Error while loading ELF: ELF object is not an executable\n", .{});
        return error.InvalidExecutable;
    }

    if (elf_header.e_machine != EM_MACH) {
        debug.print("Error while loading ELF: ELF object's target architecture does not match the current one\n", .{});
        return error.InvalidExecutable;
    }

    if (elf_header.e_phnum == 0) {
        debug.print("Error while loading ELF: ELF object has no program headers\n", .{});
        return error.InvalidExecutable;
    }

    var i: usize = 0;
    var program_header: *align(1) Elf64_Phdr = @ptrFromInt(address + elf_header.e_phoff);

    while (i < elf_header.e_phnum) {
        if (program_header.p_type == PT_LOAD) {
            debug.print("ELF: Loading segment (offset={d}, base={x}, filesize={d}, memsize={d})\n", .{ program_header.p_offset, program_header.p_vaddr, program_header.p_filesz, program_header.p_memsz });

            const vaddr_diff: u64 = @rem(program_header.p_vaddr, platform.PAGE_SIZE);
            const base_vaddr: u64 = program_header.p_vaddr - vaddr_diff;

            var flags: u32 = @intFromEnum(vmm.Flags.User) | @intFromEnum(vmm.Flags.NoExecute);
            if (canWriteSegment(program_header.p_flags)) flags |= @intFromEnum(vmm.Flags.ReadWrite);
            if (canExecuteSegment(program_header.p_flags)) flags &= ~@as(u32, @intFromEnum(vmm.Flags.NoExecute));

            // Allocate physical memory for the segment
            try vmm.allocAndMap(allocator, space, base_vaddr, try std.math.divCeil(usize, program_header.p_memsz + vaddr_diff, platform.PAGE_SIZE), flags);

            try vmm.memsetUser(space, vmm.PHYSICAL_MAPPING_BASE, base_vaddr, 0, vaddr_diff);

            try vmm.copyToUser(space, vmm.PHYSICAL_MAPPING_BASE, program_header.p_vaddr, @ptrFromInt(address + program_header.p_offset), program_header.p_filesz);

            const bss_size = program_header.p_memsz - program_header.p_filesz;

            try vmm.memsetUser(space, vmm.PHYSICAL_MAPPING_BASE, program_header.p_vaddr + program_header.p_filesz, 0, bss_size);
        } else {
            debug.print("ELF: Encountered non-loadable program header, skipping\n", .{});
        }

        i += 1;

        const new_address = address + elf_header.e_phoff + (i * elf_header.e_phentsize);

        program_header = @ptrFromInt(new_address);
    }

    return elf_header.e_entry;
}

pub fn allocateStack(allocator: *pmm.FrameAllocator, space: vmm.AddressSpace, stack_top: usize, stack_size: usize) !usize {
    const pages = try std.math.divCeil(usize, stack_size, platform.PAGE_SIZE);
    const stack_bottom = stack_top - (pages * platform.PAGE_SIZE);

    try vmm.allocAndMap(allocator, space, stack_bottom, pages, @intFromEnum(vmm.Flags.ReadWrite) | @intFromEnum(vmm.Flags.User) | @intFromEnum(vmm.Flags.NoExecute));

    return stack_top - 16;
}
