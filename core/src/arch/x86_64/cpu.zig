const thread = @import("../../thread.zig");

pub const Core = struct { id: u32, active_thread_list: thread.ThreadList, sleeping_thread_list: thread.ThreadList, current_thread: *thread.ThreadControlBlock, idle_thread: thread.ThreadList.Node };
