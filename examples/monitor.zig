const std = @import("std");
const clipboard = @import("clipboard");

fn onClipboardChange(data: clipboard.ClipboardData) void {
    switch (data.format) {
        .text => {
            const text = data.asText() catch return;
            const display_text = if (text.len > 60) text[0..57] ++ "..." else text;
            std.log.info("Clipboard changed - Text: {s}", .{display_text});
        },
        .html => {
            const html = data.data;
            const display_html = if (html.len > 60) html[0..57] ++ "..." else html;
            std.log.info("Clipboard changed - HTML ({} bytes): {s}", .{ html.len, display_html });
        },
        .image => {
            std.log.info("Clipboard changed - Image: {} bytes", .{data.data.len});
        },
        .rtf => {
            std.log.info("Clipboard changed - RTF: {} bytes", .{data.data.len});
        },
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.log.info("True Event-Based Clipboard Monitor", .{});
    std.log.info("Waiting for clipboard changes (will block until events)...", .{});
    std.log.info("Press Ctrl+C to exit", .{});
    std.log.info("", .{});
    
    var clipboard_instance = try clipboard.Clipboard.init(allocator);
    defer clipboard_instance.deinit();
    
    try clipboard_instance.startMonitoring(onClipboardChange);
    defer clipboard_instance.stopMonitoring();
    
    // True event-driven loop: blocks until Wayland events arrive
    while (true) {
        clipboard_instance.processEvents(); // This blocks until clipboard change events
    }
}