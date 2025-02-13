pub fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub fn outb(port: u16, value: u8) void {
    return asm volatile ("outb %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{al}" (value),
    );
}

pub fn inw(port: u16) u16 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u16),
        : [port] "N{dx}" (port),
    );
}

pub fn outw(port: u16, value: u16) void {
    return asm volatile ("outw %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{ax}" (value),
    );
}

pub fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u16),
        : [port] "N{dx}" (port),
    );
}

pub fn outl(port: u16, value: u32) void {
    return asm volatile ("outw %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{eax}" (value),
    );
}
