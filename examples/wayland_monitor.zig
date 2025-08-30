const std = @import("std");
const clipboard = @import("clipboard");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.log.info("Wayland Event-Based Clipboard Monitor", .{});
    std.log.info("Waiting for clipboard changes (will block until events)...", .{});
    std.log.info("Press Ctrl+C to exit", .{});
    std.log.info("", .{});
    
    var monitor = clipboard.startWaylandEventMonitoring(allocator) catch |err| {
        switch (err) {
            clipboard.ClipboardError.UnsupportedPlatform => {
                std.log.err("Error: This example only works on Wayland. Detected platform is not Wayland.", .{});
                std.log.err("Use wayland_read.zig or x11_read.zig for manual polling instead.", .{});
                return;
            },
            else => {
                std.log.err("Failed to initialize Wayland monitoring: {}", .{err});
                return err;
            },
        }
    };
    defer monitor.deinit();
    
    // True event-driven loop: blocks until Wayland events arrive
    while (true) {
        var data = monitor.waitForClipboardChange() catch |err| {
            switch (err) {
                clipboard.ClipboardError.NoData => {
                    std.log.info("Clipboard cleared", .{});
                    continue;
                },
                else => {
                    std.log.err("Error waiting for clipboard change: {}", .{err});
                    continue;
                },
            }
        };
        defer data.deinit();
        
        // Display the clipboard change
        switch (data.format) {
            .text => {
                const text = data.asText() catch continue;
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
}