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


fn getBackendModule() type {
    return switch (builtin.os.tag) {
        .linux => @import("backends/linux.zig"),
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
    
    
    pub fn clear(self: *Clipboard) !void {
        return self.backend.clear();
    }
    
    pub fn processEvents(self: *Clipboard) void {
        return self.backend.processEvents();
    }
};

// Cross-platform clipboard reading with automatic format detection
pub fn readClipboardData(allocator: std.mem.Allocator) !ClipboardData {
    if (@hasDecl(Backend, "getClipboardDataAuto")) {
        return Backend.getClipboardDataAuto(allocator);
    }
    
    // Fallback: try to read text format
    var clip = try Clipboard.init(allocator);
    defer clip.deinit();
    clip.processEvents();
    return clip.read(.text);
}

// Write text to clipboard (cross-platform)
pub fn writeClipboardText(allocator: std.mem.Allocator, text: []const u8) !void {
    var clip = try Clipboard.init(allocator);
    defer clip.deinit();
    try clip.write(text, .text);
}

// Wayland-specific event-based monitoring (fails on X11)
pub fn startWaylandEventMonitoring(allocator: std.mem.Allocator) !WaylandEventMonitor {
    const platform_type = try Backend.detectPlatform();
    if (platform_type != .wayland) {
        return ClipboardError.UnsupportedPlatform;
    }
    
    return WaylandEventMonitor.init(allocator);
}

pub const WaylandEventMonitor = struct {
    wayland_clipboard: @import("backends/wayland.zig").WaylandClipboard,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !WaylandEventMonitor {
        var wayland_clipboard: @import("backends/wayland.zig").WaylandClipboard = undefined;
        try wayland_clipboard.init(allocator);
        
        return WaylandEventMonitor{
            .wayland_clipboard = wayland_clipboard,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *WaylandEventMonitor) void {
        self.wayland_clipboard.deinit();
    }
    
    // Blocks until clipboard changes, returns new clipboard data
    pub fn waitForClipboardChange(self: *WaylandEventMonitor) !ClipboardData {
        // Reset state for new monitoring cycle
        self.wayland_clipboard.offer_received = false;
        self.wayland_clipboard.data_result = null;
        self.wayland_clipboard.data_error = null;
        
        // Block and wait for events
        while (true) {
            self.wayland_clipboard.processEvents();
            
            // Check if we got new clipboard data
            if (self.wayland_clipboard.data_result) |result| {
                // Move ownership to caller
                const owned_result = ClipboardData{
                    .data = result.data,
                    .format = result.format,
                    .allocator = result.allocator,
                };
                // Clear the result to avoid double-free
                self.wayland_clipboard.data_result = null;
                return owned_result;
            }
            
            if (self.wayland_clipboard.data_error) |err| {
                return err;
            }
        }
    }
};


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

