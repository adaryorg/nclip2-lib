const std = @import("std");
const clipboard = @import("clipboard");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.log.info("Image Clipboard Write Test", .{});
    
    // Read the existing test image file
    const image_path = "../image.png";
    const image_data = std.fs.cwd().readFileAlloc(allocator, image_path, 10 * 1024 * 1024) catch |err| {
        std.log.err("Failed to read image file {s}: {}", .{ image_path, err });
        return err;
    };
    defer allocator.free(image_data);
    
    std.log.info("About to write image to clipboard: {} bytes", .{image_data.len});
    
    var clipboard_instance = try clipboard.Clipboard.init(allocator);
    defer clipboard_instance.deinit();
    
    try clipboard_instance.write(image_data, .image);
    
    std.log.info("Image write call completed - background process serving clipboard", .{});
}