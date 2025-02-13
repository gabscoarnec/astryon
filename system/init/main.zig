fn syscall(num: u64, arg: u64) void {
    asm volatile ("int $66"
        :
        : [num] "{rax}" (num),
          [arg] "{rdi}" (arg),
    );
}

export fn _start(base: u64) callconv(.C) noreturn {
    syscall(0, base);

    while (true) {}
}
