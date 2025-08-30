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
    
    
    pub fn clear(self: *ClipboardBackend) !void {
        _ = self;
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn processEvents(self: *ClipboardBackend) void {
        _ = self;
    }
};