const std = @import("std");
const clipboard = @import("clipboard");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.log.info("Clipboard Write Test", .{});
    std.log.info("Writing text to clipboard...", .{});
    
    var clipboard_instance = try clipboard.Clipboard.init(allocator);
    defer clipboard_instance.deinit();
    
    const test_text = "Hello from nclip2 write test!";
    std.log.info("About to write to clipboard: '{s}'", .{test_text});
    
    try clipboard_instance.write(test_text, .text);
    
    std.log.info("Write call completed - background process serving clipboard", .{});
}