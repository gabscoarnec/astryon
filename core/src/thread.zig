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
    Sleeping,
};

pub const ThreadControlBlock = struct {
    id: u64,
    address_space: ?vmm.AddressSpace,
    regs: interrupts.InterruptStackFrame,
    state: ThreadState,
    user_priority: u8,

    // Managed by scheduleNewTask(), no need to set manually.
    ticks: u64,
    // Managed by addThreadToPriorityQueue(), no need to set manually.
    current_priority: u32,
    // Managed by startSleep(), no need to set manually.
    sleep_ticks: u64,
};

pub const ThreadList = std.DoublyLinkedList(ThreadControlBlock);

const ALLOCATED_TICKS_PER_TASK = 20;

pub fn enterTask(task: *ThreadControlBlock) noreturn {
    cpu.thisCore().current_thread = task;

    task.ticks = ALLOCATED_TICKS_PER_TASK;

    var table = vmm.readPageTable();

    if (task.address_space) |space| {
        table = space.phys;
    }

    arch.enterTask(&task.regs, vmm.PHYSICAL_MAPPING_BASE, table.address);
}

fn switchTask(regs: *interrupts.InterruptStackFrame, new_task: *ThreadControlBlock) void {
    const core = cpu.thisCore();

    core.current_thread.regs = regs.*;
    regs.* = new_task.regs;

    if (new_task.address_space) |space| {
        if (vmm.readPageTable().address != space.phys.address) vmm.setPageTable(space.phys);
    }

    new_task.ticks = ALLOCATED_TICKS_PER_TASK;

    core.current_thread = new_task;
}

pub fn fetchNewTask(core: *cpu.arch.Core, should_idle_if_not_found: bool) ?*ThreadControlBlock {
    const last = core.active_thread_list.last orelse {
        if (should_idle_if_not_found) {
            return &core.idle_thread.data;
        } else return null;
    };

    const new_task = &last.data;

    removeThreadFromPriorityQueue(core, new_task);

    return new_task;
}

pub fn scheduleNewTask(core: *cpu.arch.Core, regs: *interrupts.InterruptStackFrame, new_thread: *ThreadControlBlock) *ThreadControlBlock {
    if (core.active_thread_list.first) |first| {
        first.data.current_priority +|= 4;
    }

    const current_thread = core.current_thread;

    switchTask(regs, new_thread);

    return current_thread;
}

pub fn preempt(regs: *interrupts.InterruptStackFrame) void {
    const core = cpu.thisCore();

    updateSleepQueue(core);
    while (popSleepQueue(core)) |thread| {
        reviveThread(core, thread);
    }

    core.current_thread.ticks -|= 1;
    if (core.current_thread.ticks == 0) {
        const new_thread = fetchNewTask(core, false) orelse return;
        const current_thread = scheduleNewTask(core, regs, new_thread);
        addThreadToPriorityQueue(core, current_thread);
    }
}

pub fn block(regs: *interrupts.InterruptStackFrame) *ThreadControlBlock {
    const core = cpu.thisCore();

    // fetchNewTask() always returns a thread if should_idle_if_not_found is set to true.
    const new_thread = fetchNewTask(core, true) orelse unreachable;
    const current_thread = scheduleNewTask(core, regs, new_thread);
    current_thread.state = .Blocked;

    return current_thread;
}

pub fn startSleep(regs: *interrupts.InterruptStackFrame, ticks: u64) *ThreadControlBlock {
    const core = cpu.thisCore();

    // fetchNewTask() always returns a thread if should_idle_if_not_found is set to true.
    const new_thread = fetchNewTask(core, true) orelse unreachable;
    const current_thread = scheduleNewTask(core, regs, new_thread);
    current_thread.state = .Sleeping;
    addThreadToSleepQueue(core, current_thread, ticks);

    return current_thread;
}

fn addThreadToSleepQueue(core: *cpu.arch.Core, thread: *ThreadControlBlock, ticks: u64) void {
    thread.sleep_ticks = ticks;

    var it: ?*ThreadList.Node = core.sleeping_thread_list.first;
    while (it) |n| : (it = n.next) {
        if (thread.sleep_ticks <= n.data.sleep_ticks) {
            n.data.sleep_ticks -|= thread.sleep_ticks;
            core.sleeping_thread_list.insertBefore(n, @fieldParentPtr("data", thread));
            return;
        }
        thread.sleep_ticks -|= n.data.sleep_ticks;
    }

    core.sleeping_thread_list.append(@fieldParentPtr("data", thread));
}

pub fn removeThreadFromSleepQueue(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    const node: *ThreadList.Node = @fieldParentPtr("data", thread);

    if (node.next) |n| {
        n.data.sleep_ticks +|= thread.sleep_ticks;
    }

    core.sleeping_thread_list.remove(node);

    reviveThread(core, thread);
}

fn updateSleepQueue(core: *cpu.arch.Core) void {
    const first = core.sleeping_thread_list.first orelse return;

    first.data.sleep_ticks -|= 1;
}

fn popSleepQueue(core: *cpu.arch.Core) ?*ThreadControlBlock {
    const first = core.sleeping_thread_list.first orelse return null;

    if (first.data.sleep_ticks == 0) {
        core.sleeping_thread_list.remove(first);
        return &first.data;
    }

    return null;
}

pub fn reviveThread(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    thread.state = .Running;
    addThreadToPriorityQueue(core, thread);
}

var next_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

pub fn createThreadControlBlock(allocator: *pmm.FrameAllocator) !*ThreadControlBlock {
    const frame = try pmm.allocFrame(allocator);

    const node: *ThreadList.Node = @ptrFromInt(frame.virtualAddress(vmm.PHYSICAL_MAPPING_BASE));
    const thread = &node.data;
    thread.id = next_id.fetchAdd(1, .seq_cst);
    thread.address_space = null;
    thread.regs = std.mem.zeroes(@TypeOf(thread.regs));
    thread.state = .Inactive;
    thread.user_priority = 127;

    return thread;
}

pub fn addThreadToPriorityQueue(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    thread.current_priority = thread.user_priority;

    var it: ?*ThreadList.Node = core.active_thread_list.first;
    while (it) |n| : (it = n.next) {
        if (thread.current_priority <= n.data.current_priority) {
            n.data.current_priority -|= thread.current_priority;
            core.active_thread_list.insertBefore(n, @fieldParentPtr("data", thread));
            return;
        }
        thread.current_priority -|= n.data.current_priority;
    }

    core.active_thread_list.append(@fieldParentPtr("data", thread));
}

fn removeThreadFromPriorityQueue(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    const node: *ThreadList.Node = @fieldParentPtr("data", thread);

    if (node.next) |n| {
        n.data.current_priority +|= thread.current_priority;
    }

    core.active_thread_list.remove(node);
}
