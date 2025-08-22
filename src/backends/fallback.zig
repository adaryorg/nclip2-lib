const std = @import("std");
const clipboard = @import("../clipboard.zig");

pub const PlatformType = enum {
    unsupported,
};

pub fn detectPlatform() PlatformType {
    return .unsupported;
}

pub const ClipboardBackend = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !ClipboardBackend {
        _ = allocator;
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn deinit(self: *ClipboardBackend) void {
        _ = self;
    }
    
    pub fn read(self: *ClipboardBackend, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        _ = self;
        _ = format;
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn write(self: *ClipboardBackend, data: []const u8, format: clipboard.ClipboardFormat) !void {
        _ = self;
        _ = data;
        _ = format;
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn startMonitoring(self: *ClipboardBackend, callback: clipboard.ClipboardChangeCallback) !void {
        _ = self;
        _ = callback;
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn stopMonitoring(self: *ClipboardBackend) void {
        _ = self;
    }
    
    pub fn isAvailable(self: *ClipboardBackend, format: clipboard.ClipboardFormat) bool {
        _ = self;
        _ = format;
        return false;
    }
    
    pub fn getAvailableFormats(self: *ClipboardBackend, allocator: std.mem.Allocator) ![]clipboard.ClipboardFormat {
        _ = self;
        return try allocator.alloc(clipboard.ClipboardFormat, 0);
    }
    
    pub fn clear(self: *ClipboardBackend) !void {
        _ = self;
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn processEvents(self: *ClipboardBackend) void {
        _ = self;
    }
};