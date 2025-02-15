const thread = @import("../../thread.zig");

pub const Core = struct { id: u32, thread_list: thread.ThreadList, current_thread: *thread.ThreadControlBlock, idle_thread: thread.ThreadList.Node };
