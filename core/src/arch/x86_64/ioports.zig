pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub inline fn outb(port: u16, value: u8) void {
    return asm volatile ("outb %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{al}" (value),
    );
}

pub inline fn inw(port: u16) u16 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u16),
        : [port] "N{dx}" (port),
    );
}

pub inline fn outw(port: u16, value: u16) void {
    return asm volatile ("outw %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{ax}" (value),
    );
}

pub inline fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u16),
        : [port] "N{dx}" (port),
    );
}

pub inline fn outl(port: u16, value: u32) void {
    return asm volatile ("outw %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{eax}" (value),
    );
}
