# Astryon - a microkernel-based operating system project in Zig

Note: not guaranteed to be the project's final name.

## Goals

This project is in its very early stages, so don't expect much yet.

I've started this project to try something new in the world of OS development, after working on a classic monolithic system for some time. I've been wanting to make a microkernel-based system for a while. I've also been wanting to try out Zig, so this was a perfect opportunity to combine both.

- [x] Fully written in Zig
- [x] Simple microkernel that only manages memory, scheduling, and basic IPC
  - [x] Memory management
  - [x] Basic ELF program loading
  - [x] Scheduling
  - [x] Message passing
- [x] IPC system using shared memory ring buffers
- [ ] Init process that can load other services and connect processes to each other (sort of like dbus, in progress)
- [ ] Permission manager, VFS system, etc... all in userspace
- [ ] Decently POSIX-compatible (with a compatibility layer and libc)
- [ ] Window server and GUI system
- [ ] Sandbox most regular userspace processes for security

## Setup

Install [Zig](https://ziglang.org/), version `0.13.0`.

When cloning the repo, make sure to use `git clone --recursive` or run `git submodule update --init` after cloning.

If done correctly, you should have the bootloader cloned as a submodule in the `easyboot` folder. Extract `easyboot/distrib/easyboot-x86_64-linux.tgz` into the `tools` folder (Linux only).

The `tools` directory tree should look like this:
```
    tools
    - bin
    - include
    - share
      iso.sh
      run.sh
      ...
```

On other operating systems, you're going to have to build the bootloader manually.

## Building

Simply run `zig build -p .`

Built binaries will end up in `base/usr/bin`, with the exception of the kernel and core modules, which will be installed in `boot`.

## Running

### Creating the image
Use `tools/iso.sh` to generate an ISO image containing the previously built binaries.

This script assumes that you have the easyboot tool installed at `tools/bin/easyboot`. If this is not the case, you'll have to run easyboot manually. Here's the command:

`/path/to/easyboot -e boot astryon.iso`

### Running the image in QEMU
Then, to run the image in QEMU, you can use the convenience script `tools/run.sh` or run the following command:

`qemu-system-x86_64 -cdrom astryon.iso -serial stdio -enable-kvm`

If you prefer another virtualization system (like Oracle VirtualBox or VMWare), simply import `astryon.iso` into it. Keep in mind you're going to have to do this every time you build a new image.

## License

The bootloader, `easyboot` by [bzt](https://gitlab.com/bztsrc/), is licensed under the GPLv3+ [LICENSE](https://gitlab.com/bztsrc/easyboot/-/blob/main/LICENSE).

The Astryon operating system is licensed under the BSD-2-Clause [LICENSE](LICENSE).
