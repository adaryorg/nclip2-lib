const std = @import("std");
const clipboard = @import("clipboard");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.log.info("X11 Clipboard Reader (45 second test)", .{});
    std.log.info("Reading clipboard every second...", .{});
    std.log.info("", .{});
    
    var count: u32 = 0;
    while (count < 45) : (count += 1) {
        // Try to get clipboard data with automatic format detection
        var data = clipboard.readClipboardData(allocator) catch |err| {
            switch (err) {
                clipboard.ClipboardError.NoData => {
                    std.log.info("[{}] Clipboard is empty", .{count});
                },
                clipboard.ClipboardError.UnsupportedPlatform => {
                    std.log.info("[{}] Error: Not running on X11", .{count});
                    return;
                },
                else => {
                    std.log.info("[{}] Error reading clipboard: {}", .{ count, err });
                },
            }
            std.Thread.sleep(1000 * std.time.ns_per_ms);
            continue;
        };
        defer data.deinit();
        
        // Display based on format
        switch (data.format) {
            .text => {
                const text = try data.asText();
                const display_text = if (text.len > 60) text[0..57] ++ "..." else text;
                std.log.info("[{}] Text: {s}", .{ count, display_text });
            },
            .html => {
                const html = data.data;
                const display_html = if (html.len > 60) html[0..57] ++ "..." else html;
                std.log.info("[{}] HTML ({} bytes): {s}", .{ count, html.len, display_html });
            },
            .image => {
                std.log.info("[{}] Image: {} bytes", .{ count, data.data.len });
            },
            .rtf => {
                std.log.info("[{}] RTF: {} bytes", .{ count, data.data.len });
            },
        }
        
        std.Thread.sleep(1000 * std.time.ns_per_ms);
    }
}