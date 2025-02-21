const std = @import("std");
const vmm = @import("arch/vmm.zig").arch;
const interrupts = @import("arch/interrupts.zig").arch;
pub const arch = @import("arch/thread.zig").arch;
const pmm = @import("pmm.zig");
const cpu = @import("arch/cpu.zig");
const locking = @import("lib/spinlock.zig");

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

    // Managed by addThreadToGlobalList(), no need to set manually.
    tag: GlobalThreadList.Node,
    // Managed by scheduleNewThread(), no need to set manually.
    ticks: u64,
    // Managed by addThreadToPriorityQueue(), no need to set manually.
    current_priority: u32,
    // Managed by startSleep(), no need to set manually.
    sleep_ticks: u64,
};

pub const ThreadList = std.DoublyLinkedList(ThreadControlBlock);

const ALLOCATED_TICKS_PER_THREAD = 20;

/// Starts the scheduler by running a thread. This function never returns.
pub fn enterThread(thread: *ThreadControlBlock) noreturn {
    cpu.thisCore().current_thread = thread;

    thread.ticks = ALLOCATED_TICKS_PER_THREAD;

    var table = vmm.readPageTable();

    if (thread.address_space) |space| {
        table = space.phys;
    }

    thread.state = .Running;

    // If the stack is in user memory, then we need a pointer to its higher-half version. If it's already in kernel memory, no need to do anything.
    var base: usize = 0;
    if (arch.readStackPointer() < vmm.PHYSICAL_MAPPING_BASE) {
        base += vmm.PHYSICAL_MAPPING_BASE;
    }

    arch.enterThread(&thread.regs, base, table.address);
}

/// Updates the processor state to run a new thread.
fn switchThread(regs: *interrupts.InterruptStackFrame, new_thread: *ThreadControlBlock) void {
    const core = cpu.thisCore();

    core.current_thread.regs = regs.*;
    regs.* = new_thread.regs;

    if (new_thread.address_space) |space| {
        if (vmm.readPageTable().address != space.phys.address) vmm.setPageTable(space.phys);
    }

    new_thread.ticks = ALLOCATED_TICKS_PER_THREAD;

    core.current_thread = new_thread;
}

/// Changes the running thread to a new one and returns the previous one.
pub fn scheduleNewThread(core: *cpu.arch.Core, regs: *interrupts.InterruptStackFrame, new_thread: *ThreadControlBlock) *ThreadControlBlock {
    if (core.active_thread_list.first) |first| {
        first.data.current_priority +|= 4;
    }

    const current_thread = core.current_thread;

    switchThread(regs, new_thread);

    return current_thread;
}

/// Called on every timer interrupt.
///
/// Updates the core's sleep queue, checks if the running thread's time
/// is up, and if it is, schedules a new one.
pub fn preempt(regs: *interrupts.InterruptStackFrame) void {
    const core = cpu.thisCore();

    updateSleepQueue(core);
    while (popSleepQueue(core)) |thread| {
        reviveThread(core, thread);
    }

    core.current_thread.ticks -|= 1;
    if (core.current_thread.ticks == 0) {
        const new_thread = fetchNewThread(core, false) orelse return;
        const current_thread = scheduleNewThread(core, regs, new_thread);
        addThreadToPriorityQueue(core, current_thread);
    }
}

/// Sets the current thread's state to "Blocked" and schedules a new one to replace it.
pub fn block(regs: *interrupts.InterruptStackFrame) *ThreadControlBlock {
    const core = cpu.thisCore();

    // fetchNewThread() always returns a thread if should_idle_if_not_found is set to true.
    const new_thread = fetchNewThread(core, true) orelse unreachable;
    const current_thread = scheduleNewThread(core, regs, new_thread);
    current_thread.state = .Blocked;

    return current_thread;
}

/// Puts the current thread to sleep, adding it to the sleep queue, and schedules a new one to replace it.
pub fn startSleep(regs: *interrupts.InterruptStackFrame, ticks: u64) *ThreadControlBlock {
    const core = cpu.thisCore();

    // fetchNewThread() always returns a thread if should_idle_if_not_found is set to true.
    const new_thread = fetchNewThread(core, true) orelse unreachable;
    const current_thread = scheduleNewThread(core, regs, new_thread);
    current_thread.state = .Sleeping;
    addThreadToSleepQueue(core, current_thread, ticks);

    return current_thread;
}

var next_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

/// Allocates a physical frame and create a new thread control block inside it, adding
/// it to the global thread list.
pub fn createThreadControlBlock(allocator: *pmm.FrameAllocator) !*ThreadControlBlock {
    const frame = try pmm.allocFrame(allocator);

    const node: *ThreadList.Node = @ptrFromInt(frame.virtualAddress(vmm.PHYSICAL_MAPPING_BASE));
    const thread = &node.data;
    thread.id = next_id.fetchAdd(1, .seq_cst);
    thread.address_space = null;
    thread.regs = std.mem.zeroes(@TypeOf(thread.regs));
    thread.state = .Inactive;
    thread.user_priority = 127;

    addThreadToGlobalList(thread);

    return thread;
}

// The "priority queue" is the main scheduling queue for each core. In the code, it is referred to as "core.active_thread_list".
// In the priority queue, we store all threads currently waiting to run, sorted by priority.
// Threads are added to the list with an initial priority equal to their own "user_priority", but every time a new thread
// is scheduled, every other thread waiting to run that didn't get to run that time gets their priority incremented by 4.
//
// In the priority queue, threads are not stored with their absolute priority value, but their relative priority instead (that is,
// how much more priority they have than the previous thread). That way, all threads' priorities can be incremented by adding a number
// to the lowest priority thread.

/// Adds a thread to the specified core's priority queue.
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

/// Removes a thread from the specified core's priority queue.
///
/// This function is private because threads are automatically removed
/// when scheduled, and that's the only instance when they should be removed.
fn removeThreadFromPriorityQueue(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    const node: *ThreadList.Node = @fieldParentPtr("data", thread);

    if (node.next) |n| {
        n.data.current_priority +|= thread.current_priority;
    }

    core.active_thread_list.remove(node);
}

/// Finds the thread with the highest priority, removes it from the specified core's
/// priority queue, and returns it so that it can be scheduled.
///
/// This function's behaviour when there are no threads waiting to be run depends on the value
/// passed to "should_idle_if_not_found". If this value is true (the currently running thread cannot continue to run,
/// because for example it wants to block), we return the core's idle thread.
/// Otherwise, we return null, signalling that the thread currently running should continue to run
/// until a new thread is available.
pub fn fetchNewThread(core: *cpu.arch.Core, should_idle_if_not_found: bool) ?*ThreadControlBlock {
    const last = core.active_thread_list.last orelse {
        if (should_idle_if_not_found) {
            return &core.idle_thread.data;
        } else return null;
    };

    const new_thread = &last.data;

    removeThreadFromPriorityQueue(core, new_thread);

    return new_thread;
}

/// Adds a previously blocked or sleeping thread back to the specified core's priority queue.
pub fn reviveThread(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    thread.state = .Running;
    addThreadToPriorityQueue(core, thread);
}

// The "sleep queue" is the secondary scheduling queue for each core. In the code, it is referred to as "core.sleeping_thread_list".
// In the sleep queue, we store all threads currently sleeping on this core, sorted by the time remaining until they wake.
//
// In the sleep queue, threads are not stored with the absolute time remaining, but the relative time remaining instead (that is,
// how much more time they have left to sleep than the previous thread). That way, all threads' time remaining values can be decremented
// by one by doing this to the first thread in the list (see updateSleepQueue()).

/// Adds a new thread to the specified core's sleep queue, with the specified ticks left to wake.
///
/// This function is private because you should not call it directly, use startSleep() instead, which
/// also schedules a new thread to replace the one going to sleep.
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

/// Removes a new thread from the specified core's sleep queue and adds it back to the priority queue.
pub fn removeThreadFromSleepQueue(core: *cpu.arch.Core, thread: *ThreadControlBlock) void {
    const node: *ThreadList.Node = @fieldParentPtr("data", thread);

    if (node.next) |n| {
        n.data.sleep_ticks +|= thread.sleep_ticks;
    }

    core.sleeping_thread_list.remove(node);

    reviveThread(core, thread);
}

/// Decrements the time left for all threads in a core's sleep queue to wake by one.
/// As mentioned earlier, since the time left is stored relative to the other threads,
/// decrementing the time left for the first thread is enough to change it for all threads.
fn updateSleepQueue(core: *cpu.arch.Core) void {
    const first = core.sleeping_thread_list.first orelse return;

    first.data.sleep_ticks -|= 1;
}

/// If a thread in the sleep queue has finished its sleeping time, removes it from the queue and returns it.
/// Otherwise, returns null.
///
/// This function should be called in a loop until it returns null,
/// since multiple threads could wake up at the same time.
///
/// This function also does not revive the threads; you must call reviveThread() yourself.
fn popSleepQueue(core: *cpu.arch.Core) ?*ThreadControlBlock {
    const first = core.sleeping_thread_list.first orelse return null;

    if (first.data.sleep_ticks == 0) {
        core.sleeping_thread_list.remove(first);
        return &first.data;
    }

    return null;
}

// The global thread list is only used to keep track of threads so they can be looked up when needed.
// It does not perform any scheduling functions, unlike the core-specific lists.
// While threads can move in and out of scheduling-related thread lists at will, and can even remain outside of them (example: blocked threads),
// threads should be added to this list on creation and never removed until destruction, with the exception of core-specific idle threads, which for now
// will not be added to this list, as they all have the same ID and there is little a user process can do with them.
// Since this list is shared by all cores, locking is needed.

pub const GlobalThreadList = std.DoublyLinkedList(u8);

var global_thread_list_lock: locking.SpinLock = .{};
var global_thread_list: GlobalThreadList = .{};

/// Adds a newly created thread to the global list.
pub fn addThreadToGlobalList(thread: *ThreadControlBlock) void {
    global_thread_list_lock.lock();
    defer global_thread_list_lock.unlock();

    global_thread_list.append(&thread.tag);
}

/// Finds the thread with a matching thread ID by iterating through the global list.
pub fn lookupThreadById(id: u64) ?*ThreadControlBlock {
    global_thread_list_lock.lock();
    defer global_thread_list_lock.unlock();

    var it: ?*GlobalThreadList.Node = global_thread_list.first;
    while (it) |n| : (it = n.next) {
        const thread: *ThreadControlBlock = @fieldParentPtr("tag", n);
        if (thread.id == id) return thread;
    }

    return null;
}
