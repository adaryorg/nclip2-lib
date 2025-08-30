const std = @import("std");
const clipboard = @import("clipboard");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const text_to_write = "Hello from X11 clipboard! This text was written by the nclip2 library.";
    
    std.log.info("X11 Clipboard Writer", .{});
    std.log.info("Writing text to clipboard: {s}", .{text_to_write});
    
    clipboard.writeClipboardText(allocator, text_to_write) catch |err| {
        switch (err) {
            clipboard.ClipboardError.UnsupportedPlatform => {
                std.log.err("Error: Not running on X11", .{});
                return;
            },
            else => {
                std.log.err("Failed to write to clipboard: {}", .{err});
                return err;
            },
        }
    };
    
    std.log.info("Successfully wrote text to clipboard!", .{});
    std.log.info("You can now paste the text in other applications.", .{});
}