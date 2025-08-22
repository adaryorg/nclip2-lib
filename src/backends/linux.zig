const std = @import("std");
const clipboard = @import("../clipboard.zig");

const wayland = @import("wayland.zig");
const x11 = @import("x11.zig");

pub const PlatformType = enum {
    wayland,
    x11,
    unknown,
};

pub fn detectPlatform() !PlatformType {
    if (std.posix.getenv("XDG_SESSION_TYPE")) |session_type| {
        if (std.mem.eql(u8, session_type, "wayland")) {
            return .wayland;
        } else if (std.mem.eql(u8, session_type, "x11")) {
            return .x11;
        } else {
            return clipboard.ClipboardError.UnsupportedPlatform;
        }
    }
    
    return clipboard.ClipboardError.UnsupportedPlatform;
}

pub const ClipboardBackend = struct {
    platform_type: PlatformType,
    wayland_backend: ?*wayland.WaylandClipboard,
    x11_backend: ?*x11.X11Clipboard,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !ClipboardBackend {
        const platform_type = try detectPlatform();
        
        var wayland_backend: ?*wayland.WaylandClipboard = null;
        var x11_backend: ?*x11.X11Clipboard = null;
        
        switch (platform_type) {
            .wayland => {
                const backend_ptr = allocator.create(wayland.WaylandClipboard) catch return clipboard.ClipboardError.OutOfMemory;
                backend_ptr.init(allocator) catch |err| switch (err) {
                    clipboard.ClipboardError.InitializationFailed => {
                        allocator.destroy(backend_ptr);
                        // Fallback to X11 if available
                        if (std.posix.getenv("DISPLAY")) |_| {
                            const x11_ptr = allocator.create(x11.X11Clipboard) catch return clipboard.ClipboardError.OutOfMemory;
                            x11_ptr.* = try x11.X11Clipboard.init(allocator);
                            x11_backend = x11_ptr;
                            wayland_backend = null;
                            return ClipboardBackend{
                                .platform_type = platform_type,
                                .wayland_backend = wayland_backend,
                                .x11_backend = x11_backend,
                                .allocator = allocator,
                            };
                        } else {
                            return err;
                        }
                    },
                    else => {
                        allocator.destroy(backend_ptr);
                        return err;
                    },
                };
                wayland_backend = backend_ptr;
            },
            .x11 => {
                const backend_ptr = allocator.create(x11.X11Clipboard) catch return clipboard.ClipboardError.OutOfMemory;
                backend_ptr.* = try x11.X11Clipboard.init(allocator);
                x11_backend = backend_ptr;
            },
            .unknown => {
                return clipboard.ClipboardError.UnsupportedPlatform;
            },
        }
        
        return ClipboardBackend{
            .platform_type = platform_type,
            .wayland_backend = wayland_backend,
            .x11_backend = x11_backend,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ClipboardBackend) void {
        if (self.wayland_backend) |backend| {
            backend.deinit();
            self.allocator.destroy(backend);
        }
        if (self.x11_backend) |backend| {
            backend.deinit();
            self.allocator.destroy(backend);
        }
    }
    
    pub fn read(self: *ClipboardBackend, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        if (self.wayland_backend) |backend| {
            return backend.read(format);
        }
        if (self.x11_backend) |backend| {
            return backend.read(format);
        }
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn write(self: *ClipboardBackend, data: []const u8, format: clipboard.ClipboardFormat) !void {
        if (self.wayland_backend) |backend| {
            return backend.write(data, format);
        }
        if (self.x11_backend) |backend| {
            return backend.write(data, format);
        }
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn startMonitoring(self: *ClipboardBackend, callback: clipboard.ClipboardChangeCallback) !void {
        if (self.wayland_backend) |backend| {
            return backend.startMonitoring(callback);
        }
        if (self.x11_backend) |backend| {
            return backend.startMonitoring(callback);
        }
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn stopMonitoring(self: *ClipboardBackend) void {
        if (self.wayland_backend) |backend| {
            backend.stopMonitoring();
        }
        if (self.x11_backend) |backend| {
            backend.stopMonitoring();
        }
    }
    
    pub fn isAvailable(self: *ClipboardBackend, format: clipboard.ClipboardFormat) bool {
        if (self.wayland_backend) |backend| {
            return backend.isAvailable(format);
        }
        if (self.x11_backend) |backend| {
            return backend.isAvailable(format);
        }
        return false;
    }
    
    pub fn getAvailableFormats(self: *ClipboardBackend, allocator: std.mem.Allocator) ![]clipboard.ClipboardFormat {
        if (self.wayland_backend) |backend| {
            return backend.getAvailableFormats(allocator);
        }
        if (self.x11_backend) |backend| {
            return backend.getAvailableFormats(allocator);
        }
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn clear(self: *ClipboardBackend) !void {
        if (self.wayland_backend) |backend| {
            return backend.clear();
        }
        if (self.x11_backend) |backend| {
            return backend.clear();
        }
        return clipboard.ClipboardError.UnsupportedPlatform;
    }
    
    pub fn processEvents(self: *ClipboardBackend) void {
        if (self.wayland_backend) |backend| {
            backend.processEvents();
        }
        // X11 doesn't need event processing for polling-based clipboard monitoring
    }
};

// Standalone function for getting available formats with fresh connection
pub fn getAvailableClipboardFormats(allocator: std.mem.Allocator) ![]clipboard.ClipboardFormat {
    return wayland.getAvailableClipboardFormats(allocator);
}

// Single-connection function that gets formats and data with automatic format detection
pub fn getClipboardDataAuto(allocator: std.mem.Allocator) !clipboard.ClipboardData {
    return wayland.getClipboardDataWithAutoFormat(allocator);
}