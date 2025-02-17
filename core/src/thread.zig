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
    mapper: ?vmm.MemoryMapper,
    regs: interrupts.InterruptStackFrame,
    state: ThreadState,

    ticks: u64,

    user_priority: u8,
    current_priority: u32,
};

pub const ThreadList = std.DoublyLinkedList(ThreadControlBlock);

const ALLOCATED_TICKS_PER_TASK = 20;

pub fn enterTask(task: *ThreadControlBlock) noreturn {
    cpu.thisCore().current_thread = task;

    task.ticks = ALLOCATED_TICKS_PER_TASK;

    var directory = vmm.readPageDirectory();

    if (task.mapper) |mapper| {
        directory = mapper.phys;
    }

    arch.enterTask(&task.regs, vmm.PHYSICAL_MAPPING_BASE, directory.address);
}

pub fn switchTask(regs: *interrupts.InterruptStackFrame, new_task: *ThreadControlBlock) void {
    const core = cpu.thisCore();

    core.current_thread.regs = regs.*;
    regs.* = new_task.regs;

    if (new_task.mapper) |mapper| {
        if (vmm.readPageDirectory().address != mapper.phys.address) vmm.setPageDirectory(mapper.phys);
    }

    new_task.ticks = ALLOCATED_TICKS_PER_TASK;

    core.current_thread = new_task;
}

pub fn fetchNewTask(core: *cpu.arch.Core, should_idle_if_not_found: bool) ?*ThreadControlBlock {
    const last = core.thread_list.last orelse {
        if (should_idle_if_not_found) {
            return &core.idle_thread;
        } else return null;
    };

    const new_task = &last.data;

    removeThreadFromPriorityQueue(core, new_task);

    return new_task;
}

pub fn scheduleNewTask(core: *cpu.arch.Core, regs: *interrupts.InterruptStackFrame, new_thread: *ThreadControlBlock) *ThreadControlBlock {
    if (core.thread_list.first) |first| {
        first.data.current_priority +|= 4;
    }

    const current_thread = core.current_thread;

    switchTask(regs, new_thread);

    return current_thread;
}

pub fn preempt(regs: *interrupts.InterruptStackFrame) void {
    const core = cpu.thisCore();

    core.current_thread.ticks -|= 1;
    if (core.current_thread.ticks == 0) {
        const new_thread = fetchNewTask(core, false) orelse return;
        const current_thread = scheduleNewTask(core, regs, new_thread);
        addThreadToPriorityQueue(core, current_thread);
    }
}

var next_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

pub fn addThreadToScheduler(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    addThreadToPriorityQueue(core, thread);
}

pub fn createThreadControlBlock(allocator: *pmm.FrameAllocator) !*ThreadControlBlock {
    const frame = try pmm.allocFrame(allocator);

    const node: *ThreadList.Node = @ptrFromInt(frame.virtualAddress(vmm.PHYSICAL_MAPPING_BASE));
    const thread = &node.data;
    thread.id = next_id.fetchAdd(1, .seq_cst);
    thread.mapper = null;
    thread.regs = std.mem.zeroes(@TypeOf(thread.regs));
    thread.state = .Inactive;
    thread.user_priority = 0;

    return thread;
}

pub fn addThreadToPriorityQueue(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    thread.current_priority = thread.user_priority;

    var it: ?*ThreadList.Node = core.thread_list.first;
    while (it) |n| : (it = n.next) {
        if (thread.current_priority <= n.data.current_priority) {
            n.data.current_priority -|= thread.current_priority;
            core.thread_list.insertBefore(n, @fieldParentPtr("data", thread));
            return;
        }
        thread.current_priority -|= n.data.current_priority;
    }

    core.thread_list.append(@fieldParentPtr("data", thread));
}

pub fn removeThreadFromPriorityQueue(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    const node: *ThreadList.Node = @fieldParentPtr("data", thread);

    if (node.next) |n| {
        n.data.current_priority +|= thread.current_priority;
    }

    core.thread_list.remove(node);
}
