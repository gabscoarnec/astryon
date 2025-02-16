const std = @import("std");
const vmm = @import("arch/vmm.zig").arch;
const interrupts = @import("arch/interrupts.zig").arch;
pub const arch = @import("arch/thread.zig").arch;
const pmm = @import("pmm.zig");
const cpu = @import("arch/cpu.zig");

pub const ThreadState = enum {
    Inactive,
    Running,
    Blocked,
};

pub const ThreadControlBlock = struct {
    id: u64,
    directory: ?*vmm.PageDirectory,
    regs: interrupts.InterruptStackFrame,
    state: ThreadState,

    ticks: u64,
};

pub const ThreadList = std.DoublyLinkedList(ThreadControlBlock);

const ALLOCATED_TICKS_PER_TASK = 20;

pub fn enterTask(task: *ThreadControlBlock) noreturn {
    cpu.thisCore().current_thread = task;

    task.ticks = ALLOCATED_TICKS_PER_TASK;

    var directory = vmm.readPageDirectory();

    if (task.directory) |dir| {
        directory = vmm.getPhysicalPageDirectory(dir);
    }

    arch.enterTask(&task.regs, vmm.PHYSICAL_MAPPING_BASE, @ptrCast(directory));
}

pub fn switchTask(regs: *interrupts.InterruptStackFrame, new_task: *ThreadControlBlock) void {
    const core = cpu.thisCore();

    core.current_thread.regs = regs.*;
    regs.* = new_task.regs;

    if (new_task.directory) |directory| {
        if (vmm.readPageDirectory() != directory) vmm.setPageDirectory(vmm.getPhysicalPageDirectory(directory));
    }

    new_task.ticks = ALLOCATED_TICKS_PER_TASK;

    core.current_thread = new_task;
}

pub fn scheduleNewTask(regs: *interrupts.InterruptStackFrame) void {
    const core = cpu.thisCore();

    const new_task = core.thread_list.popFirst() orelse return;
    core.thread_list.append(new_task);

    switchTask(regs, &new_task.data);
}

pub fn preempt(regs: *interrupts.InterruptStackFrame) void {
    const core = cpu.thisCore();

    core.current_thread.ticks -= 1;
    if (core.current_thread.ticks == 0) {
        scheduleNewTask(regs);
    }
}

var next_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

pub fn addThreadToScheduler(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    core.thread_list.append(@fieldParentPtr("data", thread));
}

pub fn createThreadControlBlock(allocator: *pmm.FrameAllocator) !*ThreadControlBlock {
    const frame = try pmm.allocFrame(allocator);

    const node: *ThreadList.Node = @ptrFromInt(frame.virtualAddress(vmm.PHYSICAL_MAPPING_BASE));
    const thread = &node.data;
    thread.id = next_id.fetchAdd(1, .seq_cst);
    thread.directory = null;
    thread.regs = std.mem.zeroes(@TypeOf(thread.regs));
    thread.state = .Inactive;

    return thread;
}
