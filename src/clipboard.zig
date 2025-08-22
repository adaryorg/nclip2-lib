const std = @import("std");
const builtin = @import("builtin");

/// Errors that can occur during clipboard operations
pub const ClipboardError = error{
    InitializationFailed,
    ReadFailed,
    WriteFailed,
    UnsupportedPlatform,
    OutOfMemory,
    InvalidData,
    Timeout,
    NoData,
};

/// Supported clipboard data formats
pub const ClipboardFormat = enum {
    text,
    image,
    html,
    rtf,
    
    /// Returns the MIME type for this clipboard format
    pub fn mimeType(self: ClipboardFormat) []const u8 {
        return switch (self) {
            .text => "text/plain",
            .image => "image/png",
            .html => "text/html",
            .rtf => "application/rtf",
        };
    }
};

/// Container for clipboard data with format information
pub const ClipboardData = struct {
    data: []u8,
    format: ClipboardFormat,
    allocator: std.mem.Allocator,
    
    /// Frees the allocated clipboard data
    pub fn deinit(self: *ClipboardData) void {
        self.allocator.free(self.data);
    }
    
    /// Returns the data as text, or InvalidData error if format is not text
    pub fn asText(self: *const ClipboardData) ![]const u8 {
        if (self.format != .text) {
            return ClipboardError.InvalidData;
        }
        return self.data;
    }
    
    /// Returns the data as image bytes, or InvalidData error if format is not image
    pub fn asImage(self: *const ClipboardData) ![]const u8 {
        if (self.format != .image) {
            return ClipboardError.InvalidData;
        }
        return self.data;
    }
};

/// Callback function type for clipboard change monitoring
pub const ClipboardChangeCallback = *const fn (data: ClipboardData) void;

fn getBackendModule() type {
    return switch (builtin.os.tag) {
        .linux => if (@import("builtin").link_libc) 
            @import("backends/linux.zig") 
        else 
            @import("backends/fallback.zig"),
        .macos => @import("backends/macos.zig"),
        else => @import("backends/fallback.zig"),
    };
}

const Backend = getBackendModule();

/// Cross-platform clipboard manager providing access to system clipboard
pub const Clipboard = struct {
    backend: Backend.ClipboardBackend,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !Clipboard {
        return Clipboard{
            .backend = try Backend.ClipboardBackend.init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Clipboard) void {
        self.backend.deinit();
    }
    
    pub fn read(self: *Clipboard, format: ClipboardFormat) !ClipboardData {
        return self.backend.read(format);
    }
    
    pub fn write(self: *Clipboard, data: []const u8, format: ClipboardFormat) !void {
        return self.backend.write(data, format);
    }
    
    pub fn startMonitoring(self: *Clipboard, callback: ClipboardChangeCallback) !void {
        return self.backend.startMonitoring(callback);
    }
    
    pub fn stopMonitoring(self: *Clipboard) void {
        self.backend.stopMonitoring();
    }
    
    pub fn isAvailable(self: *Clipboard, format: ClipboardFormat) bool {
        return self.backend.isAvailable(format);
    }
    
    pub fn getAvailableFormats(self: *Clipboard, allocator: std.mem.Allocator) ![]ClipboardFormat {
        return self.backend.getAvailableFormats(allocator);
    }
    
    pub fn clear(self: *Clipboard) !void {
        return self.backend.clear();
    }
    
    pub fn processEvents(self: *Clipboard) void {
        return self.backend.processEvents();
    }
};

pub fn readClipboardData(allocator: std.mem.Allocator) !ClipboardData {
    if (@hasDecl(Backend, "getClipboardDataAuto")) {
        return Backend.getClipboardDataAuto(allocator);
    }
    
    var clip = try Clipboard.init(allocator);
    defer clip.deinit();
    
    clip.processEvents();
    
    const formats = try clip.getAvailableFormats(allocator);
    defer allocator.free(formats);
    
    if (formats.len == 0) {
        return ClipboardError.NoData;
    }
    
    const priority_formats = [_]ClipboardFormat{ .text, .html, .image, .rtf };
    
    for (priority_formats) |preferred_format| {
        for (formats) |available_format| {
            if (available_format == preferred_format) {
                return clip.read(preferred_format) catch continue;
            }
        }
    }
    
    return clip.read(formats[0]);
}

pub fn getAvailableClipboardFormats(allocator: std.mem.Allocator) ![]ClipboardFormat {
    if (@hasDecl(Backend, "getAvailableClipboardFormats")) {
        return Backend.getAvailableClipboardFormats(allocator);
    }
    
    var clip = try Clipboard.init(allocator);
    defer clip.deinit();
    return clip.getAvailableFormats(allocator);
}

test "clipboard basic functionality" {
    const allocator = std.testing.allocator;
    
    var clipboard = Clipboard.init(allocator) catch |err| switch (err) {
        ClipboardError.InitializationFailed => return, // Skip if platform not available
        else => return err,
    };
    defer clipboard.deinit();
    
    // Test basic write/read cycle
    const test_data = "Hello, clipboard!";
    try clipboard.write(test_data, .text);
    
    var read_data = clipboard.read(.text) catch |err| switch (err) {
        ClipboardError.NoData => return, // Skip if no clipboard data
        else => return err,
    };
    defer read_data.deinit();
    
    const text = try read_data.asText();
    try std.testing.expectEqualStrings(test_data, text);
}

