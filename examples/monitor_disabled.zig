const std = @import("std");
const clipboard = @import("clipboard");

// This example is disabled until true event-based monitoring is implemented
// Current implementation was just a polling loop with hard-coded sleep times

pub fn main() !void {
    std.log.err("Event monitoring not yet implemented", .{});
    std.log.err("Use 'zig build run-simple' for single-read clipboard functionality", .{});
}